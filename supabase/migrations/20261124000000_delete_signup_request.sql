-- Deleting an account also deletes its waitlist request (docs/SUBMISSION.md S1).
-- `private.signup_requests` is keyed by email, not by user, so deleting the Auth user left the address
-- behind, and in the website's Google Sheet. The existing delete trigger
-- (`signup_requests_deleted_sync`) now tells the Sheet the request was 'removed'.
-- A person who signs up again later joins the waitlist as new.
-- Compatible with earlier builds: same signature, called the same way by `delete-account`.

-- As in 20261109000000_review_fixes, plus the request.
create or replace function public.delete_my_account_data(p_user_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_game public.games%rowtype;
begin
    if p_user_id is null then raise exception 'invalid_input'; end if;
    for v_game in
        select g.* from public.games g join public.rsvps r on r.event_id = g.id
        where r.user_id = p_user_id and r.role = 'player' and g.ends_at > now()
        for update of g
    loop
        delete from public.rsvps where event_id = v_game.id and user_id = p_user_id;
        update public.games set
            going_count = going_count - 1,
            reposted_at = case when going_count = capacity and cancelled_at is null and auto_repost then now() else reposted_at end
        where id = v_game.id;
        insert into private.game_activity (event_id, kind) values (v_game.id, 'left');
    end loop;
    update private.game_activity
    set actor_id = null, actor_first_name = null, actor_last_initial = null, actor_grad_year = null
    where actor_id = p_user_id;
    -- The address as the auth hook stored it: lower-cased and trimmed.
    delete from private.signup_requests r
    using auth.users u
    where u.id = p_user_id and r.email = lower(btrim(u.email));
end $$;
