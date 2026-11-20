-- Ordered claims fence overlapping workers and short retries without delaying other phones.
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);
insert into auth.users (id, email) values
    ('18200000-0000-4000-8000-000000000001', 'order-one@tec.mx'),
    ('18200000-0000-4000-8000-000000000002', 'order-two@tec.mx');
insert into public.profiles (id, university_id, first_name, last_name, grad_year, guidelines_accepted_at)
select a.id, u.id, 'Order', 'Test', 2027, now()
from auth.users a cross join public.universities u
where a.id in ('18200000-0000-4000-8000-000000000001', '18200000-0000-4000-8000-000000000002')
  and u.email_domain = 'tec.mx';
update public.universities set timezone = (
    select name from pg_timezone_names where extract(hour from now() at time zone name) = 12 limit 1
) where email_domain = 'tec.mx';
update public.app_config set value = 'true' where key in ('push_enabled', 'chat_enabled');
insert into private.device_tokens (token, user_id, environment, app_version) values
    ('order-one-device', '18200000-0000-4000-8000-000000000001', 'sandbox', '1.0'),
    ('order-two-device', '18200000-0000-4000-8000-000000000002', 'sandbox', '1.0');
update private.notification_outbox set not_before = now() + interval '30 days';
create function pg_temp.enqueue_order(p_user uuid, p_key text, p_due timestamptz default now())
returns void language sql as $$
    select private.enqueue_notification(p_user, 'chat_message', null, '{"count":1,"body":"Hi"}',
        p_key, null, p_due, now() + interval '1 day', false, 'keep')
$$;
select pg_temp.enqueue_order('18200000-0000-4000-8000-000000000001', 'order:first');
select pg_temp.enqueue_order('18200000-0000-4000-8000-000000000001', 'order:second', now() - interval '1 minute');
select pg_temp.enqueue_order('18200000-0000-4000-8000-000000000002', 'order:other');
create temp table first_attempt as select * from private.claim_notifications_v2(1);
select is((select id from first_attempt), (select id from private.notification_outbox where merge_key = 'order:first'),
    'creation order wins over differing due timestamps');
create temp table other_attempt as select * from private.claim_notifications_v2(100);
select is((select count(*) from other_attempt), 1::bigint, 'overlapping drain leaves the active recipient alone');
select is((select user_id from other_attempt), '18200000-0000-4000-8000-000000000002'::uuid,
    'a different phone continues while the first recipient is leased');
select private.complete_notifications_v2(jsonb_agg(jsonb_build_object('id', id, 'claim_token', claim_token, 'outcome', 'sent')))
from other_attempt;
select private.complete_notifications_v2(jsonb_agg(jsonb_build_object('id', id, 'claim_token', claim_token, 'outcome', 'retry')))
from first_attempt;
select is((select not_before from private.notification_outbox where merge_key = 'order:first'),
    now() + interval '5 seconds', 'first retry waits five seconds instead of two minutes');
select is_empty($$select id from private.claim_notifications_v2(100)$$, 'a later alert cannot overtake a retry in backoff');
update private.notification_outbox set not_before = now() where merge_key = 'order:first';
create temp table retry_attempt as select * from private.claim_notifications_v2(100);
select is((select count(*) from retry_attempt), 2::bigint, 'both rows are claimed in one ordered batch after backoff');
select is((select array_agg(id) from retry_attempt),
    (select array_agg(id order by id) from private.notification_outbox where merge_key in ('order:first', 'order:second')),
    'the batch preserves order');
select private.complete_notifications_v2(jsonb_agg(jsonb_build_object('id', r.id, 'claim_token', r.claim_token,
    'outcome', 'retry', 'error', case when o.merge_key = 'order:second' then 'earlier_notification_pending' else 'apns_timeout' end)))
from retry_attempt r join private.notification_outbox o on o.id = r.id;
select is((select attempts from private.notification_outbox where merge_key = 'order:first'), 2, 'failed transport consumes an attempt');
select is((select attempts from private.notification_outbox where merge_key = 'order:second'), 0, 'an unsent later row does not consume an attempt');
select is((select not_before from private.notification_outbox where merge_key = 'order:first'),
    now() + interval '10 seconds', 'second retry also stays below a minute');
select is_empty($$select id from private.claim_notifications_v2(100)$$, 'released later row still waits behind the failed transport');
update private.notification_outbox set not_before = now() where merge_key = 'order:first';
create temp table success_attempt as select * from private.claim_notifications_v2(100);
select private.complete_notifications_v2(jsonb_agg(jsonb_build_object('id', id, 'claim_token', claim_token, 'outcome', 'sent')))
from success_attempt;
select ok((select bool_and(sent_at is not null) from private.notification_outbox where merge_key in ('order:first', 'order:second')),
    'successful retries finish both rows');
select pg_temp.enqueue_order('18200000-0000-4000-8000-000000000001', 'order:scheduled', now() + interval '1 hour');
select pg_temp.enqueue_order('18200000-0000-4000-8000-000000000001', 'order:current');
select is((select id from private.claim_notifications_v2(100)),
    (select id from private.notification_outbox where merge_key = 'order:current'),
    'a future scheduled alert does not block a current one');
select ok(not has_function_privilege('authenticated', 'private.claim_notifications_ordered(integer)', 'execute'),
    'members cannot invoke the private ordered claim helper');
select ok(not has_function_privilege('service_role', 'private.claim_notifications_ordered(integer)', 'execute'),
    'service role must use the fenced public wrapper');
select * from finish();
rollback;
