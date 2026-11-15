-- Push notifications (NOTIF.md). One outbox, producers in the same transaction as the write,
-- and private.claim_notifications applying the send-time rules. send-push drains it to APNs.
-- Switched off until app_config.push_enabled is true, the same way chat ships.

create table private.device_tokens (
    token text primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    environment text not null check (environment in ('sandbox', 'production')),
    locale text not null default 'en',
    app_version text not null,
    updated_at timestamptz not null default now()
);
create index device_tokens_user_idx on private.device_tokens (user_id);

create table public.notification_prefs (
    user_id uuid primary key references public.profiles(id) on delete cascade,
    interest_match boolean not null default true,
    spot_open boolean not null default true,
    reminders boolean not null default true,
    hosting boolean not null default true,
    chat boolean not null default true,
    winback boolean not null default false,
    updated_at timestamptz not null default now()
);

-- Synced Saved. notify is "Notify me if a spot opens".
create table public.bookmarks (
    event_id uuid not null references public.games(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    notify boolean not null default false,
    created_at timestamptz not null default now(),
    primary key (event_id, user_id)
);
create index bookmarks_user_idx on public.bookmarks (user_id);

alter table public.rsvps add column chat_muted boolean not null default false;
alter table public.profiles add column last_seen_at timestamptz;

create table private.notification_outbox (
    id bigint generated always as identity primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    kind text not null check (kind in (
        'game_cancelled', 'game_changed', 'reminder', 'host_update', 'game_full',
        'spot_open', 'interest_match', 'chat_message', 'signup_approved', 'winback', 'saved_soon'
    )),
    event_id uuid references public.games(id) on delete cascade,
    payload jsonb not null default '{}',
    merge_key text,
    collapse_id text,
    not_before timestamptz not null default now(),
    expires_at timestamptz not null,
    created_at timestamptz not null default now(),
    locked_at timestamptz,
    sent_at timestamptz,
    opened_at timestamptz,
    dropped text,
    attempts integer not null default 0,
    error text
);
create unique index notification_outbox_pending_merge_idx
    on private.notification_outbox (merge_key)
    where sent_at is null and dropped is null and merge_key is not null;
create index notification_outbox_due_idx
    on private.notification_outbox (not_before)
    where sent_at is null and dropped is null;
create index notification_outbox_caps_idx
    on private.notification_outbox (user_id, kind, sent_at);

-- The APNs provider token, reused until it is 50 minutes old. Apple refuses a new one more often.
create table private.apns_jwt (
    id boolean primary key default true check (id),
    token text not null,
    issued_at timestamptz not null
);

alter table private.device_tokens enable row level security;
alter table private.notification_outbox enable row level security;
alter table private.apns_jwt enable row level security;
alter table public.notification_prefs enable row level security;
alter table public.bookmarks enable row level security;

revoke all on private.device_tokens, private.notification_outbox, private.apns_jwt
    from public, anon, authenticated;
revoke all on public.notification_prefs, public.bookmarks from public, anon, authenticated;
grant select on public.notification_prefs, public.bookmarks to authenticated;

create policy "read own notification prefs" on public.notification_prefs
    for select to authenticated using (user_id = (select auth.uid()));
create policy "read own bookmarks" on public.bookmarks
    for select to authenticated using (user_id = (select auth.uid()));

-- game_cards grows is_bookmarked, spot_alert and my_chat_muted. New columns go at the end:
-- CREATE OR REPLACE VIEW cannot rename or reorder the columns already shipped.
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
           where other.event_id = g.id and private.blocked_pair((select auth.uid()), other.user_id)
       ) as has_blocked_attendee,
       exists (
           select 1 from public.bookmarks b
           where b.event_id = g.id and b.user_id = (select auth.uid())
       ) as is_bookmarked,
       coalesce((
           select b.notify from public.bookmarks b
           where b.event_id = g.id and b.user_id = (select auth.uid())
       ), false) as spot_alert,
       coalesce(mine.chat_muted, false) as my_chat_muted
from public.games g
join public.profiles host on host.id = g.host_id
left join public.rsvps mine on mine.event_id = g.id and mine.user_id = (select auth.uid());

insert into public.app_config (key, value) values
    ('push_enabled', 'false'),
    ('push_kinds_off', '[]')
on conflict (key) do nothing;

