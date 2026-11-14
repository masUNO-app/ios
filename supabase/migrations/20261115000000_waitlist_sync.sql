-- One waitlist (SPEC N38): the website's waitlist (a Google Sheet written by an Apps Script) and the
-- app's (private.signup_requests, N36/N37) become one queue, kept here and mirrored in the Sheet both
-- ways. A school email that joins on the website gets a request now, so it keeps its place when the
-- person signs up in the app later; any other email stays in the Sheet only, as launch news.
--
-- Website → here: the Apps Script calls `waitlist_join` with a shared secret. Here → website: every
-- change to a request is pushed to the Apps Script with pg_net, and the Apps Script heals anything it
-- missed with `waitlist_export` every hour. The secret and the Apps Script's URL live in Vault
-- (README, hosted checklist). Without them nothing is pushed and both RPCs refuse every call, so
-- local, CI and unconfigured projects work as before.
--
-- Compatible with 0.x and earlier 1.0 builds: nothing the app calls changes shape.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_net with schema extensions;

-- Where the request started. A website request stays 'website' after the person signs up in the app:
-- the account itself says they're in the app, and the Sheet computes "In the app" from that.
alter table private.signup_requests
    add column source text not null default 'app' check (source in ('app', 'website'));

-- Places in line are counted along this order, so each count is one short index range.
create index signup_requests_waiting_idx on private.signup_requests (requested_at, email) where approved_at is null;

-- Whether a password sign-up with this (lower-case, trimmed) address may ask to join: an open campus
-- that isn't the demo, with this exact domain, whose student pattern (if any) the address matches.
-- The auth hook and `waitlist_join` both ask this, so the website and the app take the same addresses.
create function private.open_campus_email(p_email text)
returns boolean language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.universities u
        where u.email_domain = split_part(p_email, '@', 2)
          and u.signup_enabled and not u.is_demo
          and (u.student_email_pattern is null or p_email ~ u.student_email_pattern)
    )
$$;

-- This address's place among the requests nobody has approved, by request time and then email, so two
-- people never share a place. 1 is next. Null when it has no request or is approved. The app's
-- `waitlist_position` and the website's `waitlist_join` both answer with this.
create function private.waitlist_place(p_email text)
returns integer language sql stable security definer set search_path = ''
as $$
    select (
        select count(*)::integer from private.signup_requests w
        where w.approved_at is null and (w.requested_at, w.email) <= (r.requested_at, r.email)
    )
    from private.signup_requests r
    where r.email = p_email and r.approved_at is null
$$;

