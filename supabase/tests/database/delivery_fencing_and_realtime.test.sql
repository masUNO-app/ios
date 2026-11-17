-- Forward protocol: expired workers cannot complete newer claims or clean up their tokens.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

create temp table broadcast_log (campus uuid, ids uuid[]);
create or replace function private.send_game_changes(p_university uuid, p_ids uuid[])
returns void language sql set search_path = '' as $$
    insert into pg_temp.broadcast_log values (p_university, p_ids)
$$;
insert into public.universities (id, name, short_name, email_domain, signup_enabled, center_lat, center_lng, timezone) values
    ('18100000-0000-4000-8000-000000000001', 'Fencing A', 'A', 'fence-a.invalid', false, 25, -100,
        (select name from pg_timezone_names where extract(hour from now() at time zone name) = 12 limit 1)),
    ('18100000-0000-4000-8000-000000000002', 'Fencing B', 'B', 'fence-b.invalid', false, 25, -100, 'UTC');
insert into auth.users (id, email) values
    ('18100000-0000-4000-8000-000000000011', 'host@fence-a.invalid'),
    ('18100000-0000-4000-8000-000000000012', 'host@fence-b.invalid'),
    ('18100000-0000-4000-8000-000000000013', 'player@fence-a.invalid');
insert into public.profiles (id, university_id, first_name, last_name, grad_year, guidelines_accepted_at)
select id, campus, 'Fence', 'Test', 2027, now() from (values
    ('18100000-0000-4000-8000-000000000011'::uuid, '18100000-0000-4000-8000-000000000001'::uuid),
    ('18100000-0000-4000-8000-000000000012'::uuid, '18100000-0000-4000-8000-000000000002'::uuid),
    ('18100000-0000-4000-8000-000000000013'::uuid, '18100000-0000-4000-8000-000000000001'::uuid)
) fixture(id, campus);
insert into public.games (id, university_id, host_id, activity_slug, title, starts_at, duration_minutes,
    ends_at, capacity, place_name, place_address, lat, lng)
select game, campus, host, 'basketball', 'Fence game', now() + interval '1 day', 60,
    now() + interval '1 day 1 hour', 4, 'Court', 'Test', 25, -100 from (values
    ('18100000-0000-4000-8000-000000000021'::uuid, '18100000-0000-4000-8000-000000000001'::uuid, '18100000-0000-4000-8000-000000000011'::uuid),
    ('18100000-0000-4000-8000-000000000022'::uuid, '18100000-0000-4000-8000-000000000002'::uuid, '18100000-0000-4000-8000-000000000012'::uuid)
) fixture(game, campus, host);
insert into public.rsvps (event_id, user_id, role)
select id, host_id, 'host' from public.games where id in
    ('18100000-0000-4000-8000-000000000021', '18100000-0000-4000-8000-000000000022');
truncate broadcast_log;
update public.rsvps set chat_muted = true where user_id in
    ('18100000-0000-4000-8000-000000000011', '18100000-0000-4000-8000-000000000012');
select is((select count(*)::int from broadcast_log), 0, 'mute-only updates do not wake either campus');
update public.rsvps set role = role where user_id = '18100000-0000-4000-8000-000000000011';
select is((select count(*)::int from broadcast_log), 0, 'no-op updates do not broadcast');
update public.rsvps set joined_at = joined_at - interval '1 minute' where user_id in
    ('18100000-0000-4000-8000-000000000011', '18100000-0000-4000-8000-000000000012');
select is((select count(*)::int from broadcast_log), 2, 'one statement with relevant changes broadcasts once per campus');
select ok(not exists (
    select 1 from broadcast_log l, unnest(l.ids) game_id
    join public.games g on g.id = game_id where g.university_id <> l.campus
), 'each campus receives only its own game IDs');
truncate broadcast_log;
insert into public.rsvps (event_id, user_id, role) values
    ('18100000-0000-4000-8000-000000000021', '18100000-0000-4000-8000-000000000013', 'player');
select is((select count(*)::int from broadcast_log), 1, 'membership insertion still broadcasts');
truncate broadcast_log;
delete from public.rsvps where user_id = '18100000-0000-4000-8000-000000000013';
select is((select count(*)::int from broadcast_log), 1, 'membership deletion still broadcasts');

update public.app_config set value = 'true' where key in ('push_enabled', 'chat_enabled');
update private.notification_outbox set not_before = now() + interval '30 days';
insert into private.device_tokens (token, user_id, environment, app_version) values
    ('fenced-device-token', '18100000-0000-4000-8000-000000000011', 'sandbox', '1.0');
create function pg_temp.enqueue_fenced(p_key text) returns void language sql as $$
    select private.enqueue_notification('18100000-0000-4000-8000-000000000011', 'chat_message', null,
        '{"count":1,"body":"test"}', p_key, null, now(), now() + interval '1 day', false, 'keep')
