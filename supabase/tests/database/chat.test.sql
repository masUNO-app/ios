-- Group chat messaging (B20, SPEC Appendix A): who can post and read, consent, the kill switch,
-- retries, the rate limit, unread counts, message reports and blocks.
begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true)
$$;

insert into auth.users (id, email) values
    ('a0000000-0000-4000-8000-00000000000a', 'alice@tec.mx'),
    ('b0000000-0000-4000-8000-00000000000b', 'bruno@tec.mx'),
    ('c0000000-0000-4000-8000-00000000000c', 'carla@tec.mx'),
    ('d0000000-0000-4000-8000-00000000000d', 'dario@tec.mx');

-- The migration adds the switch off, but seed.sql turns it on locally and in CI, so start from a known state.
select ok(exists (select 1 from public.app_config where key = 'chat_enabled'), 'the chat switch exists');
update public.app_config set value = 'false' where key = 'chat_enabled';
select ok(
    to_regclass('realtime.messages') is null
    or exists (select 1 from pg_policies where schemaname = 'realtime' and tablename = 'messages'
               and policyname = 'game members receive chat broadcasts'),
    'the chat channel is limited to game members');

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.complete_profile('Alice', 'Zamora', 2027, array['basketball'], 'en');
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.complete_profile('Bruno', 'Ybarra', 2026, array['soccer'], 'es');
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select public.complete_profile('Carla', 'Xochitl', 2028, array['tennis'], 'es');
select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select public.complete_profile('Darío', 'Vela', 2027, array['soccer'], 'es');

-- Alice hosts; Bruno and Carla join; Darío stays out.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
create temp table game_ids on commit drop as
select 'main'::text as name, id from public.create_game('basketball', 'Pickup game', now() + interval '1 day', 60, 6, null,
    'Arena Borregos', 'Av. Junco de la Vega', 25.65, -100.29, null, true);
grant select on game_ids to authenticated;
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.join_game((select id from game_ids));
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select public.join_game((select id from game_ids));

-- The kill switch, then consent.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.send_message((select id from game_ids), 'Hola', gen_random_uuid()) $$,
    'P0001', 'chat_disabled', 'no messages while chat is switched off');
reset role;
update public.app_config set value = 'true' where key = 'chat_enabled';
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.send_message((select id from game_ids), 'Hola', gen_random_uuid()) $$,
    'P0001', 'chat_rules_required', 'chat rules come first');
select is((select chat_rules_accepted_at from public.my_profile), null, 'my_profile shows the rules aren''t accepted');
select lives_ok($$ select public.accept_chat_rules() $$, 'Alice accepts the chat rules');
select isnt((select chat_rules_accepted_at from public.my_profile), null, 'my_profile shows when they were accepted');
select throws_ok($$ select chat_rules_accepted_at from public.profiles $$, '42501', null, 'nobody else can read that');

-- Sending, trimming and retries.
select is((select body from public.send_message((select id from game_ids), '  Nos vemos en la cancha 2  ', '11111111-1111-4111-8111-111111111111')),
    'Nos vemos en la cancha 2', 'a member posts, trimmed');
select is((select sender_last_initial::text from public.game_messages), 'Z', 'messages carry first name and last initial only');
select lives_ok($$ select public.send_message((select id from game_ids), 'Nos vemos en la cancha 2', '11111111-1111-4111-8111-111111111111') $$,
    'a retry with the same client ID succeeds');
select is((select count(*)::int from public.game_messages), 1, 'and doesn''t post twice');
select throws_ok($$ select public.send_message((select id from game_ids), 'pinche cancha', gen_random_uuid()) $$,
    'P0001', 'invalid_text', 'the word filter applies');
select throws_ok($$ select public.send_message((select id from game_ids), 'mira https://example.com', gen_random_uuid()) $$,
    'P0001', 'invalid_text', 'links are refused');
