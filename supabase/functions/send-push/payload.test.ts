import assert from "node:assert/strict";
import test from "node:test";
import { buildPush, classifyApnsStatus, mapPool } from "./payload.ts";
import { languageOf, renderAlert } from "./templates.ts";
import { importApnsKey, signApnsJwt } from "./jwt.ts";

const game = {
    title: "Sunday pickup soccer",
    sport: "soccer",
    sport_en: "Soccer",
    sport_es: "Fútbol",
    starts_at: "2026-11-15T19:30:00-06:00",
    place: "Estadio Borregos",
    meet_point: "North bleachers",
    spots_left: 4,
    capacity: 10,
    going_count: 6,
    campus: "Tec",
    timezone: "America/Monterrey",
    host_name: "Sam L.",
    lat: 25.65,
    lng: -100.29,
};

test("language follows the phone", () => {
    assert.equal(languageOf("es-MX"), "es");
    assert.equal(languageOf("en-US"), "en");
    assert.equal(languageOf("fr"), "en");
});

test("english and spanish templates name the game", () => {
    const cancelled = renderAlert("game_cancelled", "en-US", game, {});
    assert.equal(cancelled.title, "Sunday pickup soccer was cancelled");
    assert.equal(cancelled.body, "Sam L. cancelled it. Find another game?");
    const spanish = renderAlert("game_cancelled", "es-MX", game, {});
    assert.equal(spanish.title, "Se canceló Sunday pickup soccer");
    assert.match(spanish.body, /Sam L\./);

    const full = renderAlert("game_full", "en", game, { going: 10, capacity: 10 });
    assert.equal(full.title, "Your game is full");
    assert.equal(full.body, "10 of 10 going for Sunday pickup soccer");

    const approved = renderAlert("signup_approved", "es", {}, {});
    assert.equal(approved.title, "Ya estás dentro");
});

test("merged chat names the senders and the count", () => {
    const alert = renderAlert("chat_message", "en-US", game, {
        names: ["Maya C.", "Sam L."],
        count: 3,
        body: "I'll bring the ball",
        sender_name: "Sam L.",
    });
    assert.equal(alert.title, "Sunday pickup soccer");
    assert.equal(alert.body, "Maya C. and Sam L. · 3 new messages");
    const one = renderAlert("chat_message", "es-MX", game, {
        names: ["Maya C."],
        count: 1,
        body: "Llevo el balón",
        sender_name: "Maya C.",
    });
    assert.equal(one.body, "Maya C.: Llevo el balón");
});

test("a spot alert is time-sensitive and carries the game", () => {
    const message = buildPush({
        id: 4812,
        user_id: "user",
        kind: "spot_open",
        event_id: "6f1c",
        payload: {},
        collapse_id: "game:6f1c",
        expires_at: "2026-11-15T20:00:00-06:00",
        tokens: [],
        context: game,
    }, { token: "abc", environment: "sandbox", locale: "en-US" });
    const aps = message.body.aps as { alert: { title: string }; category: string; "interruption-level": string };
    assert.equal(aps.alert.title, "A spot opened");
    assert.equal(aps.category, "SPOT_OPEN");
    assert.equal(aps["interruption-level"], "time-sensitive");
    assert.equal(message.headers["apns-priority"], "10");
    assert.equal(message.headers["apns-topic"], "com.masuno.app");
    assert.equal(message.headers["apns-collapse-id"], "game:6f1c");
    assert.equal(message.body.kind, "spot_open");
    assert.equal(message.body.game_id, "6f1c");
    assert.equal(message.body.outbox_id, 4812);
});

test("chat asks the extension to redraw it and a passive kind is quiet", () => {
    const chat = buildPush({
        id: 9,
        user_id: "user",
        kind: "chat_message",
        event_id: "game-1",
        payload: {
            sender_id: "a21b",
            sender_name: "Maya C.",
            sender_initials: "MC",
            names: ["Maya C."],
            body: "I'll bring the ball",
            count: 1,
            others: [{ id: "c9d0", name: "Sam L." }, { id: "e44f", name: "Nina P." }, { id: "extra", name: "No" }],
        },
        collapse_id: "chat:game-1",
        expires_at: "2026-11-16T19:30:00-06:00",
        tokens: [],
        context: game,
    }, { token: "abc", environment: "production", locale: "en-US" });
    const aps = chat.body.aps as { "mutable-content": number; category: string };
    assert.equal(aps["mutable-content"], 1);
    assert.equal(aps.category, "CHAT");
    assert.equal((chat.body.others as unknown[]).length, 2);
    assert.equal(chat.body.body, "I'll bring the ball");

    const winback = buildPush({
        id: 3,
        user_id: "user",
        kind: "winback",
        event_id: null,
        payload: { games: 4, campus: "Tec", sport_en: "basketball", sport_games: 2, timezone: "America/Monterrey" },
        collapse_id: null,
        expires_at: "2026-11-16T00:00:00Z",
        tokens: [],
        context: { games: 4, campus: "Tec", sport_en: "basketball", sport_games: 2, timezone: "America/Monterrey" },
    }, { token: "abc", environment: "production", locale: "en-US" });
    assert.equal(winback.headers["apns-priority"], "5");
    assert.equal((winback.body.aps as { "interruption-level": string })["interruption-level"], "passive");
    assert.equal((winback.body.aps as { alert: { title: string } }).alert.title, "4 games at Tec this week");
});

