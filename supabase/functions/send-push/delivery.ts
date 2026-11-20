// Delivery is separate from the Edge entrypoint so transport and timing can be tested without APNs.
import { buildPush, classifyApnsStatus, hostFor, mapPool, type ClaimedNotification, type DeviceToken } from "./payload.ts";

export interface FencedNotification extends ClaimedNotification { claim_token: string }
export interface DeliveryResult {
    id: number;
    claim_token: string;
    outcome: "sent" | "retry" | "drop";
    error?: string;
    drop_tokens?: string[];
}

interface Outcome { status: "sent" | "dead" | "retry" | "drop"; error?: string }
interface DeliveryOptions {
    fetcher?: typeof fetch;
    concurrency?: number;
    requestTimeoutMs?: number;
    budgetMs?: number;
    now?: () => number;
}

// A single invocation stays well below the ten-minute SQL lease and leaves time for completion.
// This caps actual HTTP requests across all rows/devices, rather than multiplying nested pools.
export const HTTP_CONCURRENCY = 8;
export const REQUEST_TIMEOUT_MS = 5_000;
export const DELIVERY_BUDGET_MS = 25_000;

export async function deliverAll(rows: FencedNotification[], jwt: string, options: DeliveryOptions = {}): Promise<DeliveryResult[]> {
    const now = options.now ?? (() => performance.now());
    const deadline = now() + (options.budgetMs ?? DELIVERY_BUDGET_MS);
    // One ordered lane per phone. Different phones can send concurrently, but a
    // later alert must never overtake an earlier request to the same APNs token.
    const lanes = new Map<string, { row: FencedNotification; rowIndex: number; device: DeviceToken }[]>();
    rows.forEach((row, rowIndex) => {
        for (const device of row.tokens ?? []) {
            const key = `${device.environment}:${device.token}`;
            const lane = lanes.get(key) ?? [];
            lane.push({ row, rowIndex, device });
            lanes.set(key, lane);
        }
    });
    const grouped: { device: DeviceToken; outcome: Outcome }[][] = rows.map(() => []);
    await mapPool([...lanes.values()], options.concurrency ?? HTTP_CONCURRENCY, async (lane) => {
        let retryEarlier = false;
        for (const { row, rowIndex, device } of lane) {
            const remaining = deadline - now();
            const outcome: Outcome = retryEarlier
                ? { status: "retry" as const, error: "earlier_notification_pending" }
                : remaining <= 0
                    ? { status: "retry" as const, error: "delivery_deadline" }
                    : await post(row, device, jwt, options.fetcher ?? fetch,
                        Math.min(remaining, options.requestTimeoutMs ?? REQUEST_TIMEOUT_MS));
            grouped[rowIndex].push({ device, outcome });
            retryEarlier ||= outcome.status === "retry";
        }
    });
    return rows.map((row, index) => {
        const outcomes = grouped[index];
        const sent = outcomes.some(({ outcome }) => outcome.status === "sent");
        const retry = outcomes.find(({ outcome }) => outcome.status === "retry");
        const dead = outcomes.filter(({ outcome }) => outcome.status === "dead").map(({ device }) => device.token);
        // Preserve the existing at-least-one-device policy. Retrying successful devices here would
        // duplicate notifications; a per-device outbox would require a separate product decision.
        const result: DeliveryResult = {
            id: row.id,
            claim_token: row.claim_token,
            outcome: sent ? "sent" : retry ? "retry" : "drop",
        };
        if (!sent) result.error = retry?.outcome.error
            ?? outcomes.find(({ outcome }) => outcome.error)?.outcome.error
            ?? (dead.length ? "bad_token" : "no_token");
        if (dead.length) result.drop_tokens = dead;
        return result;
    });
}

async function post(row: FencedNotification, device: DeviceToken, jwt: string, fetcher: typeof fetch, timeoutMs: number): Promise<Outcome> {
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<Outcome>((resolve) => {
        timer = setTimeout(() => {
            controller.abort();
            resolve({ status: "retry", error: "apns_timeout" });
        }, Math.max(timeoutMs, 1));
    });
    const work = async (): Promise<Outcome> => {
        const message = buildPush(row, device);
        try {
            const response = await fetcher(`${hostFor(device.environment)}/3/device/${device.token}`, {
                method: "POST",
                headers: { authorization: `bearer ${jwt}`, ...message.headers },
                body: JSON.stringify(message.body),
                signal: controller.signal,
            });
            // The same deadline covers the response body, not just receiving the headers.
            const reason = await response.text();
            return classifyApnsStatus(response.status, reason);
        } catch {
            // Fetch exceptions can contain the device-token URL. Keep diagnostics non-sensitive.
            return { status: "retry", error: controller.signal.aborted ? "apns_timeout" : "apns_network" };
        }
    };
    try { return await Promise.race([work(), timeout]); }
    finally { if (timer !== undefined) clearTimeout(timer); }
}
