"""Two-session notification regressions. Run after `supabase test db` on a fresh local DB."""

import json
import os
import select
import subprocess
import time

DATABASE = os.environ.get(
    "MASUNO_TEST_DATABASE_URL", "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
)
USER = "18000000-0000-4000-8000-000000000020"
CAMPUS = "18000000-0000-4000-8000-000000000010"
PSQL = ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", DATABASE]


def sql(statement):
    return subprocess.run(
        PSQL, input=statement, text=True, capture_output=True, check=True, timeout=10
    ).stdout.strip()


def session(statement, name):
    process = subprocess.Popen(
        PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, env={**os.environ, "PGAPPNAME": name}, bufsize=1,
    )
    process.stdin.write(statement + "\n\\echo READY\n")
    process.stdin.flush()
    return process


def ready(process):
    # select plus unbuffered fd reads avoids TextIOWrapper read-ahead hiding the READY line.
    deadline = time.monotonic() + 10
    output = b""
    while time.monotonic() < deadline:
        if select.select([process.stdout], [], [], 0.1)[0]:
            part = os.read(process.stdout.fileno(), 4096)
            if not part:
                raise AssertionError(process.stderr.read())
            output += part
            if b"READY\n" in output:
                return output.decode().replace("READY\n", "").strip()
    raise AssertionError("Timed out waiting for the held transaction")


def commit(process):
    output, errors = process.communicate("commit;\n", timeout=10)
    assert process.returncode == 0, errors
    return output


def stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        process.communicate(timeout=5)


def enqueue(kind, key, once=False):
    # Arguments come only from the fixed fixtures below.
    return f"""select private.enqueue_notification('{USER}', '{kind}', null,
        '{{}}', '{key}', null, now(), now() + interval '1 day', {str(once).lower()}, 'keep');"""


def overlapping_claims_share_a_budget():
    sql("\n".join(enqueue("interest_match", f"parallel:{i}") for i in range(5)))
    held = None
    try:
        held = session(
            "begin; select count(*) from private.claim_notifications(1);", "notification-held-claim"
        )
        assert ready(held) == "1", "First transaction must reserve one interest slot"
        # The other transaction sees different, unlocked outbox rows for the SAME user.
        assert sql("select count(*) from private.claim_notifications(100);") == "0", (
            "A concurrent drain must skip a user whose budget is being reserved"
        )
        commit(held)
        assert sql("select count(*) from private.claim_notifications(100);") == "1", (
            "After commit, the first active lease must leave only one interest slot"
        )
        sql(f"""select private.complete_notifications(jsonb_agg(jsonb_build_object('id',id,'outcome','sent')))
            from private.notification_outbox where user_id='{USER}' and locked_at is not null;""")
        assert sql(f"""select count(*) from private.notification_outbox
            where user_id='{USER}' and sent_at is not null;""") == "2"
        print("PASS overlapping claims cannot overbook the two-interest budget")
    finally:
        stop(held)
        sql(f"delete from private.notification_outbox where user_id='{USER}';")


def once_only_unique_violation_does_not_arm_resend():
    held = contender = None
    try:
        held = session(
            "begin; " + enqueue("reminder", "once:parallel", True)
            + f"update private.notification_outbox set locked_at=now() where user_id='{USER}';",
            "notification-once-insert",
        )
        ready(held)
        contender = subprocess.Popen(
            PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, env={**os.environ, "PGAPPNAME": "notification-once-contender"},
        )
        contender.stdin.write(enqueue("reminder", "once:parallel", True) + "\n")
        contender.stdin.flush()
        deadline = time.monotonic() + 5
        while sql("""select exists(select 1 from pg_stat_activity
            where application_name='notification-once-contender' and wait_event_type='Lock');""") != "t":
            assert time.monotonic() < deadline, "Contender must reach the conflicting insert"
            time.sleep(0.02)
        commit(held)
        _, errors = contender.communicate(timeout=10)
        assert contender.returncode == 0, errors
        assert sql(f"select resend from private.notification_outbox where user_id='{USER}';") == "f"
        sql(f"""select private.complete_notifications(jsonb_agg(jsonb_build_object('id',id,'outcome','sent')))
            from private.notification_outbox where user_id='{USER}';""")
        assert sql(f"""select count(*) from private.notification_outbox
            where user_id='{USER}' and sent_at is not null and not resend;""") == "1"
        print("PASS concurrent once-only insert fallback does not cause a second delivery")
    finally:
        stop(contender)
        stop(held)
        sql(f"delete from private.notification_outbox where user_id='{USER}';")


