-- Email codes (1.0, SPEC N39; amends N36/N37). "Confirm email" is on, and the confirmation email
-- carries a 6-digit code instead of a link, so a sign-up proves the person owns the address. The team
-- no longer has to vouch for it. Sign-up stays invite-only: a verified account joins the waitlist as
-- before, and a member's or the team's code still skips it. `app_config.signup_auto_approve` opens
-- sign-up: while it's true, verifying is enough to get in (`private.set_signup_auto_approve`, README,
-- "Sign-up approvals"). Password resets use the same kind of code; nothing here changes for them.
--
-- The request now starts when the address is verified, not when the account is created: the auth hook
-- only decides who may sign up, and a trigger on auth.users records the request once the code is
-- entered. Typing someone else's address no longer takes a place in line or alerts the team.
--
-- Compatible with earlier builds as far as the server goes: nothing they call changes shape, and
-- `signup_status` answers 'unverified' only to accounts those builds can't create. Those builds can't
-- sign up once "Confirm email" is on (they expect a session from signUp), so `min_supported_version`
-- goes up with 1.0 (README, hosted checklist).

-- When the address was proven. Null for website requests that have no account yet, and for requests
-- from before this migration until the person enters a code.
alter table private.signup_requests add column verified_at timestamptz;

-- Whether sign-up is open: a verified account goes straight in. Off at launch (invite-only).
insert into public.app_config (key, value) values ('signup_auto_approve', 'false') on conflict (key) do nothing;

create function private.signup_auto_approve()
returns boolean language sql stable security definer set search_path = ''
as $$
    select coalesce((select value from public.app_config where key = 'signup_auto_approve'), 'false'::jsonb) = 'true'::jsonb
$$;

-- A password account that hasn't entered its code yet. Accounts with a profile never count, so a
-- member can't be locked out by an odd auth row; accounts made by the team in the dashboard, SSO
-- accounts and the tests' own rows aren't 'email' accounts without a confirmation, so they don't either.
create function private.email_unverified(p_user_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from auth.users u
        where u.id = p_user_id
          and u.email_confirmed_at is null
          and u.raw_app_meta_data->>'provider' = 'email'
          and not exists (select 1 from public.profiles p where p.id = u.id)
    )
$$;

