-- Delivery lifecycle regressions: assertions include post-completion state, not just row counts.
begin;
create extension if not exists pgtap with schema extensions;
select plan(30);
insert into auth.users (id, email) values ('18000000-0000-4000-8000-000000000001', 'delivery-test@tec.mx');
insert into public.profiles (id, university_id, first_name, last_name, grad_year, guidelines_accepted_at)
select '18000000-0000-4000-8000-000000000001', id, 'Delivery', 'Test', 2027, now()
from public.universities where email_domain = 'tec.mx';
update public.universities set timezone = (
    select name from pg_timezone_names where extract(hour from now() at time zone name) = 12 limit 1
) where email_domain = 'tec.mx';
update public.app_config set value = 'true' where key in ('push_enabled', 'chat_enabled');
insert into private.device_tokens (token, user_id, environment, app_version)
values ('delivery-test-token', '18000000-0000-4000-8000-000000000001', 'sandbox', '1.0');
-- Other fixtures must not consume this test's claim limit.
update private.notification_outbox set not_before = now() + interval '30 days';

create function pg_temp.enqueue(p_kind text, p_key text, p_once boolean default false)
returns void language sql as $$
    select private.enqueue_notification('18000000-0000-4000-8000-000000000001', p_kind, null,
        '{"count":1,"body":"message"}', p_key, null, now(), now() + interval '1 day', p_once, 'keep')
$$;
create function pg_temp.complete(p_outcome text) returns void language sql as $$
    select private.complete_notifications(coalesce(jsonb_agg(jsonb_build_object('id', id, 'outcome', p_outcome)), '[]'))
    from private.notification_outbox
    where user_id = '18000000-0000-4000-8000-000000000001' and locked_at is not null and sent_at is null
$$;
create function pg_temp.used() returns bigint language sql as $$
    select private.notification_budget_used('18000000-0000-4000-8000-000000000001',
        date_trunc('day', now() at time zone u.timezone) at time zone u.timezone)
    from public.universities u where email_domain = 'tec.mx'
$$;

-- Repeated scheduler ticks must not request a second delivery of the same occurrence.
select pg_temp.enqueue(kind, kind || ':first-occurrence', true) from unnest(array['reminder', 'saved_soon']) kind;
select is((select count(*) from private.claim_notifications(100)), 2::bigint, 'both once-only kinds are claimed');
select pg_temp.enqueue(kind, kind || ':first-occurrence', true) from unnest(array['reminder', 'saved_soon']) kind;
select ok((select bool_and(not resend) from private.notification_outbox where merge_key like '%:first-occurrence'),
    'another tick does not arm resend for either once-only kind');
select pg_temp.complete('sent');
select ok((select bool_and(sent_at is not null and not resend and locked_at is null)
    from private.notification_outbox where merge_key like '%:first-occurrence'), 'once-only sends finish after one delivery');
select is_empty($$select id from private.claim_notifications(100)$$, 'neither once-only row can be claimed again');
select pg_temp.enqueue('reminder', 'reminder:first-occurrence', true);
select is((select count(*) from private.notification_outbox where merge_key = 'reminder:first-occurrence'),
    1::bigint, 'a later tick does not recreate a completed occurrence');
select pg_temp.enqueue('reminder', 'reminder:changed-starts-at', true);
select is((select count(*) from private.claim_notifications(100)), 1::bigint, 'a different starts-at key still sends');

-- A recovered snapshot already includes merges from the abandoned lease.
delete from private.notification_outbox where user_id = '18000000-0000-4000-8000-000000000001';
select pg_temp.enqueue('chat_message', 'chat:recover');
select private.claim_notifications(100);
select pg_temp.enqueue('chat_message', 'chat:recover');
select ok((select resend from private.notification_outbox where merge_key = 'chat:recover'), 'a new mid-send message arms resend');
update private.notification_outbox set locked_at = now() - interval '11 minutes' where merge_key = 'chat:recover';
select is((select (payload->>'count')::int from private.claim_notifications(100)), 2, 'recovered claim contains both messages');
select ok((select not resend from private.notification_outbox where merge_key = 'chat:recover'), 'claim consumes the previous attempt resend flag');
select pg_temp.complete('sent');
select is_empty($$select id from private.claim_notifications(100)$$, 'successful recovered snapshot is not sent twice');

