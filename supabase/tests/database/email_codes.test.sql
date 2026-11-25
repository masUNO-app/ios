-- Email codes (SPEC N39, 20261128000000): a request starts when the emailed code is entered, not
-- when the account is created; unverified accounts wait; `signup_auto_approve` opens sign-up; the
-- hourly clean-up of accounts that never verified; and who can call what. Supabase Auth is stood in
-- for by writing auth.users the way it does: a password account is created with no confirmation, the
-- code email sets confirmation_sent_at (or recovery_sent_at), and entering it sets email_confirmed_at.
begin;
create extension if not exists pgtap with schema extensions;
select plan(32);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true)
$$;
create function pg_temp.request(p_email text) returns private.signup_requests language sql as $$
    select * from private.signup_requests where email = p_email
$$;
-- What Supabase Auth writes when a password sign-up is created and its code is emailed.
create function pg_temp.sign_up(p_id uuid, p_email text) returns void language sql as $$
    insert into auth.users (id, email, raw_app_meta_data, confirmation_sent_at)
    values (p_id, p_email, '{"provider": "email", "providers": ["email"]}', now())
$$;
-- And when the code is entered.
create function pg_temp.enter_code(p_id uuid) returns void language sql as $$
    update auth.users set email_confirmed_at = now() where id = p_id
$$;
create function pg_temp.alerts() returns bigint language sql as $$
    select count(*) from net.http_request_queue where url = 'https://discord.example/api/webhooks/codes'
$$;
create function pg_temp.last_alert() returns text language sql as $$
    select convert_from(body, 'utf8')::jsonb ->> 'content' from net.http_request_queue
    where url = 'https://discord.example/api/webhooks/codes' order by id desc limit 1
$$;

select vault.create_secret('https://discord.example/api/webhooks/codes', 'signup_alert_webhook_url');
select is(private.signup_auto_approve(), false, 'sign-up starts invite-only');

-- Ana signs up. Until she enters her code there's no request, and her account can do nothing.
select is(public.before_user_created('{"user":{"email":"ana@tec.mx","app_metadata":{"provider":"email"}}}'), '{}'::jsonb,
    'a school address with a password is let through');
select pg_temp.sign_up('a0000000-0000-4000-8000-00000000000a', 'ana@tec.mx');
select is((select count(*) from private.signup_requests where email = 'ana@tec.mx'), 0::bigint,
    'and takes no place in line before the code');
select is(pg_temp.alerts(), 0::bigint, 'and the team hears nothing');
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select is(public.signup_status(), 'unverified', 'the app sees the account needs its code');
select throws_ok($$ select public.complete_profile('Ana', 'Ruiz', 2028, array['soccer'], 'es') $$, 'pending_approval',
    'an unverified account can''t create a profile');
select throws_ok($$ select private.signup_verified('ana@tec.mx') $$, '42501', null, 'and can''t verify itself');
reset role;

-- She enters the code: verified, waiting, and the team gets the approval alert.
select pg_temp.enter_code('a0000000-0000-4000-8000-00000000000a');
select ok((select verified_at is not null and approved_at is null and source = 'app' from pg_temp.request('ana@tec.mx')),
    'entering the code makes a verified request that waits');
select is(pg_temp.alerts(), 1::bigint, 'and alerts the team once');
select ok(pg_temp.last_alert() like 'New sign-up waiting for approval (email verified): a•••@tec.mx%',
    'saying the address is verified, without the address');
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select is(public.signup_status(), 'pending', 'the app moves on to the waitlist');
reset role;
update auth.users set email_confirmed_at = null where id = 'a0000000-0000-4000-8000-00000000000a';
select pg_temp.enter_code('a0000000-0000-4000-8000-00000000000a');
select is(pg_temp.alerts(), 1::bigint, 'verifying again changes nothing');

-- Accounts we never emailed a code to don't get a request: the dashboard's "Auto confirm" and SSO.
insert into auth.users (id, email, raw_app_meta_data) values
    ('d0000000-0000-4000-8000-00000000000d', 'dash@tec.mx', '{"provider": "email"}'),
    ('e0000000-0000-4000-8000-00000000000e', 'sso@tec.mx', '{"provider": "azure"}');
update auth.users set confirmation_sent_at = now() where id = 'e0000000-0000-4000-8000-00000000000e';
select pg_temp.enter_code('d0000000-0000-4000-8000-00000000000d');
select pg_temp.enter_code('e0000000-0000-4000-8000-00000000000e');
select is((select count(*) from private.signup_requests where email in ('dash@tec.mx', 'sso@tec.mx')), 0::bigint,
    'a dashboard or SSO account goes straight in, with no request');
set local role authenticated;
select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select is(public.signup_status(), 'approved', 'and is approved');
reset role;

