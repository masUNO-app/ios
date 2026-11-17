-- Security review fixes (Nov 16). Compatible with 0.x and earlier 1.0 builds: no view loses a column,
-- and register_device only gains an optional argument.
--
-- 1. Blocks hide attendance both ways. A blocked person can no longer read the blocker's RSVPs,
--    see them through has_blocked_attendee, or learn about them from join_game.
-- 2. A banned account reads nothing past its own profile, blocks, bookmarks and settings.
-- 3. A password sign-up with an allowlisted address waits for approval like any other.
-- 4. Sign-up alerts no longer post email addresses to Discord.
-- 5. A device token stays with the phone that registered it.
-- 6. Signed-out callers can run only the functions meant for them.

create extension if not exists pgcrypto with schema extensions;

-- 1 and 2: read policies -------------------------------------------------------------------------

-- Whether the signed-in person has a profile that isn't banned. The read policies below use it,
-- so a banned account sees no campus games, attendees, profiles, activity or chat.
-- Returns false when signed out or without a profile.
create function private.active_viewer()
returns boolean language sql stable security definer set search_path = ''
as $$
    select exists (select 1 from public.profiles where id = auth.uid() and banned_at is null)
$$;

-- Whether the signed-in person blocked someone going to this game. One way only: being blocked by
-- someone going must not show, or it tells the blocked person which games the blocker joined.
-- Parameters: the game. Returns false when signed out.
create function private.blocked_someone_going(p_event uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.rsvps r join public.blocks b on b.blocked_id = r.user_id
        where r.event_id = p_event and b.blocker_id = auth.uid()
    )
$$;

drop policy "same-campus public profiles" on public.profiles;
create policy "same-campus public profiles" on public.profiles for select using (
    private.active_viewer()
    and private.same_university(auth.uid(), id)
    and not private.blocked_pair(auth.uid(), id)
);

drop policy "visible games at own campus" on public.games;
create policy "visible games at own campus" on public.games for select using (
    private.active_viewer()
    and exists (select 1 from public.profiles viewer where viewer.id = auth.uid() and viewer.university_id = games.university_id)
    and not private.blocked_pair(auth.uid(), host_id)
);

-- Game activity, chat messages and the chat Realtime channel all check membership through the
-- caller's own rsvps row, so hiding rows here closes those to a banned account as well.
drop policy "game attendees visible" on public.rsvps;
create policy "game attendees visible" on public.rsvps for select using (
    private.active_viewer()
    and exists (select 1 from public.games g join public.profiles me on me.university_id = g.university_id
                where g.id = rsvps.event_id and me.id = auth.uid())
    and not private.blocked_pair(auth.uid(), rsvps.user_id)
);

-- As in 20261116000000, with has_blocked_attendee only counting people the reader blocked.
create or replace view public.game_cards
with (security_invoker = true) as
select g.id, g.host_id, host.first_name as host_first_name, host.last_initial as host_last_initial,
       host.grad_year as host_grad_year, g.activity_slug, g.title, g.starts_at, g.duration_minutes, g.ends_at,
       g.capacity, g.going_count, g.capacity - g.going_count as spots_left, g.notes, g.place_name,
       g.place_address, g.lat, g.lng, g.meet_point, g.material_change_at, g.cancelled_at, g.auto_repost,
       g.reposted_at, g.created_at, coalesce(g.reposted_at, g.created_at) as sort_at,
       mine.role as my_role, mine.joined_at as my_joined_at,
       private.blocked_someone_going(g.id) as has_blocked_attendee,
       exists (
           select 1 from public.bookmarks b
           where b.event_id = g.id and b.user_id = (select auth.uid())
       ) as is_bookmarked,
       coalesce((
           select b.notify from public.bookmarks b
           where b.event_id = g.id and b.user_id = (select auth.uid())
       ), false) as spot_alert,
       coalesce(mine.chat_muted, false) as my_chat_muted
from public.games g
join public.profiles host on host.id = g.host_id
left join public.rsvps mine on mine.event_id = g.id and mine.user_id = (select auth.uid());

