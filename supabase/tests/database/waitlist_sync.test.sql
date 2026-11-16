-- One waitlist (SPEC N38): the website's joins through `waitlist_join`, the push to the Sheet, the
-- hourly `waitlist_export`, an app sign-up keeping a website place, pre-approval, places in line, and
-- who can call what. Pushes are read from pg_net's queue, which nothing sends inside this transaction.
begin;
create extension if not exists pgtap with schema extensions;
select plan(55);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true)
$$;
-- Requests queued for the Sheet's URL, and the body of the latest one.
create function pg_temp.sync_pushes() returns bigint language sql as $$
    select count(*) from net.http_request_queue where url = 'https://script.google.com/macros/s/test/exec'
$$;
create function pg_temp.last_sync() returns jsonb language sql as $$
    select convert_from(body, 'utf8')::jsonb from net.http_request_queue
    where url = 'https://script.google.com/macros/s/test/exec' order by id desc limit 1
$$;
create function pg_temp.queued() returns bigint language sql as $$
    select count(*) from net.http_request_queue
$$;
create function pg_temp.request(p_email text) returns private.signup_requests language sql as $$
    select * from private.signup_requests where email = p_email
$$;

-- Not set up yet: no secret or URL in Vault.
create temp table q0 on commit drop as select pg_temp.queued() as n;
select is(public.waitlist_join('a-secret-that-is-long-enough-0123456789', 'a1@tec.mx', now(), 'website'),
    '{"ok": false, "error": "bad_secret"}'::jsonb, 'without a secret in Vault, every join is refused');
select is(public.waitlist_export('a-secret-that-is-long-enough-0123456789'), '[]'::jsonb, 'and the export is empty');
select lives_ok($$
    select public.before_user_created('{"user":{"email":"early@tec.mx","app_metadata":{"provider":"email"}}}');
    select public.before_user_created('{"user":{"email":"gone@tec.mx","app_metadata":{"provider":"email"}}}');
    select private.approve_signup('early@tec.mx');
    select private.reject_signup('gone@tec.mx');
$$, 'without the Vault entries, sign-ups, approvals and rejections still work');
select is(pg_temp.queued() - (select n from q0), 0::bigint, 'and nothing is sent anywhere');

select vault.create_secret('test-waitlist-secret-0123456789abcdef', 'waitlist_sync_secret');
select vault.create_secret('https://script.google.com/macros/s/test/exec', 'waitlist_sync_url');

-- A wrong secret changes nothing.
select is(public.waitlist_join('wrong-secret-wrong-secret-wrong-secret', 'a2@tec.mx', now(), 'website'),
    '{"ok": false, "error": "bad_secret"}'::jsonb, 'a wrong secret is refused');
select is(public.waitlist_join(null, 'a2@tec.mx', now(), 'website') ->> 'error', 'bad_secret', 'so is none');
select is((select count(*) from private.signup_requests where email = 'a2@tec.mx'), 0::bigint, 'and nothing is stored');
select is(public.waitlist_export('wrong-secret-wrong-secret-wrong-secret'), '[]'::jsonb, 'the export with a wrong secret is empty');

-- Only school emails at an open campus get a request.
select is(public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'someone@gmail.com', now(), 'website'),
    '{"ok": true, "status": "not_school", "position": null}'::jsonb, 'a non-school email is not_school');
select is(public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'x@demo.masuno.invalid', now(), 'website') ->> 'status',
    'not_school', 'so is the demo campus');
select is(public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'a b@tec.mx', now(), 'website') ->> 'status',
    'not_school', 'and anything that isn''t an email');
select is(public.waitlist_join('test-waitlist-secret-0123456789abcdef', repeat('a', 250) || '@tec.mx', now(), 'website') ->> 'status',
    'not_school', 'or is longer than 254 characters');
select is((select count(*) from private.signup_requests where email in ('someone@gmail.com', 'x@demo.masuno.invalid', 'a b@tec.mx')),
    0::bigint, 'none of them is stored');
