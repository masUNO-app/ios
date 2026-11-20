-- Blocks hide attendance across lists, activity and queued notifications, including a block
-- added after a burst was queued. Host/player blocks remove the player without restoring them.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into public.universities(id,name,short_name,email_domain,signup_enabled,center_lat,center_lng,timezone)
select '21000000-0000-4000-8000-000000000001','Privacy tests','Privacy','privacy.invalid',true,25,-100,name
from pg_timezone_names where extract(hour from now() at time zone name)=12 limit 1;
insert into auth.users(id,email)
select id, first || '@privacy.invalid' from (values
    ('21000000-0000-4000-8000-000000000011'::uuid,'Host'),
    ('21000000-0000-4000-8000-000000000012'::uuid,'Alice'),
    ('21000000-0000-4000-8000-000000000013'::uuid,'Bruno'),
    ('21000000-0000-4000-8000-000000000014'::uuid,'Dario'),
    ('21000000-0000-4000-8000-000000000015'::uuid,'Elena'),
    ('21000000-0000-4000-8000-000000000016'::uuid,'Frida')
) fixture(id,first);
insert into public.profiles(id,university_id,first_name,last_name,grad_year,guidelines_accepted_at,chat_rules_accepted_at)
select id,'21000000-0000-4000-8000-000000000001',first,'Test',2027,now(),now() from (values
    ('21000000-0000-4000-8000-000000000011'::uuid,'Host'),
    ('21000000-0000-4000-8000-000000000012'::uuid,'Alice'),
    ('21000000-0000-4000-8000-000000000013'::uuid,'Bruno'),
    ('21000000-0000-4000-8000-000000000014'::uuid,'Dario'),
    ('21000000-0000-4000-8000-000000000015'::uuid,'Elena'),
    ('21000000-0000-4000-8000-000000000016'::uuid,'Frida')
) fixture(id,first);
insert into public.games(id,university_id,host_id,activity_slug,title,starts_at,duration_minutes,ends_at,capacity,going_count,place_name,place_address,lat,lng)
values ('21000000-0000-4000-8000-000000000021','21000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000011',
    'tennis','Privacy game',now()+interval '1 day',60,now()+interval '1 day 1 hour',6,6,'Court','Test',25,-100);
insert into public.rsvps(event_id,user_id,role,joined_at)
select '21000000-0000-4000-8000-000000000021',id,
    case when id='21000000-0000-4000-8000-000000000011' then 'host' else 'player' end,
    now()-make_interval(mins => position)
from (values
    ('21000000-0000-4000-8000-000000000011'::uuid,6),
    ('21000000-0000-4000-8000-000000000012'::uuid,5),
    ('21000000-0000-4000-8000-000000000013'::uuid,4),
    ('21000000-0000-4000-8000-000000000014'::uuid,3),
    ('21000000-0000-4000-8000-000000000015'::uuid,2),
    ('21000000-0000-4000-8000-000000000016'::uuid,1)
) fixture(id,position);
select private.activity_actor('21000000-0000-4000-8000-000000000021','joined','21000000-0000-4000-8000-000000000013');
select private.activity_actor('21000000-0000-4000-8000-000000000021','joined','21000000-0000-4000-8000-000000000012');
create temp table actor_activity as select id,actor_id from private.game_activity where event_id='21000000-0000-4000-8000-000000000021';
grant select on actor_activity to authenticated;
create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub',p_user::text,true)
$$;
create function pg_temp.other_ids(p_payload jsonb) returns jsonb language sql as $$
    select coalesce(jsonb_agg(value->>'id' order by position),'[]')
    from jsonb_array_elements(p_payload->'others') with ordinality entry(value,position)
$$;
update public.app_config set value='true' where key in ('push_enabled','chat_enabled');
update private.notification_outbox set not_before=now()+interval '30 days';
insert into private.device_tokens(token,user_id,environment,app_version)
select 'privacy-device-' || suffix,id,'sandbox','1.0' from (values
    ('21000000-0000-4000-8000-000000000012'::uuid,'12'),
    ('21000000-0000-4000-8000-000000000013'::uuid,'13'),
    ('21000000-0000-4000-8000-000000000016'::uuid,'16')
) fixture(id,suffix);

