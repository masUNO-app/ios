-- Round nights (20261126000100): posting and editing rounds, and `game_rotation` picking groups as
-- each round comes out, keeping them, leaving out people who left, and staying on the campus.
begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true)
$$;
-- Group sizes of one round, as the reader sees them.
create function pg_temp.sizes(p_rotation jsonb, p_round integer) returns integer[] language sql as $$
    select array_agg(jsonb_array_length(g) order by jsonb_array_length(g) desc)
    from jsonb_array_elements(p_rotation->'rounds'->p_round->'groups') g
$$;
-- Everyone in one round, by ID.
create function pg_temp.people(p_rotation jsonb, p_round integer) returns text[] language sql as $$
    select array_agg(p->>'id' order by p->>'id')
    from jsonb_array_elements(p_rotation->'rounds'->p_round->'groups') g, jsonb_array_elements(g) p
$$;

-- Alice hosts. Bruno, Carla, Darío and Eva play. Rita is on the demo campus.
insert into auth.users (id, email) values
    ('a0000000-0000-4000-8000-00000000000a', 'alice@tec.mx'),
    ('b0000000-0000-4000-8000-00000000000b', 'bruno@tec.mx'),
    ('c0000000-0000-4000-8000-00000000000c', 'carla@tec.mx'),
    ('d0000000-0000-4000-8000-00000000000d', 'dario@tec.mx'),
    ('e0000000-0000-4000-8000-00000000000e', 'eva@tec.mx'),
    ('f0000000-0000-4000-8000-00000000000f', 'official.masuno.app+review1@gmail.com');

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.complete_profile('Alice', 'Zamora', 2027, array['basketball'], 'en');
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.complete_profile('Bruno', 'Ybarra', 2026, array['soccer'], 'es');
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select public.complete_profile('Carla', 'Xochitl', 2028, array['tennis'], 'es');
select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select public.complete_profile('Darío', 'Vela', 2027, array['soccer'], 'es');
select pg_temp.act_as('e0000000-0000-4000-8000-00000000000e');
select public.complete_profile('Eva', 'Uribe', 2029, array['padel'], 'es');
select pg_temp.act_as('f0000000-0000-4000-8000-00000000000f');
select public.complete_profile('Rita', 'Review', 2027, array['padel'], 'en');

-- Posting rules: rounds only for a kind that has them, all four set, allowed values, the length
-- exactly the rounds and breaks, and room for two groups.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.create_game('valorant', 'Rounds', now() + interval '1 day', 60, 6, null,
    'Game room', 'Tec', 25.65, -100.29, null, true, 2, 30, 10, 2) $$, 'P0001', 'invalid_input',
    'the length must be the rounds and breaks (70 here)');
select throws_ok($$ select public.create_game('soccer', 'Rounds', now() + interval '1 day', 70, 6, null,
    'Field', 'Tec', 25.65, -100.29, null, true, 2, 30, 10, 2) $$, 'P0001', 'invalid_input',
    'sports have no round nights');
select throws_ok($$ select public.create_game('valorant', 'Rounds', now() + interval '1 day', 70, 6, null,
    'Game room', 'Tec', 25.65, -100.29, null, true, 2, 30, 10, null) $$, 'P0001', 'invalid_input',
    'all four settings or none');
select throws_ok($$ select public.create_game('valorant', 'Rounds', now() + interval '1 day', 70, 3, null,
    'Game room', 'Tec', 25.65, -100.29, null, true, 2, 30, 10, 2) $$, 'P0001', 'invalid_input',
    'room for two groups');
select throws_ok($$ select public.create_game('valorant', 'Rounds', now() + interval '1 day', 210, 12, null,
    'Game room', 'Tec', 25.65, -100.29, null, true, 6, 30, 6, 2) $$, 'P0001', 'invalid_input',
    'only the round counts and breaks the app offers');
select throws_ok($$ select public.create_game('valorant', 'Plain', now() + interval '1 day', 70, 6, null,
    'Game room', 'Tec', 25.65, -100.29, null, true) $$, 'P0001', 'invalid_input',
    'without rounds, the length is one of the five');

create temp table nights on commit drop as
select 'rounds'::text as name, id, rotation_rounds, duration_minutes
from public.create_game('valorant', 'Valorant rounds', now() + interval '1 day', 70, 6, null,
    'Game room', 'Tec', 25.65, -100.29, null, true, 2, 30, 10, 2);
insert into nights
select 'plain', id, rotation_rounds, duration_minutes
from public.create_game('valorant', 'Valorant night', now() + interval '1 day', 60, 6, null,
    'Game room', 'Tec', 25.65, -100.29, null, true);
grant select on nights to authenticated, anon;
select is((select rotation_rounds from nights where name = 'rounds'), 2, 'a round night keeps its rounds');
select is((select duration_minutes from nights where name = 'rounds'), 70, 'and lasts every round and break');
select is((select rotation_rounds from nights where name = 'plain'), null::integer, 'an esports plan can still be plain');