select is(public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'a3@tec.mx', now(), 'app'),
    '{"ok": false, "error": "invalid_input"}'::jsonb, 'the website can''t claim an app sign-up');

-- Wendy joins on the website.
create temp table q1 on commit drop as select pg_temp.sync_pushes() as n;
select is(public.waitlist_join('test-waitlist-secret-0123456789abcdef', ' Wendy@Tec.MX ', '2026-11-10T10:00:00Z', 'website'),
    '{"ok": true, "status": "waiting", "position": 1}'::jsonb, 'a website join is waiting, with a place');
select ok((select source = 'website' and requested_at = '2026-11-10T10:00:00Z' and approved_at is null
           from pg_temp.request('wendy@tec.mx')), 'as a website request at the join time');
select is(pg_temp.sync_pushes() - (select n from q1), 1::bigint, 'and the Sheet is sent it');
select is(pg_temp.last_sync(), jsonb_build_object('action', 'sync', 'secret', 'test-waitlist-secret-0123456789abcdef', 'rows',
    '[{"email": "wendy@tec.mx", "status": "waiting", "requested_at": "2026-11-10T10:00:00Z", "approved_at": null,
       "source": "website", "invited_by": null, "position": 1}]'::jsonb), 'in the agreed shape');

select is(public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'wendy@tec.mx', '2026-11-12T10:00:00Z', 'website') ->> 'status',
    'waiting', 'joining again later is fine');
select is((pg_temp.request('wendy@tec.mx')).requested_at, '2026-11-10T10:00:00Z'::timestamptz, 'and keeps the first time');
select is(pg_temp.sync_pushes() - (select n from q1), 1::bigint, 'so nothing new is sent');
select public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'wendy@tec.mx', '2026-11-08T10:00:00Z', 'website');
select is((pg_temp.request('wendy@tec.mx')).requested_at, '2026-11-08T10:00:00Z'::timestamptz, 'an earlier join moves her up');

select public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'future@tec.mx', now() + interval '1 day', 'website');
select public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'old@tec.mx', '1970-01-01T00:00:00Z', 'website');
select is((pg_temp.request('future@tec.mx')).requested_at, now(), 'a join time in the future counts as now');
select is((pg_temp.request('old@tec.mx')).requested_at, now(), 'so does one from before the waitlist existed');

-- Anton signs up in the app the day after Wendy's website join.
insert into auth.users (id, email) values
    ('a0000000-0000-4000-8000-00000000000a', 'anton@tec.mx'),
    ('f0000000-0000-4000-8000-00000000000f', 'future@tec.mx');
select public.before_user_created('{"user":{"email":"anton@tec.mx","app_metadata":{"provider":"email"}}}');
update private.signup_requests set requested_at = '2026-11-09T00:00:00Z' where email = 'anton@tec.mx';

-- Places agree between the website and the app: Wendy, Anton, then future and old (same time, by email).
select is(public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'anton@tec.mx', '2026-11-13T00:00:00Z', 'website'),
    '{"ok": true, "status": "waiting", "position": 2}'::jsonb, 'an app sign-up joining on the website later keeps its place');
select is((pg_temp.request('anton@tec.mx')).source, 'app', 'and stays an app request');
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select is(public.waitlist_position(), 2, 'the app shows the same place');
select pg_temp.act_as('f0000000-0000-4000-8000-00000000000f');
select is(public.waitlist_position(), 3, 'website joins count in the app''s line');
reset role;
select is(public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'future@tec.mx', now(), 'website') -> 'position',
    '3'::jsonb, 'and the website gets the same answer');

-- Wendy signs up in the app: she keeps her place and waits, and now the team hears about her.
select vault.create_secret('https://discord.example/api/webhooks/test', 'signup_alert_webhook_url');
select is(public.before_user_created('{"user":{"email":"wendy@tec.mx","app_metadata":{"provider":"email"}}}'),
    '{}'::jsonb, 'a website email signs up in the app');
