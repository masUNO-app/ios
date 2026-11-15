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
    return { headers, body };
}

function expiration(iso: string): number {
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return 0;
    return Math.max(0, Math.floor(date.getTime() / 1000));
}

export function hostFor(environment: string): string {
    return environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
}
