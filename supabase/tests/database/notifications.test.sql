-- Push notifications: producers, the send-time rules, and the client RPCs (NOTIF.md §2 and §5).
begin;
create extension if not exists pgtap with schema extensions;
select plan(60);

create function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

insert into auth.users (id, email) values
    ('a0000000-0000-4000-8000-00000000000a', 'alice@tec.mx'),
    ('b0000000-0000-4000-8000-00000000000b', 'bruno@tec.mx'),
    ('c0000000-0000-4000-8000-00000000000c', 'carla@tec.mx'),
    ('d0000000-0000-4000-8000-00000000000d', 'dario@tec.mx'),
    ('f0000000-0000-4000-8000-00000000000f', 'pending-push@tec.mx');
insert into private.signup_requests (email) values ('pending-push@tec.mx');

-- A waiting account can register a phone, and can't change preferences yet.
set local role authenticated;
select pg_temp.act_as('f0000000-0000-4000-8000-00000000000f');
select lives_ok($$ select public.register_device('pendingtokenpendingtoken', 'sandbox', 'es-MX', '1.0') $$,
    'a waiting account can register a phone');
select throws_ok($$ select public.set_notification_prefs(true, true, true, true, true, true) $$,
    'P0001', 'pending_approval', 'and can''t change preferences yet');
reset role;
select is((select user_id from private.device_tokens where token = 'pendingtokenpendingtoken'),
    'f0000000-0000-4000-8000-00000000000f'::uuid, 'the token is theirs');

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.complete_profile('Alice', 'Zamora', 2027, array['soccer'], 'en');
select lives_ok($$ select public.register_device('pendingtokenpendingtoken', 'production', 'en-US', '1.0') $$,
    'signing in on the same phone moves the token');
reset role;
select is((select user_id from private.device_tokens where token = 'pendingtokenpendingtoken'),
    'a0000000-0000-4000-8000-00000000000a'::uuid, 'the token now belongs to Alice');
select isnt((select last_seen_at from public.profiles where id = 'a0000000-0000-4000-8000-00000000000a'),
    null, 'registering marks her last seen');

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select lives_ok($$ select public.unregister_device('pendingtokenpendingtoken') $$, 'sign-out removes the token');
select throws_ok($$ select token from private.device_tokens $$, '42501', null, 'clients can''t read device tokens');
select throws_ok($$ select * from public.claim_notifications(10) $$, '42501', null, 'clients can''t drain the outbox');
select throws_ok($$ select private.enqueue_notification(
    'a0000000-0000-4000-8000-00000000000a', 'reminder', null, '{}'::jsonb, null, null, now(), now(), false, 'keep') $$,
    '42501', null, 'clients can''t enqueue');
reset role;
select is_empty($$ select 1 from private.device_tokens where token = 'pendingtokenpendingtoken' $$, 'the token is gone');

set local role authenticated;
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.complete_profile('Bruno', 'Ybarra', 2026, array['soccer'], 'es');
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select public.complete_profile('Carla', 'Xochitl', 2028, array['tennis'], 'es');
select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select public.complete_profile('Darío', 'Vela', 2027, array['padel'], 'es');

-- Bruno follows basketball, so a new basketball game can reach him.
reset role;
update public.profiles set interests = array['basketball'] where id = 'b0000000-0000-4000-8000-00000000000b';

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select is((select winback from public.set_notification_prefs(true, true, true, true, true, true)), true,
    'preferences save and come back');
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select is_empty($$ select 1 from public.notification_prefs where user_id = 'a0000000-0000-4000-8000-00000000000a' $$,
    'someone else can''t read them');

select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
create temp table game_ids on commit drop as
select 'main'::text as name, id from public.create_game('basketball', 'Pickup game', now() + interval '1 day', 60, 4, null,
    'Arena Borregos', 'Av. Junco de la Vega', 25.65, -100.29, null, true);
grant select, insert on game_ids to authenticated;

select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select is((select is_bookmarked from public.toggle_bookmark((select id from game_ids where name = 'main'))), true,
    'bookmarking a game marks the card');
select is((select is_bookmarked from public.toggle_bookmark((select id from game_ids where name = 'main'))), false,
    'bookmarking again removes it');
select is((select spot_alert from public.set_spot_alert((select id from game_ids where name = 'main'), true)), true,
    'notify me saves the game and turns the alert on');