-- A blocked sender's first body and name must not survive in a burst whose latest sender is allowed.
set local role authenticated;
select pg_temp.act_as('21000000-0000-4000-8000-000000000013');
select public.send_message('21000000-0000-4000-8000-000000000021','Private first message',gen_random_uuid());
select pg_temp.act_as('21000000-0000-4000-8000-000000000011');
select public.send_message('21000000-0000-4000-8000-000000000021','Public pickup update',gen_random_uuid());
select pg_temp.act_as('21000000-0000-4000-8000-000000000012');
select public.block('21000000-0000-4000-8000-000000000013');
select is((select count(*)::int from public.rsvps where user_id='21000000-0000-4000-8000-000000000013'),0,
    'the blocker cannot read the blocked person attendance');
select is((select count(*)::int from private.game_activity where actor_id='21000000-0000-4000-8000-000000000013'),0,
    'underlying activity RLS does not expose a blocked actor');
select is((select count(*)::int from public.game_activity where id in
    (select id from actor_activity where actor_id='21000000-0000-4000-8000-000000000013')),0,
    'the public timeline does not reveal anonymous attendance from a blocked actor');
select pg_temp.act_as('21000000-0000-4000-8000-000000000013');
select is((select count(*)::int from public.game_attendees where user_id='21000000-0000-4000-8000-000000000012'),0,
    'the blocked person cannot read the blocker attendance');
select is((select count(*)::int from private.game_activity where actor_id='21000000-0000-4000-8000-000000000012'),0,
    'underlying activity hides the blocker from the blocked person too');
reset role;
update private.notification_outbox set not_before=now() where event_id='21000000-0000-4000-8000-000000000021' and kind='chat_message';
create temp table v2_claims as select * from private.claim_notifications_v2(100);
select is((select count(*)::int from v2_claims),3,'eligible recipients still receive the queued chat burst');
select is((select payload->>'body' from v2_claims where user_id='21000000-0000-4000-8000-000000000012'),
    'Public pickup update','a block after enqueue removes the earlier blocked sender body');
select is((select payload->'names' from v2_claims where user_id='21000000-0000-4000-8000-000000000012'),
    '["Host T."]'::jsonb,'the merged names contain only allowed senders');
select is((select (payload->>'count')::int from v2_claims where user_id='21000000-0000-4000-8000-000000000012'),1,
    'the burst count does not expose blocked messages');
select is((select pg_temp.other_ids(payload) from v2_claims where user_id='21000000-0000-4000-8000-000000000012'),
    '["21000000-0000-4000-8000-000000000014","21000000-0000-4000-8000-000000000015"]'::jsonb,
    'v2 claims filter before limiting and refill both group member slots');
select is((select pg_temp.other_ids(payload) from v2_claims where user_id='21000000-0000-4000-8000-000000000013'),
    '["21000000-0000-4000-8000-000000000014","21000000-0000-4000-8000-000000000015"]'::jsonb,
    'v2 claims hide the blocker from a queued push to the blocked person');
select is((select pg_temp.other_ids(payload) from v2_claims where user_id='21000000-0000-4000-8000-000000000016'),
    '["21000000-0000-4000-8000-000000000012","21000000-0000-4000-8000-000000000013"]'::jsonb,
    'an unrelated recipient still sees both names in the blocked pair');
select ok((select bool_and(claim_token is not null) from v2_claims),'privacy refresh preserves v2 fencing identities');
select private.complete_notifications_v2(jsonb_agg(jsonb_build_object('id',id,'claim_token',claim_token,'outcome','release'))) from v2_claims;
create temp table legacy_claims as select * from private.claim_notifications(100);
select is((select payload->>'body' from legacy_claims where user_id='21000000-0000-4000-8000-000000000012'),
    'Public pickup update','legacy claims also recheck merged message content');