-- As in 20261111000000, and also true for a password account that hasn't verified its address.
-- Supabase won't sign one in while "Confirm email" is on, so this only matters if it's ever turned off.
create or replace function private.signup_pending(p_user_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
    select private.email_unverified(p_user_id) or exists (
        select 1 from auth.users u join private.signup_requests r on r.email = lower(u.email)
        where u.id = p_user_id and r.approved_at is null
    )
$$;

-- As in 20261111000000, plus 'unverified': a saved session from before this migration whose account
-- was waiting, and which now has to enter a code (the app sends one). Older builds read anything but
-- 'pending' as approved and then meet `pending_approval` on Set up profile, which is safe.
create or replace function public.signup_status()
returns text language sql stable security definer set search_path = ''
as $$
    select case
        when private.email_unverified(private.require_user()) then 'unverified'
        when private.signup_pending(private.require_user()) then 'pending'
        else 'approved'
    end
$$;

-- Posts one line to the account channel (Vault `signup_alert_webhook_url`, else the reports one).
-- A failure is logged and never blocks what posted it.
create function private.post_account_alert(p_message text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_webhook_url text;
begin
    select decrypted_secret into v_webhook_url from vault.decrypted_secrets where name = 'signup_alert_webhook_url';
    if v_webhook_url is null then
        select decrypted_secret into v_webhook_url from vault.decrypted_secrets where name = 'report_alert_webhook_url';
    end if;
    if v_webhook_url is null then
        raise warning 'account alert not sent: no webhook URL in Vault';
        return;
    end if;
    -- Discord reads "content" and Slack reads "text"; each ignores the other.
    perform net.http_post(
        url := v_webhook_url,
        body := jsonb_build_object('content', p_message, 'text', p_message, 'allowed_mentions', jsonb_build_object('parse', '[]'::jsonb)),
        headers := '{"Content-Type": "application/json"}'::jsonb
    );
exception when others then
    raise warning 'account alert not sent: %', sqlerrm;
end $$;

-- As in 20261119000000, saying the address is verified, so approving needs no vouching.
create or replace function private.alert_signup_request(p_email text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_sql_editor_url text;
    v_request uuid;
begin
    select id into v_request from private.signup_requests where email = p_email;
    select regexp_replace(decrypted_secret, '/editor/?$', '/sql/new') into v_sql_editor_url
    from vault.decrypted_secrets where name = 'report_alert_dashboard_url';
    perform private.post_account_alert(format(
        E'New sign-up waiting for approval (email verified): %s\n'
        'Approve: `select private.approve_signup(email) from private.signup_requests where id = %L;`\n'
        'Reject: `select private.reject_signup(email) from private.signup_requests where id = %L;`\n%s',
        private.mask_email(p_email), v_request, v_request,
        coalesce('Run one in the SQL editor: ' || v_sql_editor_url, 'Run one in the Supabase SQL editor.')
    ));
exception when others then
    raise warning 'sign-up request % not alerted: %', v_request, sqlerrm;
end $$;

-- The "You're in" push, as `approve_signup` sent it (20261116000000). Nothing for an address without
-- an account. A failure is logged and never undoes the approval.
create function private.notify_signup_approved(p_email text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_user uuid;
begin
    select id into v_user from auth.users where lower(email) = p_email;
    if v_user is null then return; end if;
    perform private.enqueue_notification(
        v_user, 'signup_approved', null, '{}'::jsonb,
        'signup:' || v_user::text, null, now(), now() + interval '7 days', true, 'keep'
    );
exception when others then
    raise warning 'signup_approved not enqueued for %: %', private.mask_email(p_email), sqlerrm;
end $$;

-- As in 20261116000000, with the push moved into private.notify_signup_approved.
create or replace function private.approve_signup(p_email text)
returns text language plpgsql security definer set search_path = ''
as $$
declare v_email text := lower(btrim(p_email));
begin
    update private.signup_requests set approved_at = now() where email = v_email and approved_at is null;
    if not found then return 'Nothing to approve for ' || v_email; end if;
    perform private.notify_signup_approved(v_email);
    return 'Approved ' || v_email;
end $$;

-- Records a verified address. Called by the trigger below once the person enters their code.
-- - An allowlisted address goes straight in: the code proves the inbox, which is all the wait was for.
-- - Otherwise the request is created, or a website request keeps its place (N38), and marked verified.
--   With sign-up open it's approved too, and the team gets an FYI; while invite-only, the team gets the
--   usual approval alert. A request the team approved in advance goes straight in with no alert.
-- - A request that was verified already changes nothing.
-- Not caught: if the request can't be written, verifying fails and the person tries again, rather
-- than an account getting in with no request.
create function private.signup_verified(p_email text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_email text := lower(btrim(p_email));
    v_allowlisted boolean := exists (select 1 from public.auth_allowlist where email = v_email);
    v_open boolean := private.signup_auto_approve();
    v_existing private.signup_requests%rowtype;
    v_request private.signup_requests%rowtype;
begin
    select r.* into v_existing from private.signup_requests r where r.email = v_email for update;
    if found and v_existing.verified_at is not null then return; end if;

    insert into private.signup_requests as r (email, verified_at, approved_at)
    values (v_email, now(), case when v_allowlisted or v_open then now() end)
    on conflict (email) do update set
        verified_at = excluded.verified_at,
        approved_at = coalesce(r.approved_at, excluded.approved_at)
    returning r.* into v_request;

    if v_request.approved_at is null then
        perform private.alert_signup_request(v_email);
    elsif v_open and not v_allowlisted and v_existing.approved_at is null then
        perform private.post_account_alert(format(
            E'%s joined: email verified, and sign-ups are open.', private.mask_email(v_email)
        ));
    end if;
end $$;

-- A password account's address was just confirmed by a code we emailed: a sign-up code, or a reset
-- code for an account that never verified (which proves the inbox just the same). Accounts the team
-- creates in the dashboard with "Auto confirm" were sent nothing, and SSO accounts aren't 'email', so
-- neither gets a request: they go straight in as before.
create function private.on_auth_email_verified()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
    if new.raw_app_meta_data->>'provider' = 'email'
       and coalesce(new.confirmation_sent_at, new.recovery_sent_at) is not null then
        perform private.signup_verified(new.email);
    end if;
    return null;
end $$;

create trigger auth_users_email_verified
after update of email_confirmed_at on auth.users
for each row when (old.email_confirmed_at is null and new.email_confirmed_at is not null)
execute function private.on_auth_email_verified();

-- As in 20261119000000, without recording a request: that waits for the code (above). Same addresses
-- allowed and refused.
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
        return '{}'::jsonb;
    end if;
    return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'email_not_allowed'));
end $$;

-- For the team, in the SQL editor: opens or closes sign-up. Turning it on also lets in everyone who is
-- verified and waiting, in one statement (so the Sheet gets one update), each with the "You're in"
-- push. Website requests without an account stay in line until the person signs up and verifies.
-- Turning it off changes nobody already in. Returns a line saying what happened.
create function private.set_signup_auto_approve(p_on boolean)
returns text language plpgsql security definer set search_path = ''
as $$
declare v_emails text[];
begin
    if p_on is null then return 'Nothing changed: pass true or false'; end if;
    insert into public.app_config (key, value) values ('signup_auto_approve', to_jsonb(p_on))
    on conflict (key) do update set value = excluded.value;
    if not p_on then
        return 'Sign-up is invite-only: new verified accounts wait for approval';
    end if;
    with approved as (
        update private.signup_requests set approved_at = now()
        where approved_at is null and verified_at is not null
        returning email
    )
    select array_agg(email) into v_emails from approved;
    perform private.notify_signup_approved(e) from unnest(coalesce(v_emails, '{}'::text[])) e;
    return format('Sign-up is open: verified accounts go straight in. Let in %s waiting',
        coalesce(array_length(v_emails, 1), 0));
end $$;

-- Accounts that never entered their code, a day on, so the address is free for its owner. Accounts
-- with a request (website joins, and those reset below) are kept: their place in line is theirs.
-- Returns how many were deleted.
create function private.delete_unverified_signups()
returns integer language plpgsql security definer set search_path = ''
as $$
declare v_count integer;
begin
    with gone as (
        delete from auth.users u
        where u.email_confirmed_at is null
          and u.raw_app_meta_data->>'provider' = 'email'
          and u.created_at < now() - interval '24 hours'
          and not exists (select 1 from public.profiles p where p.id = u.id)
          and not exists (select 1 from private.signup_requests r where r.email = lower(u.email))
        returning 1
    )
    select count(*)::integer into v_count from gone;
    return v_count;
end $$;

-- Accounts already waiting were never asked for a code ("Confirm email" was off, so Supabase marked
-- them confirmed). They verify on their next sign-in, or from their saved session ('unverified').
-- Approved, allowlisted-in and member accounts aren't touched.
update auth.users u set email_confirmed_at = null
from private.signup_requests r
where r.email = lower(u.email)
  and r.approved_at is null
  and u.raw_app_meta_data->>'provider' = 'email'
  and not exists (select 1 from public.profiles p where p.id = u.id);

revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.blocked_pair(uuid, uuid), private.same_university(uuid, uuid),
    private.active_viewer(), private.blocked_someone_going(uuid) to authenticated;
revoke execute on function public.before_user_created(jsonb) from public, anon, authenticated;
grant execute on function public.before_user_created(jsonb) to supabase_auth_admin;
revoke execute on function public.signup_status() from public, anon;
grant execute on function public.signup_status() to authenticated;

-- Hourly. Scheduling by name replaces an older job with the same name.
select cron.schedule('delete-unverified-signups', '20 * * * *', 'select private.delete_unverified_signups()');
