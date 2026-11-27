// Who may drain the outbox: only a caller holding this project's service-role key.

const textEncoder = new TextEncoder();

/**
 * Whether `authorization` is `Bearer <expected>`. The gateway's `verify_jwt` checks the signature,
 * but this must hold without it, so the token is compared to the key itself rather than decoded.
 * SHA-256 digests are compared, so how long the comparison takes says nothing about the key.
 *
 * - Parameters:
 *   - authorization: the request's `Authorization` header, or null.
 *   - expected: the function's `SUPABASE_SERVICE_ROLE_KEY`.
 * - Returns: true only for an exact match with a non-empty key.
 */
export async function bearerMatches(authorization: string | null, expected: string | undefined): Promise<boolean> {
    const match = /^Bearer\s+(\S+)$/i.exec(authorization ?? "");
    if (!match || !expected) return false;
    const [given, wanted] = await Promise.all([digest(match[1]), digest(expected)]);
    let difference = 0;
    for (let index = 0; index < given.length; index += 1) difference |= given[index] ^ wanted[index];
    return difference === 0;
}

async function digest(text: string): Promise<Uint8Array> {
    return new Uint8Array(await crypto.subtle.digest("SHA-256", textEncoder.encode(text)));
}
