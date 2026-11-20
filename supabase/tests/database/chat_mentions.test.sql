-- Group chat mentions (NOTIF §3.5): which IDs send_message keeps, what game_messages shows, and the
-- mention push, which ignores the chat switch, mute and quiet hours but not blocks, membership,
-- chat_enabled or chat_reads, and replaces the ordinary push for that message.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Noon on campus, so quiet hours stay out of the way until they're tested.
insert into public.universities(id,name,short_name,email_domain,signup_enabled,center_lat,center_lng,timezone)
select '23000000-0000-4000-8000-000000000001','Mention tests','Mention','mention.invalid',true,25,-100,name
from pg_timezone_names where extract(hour from now() at time zone name)=12 limit 1;
create temp table people(id uuid primary key, fname text, lname text);
insert into people values
    ('23000000-0000-4000-8000-000000000011','Xavi','Test'),
    ('23000000-0000-4000-8000-000000000012','Sofia','Test'),
    ('23000000-0000-4000-8000-000000000013','Alice','Test'),
    ('23000000-0000-4000-8000-000000000014','Bruno','Test'),
    ('23000000-0000-4000-8000-000000000015','Carla','Test'),
    ('23000000-0000-4000-8000-000000000016','Frida','Test'),
    ('23000000-0000-4000-8000-000000000017','Dario','Test'),
    ('23000000-0000-4000-8000-000000000018','Elena','Test');
-- Twelve more for the cap: "Member A." to "Member L.".
insert into people
select ('23000000-0000-4000-8000-0000000000' || (30 + n)::text)::uuid, 'Member', chr(64 + n)
from generate_series(1,12) n;
-- The cap check builds its mention list from here while acting as a member.
grant select on people to authenticated;
insert into auth.users(id,email) select id, lower(fname || lname) || '@mention.invalid' from people;
insert into public.profiles(id,university_id,first_name,last_name,grad_year,guidelines_accepted_at,chat_rules_accepted_at)
select id,'23000000-0000-4000-8000-000000000001',fname,lname,2027,now(),now() from people;

-- Xavi hosts every game; Sofia writes. 21: the main cast. 22: the cap. 23: a merged burst. 24: send-time rules.
insert into public.games(id,university_id,host_id,activity_slug,title,starts_at,duration_minutes,ends_at,capacity,going_count,place_name,place_address,lat,lng)
select game,'23000000-0000-4000-8000-000000000001','23000000-0000-4000-8000-000000000011','tennis',title,
    now()+interval '1 day',60,now()+interval '1 day 1 hour',22,going,'Court','Test',25,-100
from (values
    ('23000000-0000-4000-8000-000000000021'::uuid,'Mention game',7),
    ('23000000-0000-4000-8000-000000000022'::uuid,'Busy game',14),
    ('23000000-0000-4000-8000-000000000023'::uuid,'Burst game',3),
    ('23000000-0000-4000-8000-000000000024'::uuid,'Rules game',5)
) fixture(game,title,going);
insert into public.rsvps(event_id,user_id,role)
select '23000000-0000-4000-8000-000000000021'::uuid, id,
    case when id='23000000-0000-4000-8000-000000000011' then 'host' else 'player' end
from people where fname not in ('Member','Elena');
insert into public.rsvps(event_id,user_id,role)
select '23000000-0000-4000-8000-000000000022'::uuid, id,
    case when id='23000000-0000-4000-8000-000000000011' then 'host' else 'player' end
from people where fname in ('Xavi','Sofia','Member');
insert into public.rsvps(event_id,user_id,role) values
    ('23000000-0000-4000-8000-000000000023','23000000-0000-4000-8000-000000000011','host'),
    ('23000000-0000-4000-8000-000000000023','23000000-0000-4000-8000-000000000012','player'),
    ('23000000-0000-4000-8000-000000000023','23000000-0000-4000-8000-000000000017','player'),
    ('23000000-0000-4000-8000-000000000024','23000000-0000-4000-8000-000000000011','host'),
    ('23000000-0000-4000-8000-000000000024','23000000-0000-4000-8000-000000000012','player'),
    ('23000000-0000-4000-8000-000000000024','23000000-0000-4000-8000-000000000013','player'),
    ('23000000-0000-4000-8000-000000000024','23000000-0000-4000-8000-000000000014','player'),
    ('23000000-0000-4000-8000-000000000024','23000000-0000-4000-8000-000000000017','player');

