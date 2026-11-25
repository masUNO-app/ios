-- Email codes fail closed (N39). 20261128000000 records a request only when a code is entered, so with
-- "Confirm email" off (Supabase signs a new account straight in) a school address got in with no request,
-- no alert and no waitlist: before 1.0's settings are switched on, or if anyone ever turns them off. Now:
--
-- 1. A password account confirmed without any code we emailed falls back to N36: it gets a request that
--    waits (not verified), and the team gets the approval alert saying the address isn't verified. That
--    covers "Confirm email" off and accounts the team makes in the dashboard; allowlisted addresses still
--    go straight in, as the dashboard's review and QA accounts always have.
-- 2. An account confirmed at creation (no update to watch) is caught by a second trigger, on insert.
-- 3. A password account with no profile, no request and no allowlist entry waits, so nothing gets in
--    unrecorded even if both triggers were bypassed.
-- 4. `approve_signup` approves such an account too, by giving it an approved request.
--
-- Compatible with earlier builds: nothing they call changes shape.

-- As in 20261128000000, saying whether the address was verified: with "Confirm email" off it wasn't.
create or replace function private.alert_signup_request(p_email text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_sql_editor_url text;
    v_request private.signup_requests%rowtype;
begin
    select r.* into v_request from private.signup_requests r where r.email = p_email;
    select regexp_replace(decrypted_secret, '/editor/?$', '/sql/new') into v_sql_editor_url
    from vault.decrypted_secrets where name = 'report_alert_dashboard_url';
    perform private.post_account_alert(format(
        E'New sign-up waiting for approval (%s): %s\n'
        'Approve: `select private.approve_signup(email) from private.signup_requests where id = %L;`\n'
        'Reject: `select private.reject_signup(email) from private.signup_requests where id = %L;`\n%s',
        case when v_request.verified_at is not null then 'email verified'
             else 'email NOT verified: is "Confirm email" off?' end,
        private.mask_email(p_email), v_request.id, v_request.id,
        coalesce('Run one in the SQL editor: ' || v_sql_editor_url, 'Run one in the Supabase SQL editor.')
    ));
exception when others then
    raise warning 'sign-up request % not alerted: %', v_request.id, sqlerrm;
end $$;

-- As in 20261128000000, plus the fallback: confirmed with no code sent means nothing proved the inbox,
-- so it's N36's manual approval (`request_signup`), unless the address is allowlisted.
create or replace function private.on_auth_email_verified()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
    if coalesce(new.raw_app_meta_data->>'provider', '') <> 'email' then
        return null;
    end if;
    if coalesce(new.confirmation_sent_at, new.recovery_sent_at) is not null then
        perform private.signup_verified(new.email);
    elsif not exists (select 1 from public.auth_allowlist where email = lower(btrim(new.email))) then
        perform private.request_signup(lower(btrim(new.email)));
    end if;
    return null;
end $$;

create trigger auth_users_email_confirmed_at_insert
after insert on auth.users
for each row when (new.email_confirmed_at is not null)
execute function private.on_auth_email_verified();

-- As in 20261128000000, and also true for a password account that has no record at all: no profile,
-- no request and not allowlisted. Members, the dashboard's allowlisted accounts and SSO accounts don't
-- count.
create or replace function private.signup_pending(p_user_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
    select private.email_unverified(p_user_id) or exists (
        select 1 from auth.users u
        left join private.signup_requests r on r.email = lower(u.email)
        where u.id = p_user_id and (
            (r.email is not null and r.approved_at is null)
            or (r.email is null
                and u.raw_app_meta_data->>'provider' = 'email'
                and not exists (select 1 from public.profiles p where p.id = u.id)
                and not exists (select 1 from public.auth_allowlist a where a.email = lower(u.email)))
        )
    )
$$;

-- As in 20261128000000, and an account with no request gets an approved one, so the line above lets it in.
create or replace function private.approve_signup(p_email text)
returns text language plpgsql security definer set search_path = ''
as $$
declare v_email text := lower(btrim(p_email));
begin
    update private.signup_requests set approved_at = now() where email = v_email and approved_at is null;
    if not found then
        if exists (select 1 from private.signup_requests where email = v_email)
           or not exists (select 1 from auth.users where lower(email) = v_email) then
            return 'Nothing to approve for ' || v_email;
        end if;
        insert into private.signup_requests (email, approved_at) values (v_email, now());
    end if;
    perform private.notify_signup_approved(v_email);
    return 'Approved ' || v_email;
end $$;

revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.blocked_pair(uuid, uuid), private.same_university(uuid, uuid),
    private.active_viewer(), private.blocked_someone_going(uuid) to authenticated;