-- A genuinely new merge after recovery must still trigger exactly one further delivery.
delete from private.notification_outbox where user_id = '18000000-0000-4000-8000-000000000001';
select pg_temp.enqueue('chat_message', 'chat:new-after-recovery');
select private.claim_notifications(100);
select pg_temp.enqueue('chat_message', 'chat:new-after-recovery');
update private.notification_outbox set locked_at = now() - interval '11 minutes' where merge_key = 'chat:new-after-recovery';
select private.claim_notifications(100);
select pg_temp.enqueue('chat_message', 'chat:new-after-recovery');
select pg_temp.complete('sent');
select ok((select sent_at is null and locked_at is null and not resend from private.notification_outbox
    where merge_key = 'chat:new-after-recovery'), 'a merge during the recovered attempt remains queued');
select is((select (payload->>'count')::int from private.claim_notifications(100)), 3, 'next claim contains the new third message');
select pg_temp.complete('sent');
select is_empty($$select id from private.claim_notifications(100)$$, 'the third-message snapshot finishes without another resend');

-- In-flight rows reserve the same budget as completed deliveries.
delete from private.notification_outbox where user_id = '18000000-0000-4000-8000-000000000001';
select pg_temp.enqueue('interest_match', 'interest:' || i) from generate_series(1, 5) i;
select is((select count(*) from private.claim_notifications(100)), 2::bigint, 'one batch claims only two interest notifications');
select is(pg_temp.used(), 2::bigint, 'the two active leases reserve two slots');
select pg_temp.complete('sent');
select is((select count(*) from private.notification_outbox where sent_at is not null and kind = 'interest_match'),
    2::bigint, 'completion records no more than two interest sends');
select is(pg_temp.used(), 2::bigint, 'completion replaces reservations without double charging');

-- Mixed ordinary kinds share the six-per-day budget; chat and time-sensitive kinds are exempt.
delete from private.notification_outbox where user_id = '18000000-0000-4000-8000-000000000001';
select pg_temp.enqueue('interest_match', 'mixed-interest:' || i) from generate_series(1, 2) i;
select pg_temp.enqueue(case when i % 2 = 0 then 'game_changed' else 'host_update' end, 'mixed:' || i)
from generate_series(1, 7) i;
select is((select count(*) from private.claim_notifications(100)), 6::bigint, 'mixed batch reserves at most six slots');
select pg_temp.enqueue('chat_message', 'exempt:chat');
select pg_temp.enqueue('reminder', 'exempt:reminder', true);
select is((select count(*) from private.claim_notifications(100)), 2::bigint, 'chat and reminders still claim when ordinary budget is full');
select pg_temp.complete('sent');
select is(pg_temp.used(), 6::bigint, 'exempt sends do not charge the ordinary budget');

-- Failed attempts release their reservation; a retry reserves one slot again, not two.
delete from private.notification_outbox where user_id = '18000000-0000-4000-8000-000000000001';
select pg_temp.enqueue('interest_match', 'release');
select private.claim_notifications(100);
select pg_temp.complete('release');
select is(pg_temp.used(), 0::bigint, 'release frees the lease budget');
select private.claim_notifications(100);
select is(pg_temp.used(), 1::bigint, 'released row reserves one slot when reclaimed');
select pg_temp.complete('retry');
select is(pg_temp.used(), 0::bigint, 'retry backoff frees the active lease budget');
update private.notification_outbox set not_before = now() where merge_key = 'release';
select private.claim_notifications(100);
select pg_temp.complete('sent');
select is(pg_temp.used(), 1::bigint, 'successful retry counts once');
select pg_temp.enqueue('interest_match', 'drop');
select private.claim_notifications(100);
select pg_temp.complete('drop');
select is(pg_temp.used(), 1::bigint, 'dropped attempt does not consume an additional slot');

-- A successful delivery followed by resend still consumes a slot even while sent_at is NULL.
delete from private.notification_outbox where user_id = '18000000-0000-4000-8000-000000000001';
select pg_temp.enqueue('host_update', 'merged-host');
select private.claim_notifications(100);
select pg_temp.enqueue('host_update', 'merged-host');
select pg_temp.complete('sent');
select is(pg_temp.used(), 1::bigint, 'successful mid-merge delivery is retained in budget history');
select private.claim_notifications(100);
select is(pg_temp.used(), 2::bigint, 'its next attempt reserves a separate slot');
select pg_temp.complete('sent');
select is(pg_temp.used(), 2::bigint, 'final completion retains exactly two successful deliveries');

set local role authenticated;
select throws_ok($$select * from private.notification_resend_deliveries$$, '42501', null,
    'clients cannot read resend delivery history');
select throws_ok($$select private.notification_budget_used(null, now())$$, '42501', null,
    'clients cannot inspect another user budget');
reset role;
select * from finish();
rollback;
