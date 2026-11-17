-- Security review fixes (20261119000000): blocks hide attendance both ways, bans close reads,
-- allowlisted password sign-ups wait, device tokens stay with their install, Discord gets no emails,
-- and signed-out callers run only what's meant for them.
begin;
create extension if not exists pgtap with schema extensions;
select plan(39);

create function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

insert into auth.users (id, email) values
    ('a0000000-0000-4000-8000-00000000000a', 'alice@tec.mx'),
    ('b0000000-0000-4000-8000-00000000000b', 'bruno@tec.mx'),
    ('c0000000-0000-4000-8000-00000000000c', 'carla@tec.mx');

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.complete_profile('Alice', 'Zamora', 2027, array['basketball'], 'en');
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.complete_profile('Bruno', 'Ybarra', 2026, array['soccer'], 'es');
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select public.complete_profile('Carla', 'Xochitl', 2028, array['tennis'], 'es');

-- Carla hosts two games; Alice joins one, then blocks Bruno.
create temp table game_ids on commit drop as
select 'joined'::text as name, id from public.create_game('tennis', 'Doubles', now() + interval '1 day', 60, 4, null, 'Courts', 'Tec', 25.65, -100.29, null, true);
insert into game_ids
select 'open', id from public.create_game('tennis', 'Singles', now() + interval '2 days', 60, 4, null, 'Courts', 'Tec', 25.65, -100.29, null, true);
grant select on game_ids to authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.join_game((select id from game_ids where name = 'joined'));
select public.block('b0000000-0000-4000-8000-00000000000b');

-- The blocked person learns nothing about where the blocker is going.
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select is_empty($$ select 1 from public.rsvps where user_id = 'a0000000-0000-4000-8000-00000000000a' $$,
    'a blocked person can''t read the blocker''s RSVPs from the table');
select is((select count(*)::int from public.rsvps where event_id = (select id from game_ids where name = 'joined')), 1,
    'they still see everyone else going');
select is((select has_blocked_attendee from public.game_cards where id = (select id from game_ids where name = 'joined')), false,
    'has_blocked_attendee doesn''t give the blocker away');
select is((select going_count from public.join_game((select id from game_ids where name = 'joined'))), 3,
    'join_game doesn''t answer `blocked` for a game the blocker is in');

-- The blocker is still told, and still kept out.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select is((select has_blocked_attendee from public.game_cards where id = (select id from game_ids where name = 'joined')), true,
    'the blocker sees someone they blocked is going');
select is((select has_blocked_attendee from public.game_cards where id = (select id from game_ids where name = 'open')), false,
    'and not on a game without them');
select is_empty($$ select 1 from public.rsvps where user_id = 'b0000000-0000-4000-8000-00000000000b' $$,
    'the blocker can''t read the blocked person''s RSVPs either');
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.join_game((select id from game_ids where name = 'open'));
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.join_game((select id from game_ids where name = 'open')) $$,
    'P0001', 'blocked', 'the blocker gets `blocked` for a game someone they blocked is in');

-- A banned account reads nothing past its own data.
reset role;
update public.profiles set banned_at = now() where id = 'c0000000-0000-4000-8000-00000000000c';
update public.app_config set value = 'true' where key = 'chat_enabled';
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.accept_chat_rules();
select public.send_message((select id from game_ids where name = 'joined'), 'See you there', gen_random_uuid());
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select is_empty($$ select 1 from public.game_cards $$, 'a banned account sees no games');
select is_empty($$ select 1 from public.rsvps $$, 'or RSVPs');
select is_empty($$ select 1 from public.game_attendees $$, 'or who''s going');
select is_empty($$ select 1 from public.profiles $$, 'or anyone''s profile');
select is_empty($$ select 1 from public.game_activity $$, 'or game activity');
select is_empty($$ select 1 from public.game_messages $$, 'or chat messages');
select is((select first_name from public.my_profile), 'Carla', 'but still reads its own profile, for the suspended screen');
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select is((select count(*)::int from public.game_messages), 1, 'an active member still reads the chat');

-- An allowlisted address signing up with a password waits for approval.
reset role;
select is(public.before_user_created('{"user":{"email":"official.masuno.app+review2@gmail.com","app_metadata":{"provider":"email"}}}'),
    '{}'::jsonb, 'an allowlisted address can still sign up with a password');
select is((select count(*)::int from private.signup_requests where email = 'official.masuno.app+review2@gmail.com' and approved_at is null), 1,
    'but it waits for approval like anyone else');
select is(public.before_user_created('{"user":{"email":"official.masuno.app+qa1@gmail.com","app_metadata":{"provider":"azure"}}}'),
    '{}'::jsonb, 'through an SSO provider it still goes straight in');