-- Alice turned chat pushes off, Bruno muted the main game, Carla blocked Sofia, Sofia blocked Frida.
insert into public.notification_prefs(user_id,chat) values ('23000000-0000-4000-8000-000000000013',false);
update public.rsvps set chat_muted=true
where event_id='23000000-0000-4000-8000-000000000021' and user_id='23000000-0000-4000-8000-000000000014';
insert into public.blocks(blocker_id,blocked_id) values
    ('23000000-0000-4000-8000-000000000015','23000000-0000-4000-8000-000000000012'),
    ('23000000-0000-4000-8000-000000000012','23000000-0000-4000-8000-000000000016');

update public.app_config set value='true' where key in ('push_enabled','chat_enabled');
update private.notification_outbox set not_before=now()+interval '30 days' where sent_at is null and dropped is null;
insert into private.device_tokens(token,user_id,environment,app_version)
select 'mention-device-' || fname, id,'sandbox','1.0' from people
where fname in ('Xavi','Alice','Bruno','Carla','Frida','Dario');

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
    select set_config('request.jwt.claim.sub',p_user::text,true)
$$;
-- Claims everything due with the v2 sender, as send-push would, and records it as sent.
-- last_claim keeps what the claim returned, with the payload rebuilt at claim time.
create temp table last_claim(id bigint, user_id uuid, kind text, payload jsonb, collapse_id text, claim_token uuid);
create function pg_temp.claim_and_send() returns void language plpgsql as $$
begin
    delete from last_claim;
    insert into last_claim
    select c.id, c.user_id, c.kind, c.payload, c.collapse_id, c.claim_token from private.claim_notifications_v2(100) c;
    perform private.complete_notifications_v2(coalesce((
        select jsonb_agg(jsonb_build_object('id',l.id,'claim_token',l.claim_token,'outcome','sent')) from last_claim l
    ),'[]'::jsonb));
end $$;

-- What send_message keeps: current members other than you, outside a block with you, named in the text.
set local role authenticated;
select pg_temp.act_as('23000000-0000-4000-8000-000000000012');
select is((select mentions from public.send_message('23000000-0000-4000-8000-000000000021',
        '@Alice T. @Bruno T. @Carla T. @Frida T. @Elena T. @Sofia T. @Xavi T. game on', gen_random_uuid(),
        array['23000000-0000-4000-8000-000000000013','23000000-0000-4000-8000-000000000014',
              '23000000-0000-4000-8000-000000000015','23000000-0000-4000-8000-000000000016',
              '23000000-0000-4000-8000-000000000018','23000000-0000-4000-8000-000000000012',
              '23000000-0000-4000-8000-000000000013','23000000-0000-4000-8000-000000000017',
              '23000000-0000-4000-8000-000000000011']::uuid[])),
    array['23000000-0000-4000-8000-000000000013','23000000-0000-4000-8000-000000000014',
          '23000000-0000-4000-8000-000000000011']::uuid[],
    'mentions keep members and the host, once each, in order; not yourself, a block either way, a non-member or a name missing from the text');
select is((select mentions from public.send_message('23000000-0000-4000-8000-000000000021',
        'No mentions from an older build', gen_random_uuid())),
    '{}'::uuid[], 'three-argument calls from older builds still work and mention nobody');
