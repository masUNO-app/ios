-- Round nights (esports): one plan played in rounds, with a break between them and new groups each
-- round, so everyone plays with as many new people as the night allows. Only for a kind with
-- `activity_kinds.supports_rotation` (20261126000000), which today is esports, and esports reaches
-- 0.10 and later only.
--
-- A game stores its rounds as four columns. `create_game` and `update_game` take them as optional
-- parameters. `game_rotation` hands out the rounds and picks each round's groups when it comes out
-- (the first at the start, the rest as the break before them begins), from whoever is going then.
-- Once picked, a round's groups are kept, so someone joining later never reshuffles it.
--
-- Compatible with 0.9: the new parameters default to null, so its create and update calls resolve
-- to the same functions and make plain games. `game_cards` only gains columns at the end.

-- 1. Games -------------------------------------------------------------------------------------

alter table public.games
    add column rotation_rounds integer check (rotation_rounds in (2, 3, 4, 5)),
    add column rotation_round_minutes integer check (rotation_round_minutes in (30, 45, 60)),
    add column rotation_break_minutes integer check (rotation_break_minutes in (10, 15, 20, 30)),
    add column rotation_group_size integer check (rotation_group_size between 2 and 6),
    add constraint games_rotation_complete
        check (num_nulls(rotation_rounds, rotation_round_minutes, rotation_break_minutes, rotation_group_size) in (0, 4)),
    add constraint games_rotation_two_groups
        check (rotation_group_size is null or capacity >= rotation_group_size * 2);

-- A plain game keeps the five durations; a round night lasts exactly its rounds and breaks.
alter table public.games drop constraint games_duration_minutes_check;
alter table public.games add constraint games_duration_minutes_check check (
    (rotation_rounds is null and duration_minutes in (30, 60, 90, 120, 180))
    or (rotation_rounds is not null and duration_minutes
        = rotation_rounds * rotation_round_minutes + (rotation_rounds - 1) * rotation_break_minutes)
);

-- Each round's groups once picked: a JSON array of groups, each an array of user IDs, by station.
create table private.rotation_rounds (
    event_id uuid not null references public.games(id) on delete cascade,
    round integer not null check (round between 0 and 4),
    groups jsonb not null,
    picked_at timestamptz not null default now(),
    primary key (event_id, round)
);
alter table private.rotation_rounds enable row level security;
revoke all on private.rotation_rounds from public, anon, authenticated;

-- 2. Checking input ----------------------------------------------------------------------------

-- As in 20261126000000, without the duration: `valid_rotation` checks it, since a round night's
-- length isn't one of the five.
create or replace function private.valid_game_input(
    p_activity_slug text, p_title text, p_starts_at timestamptz, p_duration_minutes integer,
    p_capacity integer, p_notes text, p_place_name text, p_place_address text,
    p_lat double precision, p_lng double precision, p_meet_point text
) returns void language plpgsql security definer set search_path = ''
as $$
begin
    perform private.clean_text(p_title, 40, true);
    perform private.clean_text(p_notes, 280);
    perform private.clean_text(p_place_name, 100, true);
    perform private.clean_text(p_place_address, 180, true);
    perform private.clean_text(p_meet_point, 80);
    if not exists (select 1 from public.activities a join public.activity_kinds k on k.slug = a.kind
                   where a.slug = p_activity_slug and a.postable and a.active and k.active)
       or p_capacity not between 2 and 22
       or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
        raise exception 'invalid_input';
    end if;
end $$;

-- The duration and rounds together. No rounds: one of the five durations. Rounds: all four set to
-- allowed values, a kind that supports them, the duration exactly the rounds and breaks, and room
-- for two groups. Raises invalid_input otherwise.
create function private.valid_rotation(
    p_activity_slug text, p_duration_minutes integer, p_capacity integer,
    p_rounds integer, p_round_minutes integer, p_break_minutes integer, p_group_size integer
) returns void language plpgsql stable security definer set search_path = ''
as $$
declare v_count integer := num_nonnulls(p_rounds, p_round_minutes, p_break_minutes, p_group_size);
begin
    if v_count = 0 then
        if p_duration_minutes is null or p_duration_minutes not in (30, 60, 90, 120, 180) then
            raise exception 'invalid_input';
        end if;
        return;
    end if;
    if v_count <> 4
       or p_rounds not in (2, 3, 4, 5)
       or p_round_minutes not in (30, 45, 60)
       or p_break_minutes not in (10, 15, 20, 30)
       or p_group_size not between 2 and 6
       or p_duration_minutes is distinct from p_rounds * p_round_minutes + (p_rounds - 1) * p_break_minutes
       or p_capacity < p_group_size * 2
       or not exists (select 1 from public.activities a join public.activity_kinds k on k.slug = a.kind
                      where a.slug = p_activity_slug and k.supports_rotation) then
        raise exception 'invalid_input';
    end if;
