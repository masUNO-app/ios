import CoreLocation
import Foundation

/// Where a game happens (`place_name`, `place_address`, `lat`, `lng`).
/// The meet-up spot is separate: `Game.meetPoint`.
nonisolated struct Place: Hashable, Sendable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

nonisolated extension Place {
    /// The address without the lines that repeat the place's name: MapKit's full address for a
    /// point of interest starts with its name ("Monterrey Institute of Technology…, Av. Eugenio
    /// Garza Sada 2501 Sur, …"), and a dropped pin's name is the street that starts its address.
    static func address(_ full: String, without name: String) -> String {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return full }
        var rest = Substring(full).drop { $0 == " " }
        // Only a whole leading part, followed by a comma: "Tec Stadium Annex" keeps its "Tec Stadium".
        while let match = rest.range(of: name, options: [.anchored, .caseInsensitive, .diacriticInsensitive]),
              rest[match.upperBound...].first == "," {
            rest = rest[rest.index(after: match.upperBound)...].drop { $0 == " " }
        }
        return rest.isEmpty ? full : String(rest)
    }
}
