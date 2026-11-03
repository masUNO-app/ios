# masUNO (iOS)

masUNO helps Tec students find a pickup game — basketball, tennis, soccer or
volleyball — on a map, host one, and fill the last open spots. SwiftUI, iOS 26+.
The app currently runs on mock data; the Supabase backend is being built (see the spec).

- **Spec:** [`docs/SPEC.md`](docs/SPEC.md) · API contract: [`docs/API.md`](docs/API.md) · QA script: [`docs/QA.md`](docs/QA.md)
- **Trello:** [2026 UnaMas](https://trello.com/b/mq7VsJY6/2026-unamas)

## Setup

```sh
brew install xcodegen                          # once
git clone https://github.com/masUNO-app/ios.git && cd ios
cp Config.xcconfig.template Config.xcconfig    # fill in keys from the password manager, or leave placeholders for mock data
xcodegen generate                              # creates MasUno.xcodeproj from project.yml
open MasUno.xcodeproj                          # run the MasUno scheme on a simulator
```

`MasUno.xcodeproj` is generated and git-ignored — change `project.yml` instead, and
re-run `xcodegen generate` after pulling or adding files. `Config.xcconfig` is
git-ignored too: Debug points at `masuno-dev`, Release at `masuno-prod`.

Debug builds accept a `-screen` launch argument to jump straight to a screen for design review:
`popup`, `add`, `form-error`, `edit`, `picker`, `detail-open|in|full|hosting|ended|cancelled`
(add `-raceJoin YES` to `detail-open` for the last-spot race), `who`, `report`, `blocked`, `me`,
`me-hosting`, `profile`, `calendar`, `chat`, `chat-host`, `meetup`, `settings`, `update`, `signed-out`, `suspended`, `gallery`.

## How we work

- `main` is protected: open a PR, get one approval from the other coder, squash merge.
- `CODEOWNERS` requests the right reviewer: views, view models and `DesignSystem/` → Ethan;
  `Data/` and `supabase/` → Emilio; `docs/API.md` → both.
- Every PR links its Trello card; screen changes need screenshots for Arianna.

## Architecture

MVVM, one folder per layer:

```
MasUno/
├── App/           # @main entry, ContentView (launch gate + root NavigationStack), Route
├── Models/        # Pure data: SportsEvent, Venue, Sport, Person, Profile, AppConfig
├── Services/      # EventStore (mock source of truth + domain actions), MockData, LocationService
├── Data/          # Supabase data layer (Emilio): AuthService, repositories, GameStore
├── ViewModels/    # Per-screen presentation state & intents
├── Views/         # SwiftUI screens: Map/, Detail/, GameForm/, Chat/, Me/, Settings/, Safety/, Launch/
├── DesignSystem/  # Theme (green tokens, SPEC §7.1) + components; DEBUG ComponentGallery
└── Utilities/     # EventFormat, TextFilter
supabase/          # Migrations, functions, seed (Emilio)
docs/              # Spec, API contract, QA script
```

Views bind to `@Observable` view models; view models read/mutate the model layer
(`EventStore`, injected via environment). Views never mutate the store directly.

## Screens

Green Figma frames (node ids `341:*`). Copy follows SPEC §7.2 ("game", not "event").

| Figma frame | View | ViewModel |
| --- | --- | --- |
| Map (341:1979), Popup (341:2046) | `Views/Map/EventMapView.swift`, `EventPopup.swift` | `EventMapViewModel` |
| Add / Error / Edit / Delete event (341:1849, 3054, 2703, 2840) | `Views/GameForm/GameFormSheet.swift` | `GameFormViewModel` |
| Choose location (341:2646) | `Views/GameForm/LocationPickerSheet.swift` | `LocationPickerViewModel` |
| Event detail (341:2586), You're in (341:2989) | `Views/Detail/EventDetailView.swift` | `EventDetailViewModel` |
| Who's going (341:2309) | `Views/Detail/WhoIsGoingSheet.swift`, `Views/Safety/` | — |
| Me · Going (341:2165), Me · Hosting (341:2240) | `Views/Me/MeView.swift` | `MeViewModel` |
| Group chat (341:1791), Chat rules (341:2420), Edit meet-up (341:2507) | `Views/Chat/` | — |
| Settings (341:2144) | `Views/Settings/SettingsView.swift` | — |
| Update required, suspended (D2) | `Views/Launch/LaunchGateViews.swift` | `AppViewModel` |

Navigation, the launch gate and app-level sheets live in `ViewModels/AppViewModel.swift`; data in
`Services/EventStore.swift`; mock content in `Services/MockData.swift`. `masuno://game/<id>` opens a game.

Organizer approval (Join requests / Accept–Decline) is post-MVP and intentionally left out — spots are first come, first served.
Group chat is built but not connected: mock timeline, disabled composer ("Messages are coming soon").

## TODO

Placeholders that still need a real answer. Card IDs refer to SPEC §5.

### Waiting on design (D2)
- [ ] Onboarding (E5) — `WelcomeView` is a stand-in that signs straight in on mock auth
- [ ] Event detail Full / Hosting / Ended / Cancelled, report sheet, Blocked people and Settings rows
      were built from SPEC §7.6 copy; swap in Arianna's frames when they're Ready
- [ ] Empty / error / offline states (E14)
- [ ] Interest chip and activity tile colors for non-blue tints (only `chipSport` / `accentSoft` are tokens)

### Waiting on backend (Emilio)
- [ ] Domain models + repository protocols (E1) — screens still use `SportsEvent` / `EventStore` mocks
- [ ] Live data (B6, B7): create / edit / cancel, join / leave, the last-spot race (`-raceJoin YES` fakes it)
- [ ] Report, block and unblock RPCs (B8); delete-account function (B9); sign out via `AuthService` (B5)
- [ ] `app_config` (min version, support email, privacy URL) — mocked in `AppConfig.mock`

### Later
- [ ] TODO/TEMP: "you" are pinned at Tec (`LocationService.mockCoordinate`) so the mock games are nearby wherever you test; launch with `-realLocation YES` for real GPS. Remove with the live map (E9)
- [ ] Live map: campus fallback banner and pull to refresh (E9)
- [ ] Release hygiene (E14): app icon, launch color, Release → prod, keep `-screen` DEBUG-only
- [ ] 2.0: Notify me + Saved backend (bookmarks are local only), notifications, calendar, invite, picker drag, Past games, Spanish
- [ ] Chat backend: sending, real timeline, rules acceptance per account (`GroupChatView` is UI only)
- [ ] Not built from the Figma yet: Repost on hosted games
- [ ] TODO/TEMP: "Invite a friend" shares an App Store search link (`AppConfig.inviteURL`) until the listing / TestFlight link exists
- [ ] Profile edits and interests are local only until `complete_profile` is live (B7)
- [ ] Post-MVP: organizer approval, profile photos, dark mode
