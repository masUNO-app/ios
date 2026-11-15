-- Server-only functions, report alerts and account deletion (B8, B9, B10).
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true)
$$;

insert into auth.users (id, email) values
    ('a0000000-0000-4000-8000-00000000000a', 'alice@tec.mx'),
    ('b0000000-0000-4000-8000-00000000000b', 'bruno@tec.mx'),
    ('c0000000-0000-4000-8000-00000000000c', 'carla@tec.mx');

-- Clients can't call what only Auth, the Edge Function or cron should.
set local role authenticated;
select throws_ok($$ select public.delete_my_account_data('a0000000-0000-4000-8000-00000000000a') $$, '42501', null,
    'clients can''t run account cleanup');
select throws_ok($$ select public.before_user_created('{}') $$, '42501', null, 'clients can''t call the auth hook');
select throws_ok($$ select private.refresh_demo_campus() $$, '42501', null, 'clients can''t refresh the demo campus');
reset role;
set local role anon;
select throws_ok($$ select student_email_pattern from public.universities $$, '42501', null, 'signed out, email patterns stay private');
select is((select array_agg(short_name) from public.university_lookup), array['Tec'], 'Find your school lists Tec, not the demo campus');
reset role;

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.complete_profile('Alice', 'Zamora', 2027, array['basketball'], 'en');
create temp table game_ids on commit drop as
select 'hosted'::text as name, id from public.create_game('basketball', 'Pickup', now() + interval '1 day', 60, 4, null, 'Arena', 'Tec', 25.65, -100.29, null, true);
grant select, insert on game_ids to authenticated;
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.complete_profile('Bruno', 'Ybarra', 2026, array['soccer'], 'es');
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select public.complete_profile('Carla', 'Xochitl', 2028, array['tennis'], 'es');
insert into game_ids
select 'joined', id from public.create_game('tennis', 'Tennis', now() + interval '1 day', 60, 4, null, 'Courts', 'Tec', 25.65, -100.29, null, true);

-- Reports: Bruno reports Alice; Carla reports Alice's game. Reporting yourself is refused.
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.join_game((select id from game_ids where name = 'joined'));
select throws_ok($$ select public.report('b0000000-0000-4000-8000-00000000000b', null, 'spam', null) $$,
    'P0001', 'invalid_input', 'you can''t report yourself');
select public.report('a0000000-0000-4000-8000-00000000000a', null, 'harassment', 'said something mean');
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select public.report(null, (select id from game_ids where name = 'hosted'), 'unsafe', null);
reset role;
select is((select count(*)::int from public.reports), 2, 'reports save, with or without the alert webhook set');

-- Deleting Alice also drops her notification token, preferences, bookmarks and outbox rows.
reset role;
insert into private.device_tokens (token, user_id, environment, locale, app_version)
values ('alice-token-delete', 'a0000000-0000-4000-8000-00000000000a', 'sandbox', 'en', '1.0');
insert into public.notification_prefs (user_id) values ('a0000000-0000-4000-8000-00000000000a');
insert into public.bookmarks (event_id, user_id)
values ((select id from game_ids where name = 'joined'), 'a0000000-0000-4000-8000-00000000000a');
insert into private.notification_outbox (user_id, kind, event_id, expires_at)
values ('a0000000-0000-4000-8000-00000000000a', 'reminder', (select id from game_ids where name = 'joined'), now() + interval '1 day');

-- Deleting Alice: a host who was reported, and whose game was reported.
set local role service_role;
select lives_ok($$ select public.delete_my_account_data('a0000000-0000-4000-8000-00000000000a') $$, 'cleanup runs for a host');
reset role;
select lives_ok($$ delete from auth.users where id = 'a0000000-0000-4000-8000-00000000000a' $$, 'the Auth user deletes');
select is_empty($$ select 1 from public.games where host_id = 'a0000000-0000-4000-8000-00000000000a' $$, 'their hosted games go too');
select is_empty($$ select 1 from private.device_tokens where user_id = 'a0000000-0000-4000-8000-00000000000a' $$, 'their notification token goes too');
select is_empty($$ select 1 from public.notification_prefs where user_id = 'a0000000-0000-4000-8000-00000000000a' $$, 'their notification preferences go too');
select is_empty($$ select 1 from public.bookmarks where user_id = 'a0000000-0000-4000-8000-00000000000a' $$, 'their bookmarks go too');
select is_empty($$ select 1 from private.notification_outbox where user_id = 'a0000000-0000-4000-8000-00000000000a' $$, 'their outbox rows go too');
select is((select count(*)::int from public.reports), 2, 'reports about them are kept');

-- Deleting Bruno: a reporter with a joined game.
set local role service_role;
select public.delete_my_account_data('b0000000-0000-4000-8000-00000000000b');
reset role;
delete from auth.users where id = 'b0000000-0000-4000-8000-00000000000b';
select is((select going_count from public.games where id = (select id from game_ids where name = 'joined')), 1, 'their spot is freed');
select is((select count(*)::int from public.reports where reporter_id is null), 1, 'their report stays, without the reporter');

select * from finish();
rollback;
