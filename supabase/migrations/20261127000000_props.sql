-- Props after every game (1.0): after a plan ends, people give each other props (Good sport, On
-- time, Team player, Made it fun) — never ratings, never anything about skill. On a round night,
-- props are given after each round, to that round's group only.
--
-- Rules:
-- - Only to people you played with: everyone going, or on a round night your group that round.
-- - The window opens when the plan (or the round) ends and closes 24 hours later. Not for a
--   cancelled plan. Never to yourself, and never between people blocked either way.
-- - Anonymous to the receiver: counts of different people, never who.
-- - Counts are of different people, so one friend can't farm anyone.
-- - The monthly campus leaderboard lists only people who opted in. Anyone can see their own rank.
-- - Who's going shows someone's top prop once props come from at least 3 different people.
--
-- Additive: new tables and RPCs only, so 0.9 builds don't change. `app_config.props_enabled` is a
-- switch; off, `give_props` answers props_disabled and the reads come back empty.

insert into public.app_config (key, value) values ('props_enabled', 'true') on conflict (key) do nothing;

-- 1. Data --------------------------------------------------------------------------------------

-- One row per prop given. `round` is -1 for a whole plan and 0–4 for a round night's round, so it
-- can be part of the key. Private: clients only see counts through the RPCs below.
create table private.props (
    giver_id uuid not null references public.profiles(id) on delete cascade,
    receiver_id uuid not null references public.profiles(id) on delete cascade,
    event_id uuid not null references public.games(id) on delete cascade,
    round integer not null default -1 check (round between -1 and 4),
    prop text not null check (prop in ('good_sport', 'on_time', 'team_player', 'made_it_fun')),
    created_at timestamptz not null default now(),
    primary key (giver_id, receiver_id, event_id, round, prop),
    check (giver_id <> receiver_id)
);
create index props_receiver_idx on private.props (receiver_id, created_at);
create index props_event_idx on private.props (event_id, round);
alter table private.props enable row level security;
revoke all on private.props from public, anon, authenticated;

-- Shown on the monthly campus leaderboard. Off until the person turns it on (onboarding or Settings).
alter table public.profiles add column props_leaderboard_opt_in boolean not null default false;

-- 2. Who you can give props to -----------------------------------------------------------------

create function private.props_enabled()
returns boolean language sql stable security definer set search_path = ''
as $$
    select coalesce((select value from public.app_config where key = 'props_enabled'), 'false'::jsonb) = 'true'::jsonb
$$;

-- When the props window for a plan (round -1) or a round night's round opens. Null when there's
-- nothing to give props for: a cancelled plan, a round night asked without a round (or the reverse),
-- or a round that doesn't exist.
create function private.props_window_opens(p_game public.games, p_round integer)
returns timestamptz language sql immutable set search_path = ''
as $$
    select case
        when p_game.cancelled_at is not null then null
        when p_game.rotation_rounds is null then case when p_round = -1 then p_game.ends_at end
        when p_round between 0 and p_game.rotation_rounds - 1 then
            p_game.starts_at
            + make_interval(mins => p_round * (p_game.rotation_round_minutes + p_game.rotation_break_minutes)
                                    + p_game.rotation_round_minutes)
    end
$$;

-- Everyone `p_viewer` played with in a plan (round -1) or one round of a round night, leaving out
-- anyone blocked either way. Empty when the viewer wasn't in it. Doesn't check the time window.
create function private.props_peers(p_viewer uuid, p_game public.games, p_round integer)
returns setof uuid language sql stable security definer set search_path = ''
as $$
    select peer from (
        -- A plan: everyone still going.
        select r.user_id as peer
        from public.rsvps r
        where p_game.rotation_rounds is null and p_round = -1
          and r.event_id = p_game.id
          and exists (select 1 from public.rsvps me where me.event_id = p_game.id and me.user_id = p_viewer)
        union
        -- A round night: the viewer's group that round, as it was picked.
        select m.value::uuid
        from private.rotation_rounds rr,
             jsonb_array_elements(rr.groups) grp,
             jsonb_array_elements_text(grp) m
        where p_game.rotation_rounds is not null
          and rr.event_id = p_game.id and rr.round = p_round
          and grp @> to_jsonb(p_viewer::text)
    ) people
    where peer <> p_viewer
      and exists (select 1 from public.profiles p where p.id = peer)
      and not private.blocked_pair(p_viewer, peer)
