-- Chat pushes name up to two other members so the phone can show the chat as a group. Those names
-- skipped the block check, so two people in a blocked pair in the same game could see each other's
-- name in a notification. The sender is already left out: notify_on_chat never queues a push across
-- a block.

-- As in 20261116000000, minus anyone in a blocked pair with the recipient.
-- Parameters: the game, the message's sender and the push's recipient.
-- Returns up to two {id, name} objects, earliest to join first.
create or replace function private.chat_others(p_event uuid, p_sender uuid, p_recipient uuid)
returns jsonb language sql stable security definer set search_path = ''
as $$
    select coalesce(jsonb_agg(jsonb_build_object('id', picked.id, 'name', picked.label)), '[]'::jsonb)
    from (
        select p.id, private.notification_names(p.first_name, p.last_initial::text) as label
        from public.rsvps r
        join public.profiles p on p.id = r.user_id
        where r.event_id = p_event and r.user_id <> p_sender and r.user_id <> p_recipient
          and not private.blocked_pair(r.user_id, p_recipient)
        order by r.joined_at
        limit 2
    ) picked
$$;

revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.blocked_pair(uuid, uuid), private.same_university(uuid, uuid),
    private.active_viewer(), private.blocked_someone_going(uuid) to authenticated;
