-- masUNO initial backend. Apply with: supabase db push
-- This is intentionally the first migration; never edit it after applying to any project.

create extension if not exists pgcrypto;

create table public.universities (
    id uuid primary key default gen_random_uuid(),
    name text not null check (char_length(name) between 1 and 100),
    short_name text not null check (char_length(short_name) between 1 and 30),
    email_domain text not null unique check (email_domain = lower(email_domain)),
    sso_provider text check (sso_provider in ('azure', 'google')),
    tenant_id text,
    signup_enabled boolean not null default true,
    is_demo boolean not null default false,
    student_email_pattern text,
    center_lat double precision not null check (center_lat between -90 and 90),
    center_lng double precision not null check (center_lng between -180 and 180),
    timezone text not null default 'America/Monterrey',
    created_at timestamptz not null default now(),
    check ((is_demo and sso_provider is null) or not is_demo)
);

create table public.activities (
    slug text primary key check (slug ~ '^[a-z0-9_-]{1,32}$'),
    kind text not null default 'sport',
    label_en text not null,
    label_es text not null,
    emoji text not null,
    sort_order integer not null unique,
    postable boolean not null default true,
    interest_selectable boolean not null default true,
    active boolean not null default true
);

create table public.app_config (
    key text primary key,
    value jsonb not null
);

create table public.auth_allowlist (
    email text primary key check (email = lower(email)),
    note text not null default '',
    university_id uuid not null references public.universities(id)
);

create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    university_id uuid not null references public.universities(id),
    first_name text not null,
    last_name text not null,
    grad_year integer not null,
    interests text[] not null default '{}',
    locale text not null default 'en',
    guidelines_accepted_at timestamptz,
    banned_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.games (
    id uuid primary key default gen_random_uuid(),
    university_id uuid not null references public.universities(id),
    host_id uuid not null references public.profiles(id),
    activity_slug text not null references public.activities(slug),
    title text not null,
    starts_at timestamptz not null,
    duration_minutes integer not null,
    ends_at timestamptz not null,
    capacity integer not null check (capacity between 2 and 22),
    going_count integer not null default 1 check (going_count between 1 and capacity),
    notes text,
    place_name text not null,
    place_address text not null,
    lat double precision not null check (lat between -90 and 90),
    lng double precision not null check (lng between -180 and 180),
    meet_point text,
    material_change_at timestamptz,
    cancelled_at timestamptz,
    auto_repost boolean not null default true,
    reposted_at timestamptz,
    created_at timestamptz not null default now(),
    check (duration_minutes in (30, 60, 90, 120, 180)),
    check (ends_at = starts_at + make_interval(mins => duration_minutes))
);