select ok((select source = 'website' and requested_at = '2026-11-08T10:00:00Z' from pg_temp.request('wendy@tec.mx')),
    'and keeps its website request and time');
select is((select convert_from(body, 'utf8')::jsonb ->> 'content' from net.http_request_queue
           where url = 'https://discord.example/api/webhooks/test' order by id desc limit 1),
    E'New sign-up waiting for approval: wendy@tec.mx\nApprove: `select private.approve_signup(''wendy@tec.mx'');`\nReject: `select private.reject_signup(''wendy@tec.mx'');`\nRun one in the Supabase SQL editor.',
    'the team gets the approval alert now there''s an account');
create temp table q2 on commit drop as select pg_temp.queued() as n;
select public.before_user_created('{"user":{"email":"anton@tec.mx","app_metadata":{"provider":"email"}}}');
select is(pg_temp.queued() - (select n from q2), 0::bigint, 'an app request that''s already waiting isn''t alerted twice');
insert into auth.users (id, email) values ('e0000000-0000-4000-8000-00000000000e', 'wendy@tec.mx');
set local role authenticated;
select pg_temp.act_as('e0000000-0000-4000-8000-00000000000e');
select is(public.signup_status(), 'pending', 'her account waits');
select is(public.waitlist_position(), 1, 'first in line, from her website join');
reset role;

-- Vic joined on the website and the team approved him before he had an account.
select public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'vic@tec.mx', '2026-11-11T00:00:00Z', 'website');
select is(private.approve_signup('vic@tec.mx'), 'Approved vic@tec.mx', 'a website email can be approved in advance');
create temp table q3 on commit drop as select count(*) as n from net.http_request_queue where url like 'https://discord.example/%';
select is(public.before_user_created('{"user":{"email":"vic@tec.mx","app_metadata":{"provider":"email"}}}'), '{}'::jsonb,
    'then he signs up in the app');
select is((select count(*) from net.http_request_queue where url like 'https://discord.example/%') - (select n from q3), 0::bigint,
    'with no approval alert');
insert into auth.users (id, email) values ('c0000000-0000-4000-8000-00000000000c', 'vic@tec.mx');
set local role authenticated;
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select is(public.signup_status(), 'approved', 'and goes straight in');
select public.complete_profile('Vic', 'Paz', 2027, array['soccer'], 'es');
reset role;
select is(pg_temp.last_sync() -> 'rows', jsonb_build_array(jsonb_build_object('email', 'vic@tec.mx', 'status', 'member',
    'requested_at', '2026-11-11T00:00:00Z', 'approved_at', private.iso_utc(now()), 'source', 'website', 'invited_by', null,
    'position', null)), 'his new profile tells the Sheet he''s in the app');
select is(public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'vic@tec.mx', now(), 'website'),
    '{"ok": true, "status": "member", "position": null}'::jsonb, 'and a website join for him says so');

-- The hourly export.
update private.signup_requests set invited_by = 'c0000000-0000-4000-8000-00000000000c' where email = 'anton@tec.mx';
create temp table export on commit drop as
select e from jsonb_array_elements(public.waitlist_export('test-waitlist-secret-0123456789abcdef')) e;
select is((select jsonb_object_agg(e ->> 'email', e ->> 'status') from export
           where e ->> 'email' in ('wendy@tec.mx', 'anton@tec.mx', 'vic@tec.mx', 'early@tec.mx')),
    '{"wendy@tec.mx": "waiting", "anton@tec.mx": "waiting", "vic@tec.mx": "member", "early@tec.mx": "approved"}'::jsonb,
    'the export has every request''s status');
select ok((select bool_and((e -> 'position') = coalesce(to_jsonb(private.waitlist_place(e ->> 'email')), 'null'::jsonb)
                           and ((e ->> 'status') = 'waiting') = ((e ->> 'position') is not null)) from export),
    'with the same places as the app, for waiting rows only');
