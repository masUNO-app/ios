-- Server-driven activity catalog (20261126000000): versions, the catalog each build gets, the
-- legacy row policy for 0.9, posting rules, colors that stay readable, and drawing names the app has.
begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true)
$$;

-- WCAG contrast of a hex color against ink #1F2638, the bar ContrastTests uses for sport colors.
create function pg_temp.luminance(p_hex text) returns double precision language sql immutable as $$
    select 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
    from (select array(
        select case when v <= 0.04045 then v / 12.92 else power((v + 0.055) / 1.055, 2.4) end
        from (select ('x' || substr(p_hex, i, 2))::bit(8)::int / 255.0 as v, i
              from unnest(array[2, 4, 6]) i order by i) parts
    ) as c) channels
$$;
create function pg_temp.contrast_with_ink(p_hex text) returns double precision language sql immutable as $$
    select (greatest(pg_temp.luminance(p_hex), pg_temp.luminance('#1F2638')) + 0.05)
         / (least(pg_temp.luminance(p_hex), pg_temp.luminance('#1F2638')) + 0.05)
$$;

insert into auth.users (id, email) values ('a0000000-0000-4000-8000-00000000000a', 'alice@tec.mx');

-- Versions compare part by part.
select ok(private.version_at_least('0.10', '0.9'), '0.10 comes after 0.9');
select ok(not private.version_at_least('0.9', '0.10'), 'and 0.9 before 0.10');
select ok(private.version_at_least('1', '1.0') and private.version_at_least('1.0.0', '1'), '1, 1.0 and 1.0.0 are equal');
select ok(not private.version_at_least('beta', '0.5'), 'something that isn''t a version is never enough');

-- Each build gets what it can show.
select is(
    (select array_agg(k->>'slug' order by ord) from jsonb_array_elements(public.activity_catalog('0.9')->'kinds') with ordinality t(k, ord)),
    array['sport'], '0.9 gets sports only');
select is(
    (select array_agg(a->>'slug' order by ord) from jsonb_array_elements(public.activity_catalog('0.9')->'activities') with ordinality t(a, ord)),
    array['basketball', 'tennis', 'soccer', 'volleyball', 'padel'], 'and the five sports, in order');
select is(
    (select array_agg(k->>'slug' order by ord) from jsonb_array_elements(public.activity_catalog('1.0')->'kinds') with ordinality t(k, ord)),
    array['sport', 'esports'], '1.0 gets esports too');
select is(
    (select array_agg(a->>'slug' order by ord) from jsonb_array_elements(public.activity_catalog('1.0')->'activities') with ordinality t(a, ord)),
    array['basketball', 'tennis', 'soccer', 'volleyball', 'padel', 'valorant', 'csgo', 'league'], 'with its three titles');
select is(jsonb_array_length(public.activity_catalog('0.10')->'kinds'), 1, 'esports waits for 1.0 (20261126000200)');
select is(jsonb_array_length(public.activity_catalog('not a version')->'kinds'), 1, 'a version that can''t be read gets the base catalog');
select is(public.activity_catalog('1.0')->'kinds'->1->>'supports_rotation', 'true', 'esports turns round nights on');
select is(public.activity_catalog('1.0')->'activities'->0->>'color', '#F2853A', 'basketball has its color from the app');

-- 0.9 reads the table directly and sees no esports, signed out or in.
set local role anon;
select pg_temp.act_as(null);
select is((select array_agg(slug order by sort_order) from public.activities),
    array['basketball', 'tennis', 'soccer', 'volleyball', 'padel'], 'signed out, 0.9 sees the five sports');
select lives_ok($$ select public.activity_catalog('1.0') $$, 'signed out, a new build reads the catalog');
select is((select count(*)::int from public.activity_kinds), 2, 'kinds are readable signed out');
set local role authenticated;
select pg_temp.act_as('a0000000-0000-4000-8000-00000000000a');
select is((select count(*)::int from public.activities where kind = 'esports'), 0, 'signed in, 0.9 sees no esports either');

-- Posting: an esports title can be posted, until its kind is switched off.
select public.complete_profile('Alice', 'Zamora', 2027, array['basketball'], 'en');
select lives_ok($$ select public.create_game('valorant', 'Valorant night', now() + interval '1 day', 60, 6, null,
    'Game room', 'Tec', 25.65, -100.29, null, true) $$, 'an esports title can be posted');
reset role;
update public.activity_kinds set active = false where slug = 'esports';
set local role authenticated;
select throws_ok($$ select public.create_game('csgo', 'CS night', now() + interval '1 day', 60, 6, null,
    'Game room', 'Tec', 25.65, -100.29, null, true) $$, 'P0001', 'invalid_input', 'not once its kind is off');
reset role;
update public.activity_kinds set active = true where slug = 'esports';

-- What people type into SQL is checked.
select throws_ok($$ insert into public.activities (slug, kind, label_en, label_es, emoji, sort_order)
    values ('chess', 'board_games', 'Chess', 'Ajedrez', '♟️', 200) $$, '23503', null, 'an activity needs a kind that exists');
select throws_ok($$ update public.activities set color = '#f2853a' where slug = 'basketball' $$, '23514', null,
    'colors are upper-case hex');
select throws_ok($$ insert into public.activity_kinds (slug, label_en, label_es, item_label_en, item_label_es,
    title_placeholder_en, title_placeholder_es, min_app_version, sort_order)
    values ('hackathon', 'Hackathons', 'Hackathons', 'Event', 'Evento', 'e.g.', 'p. ej.', 'soon', 3) $$, '23514', null,
    'a kind''s version must be a version');

-- Every color stays readable with ink on it, and every drawing is one the app has (`CourtKind`).
select is_empty($$ select slug from public.activities
    where (color is not null and pg_temp.contrast_with_ink(color) < 4.5)
       or (color_dark is not null and pg_temp.contrast_with_ink(color_dark) < 4.5) $$,
    'every color reaches 4.5:1 against ink');
select is_empty($$ select coalesce(art, '') from public.activities where art is not null
        and art not in ('basketball', 'tennis', 'soccer', 'volleyball', 'padel', 'screen', 'generic')
    union all
    select default_art from public.activity_kinds
    where default_art not in ('basketball', 'tennis', 'soccer', 'volleyball', 'padel', 'screen', 'generic') $$,
    'every drawing name is a CourtKind');

-- Pushes carry the color, and only the server can claim them.
select ok((select prosrc like '%''color'', a.color%' from pg_proc
           where oid = 'private.claim_notifications_ordered(integer)'::regprocedure), 'push context includes the color');
select ok(not has_function_privilege('anon', 'private.version_at_least(text, text)', 'execute'),
    'the version helper stays private');

select * from finish();
rollback;
