# masUNO (iOS)

masUNO helps Tec students find a pickup game — basketball, tennis, soccer,
volleyball or padel — on a map, host one, and fill the last open spots. SwiftUI, iOS 26+.
Debug builds run on an in-memory mock backend; the Supabase backend is being built (see the spec).

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
`popup`, `popup-saved`, `saved`, `add`, `form-error`, `edit`, `picker`, `detail-open|in|full|hosting|ended|cancelled`
(add `-raceJoin YES` to `detail-open` for the last-spot race; `-mockLocation YES` pins you at Tec), `who`, `report`, `blocked`, `me`,
`me-hosting`, `profile`, `onboarding-primer|sheet|school|review|verified|about|interests|guidelines`, `calendar`, `chat`, `chat-host`, `meetup`, `repost`, `settings`, `update`, `signed-out`, `session-expired`, `suspended`, `gallery`.

Running from Xcode passes `-liveAuth YES` (set in `project.yml`), which puts sign-in, games and chat on `masuno-dev` when `Config.xcconfig` has real Debug keys. Untick it in the scheme, or pass a `-screen` option from the command line without it, to run on in-memory mocks: sign-in is faked there and everything is forgotten on relaunch. Unit tests always run on mocks.

## How we work

- `main` is protected: open a PR, get one approval from the other coder, squash merge.
- `CODEOWNERS` requests the right reviewer: views, view models and `DesignSystem/` → Ethan;
  `supabase/` → Emilio; `Data/` and `docs/API.md` → both.
- Every PR links its Trello card; screen changes need screenshots for Arianna.

## Architecture

MVVM, one folder per layer:

```
MasUno/
├── App/           # @main entry, ContentView (launch gate + root NavigationStack), Route
├── Models/        # Pure data: Game, Profile, Activity, Place, DomainError, AppConfig
├── Services/      # LocationService
├── Data/          # Protocols (AuthService, repositories), mocks, GameStore; only place that imports Supabase
├── ViewModels/    # Per-screen presentation state & intents
├── Views/         # SwiftUI screens: Map/, Detail/, GameForm/, Chat/, Me/, Settings/, Safety/, Launch/
├── DesignSystem/  # Theme (green tokens, SPEC §7.1) + components; DEBUG ComponentGallery
└── Utilities/     # EventFormat, TextFilter
MasUnoTests/       # Unit tests (Cmd-U, or the MasUno scheme's Test action)
supabase/          # Migrations, functions, seed (Emilio)
docs/              # Spec, API contract, QA script
```

Views bind to `@Observable` view models; screens read `GameStore` (injected via environment), which sits
over the repository protocols. `Data/AppServices.swift` is the one place that picks mock or live.

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
| Onboarding (SPEC §7.5) | `Views/Onboarding/OnboardingFlow.swift` | `OnboardingViewModel` |
| Update required, suspended (D2) | `Views/Launch/LaunchGateViews.swift` | `AppViewModel` |

Navigation, the launch gate and app-level sheets live in `ViewModels/AppViewModel.swift`; data in
`Data/GameStore.swift`; mock content in `Data/Mocks/`. `masuno://game/<id>` opens a game.

masUNO launches at Tec, but the app has no campus built in: open campuses come from `open_universities`, and your
campus from `my_profile`. To change or add a campus, see SPEC §8.10; no release needed.

Organizer approval (Join requests / Accept–Decline) is post-MVP and intentionally left out — spots are first come, first served.
Group chat messaging (E26) is built and follows `app_config.chat_enabled` on the server. Off, which is how it ships, the chat is read-only: pinned card and system rows, no composer (N14).

## TODO

Placeholders that still need a real answer. Card IDs refer to SPEC §5.

### Waiting on backend
- [ ] School sign-in for real students: the Entra ID app and Tec's tenant (B21, B22, K19). The last blocker for 0.5.
- [ ] Group chat messaging (E26, B20) is built, and on `masuno-dev` with chat on. Run QA §6 there with two phones. Then
      apply `20261110000000_group_chat` to prod, turn `chat_enabled` on there and run QA §6 again (`supabase/README.md`).

### Waiting on the team
- [ ] Final app icon (D3): the one in the icon set is a temporary one from the designer; launch color uses `Background`
- [ ] Privacy & Terms page live at `masuno-app.github.io/privacy` (D4): the app already links to it
- [ ] `AppConfig.appStoreID` from App Store Connect (E15): Invite a friend stays hidden in Release until it's set
- [ ] Version is 0.6 in `project.yml`. If 0.5 is still to be archived from this tree, set `MARKETING_VERSION` back to 0.5 for that archive
- [ ] "Verified student" vs "Tec verified" (O4), real venues in `MockFixtures` for screenshots (O5)

### Later
- [ ] 1.0: 1.0 UI (E27), Notify me + synced Saved, notifications, picker drag, Spanish
- [ ] Post-MVP: organizer approval, profile photos, dark mode