insert into game_ids
select 'other', id from public.create_game('padel', 'Evening padel', now() + interval '2 days', 60, 4, null,
    'Courts', 'Tec', 25.65, -100.29, null, true);
select lives_ok($$ select public.import_bookmarks(
    array[(select id from game_ids where name = 'other')],
    array[(select id from game_ids where name = 'other')]) $$, 'a phone can upload its saved list once');
select is((select is_bookmarked and spot_alert from public.game_cards where id = (select id from game_ids where name = 'other')),
    true, 'the uploaded game is saved with the alert');

-- Interest match: Bruno plays basketball. Alice, the host, does not get one. Carla plays tennis.
reset role;
select is((select count(*)::int from private.notification_outbox
    where event_id = (select id from game_ids where name = 'main') and kind = 'interest_match' and dropped is null),
    1, 'a new game tells campus members who play it');
select is((select user_id from private.notification_outbox
    where event_id = (select id from game_ids where name = 'main') and kind = 'interest_match'),
    'b0000000-0000-4000-8000-00000000000b'::uuid, 'and not the host');
select ok((select not_before > now() + interval '2 minutes' from private.notification_outbox
    where event_id = (select id from game_ids where name = 'main') and kind = 'interest_match'),
    'it waits a few minutes in case the game changes');

-- Host updates, then a game that fills.
set local role authenticated;
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.join_game((select id from game_ids where name = 'main'));
reset role;
select is((select count(*)::int from private.notification_outbox
    where event_id = (select id from game_ids where name = 'main') and kind = 'host_update' and dropped is null),
    1, 'a join tells the host');
select is((select user_id from private.notification_outbox
    where event_id = (select id from game_ids where name = 'main') and kind = 'host_update'),
    'a0000000-0000-4000-8000-00000000000a'::uuid, 'and not the person who joined');
select ok((select not_before > now() + interval '4 minutes' from private.notification_outbox
    where event_id = (select id from game_ids where name = 'main') and kind = 'host_update'),
    'joins in a few minutes merge into one');

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
insert into game_ids
select 'full', id from public.create_game('basketball', 'Full court', now() + interval '1 day', 60, 2, null,
    'Arena', 'Tec', 25.65, -100.29, null, true);
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.join_game((select id from game_ids where name = 'full'));
reset role;
select is((select count(*)::int from private.notification_outbox
    where event_id = (select id from game_ids where name = 'full') and kind = 'game_full' and dropped is null),
    1, 'the join that fills the game tells the host it is full');
select is((select count(*)::int from private.notification_outbox
    where event_id = (select id from game_ids where name = 'full') and kind = 'host_update' and dropped is null),
    0, 'and does not also send a join update');

-- A spot opens for someone who asked, not for the person who left.
set local role authenticated;
select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select public.set_spot_alert((select id from game_ids where name = 'full'), true);
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.leave_game((select id from game_ids where name = 'full'));
reset role;
select is((select user_id from private.notification_outbox
    where event_id = (select id from game_ids where name = 'full') and kind = 'spot_open' and dropped is null),
    'd0000000-0000-4000-8000-00000000000d'::uuid, 'a freed spot tells the person who asked');
select is((select count(*)::int from private.notification_outbox
    where event_id = (select id from game_ids where name = 'full') and kind = 'spot_open'
      and user_id = 'b0000000-0000-4000-8000-00000000000b'),
    0, 'the person who left is not told');

-- Two edits merge. Cancelling drops that pending row and tells everyone going except the host.
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.update_game((select id from game_ids where name = 'main'), 'basketball', 'Pickup game',
    now() + interval '1 day', 60, 4, null, 'Arena Borregos', 'Av. Junco de la Vega', 25.65, -100.29, 'North gate', true);
select public.update_game((select id from game_ids where name = 'main'), 'basketball', 'Pickup game',
    now() + interval '1 day', 60, 4, null, 'Arena Borregos', 'Av. Junco de la Vega', 25.65, -100.29, 'South gate', true);
reset role;
select is((select count(*)::int from private.notification_outbox
    where event_id = (select id from game_ids where name = 'main') and kind = 'game_changed' and dropped is null),
    1, 'several edits make one change notification');
select ok((select not_before > now() + interval '1 minute' from private.notification_outbox
    where event_id = (select id from game_ids where name = 'main') and kind = 'game_changed' and dropped is null),
    'it waits so the last edit wins');

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.cancel_game((select id from game_ids where name = 'main'));
reset role;
select is((select count(*)::int from private.notification_outbox
    where event_id = (select id from game_ids where name = 'main') and kind = 'game_cancelled' and dropped is null
      and user_id = 'b0000000-0000-4000-8000-00000000000b'),
    1, 'cancelling tells the people going');