select throws_ok($$ select public.send_message((select id from game_ids), '   ', gen_random_uuid()) $$,
    'P0001', 'invalid_text', 'an empty message is refused');
select throws_ok($$ select public.send_message((select id from game_ids), repeat('a', 1001), gen_random_uuid()) $$,
    'P0001', 'invalid_text', 'so is one over 1000 characters');

-- Members read; everyone else gets nothing.
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select is((select count(*)::int from public.game_messages), 1, 'another member reads the chat');
select is((select unread_count from public.chat_unread where event_id = (select id from game_ids)), 1, 'and has one new message');
select public.accept_chat_rules();
select public.send_message((select id from game_ids), 'Llego en 10', gen_random_uuid());
select is((select unread_count from public.chat_unread where event_id = (select id from game_ids)), 1, 'your own messages don''t count as new');
select lives_ok($$ select public.mark_chat_read((select id from game_ids)) $$, 'opening the chat marks it read');
select is_empty($$ select 1 from public.chat_unread $$, 'then nothing is new');
select throws_ok($$ insert into private.chat_messages (event_id, sender_id, body, client_id)
                    values ((select id from game_ids), 'b0000000-0000-4000-8000-00000000000b', 'direct', gen_random_uuid()) $$,
    '42501', null, 'clients can''t write messages directly');

select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select is_empty($$ select 1 from public.game_messages $$, 'someone outside the game can''t read it');
select is_empty($$ select 1 from public.chat_unread $$, 'or see counts for it');
select public.accept_chat_rules();
select throws_ok($$ select public.send_message((select id from game_ids), 'Hola', gen_random_uuid()) $$,
    'P0001', 'not_allowed', 'or post to it');
select lives_ok($$ select public.mark_chat_read((select id from game_ids)) $$, 'marking it read does nothing');
select throws_ok($$ select public.report_message((select id from private.chat_messages limit 1), 'spam', null) $$,
    'P0001', 'invalid_input', 'or report a message in it');

-- Reports and blocks.
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select throws_ok($$ select public.report_message((select id from public.game_messages where sender_first_name = 'Bruno'), 'rude', null) $$,
    'P0001', 'invalid_input', 'an unknown reason is refused');
select lives_ok($$ select public.report_message((select id from public.game_messages where sender_first_name = 'Bruno'), 'harassment', 'not ok') $$,
    'a member reports a message');
select public.block('b0000000-0000-4000-8000-00000000000b');
select is((select array_agg(sender_first_name) from public.game_messages), array['Alice'], 'a blocked sender''s messages are hidden');
select is((select unread_count from public.chat_unread), 1, 'and don''t count as new');
reset role;
select is((select message_body from public.reports where message_id is not null), 'Llego en 10',
    'the report keeps the sender and the text');

-- A player who leaves loses the chat; a cancelled or long-ended game is closed.
set local role authenticated;
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select public.leave_game((select id from game_ids));
select is_empty($$ select 1 from public.game_messages $$, 'leaving the game closes its chat to you');
reset role;
update public.games set starts_at = now() - interval '26 hours', ends_at = now() - interval '25 hours' where id = (select id from game_ids);
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.send_message((select id from game_ids), 'Buen juego', gen_random_uuid()) $$,
    'P0001', 'ended', 'the chat closes 24 hours after the game');

-- Rate limit: 20 a minute.
reset role;
update public.games set starts_at = now() + interval '1 day', ends_at = now() + interval '25 hours' where id = (select id from game_ids);
insert into private.chat_messages (event_id, sender_id, body, client_id)
select (select id from game_ids), 'a0000000-0000-4000-8000-00000000000a', 'msg ' || n, gen_random_uuid() from generate_series(1, 19) n;
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.send_message((select id from game_ids), 'una más', gen_random_uuid()) $$,
    'P0001', 'rate_limited', 'the 21st message in a minute is refused');

select * from finish();
rollback;