-- As in 20261109000000, except `blocked` now only means "someone you blocked is going". Someone
-- blocked by a player can join that player's game: refusing them would tell them where the
-- blocker will be. A blocked host's games stay hidden both ways (`not_found`), as before.
create or replace function public.join_game(p_id uuid)
returns setof public.game_cards language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := private.require_active(); v_game public.games%rowtype;
begin
    v_game := private.lock_visible_game(p_id, v_id);
    if exists (select 1 from public.rsvps where event_id = p_id and user_id = v_id) then
        return query select * from public.game_cards where id = p_id;
        return;
    end if;
    if v_game.cancelled_at is not null then raise exception 'cancelled'; end if;
    if v_game.ends_at <= now() then raise exception 'ended'; end if;
    if v_game.going_count >= v_game.capacity then raise exception 'full'; end if;
    if exists (
        select 1 from public.rsvps r join public.blocks b on b.blocked_id = r.user_id
        where r.event_id = p_id and b.blocker_id = v_id
    ) then
        raise exception 'blocked';
    end if;
    insert into public.rsvps (event_id, user_id, role) values (p_id, v_id, 'player');
    update public.games set going_count = going_count + 1 where id = p_id;
    perform private.activity_actor(p_id, 'joined', v_id);
    return query select * from public.game_cards where id = p_id;
end $$;

-- 3: allowlisted addresses -----------------------------------------------------------------------

