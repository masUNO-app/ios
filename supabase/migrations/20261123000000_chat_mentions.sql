-- Group chat mentions (NOTIF §3.5). "@Maya C." in a message stores Maya's ID on it, and Maya gets a
-- push for that message right away, even with chat pushes off in Settings or the game muted.
-- Blocks, membership, chat_enabled, chat_reads and the app's open-chat check still apply.
-- Compatible with earlier builds: send_message's new p_mentions defaults to empty, game_messages
-- gains a column at the end, and the push reaches the phone as a chat push with "mention": true.

-- At most 10, already filtered by send_message.
alter table private.chat_messages
    add column mentions uuid[] not null default '{}' check (cardinality(mentions) <= 10);

-- A second signature would make three-argument calls from older builds ambiguous in PostgREST,
-- so the old one goes and the new parameter has a default. It returns this view's rows, so it goes first.
drop function public.send_message(uuid, text, uuid);

-- As in 20261110000000, plus the mentions. A reader doesn't see IDs of people in a blocked pair with them.
create or replace view public.game_messages
with (security_invoker = true) as
select m.id, m.event_id, m.sender_id, p.first_name as sender_first_name, p.last_initial as sender_last_initial,
       p.grad_year as sender_grad_year, m.body, m.client_id, m.created_at,
       array(
           select mentioned.id from unnest(m.mentions) with ordinality as mentioned(id, position)
           where not private.blocked_pair((select auth.uid()), mentioned.id)
           order by mentioned.position
       ) as mentions
from private.chat_messages m
join public.profiles p on p.id = m.sender_id;

-- Posts a message to a game's chat.
-- Parameters: the game, the text (1–1000 characters after trimming), the app's ID for this send, and
-- the people it mentions. A mention is kept only for a current member (host or going) other than you,
-- outside any block with you, whose "@First L." is in the text; repeats are dropped and at most 10 kept.
-- Returns the game_messages row. Sending the same p_client_id again returns the first message.
-- Raises not_found, not_allowed (not in the game), chat_disabled, cancelled, ended (over 24 h ago),
-- chat_rules_required, invalid_text, rate_limited (20 a minute) or invalid_input.
create function public.send_message(p_game_id uuid, p_body text, p_client_id uuid, p_mentions uuid[] default '{}')
returns setof public.game_messages language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_active();
    v_game public.games%rowtype;
    v_body text;
    v_message uuid;
    v_mentions uuid[];
begin
    if p_client_id is null then raise exception 'invalid_input'; end if;
    select g.* into v_game
    from public.games g
    join public.profiles viewer on viewer.id = v_id and viewer.university_id = g.university_id
    where g.id = p_game_id;
    if not found or private.blocked_pair(v_id, v_game.host_id) then raise exception 'not_found'; end if;
    if not exists (select 1 from public.rsvps where event_id = p_game_id and user_id = v_id) then
        raise exception 'not_allowed';
    end if;

    select id into v_message from private.chat_messages where sender_id = v_id and client_id = p_client_id;
    if found then
        return query select * from public.game_messages where id = v_message;
        return;
    end if;

    if coalesce((select value from public.app_config where key = 'chat_enabled'), 'false'::jsonb) <> 'true'::jsonb then
        raise exception 'chat_disabled';
    end if;
    if v_game.cancelled_at is not null then raise exception 'cancelled'; end if;
    if v_game.ends_at <= now() - interval '24 hours' then raise exception 'ended'; end if;
    if not exists (select 1 from public.profiles where id = v_id and chat_rules_accepted_at is not null) then
        raise exception 'chat_rules_required';
    end if;
    v_body := private.clean_text(p_body, 1000, true);
    if (select count(*) from private.chat_messages
        where sender_id = v_id and created_at > now() - interval '1 minute') >= 20 then
        raise exception 'rate_limited';
    end if;

    -- Only the first 50 asked for are looked at; the first 10 that pass are kept, in the order asked.
    select coalesce(array_agg(kept.user_id order by kept.position), '{}'::uuid[]) into v_mentions
    from (
        select picked.user_id, picked.position
        from (
            select distinct on (wanted.user_id) wanted.user_id, wanted.position
            from unnest(coalesce(p_mentions, '{}'::uuid[])) with ordinality as wanted(user_id, position)
            join public.rsvps r on r.event_id = p_game_id and r.user_id = wanted.user_id
            where wanted.position <= 50
              and wanted.user_id <> v_id
              and not private.blocked_pair(v_id, wanted.user_id)
              and strpos(v_body, '@' || private.person_label(wanted.user_id)) > 0
            order by wanted.user_id, wanted.position
        ) picked
        order by picked.position
        limit 10
    ) kept;

    insert into private.chat_messages (event_id, sender_id, body, client_id, mentions)
    values (p_game_id, v_id, v_body, p_client_id, v_mentions)
    on conflict (sender_id, client_id) do nothing
    returning id into v_message;
    if v_message is null then
        select id into v_message from private.chat_messages where sender_id = v_id and client_id = p_client_id;
    end if;
    return query select * from public.game_messages where id = v_message;
end $$;

revoke execute on function public.send_message(uuid, text, uuid, uuid[]) from public, anon;
grant execute on function public.send_message(uuid, text, uuid, uuid[]) to authenticated;

-- A new kind, so the send-time rules can tell a mention from an ordinary chat push.
alter table private.notification_outbox drop constraint notification_outbox_kind_check;
alter table private.notification_outbox add constraint notification_outbox_kind_check check (kind in (
    'game_cancelled', 'game_changed', 'reminder', 'host_update', 'game_full',
    'spot_open', 'interest_match', 'chat_message', 'chat_mention', 'signup_approved', 'winback', 'saved_soon'
));

