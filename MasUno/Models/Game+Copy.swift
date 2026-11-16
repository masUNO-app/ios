import Foundation

/// Status and host lines in the 1.0 voice (SPEC §7.7.5): "Room for N more", not "N spots left".
extension Game {
    /// "Basketball · Hosted by Alex R." / "Basketball · Hosted by you". Just "Basketball" for a
    /// guest, who isn't shown the host.
    var hostLine: String {
        if hidesPeople { return activity.name }
        let host = isHostedByMe ? String(localized: "you") : host.displayName
        return String(localized: "\(activity.name) · Hosted by \(host)")
    }

    /// "Room for 4 more", "Room for one more", "Full".
    var roomLine: String {
        if isFull { return String(localized: "Full") }
        return spotsLeft == 1 ? String(localized: "Room for one more") : String(localized: "Room for \(spotsLeft) more")
    }

    /// The same, for the middle of a line: "room for 4 more", "room for one more", "game is full".
    var roomPhrase: String {
        if isFull { return String(localized: "game is full") }
        return spotsLeft == 1 ? String(localized: "room for one more") : String(localized: "room for \(spotsLeft) more")
    }

    /// The popup and Saved: "Room for 4 more", or "A spot just opened · room for 1" after a repost.
    func discoverLine(now: Date = .now) -> String {
        guard isBumped(now: now), !isFull else { return roomLine }
        return String(localized: "A spot just opened · room for \(spotsLeft)")
    }

    /// Me › Going: "You're in · room for 3 more".
    var goingLine: String {
        String(localized: "You're in · \(roomPhrase)")
    }

    /// Me › Hosting: "3 joined · room for 6 more". The host isn't counted as having joined.
    var hostingLine: String {
        String(localized: "\(joinedCount) joined · \(roomPhrase)")
    }

    /// Everyone going except the host.
    var joinedCount: Int { max(goingCount - 1, 0) }

    /// Me › Going, cancelled: "Cancelled by Alex". A guest isn't shown who cancelled.
    var cancelledLine: String {
        if isHostedByMe { return String(localized: "You cancelled this game") }
        return hidesPeople ? String(localized: "This game was cancelled.") : String(localized: "Cancelled by \(host.firstName)")
    }

    /// Me › Earlier: "You played · 10 showed up".
    var playedLine: String {
        String(localized: "You played · \(goingCount) showed up")
    }

    /// Game details, full: "Game's full · 6 of 6".
    var fullLine: String {
        String(localized: "Game's full · \(goingCount) of \(capacity)")
    }
}

extension Place {
    /// "Av. Luis Elizondo", the part of the address before the city.
    var street: String {
        String(address.split(separator: ",").first ?? Substring(address))
    }

    /// "Tecnológico, Monterrey, N.L.", what follows the street. Empty when the address is one part.
    var locality: String {
        address.split(separator: ",").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")
    }

    /// "Estadio Borregos · Av. Luis Elizondo", or just the street when the place is an address.
    var titleLine: String {
        name == street ? street : "\(name) · \(street)"
    }
}

extension ProfileInput {
    /// "Emilio G.", for the "Others see…" line.
    static func previewName(first: String, last: String) -> String {
        let first = first.trimmingCharacters(in: .whitespaces)
        guard let initial = last.trimmingCharacters(in: .whitespaces).first else { return first }
        return "\(first) \(initial.uppercased())."
    }
}
