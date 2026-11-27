-- Weekly open plans: the house account, one plan at a time, joining and leaving with nobody
-- hosting, skipping a week, and the cleanup.
begin;
create extension if not exists pgtap with schema extensions;
select plan(31);

create function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

-- The house account ------------------------------------------------------------------------------

select is((select first_name || ' ' || last_initial || '.' from public.profiles
           where id = '5e000000-0000-4000-8000-000000000001'),
    'masUNO T.', 'the house account shows as masUNO T.');
select is((select u.email_domain from public.profiles p join public.universities u on u.id = p.university_id
           where p.id = '5e000000-0000-4000-8000-000000000001'),
    'tec.mx', 'at Tec');
select ok((select not (interest_match or spot_open or reminders or hosting or chat or winback)
           from public.notification_prefs where user_id = '5e000000-0000-4000-8000-000000000001'),
    'with every notification off');
select ok(exists (select 1 from private.house_accounts where user_id = '5e000000-0000-4000-8000-000000000001'),
    'and listed as a house account');
select is((select encrypted_password from auth.users where id = '5e000000-0000-4000-8000-000000000001'),
    null, 'nobody can sign in as it');

-- Next start, in campus time (Monterrey is UTC-6 all year) ---------------------------------------

select is(private.next_recurring_start(1::smallint, '18:00', 'America/Monterrey', '2026-11-30 12:00-06'),
    '2026-11-30 18:00-06'::timestamptz, 'later the same day');
select is(private.next_recurring_start(1::smallint, '18:00', 'America/Monterrey', '2026-11-30 18:00-06'),
    '2026-12-07 18:00-06'::timestamptz, 'a start that isn''t after p_after goes to next week');
select is(private.next_recurring_start(4::smallint, '18:30', 'America/Monterrey', '2026-11-30 12:00-06'),
    '2026-12-03 18:30-06'::timestamptz, 'a later day this week');
select is(private.next_recurring_start(7::smallint, '10:00', 'America/Monterrey', '2026-12-05 23:30-06'),
    '2026-12-06 10:00-06'::timestamptz, 'Sunday');
select is(private.next_recurring_start(1::smallint, '18:00', 'America/Monterrey', '2026-12-01 01:00+00'),
    '2026-12-07 18:00-06'::timestamptz, 'campus day, not UTC day');

-- Alice plays tennis --------------------------------------------------------------------------------

insert into auth.users (id, email) values ('a0000000-0000-4000-8000-00000000000a', 'alice@tec.mx');
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.complete_profile('Alice', 'Zamora', 2027, array['tennis'], 'en');
reset role;

-- Posting -----------------------------------------------------------------------------------------

insert into private.recurring_plans (university_id, host_id, activity_slug, title, weekday, local_time,
                                     duration_minutes, capacity, notes, place_name, place_address, lat, lng)
select u.id, '5e000000-0000-4000-8000-000000000001', v.slug, v.title, v.weekday, '18:00', 60, 4,
       'Plan semanal abierto.', 'Centro Deportivo Borregos II (CDB II)', 'Calle Luis Elizondo 427, Monterrey',
       25.6508, -100.28579
from public.universities u
cross join (values ('tennis', 'Tenis abierto', 1::smallint), ('padel', 'Pádel en pausa', 3::smallint)) v(slug, title, weekday)
where u.email_domain = 'tec.mx';
create temp table t_plans on commit drop as
select id, activity_slug from private.recurring_plans where title in ('Tenis abierto', 'Pádel en pausa');
update private.recurring_plans set active = false where id = (select id from t_plans where activity_slug = 'padel');

create temp table t_tennis on commit drop as select id from t_plans where activity_slug = 'tennis';
create function pg_temp.tennis_games() returns setof public.games language sql as $$
    select g.* from public.games g join private.recurring_plan_games l on l.game_id = g.id
    where l.plan_id = (select id from t_tennis)
$$;

select is(private.post_recurring_plans(), 1, 'the active plan is posted, the paused one isn''t');
select is((select starts_at from pg_temp.tennis_games()),
    private.next_recurring_start(1::smallint, '18:00', 'America/Monterrey', now()), 'for its next Monday');
select is((select going_count from pg_temp.tennis_games()), 0, 'with nobody going');
select is((select count(*)::int from public.rsvps where event_id = (select id from pg_temp.tennis_games())), 0,
    'and nobody on the roster, not even the house');
select ok(exists (select 1 from private.notification_outbox
                  where user_id = 'a0000000-0000-4000-8000-00000000000a' and kind = 'interest_match'
                    and event_id = (select id from pg_temp.tennis_games())),
    'Alice hears about it, since tennis is one of her sports');
select is(private.post_recurring_plans(), 0, 'one at a time: nothing more while it''s upcoming');

-- Joining and leaving -------------------------------------------------------------------------------

create temp table t_game on commit drop as select id, starts_at from pg_temp.tennis_games();
grant select on t_game to authenticated;

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select is((select host_first_name || ' ' || host_last_initial from public.game_cards where id = (select id from t_game)),
    'masUNO T', 'Alice sees it, hosted by masUNO');
select is((select spots_left from public.game_cards where id = (select id from t_game)), 4, 'with every spot open');
select is((select going_count from public.join_game((select id from t_game))), 1, 'she joins');
select is((select array_agg(first_name) from public.game_attendees where event_id = (select id from t_game)),
    array['Alice'], 'and Who''s going lists only her');
reset role;
select is((select count(*)::int from private.notification_outbox
           where user_id = '5e000000-0000-4000-8000-000000000001'), 0, 'the house gets no host updates');
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select is((select going_count from public.leave_game((select id from t_game))), 0, 'she can leave, back to nobody going');
select is((select going_count from public.join_game((select id from t_game))), 1, 'and join again');
select throws_ok($$ select private.cancel_recurring_game((select id from t_game)) $$, '42501', null,
    'members can''t cancel a week');
reset role;

-- Skipping a week -------------------------------------------------------------------------------------

select alike(private.cancel_recurring_game((select id from t_game)), 'Cancelled Tenis abierto on %', 'the team skips this week');
select ok(exists (select 1 from private.notification_outbox
                  where user_id = 'a0000000-0000-4000-8000-00000000000a' and kind = 'game_cancelled'
                    and event_id = (select id from t_game)),
    'and Alice is told');
select is(private.cancel_recurring_game((select id from t_game)), 'Not cancelled: already cancelled', 'not twice');
select is(private.post_recurring_plans(), 1, 'the next run posts the week after');
select is((select max(starts_at) from pg_temp.tennis_games()), (select starts_at + interval '7 days' from t_game),
    'a week later, not the cancelled week again');

-- Cleanup -----------------------------------------------------------------------------------------

-- A month on: the empty week is gone, the cancelled week Alice was in stays, and a new one is up.
select is(private.post_recurring_plans(now() + interval '30 days'), 1, 'a month later, the next week is posted');
select is((select count(*)::int from pg_temp.tennis_games() where ends_at < now() + interval '29 days'), 1,
    'past weeks with nobody going are deleted; the one Alice joined stays');

select * from finish();
rollback;