-- Wendy joined on the website first; verifying in the app keeps her place.
insert into private.signup_requests (email, requested_at, source) values ('wendy@tec.mx', '2026-11-01T00:00:00Z', 'website');
select pg_temp.sign_up('10000000-0000-4000-8000-000000000001', 'wendy@tec.mx');
select pg_temp.enter_code('10000000-0000-4000-8000-000000000001');
select ok((select source = 'website' and requested_at = '2026-11-01T00:00:00Z' and verified_at is not null and approved_at is null
           from pg_temp.request('wendy@tec.mx')), 'a website request keeps its place and becomes verified');

-- Rosa never entered her sign-up code but reset her password by code, which proves the inbox too.
insert into auth.users (id, email, raw_app_meta_data, recovery_sent_at)
values ('20000000-0000-4000-8000-000000000002', 'rosa@tec.mx', '{"provider": "email"}', now());
select pg_temp.enter_code('20000000-0000-4000-8000-000000000002');
select ok((select verified_at is not null and approved_at is null from pg_temp.request('rosa@tec.mx')),
    'a reset code verifies the address as well');

-- An allowlisted address that proves its inbox goes straight in, quietly.
insert into public.auth_allowlist (email, note, university_id)
select 'staff@tec.mx', 'test', id from public.universities where email_domain = 'tec.mx';
create temp table q1 on commit drop as select pg_temp.alerts() as n;
select pg_temp.sign_up('30000000-0000-4000-8000-000000000003', 'staff@tec.mx');
select pg_temp.enter_code('30000000-0000-4000-8000-000000000003');
select ok((pg_temp.request('staff@tec.mx')).approved_at is not null, 'an allowlisted address is approved once verified');
select is(pg_temp.alerts() - (select n from q1), 0::bigint, 'with no alert');

-- Opening sign-up lets in everyone verified and waiting, but not a website join with no account.
insert into private.signup_requests (email, source) values ('later@tec.mx', 'website');
select is(private.set_signup_auto_approve(true), 'Sign-up is open: verified accounts go straight in. Let in 3 waiting',
    'the team opens sign-up');
select is(private.signup_auto_approve(), true, 'and the switch is on');
select is((select count(*) from private.signup_requests where email in ('ana@tec.mx', 'wendy@tec.mx', 'rosa@tec.mx') and approved_at is not null),
    3::bigint, 'everyone verified and waiting is in');
select is((select count(*)::int from private.notification_outbox
           where user_id = 'a0000000-0000-4000-8000-00000000000a' and kind = 'signup_approved'), 1,
    'and told so');
select is((pg_temp.request('later@tec.mx')).approved_at, null, 'a website join without an account still waits');

-- While it's open, entering the code is enough, and the team gets an FYI.
select pg_temp.sign_up('40000000-0000-4000-8000-000000000004', 'oscar@tec.mx');
select pg_temp.enter_code('40000000-0000-4000-8000-000000000004');
select ok((pg_temp.request('oscar@tec.mx')).approved_at is not null, 'with sign-up open, verifying gets you in');
select is(pg_temp.last_alert(), 'o•••@tec.mx joined: email verified, and sign-ups are open.', 'and the team gets an FYI');
set local role authenticated;
select pg_temp.act_as('40000000-0000-4000-8000-000000000004');
select lives_ok($$ select public.complete_profile('Oscar', 'Vega', 2027, array['soccer'], 'es') $$, 'and the profile saves');
reset role;

-- Closing it again: new accounts wait; nobody already in is touched.
select is(private.set_signup_auto_approve(false), 'Sign-up is invite-only: new verified accounts wait for approval',
    'the team closes sign-up');
select pg_temp.sign_up('50000000-0000-4000-8000-000000000005', 'pia@tec.mx');
select pg_temp.enter_code('50000000-0000-4000-8000-000000000005');
select is((pg_temp.request('pia@tec.mx')).approved_at, null, 'after closing, a verified account waits again');
select ok((pg_temp.request('oscar@tec.mx')).approved_at is not null, 'and those let in stay in');

-- The hourly clean-up: a day-old account that never verified is deleted, unless it holds a place.
select pg_temp.sign_up('60000000-0000-4000-8000-000000000006', 'stale@tec.mx');
select pg_temp.sign_up('70000000-0000-4000-8000-000000000007', 'fresh@tec.mx');
select pg_temp.sign_up('80000000-0000-4000-8000-000000000008', 'later@tec.mx');
update auth.users set created_at = now() - interval '2 days'
where id in ('60000000-0000-4000-8000-000000000006', '80000000-0000-4000-8000-000000000008');
select is(private.delete_unverified_signups(), 1, 'one stale account is deleted');
select is((select array_agg(email order by email) from auth.users where email in ('stale@tec.mx', 'fresh@tec.mx', 'later@tec.mx')),
    array['fresh@tec.mx', 'later@tec.mx'], 'a recent one stays, and so does one holding a website place');

-- Only the team runs these.
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select throws_ok($$ select private.set_signup_auto_approve(true) $$, '42501', null, 'members can''t open sign-up');

select * from finish();
rollback;
