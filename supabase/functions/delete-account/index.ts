import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * Deletes only the caller. The service-role client is never exposed to iOS.
 * `delete_my_account_data` frees the caller's spots in upcoming games under
 * row locks; deleting the Auth user then cascades the profile, hosted games,
 * RSVPs and blocks, and keeps reports without the reporter.
 */
Deno.serve(async (request) => {
    if (request.method !== "POST") {
        return new Response("Method Not Allowed", { status: 405 });
    }

    const authorization = request.headers.get("Authorization");
    if (!authorization) {
        return new Response("Unauthorized", { status: 401 });
    }

    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceRoleKey) {
        console.error("Missing Supabase function secrets.");
        return new Response("Server misconfigured", { status: 500 });
    }

    const caller = createClient(url, anonKey, {
        global: { headers: { Authorization: authorization } },
    });
    const { data: { user }, error: userError } = await caller.auth.getUser();
    if (userError || !user) {
        return new Response("Unauthorized", { status: 401 });
    }

    // The transaction lives in SQL to ensure no partially-deleted account can leak.
    const admin = createClient(url, serviceRoleKey);
    const { error: cleanupError } = await admin.rpc("delete_my_account_data", {
        p_user_id: user.id,
    });
    if (cleanupError) {
        console.error("Account cleanup failed", cleanupError);
        return new Response("Could not delete account", { status: 500 });
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
    if (deleteError) {
        console.error("Auth user deletion failed", deleteError);
        return new Response("Could not delete account", { status: 500 });
    }
    return new Response(null, { status: 204 });
});
