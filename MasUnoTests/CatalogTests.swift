import Foundation
import Testing
import UIKit
@testable import masUNO

/// The server-driven activity catalog: `activity_catalog` decoding, fallbacks for what a build doesn't
/// know, the on-phone cache, and the round-night rows (`game_cards` columns, `game_rotation`).
@MainActor
struct CatalogTests {
    private func decode<Row: Decodable>(_ json: String) throws -> Row {
        try JSONDecoder().decode(Row.self, from: Data(json.utf8))
    }

    /// An `activity_catalog` response the way Postgres writes it, with a kind and a drawing this build
    /// has never heard of.
    private let response = """
    {"kinds":[
      {"slug":"sport","label_en":"Sports","label_es":"Deportes","item_label_en":"Sport","item_label_es":"Deporte",
       "title_placeholder_en":"e.g. Pickup after class","title_placeholder_es":"p. ej., Cascarita después de clase",
       "gear_en":"I have an extra ball","gear_es":"Tengo un balón extra","default_art":"generic",
       "supports_rotation":false,"min_app_version":"0.5","sort_order":1,"active":true},
      {"slug":"hackathon","label_en":"Hackathons","label_es":"Hackatones","item_label_en":"Event","item_label_es":"Evento",
       "title_placeholder_en":"e.g. Weekend build","title_placeholder_es":"p. ej., Build de fin de semana",
       "gear_en":null,"gear_es":null,"default_art":"whiteboard",
       "supports_rotation":false,"min_app_version":"1.0","sort_order":3,"active":true}],
     "activities":[
      {"slug":"basketball","kind":"sport","label_en":"Basketball","label_es":"Básquetbol","emoji":"🏀","sort_order":1,
       "postable":true,"interest_selectable":true,"active":true,"color":"#F2853A","color_dark":null,"art":"basketball",
       "min_app_version":"0.5"},
      {"slug":"ultimate","kind":"sport","label_en":"Ultimate Frisbee","label_es":"Ultimate Frisbee","emoji":"🥏",
       "sort_order":6,"postable":true,"interest_selectable":true,"active":true,"color":"#E36F8B","color_dark":"#A84B63",
       "art":null,"min_app_version":"0.5"},
      {"slug":"hack_week","kind":"hackathon","label_en":"Hack week","label_es":"Semana de hackeo","emoji":"💻",
       "sort_order":300,"postable":true,"interest_selectable":false,"active":true,"color":null,"color_dark":null,
       "art":null,"min_app_version":"1.0"}]}
    """

    @Test func catalogResponseDecodes() throws {
        let catalog = try (decode(response) as CatalogResponse).catalog(fetchedAt: .now)
        #expect(catalog.kinds.map(\.slug) == ["sport", "hackathon"])
        #expect(catalog.kind("hackathon").gearLine == nil)
        #expect(catalog.kind("hackathon").itemName == "Event")

        let ultimate = try #require(catalog.activity(slug: "ultimate"))
        #expect(ultimate.colorHex == "#E36F8B")
        #expect(ultimate.colorDarkHex == "#A84B63")
        // No drawing of its own: the kind's, and "generic" is one this build has.
        #expect(ultimate.art == "generic")
        #expect(ultimate.court == .generic)

        // A drawing this build doesn't have falls back to the plain court.
        let hack = try #require(catalog.activity(slug: "hack_week"))
        #expect(hack.art == "whiteboard")
        #expect(hack.court == .generic)
    }

    @Test func aKindTheBuildDoesNotKnowStillHasAName() {
        let kind = Catalog.builtIn.kind("board_games")
        #expect(kind.labelEN == "Board Games")
        #expect(!kind.supportsRotation)
        #expect(kind.gearLine == nil)
    }

