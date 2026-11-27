-- Before User Created hook (SPEC §8.4, B4, N36, N39): deny by default, check provider and email.
-- A school address with a password gets in, and once its emailed code is entered it waits for the
-- team's approval. The hook itself records nothing: `private.signup_verified` does, after the code.
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true)
$$;

select is(public.before_user_created('{"user":{"email":"a0123@tec.mx","app_metadata":{"provider":"azure"}}}'),
    '{}'::jsonb, 'a Tec address through Tec''s SSO provider signs up');
select is(public.before_user_created('{"user":{"email":"A0123@TEC.MX","app_metadata":{"provider":"azure"}}}'),
    '{}'::jsonb, 'the email is compared case-insensitively');
select is((select count(*) from private.signup_requests), 0::bigint, 'an SSO sign-up needs no approval');
select ok(public.before_user_created('{"user":{"email":"a0123@mail.tec.mx","app_metadata":{"provider":"azure"}}}') ? 'error',
    'a subdomain is not the campus domain');
select ok(public.before_user_created('{"user":{"email":"someone@gmail.com","app_metadata":{"provider":"azure"}}}') ? 'error',
    'another organization''s account is refused');
select ok(public.before_user_created('{"user":{"email":"someone@gmail.com","app_metadata":{"provider":"email"}}}') ? 'error',
    'a password sign-up outside the campus domain is refused');
select ok(public.before_user_created('{"user":{"email":"x@demo.masuno.invalid","app_metadata":{"provider":"email"}}}') ? 'error',
    'nobody signs up on the demo campus by domain');
select is((select count(*) from private.signup_requests), 0::bigint, 'refused sign-ups leave no request');
-- The team creates the allowlisted accounts in the dashboard, which doesn't run this hook. One made
-- from the app is let through and proves the inbox with its code (security_fixes covers what follows).
select is(public.before_user_created('{"user":{"email":"official.masuno.app+review1@gmail.com","app_metadata":{"provider":"email"}}}'),
    '{}'::jsonb, 'an allowlisted review account signs up with a password');
select is((select count(*) from private.signup_requests where email = 'official.masuno.app+review1@gmail.com'),
    0::bigint, 'and the hook records no request for it');

-- A school address with a password: let in, and waiting for approval once its code is entered.
select is(public.before_user_created('{"user":{"email":"Pending@Tec.mx","app_metadata":{"provider":"email"}}}'),
    '{}'::jsonb, 'a password sign-up on a Tec address is let in');
select is((select count(*) from private.signup_requests), 0::bigint,
    'typing an address takes no place in line before its code is entered');
select private.signup_verified('Pending@Tec.mx');
select is((select count(*) from private.signup_requests where email = 'pending@tec.mx' and approved_at is null), 1::bigint,
    'with the code, it waits for approval');
select private.signup_verified('pending@tec.mx');
select is((select count(*) from private.signup_requests), 1::bigint, 'and entering a code again asks only once');

insert into auth.users (id, email) values ('f0000000-0000-4000-8000-00000000000f', 'pending@tec.mx');
set local role authenticated;
select pg_temp.act_as('f0000000-0000-4000-8000-00000000000f');
select is(public.signup_status(), 'pending', 'the app sees the account is waiting');
select throws_ok($$ select public.complete_profile('Pia', 'Pendiente', 2028, array['soccer'], 'es') $$, 'pending_approval',
    'a waiting account can''t create a profile');
select throws_ok($$ select private.approve_signup('pending@tec.mx') $$, '42501', null, 'and can''t approve itself');

reset role;
select is(private.approve_signup(' Pending@tec.mx '), 'Approved pending@tec.mx', 'the team approves it');
set local role authenticated;
select is(public.signup_status(), 'approved', 'the app sees the approval');
select lives_ok($$ select public.complete_profile('Pia', 'Pendiente', 2028, array['soccer'], 'es') $$, 'and the profile saves');

-- Rejecting deletes the account that was waiting.
reset role;
select private.signup_verified('nope@tec.mx');
insert into auth.users (id, email) values ('f1000000-0000-4000-8000-0000000000f1', 'nope@tec.mx');
select is(private.reject_signup('nope@tec.mx'), 'Rejected nope@tec.mx', 'the team rejects a sign-up');
select is((select count(*) from auth.users where email = 'nope@tec.mx'), 0::bigint, 'and its account is gone');

update public.universities set signup_enabled = false where email_domain = 'tec.mx';
select ok(public.before_user_created('{"user":{"email":"late@tec.mx","app_metadata":{"provider":"email"}}}') ? 'error',
    'a closed campus takes no new accounts');

select is(public.before_user_created('{"user":{"email":"x@gmail.com"}}') -> 'error' ->> 'message',
    'email_not_allowed', 'the rejection carries the code the app maps');

select * from finish();
rollback;