select is((select count(*)::int from private.notification_outbox
    where event_id = (select id from game_ids where name = 'main') and kind = 'game_cancelled'
      and user_id = 'a0000000-0000-4000-8000-00000000000a'),
    0, 'and not the host who cancelled it');
select is((select dropped from private.notification_outbox
    where event_id = (select id from game_ids where name = 'main') and kind = 'game_changed'),
    'cancelled', 'the pending change is dropped');

-- Chat: the other member, not the sender, and not someone who muted the game.
update public.app_config set value = 'true' where key = 'chat_enabled';
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
insert into game_ids
select 'chat', id from public.create_game('soccer', 'Evening soccer', now() + interval '1 day', 60, 6, null,
    'Field', 'Tec', 25.65, -100.29, null, true);
select public.accept_chat_rules();
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.join_game((select id from game_ids where name = 'chat'));
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select public.join_game((select id from game_ids where name = 'chat'));
select lives_ok($$ select public.set_chat_muted((select id from game_ids where name = 'chat'), true) $$,
    'a member can mute a game');
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.send_message((select id from game_ids where name = 'chat'), 'I will bring the ball', '11111111-1111-4111-8111-111111111111');
select public.send_message((select id from game_ids where name = 'chat'), 'Court 2', '22222222-2222-4222-8222-222222222222');
reset role;
select is((select (payload->>'count')::int from private.notification_outbox
    where event_id = (select id from game_ids where name = 'chat') and kind = 'chat_message'
      and user_id = 'b0000000-0000-4000-8000-00000000000b' and dropped is null),
    2, 'two messages a moment apart merge');
select is((select count(*)::int from private.notification_outbox
    where event_id = (select id from game_ids where name = 'chat') and kind = 'chat_message'
      and user_id = 'c0000000-0000-4000-8000-00000000000c'),
    0, 'a muted game stays quiet');
select is((select count(*)::int from private.notification_outbox
    where event_id = (select id from game_ids where name = 'chat') and kind = 'chat_message'
      and user_id = 'a0000000-0000-4000-8000-00000000000a'),
    0, 'the sender is not notified');

-- Hosting switched off: the next join writes nothing for the host.
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.set_notification_prefs(true, true, true, false, true, true);
insert into game_ids
select 'quiet-host', id from public.create_game('tennis', 'Tennis', now() + interval '2 days', 60, 4, null,
    'Courts', 'Tec', 25.65, -100.29, null, true);
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select public.join_game((select id from game_ids where name = 'quiet-host'));
reset role;
select is((select count(*)::int from private.notification_outbox
    where event_id = (select id from game_ids where name = 'quiet-host') and kind = 'host_update'),
    0, 'a host who turned updates off gets none');

-- Cron producers.
set local role authenticated;
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
insert into game_ids
select 'soon', id from public.create_game('soccer', 'Soon', now() + interval '30 minutes', 60, 4, null,
    'Field', 'Tec', 25.65, -100.29, 'North bleachers', true);
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.join_game((select id from game_ids where name = 'soon'));
select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
insert into game_ids
select 'saved', id from public.create_game('padel', 'Saved soon', now() + interval '2 hours', 60, 4, null,
    'Courts', 'Tec', 25.65, -100.29, null, true);
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.toggle_bookmark((select id from game_ids where name = 'saved'));
reset role;
select lives_ok($$ select private.enqueue_scheduled_notifications() $$, 'the reminder job runs');
select ok(exists (select 1 from private.notification_outbox
    where event_id = (select id from game_ids where name = 'soon') and kind = 'reminder' and dropped is null),
    'a game starting in half an hour reminds the people going');
select ok(exists (select 1 from private.notification_outbox
    where event_id = (select id from game_ids where name = 'saved') and kind = 'saved_soon'
      and user_id = 'b0000000-0000-4000-8000-00000000000b' and dropped is null),
    'a saved game with room nudges the person who saved it');

insert into public.games (
    university_id, host_id, activity_slug, title, starts_at, duration_minutes, ends_at, capacity,
    place_name, place_address, lat, lng
)
select university_id, id, 'basketball', 'Weekday hoops', timestamptz '2026-11-18 18:00+00', 60,
       timestamptz '2026-11-18 19:00+00', 8, 'Arena', 'Tec', 25.65, -100.29
