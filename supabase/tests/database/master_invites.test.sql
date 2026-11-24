-- Master invite codes: made and turned off by the team, used by many, with limits on uses and time,
-- through the same `redeem_invite` the app already calls. Members' codes work as before.
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true)
$$;

-- Alice is a member. Pía, Pablo, Paco and Pepa signed up with a password and are waiting.
insert into auth.users (id, email) values
    ('a0000000-0000-4000-8000-00000000000a', 'alice@tec.mx'),
    ('10000000-0000-4000-8000-000000000001', 'pia@tec.mx'),
    ('20000000-0000-4000-8000-000000000002', 'pablo@tec.mx'),
    ('30000000-0000-4000-8000-000000000003', 'paco@tec.mx'),
    ('40000000-0000-4000-8000-000000000004', 'pepa@tec.mx');
select public.before_user_created('{"user":{"email":"pia@tec.mx","app_metadata":{"provider":"email"}}}');
select public.before_user_created('{"user":{"email":"pablo@tec.mx","app_metadata":{"provider":"email"}}}');
select public.before_user_created('{"user":{"email":"paco@tec.mx","app_metadata":{"provider":"email"}}}');
select public.before_user_created('{"user":{"email":"pepa@tec.mx","app_metadata":{"provider":"email"}}}');

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.complete_profile('Alice', 'Zamora', 2027, array['basketball'], 'en');
create temp table alice_codes on commit drop as select code from public.my_invites();
grant select on alice_codes to authenticated;

-- Only the team makes or turns off master codes.
select throws_ok($$ select private.create_master_invite('MASUNO') $$, '42501', null, 'members can''t make master codes');
select throws_ok($$ select private.revoke_master_invite('MASUNO') $$, '42501', null, 'or turn them off');
select throws_ok($$ select * from private.master_invites $$, '42501', null, 'or see them');

reset role;
select is(private.create_master_invite('mas-uno'), 'Made MASUNO (no limit on uses, no end date)', 'a code with no limits');
select is(private.create_master_invite('MASUNO'), 'Not made: MASUNO exists already', 'not twice');
select is(private.create_master_invite('ONCE', 1), 'Made ONCE (1 use, no end date)', 'a code with a limit');
select is(private.create_master_invite('ONCE2', 0), 'Not made: the limit must be at least 1', 'a limit is at least 1');
select is(private.create_master_invite('NIÑO'), 'Not made: a code is 4 to 32 letters (A–Z, no accents) and digits', 'no accents');
select is(private.create_master_invite('AB'), 'Not made: a code is 4 to 32 letters (A–Z, no accents) and digits', 'not too short');
select is(private.create_master_invite((select code from alice_codes limit 1)),
    'Not made: ' || (select code from alice_codes limit 1) || ' is a member''s code', 'never a member''s code');
select private.create_master_invite('OLDCODE', null, now() - interval '1 minute');
select private.create_master_invite('OFFCODE');
select is(private.revoke_master_invite('off-code'), 'Turned off OFFCODE', 'a code is turned off');
select is(private.revoke_master_invite('OFFCODE'), 'OFFCODE was off already', 'once');
select is(private.revoke_master_invite('NOPE'), 'No master code NOPE', 'and a code that isn''t there says so');

-- Pía and Pablo both get in with the same code, typed any way.
set local role authenticated;
select pg_temp.act_as('10000000-0000-4000-8000-000000000001');
select is(public.redeem_invite('mas-uno'), 'approved', 'a master code lets someone in');
select is(public.signup_status(), 'approved', 'and they''re in');
select pg_temp.act_as('20000000-0000-4000-8000-000000000002');
select is(public.redeem_invite(' MasUno '), 'approved', 'and the next person too');
reset role;
select is((select count(*)::int from private.master_invite_uses where code = 'MASUNO'), 2, 'each use is recorded');
select is((select invited_by from private.signup_requests where email = 'pia@tec.mx'), null::uuid,
    'no member vouched, so nobody invited them');

-- A limit of 1 lets one person in. An ended or turned-off code lets nobody in, and counts as wrong.
set local role authenticated;
select pg_temp.act_as('30000000-0000-4000-8000-000000000003');
select is(public.redeem_invite('ONCE'), 'approved', 'the one use of a limited code');
select pg_temp.act_as('40000000-0000-4000-8000-000000000004');
select is(public.redeem_invite('ONCE'), 'invalid_invite', 'is the only one');
select is(public.redeem_invite('OLDCODE'), 'invalid_invite', 'an ended code is refused');
select is(public.redeem_invite('OFFCODE'), 'invalid_invite', 'so is a code that''s off');
reset role;
select is((select invite_attempts from private.signup_requests where email = 'pepa@tec.mx'), 3,
    'and each counts as a wrong try');

-- A member's code still works, and still records who invited whom.
set local role authenticated;
select pg_temp.act_as('40000000-0000-4000-8000-000000000004');
select is(public.redeem_invite((select code from alice_codes limit 1)), 'approved', 'a member''s code still works');
reset role;
select is((select invited_by from private.signup_requests where email = 'pepa@tec.mx'),
    'a0000000-0000-4000-8000-00000000000a'::uuid, 'and records the member');
select is((select invite_attempts from private.signup_requests where email = 'pepa@tec.mx'), 0, 'and clears the wrong tries');

select * from finish();
rollback;
