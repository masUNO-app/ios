-- Local-only data for `supabase db reset` (B1). Hosted projects get campuses, the demo campus and
-- review accounts from migrations; never run this on masuno-prod.

-- Two password test accounts on Tec. Create them in Studio (Authentication → Add user, with
-- "Auto confirm" on); the auth hook lets them in because they're allowlisted here.
insert into public.auth_allowlist (email, note, university_id)
select v.email, v.note, u.id
from (values
    ('official.masuno.app+local1@gmail.com', 'Local test account 1'),
    ('official.masuno.app+local2@gmail.com', 'Local test account 2')
) as v(email, note)
cross join public.universities u
where u.email_domain = 'tec.mx'
on conflict (email) do nothing;

-- Tec hosts with no password, so the Tec map isn't empty locally.
with hosts(id, first_name, last_name, grad_year) as (values
    ('7ec00000-0000-4000-8000-000000000001'::uuid, 'Ana', 'López', 2027),
    ('7ec00000-0000-4000-8000-000000000002'::uuid, 'Luis', 'Martínez', 2026)
), new_users as (
    insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data,
                            confirmation_token, recovery_token, email_change_token_new, email_change,
                            created_at, updated_at)
    select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
           'seed-host-' || right(id::text, 1) || '@seed.masuno.invalid',
           '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, '', '', '', '', now(), now()
    from hosts
    on conflict (id) do nothing
    returning id
)
insert into public.profiles (id, university_id, first_name, last_name, grad_year, interests, guidelines_accepted_at)
select h.id, u.id, h.first_name, h.last_name, h.grad_year, array['basketball', 'padel'], now()
from hosts h join new_users n on n.id = h.id cross join public.universities u
where u.email_domain = 'tec.mx';

-- Upcoming Tec games, including singles tennis with one spot left for a two-phone race.
with tec as (select id from public.universities where email_domain = 'tec.mx'),
games(host_id, activity_slug, title, days_ahead, capacity, place_name, place_address, lat, lng) as (values
    ('7ec00000-0000-4000-8000-000000000001'::uuid, 'basketball', 'Pickup after class', 1, 6, 'Arena Borregos', 'Av. Junco de la Vega, Tecnológico, Monterrey, N.L.', 25.6531, -100.2925),
    ('7ec00000-0000-4000-8000-000000000002'::uuid, 'tennis', 'Singles, any level', 2, 2, 'Tec tennis courts', 'Av. Eugenio Garza Sada 2501 Sur, Tecnológico, Monterrey, N.L.', 25.6502, -100.2918),
    ('7ec00000-0000-4000-8000-000000000001'::uuid, 'padel', 'Padel doubles', 3, 4, 'Centro Deportivo Tec', 'Av. Fernando García Roel, Tecnológico, Monterrey, N.L.', 25.6475, -100.2905)
), new_games as (
    insert into public.games (university_id, host_id, activity_slug, title, starts_at, duration_minutes, ends_at,
                              capacity, place_name, place_address, lat, lng)
    select tec.id, g.host_id, g.activity_slug, g.title,
           date_trunc('hour', now()) + make_interval(days => g.days_ahead, hours => 2), 60,
           date_trunc('hour', now()) + make_interval(days => g.days_ahead, hours => 3),
           g.capacity, g.place_name, g.place_address, g.lat, g.lng
    from games g cross join tec
    where exists (select 1 from public.profiles where id = g.host_id)
      and not exists (select 1 from public.games existing where existing.host_id = g.host_id and existing.title = g.title)
    returning id, host_id
)
insert into public.rsvps (event_id, user_id, role) select id, host_id, 'host' from new_games;