-- Whether this person's setting allows the kind. Cancellations, changes and approval are always on.
-- No prefs row uses the column defaults, so win-back stays off until they opt in.
create or replace function private.notification_allowed(p_user uuid, p_kind text)
returns boolean language sql stable security definer set search_path = ''
as $$
    select case p_kind
        when 'game_cancelled' then true
        when 'game_changed' then true
        when 'signup_approved' then true
        else coalesce((
            select case p_kind
                when 'interest_match' then interest_match
                when 'spot_open' then spot_open
                when 'saved_soon' then spot_open
                when 'reminder' then reminders
                when 'host_update' then hosting
                when 'game_full' then hosting
                when 'chat_message' then chat
                when 'winback' then winback
                else false
            end
            from public.notification_prefs where user_id = p_user
        ), p_kind <> 'winback')
    end
$$;

create or replace function private.notification_level(p_kind text)
returns text language sql immutable set search_path = ''
as $$
    select case p_kind
        when 'game_cancelled' then 'time-sensitive'
        when 'reminder' then 'time-sensitive'
        when 'spot_open' then 'time-sensitive'
        when 'interest_match' then 'passive'
        when 'winback' then 'passive'
        when 'saved_soon' then 'passive'
        else 'active'
    end
$$;

-- "First L." from a profile. Null when the account has no profile yet.
create or replace function private.person_label(p_user uuid)
returns text language sql stable security definer set search_path = ''
as $$
    select first_name || ' ' || last_initial || '.'
    from public.profiles where id = p_user
$$;

-- Fold a newer payload into a pending one: another name on a host update, a higher chat count.
create or replace function private.merge_notification_payload(p_kind text, p_old jsonb, p_new jsonb)
returns jsonb language plpgsql immutable set search_path = ''
as $$
declare
    v_names jsonb;
begin
    if p_kind = 'host_update' then
        return jsonb_build_object(
            'actor_id', coalesce(p_new->>'actor_id', p_old->>'actor_id'),
            'joined', coalesce(p_old->'joined', '[]'::jsonb) || coalesce(p_new->'joined', '[]'::jsonb),
            'left', coalesce(p_old->'left', '[]'::jsonb) || coalesce(p_new->'left', '[]'::jsonb),
            'spots_left', coalesce(p_new->'spots_left', p_old->'spots_left'),
            'capacity', coalesce(p_new->'capacity', p_old->'capacity')
        );
    elsif p_kind = 'chat_message' then
        v_names := coalesce(p_old->'names', '[]'::jsonb);
        if coalesce(p_new->>'sender_name', '') <> ''
           and not v_names @> jsonb_build_array(p_new->>'sender_name') then
            v_names := v_names || jsonb_build_array(p_new->>'sender_name');
        end if;
        return jsonb_build_object(
            'actor_id', coalesce(p_new->>'actor_id', p_old->>'actor_id'),
            'sender_id', coalesce(p_new->>'sender_id', p_old->>'sender_id'),
            'sender_name', coalesce(p_new->>'sender_name', p_old->>'sender_name'),
            'sender_initials', coalesce(p_new->>'sender_initials', p_old->>'sender_initials'),
            'names', v_names,
            'body', coalesce(p_old->>'body', p_new->>'body'),
            'count', coalesce((p_old->>'count')::int, 1) + coalesce((p_new->>'count')::int, 1),
            'message_at', coalesce(p_new->>'message_at', p_old->>'message_at'),
            'others', coalesce(p_new->'others', p_old->'others', '[]'::jsonb)
        );
    end if;
    return p_new;
end $$;

-- One row per person. A pending row with the same merge key is updated instead of inserted.
-- p_schedule: debounce resets the wait (an edited game), throttle holds a chat burst to one
-- push, keep leaves the first wait alone (host updates over 5 minutes).
-- p_once: a key that was already sent or dropped is not written again (reminders, win-back).
create or replace function private.enqueue_notification(
    p_user uuid,
    p_kind text,
    p_event uuid,
    p_payload jsonb,
    p_merge_key text,
    p_collapse_id text,
    p_not_before timestamptz,
    p_expires_at timestamptz,
    p_once boolean default false,
    p_schedule text default 'keep'
) returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_id bigint;
begin
    if p_user is null or p_expires_at is null then return; end if;
    if not private.notification_allowed(p_user, p_kind) then return; end if;

    if p_merge_key is not null then
        update private.notification_outbox set
            payload = private.merge_notification_payload(kind, payload, coalesce(p_payload, '{}'::jsonb)),
            collapse_id = coalesce(p_collapse_id, collapse_id),
            not_before = case p_schedule
                when 'debounce' then p_not_before
                when 'throttle' then case
                    when notification_outbox.not_before > now() + interval '15 seconds' then notification_outbox.not_before
                    else p_not_before
                end
                else notification_outbox.not_before
            end,
            expires_at = p_expires_at
        where merge_key = p_merge_key and sent_at is null and dropped is null
        returning id into v_id;
        if v_id is not null then return; end if;
        if p_once and exists (
            select 1 from private.notification_outbox
            where merge_key = p_merge_key and (sent_at is not null or dropped is not null)
        ) then
            return;
        end if;
    end if;

    begin
        insert into private.notification_outbox (
            user_id, kind, event_id, payload, merge_key, collapse_id, not_before, expires_at
        ) values (
            p_user, p_kind, p_event, coalesce(p_payload, '{}'::jsonb), p_merge_key, p_collapse_id,
            coalesce(p_not_before, now()), p_expires_at
        );
    exception when unique_violation then
        update private.notification_outbox set
            payload = private.merge_notification_payload(kind, payload, coalesce(p_payload, '{}'::jsonb)),
            collapse_id = coalesce(p_collapse_id, collapse_id),
            not_before = case p_schedule
                when 'debounce' then p_not_before
                when 'throttle' then case
                    when notification_outbox.not_before > now() + interval '15 seconds' then notification_outbox.not_before
                    else p_not_before
                end
                else notification_outbox.not_before
            end,
            expires_at = p_expires_at
        where merge_key = p_merge_key and sent_at is null and dropped is null;
    end;