end $$;

-- 3. The card ----------------------------------------------------------------------------------

-- As in 20261119000000, with the rounds at the end (null for a plain game).
create or replace view public.game_cards
with (security_invoker = true) as
select g.id, g.host_id, host.first_name as host_first_name, host.last_initial as host_last_initial,
       host.grad_year as host_grad_year, g.activity_slug, g.title, g.starts_at, g.duration_minutes, g.ends_at,
       g.capacity, g.going_count, g.capacity - g.going_count as spots_left, g.notes, g.place_name,
       g.place_address, g.lat, g.lng, g.meet_point, g.material_change_at, g.cancelled_at, g.auto_repost,
       g.reposted_at, g.created_at, coalesce(g.reposted_at, g.created_at) as sort_at,
       mine.role as my_role, mine.joined_at as my_joined_at,
       private.blocked_someone_going(g.id) as has_blocked_attendee,
       exists (
           select 1 from public.bookmarks b
           where b.event_id = g.id and b.user_id = (select auth.uid())
       ) as is_bookmarked,
       coalesce((
           select b.notify from public.bookmarks b
           where b.event_id = g.id and b.user_id = (select auth.uid())
       ), false) as spot_alert,
       coalesce(mine.chat_muted, false) as my_chat_muted,
       g.rotation_rounds, g.rotation_round_minutes, g.rotation_break_minutes, g.rotation_group_size
from public.games g
join public.profiles host on host.id = g.host_id
left join public.rsvps mine on mine.event_id = g.id and mine.user_id = (select auth.uid());

-- 4. Posting and editing -----------------------------------------------------------------------

-- The same name with more parameters would be a second function, and PostgREST couldn't tell
-- which one a 0.9 call means. So the old ones go, and the new ones default the rounds to null.
drop function public.create_game(text, text, timestamptz, integer, integer, text, text, text,
    double precision, double precision, text, boolean);
drop function public.update_game(uuid, text, text, timestamptz, integer, integer, text, text, text,
    double precision, double precision, text, boolean);

-- As in 20261107000000, plus the rounds. Raises invalid_input for rounds that don't fit (above).
create function public.create_game(
    p_activity_slug text, p_title text, p_starts_at timestamptz, p_duration_minutes integer, p_capacity integer,
    p_notes text, p_place_name text, p_place_address text, p_lat double precision, p_lng double precision,
    p_meet_point text, p_auto_repost boolean,
    p_rotation_rounds integer default null, p_rotation_round_minutes integer default null,
    p_rotation_break_minutes integer default null, p_rotation_group_size integer default null
) returns setof public.game_cards language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active(); v_university uuid; v_game uuid;
begin
    perform private.valid_game_input(p_activity_slug, p_title, p_starts_at, p_duration_minutes, p_capacity, p_notes,
                                     p_place_name, p_place_address, p_lat, p_lng, p_meet_point);
    perform private.valid_rotation(p_activity_slug, p_duration_minutes, p_capacity, p_rotation_rounds,
                                   p_rotation_round_minutes, p_rotation_break_minutes, p_rotation_group_size);
    if p_starts_at <= now() or p_starts_at > now() + interval '7 days' then raise exception 'invalid_time'; end if;
    select university_id into v_university from public.profiles where id = v_id;
    if (select count(*) from public.games where host_id = v_id and cancelled_at is null and ends_at > now()) >= 3 then
        raise exception 'limit_reached';
    end if;
    insert into public.games (university_id, host_id, activity_slug, title, starts_at, duration_minutes, ends_at,
                              capacity, notes, place_name, place_address, lat, lng, meet_point, auto_repost,
                              rotation_rounds, rotation_round_minutes, rotation_break_minutes, rotation_group_size)
    values (v_university, v_id, p_activity_slug, private.clean_text(p_title, 40, true), p_starts_at, p_duration_minutes,
            p_starts_at + make_interval(mins => p_duration_minutes), p_capacity, private.clean_text(p_notes, 280),
            private.clean_text(p_place_name, 100, true), private.clean_text(p_place_address, 180, true), p_lat, p_lng,
            private.clean_text(p_meet_point, 80), coalesce(p_auto_repost, true),
            p_rotation_rounds, p_rotation_round_minutes, p_rotation_break_minutes, p_rotation_group_size)
    returning id into v_game;
    insert into public.rsvps (event_id, user_id, role) values (v_game, v_id, 'host');
    perform private.activity_actor(v_game, 'created', v_id);
    return query select * from public.game_cards where id = v_game;
