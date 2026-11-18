import assert from "node:assert/strict";
import test from "node:test";
import { deliverAll, HTTP_CONCURRENCY, type FencedNotification } from "./delivery.ts";

function row(id: number, devices = 1): FencedNotification {
    return {
        id, claim_token: `00000000-0000-4000-8000-${String(id).padStart(12, "0")}`,
        user_id: "test-user", kind: "reminder", event_id: null, payload: {},
        collapse_id: null, expires_at: "2030-01-01T00:00:00Z", context: null,
        tokens: Array.from({ length: devices }, (_, index) => ({
            token: `${id}-${index}`, environment: "sandbox", locale: "en",
        })),
    };
}

test("one HTTP limit applies across notification rows and every device", async () => {
    let active = 0;
    let peak = 0;
    let calls = 0;
    const fetcher: typeof fetch = async () => {
        active += 1;
        calls += 1;
        peak = Math.max(peak, active);
        await new Promise((resolve) => setTimeout(resolve, 2));
        active -= 1;
        return new Response(null, { status: 200 });
    };
    const rows = [row(1, 12), row(2, 12), row(3, 12)];
    const result = await deliverAll(rows, "test-jwt", { fetcher });
    assert.equal(calls, 36);
    assert.equal(peak, HTTP_CONCURRENCY);
    assert.deepEqual(result.map((r) => r.outcome), ["sent", "sent", "sent"]);
    assert.deepEqual(result.map((r) => r.claim_token), rows.map((r) => r.claim_token));
});

test("notifications to the same phone wait for the previous APNs response", async () => {
    const first = row(1);
    const second = { ...row(2), tokens: first.tokens };
    const events: string[] = [];
    const fetcher: typeof fetch = async (_input, init) => {
        const id = JSON.parse(String(init?.body)).outbox_id;
        events.push(`start:${id}`);
        if (id === 1) await new Promise((resolve) => setTimeout(resolve, 10));
        events.push(`finish:${id}`);
        return new Response(null, { status: 200 });
    };
    await deliverAll([first, second], "test-jwt", { fetcher });
    assert.deepEqual(events, ["start:1", "finish:1", "start:2", "finish:2"]);
});

test("a retry holds later alerts for that phone while other phones continue", async () => {
    const first = row(1);
    const second = { ...row(2), tokens: first.tokens };
    const calls: number[] = [];
    const fetcher: typeof fetch = async (_input, init) => {
        const id = JSON.parse(String(init?.body)).outbox_id;
        calls.push(id);
        return new Response(null, { status: id === 1 ? 503 : 200 });
    };
    const result = await deliverAll([first, second, row(3)], "test-jwt", { fetcher });
    assert.deepEqual(calls.sort(), [1, 3]);
    assert.deepEqual(result.map((r) => r.outcome), ["retry", "retry", "sent"]);
    assert.equal(result[1].error, "earlier_notification_pending");
});

test("a hung transport is aborted and bounded even if it never resolves", async () => {
    let aborted = false;
    const fetcher: typeof fetch = async (_input, init) => {
        init?.signal?.addEventListener("abort", () => { aborted = true; });
        return new Promise<Response>(() => {});
    };
    const [result] = await deliverAll([row(1)], "test-jwt", { fetcher, requestTimeoutMs: 5 });
    assert.equal(result.outcome, "retry");
    assert.equal(result.error, "apns_timeout");
    assert.equal(aborted, true);
});

test("the deadline also covers a hung response body", async () => {
    const fetcher: typeof fetch = async () => ({ status: 200, text: () => new Promise<string>(() => {}) }) as Response;
    const [result] = await deliverAll([row(1)], "test-jwt", { fetcher, requestTimeoutMs: 5 });
    assert.equal(result.outcome, "retry");
    assert.equal(result.error, "apns_timeout");
});

test("remaining targets are retried without HTTP after the batch budget expires", async () => {
    let clock = 0;
    let calls = 0;
    const fetcher: typeof fetch = async () => { calls += 1; clock = 30; return new Response(null, { status: 200 }); };
    const result = await deliverAll([row(1), row(2)], "test-jwt", {
        fetcher, concurrency: 1, budgetMs: 25, now: () => clock,
    });
    assert.equal(calls, 1);
    assert.equal(result[0].outcome, "sent");
    assert.equal(result[1].outcome, "retry");
    assert.equal(result[1].error, "delivery_deadline");
});

test("partial-device success retains the at-least-one-device policy and dead-token cleanup", async () => {
    const fetcher: typeof fetch = async (input) => {
        const url = String(input);
        if (url.endsWith("1-0")) return new Response(null, { status: 200 });
        if (url.endsWith("1-1")) return new Response('{"reason":"Unregistered"}', { status: 410 });
        return new Response('{"reason":"TooManyRequests"}', { status: 429 });
    };
    const [result] = await deliverAll([row(1, 3)], "test-jwt", { fetcher });
    assert.equal(result.outcome, "sent");
    assert.deepEqual(result.drop_tokens, ["1-1"]);
});

test("retryable, permanent and missing-device outcomes remain distinct", async () => {
    const fetcher: typeof fetch = async (input) => String(input).endsWith("1-0")
        ? new Response('{"reason":"InternalServerError"}', { status: 503 })
        : new Response('{"reason":"PayloadEmpty"}', { status: 400 });
    const result = await deliverAll([row(1), row(2), row(3, 0)], "test-jwt", { fetcher });
    assert.deepEqual(result.map((r) => r.outcome), ["retry", "drop", "drop"]);
    assert.equal(result[2].error, "no_token");
});

test("transport exception messages cannot leak device-token URLs", async () => {
    const fetcher: typeof fetch = async (input) => { throw new Error(`Failed fetching ${input}`); };
    const [result] = await deliverAll([row(1)], "test-jwt", { fetcher });
    assert.equal(result.error, "apns_network");
    assert.equal(JSON.stringify(result).includes("api.sandbox"), false);
});