select is((select mentions from public.send_message('23000000-0000-4000-8000-000000000022',
        '@Member A. @Member B. @Member C. @Member D. @Member E. @Member F. @Member G. @Member H. @Member I. @Member J. @Member K. @Member L.',
        gen_random_uuid(), (select array_agg(id order by lname) from people where fname = 'Member'))),
    (select array_agg(id order by lname) from (select id, lname from people where fname = 'Member' order by lname limit 10) firsts),
    'at most ten mentions are kept, the first ten asked for');
select throws_ok($$ select public.send_message('23000000-0000-4000-8000-000000000021','Heads up @everyone',gen_random_uuid()) $$,
    'P0001','invalid_text','@everyone is still refused');
select throws_ok($$ select public.send_message('23000000-0000-4000-8000-000000000021','Anyone @here?',gen_random_uuid()) $$,
    'P0001','invalid_text','@here is still refused');

-- Other phones read the mentions; a reader doesn't see the ID of someone in a blocked pair with them.
select pg_temp.act_as('23000000-0000-4000-8000-000000000013');
select is((select mentions from public.game_messages where body like '@Alice T.%'),
    array['23000000-0000-4000-8000-000000000013','23000000-0000-4000-8000-000000000014',
          '23000000-0000-4000-8000-000000000011']::uuid[],
    'game_messages returns the mentions');
reset role;
insert into public.blocks(blocker_id,blocked_id) values ('23000000-0000-4000-8000-000000000017','23000000-0000-4000-8000-000000000013');
set local role authenticated;
select pg_temp.act_as('23000000-0000-4000-8000-000000000017');
select is((select mentions from public.game_messages where body like '@Alice T.%'),
    array['23000000-0000-4000-8000-000000000014','23000000-0000-4000-8000-000000000011']::uuid[],
    'a reader in a blocked pair with a mentioned person does not see their ID');
reset role;
delete from public.blocks where blocker_id='23000000-0000-4000-8000-000000000017';

-- The mention push: despite chat off and mute, and instead of the ordinary push.
create temp table main_message as
select id from private.chat_messages where event_id='23000000-0000-4000-8000-000000000021' and body like '@Alice T.%';
select is((select count(*)::int from private.notification_outbox
    where kind='chat_mention' and event_id='23000000-0000-4000-8000-000000000021' and dropped is null),
    3,'Alice, Bruno and Xavi each get a mention row');
select ok(exists (select 1 from private.notification_outbox
    where kind='chat_mention' and user_id='23000000-0000-4000-8000-000000000013'),
    'a mention is queued with group chat notifications off');
select ok(exists (select 1 from private.notification_outbox
    where kind='chat_mention' and user_id='23000000-0000-4000-8000-000000000014'),
    'a mention is queued in a muted game');
select is((select count(*)::int from private.notification_outbox
    where kind='chat_message' and event_id='23000000-0000-4000-8000-000000000021'
      and user_id in ('23000000-0000-4000-8000-000000000013','23000000-0000-4000-8000-000000000014',
                      '23000000-0000-4000-8000-000000000011')
      and payload->>'body' like '@Alice T.%'),
    0,'a mentioned person gets no ordinary chat push for that message');
select ok(exists (select 1 from private.notification_outbox
    where kind='chat_message' and event_id='23000000-0000-4000-8000-000000000021'
      and user_id='23000000-0000-4000-8000-000000000017'),
    'someone not mentioned still gets the ordinary chat push');
select is((select count(*)::int from private.notification_outbox
    where event_id='23000000-0000-4000-8000-000000000021'
      and user_id in ('23000000-0000-4000-8000-000000000015','23000000-0000-4000-8000-000000000016',
                      '23000000-0000-4000-8000-000000000018','23000000-0000-4000-8000-000000000012')),
    0,'nothing for the blocked pairs, a non-member or the sender');
select is((select not_before from private.notification_outbox
    where kind='chat_mention' and user_id='23000000-0000-4000-8000-000000000013'),
    now(),'a mention is due right away');
select is((select collapse_id from private.notification_outbox
    where kind='chat_mention' and user_id='23000000-0000-4000-8000-000000000013'),
    'mention:' || (select id from main_message)::text,'a mention has its own collapse ID');

