-- Invites and the waitlist, and the beta tester badge (SPEC N37): codes, redemption, the wrong-try
-- limit, places in line, `grant_invites`, the badge in my_profile and Who's going, and who can call what.
begin;
create extension if not exists pgtap with schema extensions;
select plan(41);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true)
$$;

-- Alice and Bruno are members. Pía, Pablo and Paco signed up with a password and are waiting.
insert into auth.users (id, email) values
    ('a0000000-0000-4000-8000-00000000000a', 'alice@tec.mx'),
    ('b0000000-0000-4000-8000-00000000000b', 'bruno@tec.mx'),
    ('10000000-0000-4000-8000-000000000001', 'pia@tec.mx'),
    ('20000000-0000-4000-8000-000000000002', 'pablo@tec.mx'),
    ('30000000-0000-4000-8000-000000000003', 'paco@tec.mx');
select public.before_user_created('{"user":{"email":"pia@tec.mx","app_metadata":{"provider":"email"}}}');
select public.before_user_created('{"user":{"email":"pablo@tec.mx","app_metadata":{"provider":"email"}}}');
select public.before_user_created('{"user":{"email":"paco@tec.mx","app_metadata":{"provider":"email"}}}');
-- One transaction has one now(), so spread the requests out by hand.
update private.signup_requests set requested_at = now() - interval '3 hours' where email = 'pablo@tec.mx';
update private.signup_requests set requested_at = now() - interval '2 hours' where email = 'pia@tec.mx';
update private.signup_requests set requested_at = now() - interval '1 hour' where email = 'paco@tec.mx';

-- Signed out, none of it is callable.
set local role anon;
select pg_temp.act_as(null);
select throws_ok($$ select * from public.my_invites() $$, '42501', null, 'signed out, no invites');
select throws_ok($$ select public.redeem_invite('ABCDEFGH') $$, '42501', null, 'signed out, no redeeming');
select throws_ok($$ select public.waitlist_position() $$, '42501', null, 'signed out, no place in line');
select throws_ok($$ select public.mark_beta_tester() $$, '42501', null, 'signed out, no badge');

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.complete_profile('Alice', 'Zamora', 2027, array['basketball'], 'en');
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.complete_profile('Bruno', 'Ybarra', 2026, array['soccer'], 'es');
select throws_ok($$ select private.grant_invites('bruno@tec.mx', 5) $$, '42501', null, 'members can''t give themselves codes');

-- A member's codes appear the first time they look, three of them, and no more after that.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
create temp table alice_codes on commit drop as
select code, row_number() over (order by created_at, code) as n from public.my_invites();
grant select on alice_codes to authenticated;
select is((select count(*)::int from alice_codes), 3, 'a member has three codes');
select is((select count(*)::int from public.my_invites()), 3, 'and still three on the next look');
select ok((select bool_and(code ~ '^[A-HJ-NP-Z2-9]{8}$') from alice_codes), 'codes are 8 characters, without 0, O, 1 or I');
select is((select count(*)::int from public.my_invites() where redeemed_at is not null), 0, 'none used yet');

-- The waitlist, in order of signing up.
select pg_temp.act_as('20000000-0000-4000-8000-000000000002');
select is(public.waitlist_position(), 1, 'the first to sign up is next');
select pg_temp.act_as('10000000-0000-4000-8000-000000000001');
select is(public.waitlist_position(), 2, 'the second is second');
select pg_temp.act_as('30000000-0000-4000-8000-000000000003');
select is(public.waitlist_position(), 3, 'the third is third');
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select is(public.waitlist_position(), null::integer, 'a member isn''t in line');

-- Pía, waiting, gets codes wrong until the limit, then waits out the hour.
select pg_temp.act_as('10000000-0000-4000-8000-000000000001');
select throws_ok($$ select * from public.my_invites() $$, 'P0001', 'pending_approval', 'a waiting account has no codes to give');
select throws_ok($$ select public.mark_beta_tester() $$, 'P0001', 'pending_approval', 'or a badge');
select is(public.redeem_invite('NOPE-NOPE'), 'invalid_invite', 'a code that doesn''t exist is refused');
select is(public.redeem_invite(null), 'invalid_invite', 'so is no code');
select public.redeem_invite('WRNG' || n) from generate_series(2, 4) n;
reset role;
select is((select invite_attempts from private.signup_requests where email = 'pia@tec.mx'), 5,
    'each wrong try is counted, and the count is kept');
set local role authenticated;
select pg_temp.act_as('10000000-0000-4000-8000-000000000001');
select is(public.redeem_invite((select code from alice_codes where n = 1)), 'rate_limited',
    'after 5 wrong tries in an hour, even a good code waits');
select is(public.signup_status(), 'pending', 'and the account is still waiting');

