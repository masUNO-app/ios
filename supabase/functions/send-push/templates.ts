// Titles and bodies for each kind, in the phone's language. Names are already "First L.".

export type Language = "en" | "es";

export interface NotificationContext {
    title?: string;
    sport?: string;
    sport_en?: string;
    sport_es?: string;
    emoji?: string;
    starts_at?: string;
    place?: string;
    meet_point?: string | null;
    spots_left?: number;
    capacity?: number;
    going_count?: number;
    campus?: string;
    timezone?: string;
    host_name?: string;
    lat?: number;
    lng?: number;
    games?: number;
    sport_games?: number;
}

export interface NotificationPayloadData {
    actor_id?: string;
    joined?: string[];
    left?: string[];
    spots_left?: number;
    capacity?: number;
    going?: number;
    sender_id?: string;
    sender_name?: string;
    sender_initials?: string;
    names?: string[];
    body?: string;
    count?: number;
    message_at?: string;
    others?: { id: string; name: string }[];
    games?: number;
    campus?: string;
    timezone?: string;
    sport?: string;
    sport_en?: string;
    sport_es?: string;
    sport_games?: number;
}

export interface AlertCopy {
    title: string;
    body: string;
}

/** `en-US` and `es-MX` both pick a template. Anything else is English. */
export function languageOf(locale: string | null | undefined): Language {
    return (locale ?? "").toLowerCase().startsWith("es") ? "es" : "en";
}

/** "Maya C. and Sam L." / "Maya C. y Sam L." */
export function joinNames(names: string[] | undefined, language: Language): string {
    const clean = (names ?? []).map((name) => name?.trim()).filter((name): name is string => !!name);
    if (clean.length === 0) return "";
    if (clean.length === 1) return clean[0];
    const conjunction = language === "es" ? "y" : "and";
    if (clean.length === 2) return `${clean[0]} ${conjunction} ${clean[1]}`;
    return `${clean.slice(0, -1).join(", ")} ${conjunction} ${clean[clean.length - 1]}`;
}

/**
 * Campus-local time in the device's 12/24-hour style. Today and tomorrow are words.
 */
export function formatWhen(iso: string | undefined, timeZone: string | undefined, locale: string): string {
    if (!iso) return "";
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return "";
    const zone = timeZone || "UTC";
    const language = locale || "en";
    const dayKey = new Intl.DateTimeFormat("en-CA", {
        timeZone: zone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
    });
    const today = dayKey.format(new Date());
    const tomorrow = dayKey.format(new Date(Date.now() + 24 * 60 * 60 * 1000));
    const gameDay = dayKey.format(date);
    const time = new Intl.DateTimeFormat(language, {
        timeZone: zone,
        hour: "numeric",
        minute: "2-digit",
    }).format(date);
    if (gameDay === today) return language.toLowerCase().startsWith("es") ? `Hoy ${time}` : `Today ${time}`;
    if (gameDay === tomorrow) return language.toLowerCase().startsWith("es") ? `Mañana ${time}` : `Tomorrow ${time}`;
    const weekday = new Intl.DateTimeFormat(language, { timeZone: zone, weekday: "long" }).format(date);
    return `${weekday} ${time}`;
}

function sportLabel(context: NotificationContext, payload: NotificationPayloadData, language: Language): string {
    if (language === "es") return context.sport_es || payload.sport_es || context.sport || payload.sport || "";
    return context.sport_en || payload.sport_en || context.sport || payload.sport || "";
}

function spots(context: NotificationContext, payload: NotificationPayloadData): number {
    return payload.spots_left ?? context.spots_left ?? 0;
}

/**
 * The alert for one kind. Chat with more than one message becomes "3 new messages".
 */