select pg_temp.claim_and_send();
create temp table main_claim as select * from last_claim;
select is((select count(*)::int from main_claim where kind='chat_mention'),3,'all three mentions are claimed');
select is((select payload->>'sender_name' from main_claim where kind='chat_mention'
    and user_id='23000000-0000-4000-8000-000000000013'),'Sofia T.','the mention names the sender');
select is((select payload->>'message_id' from main_claim where kind='chat_mention'
    and user_id='23000000-0000-4000-8000-000000000014'),(select id from main_message)::text,
    'the mention carries its message');
select ok((select bool_and(o.sent_at is not null) from main_claim c join private.notification_outbox o on o.id = c.id
    where c.kind='chat_mention'),'mentions are sent despite chat off and mute');

-- A merged chat push leaves the mention out, so the mention's banner isn't summarized away.
set local role authenticated;
select pg_temp.act_as('23000000-0000-4000-8000-000000000012');
select public.send_message('23000000-0000-4000-8000-000000000023','Warm-up at 6',gen_random_uuid());
select public.send_message('23000000-0000-4000-8000-000000000023','@Dario T. bring the cones',gen_random_uuid(),
    array['23000000-0000-4000-8000-000000000017']::uuid[]);
select public.send_message('23000000-0000-4000-8000-000000000023','See you there',gen_random_uuid());
reset role;
select pg_temp.claim_and_send();
create temp table burst_claim as select * from last_claim;
select is((select (payload->>'count')::int from burst_claim
    where kind='chat_message' and user_id='23000000-0000-4000-8000-000000000017'),
    2,'the merged chat push counts only the messages that did not mention the recipient');
select is((select payload->>'body' from burst_claim
    where kind='chat_message' and user_id='23000000-0000-4000-8000-000000000017'),
    'Warm-up at 6','the merged chat push keeps the first ordinary body');
select is((select payload->>'body' from burst_claim
    where kind='chat_mention' and user_id='23000000-0000-4000-8000-000000000017'),
    '@Dario T. bring the cones','the mention goes on its own');
select isnt((select collapse_id from burst_claim where kind='chat_mention' and user_id='23000000-0000-4000-8000-000000000017'),
    (select collapse_id from burst_claim where kind='chat_message' and user_id='23000000-0000-4000-8000-000000000017'),
    'the merged push cannot collapse the mention banner');

-- Still never sent: chat switched off, already read, a block after enqueue, left the game.
set local role authenticated;
select pg_temp.act_as('23000000-0000-4000-8000-000000000012');
select public.send_message('23000000-0000-4000-8000-000000000024','@Alice T. one',gen_random_uuid(),
    array['23000000-0000-4000-8000-000000000013']::uuid[]);
reset role;
update public.app_config set value='false' where key='chat_enabled';
select pg_temp.claim_and_send();
update public.app_config set value='true' where key='chat_enabled';
select is((select dropped from private.notification_outbox where kind='chat_mention' and payload->>'body'='@Alice T. one'),
    'chat_off','nothing is sent while chat is switched off');

set local role authenticated;
select pg_temp.act_as('23000000-0000-4000-8000-000000000012');
select public.send_message('23000000-0000-4000-8000-000000000024','@Bruno T. two',gen_random_uuid(),
    array['23000000-0000-4000-8000-000000000014']::uuid[]);
reset role;
insert into private.chat_reads(event_id,user_id,last_read_at)
values ('23000000-0000-4000-8000-000000000024','23000000-0000-4000-8000-000000000014',now());
select pg_temp.claim_and_send();
select is((select dropped from private.notification_outbox where kind='chat_mention' and payload->>'body'='@Bruno T. two'),
    'read','nothing is sent once they have read past the message');

set local role authenticated;
select pg_temp.act_as('23000000-0000-4000-8000-000000000012');
select public.send_message('23000000-0000-4000-8000-000000000024','@Dario T. three',gen_random_uuid(),
    array['23000000-0000-4000-8000-000000000017']::uuid[]);
