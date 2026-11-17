// Drains notification_outbox to APNs. The cron job calls this with the service-role key.
// Secrets, never in the repo: APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { type ClaimedNotification } from "./payload.ts";
import { deliverAll, type FencedNotification, type DeliveryResult } from "./delivery.ts";
import { importApnsKey, signApnsJwt } from "./jwt.ts";
import { bearerMatches } from "./auth.ts";

const TOPIC = "com.masuno.app";

Deno.serve(async (request) => {
    if (request.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

    const url = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceRoleKey) return new Response("Server misconfigured", { status: 500 });
    if (!(await bearerMatches(request.headers.get("Authorization"), serviceRoleKey))) {
        return new Response("Unauthorized", { status: 401 });
    }

    const admin = createClient(url, serviceRoleKey, {
        global: { fetch: (input, init) => fetch(input, {
            ...init,
            signal: init?.signal
                ? AbortSignal.any([init.signal, AbortSignal.timeout(15_000)])
                : AbortSignal.timeout(15_000),
        }) },
    });
    const { data, error } = await admin.rpc("claim_notifications_v2", { p_limit: 100 });
    if (error) {
        console.error("claim_notifications failed", error.message);
        return new Response("Could not claim", { status: 500 });
    }
    const claimed = (data ?? []) as (ClaimedNotification & { claim_token?: string })[];
    if (claimed.some((row) => typeof row.claim_token !== "string" || !row.claim_token)) {
        console.error("Notification claim protocol mismatch");
        return new Response("Invalid claim protocol", { status: 500 });
    }
    const rows = claimed as FencedNotification[];
    if (rows.length === 0) return new Response(null, { status: 204 });

    const keyPEM = Deno.env.get("APNS_KEY_P8");
    const keyID = Deno.env.get("APNS_KEY_ID");
    const teamID = Deno.env.get("APNS_TEAM_ID");
    if (!keyPEM || !keyID || !teamID) {
        await complete(admin, rows.map((row) => ({ id: row.id, claim_token: row.claim_token, outcome: "release" })));
        console.error("APNs secrets are missing");
        return new Response("APNs is not configured", { status: 500 });
    }

    let jwt: string;
    try {
        jwt = await providerToken(admin, keyPEM, keyID, teamID);
    } catch (cause) {
        await complete(admin, rows.map((row) => ({ id: row.id, claim_token: row.claim_token, outcome: "release" })));
        console.error("Could not sign the APNs token", cause);
        return new Response("APNs auth failed", { status: 500 });
    }

    const results = await deliverAll(rows, jwt);
    const { error: completeError } = await admin.rpc("complete_notifications_v2", { p_results: results });
    if (completeError) {
        console.error("complete_notifications failed", completeError.message);
        return new Response("Could not record results", { status: 500 });
    }
    return Response.json({ sent: results.filter((result) => result.outcome === "sent").length });
});

async function providerToken(admin: SupabaseClient, pem: string, keyID: string, teamID: string): Promise<string> {
    const { data } = await admin.rpc("current_apns_jwt");
    if (typeof data === "string" && data.length > 0) return data;
    const jwt = await signApnsJwt(await importApnsKey(pem), keyID, teamID);
    await admin.rpc("store_apns_jwt", { p_token: jwt });
    return jwt;
}

async function complete(admin: SupabaseClient, results: (Pick<DeliveryResult, "id" | "claim_token"> & { outcome: DeliveryResult["outcome"] | "release" })[]) {
    const { error } = await admin.rpc("complete_notifications_v2", { p_results: results });
    if (error) console.error("Could not release notification claims", error.message);
}

// Topic is fixed; exported so a test can see it without sending.
export const apnsTopic = TOPIC;
