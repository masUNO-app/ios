-- Block privacy applies to existing membership and to queued delivery, not only new reads.
-- Keep prior migrations intact for projects that already applied the chat-push filter.

-- RLS must protect the underlying activity table too. Masking only its invoker view leaves
-- raw actor snapshots readable and exposes anonymous join/leave timing in the public timeline.
drop policy "activity visible to members" on private.game_activity;
create policy "activity visible to members" on private.game_activity for select using (
    exists (select 1 from public.rsvps mine
            where mine.event_id = game_activity.event_id and mine.user_id = (select auth.uid()))
    and (actor_id is null or not private.blocked_pair((select auth.uid()), actor_id))
);

-- Lock all active games hosted by either participant before checking RSVPs. Joining takes
-- the same game lock: a concurrent join either sees the block or is removed after it commits.
create or replace function private.remove_blocked_players(p_first uuid, p_second uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_game public.games%rowtype; v_player uuid;
begin
    for v_game in select * from public.games
        where host_id in (p_first, p_second) and ends_at > now() and cancelled_at is null
        order by id for update
    loop
        v_player := case when v_game.host_id = p_first then p_second else p_first end;
        delete from public.rsvps where event_id = v_game.id and user_id = v_player and role = 'player';
        if not found then continue; end if;
        update public.games set going_count = going_count - 1,
            reposted_at = case when going_count = capacity and auto_repost then now() else reposted_at end
        where id = v_game.id;
        perform private.activity_actor(v_game.id, 'left', v_player);
    end loop;
end $$;
revoke execute on function private.remove_blocked_players(uuid,uuid) from public, anon, authenticated, service_role;

-- A block changes names/visibility even when no RSVP changes. Use a campus-wide invalidation
-- without game IDs: naming only this pair's games would itself disclose their attendance.
create or replace function private.broadcast_block_change(p_first uuid, p_second uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_campus uuid;
begin
    for v_campus in select distinct university_id from public.profiles where id in (p_first,p_second) loop
        perform realtime.send('{}'::jsonb,'changed','campus:' || v_campus::text || ':games',true);
    end loop;
exception when others then
    raise warning 'block visibility broadcast failed: %', sqlerrm;
end $$;
revoke execute on function private.broadcast_block_change(uuid,uuid) from public, anon, authenticated, service_role;

create or replace function public.block(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_id uuid := private.require_active();
begin
    if p_user_id = v_id or not exists(select 1 from public.profiles where id = p_user_id) then
        raise exception 'invalid_input';
    end if;
    insert into public.blocks(blocker_id,blocked_id) values(v_id,p_user_id) on conflict do nothing;
    perform private.remove_blocked_players(v_id,p_user_id);
    perform private.broadcast_block_change(v_id,p_user_id);
end $$;
create or replace function public.unblock(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_id uuid := private.require_active();
begin
    delete from public.blocks where blocker_id = v_id and blocked_id = p_user_id;
    if found then perform private.broadcast_block_change(v_id,p_user_id); end if;
end $$;

-- Repair upcoming/in-progress hosted games for block pairs that predate this migration.
-- Unblocking does not restore any removed RSVP; the person must choose to join again.
do $$
declare v_pair record;
begin
    for v_pair in select distinct least(blocker_id,blocked_id) as first_id,
                                  greatest(blocker_id,blocked_id) as second_id
                  from public.blocks order by first_id,second_id
    loop
        perform private.remove_blocked_players(v_pair.first_id,v_pair.second_id);
    end loop;
end $$;

-- A merged chat burst stores the first body and several names, while actor_id names only the
-- latest sender. Rebuild every identity-bearing field from currently visible source messages.
-- Host summaries already retain actor IDs, so filter every member, not only the latest actor.
create or replace function private.notification_payload_at_claim(
    p_kind text, p_event uuid, p_recipient uuid, p_queued_at timestamptz, p_payload jsonb
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_messages jsonb; v_names jsonb; v_first jsonb; v_last jsonb; v_members jsonb;
begin
    if p_event is null then return p_payload; end if;
    if p_kind = 'chat_message' then
        select jsonb_agg(jsonb_build_object(
            'sender_id',m.sender_id,'name',private.person_label(m.sender_id),
            'initials',upper(left(p.first_name,1) || coalesce(p.last_initial::text,'')), 'body',m.body, 'at',m.created_at
        ) order by m.created_at, (m.sender_id::text = p_payload->>'sender_id'), m.id)
        into v_messages
        from private.chat_messages m join public.profiles p on p.id = m.sender_id
        where m.event_id = p_event and m.created_at >= p_queued_at
          and m.created_at <= coalesce((p_payload->>'message_at')::timestamptz,now())
          and m.deleted_at is null and p.banned_at is null and m.sender_id <> p_recipient
          and not private.blocked_pair(p_recipient,m.sender_id);
        if v_messages is null then return null; end if;
        -- Keep the first body when its author is still visible. Equal timestamps can occur
        -- within one transaction; the producer's latest sender remains the last in that case.
        select value into v_first from jsonb_array_elements(v_messages) where value->>'body' = p_payload->>'body' limit 1;
        v_first := coalesce(v_first,v_messages->0);
        v_last := v_messages->-1;
        select jsonb_agg(name order by position) into v_names from (
            select value->>'name' as name,min(position) as position
            from jsonb_array_elements(v_messages) with ordinality entry(value,position)
            group by value->>'name'
        ) named;
        return p_payload || jsonb_build_object(
            'actor_id',v_last->'sender_id','sender_id',v_last->'sender_id',
            'sender_name',v_last->'name','sender_initials',v_last->'initials',
            'body',v_first->'body','count',jsonb_array_length(v_messages),'names',v_names,'message_at',v_last->'at',
            'others',private.chat_others(p_event,(v_last->>'sender_id')::uuid,p_recipient)
        );
    elsif p_kind = 'host_update' then
        select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) into v_members
        from jsonb_each(private.host_update_members(p_payload))
        where not private.blocked_pair(p_recipient,key::uuid);
        if v_members = '{}'::jsonb then return null; end if;
        return p_payload || jsonb_build_object(
            'roster_changes',v_members,
            'actor_id',coalesce((select key from jsonb_each(v_members) where key=p_payload->>'actor_id'),
                                (select min(key) from jsonb_each(v_members))),
            'joined',coalesce((select jsonb_agg(value->>'name' order by key) from jsonb_each(v_members)
                               where value->>'action'='joined'),'[]'::jsonb),
            'left',coalesce((select jsonb_agg(value->>'name' order by key) from jsonb_each(v_members)
                             where value->>'action'='left'),'[]'::jsonb)
        );
    end if;
    return p_payload;
end $$;
revoke execute on function private.notification_payload_at_claim(text,uuid,uuid,timestamptz,jsonb)
    from public, anon, authenticated, service_role;

-- Keep the shared send-time rule implementation behind both legacy and fenced v2 claims.
create or replace function private.claim_notifications_unfenced(p_limit integer)
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
begin
    -- #variable_conflict above: result columns share names with the outbox, and SQL uses the column.
    if coalesce((select value from public.app_config where key = 'push_enabled'), 'false'::jsonb) <> 'true'::jsonb then
        return;
    end if;

    for v_row in
        select * from private.notification_outbox
        where sent_at is null and dropped is null and not_before <= now()
          and (locked_at is null or locked_at < now() - interval '10 minutes')
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

revoke execute on function private.claim_notifications_unfenced(integer) from public,anon,authenticated,service_role;