end $$;

create or replace function private.notification_names(p_first text, p_initial text)
returns text language sql immutable set search_path = ''
as $$
    select case when p_first is null then null else p_first || ' ' || coalesce(p_initial, '') || '.' end
$$;

-- Up to two other members, so the phone can show the chat as a group.
create or replace function private.chat_others(p_event uuid, p_sender uuid, p_recipient uuid)
returns jsonb language sql stable security definer set search_path = ''
as $$
    select coalesce(jsonb_agg(jsonb_build_object('id', picked.id, 'name', picked.label)), '[]'::jsonb)
    from (
        select p.id, private.notification_names(p.first_name, p.last_initial::text) as label
        from public.rsvps r
        join public.profiles p on p.id = r.user_id
        where r.event_id = p_event and r.user_id <> p_sender and r.user_id <> p_recipient
        order by r.joined_at
        limit 2
    ) picked
$$;

create or replace function private.notify_on_activity()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
    v_game public.games%rowtype;
    v_name text;
    v_member record;
    v_payload jsonb;
begin
    select * into v_game from public.games where id = new.event_id;
    if not found then return new; end if;
    v_name := private.notification_names(new.actor_first_name, new.actor_last_initial::text);

    if new.kind = 'cancelled' then
        update private.notification_outbox set dropped = 'cancelled'
        where event_id = new.event_id and sent_at is null and dropped is null
          and kind in ('reminder', 'game_changed', 'interest_match', 'spot_open', 'saved_soon',
                       'host_update', 'game_full', 'chat_message');
        for v_member in
            select user_id from public.rsvps
            where event_id = new.event_id and role <> 'host' and user_id is distinct from new.actor_id
        loop
            perform private.enqueue_notification(
                v_member.user_id, 'game_cancelled', new.event_id,
                jsonb_build_object('actor_id', new.actor_id),
                'cancelled:' || new.event_id::text || ':' || v_member.user_id::text,
                'game:' || new.event_id::text, now(), v_game.starts_at, true, 'keep'
            );
        end loop;
    elsif new.kind in ('time_or_place_changed', 'meet_point_updated') then
        for v_member in
            select user_id from public.rsvps
            where event_id = new.event_id and user_id is distinct from new.actor_id
        loop
            perform private.enqueue_notification(
                v_member.user_id, 'game_changed', new.event_id,
                jsonb_build_object('actor_id', new.actor_id),
                'changed:' || new.event_id::text || ':' || v_member.user_id::text,
                'game:' || new.event_id::text, now() + interval '2 minutes', v_game.starts_at, false, 'debounce'
            );
        end loop;
    elsif new.kind in ('joined', 'left') and new.actor_id is not null and new.actor_id <> v_game.host_id then
        if new.kind = 'joined' and v_game.going_count >= v_game.capacity then
            update private.notification_outbox set dropped = 'replaced'
            where merge_key = 'host:' || new.event_id::text and sent_at is null and dropped is null;
            perform private.enqueue_notification(
                v_game.host_id, 'game_full', new.event_id,
                jsonb_build_object('actor_id', new.actor_id, 'going', v_game.going_count, 'capacity', v_game.capacity),
                'full:' || new.event_id::text, 'game:' || new.event_id::text,
                now(), v_game.starts_at, false, 'keep'
            );
        else
            v_payload := jsonb_build_object(
                'actor_id', new.actor_id,
                'joined', case when new.kind = 'joined' then jsonb_build_array(v_name) else '[]'::jsonb end,
                'left', case when new.kind = 'left' then jsonb_build_array(v_name) else '[]'::jsonb end,
                'spots_left', v_game.capacity - v_game.going_count,
                'capacity', v_game.capacity
            );
            perform private.enqueue_notification(
                v_game.host_id, 'host_update', new.event_id, v_payload,
                'host:' || new.event_id::text, 'game:' || new.event_id::text,
                now() + interval '5 minutes', v_game.starts_at, false, 'keep'
            );
        end if;
    elsif new.kind = 'created' then
        for v_member in
            select p.id as user_id
            from public.profiles p
            where p.university_id = v_game.university_id
              and p.id <> v_game.host_id
              and p.banned_at is null
              and v_game.activity_slug = any (p.interests)
              and not private.blocked_pair(p.id, v_game.host_id)
        loop
            perform private.enqueue_notification(
                v_member.user_id, 'interest_match', new.event_id,
                jsonb_build_object('actor_id', v_game.host_id),
                'interest:' || new.event_id::text || ':' || v_member.user_id::text,
                'game:' || new.event_id::text, now() + interval '3 minutes', v_game.starts_at, true, 'keep'
            );
        end loop;
    end if;
    return new;
