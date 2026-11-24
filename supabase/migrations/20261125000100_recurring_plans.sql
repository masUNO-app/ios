-- Weekly open plans: suggested hangouts with no host. A job posts each plan once a week as an
-- ordinary game, so the 0.9 app on the App Store shows, joins and chats in them with no update.
--
-- 0.9 needs a host on every game (`game_cards` joins the host's profile, and the app decodes a
-- name, initial and class year), so these games belong to a house account, "masUNO", that nobody
-- can sign in as. The house account isn't a player: it has no rsvps row, so it never takes a spot,
-- never appears in Who's going (so nobody can report or block it) and never gets the chat. A plan
-- starts with 0 going. Its notification switches are all off, so joins don't queue host updates.
--
-- One plan at a time per row: the next week's plan is posted once the current one has ended (or
-- was cancelled). Plans live in private.recurring_plans and are added from the SQL editor
-- (supabase/README.md, "Weekly open plans"), not here, so test databases never get them.

-- 1. A game can have nobody going ---------------------------------------------------------------

-- The host always counted, so the floor was 1. A house plan has no host in the count.
alter table public.games drop constraint games_check;
alter table public.games add constraint games_check check (going_count between 0 and capacity);

-- 2. The house account --------------------------------------------------------------------------

-- Like the demo hosts (20261109000200): an Auth user with no password and an undeliverable
-- address, inserted directly so the before-user-created hook doesn't run. Its own table, so the
-- job and reports can tell house games apart.
create table private.house_accounts (
    user_id uuid primary key references public.profiles(id) on delete cascade
);
revoke all on private.house_accounts from public, anon, authenticated;

with house(id, email) as (values
    ('5e000000-0000-4000-8000-000000000001'::uuid, 'masuno@house.masuno.invalid')
), new_users as (
    insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data,
                            confirmation_token, recovery_token, email_change_token_new, email_change,
                            created_at, updated_at)
    select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email,
           '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, '', '', '', '', now(), now()
    from house
    on conflict (id) do nothing
    returning id
), new_profiles as (
    -- 0.9 shows a host as "First L.", so the last name only gives the initial: "masUNO T."
    -- Everywhere else ("masUNO says", "masUNO knows you're coming") it's just "masUNO".
    insert into public.profiles (id, university_id, first_name, last_name, grad_year, interests, locale,
                                 guidelines_accepted_at)
    select n.id, u.id, 'masUNO', 'Tec', 2026, '{}', 'es', now()
    from new_users n cross join public.universities u
    where u.email_domain = 'tec.mx'
    returning id
), new_prefs as (
    insert into public.notification_prefs (user_id, interest_match, spot_open, reminders, hosting, chat, winback)
    select id, false, false, false, false, false, false from new_profiles
)
insert into private.house_accounts (user_id) select id from new_profiles;

-- 3. Plans and the games posted from them --------------------------------------------------------

create table private.recurring_plans (
    id uuid primary key default gen_random_uuid(),
    university_id uuid not null references public.universities(id),
    host_id uuid not null references private.house_accounts(user_id),
    activity_slug text not null references public.activities(slug),
    title text not null check (char_length(btrim(title)) between 1 and 40),
    -- ISO day of the week, 1 = Monday … 7 = Sunday, at local_time in the campus's time zone.
    weekday smallint not null check (weekday between 1 and 7),
    local_time time not null,
    duration_minutes integer not null check (duration_minutes in (30, 60, 90, 120, 180)),
    capacity integer not null check (capacity between 2 and 22),
    notes text check (char_length(notes) <= 280),
    place_name text not null check (char_length(btrim(place_name)) between 1 and 100),
    place_address text not null check (char_length(btrim(place_address)) between 1 and 180),
    lat double precision not null check (lat between -90 and 90),
    lng double precision not null check (lng between -180 and 180),
    meet_point text check (char_length(meet_point) <= 80),
    active boolean not null default true,
    created_at timestamptz not null default now()
);
revoke all on private.recurring_plans from public, anon, authenticated;

-- Which game each week became. Keyed by start, so a week is never posted twice, and a cancelled
-- week stays here and is skipped. Deleting the game (the cleanup below) deletes the row.
create table private.recurring_plan_games (
    plan_id uuid not null references private.recurring_plans(id) on delete cascade,
    starts_at timestamptz not null,
    game_id uuid not null unique references public.games(id) on delete cascade,
    primary key (plan_id, starts_at)
);
revoke all on private.recurring_plan_games from public, anon, authenticated;