reset role;
insert into public.blocks(blocker_id,blocked_id) values ('23000000-0000-4000-8000-000000000017','23000000-0000-4000-8000-000000000012');
select pg_temp.claim_and_send();
delete from public.blocks where blocker_id='23000000-0000-4000-8000-000000000017';
select is((select dropped from private.notification_outbox where kind='chat_mention' and payload->>'body'='@Dario T. three'),
    'blocked','a block after the mention drops it');

set local role authenticated;
select pg_temp.act_as('23000000-0000-4000-8000-000000000012');
select public.send_message('23000000-0000-4000-8000-000000000024','@Alice T. four',gen_random_uuid(),
    array['23000000-0000-4000-8000-000000000013']::uuid[]);
reset role;
delete from public.rsvps where event_id='23000000-0000-4000-8000-000000000024' and user_id='23000000-0000-4000-8000-000000000013';
select pg_temp.claim_and_send();
select is((select dropped from private.notification_outbox where kind='chat_mention' and payload->>'body'='@Alice T. four'),
    'not_member','someone who left the game is not told');

-- Quiet hours hold ordinary chat until morning, not a mention.
update public.universities set timezone=(
    select name from pg_timezone_names where extract(hour from now() at time zone name)=23 limit 1
) where id='23000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.act_as('23000000-0000-4000-8000-000000000012');
select public.send_message('23000000-0000-4000-8000-000000000021','@Alice T. late one',gen_random_uuid(),
    array['23000000-0000-4000-8000-000000000013']::uuid[]);
reset role;
-- Dario's push was sent a moment ago, so this one waits ten seconds. Make it due now.
update private.notification_outbox set not_before=now()
where kind='chat_message' and user_id='23000000-0000-4000-8000-000000000017'
  and event_id='23000000-0000-4000-8000-000000000021' and sent_at is null and dropped is null;
select pg_temp.claim_and_send();
create temp table night_claim as select * from last_claim;
select ok(exists (select 1 from night_claim where kind='chat_mention' and payload->>'body'='@Alice T. late one'),
    'a mention goes out during quiet hours');
select ok((select not_before > now() + interval '1 hour' from private.notification_outbox
    where kind='chat_message' and user_id='23000000-0000-4000-8000-000000000017'
      and event_id='23000000-0000-4000-8000-000000000021' and sent_at is null and dropped is null),
    'the ordinary chat push for that message waits for morning');
update public.universities set timezone=(
    select name from pg_timezone_names where extract(hour from now() at time zone name)=12 limit 1
) where id='23000000-0000-4000-8000-000000000001';

-- The legacy claim leaves mentions for the v2 sender.
set local role authenticated;
select pg_temp.act_as('23000000-0000-4000-8000-000000000012');
select public.send_message('23000000-0000-4000-8000-000000000021','@Alice T. legacy',gen_random_uuid(),
    array['23000000-0000-4000-8000-000000000013']::uuid[]);
reset role;
update private.notification_outbox set not_before=now()+interval '30 days'
where sent_at is null and dropped is null and kind <> 'chat_mention';
select is_empty($$ select id from private.claim_notifications(100) $$,'the legacy claim skips a mention');
select is((select locked_at from private.notification_outbox where kind='chat_mention' and payload->>'body'='@Alice T. legacy'),
    null,'and leaves it unclaimed');
select pg_temp.claim_and_send();
create temp table legacy_claim as select * from last_claim;
select ok(exists (select 1 from legacy_claim where kind='chat_mention' and payload->>'body'='@Alice T. legacy'),
    'the v2 sender sends it');

select ok(not has_function_privilege('anon','public.send_message(uuid,text,uuid,uuid[])','execute'),
    'signed-out callers cannot send messages');
select ok(has_function_privilege('authenticated','public.send_message(uuid,text,uuid,uuid[])','execute'),
    'members can send messages with mentions');
select * from finish();
rollback;