from public.profiles where id = 'a0000000-0000-4000-8000-00000000000a';
insert into public.games (
    university_id, host_id, activity_slug, title, starts_at, duration_minutes, ends_at, capacity,
    place_name, place_address, lat, lng
)
select university_id, id, 'basketball', 'Second hoops', timestamptz '2026-11-19 18:00+00', 60,
       timestamptz '2026-11-19 19:00+00', 8, 'Arena', 'Tec', 25.65, -100.29
from public.profiles where id = 'a0000000-0000-4000-8000-00000000000a';
update public.profiles set last_seen_at = timestamptz '2026-11-01 00:00+00'
where id = 'b0000000-0000-4000-8000-00000000000b';
update public.notification_prefs set winback = true where user_id = 'b0000000-0000-4000-8000-00000000000b';
insert into public.notification_prefs (user_id, winback)
select 'b0000000-0000-4000-8000-00000000000b', true
where not exists (select 1 from public.notification_prefs where user_id = 'b0000000-0000-4000-8000-00000000000b');
select private.enqueue_winback(timestamptz '2026-11-17 23:00+00');
select is((select (payload->>'games')::int from private.notification_outbox
    where user_id = 'b0000000-0000-4000-8000-00000000000b' and kind = 'winback'),
    2, 'win-back names how many games are on that weeknight');

-- Approval tells every token of that account.
select is(private.approve_signup('pending-push@tec.mx'), 'Approved pending-push@tec.mx', 'the team approves the waiting account');
select is((select count(*)::int from private.notification_outbox
    where user_id = 'f0000000-0000-4000-8000-00000000000f' and kind = 'signup_approved' and dropped is null),
    1, 'and that person is told they are in');

-- Nothing already written should be claimed while the rules below are checked.
update private.notification_outbox set not_before = now() + interval '3 days' where sent_at is null and dropped is null;
select lives_ok($$ select private.drain_if_due() $$, 'the drain does nothing when nothing is due');

update public.app_config set value = 'false' where key = 'push_enabled';
select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
select is_empty($$ select 1 from public.claim_notifications(50) $$, 'with push switched off, nothing is claimed');
reset role;
update public.app_config set value = 'true' where key = 'push_enabled';

insert into private.device_tokens (token, user_id, environment, locale, app_version) values
    ('alice-device-token-0001', 'a0000000-0000-4000-8000-00000000000a', 'sandbox', 'en-US', '1.0'),
    ('bruno-device-token-0001', 'b0000000-0000-4000-8000-00000000000b', 'sandbox', 'es-MX', '1.0');

-- Quiet hours hold an ordinary kind and still send a time-sensitive one.
update public.universities set timezone = (
    select name from pg_timezone_names
    where extract(hour from now() at time zone name)::int >= 22
       or extract(hour from now() at time zone name)::int < 8
    limit 1
) where email_domain = 'tec.mx';
insert into private.notification_outbox (user_id, kind, event_id, payload, not_before, expires_at)
select 'b0000000-0000-4000-8000-00000000000b', 'game_changed', id, '{"actor_id":"a0000000-0000-4000-8000-00000000000a"}'::jsonb,
       now(), now() + interval '2 days'
from game_ids where name = 'soon';
insert into private.notification_outbox (user_id, kind, event_id, payload, not_before, expires_at)
select 'b0000000-0000-4000-8000-00000000000b', 'game_cancelled', id, '{"actor_id":"a0000000-0000-4000-8000-00000000000a"}'::jsonb,
       now(), now() + interval '2 days'
from game_ids where name = 'soon';
select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
select is((select count(*)::int from public.claim_notifications(20) where kind = 'game_cancelled'), 1,
    'a cancellation still goes out at night');
reset role;
select ok((select not_before > now() from private.notification_outbox
    where user_id = 'b0000000-0000-4000-8000-00000000000b' and kind = 'game_changed' and dropped is null
    order by id desc limit 1),
    'an ordinary change waits until morning');
update public.universities set timezone = 'America/Monterrey' where email_domain = 'tec.mx';
update private.notification_outbox set not_before = now() + interval '3 days'
where sent_at is null and dropped is null and locked_at is null;