-- As in 20261115000000, except an allowlisted address that signs up with a password now waits for
-- approval too. The allowlist is public in 20261109000200, so until the team creates one of those
-- accounts, anyone could claim the address. Accounts that already exist never pass through here
-- again, and an allowlisted address through an SSO provider (which proves the address) still
-- goes straight in.
create or replace function public.before_user_created(event jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
    v_email text := lower(btrim(coalesce(event->'user'->>'email', '')));
    v_provider text := coalesce(event->'user'->'app_metadata'->>'provider', 'email');
begin
    if v_email <> '' and exists (select 1 from public.auth_allowlist where email = v_email) then
        if v_provider = 'email' then
            perform private.request_signup(v_email);
        end if;
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

-- 4: no emails in Discord ------------------------------------------------------------------------

-- What the alerts name a request by, so the approve and reject lines needn't carry the email.
alter table private.signup_requests add column id uuid not null default gen_random_uuid() unique;

-- "a•••@tec.mx": enough for the team to tell the campus apart, without the person's address.
-- Parameters: a lower-case email. Returns the masked text, or '•••' for something that isn't one.
create function private.mask_email(p_email text)
returns text language sql immutable set search_path = ''
as $$
    select case
        when coalesce(p_email, '') !~ '^[^@]+@[^@]+$' then '•••'
        else left(split_part(p_email, '@', 1), 1) || '•••@' || split_part(p_email, '@', 2)
    end
$$;

-- As in 20261111000000, naming the request by its id and a masked email. The lines to paste look
-- the email up in the SQL editor, so it never leaves the database.
create or replace function private.alert_signup_request(p_email text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_webhook_url text;
    v_sql_editor_url text;
    v_request uuid;
    v_message text;
begin
    select decrypted_secret into v_webhook_url from vault.decrypted_secrets where name = 'signup_alert_webhook_url';
    if v_webhook_url is null then
        select decrypted_secret into v_webhook_url from vault.decrypted_secrets where name = 'report_alert_webhook_url';
    end if;
    select id into v_request from private.signup_requests where email = p_email;
    if v_webhook_url is null then
        raise warning 'sign-up request % not alerted: no webhook URL in Vault', v_request;
        return;
    end if;
    select regexp_replace(decrypted_secret, '/editor/?$', '/sql/new') into v_sql_editor_url
    from vault.decrypted_secrets where name = 'report_alert_dashboard_url';

    v_message := format(
        E'New sign-up waiting for approval: %s\n'
        'Approve: `select private.approve_signup(email) from private.signup_requests where id = %L;`\n'
        'Reject: `select private.reject_signup(email) from private.signup_requests where id = %L;`\n%s',
        private.mask_email(p_email), v_request, v_request,
        coalesce('Run one in the SQL editor: ' || v_sql_editor_url, 'Run one in the Supabase SQL editor.')
    );
    -- Discord reads "content" and Slack reads "text"; each ignores the other.
    perform net.http_post(
        url := v_webhook_url,
        body := jsonb_build_object('content', v_message, 'text', v_message, 'allowed_mentions', jsonb_build_object('parse', '[]'::jsonb)),
        headers := '{"Content-Type": "application/json"}'::jsonb
    );
exception when others then
    raise warning 'sign-up request % not alerted: %', v_request, sqlerrm;
end $$;

-- As in 20261114000000, with the redeemer's email masked.
create or replace function private.alert_invite_redeemed(p_email text, p_inviter uuid)
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
        raise warning 'invite for % not alerted: no webhook URL in Vault', private.mask_email(p_email);
        return;
    end if;
    select p.first_name || ' ' || p.last_initial || '.' into v_inviter from public.profiles p where p.id = p_inviter;

    v_message := format(
        E'%s joined with %s''s invite.\nIt''s approved already, so its approval request needs nothing.',
        private.mask_email(p_email), coalesce(v_inviter, 'a member')
    );
    -- Discord reads "content" and Slack reads "text"; each ignores the other.
    perform net.http_post(
        url := v_webhook_url,
        body := jsonb_build_object('content', v_message, 'text', v_message, 'allowed_mentions', jsonb_build_object('parse', '[]'::jsonb)),
        headers := '{"Content-Type": "application/json"}'::jsonb
    );
exception when others then
    raise warning 'invite for % not alerted: %', private.mask_email(p_email), sqlerrm;
end $$;

-- 5: device tokens -------------------------------------------------------------------------------

-- SHA-256 of the app's per-install secret. A token can move to another account only from the
-- install that registered it, so knowing someone's token isn't enough to take it. Null for rows
-- from builds that don't send one; only the existing owner can bind one on upgrade.
alter table private.device_tokens add column install_hash bytea;

drop function public.register_device(text, text, text, text);

-- Registers this phone for pushes. Allowed while an account waits for approval.
-- Parameters: the APNs token, its environment, the phone's locale, the app version, and the app's
-- random per-install secret (optional, so older builds keep working).
-- Signing in to another account on the same phone moves the token to it. A token registered from
-- another install stays where it is, and the call changes nothing for it.
-- Raises not_authenticated or invalid_input.
create function public.register_device(
    p_token text, p_environment text, p_locale text, p_app_version text, p_install_id text default null
) returns void language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid := private.require_user();
    v_install_id text := nullif(btrim(p_install_id), '');
    v_install_hash bytea;
    v_row private.device_tokens%rowtype;
begin
    if p_token is null or char_length(p_token) not between 16 and 400
       or p_environment not in ('sandbox', 'production')
       or nullif(btrim(p_locale), '') is null
       or nullif(btrim(p_app_version), '') is null
       or char_length(coalesce(v_install_id, 'x')) > 200 then
        raise exception 'invalid_input';
    end if;
    if v_install_id is not null then
        v_install_hash := extensions.digest(v_install_id, 'sha256');
    end if;

    insert into private.device_tokens (token, user_id, environment, locale, app_version, install_hash)
    values (p_token, v_id, p_environment, left(btrim(p_locale), 35), left(btrim(p_app_version), 32), v_install_hash)
    on conflict (token) do nothing;
    if not found then
        select * into v_row from private.device_tokens where token = p_token for update;
        -- Only the current account can bind an unprotected legacy token. A NULL hash
        -- is not proof that an unrelated caller owns the install.
        if v_row.user_id = v_id
           or (v_row.install_hash is not null and v_row.install_hash = v_install_hash) then
            update private.device_tokens set
                user_id = v_id,
                environment = p_environment,
                locale = left(btrim(p_locale), 35),
                app_version = left(btrim(p_app_version), 32),
                install_hash = coalesce(v_install_hash, install_hash),
                updated_at = now()
            where token = p_token;
        else
            raise warning 'register_device: a token registered from another install was left with its account';
        end if;
    end if;
    update public.profiles set last_seen_at = now() where id = v_id;
end $$;

-- 6: function grants -----------------------------------------------------------------------------

-- Postgres grants EXECUTE on every new function to PUBLIC, and Supabase grants it to anon as well,
-- so the client RPCs from 20261107000000 and 20261116000000 were callable signed out. Take it away
-- from everything in public, then give back only what each role uses. A per-schema default can't
-- undo the PUBLIC grant, so every later migration still ends with this revoke for its own functions.
revoke execute on all functions in schema public from public, anon;

grant execute on function public.guest_games(uuid) to anon;
grant execute on function public.waitlist_join(text, text, timestamptz, text), public.waitlist_export(text) to anon;

grant execute on function public.register_device(text, text, text, text, text) to authenticated;
revoke execute on function public.before_user_created(jsonb) from authenticated;
grant execute on function public.before_user_created(jsonb) to supabase_auth_admin;

revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.blocked_pair(uuid, uuid), private.same_university(uuid, uuid),
    private.active_viewer(), private.blocked_someone_going(uuid) to authenticated;
