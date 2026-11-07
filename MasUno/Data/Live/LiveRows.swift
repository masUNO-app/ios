import Foundation

// What the backend sends and takes for sign-in and reference data (`docs/API.md`). None of this
// imports Supabase, so `ContractTests` can check it without a server.

/// A row in `university_lookup`.
nonisolated struct UniversityRow: Decodable, Sendable {
    let id: UUID
    let name: String
    let shortName: String
    let emailDomain: String
    let ssoProvider: String?
    let signupEnabled: Bool
    let centerLat: Double
    let centerLng: Double

    enum CodingKeys: String, CodingKey {
        case id, name
        case shortName = "short_name"
        case emailDomain = "email_domain"
        case ssoProvider = "sso_provider"
        case signupEnabled = "signup_enabled"
        case centerLat = "center_lat"
        case centerLng = "center_lng"
    }

    /// `nil` for a provider this build doesn't know: nobody could sign in there with it.
    var university: University? {
        guard let provider = ssoProvider.flatMap(SSOProvider.init(rawValue:)) else { return nil }
        return University(
            id: id, name: name, shortName: shortName, emailDomain: emailDomain,
            centerLatitude: centerLat, centerLongitude: centerLng,
            ssoProvider: provider, signupEnabled: signupEnabled
        )
    }
}

/// A row in `app_config`. Every 0.5 value is a string; anything else is skipped.
nonisolated struct AppConfigRow: Decodable, Sendable {
    let key: String
    let value: String?

    enum CodingKeys: String, CodingKey { case key, value }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        value = try? container.decode(String.self, forKey: .value)
    }
}

extension AppConfig {
    /// The fallback, with whatever the server sent on top.
    init(rows: [AppConfigRow]) {
        self = .fallback
        for row in rows {
            guard let value = row.value else { continue }
            switch row.key {
            case "min_supported_version": minSupportedVersion = value
            case "support_email": supportEmail = value
            case "privacy_url": if let url = URL(string: value) { privacyURL = url }
            default: break
            }
        }
    }
}

/// A row in `activities`.
nonisolated struct ActivityRow: Decodable, Sendable {
    let slug: String
    let kind: String
    let labelEN: String
    let labelES: String
    let emoji: String
    let sortOrder: Int
    let postable: Bool
    let interestSelectable: Bool
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case slug, kind, emoji, postable, active
        case labelEN = "label_en"
        case labelES = "label_es"
        case sortOrder = "sort_order"
        case interestSelectable = "interest_selectable"
    }

    var activity: Activity {
        Activity(
            slug: slug, kind: kind, labelEN: labelEN, labelES: labelES, emoji: emoji, sortOrder: sortOrder,
            postable: postable, interestSelectable: interestSelectable, active: active
        )
    }
}

/// The part of `my_profile` that decides the next step after sign-in. Timestamps stay strings:
/// only whether they're set matters here.
nonisolated struct ProfileStatusRow: Decodable, Sendable {
    let guidelinesAcceptedAt: String?
    let bannedAt: String?

    enum CodingKeys: String, CodingKey {
        case guidelinesAcceptedAt = "guidelines_accepted_at"
        case bannedAt = "banned_at"
    }
}

extension AuthState {
    /// `row` is nil until `complete_profile` has run. A ban comes first, so a banned account
    /// never lands on a step it can't finish.
    init(profile row: ProfileStatusRow?, userID: UUID) {
        guard let row else {
            self = .needsProfile
            return
        }
        if row.bannedAt != nil {
            self = .suspended
        } else if row.guidelinesAcceptedAt == nil {
            self = .needsGuidelines
        } else {
            self = .signedIn(userID: userID)
        }
    }
}

/// The parameters of `complete_profile`.
nonisolated struct CompleteProfileParams: Encodable, Sendable {
    let firstName: String
    let lastName: String
    let gradYear: Int
    let interests: [String]
    let locale: String

    enum CodingKeys: String, CodingKey {
        case firstName = "p_first_name"
        case lastName = "p_last_name"
        case gradYear = "p_grad_year"
        case interests = "p_interests"
        case locale = "p_locale"
    }

    init(_ input: ProfileInput) {
        firstName = input.firstName
        lastName = input.lastName
        gradYear = input.gradYear
        interests = input.interests.map(\.slug)
        locale = input.locale
    }
}

/// What a failed school sign-in sends back in the callback URL (`docs/API.md`, Auth errors).
nonisolated struct SignInFailure: Hashable, Sendable {
    var error: String?
    var code: String?
    var message: String?

    var domainError: DomainError {
        let parts = [error, code, message].compactMap { $0?.lowercased() }
        if parts.contains(where: { $0.contains("email_not_allowed") }) { return .emailNotAllowed }
        // Entra's "needs admin approval" errors, and the way back out of its approval page.
        let consent = ["access_denied", "consent_required", "aadsts65001", "aadsts90094"]
        if parts.contains(where: { part in consent.contains { part.contains($0) } }) { return .schoolApprovalNeeded }
        return .signInFailed
    }
}