end $$;

-- As in 20261109000000, plus the rounds. Rounds sent as null make it a plain game. New rounds or a
-- new start time drop the groups picked so far: they're picked again as each round comes out.
create function public.update_game(
    p_id uuid, p_activity_slug text, p_title text, p_starts_at timestamptz, p_duration_minutes integer, p_capacity integer,
    p_notes text, p_place_name text, p_place_address text, p_lat double precision, p_lng double precision,
    p_meet_point text, p_auto_repost boolean,
    p_rotation_rounds integer default null, p_rotation_round_minutes integer default null,
    p_rotation_break_minutes integer default null, p_rotation_group_size integer default null
) returns setof public.game_cards language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_active();
    v_game public.games%rowtype;
    v_auto_repost boolean := coalesce(p_auto_repost, true);
    v_place_name text;
    v_place_address text;
    v_meet_point text;
    v_ends_at timestamptz;
    v_time_or_place_changed boolean;
    v_meet_point_changed boolean;
    v_rounds_changed boolean;
begin
    v_game := private.lock_visible_game(p_id, v_id);
    if v_game.host_id <> v_id then raise exception 'not_allowed'; end if;
    if v_game.cancelled_at is not null then raise exception 'cancelled'; end if;
    if v_game.ends_at <= now() then raise exception 'ended'; end if;
    perform private.valid_game_input(p_activity_slug, p_title, p_starts_at, p_duration_minutes, p_capacity, p_notes,
                                     p_place_name, p_place_address, p_lat, p_lng, p_meet_point);
    perform private.valid_rotation(p_activity_slug, p_duration_minutes, p_capacity, p_rotation_rounds,
                                   p_rotation_round_minutes, p_rotation_break_minutes, p_rotation_group_size);
    if p_capacity < v_game.going_count then raise exception 'capacity_below_going'; end if;
    if p_starts_at is distinct from v_game.starts_at
       and (p_starts_at <= now() or p_starts_at > now() + interval '7 days') then
        raise exception 'invalid_time';
    end if;

    v_place_name := private.clean_text(p_place_name, 100, true);
    v_place_address := private.clean_text(p_place_address, 180, true);
    v_meet_point := private.clean_text(p_meet_point, 80);
    v_ends_at := p_starts_at + make_interval(mins => p_duration_minutes);
    v_time_or_place_changed := p_starts_at is distinct from v_game.starts_at
        or v_ends_at is distinct from v_game.ends_at
        or v_place_name is distinct from v_game.place_name
        or v_place_address is distinct from v_game.place_address
        or p_lat is distinct from v_game.lat
        or p_lng is distinct from v_game.lng;
    v_meet_point_changed := v_meet_point is distinct from v_game.meet_point;
    v_rounds_changed := p_starts_at is distinct from v_game.starts_at
        or (p_rotation_rounds, p_rotation_round_minutes, p_rotation_break_minutes, p_rotation_group_size)
           is distinct from (v_game.rotation_rounds, v_game.rotation_round_minutes,
                             v_game.rotation_break_minutes, v_game.rotation_group_size);

    update public.games set
        activity_slug = p_activity_slug,
        title = private.clean_text(p_title, 40, true),
        starts_at = p_starts_at,
        duration_minutes = p_duration_minutes,
        ends_at = v_ends_at,
        capacity = p_capacity,
        notes = private.clean_text(p_notes, 280),
        place_name = v_place_name,
        place_address = v_place_address,
        lat = p_lat,
        lng = p_lng,
        meet_point = v_meet_point,
        auto_repost = v_auto_repost,
        rotation_rounds = p_rotation_rounds,
        rotation_round_minutes = p_rotation_round_minutes,
        rotation_break_minutes = p_rotation_break_minutes,
        rotation_group_size = p_rotation_group_size,
        material_change_at = case when v_time_or_place_changed or v_meet_point_changed then now() else material_change_at end,
        reposted_at = case when v_game.going_count = v_game.capacity and p_capacity > v_game.going_count and v_auto_repost
                           then now() else reposted_at end
    where id = p_id;
    if v_rounds_changed then delete from private.rotation_rounds where event_id = p_id; end if;

    if v_meet_point_changed then perform private.activity_actor(p_id, 'meet_point_updated', v_id); end if;
    if v_time_or_place_changed then perform private.activity_actor(p_id, 'time_or_place_changed', v_id); end if;
    return query select * from public.game_cards where id = p_id;