    @Test func catalogColorsWinOverAssetColors() {
        var basketball = Activity.builtIn[0]
        basketball.colorHex = "#000000"
        let resolved = UIColor(basketball.color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 1
        resolved.getRed(&red, green: nil, blue: nil, alpha: nil)
        #expect(red < 0.01)
    }

    /// The hex in `Activity.builtIn` and `Activity.esports` (and the migration that seeds the same
    /// values) is what the asset colorsets draw, so nothing changes color when the server takes over.
    @Test(arguments: [
        ("basketball", "SportBasketball"), ("tennis", "SportTennis"), ("soccer", "SportSoccer"),
        ("volleyball", "SportVolleyball"), ("padel", "SportPadel"), ("valorant", "EsportsValorant"),
        ("csgo", "EsportsCSGO"), ("league", "EsportsLeague"),
    ])
    func builtInHexMatchesTheColorsets(slug: String, asset: String) throws {
        let activity = try #require((Activity.builtIn + Activity.esports).first { $0.slug == slug })
        let hex = try #require(AvatarPalette.rgb(hex: activity.colorHex))
        let colorset = try #require(UIColor(named: asset, in: Bundle(for: GameStore.self), compatibleWith: nil))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        colorset.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&red, green: &green, blue: &blue, alpha: nil)
        #expect(abs(red - hex.red) < 0.003 && abs(green - hex.green) < 0.003 && abs(blue - hex.blue) < 0.003)
    }

    @Test func builtInKindsMatchTheFormCopy() {
        #expect(ActivityKind.builtIn.map(\.slug) == [Activity.sportKind, Activity.esportsKind])
        #expect(ActivityKind.sport.gearEN == "I have an extra ball")
        #expect(ActivityKind.esports.supportsRotation)
        #expect(!ActivityKind.sport.supportsRotation)
    }

    // MARK: Cache

    @Test func cacheRoundTripsAndStartsTheCatalog() async throws {
        let cache = CatalogCache.memory()
        let served = try (decode(response) as CatalogResponse).catalog(fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let first = ActivityCatalog(cache: cache) { served }
        #expect(first.catalog == .builtIn)
        await first.loadIfNeeded()
        #expect(cache.load() == served)

        // The next launch starts from the cache, before any fetch, and offline keeps it.
        let next = ActivityCatalog(cache: cache) { throw DomainError.offline }
        #expect(next.activity(slug: "ultimate").labelEN == "Ultimate Frisbee")
        await next.loadIfNeeded()
        #expect(next.catalog == served)
    }

    @Test func aBrokenCacheFallsBackToBuiltIn() {
        let cache = CatalogCache.memory()
        cache.write(Data("not json".utf8))
        #expect(cache.load() == nil)
        #expect(ActivityCatalog(cache: cache) { .builtIn }.catalog == .builtIn)

        // An empty catalog is never kept.
        cache.save(Catalog(kinds: [], activities: []))
        #expect(cache.load() == nil)
    }

    @Test func theNotificationExtensionReadsTheCachedBadge() throws {
        let saved = AppGroupStore.catalogData
        defer { AppGroupStore.catalogData = saved }
        CatalogCache.appGroup.save(try (decode(response) as CatalogResponse).catalog(fetchedAt: .now))
        let badge = try #require(CatalogBadges.badge(for: "ultimate"))
        #expect(badge.emoji == "🥏")
        #expect(badge.color == "#E36F8B")
        #expect(CatalogBadges.badge(for: "chess") == nil)
    }

    @Test func pushGameInfoDecodesItsLook() throws {
        let info: NotificationPayload.GameInfo = try decode("""
        {"title":"Valorant night","sport":"valorant","emoji":"🎯","color":"#F06F7E"}
        """)
        #expect(info.emoji == "🎯")
        #expect(info.color == "#F06F7E")
        #expect(info.colorDark == nil)
        let old: NotificationPayload.GameInfo = try decode(#"{"title":"Pickup","sport":"soccer"}"#)
        #expect(old.emoji == nil)
    }

    // MARK: Round nights on the live backend

    private let card = """
    {"id":"6f1c2a9e-2f7b-4a59-9d3e-1d2c3b4a5f60","host_id":"0b7e4b8c-1111-4c3d-9a2b-123456789abc",
     "host_first_name":"Sofía","host_last_initial":"M","host_grad_year":2027,"activity_slug":"valorant",
     "title":"Valorant rounds","starts_at":"2026-11-27T01:00:00+00:00","duration_minutes":220,
     "ends_at":"2026-11-27T04:40:00+00:00","capacity":16,"going_count":5,"spots_left":11,"notes":null,
     "place_name":"Game room","place_address":"Tec","lat":25.65,"lng":-100.29,"meet_point":null,
     "material_change_at":null,"cancelled_at":null,"auto_repost":true,"reposted_at":null,
     "created_at":"2026-11-24T15:00:00.123456+00:00","sort_at":"2026-11-24T15:00:00.123456+00:00",
     "my_role":null,"my_joined_at":null,"has_blocked_attendee":false,"is_bookmarked":false,"spot_alert":false,
     "my_chat_muted":false,"rotation_rounds":3,"rotation_round_minutes":60,"rotation_break_minutes":20,
     "rotation_group_size":4}
    """

    @Test func roundNightCardsDecode() throws {
        let catalog = ActivityCatalog(catalog: Catalog(kinds: ActivityKind.builtIn, activities: Activity.builtIn + Activity.esports)) { .builtIn }
        let row: GameCardRow = try decode(card)
        #expect(row.game(activity: catalog.activity(slug:)).rotation == .standard)

        // A plain game, and a server from before round nights, have none.
        let plain: GameCardRow = try decode(card.replacingOccurrences(of: #""rotation_rounds":3"#, with: #""rotation_rounds":null"#))
        #expect(plain.rotation == nil)
        let old: GameCardRow = try decode(card.replacingOccurrences(of: #","rotation_rounds":3"#, with: ""))
        #expect(old.rotation == nil)
    }

    @Test func onlyARoundNightSendsRounds() throws {
        var draft = GameDraft(
            activity: Activity.esports[0], title: "Valorant rounds", startsAt: .now, durationMinutes: 220, capacity: 16,
            notes: nil, place: MockFixtures.Places.gameRoom, meetPoint: nil, rotation: .standard
        )
        let rounds = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(GameDraftParams(draft))) as? [String: Any])
        #expect(rounds["p_rotation_rounds"] as? Int == 3)
        #expect(rounds["p_rotation_group_size"] as? Int == 4)

        // A plain plan leaves the keys out, so it still matches a server from before round nights.
        draft.rotation = nil
        draft.durationMinutes = 60
        let plain = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(GameDraftParams(draft))) as? [String: Any])
        #expect(plain["p_rotation_rounds"] == nil)
    }

    @Test func gameRotationDecodes() throws {
        let response: RotationResponse = try decode("""
        {"rounds":[
          {"index":0,"starts_at":"2026-11-27T01:00:00+00:00","ends_at":"2026-11-27T02:00:00+00:00",
           "reveals_at":"2026-11-27T01:00:00+00:00",
           "groups":[[{"id":"0b7e4b8c-1111-4c3d-9a2b-123456789abc","first_name":"Sofía","last_initial":"M","grad_year":2027},
                      {"id":"1c8f5c9d-2222-4d4e-8b3c-23456789abcd","first_name":"Leo","last_initial":"R","grad_year":2026}],
                     []]},
          {"index":1,"starts_at":"2026-11-27T02:20:00+00:00","ends_at":"2026-11-27T03:20:00+00:00",
           "reveals_at":"2026-11-27T02:00:00+00:00","groups":null}]}
        """)
        let plan = response.plan
        #expect(plan.rounds.count == 2)
        #expect(plan.rounds[0].groups?[0].map(\.displayName) == ["Sofía M.", "Leo R."])
        #expect(plan.rounds[1].groups == nil)
        #expect(plan.rounds[1].revealsAt == plan.rounds[0].endsAt)
    }
}
