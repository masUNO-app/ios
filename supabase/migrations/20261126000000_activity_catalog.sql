-- Server-driven activity catalog (docs: "Server-driven activity catalog", phases 2 and 3). The
-- server decides which kinds of plan exist (sports, esports, later hackathons), how each activity
-- looks (color, court drawing) and which features a kind turns on (round nights), within what the
-- app already ships. Builds from 0.10 read it all through `activity_catalog`, which leaves out
-- anything newer than the calling build. Builds up to 0.9 keep reading `activities` directly, and a
-- row policy shows them only what they can show: today's sports, never esports.
--
-- Compatible with 0.9: `activities` only gains columns (the app's decoder ignores them), the row
-- policy hides rows 0.9 can't draw, and nothing it calls changes shape.

-- 1. Versions ----------------------------------------------------------------------------------

-- Whether app version `p_have` is at least `p_need`, compared as numbers part by part, so 0.10
-- comes after 0.9 and 1, 1.0 and 1.0.0 are equal. False when either isn't a version.
create function private.version_at_least(p_have text, p_need text)
returns boolean language sql immutable set search_path = ''
as $$
    select case
        when p_have !~ '^[0-9]+(\.[0-9]+){0,2}$' or p_need !~ '^[0-9]+(\.[0-9]+){0,2}$' then false
        else (string_to_array(p_have, '.')::int[] || array[0, 0, 0])[1:3]
             >= (string_to_array(p_need, '.')::int[] || array[0, 0, 0])[1:3]
    end
$$;

-- 2. Kinds -------------------------------------------------------------------------------------

-- A kind is a tab in Make a plan, with its own copy and feature switches. `default_art` names one
-- of the app's court drawings (`CourtKind`); `supports_rotation` turns round nights on.
create table public.activity_kinds (
    slug text primary key check (slug ~ '^[a-z0-9_-]{1,32}$'),
    label_en text not null,                 -- the tab: "Sports"
    label_es text not null,
    item_label_en text not null,            -- over the chips: "Sport"
    item_label_es text not null,
    title_placeholder_en text not null,     -- the name field: "e.g. Pickup after class"
    title_placeholder_es text not null,
    gear_en text,                           -- a note suggestion: "I have an extra ball"; null hides it
    gear_es text,
    default_art text not null default 'generic' check (default_art ~ '^[a-z0-9_-]{1,32}$'),
    supports_rotation boolean not null default false,
    min_app_version text not null default '0.5' check (min_app_version ~ '^[0-9]+(\.[0-9]+){0,2}$'),
    sort_order integer not null unique,
    active boolean not null default true
);
alter table public.activity_kinds enable row level security;
create policy "public kinds" on public.activity_kinds for select using (true);
grant select on public.activity_kinds to anon, authenticated;

-- Copy as the app shows it today (Localizable.xcstrings). Esports reaches 0.10 and later only.
insert into public.activity_kinds (slug, label_en, label_es, item_label_en, item_label_es,
    title_placeholder_en, title_placeholder_es, gear_en, gear_es, default_art, supports_rotation,
    min_app_version, sort_order) values
 ('sport', 'Sports', 'Deportes', 'Sport', 'Deporte',
  'e.g. Pickup after class', 'p. ej., Cascarita después de clase',
  'I have an extra ball', 'Tengo un balón extra', 'generic', false, '0.5', 1),
 ('esports', 'Esports', 'Esports', 'Game', 'Juego',
  'e.g. Valorant night at the game room', 'p. ej., Noche de Valorant en la sala de videojuegos',
  'I have a spare headset', 'Tengo audífonos extra', 'screen', true, '0.10', 2);

-- 3. Activities --------------------------------------------------------------------------------

-- `color` is the pin, header and chip fill, with ink on it; `color_dark` only when dark mode needs
-- another. `art` names a court drawing; null uses the kind's. Hex is upper case, as the app writes it.
alter table public.activities
    add column color text check (color ~ '^#[0-9A-F]{6}$'),
    add column color_dark text check (color_dark ~ '^#[0-9A-F]{6}$'),
    add column art text check (art ~ '^[a-z0-9_-]{1,32}$'),
    add column min_app_version text not null default '0.5' check (min_app_version ~ '^[0-9]+(\.[0-9]+){0,2}$'),
    add constraint activities_kind_fkey foreign key (kind) references public.activity_kinds(slug);

-- The asset colorsets, so the server matches what builds draw today (the same in dark mode).
update public.activities a set color = v.color, art = v.art
from (values ('basketball', '#F2853A', 'basketball'), ('tennis', '#C7D93D', 'tennis'),
             ('soccer', '#3DB26F', 'soccer'), ('volleyball', '#A99CF6', 'volleyball'),
             ('padel', '#56BDE8', 'padel')) as v(slug, color, art)
where a.slug = v.slug;

-- Esports titles, for 0.10 and later. Their drawing is the kind's screen.
insert into public.activities (slug, kind, label_en, label_es, emoji, sort_order, color, min_app_version) values
    ('valorant', 'esports', 'Valorant', 'Valorant', '🎯', 100, '#F06F7E', '0.10'),
    ('csgo', 'esports', 'CS:GO', 'CS:GO', '💣', 101, '#E8B33A', '0.10'),
    ('league', 'esports', 'League of Legends', 'League of Legends', '🐉', 102, '#4FC7B8', '0.10');

-- 4. Reading it --------------------------------------------------------------------------------

-- The catalog for one build: kinds and activities that build can show, in order. Inactive rows come
-- too, so a retired sport still has its name and look on old plans. A version that can't be read
-- counts as 0.5, the first release, which sees only what every build sees.
-- Parameters: the calling build's version ("0.10").
-- Returns {"kinds": [...], "activities": [...]}, each row with all its columns.
create function public.activity_catalog(p_app_version text)
returns jsonb language sql stable security definer set search_path = ''
as $$
    with v as (
        select case when p_app_version ~ '^[0-9]+(\.[0-9]+){0,2}$' then p_app_version else '0.5' end as have
    )
    select jsonb_build_object(
        'kinds', coalesce((
            select jsonb_agg(to_jsonb(k) order by k.sort_order)
            from public.activity_kinds k, v
            where private.version_at_least(v.have, k.min_app_version)), '[]'::jsonb),
        'activities', coalesce((
            select jsonb_agg(to_jsonb(a) order by a.sort_order)
            from public.activities a join public.activity_kinds k on k.slug = a.kind, v
            where private.version_at_least(v.have, a.min_app_version)
              and private.version_at_least(v.have, k.min_app_version)), '[]'::jsonb)
    )
$$;
revoke execute on function public.activity_catalog(text) from public;
grant execute on function public.activity_catalog(text) to anon, authenticated;

-- Builds up to 0.9 read `activities` directly. They see only rows (and kinds) a 0.9 build can show.
-- Security-definer functions (profile interests, notifications, create_game) aren't affected.
-- The comparison is `version_at_least('0.9', …)` written out, because signed-out readers (anon)
-- can't use the private schema. Once no 0.9 build is supported (min_supported_version past it),
-- this can go back to `true`.
drop policy "public activities" on public.activities;
create policy "legacy activities" on public.activities for select using (
    (string_to_array(min_app_version, '.')::int[] || array[0, 0, 0])[1:3] <= array[0, 9, 0]
    and exists (select 1 from public.activity_kinds k
                where k.slug = activities.kind
                  and (string_to_array(k.min_app_version, '.')::int[] || array[0, 0, 0])[1:3] <= array[0, 9, 0])
);

-- 5. Posting -----------------------------------------------------------------------------------

-- As in 20261107000000, and the activity's kind must be active too.
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
       or p_duration_minutes not in (30, 60, 90, 120, 180)
       or p_capacity not between 2 and 22
       or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
        raise exception 'invalid_input';
    end if;
end $$;

-- 6. Notifications -----------------------------------------------------------------------------

-- As in 20261123000000, with the activity's color in the context, so a push draws its badge in the
-- catalog's color without an app update (`send-push` forwards it).
create or replace function private.claim_notifications_ordered(p_limit integer)
returns table (
    id bigint,
    user_id uuid,
    kind text,
    event_id uuid,
    payload jsonb,
    collapse_id text,
    expires_at timestamptz,
    tokens jsonb,
    context jsonb
) language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
    v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 100);
    v_row private.notification_outbox%rowtype;
    v_game public.games%rowtype;
    v_host uuid;
    v_actor uuid;
    v_tz text;
    v_local timestamp;
    v_hour integer;
    v_morning timestamp;
    v_wake timestamptz;
    v_level text;
    v_has_game boolean;
    v_day_start timestamptz;
    v_reason text;
    v_tokens jsonb;
    v_context jsonb;
    v_claimed_ids bigint[] := '{}';
