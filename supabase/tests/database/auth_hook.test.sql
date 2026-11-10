-- Before User Created hook (SPEC §8.4, B4): deny by default, check provider and email.
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

select is(public.before_user_created('{"user":{"email":"a0123@tec.mx","app_metadata":{"provider":"azure"}}}'),
    '{}'::jsonb, 'a Tec address through Tec''s SSO provider signs up');
select is(public.before_user_created('{"user":{"email":"A0123@TEC.MX","app_metadata":{"provider":"azure"}}}'),
    '{}'::jsonb, 'the email is compared case-insensitively');
select ok(public.before_user_created('{"user":{"email":"a0123@tec.mx","app_metadata":{"provider":"email"}}}') ? 'error',
    'a password sign-up on a Tec address is refused');
select ok(public.before_user_created('{"user":{"email":"a0123@mail.tec.mx","app_metadata":{"provider":"azure"}}}') ? 'error',
    'a subdomain is not the campus domain');
select ok(public.before_user_created('{"user":{"email":"someone@gmail.com","app_metadata":{"provider":"azure"}}}') ? 'error',
    'another organization''s account is refused');
select ok(public.before_user_created('{"user":{"email":"x@demo.masuno.invalid","app_metadata":{"provider":"email"}}}') ? 'error',
    'nobody signs up on the demo campus by domain');
select is(public.before_user_created('{"user":{"email":"official.masuno.app+review1@gmail.com","app_metadata":{"provider":"email"}}}'),
    '{}'::jsonb, 'an allowlisted review account signs up with a password');

update public.universities set signup_enabled = false where email_domain = 'tec.mx';
select ok(public.before_user_created('{"user":{"email":"a0123@tec.mx","app_metadata":{"provider":"azure"}}}') ? 'error',
    'a closed campus takes no new accounts');

select is(public.before_user_created('{"user":{"email":"x@gmail.com"}}') -> 'error' ->> 'message',
    'email_not_allowed', 'the rejection carries the code the app maps');

select * from finish();
rollback;
