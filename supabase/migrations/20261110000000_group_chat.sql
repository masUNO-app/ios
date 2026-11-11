-- Group chat messaging (B20; SPEC §7.6.9 and Appendix A items 1–4, 6, 7 and 9).
-- Compatible with 0.5: nothing it reads or calls changes. New columns are added at the end of
-- my_profile, `report` keeps its signature, and the new app_config value isn't a string, so 0.5 skips it.
--
-- Chat ships switched off. After two phones exchange messages on a project, turn it on with:
--   update public.app_config set value = 'true' where key = 'chat_enabled';
-- While it's off, 0.6 shows the read-only chat (no composer) and send_message answers chat_disabled.

insert into public.app_config (key, value) values ('chat_enabled', 'false') on conflict (key) do nothing;

-- "Before you chat" consent, once per account. Not in the column grants, so only my_profile shows it.
alter table public.profiles add column chat_rules_accepted_at timestamptz;

-- Still runs as its owner (see 20261109000000); the auth.uid() filter is the only access check.
create or replace view public.my_profile
with (security_invoker = false) as
select p.id, p.first_name, p.last_name, p.grad_year, p.university_id, u.name as university_name,
       u.short_name as university_short_name, u.email_domain as university_email_domain,
       u.center_lat, u.center_lng, p.interests, p.guidelines_accepted_at, p.banned_at,
       p.chat_rules_accepted_at
from public.profiles p join public.universities u on u.id = p.university_id
where p.id = auth.uid();

-- Messages go with the game, and with the sender's account when it's deleted. A moderator hides
-- one by setting deleted_at. client_id is the app's own ID for a send, so a retry never posts twice.
create table private.chat_messages (
    id uuid primary key default gen_random_uuid(),
    event_id uuid not null references public.games(id) on delete cascade,
    sender_id uuid not null references public.profiles(id) on delete cascade,
    body text not null check (char_length(body) between 1 and 1000),
    client_id uuid not null,
    created_at timestamptz not null default now(),
    deleted_at timestamptz,
    unique (sender_id, client_id)
);
create index chat_messages_event_created_idx on private.chat_messages (event_id, created_at desc);
create index chat_messages_sender_created_idx on private.chat_messages (sender_id, created_at);