-- ISO 8601 in UTC to the second ("2026-11-14T15:04:05Z") whatever the session's time zone. Null stays null.
create function private.iso_utc(p_time timestamptz)
returns text language sql immutable set search_path = ''
as $$
    select to_char(p_time at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
$$;

-- The requests with these emails (none when null), as the Sheet sees them, in line order:
-- a JSON array of {email, status, requested_at, approved_at, source, invited_by, position}. Status is
-- 'member' when the address has an account with a profile, 'approved' when approved without one yet,
-- and 'waiting' otherwise; position is the place in line while waiting, else null. invited_by is the
-- inviter's first name and last initial ("Ana G."). Shared by the push and `waitlist_export`.
create function private.waitlist_rows(p_emails text[])
returns jsonb language sql stable security definer set search_path = ''
as $$
    select coalesce(jsonb_agg(jsonb_build_object(
        'email', r.email,
        'status', s.status,
        'requested_at', private.iso_utc(r.requested_at),
        'approved_at', private.iso_utc(r.approved_at),
        'source', r.source,
        'invited_by', i.first_name || ' ' || i.last_initial || '.',
        'position', case when s.status = 'waiting' then private.waitlist_place(r.email) end
    ) order by r.requested_at, r.email), '[]'::jsonb)
    from private.signup_requests r
    left join public.profiles i on i.id = r.invited_by
    cross join lateral (
        select case
            when r.email in (select lower(u.email) from auth.users u join public.profiles p on p.id = u.id) then 'member'
            when r.approved_at is not null then 'approved'
            else 'waiting'
        end as status
    ) s
    where r.email = any(p_emails)
$$;

-- Whether a call carries the shared secret (Vault `waitlist_sync_secret`). False when it's missing or
-- shorter than 32 characters, so an unconfigured project refuses everything. The SHA-256 hashes are
-- compared rather than the secrets, so how long the comparison takes says nothing about the secret.
create function private.waitlist_secret_ok(p_secret text)
returns boolean language plpgsql stable security definer set search_path = ''
as $$
declare v_secret text;
begin
    select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'waitlist_sync_secret';
    if v_secret is null or char_length(v_secret) < 32 or p_secret is null then
        return false;
    end if;
    return extensions.digest(p_secret, 'sha256') = extensions.digest(v_secret, 'sha256');
end $$;

-- Posts {"action": "sync", "secret", "rows"} to the Apps Script (Vault `waitlist_sync_url`). pg_net
-- sends it after the transaction commits, so a rolled-back write sends nothing. Nothing to send, or
-- no URL or secret in Vault, means no request: a warning in the second case. A failure is logged and
-- never blocks the write; the hourly `waitlist_export` heals whatever a push missed.
create function private.send_waitlist_sync(p_rows jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_url text;
    v_secret text;
begin
    if p_rows is null or jsonb_array_length(p_rows) = 0 then
        return;
    end if;
    select decrypted_secret into v_url from vault.decrypted_secrets where name = 'waitlist_sync_url';
    select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'waitlist_sync_secret';
    if v_url is null or v_secret is null or char_length(v_secret) < 32 then
        raise warning 'waitlist not pushed to the Sheet: Vault secret waitlist_sync_url or waitlist_sync_secret is missing';
        return;
    end if;
    -- The Apps Script answers a POST with a redirect after it has run, so pg_net needn't follow it.
    -- Its cold start can take a few seconds, hence the longer timeout.
    perform net.http_post(
        url := v_url,
        body := jsonb_build_object('action', 'sync', 'secret', v_secret, 'rows', p_rows),
        headers := '{"Content-Type": "application/json"}'::jsonb,
        timeout_milliseconds := 15000
    );
exception when others then
    raise warning 'waitlist not pushed to the Sheet: %', sqlerrm;
end $$;

-- Pushes the requests a statement changed, once per statement however many rows it touched (one
-- `update ... set approved_at = now() where approved_at is null` approves everyone in one request).
-- Updates that only count wrong invite codes change nothing the Sheet shows, so they send nothing.
-- A deleted request (rejected) goes as 'removed'. Postgres only allows a transition table on a
-- single-event trigger, hence one trigger per event.
create function private.push_waitlist_requests()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_rows jsonb;
begin
    -- Each branch is only planned for the trigger that runs it, so it only names tables that trigger has.
    if tg_op = 'DELETE' then
        select jsonb_agg(jsonb_build_object(
            'email', o.email, 'status', 'removed', 'requested_at', private.iso_utc(o.requested_at),
            'approved_at', private.iso_utc(o.approved_at), 'source', o.source, 'invited_by', null, 'position', null
        ) order by o.requested_at, o.email) into v_rows
        from old_requests o;
    elsif tg_op = 'UPDATE' then
        select private.waitlist_rows(array_agg(n.email)) into v_rows
        from new_requests n left join old_requests o on o.email = n.email
        where o.email is null
           or (n.requested_at, n.approved_at, n.source, n.invited_by)
              is distinct from (o.requested_at, o.approved_at, o.source, o.invited_by);
    else
        select private.waitlist_rows(array_agg(n.email)) into v_rows from new_requests n;
    end if;
    perform private.send_waitlist_sync(v_rows);
    return null;
exception when others then
    raise warning 'waitlist not pushed to the Sheet: %', sqlerrm;
    return null;
end $$;

create trigger signup_requests_inserted_sync after insert on private.signup_requests
referencing new table as new_requests for each statement execute function private.push_waitlist_requests();
create trigger signup_requests_updated_sync after update on private.signup_requests
referencing old table as old_requests new table as new_requests for each statement execute function private.push_waitlist_requests();
create trigger signup_requests_deleted_sync after delete on private.signup_requests
referencing old table as old_requests for each statement execute function private.push_waitlist_requests();

-- A new profile turns its request into 'member' ("In the app" in the Sheet) without touching the
-- request, so push it from here. One primary-key lookup per profile; profiles without a request
-- (allowlisted, SSO, the demo campus) send nothing. A deleted account isn't pushed: its email is gone
-- by the time this would run, so the hourly export corrects it.
create function private.push_waitlist_members()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_emails text[];
begin
    select array_agg(r.email) into v_emails
    from new_profiles n
    join auth.users u on u.id = n.id
    join private.signup_requests r on r.email = lower(u.email);
    if v_emails is not null then
        perform private.send_waitlist_sync(private.waitlist_rows(v_emails));
    end if;
    return null;
exception when others then
    raise warning 'waitlist not pushed to the Sheet: %', sqlerrm;
    return null;
end $$;

create trigger profiles_inserted_waitlist_sync after insert on public.profiles
referencing new table as new_profiles for each statement execute function private.push_waitlist_members();

-- Records an app sign-up. A new address gets a request and the team an alert, as before. An address
-- that joined on the website already has one: it keeps its place (requested_at) and its source, and
-- the team still gets the alert, because only now is there an account to approve, unless the team
-- approved the address in advance (then the account is let straight in: signup_pending reads
-- approved_at). Any other address that's already waiting or approved changes nothing.
create or replace function private.request_signup(p_email text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
    insert into private.signup_requests (email) values (p_email) on conflict (email) do nothing;
    if found or exists (
        select 1 from private.signup_requests
        where email = p_email and source = 'website' and approved_at is null
    ) then
        perform private.alert_signup_request(p_email);
    end if;
end $$;

-- As in 20261111000000, with the password branch's campus check moved into private.open_campus_email.
-- Same behaviour.
create or replace function public.before_user_created(event jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
    v_email text := lower(btrim(coalesce(event->'user'->>'email', '')));
    v_provider text := coalesce(event->'user'->'app_metadata'->>'provider', 'email');
begin
    if v_email <> '' and exists (select 1 from public.auth_allowlist where email = v_email) then
        return '{}'::jsonb;
    end if;
    if exists (
        select 1 from public.universities u
        where u.email_domain = split_part(v_email, '@', 2)
          and u.sso_provider = v_provider
          and u.signup_enabled and not u.is_demo
          and (u.student_email_pattern is null or v_email ~ u.student_email_pattern)
    ) then
        return '{}'::jsonb;
    end if;
    if v_provider = 'email' and private.open_campus_email(v_email) then
        perform private.request_signup(v_email);
        return '{}'::jsonb;
    end if;
    return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'email_not_allowed'));
end $$;

-- As in 20261114000000, counting through private.waitlist_place, which website requests are part of.
create or replace function public.waitlist_position()
returns integer language plpgsql stable security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_user();
    v_email text;
begin
    select lower(u.email) into v_email from auth.users u where u.id = v_id;
    return private.waitlist_place(v_email);
end $$;

-- The website's Apps Script calls this when someone joins the waitlist there, and again for any row
-- the hourly heal finds unsynced. Callable by anon, so the secret is the only gate.
-- Parameters: the shared secret; the email as typed (trimmed and lower-cased here); when they joined
-- on the website; and the source, which must be 'website' (or null).
-- Returns {"ok": true, "status": "waiting" | "approved" | "member" | "not_school", "position": int | null},
-- {"ok": false, "error": "bad_secret"} without the right secret, or {"ok": false, "error": "invalid_input"}
-- for another source. Nothing is raised, so the Apps Script always gets an answer it can read.
--
-- 'not_school' (also for anything that isn't an email, or is longer than 254 characters) stores
-- nothing. Otherwise the request exists afterwards: a new one is a website request at the join time,
-- and an existing one moves to the join time only if that's earlier, so the first join keeps its
-- place. The join time is taken as now when it's missing, in the future, or before 2026, so a broken
-- date never jumps the line. No Discord alert: there's no account to approve yet; it comes when the
-- person signs up in the app (`request_signup`). An address that already has an account without a
-- request (allowlisted, SSO, or from before approvals) or that's allowlisted gets no request either,
-- since one would make it wait: it answers 'member' or 'approved'.
create function public.waitlist_join(p_secret text, p_email text, p_joined_at timestamptz, p_source text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_joined_at timestamptz := p_joined_at;
    v_row jsonb;
begin
    if not private.waitlist_secret_ok(p_secret) then
        return jsonb_build_object('ok', false, 'error', 'bad_secret');
    end if;
    if coalesce(p_source, 'website') <> 'website' then
        return jsonb_build_object('ok', false, 'error', 'invalid_input');
    end if;
    if char_length(v_email) > 254
       or v_email !~ '^[^@[:space:][:cntrl:]]+@[^@[:space:][:cntrl:]]+$'
       or not private.open_campus_email(v_email) then
        return jsonb_build_object('ok', true, 'status', 'not_school', 'position', null);
    end if;

    if not exists (select 1 from private.signup_requests where email = v_email) and (
        exists (select 1 from public.auth_allowlist where email = v_email)
        or exists (select 1 from auth.users u where lower(u.email) = v_email)
    ) then
        return jsonb_build_object('ok', true, 'position', null, 'status', case
            when exists (select 1 from auth.users u join public.profiles p on p.id = u.id where lower(u.email) = v_email)
            then 'member' else 'approved' end);
    end if;

    if v_joined_at is null or v_joined_at < '2026-01-01T00:00:00Z' then
        v_joined_at := now();
    end if;
    v_joined_at := least(v_joined_at, now());

    insert into private.signup_requests as r (email, requested_at, source) values (v_email, v_joined_at, 'website')
    on conflict (email) do update set requested_at = excluded.requested_at
    where excluded.requested_at < r.requested_at;

    v_row := private.waitlist_rows(array[v_email]) -> 0;
    return jsonb_build_object('ok', true, 'status', v_row->'status', 'position', v_row->'position');
end $$;

-- The Apps Script's hourly heal: every request, in line order, shaped as in the push
-- (private.waitlist_rows). Without the right secret, an empty array, so a wrong call learns nothing.
create function public.waitlist_export(p_secret text)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
    if not private.waitlist_secret_ok(p_secret) then
        return '[]'::jsonb;
    end if;
    return private.waitlist_rows(array(select email from private.signup_requests));
end $$;

-- Functions created above get the default EXECUTE grant, so repeat the lock-down. The two waitlist
-- RPCs are the only ones here anon may call: the Apps Script has just the anon key, and the secret
-- is what keeps everyone else out.
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.blocked_pair(uuid, uuid), private.same_university(uuid, uuid) to authenticated;
revoke execute on function public.before_user_created(jsonb) from public, anon, authenticated;
grant execute on function public.before_user_created(jsonb) to supabase_auth_admin;
revoke execute on function public.waitlist_position() from public, anon;
grant execute on function public.waitlist_position() to authenticated;
revoke execute on function public.waitlist_join(text, text, timestamptz, text), public.waitlist_export(text)
    from public, anon, authenticated;
grant execute on function public.waitlist_join(text, text, timestamptz, text), public.waitlist_export(text) to anon;
