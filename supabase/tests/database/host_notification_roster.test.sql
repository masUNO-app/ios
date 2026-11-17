-- Host summaries retain one latest action per participant, including repeated leave/rejoin cycles.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

create function pg_temp.member_payload(p_actor text, p_name text, p_action text)
returns jsonb language sql as $$
    select jsonb_build_object('actor_id', p_actor, 'roster_changes',
        jsonb_build_object(p_actor, jsonb_build_object('name', p_name, 'action', p_action)),
        'joined', case when p_action = 'joined' then jsonb_build_array(p_name) else '[]'::jsonb end,
        'left', case when p_action = 'left' then jsonb_build_array(p_name) else '[]'::jsonb end)
$$;
create temp table folded(payload jsonb);
insert into folded values (pg_temp.member_payload('ari', 'Ari P.', 'joined'));
update folded set payload = private.merge_notification_payload('host_update', payload, pg_temp.member_payload('ari', 'Ari P.', 'left'));
select is((select payload->'joined' from folded), '[]'::jsonb, 'join then leave removes the obsolete join');
select is((select payload->'left' from folded), '["Ari P."]'::jsonb, 'join then leave has one departure');
update folded set payload = private.merge_notification_payload('host_update', payload, pg_temp.member_payload('ari', 'Ari P.', 'joined'));
select is((select payload->'joined' from folded), '["Ari P."]'::jsonb, 'join leave rejoin has one join');
select is((select payload->'left' from folded), '[]'::jsonb, 'rejoining removes the obsolete departure');
update folded set payload = private.merge_notification_payload('host_update', payload, pg_temp.member_payload('ari', 'Ari P.', 'joined'));
select is((select payload->'joined' from folded), '["Ari P."]'::jsonb, 'repeating the same action does not duplicate the person');
update folded set payload = private.merge_notification_payload('host_update', payload, pg_temp.member_payload('other-ari', 'Ari P.', 'left'));
select is((select count(*)::int from folded, jsonb_each(payload->'roster_changes')), 2, 'identical names retain distinct participant identities');
select is((select payload->'left' from folded), '["Ari P."]'::jsonb, 'another person with the same name does not overwrite the join');
select is(private.merge_notification_payload('host_update',
    '{"actor_id":"legacy","joined":["Legacy P."],"left":[]}'::jsonb,
    pg_temp.member_payload('legacy', 'Legacy P.', 'left'))->'joined', '[]'::jsonb,
    'an old single-event producer still merges by identity');
select is(private.merge_notification_payload('chat_message', '{"count":2}'::jsonb, '{"count":1}'::jsonb)->>'count',
    '3', 'chat aggregation retains its existing behavior');

insert into public.universities(id,name,short_name,email_domain,signup_enabled,center_lat,center_lng,timezone)
select '18200000-0000-4000-8000-000000000001', 'Roster tests','Roster','roster.invalid',false,25,-100,name
from pg_timezone_names where extract(hour from now() at time zone name)=12 limit 1;
insert into auth.users(id,email) values
    ('18200000-0000-4000-8000-000000000011','host@roster.invalid'),
    ('18200000-0000-4000-8000-000000000012','ricardo@roster.invalid'),
    ('18200000-0000-4000-8000-000000000013','ari@roster.invalid');
insert into public.profiles(id,university_id,first_name,last_name,grad_year,guidelines_accepted_at)
select id,'18200000-0000-4000-8000-000000000001',first,last,2027,now() from (values
    ('18200000-0000-4000-8000-000000000011'::uuid,'Host','Test'),
    ('18200000-0000-4000-8000-000000000012'::uuid,'Ricardo','Gomez'),
    ('18200000-0000-4000-8000-000000000013'::uuid,'Ari','Perez')
) fixture(id,first,last);
insert into public.games(id,university_id,host_id,activity_slug,title,starts_at,duration_minutes,ends_at,capacity,place_name,place_address,lat,lng)
select id,'18200000-0000-4000-8000-000000000001','18200000-0000-4000-8000-000000000011',
    'basketball','Roster regression',now()+interval '1 day',60,now()+interval '1 day 1 hour',capacity,'Court','Test',25,-100