def stale_v2_completion_waits_for_reclaim_and_cannot_complete_it():
    """A locks the old version before B commits; EvalPlanQual must recheck B's token."""
    held = contender = None
    try:
        sql(enqueue("signup_approved", "fenced:parallel"))
        first = json.loads(sql("select row_to_json(c) from private.claim_notifications_v2(100) c;"))
        row_id = int(first["id"])
        sql(f"update private.notification_outbox set locked_at=now()-interval '11 minutes' where id={row_id};")
        held = session("begin; select row_to_json(c) from private.claim_notifications_v2(100) c;",
                       "notification-fenced-reclaim")
        second = json.loads(ready(held))
        assert first["claim_token"] != second["claim_token"]
        stale_result = json.dumps([{"id": row_id, "claim_token": first["claim_token"], "outcome": "sent",
                                  "drop_tokens": ["concurrent-claim-test-token"]}]).replace("'", "''")
        contender = subprocess.Popen(
            PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, env={**os.environ, "PGAPPNAME": "notification-fenced-stale"},
        )
        contender.stdin.write(f"select private.complete_notifications_v2('{stale_result}'::jsonb);\n")
        contender.stdin.flush()
        deadline = time.monotonic() + 5
        while sql("""select exists(select 1 from pg_stat_activity
            where application_name='notification-fenced-stale' and wait_event_type='Lock');""") != "t":
            assert time.monotonic() < deadline, "Stale completion must wait for B's row lock"
            time.sleep(0.02)
        commit(held)
        _, errors = contender.communicate(timeout=10)
        assert contender.returncode == 0, errors
        current = json.loads(sql(f"""select json_build_object('token',claim_token,'sent',sent_at,
            'locked',locked_at is not null) from private.notification_outbox where id={row_id};"""))
        assert current["token"] == second["claim_token"] and current["sent"] is None and current["locked"]
        assert sql("select exists(select 1 from private.device_tokens where token='concurrent-claim-test-token');") == "t"
        result = json.dumps([{"id": row_id, "claim_token": second["claim_token"], "outcome": "sent"}]).replace("'", "''")
        sql(f"select private.complete_notifications_v2('{result}'::jsonb);")
        assert sql(f"select sent_at is not null and claim_token is null from private.notification_outbox where id={row_id};") == "t"
        print("PASS stale v2 completion rechecks claim ownership after concurrent reclaim commits")
    finally:
        stop(contender)
        stop(held)
        sql(f"delete from private.notification_outbox where user_id='{USER}';")


def main():
    previous_push = sql("select value::text from public.app_config where key='push_enabled';")
    # This script owns only these fixtures and must never remove an existing user's account.
    assert sql(f"select exists(select 1 from auth.users where id='{USER}');") == "f"
    assert sql(f"select exists(select 1 from public.universities where id='{CAMPUS}');") == "f"
    try:
        sql(f"""
            begin;
            insert into public.universities(id,name,short_name,email_domain,center_lat,center_lng,timezone)
            select '{CAMPUS}','Claim tests','Claim','claim-tests.invalid',0,0,name
            from pg_timezone_names where extract(hour from now() at time zone name)=12 limit 1;
            insert into auth.users(id,email) values('{USER}','claim@claim-tests.invalid');
            insert into public.profiles(id,university_id,first_name,last_name,grad_year,guidelines_accepted_at)
            values('{USER}','{CAMPUS}','Claim','Test',2027,now());
            insert into private.device_tokens(token,user_id,environment,app_version)
            values('concurrent-claim-test-token','{USER}','sandbox','1.0');
            update public.app_config set value='true' where key='push_enabled';
            commit;
        """)
        overlapping_claims_share_a_budget()
        once_only_unique_violation_does_not_arm_resend()
        stale_v2_completion_waits_for_reclaim_and_cannot_complete_it()
    finally:
        # The stored configuration is JSON, quoted for SQL as one literal.
        value = json.dumps(json.loads(previous_push)).replace("'", "''")
        sql(f"""begin; delete from auth.users where id='{USER}';
            delete from public.universities where id='{CAMPUS}';
            update public.app_config set value='{value}'::jsonb where key='push_enabled'; commit;""")


if __name__ == "__main__":
    main()