-- Before it starts: the rounds, and no groups yet.
create temp table reads (n integer, rotation jsonb) on commit drop;
grant select, insert on reads to authenticated;
insert into reads select 1, public.game_rotation((select id from nights where name = 'rounds'));
select is((select jsonb_array_length(rotation->'rounds') from reads where n = 1), 2, 'two rounds');
select ok((select rotation->'rounds'->0->'groups' = 'null'::jsonb and rotation->'rounds'->1->'groups' = 'null'::jsonb
           from reads where n = 1), 'no groups before the start');
select is((select (rotation->'rounds'->1->>'reveals_at')::timestamptz - (rotation->'rounds'->0->>'starts_at')::timestamptz
           from reads where n = 1), interval '30 minutes', 'round 2''s groups come out as round 1 ends');
select throws_ok(format('select public.game_rotation(%L)', (select id from nights where name = 'plain')),
    'P0001', 'not_found', 'a plain plan has no rounds');

-- Bruno, Carla and Darío join. Then the night starts.
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.join_game((select id from nights where name = 'rounds'));
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
select public.join_game((select id from nights where name = 'rounds'));
select pg_temp.act_as('d0000000-0000-4000-8000-00000000000d');
select public.join_game((select id from nights where name = 'rounds'));
reset role;
update public.games set starts_at = now() - interval '5 minutes', ends_at = now() - interval '5 minutes' + interval '70 minutes'
where id = (select id from nights where name = 'rounds');
set local role authenticated;

select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
insert into reads select 2, public.game_rotation((select id from nights where name = 'rounds'));
select is((select pg_temp.sizes(rotation, 0) from reads where n = 2), array[2, 2], 'round 1: two groups of two');
select is((select array_length(pg_temp.people(rotation, 0), 1) from reads where n = 2), 4, 'with all four going');
select ok((select rotation->'rounds'->1->'groups' = 'null'::jsonb from reads where n = 2), 'round 2 isn''t out yet');
select ok((select rotation->'rounds'->0->'groups'->0->0 ? 'first_name' from reads where n = 2), 'people come with their names');

-- Eva joins late: round 1 stays as it was.
select pg_temp.act_as('e0000000-0000-4000-8000-00000000000e');
select public.join_game((select id from nights where name = 'rounds'));
insert into reads select 3, public.game_rotation((select id from nights where name = 'rounds'));
select is((select rotation->'rounds'->0 from reads where n = 3), (select rotation->'rounds'->0 from reads where n = 2),
    'a round''s groups are kept once out');

-- Round 2 comes out with Eva in it: five people, groups of two and three.
reset role;
update public.games set starts_at = now() - interval '35 minutes', ends_at = now() - interval '35 minutes' + interval '70 minutes'
where id = (select id from nights where name = 'rounds');
set local role authenticated;
insert into reads select 4, public.game_rotation((select id from nights where name = 'rounds'));
select is((select pg_temp.sizes(rotation, 1) from reads where n = 4), array[3, 2], 'round 2: leftovers join a group');
select ok((select 'e0000000-0000-4000-8000-00000000000e' = any(pg_temp.people(rotation, 1)) from reads where n = 4),
    'and the late joiner plays');

-- Bruno leaves: he drops out of the groups he was in.
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.leave_game((select id from nights where name = 'rounds'));
select pg_temp.act_as('c0000000-0000-4000-8000-00000000000c');
insert into reads select 5, public.game_rotation((select id from nights where name = 'rounds'));
select ok((select not ('b0000000-0000-4000-8000-00000000000b' = any(pg_temp.people(rotation, 0) || pg_temp.people(rotation, 1)))
           from reads where n = 5), 'someone who left isn''t shown');

-- Another campus can't read it, and signed out nobody can.
select pg_temp.act_as('f0000000-0000-4000-8000-00000000000f');
select throws_ok(format('select public.game_rotation(%L)', (select id from nights where name = 'rounds')),
    'P0001', 'not_found', 'another campus sees no rounds');

-- New rounds start the picking over.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select lives_ok(format($$ select public.update_game(%L, 'valorant', 'Valorant rounds', (select starts_at from public.games where id = %L),
    100, 6, null, 'Game room', 'Tec', 25.65, -100.29, null, true, 2, 45, 10, 2) $$,
    (select id from nights where name = 'rounds'), (select id from nights where name = 'rounds')), 'the host changes the rounds');
reset role;
select is((select count(*)::int from private.rotation_rounds where event_id = (select id from nights where name = 'rounds')), 0,
    'and the groups picked so far go');
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select lives_ok(format($$ select public.update_game(%L, 'valorant', 'Valorant rounds', (select starts_at from public.games where id = %L),
    60, 6, null, 'Game room', 'Tec', 25.65, -100.29, null, true) $$,
    (select id from nights where name = 'rounds'), (select id from nights where name = 'rounds')), 'or turns them off');

set local role anon;
select pg_temp.act_as(null);
select throws_ok(format('select public.game_rotation(%L)', (select id from nights where name = 'plain')), '42501', null,
    'signed out, no rounds');
reset role;
select ok(not has_function_privilege('authenticated', 'private.pick_rotation_groups(uuid[], integer, jsonb)', 'execute'),
    'the picker stays private');

select * from finish();
rollback;