end $$;

-- 5. Picking groups ----------------------------------------------------------------------------

-- Splits `p_ids` into groups of about `p_size` (leftovers join groups one each, so a group can have
-- one more), so as few people as possible meet someone they already played with in `p_earlier`.
-- Greedy fill from up to 48 random orders, keeping the one with the fewest repeat pairs; stops at
-- the first with none. The same idea as the app's `RotationPlanner`, which the mocks use.
-- Parameters: everyone playing this round; the group size; earlier rounds' groups, as stored.
-- Returns the groups as a JSON array of arrays of user IDs, at least one group when anyone plays.
create function private.pick_rotation_groups(p_ids uuid[], p_size integer, p_earlier jsonb)
returns jsonb language plpgsql volatile set search_path = ''
as $$
declare
    v_n integer := coalesce(array_length(p_ids, 1), 0);
    v_count integer;
    v_caps integer[];
    v_met text[];
    v_order uuid[];
    v_sizes integer[];
    v_ids uuid[];
    v_groups integer[];
    v_best_ids uuid[];
    v_best_groups integer[];
    v_best_repeats integer;
    v_repeats integer;
    v_person uuid;
    v_pick integer;
    v_pick_known integer;
    v_known integer;
    v_result jsonb := '[]'::jsonb;
begin
    if v_n = 0 then return '[]'::jsonb; end if;
    v_count := greatest(1, v_n / greatest(p_size, 1));
    v_caps := array(select v_n / v_count + case when g <= v_n % v_count then 1 else 0 end
                    from generate_series(1, v_count) g);
    -- Every pair that already played together, as "smaller|larger".
    v_met := array(
        select distinct least(a.value, b.value) || '|' || greatest(a.value, b.value)
        from jsonb_array_elements(coalesce(p_earlier, '[]'::jsonb)) round,
             jsonb_array_elements(round) grp,
             jsonb_array_elements_text(grp) a,
             jsonb_array_elements_text(grp) b
        where a.value < b.value
    );

    for attempt in 1..48 loop
        v_order := array(select x from unnest(p_ids) x order by random());
        v_sizes := array_fill(0, array[v_count]);
        v_ids := '{}';
        v_groups := '{}';
        v_repeats := 0;
        foreach v_person in array v_order loop
            v_pick := null;
            v_pick_known := null;
            for g in 1..v_count loop
                continue when v_sizes[g] >= v_caps[g];
                select count(*) into v_known
                from generate_subscripts(v_ids, 1) i
                where v_groups[i] = g
                  and least(v_person::text, v_ids[i]::text) || '|' || greatest(v_person::text, v_ids[i]::text) = any(v_met);
                -- Fewest already met, then the smallest group, then the first.
                if v_pick is null or v_known < v_pick_known
                   or (v_known = v_pick_known and v_sizes[g] < v_sizes[v_pick]) then
                    v_pick := g;
                    v_pick_known := v_known;
                end if;
            end loop;
            v_repeats := v_repeats + v_pick_known;
            v_ids := v_ids || v_person;
            v_groups := v_groups || v_pick;
            v_sizes[v_pick] := v_sizes[v_pick] + 1;
        end loop;
        if v_best_repeats is null or v_repeats < v_best_repeats then
            v_best_ids := v_ids;
            v_best_groups := v_groups;
            v_best_repeats := v_repeats;
        end if;
        exit when v_repeats = 0;
    end loop;

    for g in 1..v_count loop
        v_result := v_result || jsonb_build_array(coalesce((
            select jsonb_agg(v_best_ids[i] order by i) from generate_subscripts(v_best_ids, 1) i
            where v_best_groups[i] = g), '[]'::jsonb));
    end loop;
    return v_result;
end $$;

-- 6. Reading the rounds ------------------------------------------------------------------------

