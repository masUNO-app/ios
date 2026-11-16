-- Invite-only with a waitlist, and the beta tester badge (1.0, SPEC N37). Builds on the
-- manual approval in 20261111000000 (N36): a sign-up without a code still waits for the team, which
-- the app now calls the waitlist. A member's invite code lets a waiting account in straight away,
-- with no approval, and the team gets an FYI instead of a request. Every member has 3 codes; the
-- team gives more with `private.grant_invites` (README, "Sign-up approvals"). Allowlisted accounts
-- and the unused SSO path never wait, so nothing changes for them.
--
-- Compatible with 0.x: my_profile and game_attendees only gain a column at the end, and nothing
-- an older build calls changes.

create extension if not exists pgcrypto with schema extensions;

-- How many codes this member may have in all, used or not. `my_invites` tops them up to it.
alter table public.profiles add column invite_allowance integer not null default 3 check (invite_allowance >= 0);

-- Set the first time a signed-in member opens a TestFlight build (`mark_beta_tester`). The app
-- reports it itself, so a modified client could set it: that's fine for a badge that grants nothing.
-- Others see only the boolean, through a column grant like `last_initial`'s, never the time.
alter table public.profiles add column beta_tester_at timestamptz;
alter table public.profiles add column is_beta_tester boolean generated always as (beta_tester_at is not null) stored;
grant select (is_beta_tester) on public.profiles to authenticated;

-- Still runs as its owner (see 20261109000000); the auth.uid() filter is the only access check.
-- `is_beta_tester` is added at the end, so 0.x keeps decoding it.
create or replace view public.my_profile
with (security_invoker = false) as
select p.id, p.first_name, p.last_name, p.grad_year, p.university_id, u.name as university_name,
       u.short_name as university_short_name, u.email_domain as university_email_domain,
       u.center_lat, u.center_lng, p.interests, p.guidelines_accepted_at, p.banned_at,
       p.chat_rules_accepted_at, p.is_beta_tester
from public.profiles p join public.universities u on u.id = p.university_id
where p.id = auth.uid();

-- As in 20261109000000, with the badge for Who's going at the end.
create or replace view public.game_attendees
with (security_invoker = true) as
select r.event_id, p.id as user_id, p.first_name, p.last_initial, p.grad_year, r.role, r.joined_at,
       p.is_beta_tester
from public.rsvps r join public.profiles p on p.id = r.user_id
where not private.blocked_pair(auth.uid(), r.user_id);

-- One row per code. Keyed by the code: it's what people type. The redeemer is kept by email, like
-- signup_requests, because that's all a waiting account has; their name comes from their profile.
create table private.invites (
    code text primary key check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
    inviter_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    redeemed_email text check (redeemed_email = lower(redeemed_email)),
    redeemed_at timestamptz,
    check ((redeemed_email is null) = (redeemed_at is null))
);
create index invites_inviter_idx on private.invites (inviter_id, created_at);
alter table private.invites enable row level security;
revoke all on private.invites from public, anon, authenticated;

-- Who let a waiting account in, and its wrong codes in the current hour (`redeem_invite`).
alter table private.signup_requests
    add column invited_by uuid references public.profiles(id) on delete set null,
    add column invite_attempts integer not null default 0,
    add column invite_attempt_at timestamptz;

-- 8 characters from 32 that can't be misread (no 0, O, 1 or I). 256 is a multiple of 32, so each
-- random byte picks a character with no bias. About 10^12 codes, so guessing one takes far longer
-- than the rate limit allows.
create function private.new_invite_code()
returns text language plpgsql volatile set search_path = ''
as $$
declare
    v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    v_bytes bytea := extensions.gen_random_bytes(8);
    v_code text := '';
begin
    for i in 0..7 loop
        v_code := v_code || substr(v_alphabet, get_byte(v_bytes, i) % 32 + 1, 1);
    end loop;
    return v_code;
end $$;