-- As in 20261116000000. Mentions are always on: the chat switch doesn't apply to them.
create or replace function private.notification_allowed(p_user uuid, p_kind text)
returns boolean language sql stable security definer set search_path = ''
as $$
    select case p_kind
        when 'game_cancelled' then true
        when 'game_changed' then true
        when 'signup_approved' then true
        when 'chat_mention' then true
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

-- As in 20261116000000. Mentions don't count toward the daily cap, like the rest of chat.
create or replace function private.notification_budget_used(p_user uuid, p_since timestamptz, p_kind text default null)
returns bigint language sql stable security definer set search_path = ''
as $$
    select (
        select count(*) from private.notification_outbox o
        where o.user_id = p_user
          and (p_kind is null or o.kind = p_kind)
          and o.kind not in ('chat_message', 'chat_mention') and private.notification_level(o.kind) <> 'time-sensitive'
          and (o.sent_at >= p_since or (
              o.sent_at is null and o.dropped is null and o.locked_at >= now() - interval '10 minutes'
          ))
    ) + (
        select count(*) from private.notification_resend_deliveries d
        where d.user_id = p_user and d.sent_at >= p_since
          and (p_kind is null or d.kind = p_kind)
    )
$$;

-- As in 20261122000000. A mentioned member gets a chat_mention row for that message instead of a
-- chat_message, whether or not they muted the game. It goes now, outside the ten-second throttle,
-- with its own collapse ID, so a later merged chat push can't replace its banner.
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
        select r.user_id, r.chat_muted, r.user_id = any (new.mentions) as mentioned
        from public.rsvps r
        where r.event_id = new.event_id
          and r.user_id <> new.sender_id
          and not private.blocked_pair(r.user_id, new.sender_id)
    loop
        if v_member.mentioned then
            perform private.enqueue_notification(
                v_member.user_id, 'chat_mention', new.event_id,
                jsonb_build_object(
                    'actor_id', new.sender_id,
                    'sender_id', new.sender_id,
                    'sender_name', v_name,
                    'sender_initials', v_initials,
                    'message_id', new.id,
                    'body', left(new.body, 1000),
                    'count', 1,
                    'message_at', new.created_at,
                    'others', private.chat_others(new.event_id, new.sender_id, v_member.user_id)
                ),
                'mention:' || new.id::text || ':' || v_member.user_id::text,
                'mention:' || new.id::text, now(), now() + interval '24 hours', true, 'keep'
            );
            continue;
        end if;
        if v_member.chat_muted then continue; end if;

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

-- As in 20261121000000, plus mentions. A merged chat push leaves out messages that mention the
-- recipient, since those have their own push. A mention is rebuilt from its message: gone if the
-- message was hidden, its sender banned or blocked, or the mention no longer names the recipient.
create or replace function private.notification_payload_at_claim(
    p_kind text, p_event uuid, p_recipient uuid, p_queued_at timestamptz, p_payload jsonb
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_messages jsonb; v_names jsonb; v_first jsonb; v_last jsonb; v_members jsonb; v_mention record;
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
          and not private.blocked_pair(p_recipient,m.sender_id)
          and not (p_recipient = any (m.mentions));
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
    elsif p_kind = 'chat_mention' then
        select m.sender_id, m.body, m.created_at, p.first_name, p.last_initial into v_mention
        from private.chat_messages m join public.profiles p on p.id = m.sender_id
        where m.id = nullif(p_payload->>'message_id','')::uuid and m.event_id = p_event
          and m.deleted_at is null and p.banned_at is null and m.sender_id <> p_recipient
          and p_recipient = any (m.mentions)
          and not private.blocked_pair(p_recipient,m.sender_id);
        if not found then return null; end if;
        return p_payload || jsonb_build_object(
            'actor_id',v_mention.sender_id,'sender_id',v_mention.sender_id,
            'sender_name',private.notification_names(v_mention.first_name,v_mention.last_initial::text),
            'sender_initials',upper(left(v_mention.first_name,1) || coalesce(v_mention.last_initial::text,'')),
            'body',v_mention.body,'count',1,'message_at',v_mention.created_at,
            'others',private.chat_others(p_event,v_mention.sender_id,p_recipient)
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

-- As in 20261122000000, with mentions following chat's rules except the chat switch, mute,
-- quiet hours and the throttle: still members only, chat_enabled, not already read, and blocks
-- (the generic actor check covers the sender).
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


-- The legacy claim (before the v2 sender) doesn't know mentions: it leaves them for v2.
create or replace function private.claim_notifications(p_limit integer)
returns table (
    id bigint, user_id uuid, kind text, event_id uuid, payload jsonb,
    collapse_id text, expires_at timestamptz, tokens jsonb, context jsonb
) language plpgsql security definer set search_path = '' as $$
declare r record;
begin
    for r in select * from private.claim_notifications_unfenced(p_limit) loop
        if r.kind = 'chat_mention' then
            update private.notification_outbox o set locked_at = null where o.id = r.id;
            continue;
        end if;
        update private.notification_outbox o set claim_token = null where o.id = r.id;
        id := r.id;
        user_id := r.user_id;
        kind := r.kind;
        event_id := r.event_id;
        payload := r.payload;
        collapse_id := r.collapse_id;
        expires_at := r.expires_at;
        tokens := r.tokens;
        context := r.context;
        return next;
    end loop;
end $$;

-- Replacing a function keeps its grants; repeat the earlier lock-down anyway.
revoke execute on function private.claim_notifications_ordered(integer), private.claim_notifications(integer),
    private.notify_on_chat(), private.notification_payload_at_claim(text, uuid, uuid, timestamptz, jsonb)
    from public, anon, authenticated, service_role;
revoke execute on function private.notification_allowed(uuid, text),
    private.notification_budget_used(uuid, timestamptz, text) from public, anon, authenticated;