test("a long chat stays under the APNs limit", () => {
    const long = "🙂".repeat(1000);
    const chat = buildPush({
        id: 9,
        user_id: "user",
        kind: "chat_message",
        event_id: "game-1",
        payload: {
            sender_id: "a21b",
            sender_name: "Maya C.",
            sender_initials: "MC",
            names: ["Maya C."],
            body: long,
            count: 1,
        },
        collapse_id: "chat:game-1",
        expires_at: "2026-11-16T19:30:00-06:00",
        tokens: [],
        context: game,
    }, { token: "abc", environment: "production", locale: "en-US" });
    const bytes = Buffer.byteLength(JSON.stringify(chat.body));
    assert.ok(bytes <= 4096, `payload is ${bytes} bytes`);
    assert.ok(String(chat.body.body).length < long.length);
});

test("a bad payload is permanent and a network status is not", () => {
    assert.equal(classifyApnsStatus(413, "PayloadTooLarge").status, "drop");
    assert.equal(classifyApnsStatus(400, "BadCollapseId").status, "drop");
    assert.equal(classifyApnsStatus(410, "Unregistered").status, "dead");
    assert.equal(classifyApnsStatus(429, "TooManyRequests").status, "retry");
    assert.equal(classifyApnsStatus(500, "Internal").status, "retry");
});

test("sends stay in order with only a few in flight", async () => {
    let inFlight = 0;
    let peak = 0;
    const results = await mapPool([1, 2, 3, 4, 5, 6], 2, async (item) => {
        inFlight += 1;
        peak = Math.max(peak, inFlight);
        await new Promise((resolve) => setTimeout(resolve, 15));
        inFlight -= 1;
        return item * 10;
    });
    assert.deepEqual(results, [10, 20, 30, 40, 50, 60]);
    assert.equal(peak, 2);
    assert.deepEqual(await mapPool([], 8, async (item: number) => item), []);
});

test("an ES256 provider token verifies", async () => {
    const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
    const pkcs8 = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
    const pem = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(pkcs8).toString("base64")}\n-----END PRIVATE KEY-----\n`;
    const key = await importApnsKey(pem);
    const jwt = await signApnsJwt(key, "KEYID", "TEAMID", 1_700_000_000);
    const [header, payload, signature] = jwt.split(".");
    assert.equal(JSON.parse(Buffer.from(header, "base64url").toString()).kid, "KEYID");
    assert.equal(JSON.parse(Buffer.from(payload, "base64url").toString()).iss, "TEAMID");
    const raw = Buffer.from(signature, "base64url");
    const verified = await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" },
        pair.publicKey,
        raw,
        new TextEncoder().encode(`${header}.${payload}`),
    );
    assert.equal(verified, true);
});


test("host summaries use each participant's latest action despite stale legacy arrays", () => {
    const payload = {
        joined: ["Ricardo G.", "Ari P.", "Ari P."], left: ["Ari P."], spots_left: 9,
        roster_changes: {
            ricardo: { name: "Ricardo G.", action: "joined" as const },
            ari: { name: "Ari P.", action: "left" as const },
        },
    };
    const alert = renderAlert("host_update", "en", { ...game, spots_left: 3 }, payload);
    assert.equal(alert.title, "Ricardo G. joined, Ari P. left");
    assert.equal(alert.body, "Sunday pickup soccer · 3 spots left");
    const rejoined = { ...payload, roster_changes: { ...payload.roster_changes,
        ari: { name: "Ari P.", action: "joined" as const },
    } };
    assert.equal(renderAlert("host_update", "en", game, rejoined).title, "Ricardo G. and Ari P. joined");
});

test("host summaries preserve distinct participants sharing a name", () => {
    const payload = { roster_changes: {
        first: { name: "Ari P.", action: "joined" as const },
        second: { name: "Ari P.", action: "left" as const },
    } };
    assert.equal(renderAlert("host_update", "en", game, payload).title, "Ari P. joined, Ari P. left");
});

test("Spanish host summaries name both joins and departures", () => {
    assert.equal(renderAlert("host_update", "es", game, {
        roster_changes: {
            first: { name: "Ricardo G.", action: "joined" },
            second: { name: "Ari P.", action: "left" },
        },
    }).title, "Ricardo G. se unió, Ari P. se fue");
});

test("legacy host summaries deduplicate repeated labels", () => {
    assert.equal(renderAlert("host_update", "en", game, {
        joined: ["Ari P.", "Ari P."], left: [],
    }).title, "Ari P. joined");
});
