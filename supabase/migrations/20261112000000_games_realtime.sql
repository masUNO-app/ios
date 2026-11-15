-- Live game lists (1.0 refresh): a game changing, or someone joining or leaving, pings the game's
-- campus on `campus:<university_id>:games` with the IDs of the games that changed. Phones re-read
-- only those games through the RLS views, so what each person sees doesn't change, and a change on
-- one campus never wakes phones on another.
--
-- Statement-level triggers with transition tables: one ping per campus per statement, however many
-- rows it touched. Postgres only allows a transition table on a single-event trigger, hence one
-- trigger per event. A big statement (the demo campus refresh) sends no IDs, which tells the app to
-- re-read its lists instead.
create function private.send_game_changes(p_university uuid, p_ids uuid[])
returns void language sql set search_path = ''
as $$
    select realtime.send(
        case when cardinality(p_ids) <= 50 then jsonb_build_object('ids', to_jsonb(p_ids)) else '{}'::jsonb end,
        'changed', 'campus:' || p_university::text || ':games', true
    )
$$;

create function private.broadcast_game_changes()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
    -- Each branch is only planned for the table that runs it, so `changed` always has its columns.
    if tg_table_name = 'games' then
        perform private.send_game_changes(c.university_id, array_agg(distinct c.id))
        from changed c group by c.university_id;
    else
        perform private.send_game_changes(g.university_id, array_agg(distinct c.event_id))
        from changed c join public.games g on g.id = c.event_id group by g.university_id;
    end if;
    return null;
exception when others then
    -- A failed ping never blocks the write: the app also re-reads on foreground and pull to refresh.
    raise warning 'games broadcast failed: %', sqlerrm;
    return null;
end $$;

create trigger games_inserted_broadcast after insert on public.games
referencing new table as changed for each statement execute function private.broadcast_game_changes();
create trigger games_updated_broadcast after update on public.games
referencing new table as changed for each statement execute function private.broadcast_game_changes();
create trigger games_deleted_broadcast after delete on public.games
referencing old table as changed for each statement execute function private.broadcast_game_changes();

create trigger rsvps_inserted_broadcast after insert on public.rsvps
referencing new table as changed for each statement execute function private.broadcast_game_changes();
create trigger rsvps_updated_broadcast after update on public.rsvps
referencing new table as changed for each statement execute function private.broadcast_game_changes();
create trigger rsvps_deleted_broadcast after delete on public.rsvps
referencing old table as changed for each statement execute function private.broadcast_game_changes();

-- Signed-in, unbanned people may listen on their own campus's topic only. `profiles.id` is the
-- primary key, so the check is one index lookup per join.
do $$
begin
    if to_regclass('realtime.messages') is null then
        raise warning 'realtime.messages is missing: games channel policy not created';
        return;
    end if;
    execute $policy$
        create policy "campus members receive game changes" on realtime.messages
        for select to authenticated using (
            extension = 'broadcast'
            and exists (
                select 1 from public.profiles p
                where p.id = (select auth.uid())
                  and p.banned_at is null
                  and 'campus:' || p.university_id::text || ':games' = (select realtime.topic())
            )
        )
    $policy$;
end $$;