create table public.rsvps (
    event_id uuid not null references public.games(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    role text not null check (role in ('host', 'player')),
    joined_at timestamptz not null default now(),
    primary key (event_id, user_id)
);

create unique index rsvps_one_host_per_game on public.rsvps (event_id) where role = 'host';
create index games_university_starts_idx on public.games (university_id, starts_at);
create index rsvps_user_idx on public.rsvps (user_id, event_id);

create table public.blocks (
    blocker_id uuid not null references public.profiles(id) on delete cascade,
    blocked_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    check (blocker_id <> blocked_id)
);

create table public.reports (
    id uuid primary key default gen_random_uuid(),
    reporter_id uuid references public.profiles(id) on delete set null,
    user_id uuid references public.profiles(id) on delete set null,
    game_id uuid references public.games(id) on delete set null,
    reason text not null check (reason in ('harassment', 'inappropriate', 'spam', 'unsafe', 'other')),
    note text,
    created_at timestamptz not null default now(),
    resolved_at timestamptz,
    check ((user_id is null) <> (game_id is null))
);

create table public.game_activity (
    id uuid primary key default gen_random_uuid(),
    event_id uuid not null references public.games(id) on delete cascade,
    kind text not null check (kind in ('created', 'joined', 'left', 'meet_point_updated', 'time_or_place_changed', 'cancelled')),
    actor_id uuid references public.profiles(id) on delete set null,
    actor_first_name text,
    actor_last_initial char(1),
    actor_grad_year integer,
    at timestamptz not null default now()
);
create index game_activity_event_at_idx on public.game_activity (event_id, at);

-- Helpers are deliberately private; all client writes go through the public RPCs below.
create schema if not exists private;

create or replace function private.require_user()
returns uuid language plpgsql stable security definer set search_path = ''
as $$
declare v_id uuid := auth.uid();
begin
    if v_id is null then raise exception 'not_authenticated'; end if;
    return v_id;
end $$;

create or replace function private.require_active()
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_user();
begin
    if exists (select 1 from public.profiles where id = v_id and banned_at is not null) then
        raise exception 'suspended';
    end if;
    return v_id;
end $$;

create or replace function private.clean_text(p_value text, p_limit integer, p_required boolean default false)
returns text language plpgsql immutable set search_path = ''
as $$
declare v_clean text := nullif(btrim(p_value), '');
begin
    if (p_required and v_clean is null) or char_length(coalesce(v_clean, '')) > p_limit
       or coalesce(v_clean, '') ~* '(https?://|www\.|@everyone|@here)' then
        raise exception 'invalid_text';
    end if;
    return v_clean;
end $$;

create or replace function private.blocked_pair(p_first uuid, p_second uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (
    select 1 from public.blocks
    where (blocker_id = p_first and blocked_id = p_second)
       or (blocker_id = p_second and blocked_id = p_first)
) $$;

create or replace function private.same_university(p_user_id uuid, p_other_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (
    select 1 from public.profiles a join public.profiles b on b.id = p_other_id
    where a.id = p_user_id and a.university_id = b.university_id
) $$;

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
    if not exists (select 1 from public.activities where slug = p_activity_slug and postable and active)
       or p_duration_minutes not in (30, 60, 90, 120, 180)
       or p_capacity not between 2 and 22
       or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
        raise exception 'invalid_input';
    end if;
end $$;

create or replace function private.activity_actor(p_event_id uuid, p_kind text, p_actor uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
    insert into public.game_activity (event_id, kind, actor_id, actor_first_name, actor_last_initial, actor_grad_year)
    select p_event_id, p_kind, p.id, p.first_name, upper(left(p.last_name, 1)), p.grad_year
    from public.profiles p where p.id = p_actor;
end $$;

-- The three reference tables are public only through restrictive RLS policies.
alter table public.universities enable row level security;
alter table public.activities enable row level security;
alter table public.app_config enable row level security;
alter table public.profiles enable row level security;
alter table public.games enable row level security;
alter table public.rsvps enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table public.game_activity enable row level security;
alter table public.auth_allowlist enable row level security;

create policy "public app configuration" on public.app_config for select using (true);
create policy "public activities" on public.activities for select using (true);
create policy "public school lookup" on public.universities for select using (not is_demo);
-- Base table policies only support security-invoker views. No direct client writes are allowed.
create policy "same-campus public profiles" on public.profiles for select using (
    private.same_university(auth.uid(), id) and not private.blocked_pair(auth.uid(), id)
);
create policy "visible games at own campus" on public.games for select using (
    exists (select 1 from public.profiles viewer where viewer.id = auth.uid() and viewer.university_id = games.university_id)
    and not private.blocked_pair(auth.uid(), host_id)
);
create policy "own blocks only" on public.blocks for select using (blocker_id = auth.uid());

create or replace view public.university_lookup
with (security_invoker = true) as
select id, name, short_name, email_domain, sso_provider, tenant_id, signup_enabled, center_lat, center_lng
from public.universities where not is_demo;

create or replace view public.my_profile
with (security_invoker = true) as
select p.id, p.first_name, p.last_name, p.grad_year, p.university_id, u.name as university_name,
       u.short_name as university_short_name, u.email_domain as university_email_domain,
       u.center_lat, u.center_lng, p.interests, p.guidelines_accepted_at, p.banned_at
from public.profiles p join public.universities u on u.id = p.university_id
where p.id = auth.uid();

create or replace view public.game_cards
with (security_invoker = true) as
select g.id, g.host_id, host.first_name as host_first_name, upper(left(host.last_name, 1))::char(1) as host_last_initial,
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
select r.event_id, p.id as user_id, p.first_name, upper(left(p.last_name, 1))::char(1) as last_initial,
       p.grad_year, r.role, r.joined_at
from public.rsvps r join public.profiles p on p.id = r.user_id
where not private.blocked_pair(auth.uid(), r.user_id);

-- game_activity is an append-only table, but its reads are deliberately exposed through its RLS policy.
create policy "game attendees visible" on public.rsvps for select using (
    exists (select 1 from public.games g join public.profiles me on me.university_id = g.university_id
            where g.id = rsvps.event_id and me.id = auth.uid())
);
create policy "activity visible to members" on public.game_activity for select using (
    exists (select 1 from public.rsvps mine where mine.event_id = game_activity.event_id and mine.user_id = auth.uid())
);

create or replace function public.complete_profile(
    p_first_name text, p_last_name text, p_grad_year integer, p_interests text[], p_locale text
) returns setof public.my_profile language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active(); v_email text; v_university uuid;
begin
    perform private.clean_text(p_first_name, 30, true);
    perform private.clean_text(p_last_name, 30, true);
    if p_grad_year not between extract(year from now())::integer - 1 and extract(year from now())::integer + 10
       or coalesce(array_length(p_interests, 1), 0) = 0
       or exists (select 1 from unnest(p_interests) s left join public.activities a on a.slug = s
                  where a.slug is null or not a.interest_selectable or not a.active) then
        raise exception 'invalid_input';
    end if;
    select lower(email) into v_email from auth.users where id = v_id;
    select coalesce((select university_id from public.auth_allowlist where email = v_email),
                    (select id from public.universities where email_domain = split_part(v_email, '@', 2)))
    into v_university;
    if v_university is null then raise exception 'invalid_input'; end if;
    insert into public.profiles (id, university_id, first_name, last_name, grad_year, interests, locale)
    values (v_id, v_university, private.clean_text(p_first_name,30,true), private.clean_text(p_last_name,30,true),
            p_grad_year, p_interests, coalesce(nullif(btrim(p_locale), ''), 'en'))
    on conflict (id) do update set first_name = excluded.first_name, last_name = excluded.last_name,
        grad_year = excluded.grad_year, interests = excluded.interests, locale = excluded.locale, updated_at = now();
    return query select * from public.my_profile;
end $$;

create or replace function public.accept_guidelines()
returns void language plpgsql security definer set search_path = ''
as $$ begin
    update public.profiles set guidelines_accepted_at = coalesce(guidelines_accepted_at, now()), updated_at = now()
    where id = private.require_active();
end $$;

create or replace function public.create_game(
    p_activity_slug text, p_title text, p_starts_at timestamptz, p_duration_minutes integer, p_capacity integer,
    p_notes text, p_place_name text, p_place_address text, p_lat double precision, p_lng double precision,
    p_meet_point text, p_auto_repost boolean
) returns setof public.game_cards language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active(); v_university uuid; v_game uuid;
begin
    perform private.valid_game_input(p_activity_slug,p_title,p_starts_at,p_duration_minutes,p_capacity,p_notes,p_place_name,p_place_address,p_lat,p_lng,p_meet_point);
    if p_starts_at <= now() or p_starts_at > now() + interval '7 days' then raise exception 'invalid_time'; end if;
    select university_id into v_university from public.profiles where id = v_id;
    if (select count(*) from public.games where host_id = v_id and cancelled_at is null and ends_at > now()) >= 3 then
        raise exception 'limit_reached';
    end if;
    insert into public.games (university_id,host_id,activity_slug,title,starts_at,duration_minutes,ends_at,capacity,notes,place_name,place_address,lat,lng,meet_point,auto_repost)
    values (v_university,v_id,p_activity_slug,private.clean_text(p_title,40,true),p_starts_at,p_duration_minutes,
            p_starts_at + make_interval(mins => p_duration_minutes),p_capacity,private.clean_text(p_notes,280),
            private.clean_text(p_place_name,100,true),private.clean_text(p_place_address,180,true),p_lat,p_lng,
            private.clean_text(p_meet_point,80),coalesce(p_auto_repost,true)) returning id into v_game;
    insert into public.rsvps (event_id,user_id,role) values (v_game,v_id,'host');
    perform private.activity_actor(v_game, 'created', v_id);
    return query select * from public.game_cards where id = v_game;
end $$;

create or replace function public.update_game(
    p_id uuid, p_activity_slug text, p_title text, p_starts_at timestamptz, p_duration_minutes integer, p_capacity integer,
    p_notes text, p_place_name text, p_place_address text, p_lat double precision, p_lng double precision,
    p_meet_point text, p_auto_repost boolean
) returns setof public.game_cards language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active(); v_game public.games%rowtype; v_changed boolean; v_meet_changed boolean;
begin
    select * into v_game from public.games where id = p_id for update;
    if not found or private.blocked_pair(v_id, v_game.host_id) then raise exception 'not_found'; end if;
    if v_game.host_id <> v_id then raise exception 'not_allowed'; end if;
    if v_game.cancelled_at is not null then raise exception 'cancelled'; end if;
    if v_game.ends_at <= now() then raise exception 'ended'; end if;
    perform private.valid_game_input(p_activity_slug,p_title,p_starts_at,p_duration_minutes,p_capacity,p_notes,p_place_name,p_place_address,p_lat,p_lng,p_meet_point);
    if p_capacity < v_game.going_count then raise exception 'capacity_below_going'; end if;
    if p_starts_at is distinct from v_game.starts_at and (p_starts_at <= now() or p_starts_at > now() + interval '7 days') then raise exception 'invalid_time'; end if;
    v_changed := p_starts_at is distinct from v_game.starts_at or p_place_name is distinct from v_game.place_name
        or p_place_address is distinct from v_game.place_address or p_lat is distinct from v_game.lat or p_lng is distinct from v_game.lng;
    v_meet_changed := nullif(btrim(p_meet_point),'') is distinct from v_game.meet_point;
    update public.games set activity_slug=p_activity_slug,title=private.clean_text(p_title,40,true),starts_at=p_starts_at,
      duration_minutes=p_duration_minutes,ends_at=p_starts_at + make_interval(mins => p_duration_minutes),capacity=p_capacity,
      notes=private.clean_text(p_notes,280),place_name=private.clean_text(p_place_name,100,true),
      place_address=private.clean_text(p_place_address,180,true),lat=p_lat,lng=p_lng,meet_point=private.clean_text(p_meet_point,80),
      auto_repost=coalesce(p_auto_repost,true),material_change_at=case when v_changed or v_meet_changed then now() else material_change_at end,
      reposted_at=case when v_game.going_count = v_game.capacity and p_capacity > v_game.going_count and coalesce(p_auto_repost,true) then now() else reposted_at end
      where id=p_id;
    if v_meet_changed then perform private.activity_actor(p_id,'meet_point_updated',v_id);
    elsif v_changed then perform private.activity_actor(p_id,'time_or_place_changed',v_id); end if;
    return query select * from public.game_cards where id=p_id;
end $$;

create or replace function public.cancel_game(p_id uuid)
returns setof public.game_cards language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active(); v_game public.games%rowtype;
begin
    select * into v_game from public.games where id=p_id for update;
    if not found or private.blocked_pair(v_id,v_game.host_id) then raise exception 'not_found'; end if;
    if v_game.host_id <> v_id then raise exception 'not_allowed'; end if;
    if v_game.ends_at <= now() then raise exception 'ended'; end if;
    if v_game.cancelled_at is null then
      update public.games set cancelled_at=now() where id=p_id;
      perform private.activity_actor(p_id,'cancelled',v_id);
    end if;
    return query select * from public.game_cards where id=p_id;
end $$;

create or replace function public.join_game(p_id uuid)
returns setof public.game_cards language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active(); v_game public.games%rowtype;
begin
    select * into v_game from public.games where id=p_id for update;
    if not found or private.blocked_pair(v_id,v_game.host_id) then raise exception 'not_found'; end if;
    if exists (select 1 from public.rsvps where event_id=p_id and user_id=v_id) then return query select * from public.game_cards where id=p_id; end if;
    if v_game.cancelled_at is not null then raise exception 'cancelled'; end if;
    if v_game.ends_at <= now() then raise exception 'ended'; end if;
    if v_game.going_count >= v_game.capacity then raise exception 'full'; end if;
    if exists (select 1 from public.rsvps r where r.event_id=p_id and private.blocked_pair(v_id,r.user_id)) then raise exception 'blocked'; end if;
    insert into public.rsvps(event_id,user_id,role) values(p_id,v_id,'player');
    update public.games set going_count=going_count+1 where id=p_id;
    perform private.activity_actor(p_id,'joined',v_id);
    return query select * from public.game_cards where id=p_id;
end $$;

create or replace function public.leave_game(p_id uuid)
returns setof public.game_cards language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active(); v_game public.games%rowtype; v_was_full boolean;
begin
    select * into v_game from public.games where id=p_id for update;
    if not found or private.blocked_pair(v_id,v_game.host_id) then raise exception 'not_found'; end if;
    if v_game.host_id=v_id then raise exception 'not_allowed'; end if;
    if v_game.ends_at <= now() then raise exception 'ended'; end if;
    if not exists (select 1 from public.rsvps where event_id=p_id and user_id=v_id) then return query select * from public.game_cards where id=p_id; end if;
    v_was_full := v_game.going_count = v_game.capacity;
    delete from public.rsvps where event_id=p_id and user_id=v_id;
    update public.games set going_count=going_count-1, reposted_at=case when v_was_full and cancelled_at is null and auto_repost then now() else reposted_at end where id=p_id;
    perform private.activity_actor(p_id,'left',v_id);
    return query select * from public.game_cards where id=p_id;
end $$;

create or replace function public.report(p_user_id uuid default null, p_game_id uuid default null, p_reason text default null, p_note text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active();
begin
    if (p_user_id is null) = (p_game_id is null) or p_reason not in ('harassment','inappropriate','spam','unsafe','other')
       or char_length(coalesce(btrim(p_note),'')) > 500 then raise exception 'invalid_input'; end if;
    if p_user_id is not null and not exists(select 1 from public.profiles where id=p_user_id) then raise exception 'invalid_input'; end if;
    if p_game_id is not null and not exists(select 1 from public.games where id=p_game_id) then raise exception 'invalid_input'; end if;
    insert into public.reports(reporter_id,user_id,game_id,reason,note) values(v_id,p_user_id,p_game_id,p_reason,nullif(btrim(p_note),''));
end $$;

create or replace function public.block(p_user_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active();
begin
    if p_user_id = v_id or not exists(select 1 from public.profiles where id=p_user_id) then raise exception 'invalid_input'; end if;
    insert into public.blocks(blocker_id,blocked_id) values(v_id,p_user_id) on conflict do nothing;
end $$;

create or replace function public.unblock(p_user_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$ begin delete from public.blocks where blocker_id=private.require_active() and blocked_id=p_user_id; end $$;

create or replace function public.my_blocks()
returns table(user_id uuid, first_name text, last_initial char(1), grad_year integer)
language sql security definer set search_path = ''
as $$ select p.id,p.first_name,upper(left(p.last_name,1))::char(1),p.grad_year
      from public.blocks b join public.profiles p on p.id=b.blocked_id
      where b.blocker_id=private.require_active() order by b.created_at desc $$;

-- Before User Created hook. Configure it in Dashboard → Auth → Hooks with this function.
create or replace function public.before_user_created(event jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_email text := lower(coalesce(event->'user'->>'email','')); v_domain text := split_part(v_email,'@',2);
begin
    if exists(select 1 from public.auth_allowlist where email=v_email) then return jsonb_build_object('decision','continue'); end if;
    if exists(select 1 from public.universities where email_domain=v_domain and signup_enabled and not is_demo
              and (student_email_pattern is null or v_email ~ student_email_pattern)) then
        return jsonb_build_object('decision','continue');
    end if;
    return jsonb_build_object('decision','reject','message','email_not_allowed');
end $$;


-- Called only by the delete-account Edge Function with the service-role key.
-- Lock every affected game before changing counts, then Auth deletion cascades the profile.
create or replace function public.delete_my_account_data(p_user_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_game public.games%rowtype;
begin
    if p_user_id is null then raise exception 'invalid_input'; end if;
    for v_game in select * from public.games where host_id = p_user_id and cancelled_at is null and ends_at > now() for update loop
        update public.games set cancelled_at = now() where id = v_game.id;
        insert into public.game_activity(event_id,kind) values(v_game.id,'cancelled');
    end loop;
    for v_game in select g.* from public.games g join public.rsvps r on r.event_id = g.id
                  where r.user_id = p_user_id and r.role = 'player' and g.ends_at > now() for update of g loop
        delete from public.rsvps where event_id = v_game.id and user_id = p_user_id;
        update public.games set going_count = going_count - 1,
            reposted_at = case when going_count = capacity and cancelled_at is null and auto_repost then now() else reposted_at end
        where id = v_game.id;
        insert into public.game_activity(event_id,kind) values(v_game.id,'left');
    end loop;
    update public.game_activity set actor_id = null, actor_first_name = null, actor_last_initial = null, actor_grad_year = null
    where actor_id = p_user_id;
end $$;

revoke all on all tables in schema public from anon, authenticated;
grant select on public.app_config, public.activities, public.universities, public.university_lookup to anon, authenticated;
grant select on public.my_profile, public.game_cards, public.game_attendees, public.game_activity to authenticated;
grant execute on function public.complete_profile(text,text,integer,text[],text), public.accept_guidelines(),
    public.create_game(text,text,timestamptz,integer,integer,text,text,text,double precision,double precision,text,boolean),
    public.update_game(uuid,text,text,timestamptz,integer,integer,text,text,text,double precision,double precision,text,boolean),
    public.cancel_game(uuid), public.join_game(uuid), public.leave_game(uuid), public.report(uuid,uuid,text,text),
    public.block(uuid), public.unblock(uuid), public.my_blocks() to authenticated;

-- security_invoker views require the caller to have SELECT on their source tables.
-- RLS continues to enforce campus and block boundaries; clients have no write grants.
grant select on public.profiles, public.games, public.rsvps, public.game_activity, public.blocks to authenticated;
grant usage on schema public to anon, authenticated;
grant usage on schema private to postgres, service_role;
grant execute on function public.before_user_created(jsonb) to supabase_auth_admin;

insert into public.activities(slug,kind,label_en,label_es,emoji,sort_order) values
 ('basketball','sport','Basketball','Básquetbol','🏀',1),('tennis','sport','Tennis','Tenis','🎾',2),
 ('soccer','sport','Soccer','Fútbol','⚽️',3),('volleyball','sport','Volleyball','Voleibol','🏐',4),
 ('padel','sport','Padel','Pádel','🏓',5);

insert into public.app_config(key,value) values
 ('min_supported_version','"0.5"'),('support_email','"support@example.com"'),('privacy_url','"https://masuno-app.github.io/privacy"');