$$;
create function pg_temp.finish_fenced(p_id bigint, p_token uuid, p_outcome text, p_drop boolean default false)
returns void language sql as $$
    select private.complete_notifications_v2(jsonb_build_array(jsonb_build_object(
        'id', p_id, 'claim_token', p_token, 'outcome', p_outcome,
        'drop_tokens', case when p_drop then '["fenced-device-token"]'::jsonb else '[]'::jsonb end)))
$$;
select pg_temp.enqueue_fenced('fence:first');
create temp table attempt_a as select * from private.claim_notifications_v2(100);
select isnt((select claim_token from attempt_a), null, 'v2 claim returns an opaque identity');
update private.notification_outbox set locked_at = now() - interval '11 minutes' where merge_key = 'fence:first';
create temp table attempt_b as select * from private.claim_notifications_v2(100);
select isnt((select claim_token from attempt_a), (select claim_token from attempt_b), 'a reclaimed lease has a fresh identity');
select pg_temp.finish_fenced(id, claim_token, 'sent', true) from attempt_a;
select ok((select sent_at is null and locked_at is not null from private.notification_outbox where merge_key = 'fence:first'),
    'late worker A cannot complete worker B lease');
select ok(exists(select 1 from private.device_tokens where token = 'fenced-device-token'),
    'stale worker cannot delete device tokens');
select private.complete_notifications(jsonb_build_array(jsonb_build_object('id', id, 'outcome', 'sent'))) from attempt_b;
select ok((select sent_at is null from private.notification_outbox where merge_key = 'fence:first'),
    'legacy id-only completion cannot complete a v2 lease');
select pg_temp.finish_fenced(id, claim_token, null, true) from attempt_b;
select ok((select claim_token = (select claim_token from attempt_b) and locked_at is not null
    from private.notification_outbox where merge_key = 'fence:first'),
    'malformed outcome cannot clear a current identity');
select ok(exists(select 1 from private.device_tokens where token = 'fenced-device-token'),
    'malformed outcome cannot clean up tokens');
select pg_temp.finish_fenced(id, claim_token, 'sent') from attempt_b;
select ok((select sent_at is not null and locked_at is null and claim_token is null from private.notification_outbox where merge_key = 'fence:first'),
    'current worker completes and clears its lease and identity');
select pg_temp.finish_fenced(id, claim_token, 'sent', true) from attempt_b;
select ok(exists(select 1 from private.device_tokens where token = 'fenced-device-token'),
    'duplicate completion does not repeat cleanup');

select pg_temp.enqueue_fenced('fence:merge');
truncate attempt_a, attempt_b;
insert into attempt_a select * from private.claim_notifications_v2(100);
select pg_temp.enqueue_fenced('fence:merge');
select pg_temp.finish_fenced(id, claim_token, 'sent') from attempt_a;
select ok((select sent_at is null and locked_at is null and claim_token is null from private.notification_outbox where merge_key = 'fence:merge'),
    'new merged content stays pending after successful snapshot completion');
insert into attempt_b select * from private.claim_notifications_v2(100);
select pg_temp.finish_fenced(id, claim_token, 'sent') from attempt_a;
select ok((select sent_at is null and locked_at is not null from private.notification_outbox where merge_key = 'fence:merge'),
    'duplicate old completion cannot consume the merged snapshot');
select pg_temp.finish_fenced(id, claim_token, 'retry') from attempt_b;
select ok((select attempts = 1 and locked_at is null and claim_token is null from private.notification_outbox where merge_key = 'fence:merge'),
    'current retry clears ownership and increments retry accounting once');

select pg_temp.enqueue_fenced('fence:legacy');
truncate attempt_a, attempt_b;
insert into attempt_a select * from private.claim_notifications_v2(100);
update private.notification_outbox set locked_at = now() - interval '11 minutes' where merge_key = 'fence:legacy';
select private.claim_notifications(100);
select pg_temp.finish_fenced(id, claim_token, 'drop', true) from attempt_a;
select ok((select dropped is null and locked_at is not null and claim_token is null from private.notification_outbox where merge_key = 'fence:legacy'),
    'a legacy reclaim fences the earlier v2 worker');
select private.complete_notifications(jsonb_build_array(jsonb_build_object('id', id, 'outcome', 'sent'))) from attempt_a;
select ok((select sent_at is not null from private.notification_outbox where merge_key = 'fence:legacy'),
    'legacy claim/completion remains compatible during migration');

select ok(not has_function_privilege('anon', 'public.claim_notifications_v2(integer)', 'execute'), 'anon cannot claim v2');
select ok(not has_function_privilege('authenticated', 'public.complete_notifications_v2(jsonb)', 'execute'), 'members cannot complete v2');
select ok(has_function_privilege('service_role', 'public.claim_notifications_v2(integer)', 'execute'), 'service role can claim v2');
select ok(not has_function_privilege('service_role', 'private.claim_notifications_unfenced(integer)', 'execute'),
    'service role cannot bypass fencing through the private underlying helper');
select * from finish();
rollback;
