-- Report alerts (B8, SPEC §8.6): each new report posts to the team chat's incoming webhook.
-- The webhook URL lives in Vault, never in the repo (README, "Report alerts").

create extension if not exists pg_net with schema extensions;

-- Posts a short alert for a new report: reason, target type and id, and a dashboard link.
-- No names or note text. A failure is logged and never blocks the report itself.
-- Returns the inserted row unchanged.
create or replace function private.alert_new_report()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
    v_webhook_url text;
    v_dashboard_url text;
    v_message text;
begin
    select decrypted_secret into v_webhook_url from vault.decrypted_secrets where name = 'report_alert_webhook_url';
    if v_webhook_url is null then
        raise warning 'report % not alerted: Vault secret report_alert_webhook_url is missing', new.id;
        return new;
    end if;
    select decrypted_secret into v_dashboard_url from vault.decrypted_secrets where name = 'report_alert_dashboard_url';

    v_message := format(
        'New report: %s, about a %s. Report %s. Act on it within 24 h. %s',
        new.reason,
        case when new.user_id is not null then 'person' else 'game' end,
        new.id,
        coalesce(v_dashboard_url, 'Open the reports table in Supabase.')
    );
    -- Discord reads "content" and Slack reads "text"; each ignores the other.
    perform net.http_post(
        url := v_webhook_url,
        body := jsonb_build_object('content', v_message, 'text', v_message),
        headers := '{"Content-Type": "application/json"}'::jsonb
    );
    return new;
exception when others then
    raise warning 'report % not alerted: %', new.id, sqlerrm;
    return new;
end $$;

revoke execute on function private.alert_new_report() from public, anon, authenticated;

create trigger reports_alert_team
after insert on public.reports
for each row execute function private.alert_new_report();
