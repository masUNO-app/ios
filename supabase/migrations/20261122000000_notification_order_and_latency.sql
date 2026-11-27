-- Bound conversational latency and preserve submission order across drain workers.
-- Eligible notifications are ordered by creation ID. Scheduled/quiet-hour rows do not
-- hold up current alerts; an active send or retry does hold up that recipient.
create index notification_pending_recipient_order
    on private.notification_outbox (user_id, id)
    where sent_at is null and dropped is null;

create function private.claim_notifications_ordered(p_limit integer)
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
                -- Each user's claims share a transaction lock. Try instead of waiting while
                -- holding outbox row locks, so overlapping drains cannot deadlock each other.
                if v_row.kind <> 'chat_message' and v_level <> 'time-sensitive' and not
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
                elsif v_row.kind <> 'chat_message' and v_level <> 'time-sensitive' and
                    private.notification_budget_used(v_row.user_id, v_day_start) >= 6 then
                    v_reason := 'cap';
                end if;
            end if;

            if v_reason is null and v_has_game
               and v_row.kind in ('chat_message','reminder','game_changed','game_cancelled')
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

            if v_row.kind = 'chat_message' and exists (
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


create or replace function private.claim_notifications_v2(p_limit integer)
returns table (
    id bigint, user_id uuid, kind text, event_id uuid, payload jsonb,
    collapse_id text, expires_at timestamptz, tokens jsonb, context jsonb, claim_token uuid
) language plpgsql security definer set search_path = '' as $$
declare r record; v_token uuid;
begin
    for r in select * from private.claim_notifications_ordered(p_limit) loop
        v_token := gen_random_uuid();
        update private.notification_outbox o set claim_token = v_token where o.id = r.id;
        id := r.id;
        user_id := r.user_id;
        kind := r.kind;
        event_id := r.event_id;
        payload := r.payload;
        collapse_id := r.collapse_id;
        expires_at := r.expires_at;
        tokens := r.tokens;
        context := r.context;
        claim_token := v_token;
        return next;
    end loop;
end $$;

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
        -- First message is immediate; follow-ups wait at most ten seconds.
        -- Keep an existing pending deadline so steady conversation cannot starve it.
        select max(sent_at) into v_sent
        from private.notification_outbox
        where merge_key = v_key and sent_at > now() - interval '10 seconds';
        v_not_before := greatest(now(), coalesce(v_sent + interval '10 seconds', now()));
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
            v_key, 'chat:' || new.event_id::text, v_not_before, now() + interval '24 hours', false, 'keep'
        );
    end loop;
    perform private.drain_if_due();
    return new;
exception when others then
    raise warning 'chat notification enqueue failed for %: %', new.id, sqlerrm;
    return new;
end $$;


create or replace function private.complete_notifications_unfenced(p_results jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_item jsonb;
    v_id bigint;
    v_outcome text;
    v_kind text;
    v_user uuid;
    v_event uuid;
    v_resend boolean;
    v_claimed timestamptz;
begin
    for v_item in select value from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
        v_id := (v_item->>'id')::bigint;
        v_outcome := v_item->>'outcome';
        select kind, user_id, event_id, resend, locked_at
        into v_kind, v_user, v_event, v_resend, v_claimed
        from private.notification_outbox where id = v_id and sent_at is null for update;
        if not found then continue; end if;

        if v_outcome = 'sent' then
            if v_resend and v_claimed is not null and v_kind <> 'chat_message'
               and private.notification_level(v_kind) <> 'time-sensitive' then
                insert into private.notification_resend_deliveries (outbox_id, claimed_at, user_id, kind)
                values (v_id, v_claimed, v_user, v_kind)
                on conflict (outbox_id, claimed_at) do nothing;
            end if;
            -- The phone already has this version. Messages that arrived mid-send stay queued.
            update private.notification_outbox
            set sent_at = case when resend then sent_at else now() end,
                locked_at = null,
                not_before = case when resend then now() else not_before end,
                resend = false,
                error = null
            where id = v_id and sent_at is null;
            if v_kind = 'spot_open' and not coalesce(v_resend, false) then
                update public.bookmarks set notify = false
                where user_id = v_user and event_id = v_event;
            end if;
        elsif v_outcome = 'release' then
            update private.notification_outbox
            set locked_at = null, resend = false
            where id = v_id and sent_at is null;
        elsif v_outcome = 'retry' and v_item->>'error' = 'earlier_notification_pending' then
            update private.notification_outbox set locked_at = null, resend = false
            where id = v_id and sent_at is null;
        elsif v_outcome = 'retry' then
            update private.notification_outbox set
                attempts = attempts + 1,
                locked_at = null,
                resend = false,
                error = left(v_item->>'error', 500),
                not_before = now() + make_interval(secs => (5 * power(2, attempts))::int),
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
                'game:' || new.event_id::text, now() + interval '10 seconds', v_game.starts_at, false, 'keep'
            );
        end loop;
    elsif new.kind in ('joined', 'left') and new.actor_id is not null and new.actor_id <> v_game.host_id then
        -- A pending full alert becomes obsolete as soon as someone frees a spot.
        if new.kind = 'left' then
            update private.notification_outbox set dropped = 'stale'
            where event_id = new.event_id and kind = 'game_full'
              and sent_at is null and dropped is null;
        end if;
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
                'roster_changes', jsonb_build_object(new.actor_id::text,
                    jsonb_build_object('name', v_name, 'action', new.kind)),
                'joined', case when new.kind = 'joined' then jsonb_build_array(v_name) else '[]'::jsonb end,
                'left', case when new.kind = 'left' then jsonb_build_array(v_name) else '[]'::jsonb end,
                'spots_left', v_game.capacity - v_game.going_count,
                'capacity', v_game.capacity
            );
            perform private.enqueue_notification(
                v_game.host_id, 'host_update', new.event_id, v_payload,
                'host:' || new.event_id::text, 'game:' || new.event_id::text,
                now() + interval '10 seconds', v_game.starts_at, false, 'keep'
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
                'game:' || new.event_id::text, now() + interval '10 seconds', v_game.starts_at, true, 'keep'
            );
        end loop;
    end if;
    return new;
exception when others then
    raise warning 'notification enqueue failed for activity %: %', new.id, sqlerrm;
    return new;
end $$;

revoke execute on function private.notify_on_activity() from public, anon, authenticated, service_role;

-- Shorten existing batching deadlines; leave quiet hours and retry backoff alone.
update private.notification_outbox
set not_before = least(not_before, now() + interval '10 seconds')
where kind in ('chat_message', 'game_changed', 'host_update', 'interest_match') and sent_at is null and dropped is null and attempts = 0
  and locked_at is null and not_before <= now() + interval '5 minutes';

revoke execute on function private.claim_notifications_ordered(integer),
    private.notify_on_chat(), private.complete_notifications_unfenced(jsonb)
    from public, anon, authenticated, service_role;