-- Rules that drop a row.
insert into private.notification_outbox (user_id, kind, event_id, payload, not_before, expires_at)
select 'b0000000-0000-4000-8000-00000000000b', 'game_changed', id,
       '{"actor_id":"a0000000-0000-4000-8000-00000000000a"}'::jsonb, now(), now() + interval '1 day'
from game_ids where name = 'soon';
set local role authenticated;
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.block('a0000000-0000-4000-8000-00000000000a');
reset role;
select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
select public.claim_notifications(20);
reset role;
select is((select dropped from private.notification_outbox
    where user_id = 'b0000000-0000-4000-8000-00000000000b' and kind = 'game_changed' and not_before <= now()
    order by id desc limit 1),
    'blocked', 'a block in either direction drops the row');
set local role authenticated;
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.unblock('a0000000-0000-4000-8000-00000000000a');
reset role;

insert into private.notification_outbox (user_id, kind, event_id, payload, not_before, expires_at)
select 'a0000000-0000-4000-8000-00000000000a', 'reminder', id, '{}'::jsonb, now() - interval '1 minute', now() - interval '1 second'
from game_ids where name = 'soon';
insert into private.notification_outbox (user_id, kind, payload, not_before, expires_at) values
    ('b0000000-0000-4000-8000-00000000000b', 'interest_match', '{}'::jsonb, now() - interval '1 day', now() - interval '1 day'),
    ('b0000000-0000-4000-8000-00000000000b', 'interest_match', '{}'::jsonb, now() - interval '1 hour', now() - interval '1 hour');
update private.notification_outbox set sent_at = now()
where user_id = 'b0000000-0000-4000-8000-00000000000b' and kind = 'interest_match' and event_id is null;
insert into private.notification_outbox (user_id, kind, event_id, payload, not_before, expires_at)
select 'b0000000-0000-4000-8000-00000000000b', 'interest_match', id, '{}'::jsonb, now(), now() + interval '1 day'
from game_ids where name = 'soon';
insert into private.notification_outbox (user_id, kind, event_id, payload, not_before, expires_at, sent_at)
select 'a0000000-0000-4000-8000-00000000000a', 'game_changed', id, '{}'::jsonb, now(), now() + interval '1 day', now()
from game_ids where name = 'soon', generate_series(1, 6);
insert into private.notification_outbox (user_id, kind, event_id, payload, not_before, expires_at)
select 'a0000000-0000-4000-8000-00000000000a', 'game_changed', id, '{}'::jsonb, now(), now() + interval '1 day'
from game_ids where name = 'soon';
insert into private.notification_outbox (user_id, kind, event_id, payload, not_before, expires_at)
select 'b0000000-0000-4000-8000-00000000000b', 'spot_open', id, '{}'::jsonb, now(), now() + interval '1 day'
from game_ids where name = 'full';
update public.games set going_count = capacity where id = (select id from game_ids where name = 'full');
insert into private.notification_outbox (user_id, kind, event_id, payload, not_before, expires_at)
select 'b0000000-0000-4000-8000-00000000000b', 'chat_message', id,
       jsonb_build_object('actor_id', 'a0000000-0000-4000-8000-00000000000a', 'message_at', now() - interval '5 minutes', 'count', 1),
       now(), now() + interval '1 day'
from game_ids where name = 'chat';
insert into private.chat_reads (event_id, user_id, last_read_at)
select id, 'b0000000-0000-4000-8000-00000000000b', now() from game_ids where name = 'chat'
on conflict (event_id, user_id) do update set last_read_at = excluded.last_read_at;
update public.profiles set banned_at = now() where id = 'd0000000-0000-4000-8000-00000000000d';
insert into private.notification_outbox (user_id, kind, event_id, payload, not_before, expires_at)
select 'd0000000-0000-4000-8000-00000000000d', 'reminder', id, '{}'::jsonb, now(), now() + interval '1 day'
from game_ids where name = 'soon';
insert into private.notification_outbox (user_id, kind, event_id, payload, not_before, expires_at)
select 'a0000000-0000-4000-8000-00000000000a', 'game_changed', id,
       '{"actor_id":"a0000000-0000-4000-8000-00000000000a"}'::jsonb, now(), now() + interval '1 day'
from game_ids where name = 'soon';
insert into private.notification_outbox (user_id, kind, event_id, payload, not_before, expires_at)
select 'a0000000-0000-4000-8000-00000000000a', 'host_update', id,
       '{"actor_id":"b0000000-0000-4000-8000-00000000000b"}'::jsonb, now(), now() + interval '1 day'