begin
    -- #variable_conflict above: result columns share names with the outbox, and SQL uses the column.
    if coalesce((select value from public.app_config where key = 'push_enabled'), 'false'::jsonb) <> 'true'::jsonb then
        return;
    end if;

    for v_row in
        select * from private.notification_outbox
        where sent_at is null and dropped is null and not_before <= now()
          and (locked_at is null or locked_at < now() - interval '10 minutes')
        order by id
        limit v_limit
        for update skip locked
    loop
        begin
            -- Do not wait while holding outbox row locks. A competing worker can
            -- claim a different recipient immediately, but never overtake this one.
            if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended(
                'notification-delivery:' || v_row.user_id::text, 0
            )) then continue; end if;
            if exists (
                select 1 from private.notification_outbox earlier
                where earlier.user_id = v_row.user_id
                  and earlier.sent_at is null and earlier.dropped is null
                  and earlier.id <> v_row.id and not (earlier.id = any(v_claimed_ids))
                  and (
                      earlier.locked_at >= now() - interval '10 minutes'
                      or (earlier.id < v_row.id and (earlier.not_before <= now() or earlier.attempts > 0))
                  )
            ) then continue; end if;
            v_reason := null;
            v_host := null;
            v_context := null;
            v_has_game := false;
            v_actor := nullif(v_row.payload->>'actor_id', '')::uuid;
            if v_row.event_id is not null then
                select * into v_game from public.games where id = v_row.event_id;
                v_has_game := found;
                if v_has_game then v_host := v_game.host_id; end if;
            end if;

            v_tz := coalesce(
                (select u.timezone from public.profiles p
                 join public.universities u on u.id = p.university_id where p.id = v_row.user_id),
                (select u.timezone from public.universities u
                 where v_has_game and u.id = v_game.university_id),
                'UTC'
            );
            v_level := private.notification_level(v_row.kind);

            if v_row.expires_at <= now() then
                v_reason := 'expired';
            elsif v_row.kind = any (coalesce(
                (select array(select jsonb_array_elements_text(value)) from public.app_config where key = 'push_kinds_off'),
                '{}'::text[]
            )) then
                v_reason := 'switch';
            elsif not private.notification_allowed(v_row.user_id, v_row.kind) then
                v_reason := 'pref';
            elsif exists (select 1 from public.profiles p where p.id = v_row.user_id and p.banned_at is not null) then
                v_reason := 'banned';
            elsif v_actor is not null and v_actor = v_row.user_id then
                v_reason := 'actor';
            elsif v_host is not null and private.blocked_pair(v_row.user_id, v_host) then
                v_reason := 'blocked';
            elsif v_actor is not null and v_row.kind not in ('chat_message','host_update')
                  and private.blocked_pair(v_row.user_id, v_actor) then
                v_reason := 'blocked';
            elsif v_row.event_id is not null and not v_has_game then
                v_reason := 'missing';
            elsif v_has_game and v_game.cancelled_at is not null and v_row.kind <> 'game_cancelled' then
                v_reason := 'cancelled';
            elsif v_has_game and v_row.kind in ('chat_message', 'chat_mention') and v_game.ends_at <= now() - interval '24 hours' then
                v_reason := 'ended';
            elsif v_has_game and v_row.kind not in ('chat_message', 'chat_mention', 'signup_approved', 'winback')
                  and v_game.starts_at <= now() then
                v_reason := 'started';
            elsif v_row.kind in ('chat_message', 'chat_mention') and coalesce(
                (select value from public.app_config where key = 'chat_enabled'), 'false'::jsonb
            ) <> 'true'::jsonb then
                v_reason := 'chat_off';
            elsif v_row.kind = 'chat_message' and exists (
                select 1 from public.rsvps r
                where r.event_id = v_row.event_id and r.user_id = v_row.user_id and r.chat_muted
            ) then
                v_reason := 'muted';
            elsif v_row.kind in ('chat_message', 'chat_mention') and exists (
                select 1 from private.chat_reads c
                where c.event_id = v_row.event_id and c.user_id = v_row.user_id
                  and c.last_read_at >= coalesce((v_row.payload->>'message_at')::timestamptz, v_row.created_at)
            ) then
                v_reason := 'read';
            elsif v_has_game and v_row.kind = 'spot_open' and (
                v_game.going_count >= v_game.capacity
                or exists (select 1 from public.rsvps r where r.event_id = v_game.id and r.user_id = v_row.user_id)
            ) then
                v_reason := 'stale';
            elsif v_has_game and v_row.kind = 'interest_match' and v_game.going_count >= v_game.capacity then
                v_reason := 'stale';
            end if;

            -- A mention goes right away, even in quiet hours: the person's own Focus decides.
            if v_reason is null and v_level <> 'time-sensitive' and v_row.kind <> 'chat_mention' then
                v_local := now() at time zone v_tz;
                v_hour := extract(hour from v_local)::int;
                if v_hour >= 22 or v_hour < 8 then
                    v_morning := date_trunc('day', v_local) + interval '8 hours';
                    if v_hour >= 22 then v_morning := v_morning + interval '1 day'; end if;
                    v_wake := v_morning at time zone v_tz;
                    if v_row.expires_at <= v_wake then
                        v_reason := 'expired';
                    else
                        update private.notification_outbox
                        set not_before = v_wake, locked_at = null
                        where id = v_row.id;
                        continue;
                    end if;
                end if;
            end if;

            if v_reason is null then
                v_day_start := date_trunc('day', now() at time zone v_tz) at time zone v_tz;
                -- Each user's claims share a transaction lock. Try instead of waiting while
                -- holding outbox row locks, so overlapping drains cannot deadlock each other.
                if v_row.kind not in ('chat_message', 'chat_mention') and v_level <> 'time-sensitive' and not
                    pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended(
                        'notification-budget:' || v_row.user_id::text, 0
                    )) then
                    continue;
                end if;
                if v_row.kind = 'interest_match' and
                    private.notification_budget_used(v_row.user_id, v_day_start, 'interest_match') >= 2 then
                    v_reason := 'cap';
                elsif v_row.kind = 'winback' and
                    private.notification_budget_used(v_row.user_id, now() - interval '14 days', 'winback') > 0 then
                    v_reason := 'cap';
                elsif v_row.kind = 'winback' and (
                    select count(*) = 3 and bool_and(opened_at is null)
                    from (
                        select opened_at from private.notification_outbox o
                        where o.user_id = v_row.user_id and o.kind = 'winback' and o.sent_at is not null
                        order by o.sent_at desc
                        limit 3
                    ) recent
                ) then
                    v_reason := 'cap';
                elsif v_row.kind not in ('chat_message', 'chat_mention') and v_level <> 'time-sensitive' and
                    private.notification_budget_used(v_row.user_id, v_day_start) >= 6 then
                    v_reason := 'cap';
                end if;
            end if;

            if v_reason is null and v_has_game
               and v_row.kind in ('chat_message','chat_mention','reminder','game_changed','game_cancelled')
               and not exists (select 1 from public.rsvps r
                               where r.event_id = v_row.event_id and r.user_id = v_row.user_id) then
                v_reason := 'not_member';
            end if;

            if v_reason is not null then
                update private.notification_outbox set dropped = v_reason, locked_at = null where id = v_row.id;
                continue;
            end if;

            v_row.payload := private.notification_payload_at_claim(
                v_row.kind,v_row.event_id,v_row.user_id,v_row.created_at,v_row.payload);
            if v_row.payload is null then
                update private.notification_outbox set dropped = 'stale', locked_at = null where id = v_row.id;
                continue;
            end if;

            if v_row.kind in ('chat_message', 'chat_mention') and exists (
                select 1 from private.chat_reads c
                where c.event_id = v_row.event_id and c.user_id = v_row.user_id
                  and c.last_read_at >= coalesce((v_row.payload->>'message_at')::timestamptz,v_row.created_at)
            ) then
                update private.notification_outbox set dropped = 'read', locked_at = null where id = v_row.id;
                continue;
            end if;

            select coalesce(jsonb_agg(jsonb_build_object(
                'token', t.token, 'environment', t.environment, 'locale', t.locale
            )), '[]'::jsonb) into v_tokens
            from private.device_tokens t where t.user_id = v_row.user_id;

            if v_tokens = '[]'::jsonb then
                if v_row.created_at < now() - interval '1 day' then
                    update private.notification_outbox set dropped = 'no_token', locked_at = null where id = v_row.id;
                else
                    update private.notification_outbox
                    set not_before = now() + interval '5 minutes', locked_at = null
                    where id = v_row.id;
                end if;
                continue;
            end if;

            if v_has_game then
                select jsonb_build_object(
                    'title', v_game.title,
                    'sport', v_game.activity_slug,
                    'sport_en', a.label_en,
                    'sport_es', a.label_es,
                    'emoji', a.emoji,
                    'color', a.color,
                    'color_dark', a.color_dark,
                    'starts_at', v_game.starts_at,
                    'place', v_game.place_name,
                    'meet_point', v_game.meet_point,
                    'spots_left', v_game.capacity - v_game.going_count,
                    'capacity', v_game.capacity,
                    'going_count', v_game.going_count,
                    'campus', u.short_name,
                    'timezone', u.timezone,
                    'host_name', private.person_label(v_game.host_id),
                    'lat', v_game.lat,
                    'lng', v_game.lng
                ) into v_context
                from public.activities a, public.universities u
                where a.slug = v_game.activity_slug and u.id = v_game.university_id;
            elsif v_row.kind = 'winback' then
                v_context := v_row.payload;
            end if;

            -- This snapshot already includes earlier merges. Only an enqueue after this
            -- claim may arm resend again. clock_timestamp also identifies successive leases.
            update private.notification_outbox
            set locked_at = clock_timestamp(), resend = false where id = v_row.id;

            v_claimed_ids := array_append(v_claimed_ids, v_row.id);
            id := v_row.id;
            user_id := v_row.user_id;
            kind := v_row.kind;
            event_id := v_row.event_id;
            payload := v_row.payload;
            collapse_id := v_row.collapse_id;
            expires_at := v_row.expires_at;
            tokens := v_tokens;
            context := v_context;
            return next;
        exception when others then
            raise warning 'claim failed for notification %: %', v_row.id, sqlerrm;
            update private.notification_outbox
            set locked_at = null, error = left(sqlerrm, 500)
            where id = v_row.id;
        end;
    end loop;
end $$;

-- Replacing a function keeps its grants; repeat the earlier lock-down anyway. The version helper is
-- new, so it starts with the default grant to everyone: take it away (activity_catalog runs as owner).
revoke execute on function private.claim_notifications_ordered(integer), private.valid_game_input(text, text,
    timestamptz, integer, integer, text, text, text, double precision, double precision, text)
    from public, anon, authenticated, service_role;
revoke execute on function private.version_at_least(text, text) from public, anon, authenticated;
