-- Join/leave summaries describe the latest action of each participant, not an append-only log.
-- Keep both legacy name arrays for the existing sender and ID-keyed state for reliable merges.
-- Briefly serialize outbox writes while legacy pending summaries are upgraded below.
begin;
lock table private.notification_outbox in share row exclusive mode;

create function private.host_update_members(p_payload jsonb)
returns jsonb language sql immutable set search_path = '' as $$
    select case
        when jsonb_typeof(p_payload->'roster_changes') = 'object' then p_payload->'roster_changes'
        -- Single-event payloads from an older in-flight producer are still unambiguous.
        when coalesce(p_payload->>'actor_id', '') <> ''
             and jsonb_array_length(coalesce(p_payload->'joined', '[]'::jsonb)) = 1
             and jsonb_array_length(coalesce(p_payload->'left', '[]'::jsonb)) = 0 then
            jsonb_build_object(p_payload->>'actor_id', jsonb_build_object(
                'name', p_payload->'joined'->>0, 'action', 'joined'))
        when coalesce(p_payload->>'actor_id', '') <> ''
             and jsonb_array_length(coalesce(p_payload->'left', '[]'::jsonb)) = 1
             and jsonb_array_length(coalesce(p_payload->'joined', '[]'::jsonb)) = 0 then
            jsonb_build_object(p_payload->>'actor_id', jsonb_build_object(
                'name', p_payload->'left'->>0, 'action', 'left'))
        else '{}'::jsonb
    end
$$;
revoke execute on function private.host_update_members(jsonb) from public, anon, authenticated, service_role;

create or replace function private.merge_notification_payload(p_kind text, p_old jsonb, p_new jsonb)
returns jsonb language plpgsql immutable set search_path = ''
as $$
declare
    v_names jsonb;
    v_members jsonb;
begin
    if p_kind = 'host_update' then
        v_members := private.host_update_members(p_old) || private.host_update_members(p_new);
        return p_old || p_new || jsonb_build_object(
            'roster_changes', v_members,
            'joined', coalesce((select jsonb_agg(value->>'name' order by key)
                from jsonb_each(v_members) where value->>'action' = 'joined'), '[]'::jsonb),
            'left', coalesce((select jsonb_agg(value->>'name' order by key)
                from jsonb_each(v_members) where value->>'action' = 'left'), '[]'::jsonb),
            'spots_left', coalesce(p_new->'spots_left', p_old->'spots_left'),
            'capacity', coalesce(p_new->'capacity', p_old->'capacity')
        );
    elsif p_kind = 'chat_message' then
        v_names := coalesce(p_old->'names', '[]'::jsonb);
        if coalesce(p_new->>'sender_name', '') <> ''
           and not v_names @> jsonb_build_array(p_new->>'sender_name') then
            v_names := v_names || jsonb_build_array(p_new->>'sender_name');
        end if;
        return jsonb_build_object(
            'actor_id', coalesce(p_new->>'actor_id', p_old->>'actor_id'),
            'sender_id', coalesce(p_new->>'sender_id', p_old->>'sender_id'),
            'sender_name', coalesce(p_new->>'sender_name', p_old->>'sender_name'),
            'sender_initials', coalesce(p_new->>'sender_initials', p_old->>'sender_initials'),
            'names', v_names,
            'body', coalesce(p_old->>'body', p_new->>'body'),
            'count', coalesce((p_old->>'count')::int, 1) + coalesce((p_new->>'count')::int, 1),
            'message_at', coalesce(p_new->>'message_at', p_old->>'message_at'),
            'others', coalesce(p_new->'others', p_old->'others', '[]'::jsonb)
        );
    end if;
    return p_new;
end $$;

create or replace function private.notify_on_activity()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
    v_game public.games%rowtype;
    v_name text;
    v_member record;
    v_payload jsonb;
