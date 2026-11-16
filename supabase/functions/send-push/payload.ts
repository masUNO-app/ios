// The JSON APNs receives. One object per device, in that device's language.

import { type NotificationContext, type NotificationPayloadData, renderAlert } from "./templates.ts";

export interface DeviceToken {
    token: string;
    environment: "sandbox" | "production" | string;
    locale: string;
}

export interface ClaimedNotification {
    id: number;
    user_id: string;
    kind: string;
    event_id: string | null;
    payload: NotificationPayloadData;
    collapse_id: string | null;
    expires_at: string;
    tokens: DeviceToken[];
    context: NotificationContext | null;
}

const TIME_SENSITIVE = new Set(["game_cancelled", "reminder", "spot_open"]);
const PASSIVE = new Set(["interest_match", "winback", "saved_soon"]);

export function interruptionLevel(kind: string): "time-sensitive" | "passive" | "active" {
    if (TIME_SENSITIVE.has(kind)) return "time-sensitive";
    if (PASSIVE.has(kind)) return "passive";
    return "active";
}

export function apnsPriority(kind: string): "5" | "10" {
    return PASSIVE.has(kind) ? "5" : "10";
}

export function category(kind: string): string | undefined {
    switch (kind) {
        case "spot_open":
            return "SPOT_OPEN";
        case "interest_match":
            return "INTEREST";
        case "saved_soon":
            return "SAVED_SOON";
        case "reminder":
            return "REMINDER";
        case "chat_message":
            return "CHAT";
        default:
            return undefined;
    }
}

export function threadID(kind: string, eventID: string | null): string | undefined {
    if (!eventID) return undefined;
    return kind === "chat_message" ? `chat:${eventID}` : `game:${eventID}`;
}

/**
 * The body Apple delivers. Chat keeps the sender and the game so the extension can redraw it.
 * Returns null when there is nothing to say.
 */
export function buildPush(
    row: ClaimedNotification,
    token: DeviceToken,
): { headers: Record<string, string>; body: Record<string, unknown> } {
    const context = row.context ?? {};
    const data = row.payload ?? {};
    const alert = renderAlert(row.kind, token.locale, context, data);
    const thread = threadID(row.kind, row.event_id);
    const group = category(row.kind);
    const aps: Record<string, unknown> = {
        alert: { title: alert.title, body: alert.body },
        sound: "default",
        "interruption-level": interruptionLevel(row.kind),
        "relevance-score": TIME_SENSITIVE.has(row.kind) ? 0.9 : PASSIVE.has(row.kind) ? 0.3 : 0.6,
    };
    if (thread) {
        aps["thread-id"] = thread;
        aps["target-content-id"] = thread;
    }
    if (group) aps.category = group;
    if (row.kind === "chat_message") aps["mutable-content"] = 1;

    const body: Record<string, unknown> = {
        aps,
        kind: row.kind,
        outbox_id: row.id,
    };
    if (row.event_id) body.game_id = row.event_id;
    if (typeof context.lat === "number" && typeof context.lng === "number") {
        body.place = { name: context.place ?? "", lat: context.lat, lng: context.lng };
    }
    if (row.kind === "chat_message") {
        const count = data.count ?? 1;
        body.game = { title: context.title ?? "", sport: context.sport ?? "" };
        body.sender = {
            id: data.sender_id ?? data.actor_id ?? "",
            name: data.sender_name ?? "",
            initials: data.sender_initials ?? "",
        };
        body.others = (data.others ?? []).slice(0, 2);
        body.body = count > 1 ? alert.body : (data.body ?? "");
        body.count = count;
    }

    const headers: Record<string, string> = {
        "apns-topic": "com.masuno.app",
        "apns-push-type": "alert",
        "apns-priority": apnsPriority(row.kind),
        "apns-expiration": String(expiration(row.expires_at)),
    };
    if (row.collapse_id) headers["apns-collapse-id"] = row.collapse_id;
    return { headers, body: fitPushBody(body) };
}

/** APNs refuses a body over 4 KB. Chat repeats the text in the alert and in `body`, so shrink both. */
export function fitPushBody(body: Record<string, unknown>, limit = 4096): Record<string, unknown> {
    let guard = 0;
    while (utf8Length(JSON.stringify(body)) > limit && guard < 200) {
        if (!shrinkLongestText(body)) break;
        guard += 1;
    }
    return body;
}

/**
 * What one APNs response means. 400 and 413 will not succeed on a retry.
 * A dead token is separate from a payload we should stop sending.
 */
export function classifyApnsStatus(
    status: number,
    reason: string,
): { status: "sent" | "dead" | "retry" | "drop"; error?: string } {
    if (status === 200) return { status: "sent" };
    const error = `${status} ${reason}`.trim().slice(0, 200);
    if (status === 410 || reason.includes("BadDeviceToken") || reason.includes("Unregistered")) {
        return { status: "dead", error };
    }
    if (status === 400 || status === 413) return { status: "drop", error };
    return { status: "retry", error };
}

function shrinkLongestText(body: Record<string, unknown>): boolean {
    const aps = body.aps as { alert?: { title?: string; body?: string } } | undefined;
    const message = typeof body.body === "string" ? body.body : "";
    const alertBody = aps?.alert?.body ?? "";
    if (utf8Length(message) >= utf8Length(alertBody) && message.length > 0) {
        body.body = truncateUTF8(message, Math.max(0, utf8Length(message) - 48));
        return body.body !== message;
    }
    if (aps?.alert && alertBody.length > 0) {
        const shorter = truncateUTF8(alertBody, Math.max(0, utf8Length(alertBody) - 48));
        if (shorter === alertBody) return false;
        aps.alert = { ...aps.alert, body: shorter };
        return true;
    }
    return false;
}

function utf8Length(value: string): number {
    return new TextEncoder().encode(value).length;
}

function truncateUTF8(value: string, maxBytes: number): string {
    const encoded = new TextEncoder().encode(value);
    if (encoded.byteLength <= maxBytes) return value;
    const ellipsis = new TextEncoder().encode("…");
    let budget = Math.max(0, maxBytes - ellipsis.byteLength);
    while (budget > 0 && (encoded[budget] & 0xc0) === 0x80) budget -= 1;
    const text = new TextDecoder().decode(encoded.subarray(0, budget));
    return maxBytes >= ellipsis.byteLength ? text + "…" : text;
}

function expiration(iso: string): number {
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return 0;
    return Math.max(0, Math.floor(date.getTime() / 1000));
}

export function hostFor(environment: string): string {
    return environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
}

/// Runs `work` over `items` with at most `limit` calls in flight, and keeps result order.
export async function mapPool<T, R>(
    items: readonly T[],
    limit: number,
    work: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
    const results = new Array<R>(items.length);
    if (items.length === 0) return results;
    let next = 0;
    const workers = Math.min(Math.max(1, limit), items.length);
    await Promise.all(Array.from({ length: workers }, async () => {
        while (next < items.length) {
            const index = next;
            next += 1;
            results[index] = await work(items[index]!, index);
        }
    }));
    return results;
}
