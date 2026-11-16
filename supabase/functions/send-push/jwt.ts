// APNs token auth: an ES256 JWT, reused until it is 50 minutes old.

const textEncoder = new TextEncoder();

/** PKCS#8 PEM from the `APNS_KEY_P8` secret, including a key stored with literal `\n`. */
export function pemToDer(pem: string): Uint8Array {
    const body = pem.replace(/-----BEGIN [^-]+-----/g, "").replace(/-----END [^-]+-----/g, "").replace(/\\n/g, "").replace(/\s/g, "");
    const binary = atob(body);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
    return bytes;
}

export async function importApnsKey(pem: string): Promise<CryptoKey> {
    return crypto.subtle.importKey(
        "pkcs8",
        pemToDer(pem) as BufferSource,
        { name: "ECDSA", namedCurve: "P-256" },
        false,
        ["sign"],
    );
}

function base64url(bytes: Uint8Array): string {
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

/**
 * A provider token. `iat` is now. Apple rejects a new token more than once every 20 minutes,
 * so the caller stores this and only signs again after 50 minutes.
 */
export async function signApnsJwt(key: CryptoKey, keyID: string, teamID: string, issuedAt = Math.floor(Date.now() / 1000)): Promise<string> {
    const header = base64url(textEncoder.encode(JSON.stringify({ alg: "ES256", kid: keyID })));
    const payload = base64url(textEncoder.encode(JSON.stringify({ iss: teamID, iat: issuedAt })));
    const signingInput = `${header}.${payload}`;
    const signature = new Uint8Array(await crypto.subtle.sign(
        { name: "ECDSA", hash: "SHA-256" },
        key,
        textEncoder.encode(signingInput),
    ));
    return `${signingInput}.${base64url(signature)}`;
}
