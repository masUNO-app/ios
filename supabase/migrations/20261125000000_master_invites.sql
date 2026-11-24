-- Master invite codes: codes the team makes that work for many people, unlike a member's code,
-- which works once. Typed in the same field as any invite, so the app doesn't change: `redeem_invite`
-- keeps its name, parameter and answers, and a published build redeems one like a member's code.
--
-- A master code lets anyone with a school email in, so it can have a limit on uses, an end date, or
-- both, and the team can turn it off (README, "Invites"). Each use posts an FYI to the sign-up
-- channel, like a member's invite. Wrong codes count toward the same 5-an-hour limit.
--
-- Compatible with 0.x and 1.0: nothing the app calls changes shape.

-- The code is what people type, stored the way `redeem_invite` compares it: upper case, no spaces
-- or dashes. Letters and digits only, so it can be read aloud. `note` is for the team ("launch
-- posters"). Null `max_uses` or `expires_at` means no limit.
create table private.master_invites (
    code text primary key check (code ~ '^[A-Z0-9]{4,32}$'),
    note text,
    max_uses integer check (max_uses is null or max_uses > 0),
    expires_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz not null default now()
);
alter table private.master_invites enable row level security;
revoke all on private.master_invites from public, anon, authenticated;

-- One row per use. Not keyed by email: an account deleted and made again may use a code again.
create table private.master_invite_uses (
    id bigint generated always as identity primary key,
    code text not null references private.master_invites(code) on delete cascade,
    email text not null check (email = lower(email)),
    redeemed_at timestamptz not null default now()
);
create index master_invite_uses_code_idx on private.master_invite_uses (code, redeemed_at);
alter table private.master_invite_uses enable row level security;
revoke all on private.master_invite_uses from public, anon, authenticated;

-- Posts "<email> joined with the team code MASUNO (3 of 50 used)" to the sign-up channel. Same
-- webhook and masking as `alert_invite_redeemed`. A failure is logged and never undoes the use.
create function private.alert_master_invite_redeemed(p_email text, p_code text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_webhook_url text;
    v_master private.master_invites%rowtype;
    v_uses integer;
    v_message text;
begin
    select decrypted_secret into v_webhook_url from vault.decrypted_secrets where name = 'signup_alert_webhook_url';
    if v_webhook_url is null then
        select decrypted_secret into v_webhook_url from vault.decrypted_secrets where name = 'report_alert_webhook_url';
    end if;
    if v_webhook_url is null then
        raise warning 'master invite for % not alerted: no webhook URL in Vault', private.mask_email(p_email);
        return;
    end if;
    select m.* into v_master from private.master_invites m where m.code = p_code;
    select count(*)::integer into v_uses from private.master_invite_uses u where u.code = p_code;

    v_message := format(
        E'%s joined with the team code %s (%s).\nThey''re in already, so ignore their approval request.',
        private.mask_email(p_email), p_code,
        case when v_master.max_uses is null then v_uses || ' used'
             else v_uses || ' of ' || v_master.max_uses || ' used' end
    );
    -- Discord reads "content" and Slack reads "text"; each ignores the other.
    perform net.http_post(
        url := v_webhook_url,
        body := jsonb_build_object('content', v_message, 'text', v_message, 'allowed_mentions', jsonb_build_object('parse', '[]'::jsonb)),
        headers := '{"Content-Type": "application/json"}'::jsonb
    );
exception when others then
    raise warning 'master invite for % not alerted: %', private.mask_email(p_email), sqlerrm;
end $$;

-- As in 20261114000000, and a code that isn't a member's may be a master code. Same signature and
-- answers. A member's code is looked up first, so the rare master code that matches one never
-- takes it over. A master code leaves `invited_by` null: no member vouched for the account.
create or replace function public.redeem_invite(p_code text)
returns text language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_user();
    v_email text;
    v_request private.signup_requests%rowtype;
    v_attempts integer;
    v_code text := upper(regexp_replace(coalesce(p_code, ''), '[[:space:]-]', '', 'g'));
    v_invite private.invites%rowtype;
    v_master private.master_invites%rowtype;
begin
    select lower(u.email) into v_email from auth.users u where u.id = v_id;
    -- Locked, so one account's tries are counted one at a time.
    select r.* into v_request from private.signup_requests r where r.email = v_email for update;
    if not found or v_request.approved_at is not null then return 'approved'; end if;

    v_attempts := case when v_request.invite_attempt_at > now() - interval '1 hour' then v_request.invite_attempts else 0 end;
    if v_attempts >= 5 then return 'rate_limited'; end if;

    -- Locked, so two people can't both use the last of a code: the second sees it redeemed.
    select i.* into v_invite from private.invites i where i.code = v_code for update;
    if found then
        if v_invite.redeemed_at is null and v_invite.inviter_id <> v_id
           and not exists (select 1 from public.profiles p where p.id = v_invite.inviter_id and p.banned_at is not null) then
            update private.invites set redeemed_email = v_email, redeemed_at = now() where code = v_code;
            update private.signup_requests set
                approved_at = now(), invited_by = v_invite.inviter_id, invite_attempts = 0, invite_attempt_at = null
            where email = v_email;
            perform private.alert_invite_redeemed(v_email, v_invite.inviter_id);
            return 'approved';
        end if;
    else
        -- Locked, so the last use under a limit goes to one person.
        select m.* into v_master from private.master_invites m where m.code = v_code for update;
        if found and v_master.revoked_at is null
           and (v_master.expires_at is null or v_master.expires_at > now())
           and (v_master.max_uses is null
                or (select count(*) from private.master_invite_uses u where u.code = v_code) < v_master.max_uses) then
            insert into private.master_invite_uses (code, email) values (v_code, v_email);
            update private.signup_requests set
                approved_at = now(), invite_attempts = 0, invite_attempt_at = null
            where email = v_email;
            perform private.alert_master_invite_redeemed(v_email, v_code);
            return 'approved';
        end if;
    end if;

    update private.signup_requests set
        invite_attempts = v_attempts + 1,
        invite_attempt_at = case when v_attempts = 0 then now() else invite_attempt_at end
    where email = v_email;
    return 'invalid_invite';
end $$;

-- For the team, in the SQL editor: makes a master code. Spaces, dashes and case don't matter, as when
-- it's typed. Returns a line saying what happened.
--   select private.create_master_invite('MASUNO');                              -- no limit
--   select private.create_master_invite('POSTERS', 50, now() + interval '30 days', 'launch posters');
create function private.create_master_invite(
    p_code text,
    p_max_uses integer default null,
    p_expires_at timestamptz default null,
    p_note text default null
)
returns text language plpgsql security definer set search_path = ''
as $$
declare v_code text := upper(regexp_replace(coalesce(p_code, ''), '[[:space:]-]', '', 'g'));
begin
    if v_code !~ '^[A-Z0-9]{4,32}$' then
        return 'Not made: a code is 4 to 32 letters (A–Z, no accents) and digits';
    end if;
    if p_max_uses is not null and p_max_uses < 1 then return 'Not made: the limit must be at least 1'; end if;
    if exists (select 1 from private.invites where code = v_code) then
        return 'Not made: ' || v_code || ' is a member''s code';
    end if;
    insert into private.master_invites (code, note, max_uses, expires_at)
    values (v_code, nullif(btrim(p_note), ''), p_max_uses, p_expires_at)
    on conflict (code) do nothing;
    if not found then return 'Not made: ' || v_code || ' exists already'; end if;
    return format('Made %s (%s, %s)', v_code,
        coalesce(p_max_uses || case when p_max_uses = 1 then ' use' else ' uses' end, 'no limit on uses'),
        coalesce('until ' || to_char(p_expires_at at time zone 'America/Mexico_City', 'YYYY-MM-DD HH24:MI') || ' CDMX', 'no end date'));
end $$;

-- For the team: turns a master code off. People it already let in stay in. Returns a line.
create function private.revoke_master_invite(p_code text)
returns text language plpgsql security definer set search_path = ''
as $$
declare v_code text := upper(regexp_replace(coalesce(p_code, ''), '[[:space:]-]', '', 'g'));
begin
    update private.master_invites set revoked_at = now() where code = v_code and revoked_at is null;
    if found then return 'Turned off ' || v_code; end if;
    if exists (select 1 from private.master_invites where code = v_code) then return v_code || ' was off already'; end if;
    return 'No master code ' || v_code;
end $$;

-- New functions get the default EXECUTE grant; these are for the team only.
revoke execute on function private.alert_master_invite_redeemed(text, text),
    private.create_master_invite(text, integer, timestamptz, text),
    private.revoke_master_invite(text) from public, anon, authenticated;
revoke execute on function public.redeem_invite(text) from public, anon;
grant execute on function public.redeem_invite(text) to authenticated;
