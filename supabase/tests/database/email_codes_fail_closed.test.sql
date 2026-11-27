-- Email codes fail closed (20261128000100): with "Confirm email" off, or an account made in the
-- dashboard, nothing proves the inbox, so a password account waits for approval as in N36 instead of
-- getting in with no request. Supabase Auth is stood in for as in email_codes.test.sql.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true)
$$;
create function pg_temp.request(p_email text) returns private.signup_requests language sql as $$
    select * from private.signup_requests where email = p_email
$$;
create function pg_temp.last_alert() returns text language sql as $$
    select convert_from(body, 'utf8')::jsonb ->> 'content' from net.http_request_queue
    where url = 'https://discord.example/api/webhooks/closed' order by id desc limit 1
$$;
select vault.create_secret('https://discord.example/api/webhooks/closed', 'signup_alert_webhook_url');

-- "Confirm email" off: Supabase creates the account, then confirms it straight away, sending nothing.
insert into auth.users (id, email, raw_app_meta_data)
values ('a0000000-0000-4000-8000-00000000000a', 'ana@tec.mx', '{"provider": "email"}');
update auth.users set email_confirmed_at = now() where id = 'a0000000-0000-4000-8000-00000000000a';
select ok((select approved_at is null and verified_at is null from pg_temp.request('ana@tec.mx')),
    'a password account confirmed without a code gets a request that waits, not verified');
select ok(pg_temp.last_alert() like 'New sign-up waiting for approval (email NOT verified%a•••@tec.mx%',
    'and the team''s alert says the address wasn''t verified');
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select is(public.signup_status(), 'pending', 'the app shows the waitlist');
reset role;
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.complete_profile('Ana', 'Ruiz', 2028, array['soccer'], 'es') $$, 'pending_approval',
    'and the account can''t set up a profile');
reset role;

-- Opening sign-up doesn't let in an address nobody verified.
select private.set_signup_auto_approve(true);
select is((pg_temp.request('ana@tec.mx')).approved_at, null, 'opening sign-up skips unverified requests');
select private.set_signup_auto_approve(false);

-- An account created already confirmed is caught on insert.
insert into auth.users (id, email, raw_app_meta_data, email_confirmed_at)
values ('b0000000-0000-4000-8000-00000000000b', 'beto@tec.mx', '{"provider": "email"}', now());
select ok((select approved_at is null from pg_temp.request('beto@tec.mx')), 'an account confirmed at creation waits too');

-- Allowlisted addresses made in the dashboard, and SSO accounts, go straight in as before.
insert into public.auth_allowlist (email, note, university_id)
select 'staff@tec.mx', 'test', id from public.universities where email_domain = 'tec.mx';
insert into auth.users (id, email, raw_app_meta_data, email_confirmed_at) values
    ('c0000000-0000-4000-8000-00000000000c', 'staff@tec.mx', '{"provider": "email"}', now()),
    ('d0000000-0000-4000-8000-00000000000d', 'sso@tec.mx', '{"provider": "azure"}', now());
select is((select count(*) from private.signup_requests where email in ('staff@tec.mx', 'sso@tec.mx')), 0::bigint,
    'an allowlisted dashboard account or an SSO account gets no request');
set local role authenticated;
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select is(public.signup_status(), 'approved', 'the allowlisted one is in');
reset role;
set local role authenticated;
select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select is(public.signup_status(), 'approved', 'and so is the SSO one');
reset role;

-- A password account with no record at all waits, however it got here.
insert into auth.users (id, email, raw_app_meta_data, email_confirmed_at)
values ('e0000000-0000-4000-8000-00000000000e', 'orphan@tec.mx', '{"provider": "email"}', now());
delete from private.signup_requests where email = 'orphan@tec.mx';
set local role authenticated;
select pg_temp.act_as('e0000000-0000-4000-8000-00000000000e');
select is(public.signup_status(), 'pending', 'a password account with no request waits');
reset role;
select is(private.approve_signup('orphan@tec.mx'), 'Approved orphan@tec.mx', 'the team can still approve it');
set local role authenticated;
select pg_temp.act_as('e0000000-0000-4000-8000-00000000000e');
select is(public.signup_status(), 'approved', 'and then it''s in');
reset role;
select is(private.approve_signup('nobody@tec.mx'), 'Nothing to approve for nobody@tec.mx',
    'approving an address with no account and no request does nothing');

-- Members never wait, whatever their auth row looks like (5 members on dev have no confirmation).
insert into auth.users (id, email) values ('f0000000-0000-4000-8000-00000000000f', 'member@tec.mx');
set local role authenticated;
select pg_temp.act_as('f0000000-0000-4000-8000-00000000000f');
select lives_ok($$ select public.complete_profile('Mia', 'Soto', 2027, array['soccer'], 'es') $$, 'a member sets up a profile');
reset role;
update auth.users set raw_app_meta_data = '{"provider": "email"}' where id = 'f0000000-0000-4000-8000-00000000000f';
set local role authenticated;
select pg_temp.act_as('f0000000-0000-4000-8000-00000000000f');
select is(public.signup_status(), 'approved', 'a member with a password account, no confirmation and no request is still in');
reset role;

-- A code still works the N39 way: verified, waiting, verified alert.
insert into auth.users (id, email, raw_app_meta_data, confirmation_sent_at)
values ('10000000-0000-4000-8000-000000000001', 'vera@tec.mx', '{"provider": "email"}', now());
update auth.users set email_confirmed_at = now() where id = '10000000-0000-4000-8000-000000000001';
select ok((select verified_at is not null and approved_at is null from pg_temp.request('vera@tec.mx'))
          and pg_temp.last_alert() like 'New sign-up waiting for approval (email verified): v•••@tec.mx%',
    'a sign-up with a code is verified and alerted as verified');

select * from finish();
rollback;
