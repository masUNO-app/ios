-- Forward-only optimization: per-user mute changes do not invalidate the campus map.
create function private.broadcast_rsvp_updates()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    perform private.send_game_changes(g.university_id, array_agg(distinct relevant.event_id))
    from (
        select coalesce(n.event_id, o.event_id) as event_id
        from new_rsvps n full join old_rsvps o using (event_id, user_id)
        where n.event_id is null or o.event_id is null
           or (n.role, n.joined_at) is distinct from (o.role, o.joined_at)
    ) relevant
    join public.games g on g.id = relevant.event_id
    group by g.university_id;
    return null;
exception when others then
    raise warning 'games broadcast failed: %', sqlerrm;
    return null;
end $$;
drop trigger rsvps_updated_broadcast on public.rsvps;
create trigger rsvps_updated_broadcast after update on public.rsvps
referencing old table as old_rsvps new table as new_rsvps
for each statement execute function private.broadcast_rsvp_updates();
revoke execute on function private.broadcast_rsvp_updates() from public, anon, authenticated, service_role;

-- Opaque attempt identity fences late workers across the ten-minute lease. No index is needed:
-- completion locks the row by its existing primary key, then compares its current claim token.
alter table private.notification_outbox add column claim_token uuid;
alter function private.claim_notifications(integer) rename to claim_notifications_unfenced;
alter function private.complete_notifications(jsonb) rename to complete_notifications_unfenced;

-- Legacy workers keep their response shape. A legacy reclaim clears a v2 attempt identity;
-- the earlier v2 worker can no longer complete it. Legacy-to-legacy workers still lack identity,
-- so deploy the v2 sender after this migration to obtain full stale-worker fencing.
create function private.claim_notifications(p_limit integer)
returns table (
    id bigint, user_id uuid, kind text, event_id uuid, payload jsonb,
    collapse_id text, expires_at timestamptz, tokens jsonb, context jsonb
) language plpgsql security definer set search_path = '' as $$
declare r record;
begin
    for r in select * from private.claim_notifications_unfenced(p_limit) loop
        update private.notification_outbox o set claim_token = null where o.id = r.id;
        id := r.id;
        user_id := r.user_id;
        kind := r.kind;
        event_id := r.event_id;
        payload := r.payload;
        collapse_id := r.collapse_id;
        expires_at := r.expires_at;
        tokens := r.tokens;
        context := r.context;
        return next;
    end loop;
end $$;

create function private.claim_notifications_v2(p_limit integer)
returns table (
    id bigint, user_id uuid, kind text, event_id uuid, payload jsonb,
    collapse_id text, expires_at timestamptz, tokens jsonb, context jsonb, claim_token uuid
) language plpgsql security definer set search_path = '' as $$
declare r record; v_token uuid;
begin
    for r in select * from private.claim_notifications_unfenced(p_limit) loop
        v_token := gen_random_uuid();
        update private.notification_outbox o set claim_token = v_token where o.id = r.id;
        id := r.id;
        user_id := r.user_id;
        kind := r.kind;
        event_id := r.event_id;
        payload := r.payload;
        collapse_id := r.collapse_id;
        expires_at := r.expires_at;
        tokens := r.tokens;
        context := r.context;
        claim_token := v_token;
        return next;
    end loop;
end $$;

-- Both protocols lock before validating attempt ownership, including dead-token cleanup.
-- A missing or superseded token is a no-op; duplicate completions cannot charge resend history.
create function private.complete_notifications(p_results jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare item jsonb; found_id bigint;
begin
    for item in select value from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
        select o.id into found_id from private.notification_outbox o
        where o.id = (item->>'id')::bigint and o.sent_at is null and o.claim_token is null
        for update;
        if found then
            perform private.complete_notifications_unfenced(jsonb_build_array(item));
        end if;
    end loop;
end $$;

create function private.complete_notifications_v2(p_results jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare item jsonb; found_id bigint;
begin
    for item in select value from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
        select o.id into found_id from private.notification_outbox o
        where o.id = (item->>'id')::bigint and o.sent_at is null
          and o.claim_token is not null and o.claim_token::text = item->>'claim_token'
        for update;
        if not found then continue; end if;
        if coalesce(item->>'outcome', '') not in ('sent', 'retry', 'release', 'drop') then continue; end if;
        perform private.complete_notifications_unfenced(jsonb_build_array(item));
        update private.notification_outbox o set claim_token = null where o.id = found_id;
    end loop;
end $$;

-- Rebind existing public wrappers explicitly after renaming their private implementations.
create or replace function public.claim_notifications(p_limit integer default 100)
returns table (
    id bigint, user_id uuid, kind text, event_id uuid, payload jsonb,
    collapse_id text, expires_at timestamptz, tokens jsonb, context jsonb
) language plpgsql security definer set search_path = '' as $$
begin
    if coalesce(auth.role(), '') is distinct from 'service_role' then raise exception 'not_allowed'; end if;
    return query select * from private.claim_notifications(p_limit);
end $$;
create or replace function public.complete_notifications(p_results jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
    if coalesce(auth.role(), '') is distinct from 'service_role' then raise exception 'not_allowed'; end if;
    perform private.complete_notifications(p_results);
end $$;
create function public.claim_notifications_v2(p_limit integer default 100)
returns table (
    id bigint, user_id uuid, kind text, event_id uuid, payload jsonb,
    collapse_id text, expires_at timestamptz, tokens jsonb, context jsonb, claim_token uuid
) language plpgsql security definer set search_path = '' as $$
begin
    if coalesce(auth.role(), '') is distinct from 'service_role' then raise exception 'not_allowed'; end if;
    return query select * from private.claim_notifications_v2(p_limit);
end $$;
create function public.complete_notifications_v2(p_results jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
    if coalesce(auth.role(), '') is distinct from 'service_role' then raise exception 'not_allowed'; end if;
    perform private.complete_notifications_v2(p_results);
end $$;

revoke execute on function
    private.claim_notifications_unfenced(integer), private.complete_notifications_unfenced(jsonb),
    private.claim_notifications(integer), private.complete_notifications(jsonb),
    private.claim_notifications_v2(integer), private.complete_notifications_v2(jsonb)
    from public, anon, authenticated, service_role;
revoke execute on function public.claim_notifications_v2(integer), public.complete_notifications_v2(jsonb)
    from public, anon, authenticated;
grant execute on function public.claim_notifications_v2(integer), public.complete_notifications_v2(jsonb) to service_role;