from game_ids where name = 'soon';
insert into private.notification_outbox (user_id, kind, payload, not_before, expires_at) values
    ('f0000000-0000-4000-8000-00000000000f', 'signup_approved', '{}'::jsonb, now(), now() + interval '1 day');

-- Noon somewhere, so quiet hours don't swallow the cap checks.
update public.universities set timezone = (
    select name from pg_timezone_names
    where extract(hour from now() at time zone name)::int = 12
    limit 1
) where email_domain = 'tec.mx';
select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
select public.claim_notifications(100);
reset role;

select is((select dropped from private.notification_outbox
    where user_id = 'a0000000-0000-4000-8000-00000000000a' and kind = 'reminder' and expires_at < now()
    order by id desc limit 1),
    'expired', 'an expired row is dropped');
select is((select dropped from private.notification_outbox
    where user_id = 'b0000000-0000-4000-8000-00000000000b' and kind = 'interest_match' and event_id is not null
      and sent_at is null and not_before <= now() + interval '1 minute'
    order by id desc limit 1),
    'cap', 'interest matches stop at two a day');
select is((select dropped from private.notification_outbox
    where user_id = 'a0000000-0000-4000-8000-00000000000a' and kind = 'game_changed' and sent_at is null
      and coalesce(payload->>'actor_id', '') = ''
      and not_before <= now() + interval '1 minute'
    order by id desc limit 1),
    'cap', 'ordinary kinds stop at six a day');
select is((select dropped from private.notification_outbox
    where user_id = 'b0000000-0000-4000-8000-00000000000b' and kind = 'spot_open' and not_before <= now() + interval '1 minute'
    order by id desc limit 1),
    'stale', 'a spot alert is dropped when the game is full again');
select is((select dropped from private.notification_outbox
    where user_id = 'b0000000-0000-4000-8000-00000000000b' and kind = 'chat_message' and not_before <= now()
    order by id desc limit 1),
    'read', 'someone already reading the chat is skipped');
select is((select dropped from private.notification_outbox
    where user_id = 'd0000000-0000-4000-8000-00000000000d' and kind = 'reminder' and not_before <= now() + interval '1 minute'
    order by id desc limit 1),
    'banned', 'a banned account is skipped');
select is((select dropped from private.notification_outbox
    where user_id = 'a0000000-0000-4000-8000-00000000000a' and kind = 'game_changed'
      and payload->>'actor_id' = 'a0000000-0000-4000-8000-00000000000a'),
    'actor', 'the person who caused it is skipped');
select is((select dropped from private.notification_outbox
    where user_id = 'a0000000-0000-4000-8000-00000000000a' and kind = 'host_update'
      and not_before <= now() + interval '1 minute'
    order by id desc limit 1),
    'pref', 'a setting that is off drops the row');
select ok((select not_before > now() from private.notification_outbox
    where user_id = 'f0000000-0000-4000-8000-00000000000f' and kind = 'signup_approved' and sent_at is null
      and dropped is null
    order by id desc limit 1),
    'a row with no phone yet waits instead of being dropped');

-- A successful send clears "Notify me" so it fires once per request.
insert into private.notification_outbox (user_id, kind, event_id, payload, not_before, expires_at)
select 'b0000000-0000-4000-8000-00000000000b', 'spot_open', id, '{}'::jsonb, now(), now() + interval '1 day'
from game_ids where name = 'saved';
update public.bookmarks set notify = true
where user_id = 'b0000000-0000-4000-8000-00000000000b'
  and event_id = (select id from game_ids where name = 'saved');
select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
select public.complete_notifications(jsonb_build_array(jsonb_build_object(
    'id', (select id from private.notification_outbox
           where user_id = 'b0000000-0000-4000-8000-00000000000b' and kind = 'spot_open'
             and event_id = (select id from game_ids where name = 'saved')
           order by id desc limit 1),
    'outcome', 'sent'
)));
reset role;
select isnt((select sent_at from private.notification_outbox
    where user_id = 'b0000000-0000-4000-8000-00000000000b' and kind = 'spot_open'
      and event_id = (select id from game_ids where name = 'saved')),
    null, 'a sent row is marked sent');
select is((select notify from public.bookmarks
    where user_id = 'b0000000-0000-4000-8000-00000000000b'
      and event_id = (select id from game_ids where name = 'saved')),
    false, 'and that notify-me flag is cleared');

select * from finish();
rollback;
