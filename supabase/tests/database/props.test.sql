-- Props after every game (20261127000000): who you can give props to, the 24-hour window, round
-- nights by group, blocks, anonymity and the 3-giver threshold, the leaderboard opt-in, the switch.
begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true)
$$;

-- Alice hosts. Bruno, Carla and Darío play. Rita is on the demo campus.
insert into auth.users (id, email) values
    ('a0000000-0000-4000-8000-00000000000a', 'alice@tec.mx'),
    ('b0000000-0000-4000-8000-00000000000b', 'bruno@tec.mx'),
    ('c0000000-0000-4000-8000-00000000000c', 'carla@tec.mx'),
    ('d0000000-0000-4000-8000-00000000000d', 'dario@tec.mx'),
    ('f0000000-0000-4000-8000-00000000000f', 'official.masuno.app+review1@gmail.com');

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.complete_profile('Alice', 'Zamora', 2027, array['soccer'], 'en');
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.complete_profile('Bruno', 'Ybarra', 2026, array['soccer'], 'es');
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select public.complete_profile('Carla', 'Xochitl', 2028, array['soccer'], 'es');
select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select public.complete_profile('Darío', 'Vela', 2027, array['soccer'], 'es');
select pg_temp.act_as('f0000000-0000-4000-8000-00000000000f');
select public.complete_profile('Rita', 'Review', 2027, array['padel'], 'en');

-- Two soccer plans everyone joins, and a round night. Then time moves on (below, as the owner).
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
create temp table plans on commit drop as
select 'earlier'::text as name, id from public.create_game('soccer', 'Earlier match', now() + interval '1 day', 60, 6, null,
    'Field', 'Tec', 25.65, -100.29, null, true);
insert into plans select 'match', id from public.create_game('soccer', 'Sunday match', now() + interval '1 day', 60, 6, null,
    'Field', 'Tec', 25.65, -100.29, null, true);
insert into plans select 'rounds', id from public.create_game('valorant', 'Valorant rounds', now() + interval '1 day', 70, 6, null,
    'Game room', 'Tec', 25.65, -100.29, null, true, 2, 30, 10, 2);
grant select on plans to authenticated, anon;
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.join_game(id) from plans;
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select public.join_game(id) from plans;
select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select public.join_game((select id from plans where name = 'match'));
select public.join_game((select id from plans where name = 'rounds'));

reset role;
-- The earlier match ended two days ago; the Sunday match ended an hour ago; the round night started
-- 35 minutes ago, so its first round is over and the second is being played.
update public.games set starts_at = now() - interval '2 days 1 hour', ends_at = now() - interval '2 days'
where id = (select id from plans where name = 'earlier');
update public.games set starts_at = now() - interval '2 hours', ends_at = now() - interval '1 hour'
where id = (select id from plans where name = 'match');
update public.games set starts_at = now() - interval '35 minutes', ends_at = now() - interval '35 minutes' + interval '70 minutes'
where id = (select id from plans where name = 'rounds');
set local role authenticated;

-- Who Bruno can give props to after the match: everyone else there, the host first.
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
create temp table sheet on commit drop as select public.props_to_give((select id from plans where name = 'match')) as v;
grant select on sheet to authenticated;
select ok((select (v->>'open')::boolean from sheet), 'props are open after the match');
select is((select jsonb_array_length(v->'people') from sheet), 3, 'for the three others who played');
select is((select v->'people'->0->>'first_name' from sheet), 'Alice', 'the host first');
select is((select (v->'people'->0->>'is_host')::boolean from sheet), true, 'marked as host');
select is((select (p->>'played_before')::int from sheet, jsonb_array_elements(v->'people') p where p->>'first_name' = 'Carla'), 1,
    'Bruno and Carla played together once before');
select is((select (p->>'played_before')::int from sheet, jsonb_array_elements(v->'people') p where p->>'first_name' = 'Darío'), 0,
    'and Darío is new to him');

-- Giving, changing your mind, and what isn't allowed.
select is(public.give_props((select id from plans where name = 'match'), null,
    '{"a0000000-0000-4000-8000-00000000000a": ["good_sport", "on_time"], "c0000000-0000-4000-8000-00000000000c": ["team_player"]}'),
    '{"sent": 3}'::jsonb, 'Bruno sends three props');
select is(public.give_props((select id from plans where name = 'match'), null,
    '{"a0000000-0000-4000-8000-00000000000a": ["good_sport", "good_sport"]}'),
    '{"sent": 2}'::jsonb, 'sending again replaces what Alice got from him (and a repeat counts once)');
select is((select v->'people'->0->'sent' from (select public.props_to_give((select id from plans where name = 'match')) v) x),
    '["good_sport"]'::jsonb, 'the sheet shows what he already sent');
select throws_ok(format($$ select public.give_props(%L, null, '{"f0000000-0000-4000-8000-00000000000f": ["good_sport"]}') $$,
    (select id from plans where name = 'match')), 'P0001', 'invalid_input', 'not to someone who wasn''t there');
select throws_ok(format($$ select public.give_props(%L, null, '{"b0000000-0000-4000-8000-00000000000b": ["good_sport"]}') $$,
    (select id from plans where name = 'match')), 'P0001', 'invalid_input', 'not to yourself');