exception when others then
    raise warning 'notification enqueue failed for activity %: %', new.id, sqlerrm;
    return new;
end $$;

create trigger game_activity_notify
after insert on private.game_activity
for each row execute function private.notify_on_activity();

create or replace function private.notify_on_repost()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
    v_member record;
begin
    if new.reposted_at is null or new.reposted_at is not distinct from old.reposted_at then
        return new;
    end if;
    for v_member in
        select b.user_id
        from public.bookmarks b
        where b.event_id = new.id and b.notify
          and not exists (
              select 1 from public.rsvps r where r.event_id = new.id and r.user_id = b.user_id
          )
          and not private.blocked_pair(b.user_id, new.host_id)
    loop
        perform private.enqueue_notification(
            v_member.user_id, 'spot_open', new.id,
            jsonb_build_object('actor_id', new.host_id),
            'spot:' || new.id::text || ':' || v_member.user_id::text,
            'game:' || new.id::text, now(), new.starts_at, false, 'keep'
        );
    end loop;
    return new;
exception when others then
    raise warning 'spot_open enqueue failed for game %: %', new.id, sqlerrm;
    return new;
end $$;

create trigger games_spot_open_notify
after update on public.games
for each row execute function private.notify_on_repost();

create or replace function private.notify_on_chat()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
    v_game public.games%rowtype;
    v_sender public.profiles%rowtype;
    v_member record;
    v_key text;
    v_sent timestamptz;
    v_not_before timestamptz;
    v_name text;
    v_initials text;
begin
    if coalesce((select value from public.app_config where key = 'chat_enabled'), 'false'::jsonb) <> 'true'::jsonb then
        return new;
    end if;
    select * into v_game from public.games where id = new.event_id;
    select * into v_sender from public.profiles where id = new.sender_id;
    if not found then return new; end if;
    v_name := private.notification_names(v_sender.first_name, v_sender.last_initial::text);
    v_initials := upper(left(v_sender.first_name, 1) || coalesce(v_sender.last_initial::text, ''));

    for v_member in
        select r.user_id
        from public.rsvps r
        where r.event_id = new.event_id
          and r.user_id <> new.sender_id
          and not r.chat_muted
          and not private.blocked_pair(r.user_id, new.sender_id)
    loop
        v_key := 'chat:' || new.event_id::text || ':' || v_member.user_id::text;
        select max(sent_at) into v_sent
        from private.notification_outbox
        where merge_key = v_key and sent_at > now() - interval '2 minutes';
        if v_sent is not null then
            v_not_before := v_sent + interval '2 minutes';
        elsif exists (
            select 1 from private.notification_outbox
            where merge_key = v_key and sent_at is null and dropped is null
        ) then
            v_not_before := now() + interval '2 minutes';
        else
            v_not_before := now();
        end if;
        perform private.enqueue_notification(
            v_member.user_id, 'chat_message', new.event_id,
            jsonb_build_object(
                'actor_id', new.sender_id,
                'sender_id', new.sender_id,
                'sender_name', v_name,
                'sender_initials', v_initials,
                'names', jsonb_build_array(v_name),
                'body', left(new.body, 1000),
                'count', 1,
                'message_at', new.created_at,
                'others', private.chat_others(new.event_id, new.sender_id, v_member.user_id)
            ),
            v_key, 'chat:' || new.event_id::text, v_not_before, now() + interval '24 hours', false, 'throttle'
        );
    end loop;
    perform private.drain_if_due();
    return new;
exception when others then
    raise warning 'chat notification enqueue failed for %: %', new.id, sqlerrm;
    return new;
end $$;

create trigger chat_messages_notify
after insert on private.chat_messages
for each row execute function private.notify_on_chat();

