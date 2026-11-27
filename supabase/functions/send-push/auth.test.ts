import assert from "node:assert/strict";
import test from "node:test";
import { bearerMatches } from "./auth.ts";

const key = "service-role-key-for-tests";

/** A JWT-shaped token whose payload claims service_role, with no valid signature. */
function forgedServiceRoleToken(): string {
    const encode = (value: object) => btoa(JSON.stringify(value)).replaceAll("=", "");
    return `${encode({ alg: "none" })}.${encode({ role: "service_role" })}.`;
}

test("the service-role key itself is let in", async () => {
    assert.equal(await bearerMatches(`Bearer ${key}`, key), true);
    assert.equal(await bearerMatches(`bearer ${key}`, key), true);
});

test("a token that only claims service_role is refused", async () => {
    assert.equal(await bearerMatches(`Bearer ${forgedServiceRoleToken()}`, key), false);
});

test("a missing, empty or different key is refused", async () => {
    assert.equal(await bearerMatches(null, key), false);
    assert.equal(await bearerMatches("Bearer ", key), false);
    assert.equal(await bearerMatches(key, key), false);
    assert.equal(await bearerMatches(`Bearer ${key}x`, key), false);
    assert.equal(await bearerMatches(`Bearer ${key}`, ""), false);
    assert.equal(await bearerMatches(`Bearer ${key}`, undefined), false);
});