select is((select pg_temp.other_ids(payload) from legacy_claims where user_id='21000000-0000-4000-8000-000000000012'),
    '["21000000-0000-4000-8000-000000000014","21000000-0000-4000-8000-000000000015"]'::jsonb,
    'legacy claims also recheck other members');
select private.complete_notifications(jsonb_agg(jsonb_build_object('id',id,'outcome','release'))) from legacy_claims;
set local role authenticated;
select pg_temp.act_as('21000000-0000-4000-8000-000000000012');
reset role;
update private.notification_outbox set payload = payload || jsonb_build_object(
    'actor_id','21000000-0000-4000-8000-000000000013','sender_id','21000000-0000-4000-8000-000000000013')
where event_id='21000000-0000-4000-8000-000000000021' and user_id='21000000-0000-4000-8000-000000000012' and kind='chat_message';
create temp table latest_blocked as select * from private.claim_notifications_v2(100);
select is((select payload->'names' from latest_blocked where user_id='21000000-0000-4000-8000-000000000012'),
    '["Host T."]'::jsonb,'a blocked latest sender does not discard an earlier allowed sender');
select private.complete_notifications_v2(jsonb_agg(jsonb_build_object('id',id,'claim_token',claim_token,'outcome','release'))) from latest_blocked;
set local role authenticated;
select pg_temp.act_as('21000000-0000-4000-8000-000000000012');
select public.leave_game('21000000-0000-4000-8000-000000000021');
reset role;
create temp table after_leave as select * from private.claim_notifications_v2(100);
select is((select count(*)::int from after_leave where user_id='21000000-0000-4000-8000-000000000012'),0,
    'leaving a game closes queued chat delivery too');

-- Blocking a player as host also removes yourself from games they host, in the same transaction.
insert into public.games(id,university_id,host_id,activity_slug,title,starts_at,duration_minutes,ends_at,capacity,going_count,place_name,place_address,lat,lng)
select game,'21000000-0000-4000-8000-000000000001',host,'tennis','Host privacy',now()+interval '1 day',60,
    now()+interval '1 day 1 hour',2,2,'Court','Test',25,-100
from (values
    ('21000000-0000-4000-8000-000000000022'::uuid,'21000000-0000-4000-8000-000000000011'::uuid),
    ('21000000-0000-4000-8000-000000000023'::uuid,'21000000-0000-4000-8000-000000000013'::uuid)
) fixture(game,host);
insert into public.rsvps(event_id,user_id,role) values
    ('21000000-0000-4000-8000-000000000022','21000000-0000-4000-8000-000000000011','host'),
    ('21000000-0000-4000-8000-000000000022','21000000-0000-4000-8000-000000000013','player'),
    ('21000000-0000-4000-8000-000000000023','21000000-0000-4000-8000-000000000013','host'),
    ('21000000-0000-4000-8000-000000000023','21000000-0000-4000-8000-000000000011','player');
set local role authenticated;
select pg_temp.act_as('21000000-0000-4000-8000-000000000011');
select public.block('21000000-0000-4000-8000-000000000013');
select throws_ok($$ select public.join_game('21000000-0000-4000-8000-000000000023') $$,
    'P0001','not_found','a blocked host cannot be rejoined');
reset role;
select is((select count(*)::int from public.rsvps where event_id='21000000-0000-4000-8000-000000000022' and role='player'),0,
    'a host block removes the blocked player');
select is((select count(*)::int from public.rsvps where event_id='21000000-0000-4000-8000-000000000023' and role='player'),0,
    'blocking a host removes the blocker own player RSVP');
select is((select going_count from public.games where id='21000000-0000-4000-8000-000000000022'),1,'the host game frees the occupied spot');
select is((select going_count from public.games where id='21000000-0000-4000-8000-000000000023'),1,'the other host game also frees the spot');
select ok((select bool_and(reposted_at is not null) from public.games where id in
    ('21000000-0000-4000-8000-000000000022','21000000-0000-4000-8000-000000000023')),
    'previously full games retain normal auto-repost behavior');
