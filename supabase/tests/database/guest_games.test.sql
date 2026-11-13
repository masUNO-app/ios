-- Guest browsing (1.0, SPEC R7-15): signed out, `guest_games` shows a campus's open games without
-- names, and it's the only game read `anon` has.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true)
$$;

insert into auth.users (id, email) values
    ('a0000000-0000-4000-8000-00000000000a', 'alice@tec.mx'),
    ('b0000000-0000-4000-8000-00000000000b', 'bruno@tec.mx');

set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select public.complete_profile('Alice', 'Zamora', 2027, array['basketball'], 'en');
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.complete_profile('Bruno', 'Ybarra', 2026, array['soccer'], 'es');

-- Alice hosts an open game, one that fills and one she cancels.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
create temp table game_ids on commit drop as
select 'open'::text as name, id from public.create_game('basketball', 'Pickup game', now() + interval '1 day', 60, 6,
    'Bring water', 'Arena Borregos', 'Av. Junco de la Vega', 25.65, -100.29, 'Court 2', true);
grant select, insert on game_ids to authenticated, anon;
insert into game_ids
select 'full', id from public.create_game('tennis', 'Singles', now() + interval '1 day', 60, 2, null,
    'Courts', 'Tec', 25.65, -100.29, null, true);
insert into game_ids
select 'cancelled', id from public.create_game('soccer', 'Called off', now() + interval '2 days', 60, 6, null,
    'Field', 'Tec', 25.65, -100.29, null, true);
select public.cancel_game((select id from game_ids where name = 'cancelled'));
select pg_temp.act_as('b0000000-0000-4000-8000-00000000000b');
select public.join_game((select id from game_ids where name = 'full'));

-- An ended game, one past the 7-day window and one on a closed campus, which no RPC can make.
reset role;
insert into public.universities (name, short_name, email_domain, sso_provider, signup_enabled, center_lat, center_lng)
values ('Closed U', 'Closed', 'closed.edu', 'azure', false, 41.8, -87.6);
with added as (
    insert into public.games (university_id, host_id, activity_slug, title, starts_at, duration_minutes, ends_at,
                              capacity, place_name, place_address, lat, lng)
    select u.id, 'a0000000-0000-4000-8000-00000000000a', 'basketball', v.title, now() + v.starts_in, 60,
           now() + v.starts_in + interval '60 minutes', 6, 'Arena', 'Tec', 25.65, -100.29
    from (values
        ('ended', 'tec.mx', 'Yesterday', interval '-1 day'),
        ('later', 'tec.mx', 'Next week', interval '8 days'),
        ('closed', 'closed.edu', 'Elsewhere', interval '1 day')
    ) as v(name, email_domain, title, starts_in)
    join public.universities u on u.email_domain = v.email_domain
    returning id, title
)
insert into game_ids
select case a.title when 'Yesterday' then 'ended' when 'Next week' then 'later' else 'closed' end, a.id
from added a;

-- RLS hides the demo campus from anon, so its ID is looked up here.
create temp table campus_ids on commit drop as
select case when is_demo then 'demo' else 'closed' end as name, id
from public.universities where is_demo or email_domain = 'closed.edu';
grant select on campus_ids to anon;
select ok(exists (select 1 from public.games g join campus_ids c on c.id = g.university_id and c.name = 'demo'
                  where g.cancelled_at is null and g.ends_at > now() and g.going_count < g.capacity),
    'the demo campus has open games a student there would see');

-- Signed out.
set local role anon;
select pg_temp.act_as(null);

select is(
    (select title from public.guest_games((select id from public.university_lookup where email_domain = 'tec.mx'))
     where id = (select id from game_ids where name = 'open')),
    'Pickup game', 'a guest sees an open Tec game'
);
select is(
    (select array[going_count, spots_left, capacity]
     from public.guest_games((select id from public.university_lookup where email_domain = 'tec.mx'))
     where id = (select id from game_ids where name = 'open')),
    array[1, 5, 6], 'with how many are going and the room left'
);
select is(
    (select proargnames from pg_proc where oid = 'public.guest_games(uuid)'::regprocedure),
    array['p_university', 'id', 'activity_slug', 'title', 'starts_at', 'duration_minutes', 'ends_at', 'capacity',
          'going_count', 'spots_left', 'place_name', 'place_address', 'lat', 'lng', 'reposted_at', 'created_at', 'sort_at'],
    'no names, note, meet-up spot or per-viewer columns'
);
select is_empty(
    $$ select 1 from public.guest_games((select id from public.university_lookup where email_domain = 'tec.mx'))
       where id = (select id from game_ids where name = 'full') $$,
    'full games are left out'
);
select is_empty(
    $$ select 1 from public.guest_games((select id from public.university_lookup where email_domain = 'tec.mx'))
       where id = (select id from game_ids where name = 'cancelled') $$,
    'cancelled games are left out'
);
select is_empty(
    $$ select 1 from public.guest_games((select id from public.university_lookup where email_domain = 'tec.mx'))
       where id = (select id from game_ids where name = 'ended') $$,
    'ended games are left out'
);
select is_empty(
    $$ select 1 from public.guest_games((select id from public.university_lookup where email_domain = 'tec.mx'))
       where id = (select id from game_ids where name = 'later') $$,
    'games more than 7 days out are left out'
);
select ok(
    (select coalesce(bool_and(sort_at >= next_sort_at), true) from (
        select t.sort_at, lead(t.sort_at) over (order by t.ordinality) as next_sort_at
        from public.guest_games((select id from public.university_lookup where email_domain = 'tec.mx'))
             with ordinality as t
    ) ordered),
    'newest bump first'
);

select is_empty($$ select 1 from public.guest_games((select id from campus_ids where name = 'demo')) $$,
    'the hidden demo campus shows guests nothing');
select is_empty($$ select 1 from public.guest_games((select id from campus_ids where name = 'closed')) $$,
    'a closed campus shows guests nothing');
select is_empty($$ select 1 from public.guest_games(null) $$, 'no campus, no games');

-- Everything else about games stays closed to anon.
select throws_ok($$ select 1 from public.game_cards $$, '42501', null, 'signed out, game_cards stays closed');
select throws_ok($$ select 1 from public.games $$, '42501', null, 'signed out, games stays closed');
select throws_ok($$ select 1 from public.rsvps $$, '42501', null, 'signed out, rsvps stays closed');
select throws_ok($$ select 1 from public.game_attendees $$, '42501', null, 'signed out, Who''s going stays closed');

select * from finish();
rollback;
