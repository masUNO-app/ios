-- Fixes from the PR #12 review. A new migration rather than an edit to 20261107000000, so a project
-- that already applied it stays in step.

-- Private helpers: nobody but the RLS helpers below is callable by clients.
alter default privileges in schema private revoke execute on functions from public;
revoke execute on all functions in schema private from public, anon, authenticated;
grant usage on schema private to authenticated;
grant execute on function private.blocked_pair(uuid, uuid), private.same_university(uuid, uuid) to authenticated;

-- Server-only entry points: the auth hook and the delete-account cleanup.
revoke execute on function public.before_user_created(jsonb), public.delete_my_account_data(uuid)
    from public, anon, authenticated;
grant execute on function public.before_user_created(jsonb) to supabase_auth_admin;
grant execute on function public.delete_my_account_data(uuid) to service_role;

-- A deleted host takes their games along: game_cards needs a host for every row.
alter table public.games
    drop constraint games_host_id_fkey,
    add constraint games_host_id_fkey foreign key (host_id) references public.profiles(id) on delete cascade;

-- A report outlives its target, so both targets can end up null. report() still requires exactly one.
alter table public.reports
    drop constraint reports_check,
    add constraint reports_at_most_one_target check (num_nonnulls(user_id, game_id) <= 1);

-- Column-level grants: clients only ever see a first name, last initial and class year of others.
alter table public.profiles
    add column last_initial char(1) generated always as (upper(left(last_name, 1))::char(1)) stored;
revoke select on public.profiles from authenticated;
grant select (id, university_id, first_name, last_initial, grad_year) on public.profiles to authenticated;

revoke select on public.universities from anon, authenticated;
grant select (id, name, short_name, email_domain, sso_provider, tenant_id, signup_enabled, is_demo, center_lat, center_lng)
    on public.universities to anon, authenticated;

create or replace view public.game_cards
with (security_invoker = true) as
select g.id, g.host_id, host.first_name as host_first_name, host.last_initial as host_last_initial,
       host.grad_year as host_grad_year, g.activity_slug, g.title, g.starts_at, g.duration_minutes, g.ends_at,
       g.capacity, g.going_count, g.capacity - g.going_count as spots_left, g.notes, g.place_name,
       g.place_address, g.lat, g.lng, g.meet_point, g.material_change_at, g.cancelled_at, g.auto_repost,
       g.reposted_at, g.created_at, coalesce(g.reposted_at, g.created_at) as sort_at,
       mine.role as my_role, mine.joined_at as my_joined_at,
       exists (
           select 1 from public.rsvps other
           where other.event_id = g.id and private.blocked_pair(auth.uid(), other.user_id)
       ) as has_blocked_attendee
from public.games g
join public.profiles host on host.id = g.host_id
left join public.rsvps mine on mine.event_id = g.id and mine.user_id = auth.uid();

create or replace view public.game_attendees
with (security_invoker = true) as
select r.event_id, p.id as user_id, p.first_name, p.last_initial, p.grad_year, r.role, r.joined_at
from public.rsvps r join public.profiles p on p.id = r.user_id
where not private.blocked_pair(auth.uid(), r.user_id);

-- Runs as its owner so it can read your own private columns and a hidden demo campus.
-- The auth.uid() filter is the only access check, so it must stay.
alter view public.my_profile set (security_invoker = false);

-- game_activity moves behind a view that hides actor names in blocked pairs. Same name and
-- columns for the app; RLS on the table still limits rows to the game's members.
alter table public.game_activity set schema private;

create view public.game_activity
with (security_invoker = true) as
select a.id, a.event_id, a.kind,
       case when hidden.is_hidden then null else a.actor_id end as actor_id,
       case when hidden.is_hidden then null else a.actor_first_name end as actor_first_name,
       case when hidden.is_hidden then null else a.actor_last_initial end as actor_last_initial,
       case when hidden.is_hidden then null else a.actor_grad_year end as actor_grad_year,
       a.at
from private.game_activity a
cross join lateral (
    select a.actor_id is not null and private.blocked_pair(auth.uid(), a.actor_id) as is_hidden
) hidden;

revoke all on public.game_activity from anon, authenticated;
grant select on public.game_activity to authenticated;