-- When each member last opened a game's chat, for "Group chat · N new".
create table private.chat_reads (
    event_id uuid not null references public.games(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    last_read_at timestamptz not null default now(),
    primary key (event_id, user_id)
);
create index chat_reads_user_idx on private.chat_reads (user_id);

alter table private.chat_messages enable row level security;
alter table private.chat_reads enable row level security;
revoke all on private.chat_messages, private.chat_reads from public, anon, authenticated;
grant select on private.chat_messages, private.chat_reads to authenticated;

-- Only people in the game read its chat; leaving the game closes it. Blocked senders are hidden.
create policy "messages visible to members" on private.chat_messages for select to authenticated using (
    deleted_at is null
    and exists (
        select 1 from public.rsvps mine
        where mine.event_id = chat_messages.event_id and mine.user_id = (select auth.uid())
    )
    and not private.blocked_pair((select auth.uid()), sender_id)
);
create policy "own chat reads" on private.chat_reads for select to authenticated using (
    user_id = (select auth.uid())
);

create view public.game_messages
with (security_invoker = true) as
select m.id, m.event_id, m.sender_id, p.first_name as sender_first_name, p.last_initial as sender_last_initial,
       p.grad_year as sender_grad_year, m.body, m.client_id, m.created_at
from private.chat_messages m
join public.profiles p on p.id = m.sender_id;

-- One row per game with messages you haven't seen. Your own messages never count.
create view public.chat_unread
with (security_invoker = true) as
select m.event_id, count(*)::integer as unread_count
from private.chat_messages m
left join private.chat_reads r on r.event_id = m.event_id and r.user_id = (select auth.uid())
where m.sender_id <> (select auth.uid())
  and (r.last_read_at is null or m.created_at > r.last_read_at)
group by m.event_id;

revoke all on public.game_messages, public.chat_unread from public, anon, authenticated;
grant select on public.game_messages, public.chat_unread to authenticated;

create function public.accept_chat_rules()
returns void language plpgsql security definer set search_path = ''
as $$ begin
    update public.profiles
    set chat_rules_accepted_at = coalesce(chat_rules_accepted_at, now()), updated_at = now()
    where id = private.require_active();
end $$;

-- Posts a message to a game's chat.
-- Parameters: the game, the text (1–1000 characters after trimming) and the app's ID for this send.
-- Returns the game_messages row. Sending the same p_client_id again returns the first message.
-- Raises not_found, not_allowed (not in the game), chat_disabled, cancelled, ended (over 24 h ago),
-- chat_rules_required, invalid_text, rate_limited (20 a minute) or invalid_input.
create function public.send_message(p_game_id uuid, p_body text, p_client_id uuid)
returns setof public.game_messages language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_active();
    v_game public.games%rowtype;
    v_body text;
    v_message uuid;
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

    insert into private.chat_messages (event_id, sender_id, body, client_id)
    values (p_game_id, v_id, v_body, p_client_id)
    on conflict (sender_id, client_id) do nothing
    returning id into v_message;
    if v_message is null then
        select id into v_message from private.chat_messages where sender_id = v_id and client_id = p_client_id;
    end if;
    return query select * from public.game_messages where id = v_message;
end $$;

-- Marks a game's chat as read up to now. Does nothing if you aren't in the game.
create function public.mark_chat_read(p_game_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active();
begin
    insert into private.chat_reads (event_id, user_id, last_read_at)
    select p_game_id, v_id, now()
    where exists (select 1 from public.rsvps where event_id = p_game_id and user_id = v_id)
    on conflict (event_id, user_id) do update set last_read_at = excluded.last_read_at;
end $$;

-- A reported message is filed against its sender, with the text copied so the report still reads
-- after the message, the game or the account is gone.
alter table public.reports
    add column message_id uuid references private.chat_messages(id) on delete set null,
    add column message_body text;
create index reports_message_idx on public.reports (message_id) where message_id is not null;

-- Reports a message in a chat you're in. Reasons are the same as `report`.
-- Raises invalid_input for an unknown reason, a note over 500 characters, your own message, or a
-- message you can't see.
create function public.report_message(p_message_id uuid, p_reason text, p_note text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_active();
    v_message private.chat_messages%rowtype;
begin
    if p_reason is null or p_reason not in ('harassment', 'inappropriate', 'spam', 'unsafe', 'other')
       or char_length(coalesce(btrim(p_note), '')) > 500 then
        raise exception 'invalid_input';
    end if;
    select m.* into v_message
    from private.chat_messages m
    where m.id = p_message_id
      and exists (select 1 from public.rsvps r where r.event_id = m.event_id and r.user_id = v_id);
    if not found or v_message.sender_id = v_id then raise exception 'invalid_input'; end if;
    insert into public.reports (reporter_id, user_id, message_id, message_body, reason, note)
    values (v_id, v_message.sender_id, v_message.id, v_message.body, p_reason, nullif(btrim(p_note), ''));
end $$;

-- Same alert as before, now naming a chat message as its own kind of target.
create or replace function private.alert_new_report()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
    v_webhook_url text;
    v_dashboard_url text;
    v_message text;
begin
    select decrypted_secret into v_webhook_url from vault.decrypted_secrets where name = 'report_alert_webhook_url';
    if v_webhook_url is null then
        raise warning 'report % not alerted: Vault secret report_alert_webhook_url is missing', new.id;
        return new;
    end if;
    select decrypted_secret into v_dashboard_url from vault.decrypted_secrets where name = 'report_alert_dashboard_url';

    v_message := format(
        'New report: %s, about a %s. Report %s. Act on it within 24 h. %s',
        new.reason,
        case when new.message_id is not null then 'chat message'
             when new.user_id is not null then 'person'
             else 'game' end,
        new.id,
        coalesce(v_dashboard_url, 'Open the reports table in Supabase.')
    );
    -- Discord reads "content" and Slack reads "text"; each ignores the other.
    perform net.http_post(
        url := v_webhook_url,
        body := jsonb_build_object('content', v_message, 'text', v_message),
        headers := '{"Content-Type": "application/json"}'::jsonb
    );
    return new;
exception when others then
    raise warning 'report % not alerted: %', new.id, sqlerrm;
    return new;
end $$;

-- Realtime (Appendix A item 4): each new message or system row pings the game's private channel,
-- `game:<id>:chat`. The ping carries only the row's ID; the app then reads game_messages or
-- game_activity, so blocks and membership are enforced in one place. A failed ping never blocks
-- the write: the app also checks for new messages on a timer.
create function private.broadcast_chat_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
    perform realtime.send(
        jsonb_build_object('id', new.id), tg_argv[0], 'game:' || new.event_id::text || ':chat', true
    );
    return null;
exception when others then
    raise warning 'chat broadcast failed for %: %', new.id, sqlerrm;
    return null;
end $$;

create trigger chat_messages_broadcast
after insert on private.chat_messages
for each row execute function private.broadcast_chat_change('message');

create trigger game_activity_broadcast
after insert on private.game_activity
for each row execute function private.broadcast_chat_change('activity');

-- Only people in the game may join its channel. The Realtime service owns realtime.messages, so a
-- database without it (a bare Postgres) skips the policy with a warning instead of failing.
do $$
begin
    if to_regclass('realtime.messages') is null then
        raise warning 'realtime.messages is missing: chat channel policy not created';
        return;
    end if;
    execute $policy$
        create policy "game members receive chat broadcasts" on realtime.messages
        for select to authenticated using (
            extension = 'broadcast'
            and exists (
                select 1 from public.rsvps r
                where r.user_id = (select auth.uid())
                  and 'game:' || r.event_id::text || ':chat' = (select realtime.topic())
            )
        )
    $policy$;
end $$;

-- Retention (Appendix A item 9): message text goes 30 days after its game ended. 00:45 in Monterrey.
select cron.schedule(
    'purge-old-chat', '45 6 * * *',
    $$delete from private.chat_messages m using public.games g
      where g.id = m.event_id and g.ends_at < now() - interval '30 days'$$
);

-- Functions created above get the default EXECUTE grant, so repeat the lock-down.
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.blocked_pair(uuid, uuid), private.same_university(uuid, uuid) to authenticated;
revoke execute on function public.accept_chat_rules(), public.send_message(uuid, text, uuid),
    public.mark_chat_read(uuid), public.report_message(uuid, text, text) from public, anon;
grant execute on function public.accept_chat_rules(), public.send_message(uuid, text, uuid),
    public.mark_chat_read(uuid), public.report_message(uuid, text, text) to authenticated;