export function renderAlert(
    kind: string,
    locale: string,
    context: NotificationContext,
    payload: NotificationPayloadData,
): AlertCopy {
    const language = languageOf(locale);
    const game = context.title ?? "";
    const when = formatWhen(context.starts_at, context.timezone, locale);
    const place = context.place ?? "";
    const meet = context.meet_point || place;
    const host = context.host_name ?? "";
    const campus = context.campus || payload.campus || "";
    const sport = sportLabel(context, payload, language);
    const room = spots(context, payload);
    const capacity = payload.capacity ?? context.capacity ?? 0;
    const going = payload.going ?? context.going_count ?? capacity;

    if (kind === "chat_message") {
        const count = payload.count ?? 1;
        const names = joinNames(payload.names?.length ? payload.names : [payload.sender_name ?? ""], language);
        if (count > 1) {
            const summary = language === "es" ? `${count} mensajes nuevos` : `${count} new messages`;
            return { title: game, body: names ? `${names} · ${summary}` : summary };
        }
        return { title: game, body: `${payload.sender_name ?? names}: ${payload.body ?? ""}`.trim() };
    }

    if (language === "es") {
        switch (kind) {
            case "game_cancelled":
                return { title: `Se canceló ${game}`, body: `${host} lo canceló. ¿Buscas otro partido?` };
            case "game_changed":
                return { title: `${game} cambió`, body: `Ahora ${when} en ${place}` };
            case "reminder":
                return { title: "Empieza en 30 min", body: `${game} · ${meet}` };
            case "host_update":
                return hostUpdate(language, game, room, payload);
            case "game_full":
                return { title: "Tu partido está lleno", body: `${going} de ${capacity} van a ${game}` };
            case "spot_open":
                return { title: "Se abrió un lugar", body: `${game} · ${when}` };
            case "interest_match":
                return {
                    title: `Nuevo partido de ${sport} en ${campus}`,
                    body: `${game} · ${when} · hay lugar para ${room}`,
                };
            case "signup_approved":
                return { title: "Ya estás dentro", body: "Completa tu perfil y encuentra un partido." };
            case "winback":
                return {
                    title: `${payload.games ?? context.games ?? 0} partidos en ${campus} esta semana`,
                    body: `${payload.sport_games ?? context.sport_games ?? 0} de ${sport}. ¿Hay lugar para uno más?`,
                };
            case "saved_soon":
                return { title: `Aún hay lugar en ${game}`, body: `Empieza en 2 h · hay lugar para ${room}` };
            default:
                return { title: game || "masUNO", body: "" };
        }
    }

    switch (kind) {
        case "game_cancelled":
            return { title: `${game} was cancelled`, body: `${host} cancelled it. Find another game?` };
        case "game_changed":
            return { title: `${game} changed`, body: `Now ${when} at ${place}` };
        case "reminder":
            return { title: "Starts in 30 min", body: `${game} · ${meet}` };
        case "host_update":
            return hostUpdate(language, game, room, payload);
        case "game_full":
            return { title: "Your game is full", body: `${going} of ${capacity} going for ${game}` };
        case "spot_open":
            return { title: "A spot opened", body: `${game} · ${when}` };
        case "interest_match":
            return {
                title: `New ${sport} game at ${campus}`,
                body: `${game} · ${when} · room for ${room}`,
            };
        case "signup_approved":
            return { title: "You're in", body: "Set up your profile and find a game." };
        case "winback":
            return {
                title: `${payload.games ?? context.games ?? 0} games at ${campus} this week`,
                body: `${payload.sport_games ?? context.sport_games ?? 0} ${sport}. Room for one more?`,
            };
        case "saved_soon":
            return { title: `Still room in ${game}`, body: `Starts in 2 h · room for ${room}` };
        default:
            return { title: game || "masUNO", body: "" };
    }
}

function hostUpdate(
    language: Language,
    game: string,
    room: number,
    payload: NotificationPayloadData,
): AlertCopy {
    const joined = payload.joined ?? [];
    const left = payload.left ?? [];
    const names = joinNames(joined.length ? joined : left, language);
    if (language === "es") {
        const verb = joined.length && !left.length
            ? "se unió"
            : !joined.length && left.length
            ? "se fue"
            : "cambió";
        const title = joined.length > 1
            ? `${joinNames(joined, language)} se unieron`
            : left.length > 1 && !joined.length
            ? `${joinNames(left, language)} se fueron`
            : `${names} ${verb}`;
        return { title, body: `${game} · quedan ${room} lugares` };
    }
    const verb = joined.length ? "joined" : "left";
    const title = joined.length && left.length
        ? `${joinNames(joined, language)} joined, ${joinNames(left, language)} left`
        : `${names} ${verb}`;
    return { title, body: `${game} · ${room} spots left` };
}