-- Creates the codes a member is still owed, lazily, so members from before this migration get
-- theirs the first time they look. The profile row lock stops two calls at once from making extra.
-- Does nothing without a profile: codes belong to members.
create function private.issue_invites(p_inviter uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_allowance integer;
    v_have integer;
begin
    select invite_allowance into v_allowance from public.profiles where id = p_inviter for update;
    if not found then return; end if;
    select count(*) into v_have from private.invites where inviter_id = p_inviter;
    while v_have < v_allowance loop
        insert into private.invites (code, inviter_id) values (private.new_invite_code(), p_inviter)
        on conflict (code) do nothing;
        if found then v_have := v_have + 1; end if;
    end loop;
end $$;

-- Your invite codes, oldest first, creating any you're still owed.
-- Returns each code, when it was made and used, and who used it as a first name and last initial
-- (null until they've set up a profile, or if either of you blocked the other). Never an email.
-- Raises not_authenticated, suspended or pending_approval.
create function public.my_invites()
returns table (
    code text,
    created_at timestamptz,
    redeemed_at timestamptz,
    redeemer_first_name text,
    redeemer_last_initial char(1)
)
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active();
begin
    perform private.issue_invites(v_id);
    return query
    select i.code, i.created_at, i.redeemed_at,
           case when shown.is_shown then p.first_name end,
           case when shown.is_shown then p.last_initial end
    from private.invites i
    left join auth.users u on lower(u.email) = i.redeemed_email
    left join public.profiles p on p.id = u.id
    cross join lateral (select p.id is not null and not private.blocked_pair(v_id, p.id) as is_shown) shown
    where i.inviter_id = v_id
    order by i.created_at, i.code;
end $$;

-- Posts "<email> joined with <name>'s invite" to the sign-up channel: an FYI, since the account is
-- already in. Same webhook as the approval alerts. A failure is logged and never undoes the redemption.
create function private.alert_invite_redeemed(p_email text, p_inviter uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_webhook_url text;
    v_inviter text;
    v_message text;
begin
    select decrypted_secret into v_webhook_url from vault.decrypted_secrets where name = 'signup_alert_webhook_url';
    if v_webhook_url is null then
        select decrypted_secret into v_webhook_url from vault.decrypted_secrets where name = 'report_alert_webhook_url';
    end if;
    if v_webhook_url is null then
        raise warning 'invite for % not alerted: no webhook URL in Vault', p_email;
        return;
    end if;
    select p.first_name || ' ' || p.last_initial || '.' into v_inviter from public.profiles p where p.id = p_inviter;

    v_message := format(
        E'%s joined with %s''s invite.\nIt''s approved already, so its approval request needs nothing.',
        p_email, coalesce(v_inviter, 'a member')
    );
    -- Discord reads "content" and Slack reads "text"; each ignores the other.
    perform net.http_post(
        url := v_webhook_url,
        body := jsonb_build_object('content', v_message, 'text', v_message, 'allowed_mentions', jsonb_build_object('parse', '[]'::jsonb)),
        headers := '{"Content-Type": "application/json"}'::jsonb
    );
exception when others then
    raise warning 'invite for % not alerted: %', p_email, sqlerrm;
end $$;

-- Lets a waiting account in with a member's code, at sign-up or later from the waitlist. Works
-- while pending, so it checks the session only (`require_user`), not `require_active`.
-- Parameters: the code as typed; spaces, dashes and case don't matter.
-- Returns 'approved' (also when the account isn't waiting), 'invalid_invite' (no such code, used,
-- your own, or its member is banned) or 'rate_limited' (more than 5 wrong codes this hour; the
-- next try waits out the hour, even with a good code). Raises not_authenticated.
--
-- The two refusals are returned, not raised, on purpose: a raise rolls back the whole call,
-- wrong-try count included (PostgREST runs each RPC in one transaction, and a wrapper that raises
-- after counting would roll it back too). The app treats them like error codes.
create function public.redeem_invite(p_code text)
returns text language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_user();
    v_email text;
    v_request private.signup_requests%rowtype;
    v_attempts integer;
    v_code text := upper(regexp_replace(coalesce(p_code, ''), '[[:space:]-]', '', 'g'));
    v_invite private.invites%rowtype;
begin
    select lower(u.email) into v_email from auth.users u where u.id = v_id;
    -- Locked, so one account's tries are counted one at a time.
    select r.* into v_request from private.signup_requests r where r.email = v_email for update;
    if not found or v_request.approved_at is not null then return 'approved'; end if;

    v_attempts := case when v_request.invite_attempt_at > now() - interval '1 hour' then v_request.invite_attempts else 0 end;
    if v_attempts >= 5 then return 'rate_limited'; end if;

    -- Locked, so two people can't both use the last of a code: the second sees it redeemed.
    select i.* into v_invite from private.invites i where i.code = v_code for update;
    if not found or v_invite.redeemed_at is not null or v_invite.inviter_id = v_id
       or exists (select 1 from public.profiles p where p.id = v_invite.inviter_id and p.banned_at is not null) then
        update private.signup_requests set
            invite_attempts = v_attempts + 1,
            invite_attempt_at = case when v_attempts = 0 then now() else invite_attempt_at end
        where email = v_email;
        return 'invalid_invite';
    end if;

    update private.invites set redeemed_email = v_email, redeemed_at = now() where code = v_code;
    update private.signup_requests set
        approved_at = now(), invited_by = v_invite.inviter_id, invite_attempts = 0, invite_attempt_at = null
    where email = v_email;
    perform private.alert_invite_redeemed(v_email, v_invite.inviter_id);
    return 'approved';
end $$;

-- Your place on the waitlist: 1 is next. Null when you aren't waiting. Raises not_authenticated.
create function public.waitlist_position()
returns integer language plpgsql stable security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_user();
    v_request private.signup_requests%rowtype;
begin
    select r.* into v_request
    from auth.users u join private.signup_requests r on r.email = lower(u.email)
    where u.id = v_id;
    if not found or v_request.approved_at is not null then return null; end if;
    -- Ties (the same instant) go by email, so two people never share a place.
    return (
        select count(*)::integer from private.signup_requests w
        where w.approved_at is null and (w.requested_at, w.email) <= (v_request.requested_at, v_request.email)
    );
end $$;

-- For the team, in the SQL editor: gives a member more codes. They appear the next time the member
-- opens their invites. Returns a line saying what happened.
create function private.grant_invites(p_email text, p_count integer)
returns text language plpgsql security definer set search_path = ''
as $$
declare
    v_email text := lower(btrim(p_email));
    v_allowance integer;
begin
    if p_count is null or p_count < 1 then return 'Nothing to give: the count must be at least 1'; end if;
    update public.profiles p set invite_allowance = p.invite_allowance + p_count
    from auth.users u
    where u.id = p.id and lower(u.email) = v_email
    returning p.invite_allowance into v_allowance;
    if not found then return 'No profile for ' || v_email; end if;
    return format('Gave %s %s more invites (%s in all)', v_email, p_count, v_allowance);
end $$;

-- The app calls this once, the first time a signed-in member opens a TestFlight build. Later calls
-- keep the first time. Returns the my_profile row, like complete_profile.
create function public.mark_beta_tester()
returns setof public.my_profile language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active();
begin
    update public.profiles set beta_tester_at = now(), updated_at = now()
    where id = v_id and beta_tester_at is null;
    return query select * from public.my_profile;
end $$;

-- Functions created above get the default EXECUTE grant, so repeat the lock-down.
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.blocked_pair(uuid, uuid), private.same_university(uuid, uuid) to authenticated;
revoke execute on function public.my_invites(), public.redeem_invite(text), public.waitlist_position(),
    public.mark_beta_tester() from public, anon;
grant execute on function public.my_invites(), public.redeem_invite(text), public.waitlist_position(),
    public.mark_beta_tester() to authenticated;