$$;

-- What the props sheet shows: whether props are open, until when, and each person with how often
-- you've played together before and the props you already sent them.
-- Parameters: the plan; the round (0 first) on a round night, else null.
-- Returns {"open": bool, "opens_at", "closes_at", "people": [{"id", "first_name", "last_initial",
-- "grad_year", "is_host", "played_before", "sent": ["good_sport", ...]}]}. `open` is false (and
-- `people` empty) outside the window, when props are off, or for someone who wasn't there.
-- Raises not_authenticated, suspended, pending_approval, or not_found (no such plan, another campus,
-- or a blocked host).
create function public.props_to_give(p_game_id uuid, p_round integer default null)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_active();
    v_game public.games%rowtype;
    v_round integer := coalesce(p_round, -1);
    v_opens timestamptz;
    v_open boolean;
begin
    select g.* into v_game
    from public.games g join public.profiles me on me.id = v_id and me.university_id = g.university_id
    where g.id = p_game_id;
    if not found or private.blocked_pair(v_id, v_game.host_id) then raise exception 'not_found'; end if;

    v_opens := private.props_window_opens(v_game, v_round);
    v_open := private.props_enabled() and v_opens is not null
              and now() >= v_opens and now() < v_opens + interval '24 hours';
    return jsonb_build_object(
        'open', v_open,
        'opens_at', v_opens,
        'closes_at', v_opens + interval '24 hours',
        'people', case when not v_open then '[]'::jsonb else coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', p.id, 'first_name', p.first_name, 'last_initial', p.last_initial, 'grad_year', p.grad_year,
                'is_host', p.id = v_game.host_id,
                'played_before', (
                    select count(*) from public.games other
                    join public.rsvps a on a.event_id = other.id and a.user_id = v_id
                    join public.rsvps b on b.event_id = other.id and b.user_id = p.id
                    where other.id <> v_game.id and other.cancelled_at is null and other.ends_at <= now()),
                'sent', coalesce((
                    select jsonb_agg(s.prop order by s.prop) from private.props s
                    where s.giver_id = v_id and s.receiver_id = p.id and s.event_id = v_game.id and s.round = v_round),
                    '[]'::jsonb)
            ) order by p.id = v_game.host_id desc, p.first_name, p.id)
            from public.profiles p
            where p.id in (select private.props_peers(v_id, v_game, v_round))), '[]'::jsonb)
        end
    );
end $$;

-- 3. Giving ------------------------------------------------------------------------------------