select is((select count(*)::int from private.signup_requests where email = 'official.masuno.app+qa1@gmail.com'), 0,
    'with no request');

-- Discord alerts name the request, never the address.
select is(private.mask_email('a01234567@tec.mx'), 'a•••@tec.mx', 'alerts mask the email');
select is(private.mask_email('not an email'), '•••', 'and anything that isn''t one');
select isnt((select id from private.signup_requests where email = 'official.masuno.app+review2@gmail.com'), null,
    'each request has an id for the approve and reject lines');

-- A device token stays with the install that registered it.
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.register_device('alicetokenalicetoken', 'sandbox', 'en', '1.0', 'alice-phone-install-secret');
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select lives_ok($$ select public.register_device('alicetokenalicetoken', 'sandbox', 'en', '1.0', 'bruno-phone-install-secret') $$,
    'registering someone else''s token from another install isn''t an error');
select lives_ok($$ select public.register_device('alicetokenalicetoken', 'sandbox', 'en', '1.0') $$,
    'nor is it without an install secret');
reset role;
select is((select user_id from private.device_tokens where token = 'alicetokenalicetoken'),
    'a0000000-0000-4000-8000-00000000000a'::uuid, 'but the token stays Alice''s');
set local role authenticated;
select public.register_device('alicetokenalicetoken', 'sandbox', 'en', '1.0', 'alice-phone-install-secret');
reset role;
select is((select user_id from private.device_tokens where token = 'alicetokenalicetoken'),
    'b0000000-0000-4000-8000-00000000000b'::uuid, 'signing in to another account on the same install moves it');

-- An unbound legacy token is still owned by its current account during the upgrade.
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.register_device('legacytokenlegacytoken', 'sandbox', 'en', '0.9');
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.register_device('legacytokenlegacytoken', 'sandbox', 'es', '1.0', 'attacker-install-secret');
reset role;
select is((select user_id from private.device_tokens where token='legacytokenlegacytoken'),
    'a0000000-0000-4000-8000-00000000000a'::uuid, 'a foreign install cannot take an unbound legacy token');
select is((select install_hash from private.device_tokens where token='legacytokenlegacytoken'),
    null::bytea, 'a foreign install cannot bind its own secret to a legacy token');
set local role authenticated;
select public.register_device('legacytokenlegacytoken', 'sandbox', 'es', '0.9');
reset role;
select is((select user_id from private.device_tokens where token='legacytokenlegacytoken'),
    'a0000000-0000-4000-8000-00000000000a'::uuid, 'an old client cannot take another account legacy token either');
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.register_device('legacytokenlegacytoken', 'sandbox', 'en', '1.0', 'genuine-install-secret');
reset role;
select is((select install_hash from private.device_tokens where token='legacytokenlegacytoken'),
    extensions.digest('genuine-install-secret','sha256'), 'the current owner can bind the genuine install on upgrade');
set local role authenticated;
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.register_device('legacytokenlegacytoken', 'sandbox', 'es', '1.0', 'attacker-install-secret');
reset role;
select is((select user_id from private.device_tokens where token='legacytokenlegacytoken'),
    'a0000000-0000-4000-8000-00000000000a'::uuid, 'a later takeover attempt still leaves the token with its owner');
select is((select install_hash from private.device_tokens where token='legacytokenlegacytoken'),
    extensions.digest('genuine-install-secret','sha256'), 'a later takeover attempt cannot replace the binding');
set local role authenticated;
select public.register_device('legacytokenlegacytoken', 'sandbox', 'en', '1.0', 'genuine-install-secret');
reset role;
select is((select user_id from private.device_tokens where token='legacytokenlegacytoken'),
    'b0000000-0000-4000-8000-00000000000b'::uuid, 'the proven install can still switch accounts after upgrading');

-- Signed out, only guest browsing and the website's waitlist RPCs run.
set local role anon;
select throws_ok($$ select public.join_game((select id from game_ids where name = 'open')) $$, '42501', null,
    'signed out, game RPCs from the first migration are closed');
select throws_ok($$ select public.register_device('anontokenanontoken', 'sandbox', 'en', '1.0') $$, '42501', null,
    'and so are the notification RPCs');
select lives_ok($$ select * from public.guest_games(null) $$,
    'guest browsing still works');
select lives_ok($$ select public.waitlist_export('wrong') $$, 'and so does the website''s waitlist export');
reset role;
select is_empty($$
    select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')
      and p.proname not in ('guest_games', 'waitlist_join', 'waitlist_export')
$$, 'anon can execute nothing else in public');

select * from finish();
rollback;