select throws_ok(format($$ select public.give_props(%L, null, '{"a0000000-0000-4000-8000-00000000000a": ["best_player"]}') $$,
    (select id from plans where name = 'match')), 'P0001', 'invalid_input', 'only the four props, nothing about skill');

-- Alice gets Good sport from three different people: now it shows on Who's going.
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select public.give_props((select id from plans where name = 'match'), null, '{"a0000000-0000-4000-8000-00000000000a": ["good_sport"]}');
select is((select count(*)::int from public.prop_counts(array['a0000000-0000-4000-8000-00000000000a'::uuid])), 0,
    'with two people, nothing shows yet');
select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select public.give_props((select id from plans where name = 'match'), null, '{"a0000000-0000-4000-8000-00000000000a": ["good_sport", "made_it_fun"]}');
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select is((select people from public.prop_counts(array['a0000000-0000-4000-8000-00000000000a'::uuid]) where prop = 'good_sport'), 3,
    'with three, her Good sport count shows');
select pg_temp.act_as('f0000000-0000-4000-8000-00000000000f');
select is((select count(*)::int from public.prop_counts(array['a0000000-0000-4000-8000-00000000000a'::uuid])), 0,
    'but not to another campus');

-- Alice's recap: counts, never who.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select is(public.my_props_for_game((select id from plans where name = 'match')),
    '{"people": 3, "props": {"good_sport": 3, "made_it_fun": 1}}'::jsonb, 'Alice sees how many, not who');

-- The leaderboard lists only people who opted in; Alice can always see her own rank.
create temp table board on commit drop as select public.props_leaderboard('good_sport') as v;
grant select on board to authenticated;
select is((select jsonb_array_length(v->'top') from board), 0, 'nobody is listed before opting in');
select is((select v->'me' from board), '{"opted_in": false, "rank": 1, "people": 3}'::jsonb, 'Alice still sees her standing');
select is(public.set_props_leaderboard(true), true, 'Alice opts in');
select is((select p->>'first_name' from jsonb_array_elements(public.props_leaderboard('good_sport')->'top') p), 'Alice',
    'and is listed');
select is((select p->>'mostly' from jsonb_array_elements(public.props_leaderboard('good_sport')->'top') p), 'soccer',
    'with what most of her props came from');
select is(jsonb_array_length(public.props_leaderboard('good_sport', 'esports')->'top'), 0, 'esports is its own filter');
select throws_ok($$ select public.props_leaderboard('fastest') $$, 'P0001', 'invalid_input', 'only the four props');

-- Blocks: once Carla blocks Darío, neither can give the other props.
reset role;
insert into public.blocks (blocker_id, blocked_id) values ('c0000000-0000-4000-8000-00000000000c', 'd0000000-0000-4000-8000-00000000000d');
set local role authenticated;
select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select ok(not exists (select 1 from jsonb_array_elements(public.props_to_give((select id from plans where name = 'match'))->'people') p
                      where p->>'first_name' = 'Carla'), 'blocked people aren''t offered');

-- Round nights: after each round, to that round's group only.
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.game_rotation((select id from plans where name = 'rounds'));
select is((select (v->>'open')::boolean from (select public.props_to_give((select id from plans where name = 'rounds'), 0) v) x), true,
    'round 1 is over: props for it are open');
select is((select jsonb_array_length(v->'people') from (select public.props_to_give((select id from plans where name = 'rounds'), 0) v) x), 1,
    'for Bruno''s group of two: one person');
select is((select (v->>'open')::boolean from (select public.props_to_give((select id from plans where name = 'rounds'), 1) v) x), false,
    'round 2 isn''t over yet');
select is((select (v->>'open')::boolean from (select public.props_to_give((select id from plans where name = 'rounds')) v) x), false,
    'a round night has no whole-night props, only per round');

-- The window closes 24 hours after the end.
reset role;
update public.games set starts_at = now() - interval '26 hours', ends_at = now() - interval '25 hours'
where id = (select id from plans where name = 'match');
set local role authenticated;
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select throws_ok(format($$ select public.give_props(%L, null, '{"a0000000-0000-4000-8000-00000000000a": []}') $$,
    (select id from plans where name = 'match')), 'P0001', 'props_closed', 'a day after, props are closed');

-- The switch.
reset role;
update public.app_config set value = 'false' where key = 'props_enabled';
set local role authenticated;
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select is((select count(*)::int from public.prop_counts(array['a0000000-0000-4000-8000-00000000000a'::uuid])), 0,
    'off, nothing shows');
select throws_ok(format($$ select public.give_props(%L, 0, '{}') $$, (select id from plans where name = 'rounds')),
    'P0001', 'props_disabled', 'and nothing can be sent');

-- Signed out, none of it.
set local role anon;
select pg_temp.act_as(null);
select throws_ok(format($$ select public.props_to_give(%L) $$, (select id from plans where name = 'match')), '42501', null,
    'signed out, no props');
reset role;
select ok(not has_function_privilege('authenticated', 'private.props_peers(uuid, public.games, integer)', 'execute'),
    'the eligibility helper stays private');

select * from finish();
rollback;