-- Sends props for a plan or one round. Each person named gets exactly the props listed, replacing
-- what you sent them before for this plan or round (an empty list takes them all back); people not
-- named are left as they were.
-- Parameters: the plan; the round on a round night, else null; {"<user id>": ["good_sport", ...]}.
-- Returns {"sent": total props you've now sent for this plan or round}.
-- Raises props_disabled, props_closed (outside the window), invalid_input (someone you didn't play
-- with, an unknown prop, or a malformed list), plus require_active's errors and not_found.
create function public.give_props(p_game_id uuid, p_round integer, p_props jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_active();
    v_game public.games%rowtype;
    v_round integer := coalesce(p_round, -1);
    v_opens timestamptz;
    v_receiver text;
    v_list jsonb;
begin
    select g.* into v_game
    from public.games g join public.profiles me on me.id = v_id and me.university_id = g.university_id
    where g.id = p_game_id;
    if not found or private.blocked_pair(v_id, v_game.host_id) then raise exception 'not_found'; end if;
    if not private.props_enabled() then raise exception 'props_disabled'; end if;
    v_opens := private.props_window_opens(v_game, v_round);
    if v_opens is null or now() < v_opens or now() >= v_opens + interval '24 hours' then
        raise exception 'props_closed';
    end if;
    if p_props is null or jsonb_typeof(p_props) <> 'object' then raise exception 'invalid_input'; end if;

    for v_receiver, v_list in select key, value from jsonb_each(p_props) loop
        if v_receiver !~ '^[0-9a-fA-F-]{36}$'
           or v_receiver::uuid not in (select private.props_peers(v_id, v_game, v_round))
           or jsonb_typeof(v_list) <> 'array'
           or exists (select 1 from jsonb_array_elements(v_list) e
                      where jsonb_typeof(e) <> 'string'
                         or e #>> '{}' not in ('good_sport', 'on_time', 'team_player', 'made_it_fun')) then
            raise exception 'invalid_input';
        end if;
        delete from private.props
        where giver_id = v_id and receiver_id = v_receiver::uuid and event_id = p_game_id and round = v_round;
        insert into private.props (giver_id, receiver_id, event_id, round, prop)
        select distinct v_id, v_receiver::uuid, p_game_id, v_round, e
        from jsonb_array_elements_text(v_list) e;
    end loop;

    return jsonb_build_object('sent', (
        select count(*) from private.props
        where giver_id = v_id and event_id = p_game_id and round = v_round));
end $$;

-- 4. Seeing props ------------------------------------------------------------------------------

-- Each person's props, as the number of different people who gave each one, for Who's going.
-- Only people on your campus whom you haven't blocked (either way), and only once their props come
-- from at least 3 different people; anyone else is left out. Up to 50 people a call.
-- Returns a row per person and prop: user_id, prop, people.
create function public.prop_counts(p_user_ids uuid[])
returns table (user_id uuid, prop text, people integer)
language plpgsql stable security definer set search_path = ''
as $$
declare v_id uuid := private.require_active();
begin
    if not private.props_enabled() then return; end if;
    if coalesce(array_length(p_user_ids, 1), 0) > 50 then raise exception 'invalid_input'; end if;
    return query
    select s.receiver_id, s.prop, count(distinct s.giver_id)::integer
    from private.props s
    where s.receiver_id = any(p_user_ids)
      and private.same_university(v_id, s.receiver_id)
      and not private.blocked_pair(v_id, s.receiver_id)
      and (select count(distinct t.giver_id) from private.props t where t.receiver_id = s.receiver_id) >= 3
    group by s.receiver_id, s.prop;
end $$;

-- The props you got for one plan (every round of a round night together), for its recap.
-- Returns {"people": different people who gave you any, "props": {"good_sport": 4, ...}}.
create function public.my_props_for_game(p_game_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_id uuid := private.require_active();
begin
    return jsonb_build_object(
        'people', (select count(distinct giver_id) from private.props where receiver_id = v_id and event_id = p_game_id),
        'props', coalesce((
            select jsonb_object_agg(prop, people) from (
                select prop, count(distinct giver_id) as people from private.props
                where receiver_id = v_id and event_id = p_game_id group by prop) per), '{}'::jsonb)
    );
end $$;

-- 5. The leaderboard ---------------------------------------------------------------------------

-- Your campus's top people for one prop this month: the number of different people who gave it,
-- only on plans at your campus. Lists opted-in people only; `me` is your own standing, opted in or
-- not, ranked as if you were listed.
-- Parameters: the prop; a filter: null for all, an activity kind ("esports") or an activity slug
-- ("soccer").
-- Returns {"month": "2026-11-01", "resets_at", "top": [{"rank", "id", "first_name", "last_initial",
-- "grad_year", "people", "mostly"}], "me": {"opted_in", "rank", "people"}}. `top` has at most 50;
-- `mostly` is the activity slug most of their props came from this month. `me.rank` is null with
-- no props this month.
create function public.props_leaderboard(p_prop text, p_filter text default null)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_active();
    v_campus uuid;
    v_tz text;
    v_month timestamptz;
    v_result jsonb;
begin
    if p_prop is null or p_prop not in ('good_sport', 'on_time', 'team_player', 'made_it_fun') then
        raise exception 'invalid_input';
    end if;
    -- The month as the campus counts it.
    select p.university_id, u.timezone into v_campus, v_tz
    from public.profiles p join public.universities u on u.id = p.university_id where p.id = v_id;
    v_month := date_trunc('month', now() at time zone v_tz) at time zone v_tz;

    with given as (
        select s.receiver_id, s.giver_id, g.activity_slug
        from private.props s
        join public.games g on g.id = s.event_id
        join public.activities a on a.slug = g.activity_slug
        where private.props_enabled()
          and s.prop = p_prop and s.created_at >= v_month
          and g.university_id = v_campus
          and (p_filter is null or a.kind = p_filter or a.slug = p_filter)
    ), totals as (
        select receiver_id, count(distinct giver_id)::integer as people,
               mode() within group (order by activity_slug) as mostly
        from given group by receiver_id
    ), ranked as (
        select t.*, rank() over (order by t.people desc) as rank
        from totals t join public.profiles p on p.id = t.receiver_id
        where (p.props_leaderboard_opt_in or p.id = v_id) and p.banned_at is null
          and not private.blocked_pair(v_id, p.id)
    )
    select jsonb_build_object(
        'month', to_char(v_month at time zone v_tz, 'YYYY-MM-DD'),
        'resets_at', (v_month at time zone v_tz + interval '1 month') at time zone v_tz,
        'top', coalesce((
            -- Ranked among the opted in, so someone not on the list doesn't leave a gap.
            select jsonb_agg(jsonb_build_object('rank', listed.listed_rank, 'id', p.id, 'first_name', p.first_name,
                                                'last_initial', p.last_initial, 'grad_year', p.grad_year,
                                                'people', listed.people, 'mostly', listed.mostly)
                             order by listed.listed_rank, p.first_name, p.id)
            from (select t.*, rank() over (order by t.people desc) as listed_rank from totals t
                  join public.profiles q on q.id = t.receiver_id
                  where q.props_leaderboard_opt_in and q.banned_at is null and not private.blocked_pair(v_id, q.id)) listed
            join public.profiles p on p.id = listed.receiver_id
            where listed.listed_rank <= 50), '[]'::jsonb),
        'me', jsonb_build_object(
            'opted_in', (select props_leaderboard_opt_in from public.profiles where id = v_id),
            'rank', (select rank from ranked where receiver_id = v_id),
            'people', coalesce((select people from totals where receiver_id = v_id), 0))
    ) into v_result;
    return v_result;
end $$;

-- Whether you're on the leaderboard. Returns the setting.
create function public.props_leaderboard_opt_in()
returns boolean language sql stable security definer set search_path = ''
as $$
    select props_leaderboard_opt_in from public.profiles where id = private.require_active()
$$;

-- Turns the leaderboard on or off for you (onboarding and Settings). Returns the new setting.
create function public.set_props_leaderboard(p_on boolean)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active();
begin
    if p_on is null then raise exception 'invalid_input'; end if;
    update public.profiles set props_leaderboard_opt_in = p_on, updated_at = now() where id = v_id;
    return p_on;
end $$;

-- 6. Access ------------------------------------------------------------------------------------

revoke execute on function private.props_enabled(), private.props_window_opens(public.games, integer),
    private.props_peers(uuid, public.games, integer)
    from public, anon, authenticated;
revoke execute on function public.props_to_give(uuid, integer), public.give_props(uuid, integer, jsonb),
    public.prop_counts(uuid[]), public.my_props_for_game(uuid), public.props_leaderboard(text, text),
    public.props_leaderboard_opt_in(), public.set_props_leaderboard(boolean)
    from public, anon;
grant execute on function public.props_to_give(uuid, integer), public.give_props(uuid, integer, jsonb),
    public.prop_counts(uuid[]), public.my_props_for_game(uuid), public.props_leaderboard(text, text),
    public.props_leaderboard_opt_in(), public.set_props_leaderboard(boolean)
    to authenticated;
