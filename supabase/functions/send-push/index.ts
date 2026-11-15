// Drains notification_outbox to APNs. The cron job calls this with the service-role key.
// Secrets, never in the repo: APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildPush, classifyApnsStatus, hostFor, type ClaimedNotification, type DeviceToken } from "./payload.ts";
import { importApnsKey, signApnsJwt } from "./jwt.ts";

const TOPIC = "com.masuno.app";

Deno.serve(async (request) => {
    if (request.method !== "POST") return new Response("Method Not Allowed", { status: 405 });
    if (roleOf(request.headers.get("Authorization")) !== "service_role") {
        return new Response("Unauthorized", { status: 401 });
    }

    const url = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceRoleKey) return new Response("Server misconfigured", { status: 500 });

    const admin = createClient(url, serviceRoleKey);
    const { data, error } = await admin.rpc("claim_notifications", { p_limit: 100 });
    if (error) {
        console.error("claim_notifications failed", error.message);
        return new Response("Could not claim", { status: 500 });
    }
    const rows = (data ?? []) as ClaimedNotification[];
    if (rows.length === 0) return new Response(null, { status: 204 });

    const keyPEM = Deno.env.get("APNS_KEY_P8");
    const keyID = Deno.env.get("APNS_KEY_ID");
    const teamID = Deno.env.get("APNS_TEAM_ID");
    if (!keyPEM || !keyID || !teamID) {
        await complete(admin, rows.map((row) => ({ id: row.id, outcome: "release" })));
        console.error("APNs secrets are missing");
        return new Response("APNs is not configured", { status: 500 });
    }

    let jwt: string;
    try {
        jwt = await providerToken(admin, keyPEM, keyID, teamID);
    } catch (cause) {
        await complete(admin, rows.map((row) => ({ id: row.id, outcome: "release" })));
        console.error("Could not sign the APNs token", cause);
        return new Response("APNs auth failed", { status: 500 });
    }

    const results = await deliverAll(rows, jwt);
    const { error: completeError } = await admin.rpc("complete_notifications", { p_results: results });
    if (completeError) {
        console.error("complete_notifications failed", completeError.message);
        return new Response("Could not record results", { status: 500 });
    }
    return Response.json({ sent: results.filter((result) => result.outcome === "sent").length });
});

function roleOf(authorization: string | null): string | null {
    const token = authorization?.replace(/^Bearer\s+/i, "") ?? "";
    const segment = token.split(".")[1];
    if (!segment) return null;
    try {
        const base64 = segment.replaceAll("-", "+").replaceAll("_", "/");
        const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
        const json = JSON.parse(atob(padded));
        return typeof json.role === "string" ? json.role : null;
    } catch {
        return null;
    }
}

async function providerToken(admin: SupabaseClient, pem: string, keyID: string, teamID: string): Promise<string> {
    const { data } = await admin.rpc("current_apns_jwt");
    if (typeof data === "string" && data.length > 0) return data;
    const jwt = await signApnsJwt(await importApnsKey(pem), keyID, teamID);
    await admin.rpc("store_apns_jwt", { p_token: jwt });
    return jwt;
}

interface DeliveryResult {
    id: number;
    outcome: "sent" | "retry" | "drop";
    error?: string;
    drop_tokens?: string[];
}

/// A few posts at a time. One hundred rows, one after another, outlives the claim lease.
async function deliverAll(rows: ClaimedNotification[], jwt: string): Promise<DeliveryResult[]> {
    const results: DeliveryResult[] = new Array(rows.length);
    let next = 0;
    const workers = Math.min(8, rows.length);
    await Promise.all(Array.from({ length: workers }, async () => {
        while (next < rows.length) {
            const index = next;
            next += 1;
            results[index] = await deliver(rows[index], jwt);
        }
    }));
    return results;
}

async function deliver(row: ClaimedNotification, jwt: string): Promise<DeliveryResult> {
    const dead: string[] = [];
    let sent = 0;
    let retry = false;
    let lastError = "";
    for (const device of row.tokens ?? []) {
        const outcome = await post(row, device, jwt);
        if (outcome.status === "sent") sent += 1;
        else if (outcome.status === "dead") dead.push(device.token);
        else if (outcome.status === "retry") {
            retry = true;
            lastError = outcome.error ?? "apns";
        } else {
            lastError = outcome.error ?? "rejected";
        }
    }
    const result: DeliveryResult = sent > 0
        ? { id: row.id, outcome: "sent" }
        : retry
        ? { id: row.id, outcome: "retry", error: lastError }
        : { id: row.id, outcome: "drop", error: lastError || (dead.length ? "bad_token" : "no_token") };
    if (dead.length) result.drop_tokens = dead;
    return result;
}

async function post(
    row: ClaimedNotification,
    device: DeviceToken,
    jwt: string,
): Promise<{ status: "sent" | "dead" | "retry" | "drop"; error?: string }> {
    const message = buildPush(row, device);
    let response: Response;
    try {
        response = await fetch(`${hostFor(device.environment)}/3/device/${device.token}`, {
            method: "POST",
            headers: { authorization: `bearer ${jwt}`, ...message.headers },
            body: JSON.stringify(message.body),
        });
    } catch (cause) {
        const error = cause instanceof Error ? cause.message : "network";
        return { status: "retry", error: error.slice(0, 200) };
    }
    let reason = "";
    try {
        reason = await response.text();
    } catch (cause) {
        const error = cause instanceof Error ? cause.message : "unread";
        return { status: "retry", error: error.slice(0, 200) };
    }
    return classifyApnsStatus(response.status, reason);
}

async function complete(admin: SupabaseClient, results: { id: number; outcome: string }[]) {
    await admin.rpc("complete_notifications", { p_results: results });
}

// Topic is fixed; exported so a test can see it without sending.
export const apnsTopic = TOPIC;
