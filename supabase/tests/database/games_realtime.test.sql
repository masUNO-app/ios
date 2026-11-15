-- Live game lists (1.0 refresh): game and spot changes ping the game's campus with the games' IDs.
begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true)
$$;

select has_trigger('public', 'games', 'games_updated_broadcast', 'changing a game sends a ping');
select has_trigger('public', 'rsvps', 'rsvps_inserted_broadcast', 'joining sends a ping');
select has_trigger('public', 'rsvps', 'rsvps_deleted_broadcast', 'leaving sends a ping');
select ok(
    to_regclass('realtime.messages') is null
    or exists (select 1 from pg_policies where schemaname = 'realtime' and tablename = 'messages'
               and policyname = 'campus members receive game changes'),
    'campus members can listen for their campus''s game changes'
);

insert into auth.users (id, email) values
    ('a0000000-0000-4000-8000-00000000000a', 'alice@tec.mx'),
    ('b0000000-0000-4000-8000-00000000000b', 'bruno@tec.mx');

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.complete_profile('Alice', 'Zamora', 2027, array['basketball'], 'en');
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.complete_profile('Bruno', 'Ybarra', 2026, array['soccer'], 'es');

select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
create temp table game_ids on commit drop as
select id from public.create_game('basketball', 'Pickup game', now() + interval '1 day', 60, 6, null,
    'Arena Borregos', 'Av. Junco de la Vega', 25.65, -100.29, null, true);
grant select on game_ids to authenticated;
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.join_game((select id from game_ids));
reset role;

-- Each ping names the game, on its campus's topic.
select ok(
    to_regclass('realtime.messages') is null
    or exists (
        select 1 from realtime.messages m, public.profiles p
        where p.id = 'b0000000-0000-4000-8000-00000000000b'
          and m.topic = 'campus:' || p.university_id::text || ':games'
          and m.event = 'changed'
          and m.payload -> 'ids' ? (select id::text from game_ids)
    ),
    'a join pings the campus with the game''s ID'
);
select ok(
    to_regclass('realtime.messages') is null
    or not exists (select 1 from realtime.messages where topic = 'games:changes'),
    'nothing goes out on an all-campus topic'
);

select * from finish();
rollback;
