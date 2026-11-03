import Foundation

/// Client-side copy of the server's text filter (SPEC §7.6.6): game names, notes,
/// meet-up spots and names. The server (B3) has the full English + Spanish list and
/// is the real check; this catches the obvious cases before a round trip.
enum TextFilter {
    static let message = String(localized: "Please keep it friendly — try different wording.")

    /// Whole-word matches only, ignoring case and accents.
    private static let blockedWords: Set<String> = [
        // English
        "fuck", "fucking", "shit", "bitch", "asshole", "cunt", "dick", "fag", "faggot", "nigger", "retard", "slut", "whore",
        // Spanish
        "puta", "puto", "pendejo", "pendeja", "cabron", "cabrona", "chinga", "chingada", "verga", "joto", "marica", "culero", "pinche",
    ]

    static func isFriendly(_ text: String) -> Bool {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = folded.split { !$0.isLetter }.map(String.init)
        return !words.contains(where: blockedWords.contains)
    }
}