from (values
    ('18200000-0000-4000-8000-000000000021'::uuid,6),
    ('18200000-0000-4000-8000-000000000022'::uuid,2),
    ('18200000-0000-4000-8000-000000000023'::uuid,6)
) fixture(id,capacity);
insert into public.rsvps(event_id,user_id,role)
select id,host_id,'host' from public.games where university_id='18200000-0000-4000-8000-000000000001';
update public.app_config set value='true' where key in ('push_enabled','chat_enabled');
-- Keep real/dev rows out of the controlled claim, then roll everything back.
update private.notification_outbox set not_before=now()+interval '30 days';
insert into private.device_tokens(token,user_id,environment,app_version)
values('roster-regression-device','18200000-0000-4000-8000-000000000011','sandbox','1.0');
create function pg_temp.act_as(p_actor uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub', p_actor::text, true)
$$;
create function pg_temp.host_payload(p_game uuid) returns jsonb language sql as $$
    select payload from private.notification_outbox where event_id=p_game and kind='host_update' and dropped is null and sent_at is null
$$;

set local role authenticated;
select pg_temp.act_as('18200000-0000-4000-8000-000000000012');
select public.join_game('18200000-0000-4000-8000-000000000021');
select public.leave_game('18200000-0000-4000-8000-000000000021');
select public.join_game('18200000-0000-4000-8000-000000000021');
reset role;
select is(pg_temp.host_payload('18200000-0000-4000-8000-000000000021')->'joined', '["Ricardo G."]'::jsonb, 'real join leave rejoin emits one joined name');
select is(pg_temp.host_payload('18200000-0000-4000-8000-000000000021')->'left', '[]'::jsonb, 'real rejoin removes earlier leave');
set local role authenticated;
select pg_temp.act_as('18200000-0000-4000-8000-000000000013');
select public.join_game('18200000-0000-4000-8000-000000000021');
select pg_temp.act_as('18200000-0000-4000-8000-000000000012');
select public.leave_game('18200000-0000-4000-8000-000000000021');
reset role;
select is(pg_temp.host_payload('18200000-0000-4000-8000-000000000021')->'joined', '["Ari P."]'::jsonb, 'another participant retains their join');
select is(pg_temp.host_payload('18200000-0000-4000-8000-000000000021')->'left', '["Ricardo G."]'::jsonb, 'only the latest departing participant is left');
select is(pg_temp.host_payload('18200000-0000-4000-8000-000000000021')->>'spots_left', '4', 'producer keeps the newest spot count');

set local role authenticated;
select pg_temp.act_as('18200000-0000-4000-8000-000000000012');
select public.join_game('18200000-0000-4000-8000-000000000022');
select public.leave_game('18200000-0000-4000-8000-000000000022');
reset role;
select is((select count(*)::int from private.notification_outbox where event_id='18200000-0000-4000-8000-000000000022' and kind='game_full' and dropped is null),0,'leaving invalidates a pending full alert');
set local role authenticated;
select pg_temp.act_as('18200000-0000-4000-8000-000000000012');
select public.join_game('18200000-0000-4000-8000-000000000022');
reset role;
select is((select count(*)::int from private.notification_outbox where event_id='18200000-0000-4000-8000-000000000022' and kind='game_full' and dropped is null),1,'filling again creates one fresh full alert');

-- Claim a snapshot, then change membership before its completion. The resend stays correct.
update private.notification_outbox set not_before=now()+interval '30 days';
update private.notification_outbox set not_before=now() where event_id='18200000-0000-4000-8000-000000000021' and kind='host_update' and dropped is null;
create temp table roster_claim as select * from private.claim_notifications_v2(100);
set local role authenticated;
select pg_temp.act_as('18200000-0000-4000-8000-000000000012');
select public.join_game('18200000-0000-4000-8000-000000000021');
reset role;
select is((select resend from private.notification_outbox where id=(select id from roster_claim)),true,'an action during delivery arms a corrected resend');
select private.complete_notifications_v2((select jsonb_agg(jsonb_build_object('id',id,'claim_token',claim_token,'outcome','sent')) from roster_claim));
select ok((select sent_at is null and claim_token is null from private.notification_outbox where id=(select id from roster_claim)), 'fenced completion leaves new membership work pending');
select is(pg_temp.host_payload('18200000-0000-4000-8000-000000000021')->'left','[]'::jsonb,'a mid-delivery rejoin removes the obsolete leave from the resend');

-- Simulate a corrupt pending legacy summary and recover IDs from activity, with tied timestamps.
set local role authenticated;
select pg_temp.act_as('18200000-0000-4000-8000-000000000012');
select public.join_game('18200000-0000-4000-8000-000000000023');
select pg_temp.act_as('18200000-0000-4000-8000-000000000013');
select public.join_game('18200000-0000-4000-8000-000000000023');
select public.leave_game('18200000-0000-4000-8000-000000000023');
select public.join_game('18200000-0000-4000-8000-000000000023');
reset role;
update private.notification_outbox set payload='{"actor_id":"18200000-0000-4000-8000-000000000013","joined":["Ricardo G.","Ari P.","Ari P."],"left":["Ari P."]}',
    locked_at=now(),claim_token='18200000-0000-4000-8000-000000000099'
where event_id='18200000-0000-4000-8000-000000000023' and kind='host_update';
select private.reconcile_pending_host_updates();
select is(pg_temp.host_payload('18200000-0000-4000-8000-000000000023')->'joined','["Ricardo G.","Ari P."]'::jsonb,'queued legacy duplicates are repaired by participant identity');
select is(pg_temp.host_payload('18200000-0000-4000-8000-000000000023')->'left','[]'::jsonb,'queued legacy opposite actions resolve to current membership');
select ok((select resend and claim_token='18200000-0000-4000-8000-000000000099' from private.notification_outbox where event_id='18200000-0000-4000-8000-000000000023' and kind='host_update'), 'repair retains claim ownership and queues a corrected resend');
select ok(not has_function_privilege('authenticated','private.reconcile_pending_host_updates()','execute'),'clients cannot invoke the repair helper');
select * from finish();
rollback;