select is((select count(*)::int from public.rsvps where role='host' and event_id in
    ('21000000-0000-4000-8000-000000000022','21000000-0000-4000-8000-000000000023')),2,
    'neither host RSVP is removed');
set local role authenticated;
select pg_temp.act_as('21000000-0000-4000-8000-000000000011');
select public.unblock('21000000-0000-4000-8000-000000000013');
reset role;
select is((select count(*)::int from public.rsvps where role='player' and event_id in
    ('21000000-0000-4000-8000-000000000022','21000000-0000-4000-8000-000000000023')),0,
    'unblocking never restores removed attendance');
-- A roster summary can name more than its latest actor. Filter every identity at claim time.
set local role authenticated;
select pg_temp.act_as('21000000-0000-4000-8000-000000000011');
select public.block('21000000-0000-4000-8000-000000000013');
reset role;
insert into private.device_tokens(token,user_id,environment,app_version)
values('privacy-host-device','21000000-0000-4000-8000-000000000011','sandbox','1.0');
update private.notification_outbox set not_before=now()+interval '30 days';
select private.enqueue_notification('21000000-0000-4000-8000-000000000011','host_update',
    '21000000-0000-4000-8000-000000000022',
    '{"actor_id":"21000000-0000-4000-8000-000000000013","roster_changes":{
      "21000000-0000-4000-8000-000000000013":{"name":"Bruno T.","action":"left"},
      "21000000-0000-4000-8000-000000000014":{"name":"Dario T.","action":"joined"}}}',
    'privacy-host-summary',null,now(),now()+interval '1 day',false,'keep');
create temp table host_summary as select * from private.claim_notifications_v2(100);
select is((select payload->'joined' from host_summary),'["Dario T."]'::jsonb,'host summaries preserve allowed members');
select is((select payload->'left' from host_summary),'[]'::jsonb,'host summaries omit blocked names');
select is((select payload->>'actor_id' from host_summary),'21000000-0000-4000-8000-000000000014',
    'the summary actor identity is also replaced with a visible member');
select ok((select not (payload->'roster_changes' ? '21000000-0000-4000-8000-000000000013') from host_summary),
    'blocked identities are absent from the underlying roster payload');
select is(private.notification_payload_at_claim('host_update','21000000-0000-4000-8000-000000000022',
    '21000000-0000-4000-8000-000000000011',now(),'{"joined":["Unknown person","Another person"]}'),null::jsonb,
    'legacy multi-person summaries without identities fail closed');
select is(private.notification_payload_at_claim('chat_message','21000000-0000-4000-8000-000000000022',
    '21000000-0000-4000-8000-000000000011',now(),'{"body":"old","count":1}'),null::jsonb,
    'chat content without a visible source message fails closed');
-- The migration uses this same helper to reconcile block pairs that existed before rollout.
insert into public.rsvps(event_id,user_id,role) values
    ('21000000-0000-4000-8000-000000000022','21000000-0000-4000-8000-000000000013','player');
update public.games set going_count=2 where id='21000000-0000-4000-8000-000000000022';
select private.remove_blocked_players('21000000-0000-4000-8000-000000000011','21000000-0000-4000-8000-000000000013');
select is((select going_count from public.games where id='21000000-0000-4000-8000-000000000022'),1,
    'existing invalid host/player membership is repaired during backfill');
select private.remove_blocked_players('21000000-0000-4000-8000-000000000013','21000000-0000-4000-8000-000000000011');
select is((select going_count from public.games where id='21000000-0000-4000-8000-000000000022'),1,
    'repeating a reverse block or backfill cannot decrement the spot twice');
select ok(not has_function_privilege('authenticated','private.chat_others(uuid,uuid,uuid)','execute'),
    'clients cannot bypass RLS through the notification helper');
select * from finish();
rollback;