-- Reminders (25–35 min out) and saved games that still have room (about 2 h out).
create or replace function private.enqueue_scheduled_notifications()
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_game public.games%rowtype;
    v_member record;
begin
    for v_game in
        select * from public.games
        where cancelled_at is null
          and starts_at > now() + interval '25 minutes'
          and starts_at <= now() + interval '35 minutes'
    loop
        for v_member in select user_id from public.rsvps where event_id = v_game.id loop
            perform private.enqueue_notification(
                v_member.user_id, 'reminder', v_game.id,
                jsonb_build_object('starts_at', v_game.starts_at),
                'reminder:' || v_game.id::text || ':' || v_game.starts_at::text || ':' || v_member.user_id::text,
                'game:' || v_game.id::text, now(), v_game.starts_at, true, 'keep'
            );
        end loop;
    end loop;

    for v_game in
        select * from public.games
        where cancelled_at is null
          and going_count < capacity
          and starts_at > now() + interval '115 minutes'
          and starts_at <= now() + interval '125 minutes'
    loop
        for v_member in
            select b.user_id
            from public.bookmarks b
            where b.event_id = v_game.id
              and not exists (
                  select 1 from public.rsvps r where r.event_id = v_game.id and r.user_id = b.user_id
              )
        loop
            perform private.enqueue_notification(
                v_member.user_id, 'saved_soon', v_game.id,
                jsonb_build_object('spots_left', v_game.capacity - v_game.going_count),
                'saved:' || v_game.id::text || ':' || v_game.starts_at::text || ':' || v_member.user_id::text,
                'game:' || v_game.id::text, now(), v_game.starts_at, true, 'keep'
            );
        end loop;
    end loop;
exception when others then
    raise warning 'scheduled notifications failed: %', sqlerrm;
end $$;

-- Opted-in people who haven't opened the app in 10 days, when their campus has games.
-- p_now lets a test pin a Tuesday at 17:00; the cron calls it with the default.
create or replace function private.enqueue_winback(p_now timestamptz default now())
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_campus public.universities%rowtype;
    v_local timestamp;
    v_person record;
    v_games integer;
    v_sport_slug text;
    v_sport_en text;
    v_sport_es text;
    v_sport_games integer;
begin
    for v_campus in select * from public.universities loop
        v_local := p_now at time zone v_campus.timezone;
        if extract(hour from v_local)::int <> 17 or extract(dow from v_local)::int not between 2 and 4 then
            continue;
        end if;
        for v_person in
            select p.id, p.interests
            from public.profiles p
            join public.notification_prefs n on n.user_id = p.id and n.winback
            where p.university_id = v_campus.id
              and p.banned_at is null
              and p.last_seen_at < p_now - interval '10 days'
        loop
            select count(*)::int into v_games
            from public.games g
            where g.university_id = v_campus.id
              and g.cancelled_at is null
              and g.starts_at > p_now
              and g.starts_at < p_now + interval '3 days'
              and g.going_count < g.capacity
              and (cardinality(v_person.interests) = 0 or g.activity_slug = any (v_person.interests));
            if v_games < 2 then continue; end if;

            select a.slug, a.label_en, a.label_es, count(*)::int
            into v_sport_slug, v_sport_en, v_sport_es, v_sport_games
            from public.games g
            join public.activities a on a.slug = g.activity_slug
            where g.university_id = v_campus.id
              and g.cancelled_at is null
              and g.starts_at > p_now
              and g.starts_at < p_now + interval '3 days'
              and g.going_count < g.capacity
              and (cardinality(v_person.interests) = 0 or g.activity_slug = any (v_person.interests))
            group by a.slug, a.label_en, a.label_es
            order by count(*) desc, a.slug
            limit 1;

            perform private.enqueue_notification(
                v_person.id, 'winback', null,
                jsonb_build_object(
                    'games', v_games, 'campus', v_campus.short_name, 'timezone', v_campus.timezone,
                    'sport', v_sport_slug, 'sport_en', v_sport_en, 'sport_es', v_sport_es,
                    'sport_games', v_sport_games
                ),
                'winback:' || v_person.id::text || ':' || to_char(v_local, 'YYYY-MM-DD'),
                null, p_now, p_now + interval '1 day', true, 'keep'
            );
        end loop;
    end loop;
exception when others then
    raise warning 'winback enqueue failed: %', sqlerrm;
end $$;

create or replace function private.purge_notifications()
returns void language plpgsql security definer set search_path = ''
as $$
begin
    delete from private.notification_outbox where created_at < now() - interval '30 days';
    delete from private.device_tokens where updated_at < now() - interval '90 days';
exception when others then
    raise warning 'notification purge failed: %', sqlerrm;