-- The first p_weekday at p_local_time (campus time) strictly after p_after.
create function private.next_recurring_start(p_weekday smallint, p_local_time time, p_timezone text, p_after timestamptz)
returns timestamptz language plpgsql stable set search_path = ''
as $$
declare
    v_today date := (p_after at time zone p_timezone)::date;
    v_day date := v_today + ((p_weekday - extract(isodow from v_today)::integer + 7) % 7);
    v_start timestamptz := (v_day + p_local_time) at time zone p_timezone;
begin
    if v_start <= p_after then
        v_start := ((v_day + 7) + p_local_time) at time zone p_timezone;
    end if;
    return v_start;
end $$;

-- Posts the next week of every active plan that has nothing upcoming, and deletes house games
-- that ended over a day ago with nobody going (people who went keep theirs in Past).
-- Returns the number of games posted.
create function private.post_recurring_plans(p_now timestamptz default now())
returns integer language plpgsql security definer set search_path = ''
as $$
declare
    v_plan record;
    v_start timestamptz;
    v_game uuid;
    v_posted integer := 0;
begin
    -- One run at a time, so a slow run and the next tick can't both post the same week.
    perform pg_advisory_xact_lock(hashtext('private.post_recurring_plans'));

    delete from public.games g
    using private.recurring_plan_games l
    where l.game_id = g.id and g.going_count = 0 and g.ends_at < p_now - interval '1 day';

    for v_plan in
        select p.*, u.timezone
        from private.recurring_plans p
        join public.universities u on u.id = p.university_id
        join public.activities a on a.slug = p.activity_slug and a.active
        where p.active
          and not exists (
              select 1 from private.recurring_plan_games l
              join public.games g on g.id = l.game_id
              where l.plan_id = p.id and g.cancelled_at is null and g.ends_at > p_now
          )
        order by p.created_at
    loop
        v_start := private.next_recurring_start(v_plan.weekday, v_plan.local_time, v_plan.timezone, p_now);
        -- A week that was posted and cancelled (a holiday) isn't posted again: take the one after.
        while exists (select 1 from private.recurring_plan_games where plan_id = v_plan.id and starts_at = v_start) loop
            v_start := private.next_recurring_start(v_plan.weekday, v_plan.local_time, v_plan.timezone, v_start);
        end loop;

        insert into public.games (university_id, host_id, activity_slug, title, starts_at, duration_minutes, ends_at,
                                  capacity, going_count, notes, place_name, place_address, lat, lng, meet_point,
                                  auto_repost)
        values (v_plan.university_id, v_plan.host_id, v_plan.activity_slug, btrim(v_plan.title), v_start,
                v_plan.duration_minutes, v_start + make_interval(mins => v_plan.duration_minutes), v_plan.capacity,
                0, nullif(btrim(v_plan.notes), ''), btrim(v_plan.place_name), btrim(v_plan.place_address),
                v_plan.lat, v_plan.lng, nullif(btrim(v_plan.meet_point), ''), true)
        returning id into v_game;
        insert into private.recurring_plan_games (plan_id, starts_at, game_id) values (v_plan.id, v_start, v_game);
        -- "created" is what tells people with that sport in their interests (interest_match).
        perform private.activity_actor(v_game, 'created', v_plan.host_id);
        v_posted := v_posted + 1;
    end loop;
    return v_posted;
end $$;

-- Skips a week: cancels a house game the way cancel_game does, so everyone going is told. The job
-- then posts the following week. Returns what happened, for the SQL editor.
create function private.cancel_recurring_game(p_game_id uuid)
returns text language plpgsql security definer set search_path = ''
as $$
declare v_game public.games%rowtype;
begin
    select g.* into v_game from public.games g
    join private.recurring_plan_games l on l.game_id = g.id
    where g.id = p_game_id
    for update of g;
    if not found then return 'Not cancelled: not a weekly open plan'; end if;
    if v_game.cancelled_at is not null then return 'Not cancelled: already cancelled'; end if;
    if v_game.ends_at <= now() then return 'Not cancelled: it has ended'; end if;
    update public.games set cancelled_at = now() where id = p_game_id;
    perform private.activity_actor(p_game_id, 'cancelled', v_game.host_id);
    return 'Cancelled ' || v_game.title || ' on ' || to_char(v_game.starts_at, 'YYYY-MM-DD HH24:MI TZ');
end $$;

revoke execute on function private.next_recurring_start(smallint, time, text, timestamptz),
    private.post_recurring_plans(timestamptz), private.cancel_recurring_game(uuid)
    from public, anon, authenticated;

-- Every 15 minutes: the next week appears soon after the current plan ends. Cheap when there's
-- nothing to post. Scheduling by name replaces an older job with the same name.
select cron.schedule('post-recurring-plans', '*/15 * * * *', 'select private.post_recurring_plans()');