select is((select e ->> 'invited_by' from export where e ->> 'email' = 'anton@tec.mx'), 'Vic P.', 'and who invited whom');
select is((select array_agg(k order by k) from export, jsonb_object_keys(e) k where e ->> 'email' = 'wendy@tec.mx'),
    array['approved_at', 'email', 'invited_by', 'position', 'requested_at', 'source', 'status'], 'in the push''s shape');

-- Counting wrong invite codes changes nothing the Sheet shows; a rejection removes the row.
create temp table q4 on commit drop as select pg_temp.sync_pushes() as n;
update private.signup_requests set invite_attempts = 1, invite_attempt_at = now() where email = 'anton@tec.mx';
select is(pg_temp.sync_pushes() - (select n from q4), 0::bigint, 'a wrong invite code sends nothing');
select private.reject_signup('old@tec.mx');
select is(pg_temp.last_sync() -> 'rows' -> 0 ->> 'status', 'removed', 'a rejected request is removed from the Sheet');

-- One statement approving everyone sends one request with every row.
create temp table q5 on commit drop as
select pg_temp.sync_pushes() as n, (select count(*)::int from private.signup_requests where approved_at is null) as waiting;
update private.signup_requests set approved_at = now() where approved_at is null;
select ok(pg_temp.sync_pushes() - (select n from q5) = 1 and jsonb_array_length(pg_temp.last_sync() -> 'rows') = (select waiting from q5)
    and (select bool_and(r ->> 'status' = 'approved') from jsonb_array_elements(pg_temp.last_sync() -> 'rows') r),
    'approving everyone at once sends the Sheet one update with every row');

-- Allowlisted addresses and accounts without a request never wait, so the website can't make them.
insert into public.auth_allowlist (email, note, university_id)
select 'staff@tec.mx', 'test', id from public.universities where email_domain = 'tec.mx';
insert into auth.users (id, email) values ('d0000000-0000-4000-8000-00000000000d', 'sso@tec.mx');
select is(array[public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'staff@tec.mx', now(), 'website') ->> 'status',
                public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'sso@tec.mx', now(), 'website') ->> 'status'],
    array['approved', 'approved'], 'an allowlisted address or an account with no request is already in');
select is((select count(*) from private.signup_requests where email in ('staff@tec.mx', 'sso@tec.mx')), 0::bigint,
    'and gets no request that would make it wait');

-- Who can call what: anon only the two secret-checked RPCs.
set local role anon;
select pg_temp.act_as(null);
select is(public.waitlist_join('wrong-secret-wrong-secret-wrong-secret', 'a4@tec.mx', now(), 'website') ->> 'error',
    'bad_secret', 'anon can call waitlist_join, and a wrong secret is refused');
select ok(jsonb_array_length(public.waitlist_export('test-waitlist-secret-0123456789abcdef')) > 0,
    'anon can call waitlist_export with the secret');
select throws_ok($$ select private.waitlist_rows(array['wendy@tec.mx']) $$, '42501', null, 'but nothing private');
set local role authenticated;
select throws_ok($$ select public.waitlist_join('test-waitlist-secret-0123456789abcdef', 'a5@tec.mx', now(), 'website') $$,
    '42501', null, 'signed-in apps can''t call it at all');
reset role;
select is((select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('public', 'private') and has_function_privilege('anon', p.oid, 'execute')
             and p.proname in ('waitlist_join', 'waitlist_export', 'waitlist_position', 'before_user_created', 'request_signup',
                               'waitlist_rows', 'waitlist_place', 'waitlist_secret_ok', 'send_waitlist_sync', 'open_campus_email')),
    array['waitlist_export', 'waitlist_join'], 'of the waitlist functions, anon can run exactly the two RPCs');

select * from finish();
rollback;