reset role;
update private.signup_requests set invite_attempt_at = now() - interval '61 minutes' where email = 'pia@tec.mx';
set local role authenticated;
select pg_temp.act_as('10000000-0000-4000-8000-000000000001');
select is(
    public.redeem_invite((select ' ' || lower(left(code, 4)) || ' - ' || lower(right(code, 4)) || ' ' from alice_codes where n = 1)),
    'approved', 'an hour later, a member''s code lets her in, however it''s typed');
select is(public.signup_status(), 'approved', 'with no approval from the team');
select is(public.waitlist_position(), null::integer, 'and off the waitlist');
select lives_ok($$ select public.complete_profile('Pía', 'Pérez', 2028, array['soccer'], 'es') $$, 'so her profile saves');
select is(public.redeem_invite('ANYTHING'), 'approved', 'redeeming again when you aren''t waiting does nothing');
reset role;
select is((select invited_by from private.signup_requests where email = 'pia@tec.mx'),
    'a0000000-0000-4000-8000-00000000000a'::uuid, 'who invited her is recorded');
select is((select redeemed_email from private.invites where code = (select code from alice_codes where n = 1)),
    'pia@tec.mx', 'and the code is marked used');

-- A used code doesn't work twice.
set local role authenticated;
select pg_temp.act_as('20000000-0000-4000-8000-000000000002');
select is(public.redeem_invite((select code from alice_codes where n = 1)), 'invalid_invite', 'a used code is refused');
select is(public.waitlist_position(), 1, 'and Pablo is still next in line');

-- Alice sees who used her code by first name and last initial, and never an email.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select is((select redeemer_first_name || ' ' || redeemer_last_initial from public.my_invites()
           where code = (select code from alice_codes where n = 1)), 'Pía P', 'the inviter sees who joined');
select is(
    (select proargnames from pg_proc where oid = 'public.my_invites()'::regprocedure),
    array['code', 'created_at', 'redeemed_at', 'redeemer_first_name', 'redeemer_last_initial'],
    'my_invites returns no emails');

-- The team gives more codes.
reset role;
select is(private.grant_invites(' Alice@Tec.mx ', 2), 'Gave alice@tec.mx 2 more invites (5 in all)', 'the team gives Alice two more');
select is(private.grant_invites('nobody@tec.mx', 2), 'No profile for nobody@tec.mx', 'an address without a profile gets none');
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select is((select count(*)::int from public.my_invites()), 5, 'and they show up');

-- Beta tester badge: stamped once, shown on your profile and in Who's going.
select is((select is_beta_tester from public.my_profile), false, 'nobody starts as a beta tester');
select is((select is_beta_tester from public.mark_beta_tester()), true, 'opening a TestFlight build sets the badge');
reset role;
update public.profiles set beta_tester_at = '2026-11-01T00:00:00Z' where id = 'a0000000-0000-4000-8000-00000000000a';
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.mark_beta_tester();
reset role;
select is((select beta_tester_at from public.profiles where id = 'a0000000-0000-4000-8000-00000000000a'),
    '2026-11-01T00:00:00Z'::timestamptz, 'and keeps the first time');
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
create temp table game_ids on commit drop as
select id from public.create_game('basketball', 'Pickup game', now() + interval '1 day', 60, 6, null,
    'Arena Borregos', 'Av. Junco de la Vega', 25.65, -100.29, null, true);
grant select on game_ids to authenticated;
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.join_game((select id from game_ids));
select is((select array_agg(first_name || ':' || is_beta_tester::text order by first_name) from public.game_attendees
           where event_id = (select id from game_ids)),
    array['Alice:true', 'Bruno:false'], 'Who''s going shows who has the badge');
select throws_ok($$ select beta_tester_at from public.profiles $$, '42501', null, 'but not when they got it');

-- An inviter's own code, and a banned inviter's codes, don't work. Bruno is made to wait again, as
-- if his request were still open, to try his own.
reset role;
select private.issue_invites('b0000000-0000-4000-8000-00000000000b');
create temp table bruno_codes on commit drop as select code from private.invites where inviter_id = 'b0000000-0000-4000-8000-00000000000b';
grant select on bruno_codes to authenticated;
insert into private.signup_requests (email) values ('bruno@tec.mx');
update public.profiles set banned_at = now() where id = 'a0000000-0000-4000-8000-00000000000a';
set local role authenticated;
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select is(public.redeem_invite((select code from bruno_codes limit 1)), 'invalid_invite', 'nobody redeems their own code');
select pg_temp.act_as('30000000-0000-4000-8000-000000000003');
select is(public.redeem_invite((select code from alice_codes where n = 2)), 'invalid_invite', 'a banned member''s codes stop working');

select * from finish();
rollback;
