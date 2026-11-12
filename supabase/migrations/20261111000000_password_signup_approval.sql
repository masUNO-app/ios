-- Sign-up with a school email and a password, approved by hand (SPEC N36). Tec IT hasn't approved
-- the Entra app, so school SSO can't be the way in. A new student signs up with their school
-- address; the team gets a Discord alert and approves or rejects the account in the SQL editor
-- (README, "Sign-up approvals"). Until then every write RPC answers `pending_approval`, and with
-- no profile the account reads nothing. The SSO branch of the hook stays for the day Tec says yes.

-- One row per address that signed up with a password. Keyed by email, not user id: the hook runs
-- before the Auth user exists.
create table private.signup_requests (
    email text primary key check (email = lower(email)),
    requested_at timestamptz not null default now(),
    approved_at timestamptz
);
alter table private.signup_requests enable row level security;
revoke all on private.signup_requests from public, anon, authenticated;

-- Posts "New sign-up" with the two lines to paste. Uses `signup_alert_webhook_url` from Vault,
-- or the report alerts' webhook when that isn't set. A failure is logged and never blocks the
-- sign-up: the row is still in private.signup_requests.
create or replace function private.alert_signup_request(p_email text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_webhook_url text;
    v_sql_editor_url text;
    v_message text;
begin
    select decrypted_secret into v_webhook_url from vault.decrypted_secrets where name = 'signup_alert_webhook_url';
    if v_webhook_url is null then
        select decrypted_secret into v_webhook_url from vault.decrypted_secrets where name = 'report_alert_webhook_url';
    end if;
    if v_webhook_url is null then
        raise warning 'sign-up % not alerted: no webhook URL in Vault', p_email;
        return;
    end if;
    select regexp_replace(decrypted_secret, '/editor/?$', '/sql/new') into v_sql_editor_url
    from vault.decrypted_secrets where name = 'report_alert_dashboard_url';

    v_message := format(
        E'New sign-up waiting for approval: %s\nApprove: `select private.approve_signup(%L);`\nReject: `select private.reject_signup(%L);`\n%s',
        p_email, p_email, p_email,
        coalesce('Run one in the SQL editor: ' || v_sql_editor_url, 'Run one in the Supabase SQL editor.')
    );
    -- Discord reads "content" and Slack reads "text"; each ignores the other.
    perform net.http_post(
        url := v_webhook_url,
        body := jsonb_build_object('content', v_message, 'text', v_message, 'allowed_mentions', jsonb_build_object('parse', '[]'::jsonb)),
        headers := '{"Content-Type": "application/json"}'::jsonb
    );
exception when others then
    raise warning 'sign-up % not alerted: %', p_email, sqlerrm;
end $$;

-- Records the request and alerts the team, once per address: signing up again with an address
-- that's already waiting (or already approved) changes nothing.
create or replace function private.request_signup(p_email text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
    insert into private.signup_requests (email) values (p_email) on conflict (email) do nothing;
    if found then
        perform private.alert_signup_request(p_email);
    end if;
end $$;

-- Whether this account signed up with a password and nobody has approved it yet. Allowlisted and
-- SSO accounts never have a request, so they're never pending.
create or replace function private.signup_pending(p_user_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from auth.users u join private.signup_requests r on r.email = lower(u.email)
        where u.id = p_user_id and r.approved_at is null
    )
$$;

-- For the team, in the SQL editor. Returns a line saying what happened.
create or replace function private.approve_signup(p_email text)
returns text language plpgsql security definer set search_path = ''
as $$
declare v_email text := lower(btrim(p_email));
begin
    update private.signup_requests set approved_at = now() where email = v_email and approved_at is null;
    if not found then return 'Nothing to approve for ' || v_email; end if;
    return 'Approved ' || v_email;
end $$;

-- Rejecting deletes the unapproved account, so the address can ask again later. An account that
-- was already approved is banned instead (README, Moderation).
create or replace function private.reject_signup(p_email text)
returns text language plpgsql security definer set search_path = ''
as $$
declare v_email text := lower(btrim(p_email));
begin
    delete from private.signup_requests where email = v_email and approved_at is null;
    if not found then return 'Nothing to reject for ' || v_email; end if;
    delete from auth.users u
    where lower(u.email) = v_email and not exists (select 1 from public.profiles p where p.id = u.id);
    return 'Rejected ' || v_email;
end $$;

-- Before User Created hook. Deny by default. Lets through: an allowlisted address with any
-- provider; a school address through that school's own SSO provider; and now a school address
-- with a password, which starts out waiting for approval. Returning {} lets the sign-up through.
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
    if v_provider = 'email' and exists (
        select 1 from public.universities u
        where u.email_domain = split_part(v_email, '@', 2)
          and u.signup_enabled and not u.is_demo
          and (u.student_email_pattern is null or v_email ~ u.student_email_pattern)
    ) then
        perform private.request_signup(v_email);
        return '{}'::jsonb;
    end if;
    return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'email_not_allowed'));
end $$;

-- Every write RPC starts here, so an account that's still waiting can't create a profile, and
-- without a profile RLS shows it nothing.
create or replace function private.require_active()
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_user();
begin
    if exists (select 1 from public.profiles where id = v_id and banned_at is not null) then
        raise exception 'suspended';
    end if;
    if private.signup_pending(v_id) then
        raise exception 'pending_approval';
    end if;
    return v_id;
end $$;

-- What the app asks after sign-in when there's no profile yet: 'pending' or 'approved'.
create or replace function public.signup_status()
returns text language sql stable security definer set search_path = ''
as $$
    select case when private.signup_pending(private.require_user()) then 'pending' else 'approved' end
$$;

revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.blocked_pair(uuid, uuid), private.same_university(uuid, uuid) to authenticated;
revoke execute on function public.before_user_created(jsonb) from public, anon, authenticated;
grant execute on function public.before_user_created(jsonb) to supabase_auth_admin;
revoke execute on function public.signup_status() from public, anon;
grant execute on function public.signup_status() to authenticated;