end $$;

-- Called by the edge function with the service role. Locks due rows that pass every send-time
-- rule and returns them with the person's device tokens. Rows that fail are marked dropped.
create or replace function private.claim_notifications(p_limit integer)
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
begin
    if coalesce((select value from public.app_config where key = 'push_enabled'), 'false'::jsonb) <> 'true'::jsonb then
        return;
    end if;

    for v_row in
        select * from private.notification_outbox
        where sent_at is null and dropped is null and not_before <= now()
          and (locked_at is null or locked_at < now() - interval '2 minutes')
        order by not_before, id
        limit v_limit
        for update skip locked
    loop
        begin
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
            elsif v_actor is not null and private.blocked_pair(v_row.user_id, v_actor) then
                v_reason := 'blocked';
            elsif v_row.event_id is not null and not v_has_game then
                v_reason := 'missing';
            elsif v_has_game and v_game.cancelled_at is not null and v_row.kind <> 'game_cancelled' then
                v_reason := 'cancelled';
            elsif v_has_game and v_row.kind = 'chat_message' and v_game.ends_at <= now() - interval '24 hours' then
                v_reason := 'ended';
            elsif v_has_game and v_row.kind not in ('chat_message', 'signup_approved', 'winback')
                  and v_game.starts_at <= now() then
                v_reason := 'started';
            elsif v_row.kind = 'chat_message' and coalesce(
                (select value from public.app_config where key = 'chat_enabled'), 'false'::jsonb
            ) <> 'true'::jsonb then
                v_reason := 'chat_off';
            elsif v_row.kind = 'chat_message' and exists (
                select 1 from public.rsvps r
                where r.event_id = v_row.event_id and r.user_id = v_row.user_id and r.chat_muted
            ) then
                v_reason := 'muted';
            elsif v_row.kind = 'chat_message' and exists (
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

            if v_reason is null and v_level <> 'time-sensitive' then
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
                if v_row.kind = 'interest_match' and (
                    select count(*) from private.notification_outbox o
                    where o.user_id = v_row.user_id and o.kind = 'interest_match' and o.sent_at >= v_day_start
                ) >= 2 then
                    v_reason := 'cap';
                elsif v_row.kind = 'winback' and exists (
                    select 1 from private.notification_outbox o
                    where o.user_id = v_row.user_id and o.kind = 'winback'
                      and o.sent_at > now() - interval '14 days'
                ) then
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
                elsif v_row.kind <> 'chat_message' and v_level <> 'time-sensitive' and (
                    select count(*) from private.notification_outbox o
                    where o.user_id = v_row.user_id and o.sent_at >= v_day_start
                      and o.kind <> 'chat_message'
                      and private.notification_level(o.kind) <> 'time-sensitive'
                ) >= 6 then
                    v_reason := 'cap';
                end if;
            end if;

            if v_reason is not null then
                update private.notification_outbox set dropped = v_reason, locked_at = null where id = v_row.id;
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

            update private.notification_outbox set locked_at = now() where id = v_row.id;

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

create or replace function public.claim_notifications(p_limit integer default 100)
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
begin
    if coalesce(auth.role(), '') is distinct from 'service_role' then
        raise exception 'not_allowed';
    end if;
    return query select * from private.claim_notifications(p_limit);
end $$;

-- What APNs said. outcome is sent, retry, release (clear the lease) or drop.
-- drop_tokens removes dead device tokens. A sent spot_open clears "Notify me" for that game.
create or replace function private.complete_notifications(p_results jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_item jsonb;
    v_id bigint;
    v_outcome text;
    v_kind text;
    v_user uuid;
    v_event uuid;
begin
    for v_item in select value from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
        v_id := (v_item->>'id')::bigint;
        v_outcome := v_item->>'outcome';
        select kind, user_id, event_id into v_kind, v_user, v_event
        from private.notification_outbox where id = v_id;

        if v_outcome = 'sent' then
            update private.notification_outbox
            set sent_at = now(), locked_at = null, error = null
            where id = v_id and sent_at is null;
            if v_kind = 'spot_open' then
                update public.bookmarks set notify = false
                where user_id = v_user and event_id = v_event;
            end if;
        elsif v_outcome = 'release' then
            update private.notification_outbox set locked_at = null where id = v_id and sent_at is null;
        elsif v_outcome = 'retry' then
            update private.notification_outbox set
                attempts = attempts + 1,
                locked_at = null,
                error = left(v_item->>'error', 500),
                not_before = now() + make_interval(mins => (power(2, attempts + 1))::int),
                dropped = case when attempts + 1 >= 3 then 'error' else dropped end
            where id = v_id and sent_at is null;
        elsif v_outcome = 'drop' then
            update private.notification_outbox set
                dropped = coalesce(nullif(v_item->>'error', ''), 'error'),
                locked_at = null,
                error = left(v_item->>'error', 500)
            where id = v_id and sent_at is null;
        end if;

        if v_item ? 'drop_tokens' then
            delete from private.device_tokens
            where token in (select jsonb_array_elements_text(v_item->'drop_tokens'));
        end if;
    end loop;
end $$;

create or replace function public.complete_notifications(p_results jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
begin
    if coalesce(auth.role(), '') is distinct from 'service_role' then
        raise exception 'not_allowed';
    end if;
    perform private.complete_notifications(p_results);
end $$;

create or replace function private.current_apns_jwt()
returns text language sql stable security definer set search_path = ''
as $$
    select token from private.apns_jwt
    where issued_at > now() - interval '50 minutes'
$$;

create or replace function public.current_apns_jwt()
returns text language plpgsql security definer set search_path = ''
as $$
begin
    if coalesce(auth.role(), '') is distinct from 'service_role' then
        raise exception 'not_allowed';
    end if;
    return private.current_apns_jwt();
end $$;

create or replace function private.store_apns_jwt(p_token text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
    insert into private.apns_jwt (id, token, issued_at) values (true, p_token, now())
    on conflict (id) do update set token = excluded.token, issued_at = excluded.issued_at;
end $$;

create or replace function public.store_apns_jwt(p_token text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
    if coalesce(auth.role(), '') is distinct from 'service_role' then
        raise exception 'not_allowed';
    end if;
    if p_token is null or length(p_token) < 20 then raise exception 'invalid_input'; end if;
    perform private.store_apns_jwt(p_token);
end $$;

-- Posts to send-push only when a row is due. The URL and service-role key live in Vault.
create or replace function private.drain_if_due()
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_url text;
    v_key text;
begin
    if not exists (
        select 1 from private.notification_outbox
        where sent_at is null and dropped is null and not_before <= now()
          and (locked_at is null or locked_at < now() - interval '2 minutes')
    ) then
        return;
    end if;
    select decrypted_secret into v_url from vault.decrypted_secrets where name = 'send_push_url';
    select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
    if v_url is null or v_key is null then
        raise warning 'notifications not drained: Vault secrets send_push_url or service_role_key are missing';
        return;
    end if;
    perform net.http_post(
        url := v_url,
        body := '{}'::jsonb,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_key
        )
    );
exception when others then
    raise warning 'notification drain failed: %', sqlerrm;
end $$;

create or replace function private.approve_signup(p_email text)
returns text language plpgsql security definer set search_path = ''
as $$
declare
    v_email text := lower(btrim(p_email));
    v_user uuid;
begin
    update private.signup_requests set approved_at = now() where email = v_email and approved_at is null;
    if not found then return 'Nothing to approve for ' || v_email; end if;
    select id into v_user from auth.users where lower(email) = v_email;
    if v_user is not null then
        begin
            perform private.enqueue_notification(
                v_user, 'signup_approved', null, '{}'::jsonb,
                'signup:' || v_user::text, null, now(), now() + interval '7 days', true, 'keep'
            );
        exception when others then
            raise warning 'signup_approved not enqueued for %: %', v_email, sqlerrm;
        end;
    end if;
    return 'Approved ' || v_email;
end $$;

-- Client RPCs. register_device is allowed while an account waits for approval.
create or replace function public.register_device(
    p_token text, p_environment text, p_locale text, p_app_version text
) returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_user();
begin
    if p_token is null or char_length(p_token) not between 16 and 400
       or p_environment not in ('sandbox', 'production')
       or nullif(btrim(p_locale), '') is null
       or nullif(btrim(p_app_version), '') is null then
        raise exception 'invalid_input';
    end if;
    insert into private.device_tokens (token, user_id, environment, locale, app_version)
    values (p_token, v_id, p_environment, left(btrim(p_locale), 35), left(btrim(p_app_version), 32))
    on conflict (token) do update set
        user_id = excluded.user_id,
        environment = excluded.environment,
        locale = excluded.locale,
        app_version = excluded.app_version,
        updated_at = now();
    update public.profiles set last_seen_at = now() where id = v_id;
end $$;

create or replace function public.unregister_device(p_token text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_user();
begin
    delete from private.device_tokens where token = p_token and user_id = v_id;
end $$;

create or replace function public.set_notification_prefs(
    p_interest_match boolean, p_spot_open boolean, p_reminders boolean,
    p_hosting boolean, p_chat boolean, p_winback boolean
) returns setof public.notification_prefs
language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_active();
begin
    if p_interest_match is null or p_spot_open is null or p_reminders is null
       or p_hosting is null or p_chat is null or p_winback is null then
        raise exception 'invalid_input';
    end if;
    insert into public.notification_prefs (
        user_id, interest_match, spot_open, reminders, hosting, chat, winback
    ) values (
        v_id, p_interest_match, p_spot_open, p_reminders, p_hosting, p_chat, p_winback
    )
    on conflict (user_id) do update set
        interest_match = excluded.interest_match,
        spot_open = excluded.spot_open,
        reminders = excluded.reminders,
        hosting = excluded.hosting,
        chat = excluded.chat,
        winback = excluded.winback,
        updated_at = now();
    return query select * from public.notification_prefs where user_id = v_id;
end $$;

create or replace function public.toggle_bookmark(p_game_id uuid)
returns setof public.game_cards language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_active();
begin
    perform private.lock_visible_game(p_game_id, v_id);
    if exists (select 1 from public.bookmarks where event_id = p_game_id and user_id = v_id) then
        delete from public.bookmarks where event_id = p_game_id and user_id = v_id;
    else
        insert into public.bookmarks (event_id, user_id) values (p_game_id, v_id);
    end if;
    return query select * from public.game_cards where id = p_game_id;
end $$;

create or replace function public.set_spot_alert(p_game_id uuid, p_on boolean)
returns setof public.game_cards language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_active();
begin
    if p_on is null then raise exception 'invalid_input'; end if;
    perform private.lock_visible_game(p_game_id, v_id);
    if p_on then
        insert into public.bookmarks (event_id, user_id, notify) values (p_game_id, v_id, true)
        on conflict (event_id, user_id) do update set notify = true;
    else
        update public.bookmarks set notify = false where event_id = p_game_id and user_id = v_id;
    end if;
    return query select * from public.game_cards where id = p_game_id;
end $$;

create or replace function public.import_bookmarks(p_ids uuid[], p_alert_ids uuid[])
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_active();
    v_ids uuid[] := coalesce(p_ids, '{}'::uuid[]) || coalesce(p_alert_ids, '{}'::uuid[]);
begin
    insert into public.bookmarks (event_id, user_id, notify)
    select g.id, v_id, g.id = any (coalesce(p_alert_ids, '{}'::uuid[]))
    from public.games g
    join public.profiles viewer on viewer.id = v_id and viewer.university_id = g.university_id
    where g.id = any (v_ids)
      and not private.blocked_pair(v_id, g.host_id)
    on conflict (event_id, user_id) do update
        set notify = public.bookmarks.notify or excluded.notify;
end $$;

create or replace function public.set_chat_muted(p_game_id uuid, p_muted boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_active();
begin
    if p_muted is null then raise exception 'invalid_input'; end if;
    update public.rsvps set chat_muted = p_muted
    where event_id = p_game_id and user_id = v_id;
    if not found then raise exception 'not_allowed'; end if;
end $$;

create or replace function public.notification_opened(p_outbox_id bigint)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_user();
begin
    update private.notification_outbox
    set opened_at = coalesce(opened_at, now())
    where id = p_outbox_id and user_id = v_id;
end $$;

revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.blocked_pair(uuid, uuid), private.same_university(uuid, uuid) to authenticated;

revoke execute on function
    public.claim_notifications(integer),
    public.complete_notifications(jsonb),
    public.current_apns_jwt(),
    public.store_apns_jwt(text)
    from public, anon, authenticated;
grant execute on function
    public.claim_notifications(integer),
    public.complete_notifications(jsonb),
    public.current_apns_jwt(),
    public.store_apns_jwt(text)
    to service_role;

grant execute on function
    public.register_device(text, text, text, text),
    public.unregister_device(text),
    public.set_notification_prefs(boolean, boolean, boolean, boolean, boolean, boolean),
    public.toggle_bookmark(uuid),
    public.set_spot_alert(uuid, boolean),
    public.import_bookmarks(uuid[], uuid[]),
    public.set_chat_muted(uuid, boolean),
    public.notification_opened(bigint)
    to authenticated;

-- Second-level cron where pg_cron allows it. Otherwise a one-minute drain, and chat kicks it.
do $$
begin
    perform cron.schedule('drain-notifications', '10 seconds', 'select private.drain_if_due()');
exception when others then
    raise warning '10-second notification drain unavailable (%); scheduling every minute', sqlerrm;
    perform cron.schedule('drain-notifications', '* * * * *', 'select private.drain_if_due()');
end $$;

select cron.schedule('notification-reminders', '*/5 * * * *', 'select private.enqueue_scheduled_notifications()');
select cron.schedule('notification-winback', '5 * * * *', 'select private.enqueue_winback()');
select cron.schedule('notification-purge', '40 8 * * *', 'select private.purge_notifications()');
