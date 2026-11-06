import Foundation

/// Status and host lines (SPEC §7.2).
extension Game {
    /// "Basketball · Hosted by Alex R." / "Basketball · Hosted by you".
    var hostLine: String {
        let host = isHostedByMe ? String(localized: "you") : host.displayName
        return String(localized: "\(activity.name) · Hosted by \(host)")
    }

    /// "4 spots left", "1 spot left", "Full".
    var spotsLine: String {
        if isFull { return String(localized: "Full") }
        return spotsLeft == 1 ? String(localized: "1 spot left") : String(localized: "\(spotsLeft) spots left")
    }

    /// "Open · 4 spots left" / "Full".
    var openLine: String {
        isFull ? spotsLine : String(localized: "Open · \(spotsLine)")
    }

    /// "3 going · 3 spots left", "3 going · 1 spot left", "Full".
    var statusLine: String {
        isFull ? spotsLine : String(localized: "\(goingCount) going · \(spotsLine)")
    }
}

extension Place {
    /// "Av. Luis Elizondo", the part of the address before the city.
    var street: String {
        String(address.split(separator: ",").first ?? Substring(address))
    }

    /// "Estadio Borregos · Av. Luis Elizondo", or just the street when the place is an address.
    var titleLine: String {
        name == street ? street : "\(name) · \(street)"
    }
}

extension ProfileInput {
    /// "Emilio G.", for the "This is how others see you" preview.
    static func previewName(first: String, last: String) -> String {
        let first = first.trimmingCharacters(in: .whitespaces)
        guard let initial = last.trimmingCharacters(in: .whitespaces).first else { return first }
        return "\(first) \(initial.uppercased())."
    }
}
