-- Game RPCs, RLS and views (SPEC §8.4–§8.5, B3, B10). The two-phone last-spot race itself is a
-- row-lock property, so it stays in docs/QA.md; this checks the `full` answer it produces.
begin;
create extension if not exists pgtap with schema extensions;
select plan(29);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true)
$$;

insert into auth.users (id, email) values
    ('a0000000-0000-4000-8000-00000000000a', 'alice@tec.mx'),
    ('b0000000-0000-4000-8000-00000000000b', 'bruno@tec.mx'),
    ('c0000000-0000-4000-8000-00000000000c', 'carla@tec.mx'),
    ('d0000000-0000-4000-8000-00000000000d', 'dario@tec.mx'),
    ('e0000000-0000-4000-8000-00000000000e', 'official.masuno.app+review1@gmail.com');

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select lives_ok($$ select public.complete_profile('Alice', 'Zamora', 2027, array['basketball'], 'en') $$, 'Alice completes her profile');
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select lives_ok($$ select public.complete_profile('Bruno', 'Ybarra', 2026, array['soccer'], 'es') $$, 'Bruno completes his profile');
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select lives_ok($$ select public.complete_profile('Carla', 'Xochitl', 2028, array['tennis'], 'es') $$, 'Carla completes her profile');
select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select lives_ok($$ select public.complete_profile('Darío', 'Vela', 2027, array['soccer'], 'es') $$, 'Darío completes his profile');

-- Review account: placed on the demo campus by the allowlist, and can see it.
select pg_temp.act_as('e0000000-0000-4000-8000-00000000000e');
select lives_ok($$ select public.complete_profile('Rita', 'Review', 2027, array['padel'], 'en') $$, 'review account completes its profile');
select is((select university_short_name from public.my_profile), 'Demo', 'review account lands on the demo campus');
select ok((select count(*) from public.game_cards where cancelled_at is null) >= 4, 'review account sees joinable demo games');

-- Posting rules.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.create_game('basketball', 'Late', now() + interval '8 days', 60, 4, null, 'Arena', 'Tec', 25.65, -100.29, null, true) $$,
    'P0001', 'invalid_time', 'no games more than 7 days out');
select throws_ok($$ select public.create_game('basketball', 'Past', now() - interval '1 hour', 60, 4, null, 'Arena', 'Tec', 25.65, -100.29, null, true) $$,
    'P0001', 'invalid_time', 'no games in the past');
select throws_ok($$ select public.create_game('soccer', 'Pinche partido', now() + interval '1 day', 60, 4, null, 'Arena', 'Tec', 25.65, -100.29, null, true) $$,
    'P0001', 'invalid_text', 'the Spanish word filter rejects a title');
select throws_ok($$ select public.create_game('soccer', 'Juego', now() + interval '1 day', 60, 4, 'no CABRÓNES', 'Arena', 'Tec', 25.65, -100.29, null, true) $$,
    'P0001', 'invalid_text', 'the filter ignores accents and catches plurals');
select lives_ok($$ select public.create_game('soccer', 'Computación vs Shitake fans', now() + interval '1 day', 60, 4, null, 'Arena', 'Tec', 25.65, -100.29, null, true) $$,
    'words that only contain a filtered word pass');

create temp table game_ids on commit drop as
select 'main'::text as name, id from public.create_game('basketball', 'Pickup game', now() + interval '1 day', 60, 3, null,
    '  Arena Borregos ', 'Av. Junco de la Vega', 25.65, -100.29, 'Court 2', true);
grant select on game_ids to authenticated;

select lives_ok($$ select public.create_game('tennis', 'Third', now() + interval '2 days', 60, 2, null, 'Courts', 'Tec', 25.65, -100.29, null, true) $$,
    'a third upcoming game is allowed');
select throws_ok($$ select public.create_game('tennis', 'Fourth', now() + interval '2 days', 60, 2, null, 'Courts', 'Tec', 25.65, -100.29, null, true) $$,
    'P0001', 'limit_reached', 'a fourth upcoming game is not');

-- Joining, the last spot and idempotency.
select is((select going_count from public.join_game((select id from game_ids where name = 'main'))), 1, 'the host joining is a no-op');
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select is((select going_count from public.join_game((select id from game_ids where name = 'main'))), 2, 'Bruno joins');
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select is((select going_count from public.join_game((select id from game_ids where name = 'main'))), 3, 'Carla takes the last spot');
select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select throws_ok($$ select public.join_game((select id from game_ids where name = 'main')) $$,
    'P0001', 'full', 'the next person gets `full`');
select is((select count(*)::int from public.game_attendees where event_id = (select id from game_ids where name = 'main')), 3, 'Who''s going lists all three');
select is((select host_last_initial from public.game_cards where id = (select id from game_ids where name = 'main')), 'Z', 'cards show the host''s last initial');

-- Campus boundary.
select pg_temp.act_as('e0000000-0000-4000-8000-00000000000e');
select is_empty($$ select 1 from public.game_cards where id = (select id from game_ids where name = 'main') $$, 'another campus can''t see the game');
select throws_ok($$ select public.join_game((select id from game_ids where name = 'main')) $$,
    'P0001', 'not_found', 'another campus can''t join it');

-- Privacy: column grants.
select throws_ok($$ select last_name from public.profiles $$, '42501', null, 'last names aren''t readable');
select throws_ok($$ select banned_at from public.profiles $$, '42501', null, 'bans aren''t readable');

-- Blocks hide actors in the chat history; a full game that loses a player is reposted.
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.block('c0000000-0000-4000-8000-00000000000c');
select is_empty($$ select 1 from public.game_activity where actor_first_name = 'Carla' $$, 'a blocked person''s name is hidden in chat rows');
select public.unblock('c0000000-0000-4000-8000-00000000000c');
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select lives_ok($$ select public.leave_game((select id from game_ids where name = 'main')) $$, 'Bruno leaves the full game');
select isnt((select reposted_at from public.game_cards where id = (select id from game_ids where name = 'main')), null,
    'a full game that loses a player is reposted');

-- Edits: trimmed input isn't a change; duration and meet-up spot are.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.update_game(g.id, 'basketball', 'Pickup game', g.starts_at, 90, 3, null, ' Arena Borregos', 'Av. Junco de la Vega ', 25.65, -100.29, 'Court 3', true)
from public.game_cards g where g.id = (select id from game_ids where name = 'main');
select is((select array_agg(kind order by kind) from public.game_activity
           where event_id = (select id from game_ids where name = 'main') and kind in ('meet_point_updated', 'time_or_place_changed')),
    array['meet_point_updated', 'time_or_place_changed'], 'a duration and meet-up change log both rows, once each');

-- Suspension.
reset role;
update public.profiles set banned_at = now() where id = 'a0000000-0000-4000-8000-00000000000a';
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.cancel_game((select id from game_ids where name = 'main')) $$,
    'P0001', 'suspended', 'a banned account can''t write');

select * from finish();
rollback;
