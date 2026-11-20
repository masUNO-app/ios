"""Two-session block/join regressions. Run against a fresh local Supabase database."""

import os
import subprocess
import time

from notification_claim_concurrency import PSQL, commit, ready, session, sql, stop

CAMPUS = "21100000-0000-4000-8000-000000000001"
HOST = "21100000-0000-4000-8000-000000000011"
PLAYER = "21100000-0000-4000-8000-000000000012"
GAME = "21100000-0000-4000-8000-000000000021"


def as_user(user, statement):
    return f"set local role authenticated; select set_config('request.jwt.claim.sub','{user}',true); {statement}"


def contend(statement, name):
    process = subprocess.Popen(
        PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, env={**os.environ, "PGAPPNAME": name},
    )
    process.stdin.write("begin; " + statement + " commit;\n")
    process.stdin.flush()
    return process


def wait_for_lock(name):
    deadline = time.monotonic() + 5
    while sql(f"""select exists(select 1 from pg_stat_activity
        where application_name='{name}' and wait_event_type='Lock');""") != "t":
        assert time.monotonic() < deadline, "Contender must wait on the other transaction's game lock"
        time.sleep(0.02)


def assert_removed():
    assert sql(f"select count(*) from public.rsvps where event_id='{GAME}' and user_id='{PLAYER}';") == "0"
    assert sql(f"select going_count from public.games where id='{GAME}';") == "1"


def joining_first_is_removed_by_the_block():
    held = contender = None
    try:
        held = session("begin; " + as_user(PLAYER, f"select public.join_game('{GAME}');"), "block-join-first")
        ready(held)
        contender = contend(as_user(HOST, f"select public.block('{PLAYER}');"), "block-join-blocker")
        wait_for_lock("block-join-blocker")
        commit(held)
        _, errors = contender.communicate(timeout=10)
        assert contender.returncode == 0, errors
        assert_removed()
        print("PASS a host block removes a join that committed while it waited for the game")
    finally:
        stop(contender)
        stop(held)


def blocking_first_rejects_the_join():
    held = contender = None
    try:
        sql("begin; " + as_user(HOST, f"select public.unblock('{PLAYER}');") + " commit;")
        held = session("begin; " + as_user(HOST, f"select public.block('{PLAYER}');"), "block-join-block-first")
        ready(held)
        contender = contend(as_user(PLAYER, f"select public.join_game('{GAME}');"), "block-join-player")
        wait_for_lock("block-join-player")
        commit(held)
        _, errors = contender.communicate(timeout=10)
        assert contender.returncode != 0 and "not_found" in errors, errors
        assert_removed()
        print("PASS a join waiting on a host block rechecks visibility after that block commits")
    finally:
        stop(contender)
        stop(held)


def main():
    assert sql(f"select count(*) from auth.users where id in ('{HOST}','{PLAYER}');") == "0"
    assert sql(f"select count(*) from public.universities where id='{CAMPUS}';") == "0"
    try:
        sql(f"""begin;
            insert into public.universities(id,name,short_name,email_domain,center_lat,center_lng)
            values('{CAMPUS}','Block race tests','Blocks','block-race.invalid',25,-100);
            insert into auth.users(id,email) values('{HOST}','host@block-race.invalid'),('{PLAYER}','player@block-race.invalid');
            insert into public.profiles(id,university_id,first_name,last_name,grad_year,guidelines_accepted_at)
            values('{HOST}','{CAMPUS}','Host','Test',2027,now()),('{PLAYER}','{CAMPUS}','Player','Test',2027,now());
            insert into public.games(id,university_id,host_id,activity_slug,title,starts_at,duration_minutes,
                ends_at,capacity,place_name,place_address,lat,lng)
            values('{GAME}','{CAMPUS}','{HOST}','tennis','Block race',now()+interval '1 day',60,
                now()+interval '1 day 1 hour',2,'Court','Test',25,-100);
            insert into public.rsvps(event_id,user_id,role) values('{GAME}','{HOST}','host');
            commit;""")
        joining_first_is_removed_by_the_block()
        blocking_first_rejects_the_join()
    finally:
        sql(f"""begin; delete from auth.users where id in ('{HOST}','{PLAYER}');
            delete from public.universities where id='{CAMPUS}'; commit;""")


if __name__ == "__main__":
    main()