-- A round night's rounds, picking the groups of any round whose time has come (not for a cancelled
-- game). Groups are kept once picked. Someone who left since drops out of their group, and anyone
-- blocked either way is never shown.
-- Parameters: the game.
-- Returns {"rounds": [{"index", "starts_at", "ends_at", "reveals_at", "groups"}]}, oldest first;
-- `groups` is null until the round comes out, then an array of groups (station 1 first), each an
-- array of {"id", "first_name", "last_initial", "grad_year"}.
-- Raises not_authenticated, suspended, pending_approval, or not_found (no such game, another campus,
-- a blocked host, or not a round night).
create function public.game_rotation(p_game_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_active();
    v_game public.games%rowtype;
    v_step interval;
    v_round_length interval;
    v_picked integer;
    v_earlier jsonb;
    v_roster uuid[];
    v_rounds jsonb := '[]'::jsonb;
    v_groups jsonb;
begin
    -- Locked, so two readers at a reveal pick that round once.
    v_game := private.lock_visible_game(p_game_id, v_id);
    if v_game.rotation_rounds is null then raise exception 'not_found'; end if;
    v_round_length := make_interval(mins => v_game.rotation_round_minutes);
    v_step := make_interval(mins => v_game.rotation_round_minutes + v_game.rotation_break_minutes);

    select count(*) into v_picked from private.rotation_rounds where event_id = p_game_id;
    while v_game.cancelled_at is null and v_picked < v_game.rotation_rounds
          and (case when v_picked = 0 then v_game.starts_at
                    else v_game.starts_at + (v_picked - 1) * v_step + v_round_length end) <= now() loop
        select coalesce(jsonb_agg(r.groups order by r.round), '[]'::jsonb) into v_earlier
        from private.rotation_rounds r where r.event_id = p_game_id;
        v_roster := array(select user_id from public.rsvps where event_id = p_game_id order by joined_at, user_id);
        insert into private.rotation_rounds (event_id, round, groups)
        values (p_game_id, v_picked, private.pick_rotation_groups(v_roster, v_game.rotation_group_size, v_earlier));
        v_picked := v_picked + 1;
    end loop;

    for i in 0..v_game.rotation_rounds - 1 loop
        v_groups := null;
        select (
            select coalesce(jsonb_agg(coalesce((
                select jsonb_agg(jsonb_build_object('id', p.id, 'first_name', p.first_name,
                                                    'last_initial', p.last_initial, 'grad_year', p.grad_year)
                                 order by m.ord)
                from jsonb_array_elements_text(grp.value) with ordinality m(user_id, ord)
                join public.rsvps going on going.event_id = p_game_id and going.user_id = m.user_id::uuid
                join public.profiles p on p.id = going.user_id
                where not private.blocked_pair(v_id, p.id)), '[]'::jsonb) order by grp.ord), '[]'::jsonb)
            from jsonb_array_elements(r.groups) with ordinality grp(value, ord)
        ) into v_groups
        from private.rotation_rounds r where r.event_id = p_game_id and r.round = i;

        v_rounds := v_rounds || jsonb_build_object(
            'index', i,
            'starts_at', v_game.starts_at + i * v_step,
            'ends_at', v_game.starts_at + i * v_step + v_round_length,
            'reveals_at', case when i = 0 then v_game.starts_at
                               else v_game.starts_at + (i - 1) * v_step + v_round_length end,
            'groups', v_groups
        );
    end loop;
    return jsonb_build_object('rounds', v_rounds);
end $$;

-- 7. Access ------------------------------------------------------------------------------------

revoke execute on function private.valid_rotation(text, integer, integer, integer, integer, integer, integer),
    private.pick_rotation_groups(uuid[], integer, jsonb),
    private.valid_game_input(text, text, timestamptz, integer, integer, text, text, text, double precision,
                             double precision, text)
    from public, anon, authenticated;
revoke execute on function
    public.create_game(text, text, timestamptz, integer, integer, text, text, text, double precision,
                       double precision, text, boolean, integer, integer, integer, integer),
    public.update_game(uuid, text, text, timestamptz, integer, integer, text, text, text, double precision,
                       double precision, text, boolean, integer, integer, integer, integer),
    public.game_rotation(uuid)
    from public, anon;
grant execute on function
    public.create_game(text, text, timestamptz, integer, integer, text, text, text, double precision,
                       double precision, text, boolean, integer, integer, integer, integer),
    public.update_game(uuid, text, text, timestamptz, integer, integer, text, text, text, double precision,
                       double precision, text, boolean, integer, integer, integer, integer),
    public.game_rotation(uuid)
    to authenticated;