create or replace function private.activity_actor(p_event_id uuid, p_kind text, p_actor uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
    insert into private.game_activity (event_id, kind, actor_id, actor_first_name, actor_last_initial, actor_grad_year)
    select p_event_id, p_kind, p.id, p.first_name, p.last_initial, p.grad_year
    from public.profiles p where p.id = p_actor;
end $$;

-- Locks a game the caller may act on. Another campus or a blocked host looks like no game at all.
create or replace function private.lock_visible_game(p_id uuid, p_user_id uuid)
returns public.games language plpgsql security definer set search_path = ''
as $$
declare v_game public.games%rowtype;
begin
    select g.* into v_game
    from public.games g
    join public.profiles viewer on viewer.id = p_user_id and viewer.university_id = g.university_id
    where g.id = p_id
    for update of g;
    if not found or private.blocked_pair(p_user_id, v_game.host_id) then
        raise exception 'not_found';
    end if;
    return v_game;
end $$;

create or replace function public.update_game(
    p_id uuid, p_activity_slug text, p_title text, p_starts_at timestamptz, p_duration_minutes integer, p_capacity integer,
    p_notes text, p_place_name text, p_place_address text, p_lat double precision, p_lng double precision,
    p_meet_point text, p_auto_repost boolean
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
begin
    v_game := private.lock_visible_game(p_id, v_id);
    if v_game.host_id <> v_id then raise exception 'not_allowed'; end if;
    if v_game.cancelled_at is not null then raise exception 'cancelled'; end if;
    if v_game.ends_at <= now() then raise exception 'ended'; end if;
    perform private.valid_game_input(p_activity_slug, p_title, p_starts_at, p_duration_minutes, p_capacity, p_notes,
                                     p_place_name, p_place_address, p_lat, p_lng, p_meet_point);
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
        material_change_at = case when v_time_or_place_changed or v_meet_point_changed then now() else material_change_at end,
        reposted_at = case when v_game.going_count = v_game.capacity and p_capacity > v_game.going_count and v_auto_repost
                           then now() else reposted_at end
    where id = p_id;

    if v_meet_point_changed then perform private.activity_actor(p_id, 'meet_point_updated', v_id); end if;
    if v_time_or_place_changed then perform private.activity_actor(p_id, 'time_or_place_changed', v_id); end if;
    return query select * from public.game_cards where id = p_id;
end $$;

create or replace function public.cancel_game(p_id uuid)
returns setof public.game_cards language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active(); v_game public.games%rowtype;
begin
    v_game := private.lock_visible_game(p_id, v_id);
    if v_game.host_id <> v_id then raise exception 'not_allowed'; end if;
    if v_game.ends_at <= now() then raise exception 'ended'; end if;
    if v_game.cancelled_at is null then
        update public.games set cancelled_at = now() where id = p_id;
        perform private.activity_actor(p_id, 'cancelled', v_id);
    end if;
    return query select * from public.game_cards where id = p_id;
end $$;

create or replace function public.join_game(p_id uuid)
returns setof public.game_cards language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active(); v_game public.games%rowtype;
begin
    v_game := private.lock_visible_game(p_id, v_id);
    if exists (select 1 from public.rsvps where event_id = p_id and user_id = v_id) then
        return query select * from public.game_cards where id = p_id;
        return;
    end if;
    if v_game.cancelled_at is not null then raise exception 'cancelled'; end if;
    if v_game.ends_at <= now() then raise exception 'ended'; end if;
    if v_game.going_count >= v_game.capacity then raise exception 'full'; end if;
    if exists (select 1 from public.rsvps r where r.event_id = p_id and private.blocked_pair(v_id, r.user_id)) then
        raise exception 'blocked';
    end if;
    insert into public.rsvps (event_id, user_id, role) values (p_id, v_id, 'player');
    update public.games set going_count = going_count + 1 where id = p_id;
    perform private.activity_actor(p_id, 'joined', v_id);
    return query select * from public.game_cards where id = p_id;
end $$;

create or replace function public.leave_game(p_id uuid)
returns setof public.game_cards language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active(); v_game public.games%rowtype;
begin
    v_game := private.lock_visible_game(p_id, v_id);
    if v_game.host_id = v_id then raise exception 'not_allowed'; end if;
    if v_game.ends_at <= now() then raise exception 'ended'; end if;
    if not exists (select 1 from public.rsvps where event_id = p_id and user_id = v_id) then
        return query select * from public.game_cards where id = p_id;
        return;
    end if;
    delete from public.rsvps where event_id = p_id and user_id = v_id;
    update public.games set
        going_count = going_count - 1,
        reposted_at = case when v_game.going_count = v_game.capacity and cancelled_at is null and auto_repost
                           then now() else reposted_at end
    where id = p_id;
    perform private.activity_actor(p_id, 'left', v_id);
    return query select * from public.game_cards where id = p_id;
end $$;

create or replace function public.report(p_user_id uuid default null, p_game_id uuid default null, p_reason text default null, p_note text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active();
begin
    if (p_user_id is null) = (p_game_id is null)
       or p_reason is null or p_reason not in ('harassment', 'inappropriate', 'spam', 'unsafe', 'other')
       or char_length(coalesce(btrim(p_note), '')) > 500 then
        raise exception 'invalid_input';
    end if;
    if p_user_id is not null and (p_user_id = v_id or not private.same_university(v_id, p_user_id)) then
        raise exception 'invalid_input';
    end if;
    if p_game_id is not null and not exists (
        select 1 from public.games g join public.profiles viewer on viewer.id = v_id and viewer.university_id = g.university_id
        where g.id = p_game_id
    ) then
        raise exception 'invalid_input';
    end if;
    insert into public.reports (reporter_id, user_id, game_id, reason, note)
    values (v_id, p_user_id, p_game_id, p_reason, nullif(btrim(p_note), ''));
end $$;

-- Before User Created hook. Deny by default: an allowlisted address with any provider, or a school
-- address that came through that school's own SSO provider. Returning {} lets the sign-up through.
create or replace function public.before_user_created(event jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
    v_email text := lower(btrim(coalesce(event->'user'->>'email', '')));
    v_provider text := coalesce(event->'user'->'app_metadata'->>'provider', 'email');
begin
    if v_email <> '' and exists (select 1 from public.auth_allowlist where email = v_email) then
        return '{}'::jsonb;
    end if;
    if exists (
        select 1 from public.universities u
        where u.email_domain = split_part(v_email, '@', 2)
          and u.sso_provider = v_provider
          and u.signup_enabled and not u.is_demo
          and (u.student_email_pattern is null or v_email ~ u.student_email_pattern)
    ) then
        return '{}'::jsonb;
    end if;
    return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'email_not_allowed'));
end $$;

-- Called only by the delete-account Edge Function. Hosted games, RSVPs and blocks go with the
-- profile through ON DELETE CASCADE; this frees spots in upcoming games under lock first.
create or replace function public.delete_my_account_data(p_user_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_game public.games%rowtype;
begin
    if p_user_id is null then raise exception 'invalid_input'; end if;
    for v_game in
        select g.* from public.games g join public.rsvps r on r.event_id = g.id
        where r.user_id = p_user_id and r.role = 'player' and g.ends_at > now()
        for update of g
    loop
        delete from public.rsvps where event_id = v_game.id and user_id = p_user_id;
        update public.games set
            going_count = going_count - 1,
            reposted_at = case when going_count = capacity and cancelled_at is null and auto_repost then now() else reposted_at end
        where id = v_game.id;
        insert into private.game_activity (event_id, kind) values (v_game.id, 'left');
    end loop;
    update private.game_activity
    set actor_id = null, actor_first_name = null, actor_last_initial = null, actor_grad_year = null
    where actor_id = p_user_id;
end $$;

-- Functions created above get the default EXECUTE grant again, so repeat the lock-down.
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.blocked_pair(uuid, uuid), private.same_university(uuid, uuid) to authenticated;
revoke execute on function public.before_user_created(jsonb), public.delete_my_account_data(uuid)
    from public, anon, authenticated;
grant execute on function public.before_user_created(jsonb) to supabase_auth_admin;
grant execute on function public.delete_my_account_data(uuid) to service_role;

update public.app_config set value = '"official.masuno.app@gmail.com"' where key = 'support_email';