begin
    select * into v_game from public.games where id = new.event_id;
    if not found then return new; end if;
    v_name := private.notification_names(new.actor_first_name, new.actor_last_initial::text);

    if new.kind = 'cancelled' then
        update private.notification_outbox set dropped = 'cancelled'
        where event_id = new.event_id and sent_at is null and dropped is null
          and kind in ('reminder', 'game_changed', 'interest_match', 'spot_open', 'saved_soon',
                       'host_update', 'game_full', 'chat_message');
        for v_member in
            select user_id from public.rsvps
            where event_id = new.event_id and role <> 'host' and user_id is distinct from new.actor_id
        loop
            perform private.enqueue_notification(
                v_member.user_id, 'game_cancelled', new.event_id,
                jsonb_build_object('actor_id', new.actor_id),
                'cancelled:' || new.event_id::text || ':' || v_member.user_id::text,
                'game:' || new.event_id::text, now(), v_game.starts_at, true, 'keep'
            );
        end loop;
    elsif new.kind in ('time_or_place_changed', 'meet_point_updated') then
        for v_member in
            select user_id from public.rsvps
            where event_id = new.event_id and user_id is distinct from new.actor_id
        loop
            perform private.enqueue_notification(
                v_member.user_id, 'game_changed', new.event_id,
                jsonb_build_object('actor_id', new.actor_id),
                'changed:' || new.event_id::text || ':' || v_member.user_id::text,
                'game:' || new.event_id::text, now() + interval '2 minutes', v_game.starts_at, false, 'debounce'
            );
        end loop;
    elsif new.kind in ('joined', 'left') and new.actor_id is not null and new.actor_id <> v_game.host_id then
        -- A pending full alert becomes obsolete as soon as someone frees a spot.
        if new.kind = 'left' then
            update private.notification_outbox set dropped = 'stale'
            where event_id = new.event_id and kind = 'game_full'
              and sent_at is null and dropped is null;
        end if;
        if new.kind = 'joined' and v_game.going_count >= v_game.capacity then
            update private.notification_outbox set dropped = 'replaced'
            where merge_key = 'host:' || new.event_id::text and sent_at is null and dropped is null;
            perform private.enqueue_notification(
                v_game.host_id, 'game_full', new.event_id,
                jsonb_build_object('actor_id', new.actor_id, 'going', v_game.going_count, 'capacity', v_game.capacity),
                'full:' || new.event_id::text, 'game:' || new.event_id::text,
                now(), v_game.starts_at, false, 'keep'
            );
        else
            v_payload := jsonb_build_object(
                'actor_id', new.actor_id,
                'roster_changes', jsonb_build_object(new.actor_id::text,
                    jsonb_build_object('name', v_name, 'action', new.kind)),
                'joined', case when new.kind = 'joined' then jsonb_build_array(v_name) else '[]'::jsonb end,
                'left', case when new.kind = 'left' then jsonb_build_array(v_name) else '[]'::jsonb end,
                'spots_left', v_game.capacity - v_game.going_count,
                'capacity', v_game.capacity
            );
            perform private.enqueue_notification(
                v_game.host_id, 'host_update', new.event_id, v_payload,
                'host:' || new.event_id::text, 'game:' || new.event_id::text,
                now() + interval '5 minutes', v_game.starts_at, false, 'keep'
            );
        end if;
    elsif new.kind = 'created' then
        for v_member in
            select p.id as user_id
            from public.profiles p
            where p.university_id = v_game.university_id
              and p.id <> v_game.host_id
              and p.banned_at is null
              and v_game.activity_slug = any (p.interests)
              and not private.blocked_pair(p.id, v_game.host_id)
        loop
            perform private.enqueue_notification(
                v_member.user_id, 'interest_match', new.event_id,
                jsonb_build_object('actor_id', v_game.host_id),
                'interest:' || new.event_id::text || ':' || v_member.user_id::text,
                'game:' || new.event_id::text, now() + interval '3 minutes', v_game.starts_at, true, 'keep'
            );
        end loop;
    end if;
    return new;
exception when others then
    raise warning 'notification enqueue failed for activity %: %', new.id, sqlerrm;
    return new;
end $$;

-- Old arrays have lost identity/order. Recover participants from the indexed event activity
-- window and use current membership to resolve same-transaction/timestamp action ties.
create function private.reconcile_pending_host_updates()
returns void language sql security definer set search_path = '' as $$
with recovered as (
    select o.id, jsonb_object_agg(p.id::text, jsonb_build_object(
        'name', private.notification_names(p.first_name, p.last_initial::text),
        'action', case when exists(select 1 from public.rsvps r
            where r.event_id = o.event_id and r.user_id = p.id) then 'joined' else 'left' end
    )) as members
    from private.notification_outbox o
    join lateral (
        select distinct a.actor_id from private.game_activity a
        where a.event_id = o.event_id and a.at >= o.created_at
          and a.kind in ('joined', 'left') and a.actor_id is not null and a.actor_id <> o.user_id
    ) changed on true
    join public.profiles p on p.id = changed.actor_id
    where o.kind = 'host_update' and o.sent_at is null and o.dropped is null
      and not (o.payload ? 'roster_changes')
    group by o.id
)
update private.notification_outbox o
set payload = private.merge_notification_payload('host_update', '{}'::jsonb,
        o.payload || jsonb_build_object('roster_changes', recovered.members)),
    resend = o.resend or (o.locked_at is not null and o.locked_at >= now() - interval '10 minutes')
from recovered where recovered.id = o.id;
$$;
revoke execute on function private.reconcile_pending_host_updates() from public, anon, authenticated, service_role;
select private.reconcile_pending_host_updates();
commit;
