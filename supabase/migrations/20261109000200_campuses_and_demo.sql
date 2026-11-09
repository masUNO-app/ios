-- Launch campus, the hidden App Review demo campus (C12) and its daily refresh, and the allowlisted
-- review/QA addresses (B4). Both projects need these, so they live in a migration, not seed.sql.

create extension if not exists pg_cron;

insert into public.universities (name, short_name, email_domain, sso_provider, signup_enabled, center_lat, center_lng, timezone)
values ('Tec de Monterrey', 'Tec', 'tec.mx', 'azure', true, 25.6514, -100.2895, 'America/Monterrey')
on conflict (email_domain) do nothing;

insert into public.universities (name, short_name, email_domain, sso_provider, signup_enabled, is_demo, center_lat, center_lng, timezone)
values ('masUNO Demo', 'Demo', 'demo.masuno.invalid', null, false, true, 25.6600, -100.3000, 'America/Monterrey')
on conflict (email_domain) do nothing;

-- Password accounts are created in the dashboard with the email confirmed (README); passwords
-- live in the shared password manager, never here.
insert into public.auth_allowlist (email, note, university_id)
select v.email, v.note, u.id
from (values
    ('official.masuno.app+review1@gmail.com', 'App Review account 1'),
    ('official.masuno.app+review2@gmail.com', 'App Review account 2'),
    ('official.masuno.app+qa1@gmail.com', 'QA third phone (last-spot race)')
) as v(email, note)
cross join public.universities u
where u.is_demo
on conflict (email) do nothing;

-- Demo hosts are Auth users with no password and an undeliverable address, so nobody can sign in
-- as them. Inserted directly, so the before-user-created hook doesn't run.
create table private.demo_hosts (
    user_id uuid primary key references public.profiles(id) on delete cascade
);
revoke all on private.demo_hosts from public, anon, authenticated;

with hosts(id, first_name, last_name, grad_year) as (values
    ('d0000000-0000-4000-8000-000000000001'::uuid, 'Sofía', 'Ramírez', 2027),
    ('d0000000-0000-4000-8000-000000000002'::uuid, 'Diego', 'Treviño', 2026),
    ('d0000000-0000-4000-8000-000000000003'::uuid, 'Valeria', 'Garza', 2028),
    ('d0000000-0000-4000-8000-000000000004'::uuid, 'Mateo', 'Cantú', 2027)
), new_users as (
    insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data,
                            confirmation_token, recovery_token, email_change_token_new, email_change,
                            created_at, updated_at)
    select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
           'demo-host-' || right(id::text, 1) || '@demo.masuno.invalid',
           '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, '', '', '', '', now(), now()
    from hosts
    on conflict (id) do nothing
    returning id
), new_profiles as (
    insert into public.profiles (id, university_id, first_name, last_name, grad_year, interests, guidelines_accepted_at)
    select h.id, u.id, h.first_name, h.last_name, h.grad_year, array['basketball', 'soccer'], now()
    from hosts h join new_users n on n.id = h.id cross join public.universities u
    where u.is_demo
    returning id
)
insert into private.demo_hosts (user_id) select id from new_profiles;

-- Tops the demo campus up to 6 upcoming, joinable games, and removes demo games that ended over a
-- day ago. Games that review accounts host are left alone.
-- Returns the number of games created.
create or replace function private.refresh_demo_campus()
returns integer language plpgsql security definer set search_path = ''
as $$
declare
    v_campus public.universities%rowtype;
    v_hosts uuid[];
    v_upcoming integer;
    v_created integer := 0;
    v_template record;
    v_host uuid;
    v_player uuid;
    v_starts_at timestamptz;
    v_game uuid;
begin
    select * into v_campus from public.universities where is_demo order by created_at limit 1;
    if not found then
        raise warning 'refresh_demo_campus: no demo campus row';
        return 0;
    end if;
    select array_agg(user_id order by user_id) into v_hosts from private.demo_hosts;
    if coalesce(array_length(v_hosts, 1), 0) < 2 then
        raise warning 'refresh_demo_campus: needs at least 2 demo hosts';
        return 0;
    end if;

    delete from public.games
    where university_id = v_campus.id and host_id = any(v_hosts) and ends_at < now() - interval '1 day';

    select count(*) into v_upcoming from public.games
    where university_id = v_campus.id and host_id = any(v_hosts)
      and cancelled_at is null and starts_at > now() + interval '1 hour' and going_count < capacity;

    for v_template in
        select * from (values
            (1, 'basketball', 'Pickup 3v3, all levels', 60, 6, 19, 'Arena Borregos', 'Av. Junco de la Vega, Tecnológico, Monterrey, N.L.', 25.6531, -100.2925, 'Court 2, by the benches'),
            (2, 'soccer', 'Fútbol 7 after class', 90, 14, 18, 'Centro Deportivo Tec', 'Av. Fernando García Roel, Tecnológico, Monterrey, N.L.', 25.6475, -100.2905, 'Main gate'),
            (3, 'tennis', 'Doubles, bring a racket', 60, 4, 8, 'Tec tennis courts', 'Av. Eugenio Garza Sada 2501 Sur, Tecnológico, Monterrey, N.L.', 25.6502, -100.2918, null),
            (4, 'volleyball', 'Sunset volleyball', 60, 8, 17, 'Parque Distrito Tec', 'Calle Profr. Moisés Sáenz, Tecnológico, Monterrey, N.L.', 25.6553, -100.2889, 'Sand court'),
            (5, 'padel', 'Padel doubles', 90, 4, 20, 'Centro Deportivo Tec', 'Av. Fernando García Roel, Tecnológico, Monterrey, N.L.', 25.6475, -100.2905, null),
            (6, 'basketball', 'Shootaround before class', 30, 10, 10, 'Tec basketball courts', 'Av. Eugenio Garza Sada 2501 Sur, Tecnológico, Monterrey, N.L.', 25.6521, -100.2903, null)
        ) as t(slot, activity_slug, title, duration_minutes, capacity, local_hour, place_name, place_address, lat, lng, meet_point)
        where t.slot > v_upcoming
        order by t.slot
    loop
        v_host := v_hosts[1 + (v_template.slot % array_length(v_hosts, 1))];
        v_player := v_hosts[1 + ((v_template.slot + 1) % array_length(v_hosts, 1))];
        v_starts_at := (((now() at time zone v_campus.timezone)::date + v_template.slot)
                        + make_time(v_template.local_hour, 0, 0)) at time zone v_campus.timezone;

        insert into public.games (university_id, host_id, activity_slug, title, starts_at, duration_minutes, ends_at,
                                  capacity, going_count, place_name, place_address, lat, lng, meet_point)
        values (v_campus.id, v_host, v_template.activity_slug, v_template.title, v_starts_at, v_template.duration_minutes,
                v_starts_at + make_interval(mins => v_template.duration_minutes), v_template.capacity, 2,
                v_template.place_name, v_template.place_address, v_template.lat, v_template.lng, v_template.meet_point)
        returning id into v_game;
        insert into public.rsvps (event_id, user_id, role) values (v_game, v_host, 'host'), (v_game, v_player, 'player');
        perform private.activity_actor(v_game, 'created', v_host);
        perform private.activity_actor(v_game, 'joined', v_player);
        v_created := v_created + 1;
    end loop;
    return v_created;
end $$;

revoke execute on function private.refresh_demo_campus() from public, anon, authenticated;

-- 00:15 in Monterrey (UTC-6, no DST). Scheduling by name replaces an older job with the same name.
select cron.schedule('refresh-demo-campus', '15 6 * * *', 'select private.refresh_demo_campus()');
select private.refresh_demo_campus();
