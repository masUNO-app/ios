# masUNO (iOS)

masUNO helps Tec students find a pickup game — basketball, tennis, soccer,
volleyball or padel — on a map, host one, and fill the last open spots. SwiftUI, iOS 18.0+. Liquid Glass controls are used on iOS 26 and later; iOS 18 uses themed controls.
Launch is 1.0 on Wed Dec 16; 0.5 and 0.6 are the earlier App Store builds (SPEC §3).

Where things stand (Nov 15): the Supabase backend is live on `masuno-dev` and `masuno-prod`, the 1.0 UI
(sport colors, court art, new map and sheets) is on `main`, and the open PR adds guest browsing,
invite-only sign-up with a waitlist, and the beta tester badge. Debug builds use the real backend when
`Config.xcconfig` has Debug keys; otherwise, and for design review, they run on in-memory mocks.

- **Spec:** [`docs/SPEC.md`](docs/SPEC.md) · API contract: [`docs/API.md`](docs/API.md) · QA script: [`docs/QA.md`](docs/QA.md) · Backend: [`supabase/README.md`](supabase/README.md)
- **Trello:** [2026 UnaMas](https://trello.com/b/mq7VsJY6/2026-unamas)

## The pieces

| Piece | What | Where |
| --- | --- | --- |
| iOS app | This repo: SwiftUI client, bundle ID `com.masuno.app` | `MasUno/` |
| Backend | Supabase (Postgres, RLS, RPCs, Realtime, one edge function). `masuno-dev` for Debug, `masuno-prod` for Release | `supabase/` |
| Alerts | Report, sign-up and invite alerts post to the team Discord from the database | `supabase/README.md` |
| Website and waitlist | `masuno-app.github.io` (Privacy & Terms, Support, the waitlist). Its Google Sheet waitlist is mirrored with Supabase's queue by an Apps Script (N38) | SPEC §8, `docs/API.md` (Website waitlist sync) |
| CI | `ios.yml` builds Release and runs unit/UI tests on pinned iOS 18.6 and 26.5 simulators; `database.yml` runs the pgTAP tests; `keep-alive.yml` reads prod daily so the free project doesn't pause | `.github/workflows/` |
| Design | Figma file and the 1.0 frames (SPEC §7.7) | Arianna |

## Setup

```sh
brew install xcodegen                          # once
git clone https://github.com/masUNO-app/ios.git && cd ios
cp Config.xcconfig.template Config.xcconfig    # fill in keys from the password manager, or leave placeholders for mock data
xcodegen generate                              # creates masUNO.xcodeproj from project.yml
open masUNO.xcodeproj                          # run the masUNO scheme on a simulator
```

`masUNO.xcodeproj` is generated and git-ignored — change `project.yml` instead, and
re-run `xcodegen generate` after pulling or adding files. `Config.xcconfig` is
git-ignored too: Debug points at `masuno-dev`, Release at `masuno-prod`.

Before archiving for TestFlight, fill in the real **Release** values in `Config.xcconfig`.
Archives reject missing or placeholder backend settings. CI's unsigned Release compile uses
the template and verifies compilation; it does not verify production configuration or sign-in.

Debug builds accept a `-screen` launch argument to jump straight to a screen for design review:
`popup`, `popup-saved`, `guest`, `guest-popup`, `guest-detail`, `guest-prompt`, `saved`, `add`, `form-error`, `edit`, `picker`, `detail-open|in|full|hosting|ended|cancelled`
(add `-raceJoin YES` to `detail-open` for the last-spot race; `-mockLocation YES` pins you at Tec), `who`, `who-beta`, `report`, `blocked`, `me`,
`me-hosting`, `invites`, `profile`, `onboarding-primer|sheet|signup|pending|pending-code|campus|school|review|verified|about|interests|guidelines`, `calendar`, `chat`, `chat-unavailable`, `chat-host`, `meetup`, `repost`, `settings`, `update`, `signed-out`, `session-expired`, `suspended`, `gallery`. The full list is in the comment above `openDebugScreen` in `AppViewModel.swift`.

A Debug build puts sign-in, games and chat on `masuno-dev` when `Config.xcconfig` has real Debug keys, including when you open it from the home screen after disconnecting from Xcode (launch arguments only exist for Xcode launches, so this is the default, not the argument). It runs on in-memory mocks, where sign-in is faked and everything is forgotten on relaunch, when you pass `-liveAuth NO` or any `-screen` option, or when there are no real keys. Unit tests pass `-liveAuth NO`.

## How we work

- `main` is protected: open a PR, get one approval from the other coder, squash merge. Squash merges rewrite history, so
  if a branch was stacked on another PR's branch, rebase it onto the new `main` with `git rebase --onto origin/main <old base>` after that PR lands.
- `CODEOWNERS` requests the right reviewer: views, view models and `DesignSystem/` → Ethan;
  `supabase/` → Emilio; `Data/` and `docs/API.md` → both.
- Every PR links its Trello card; screen changes need screenshots for Arianna.

## Architecture

MVVM, one folder per layer:

```
MasUno/
├── App/           # @main entry, ContentView (launch gate + root NavigationStack), Route
├── Models/        # Pure data: Game, Profile, Activity, Place, Chat, Invite, University, DomainError, AppConfig
├── Services/      # LocationService, BuildChannel (TestFlight vs App Store, for the beta badge)
├── Data/          # Protocols (AuthService, repositories), Live/ and Mocks/, GameStore; only place that imports Supabase
├── ViewModels/    # Per-screen presentation state & intents
├── Views/         # SwiftUI screens: Map/, Detail/, GameForm/, Chat/, Me/, Onboarding/, Settings/, Safety/, Launch/
├── DesignSystem/  # Theme and tokens (1.0, SPEC §7.7), SportStyle, CourtArt, components; DEBUG ComponentGallery
└── Utilities/     # EventFormat, TextFilter
MasUnoTests/       # Unit tests (Cmd-U, or the masUNO scheme's Test action)
supabase/          # Migrations, delete-account function, seed, pgTAP tests (Emilio)
docs/              # Spec, API contract, QA script
.github/           # CODEOWNERS, PR template, CI workflows
```

Views bind to `@Observable` view models; screens read `GameStore` (injected via environment), which sits
over the repository protocols. `Data/AppServices.swift` is the one place that picks mock or live.

## Screens

Built from the green Figma frames (node ids `341:*`) and restyled for 1.0 (SPEC §7.7). Copy follows SPEC §7.2 ("game", not "event").

| Figma frame | View | ViewModel |
| --- | --- | --- |
| Map (341:1979), Popup (341:2046) | `Views/Map/EventMapView.swift`, `EventPopup.swift` | `EventMapViewModel` |
| Add / Error / Edit / Delete event (341:1849, 3054, 2703, 2840) | `Views/GameForm/GameFormSheet.swift` | `GameFormViewModel` |
| Choose location (341:2646) | `Views/GameForm/LocationPickerView.swift` | `LocationPickerViewModel` |
| Event detail (341:2586), You're in (341:2989) | `Views/Detail/EventDetailView.swift` | `EventDetailViewModel` |
| Who's going (341:2309) | `Views/Detail/WhoIsGoingSheet.swift`, `Views/Safety/` | — |
| Me · Going (341:2165), Me · Hosting (341:2240) | `Views/Me/MeView.swift`, `EditProfileSheet.swift` | `MeViewModel`, `ProfileEditorViewModel` |
| Invites (N37) | `Views/Me/InvitesSheet.swift` | `MeViewModel` |
| Group chat (341:1791), Chat rules (341:2420), Edit meet-up (341:2507) | `Views/Chat/` | — |
| Settings (341:2144) | `Views/Settings/SettingsView.swift` | — |
| Onboarding, waitlist, invite code (SPEC §7.5) | `Views/Onboarding/OnboardingFlow.swift` | `OnboardingViewModel` |
| Browse as a guest, Which campus? (R7-15) | `Views/Onboarding/GuestCampusStep.swift`, the map and detail views | `AppViewModel` |
| Update required, suspended (D2) | `Views/Launch/LaunchGateViews.swift` | `AppViewModel` |

Navigation, the launch gate and app-level sheets live in `ViewModels/AppViewModel.swift`; data in
`Data/GameStore.swift`; mock content in `Data/Mocks/`. `masuno://game/<id>` opens a game.

masUNO launches at Tec, but the app has no campus built in: open campuses come from `open_universities`, and your
campus from `my_profile`. To change or add a campus, see SPEC §8.10; no release needed.

Signed out, a guest sees the map and game details without names (`guest_games`); joining, saving, hosting and Who's going ask for an account.
New accounts are invite-only: a member's code (3 each) lets you in at once, and without one you wait on the waitlist with your place in line (N37, N38).

Organizer approval (Join requests / Accept–Decline) is post-MVP and intentionally left out — spots are first come, first served.
Group chat messaging (E26) is built and follows `app_config.chat_enabled` on the server. Off, which is how it ships, the chat is read-only: pinned card and system rows, no composer (N14).

## TODO

Placeholders that still need a real answer. Card IDs refer to SPEC §5.

### Waiting on backend
- [x] Sign-in for real students: school email and password, approved by hand from the Discord alert (N36). School SSO (B21, B22, K19) is kept in the code, unused, in case Tec IT approves the Entra app.
- [ ] Apply the newer migrations to `masuno-prod` and `masuno-dev` as they land (`supabase/README.md` lists them: group chat, live game lists, guest games, invites and beta, waitlist sync).
- [ ] Group chat messaging (E26, B20): run QA §8 with two phones, then turn `chat_enabled` on in prod.
- [ ] Website waitlist sync (N38): store the shared secret and the Apps Script URL in Vault, and give the secret to whoever deploys the website's script (`supabase/README.md`, step 9).

### Waiting on the team
- [ ] Final app icon (D3): the one in the icon set is a temporary one from the designer; launch color uses `Background`
- [ ] Version is 0.6 in `project.yml`. If 0.5 is still to be archived from this tree, set `MARKETING_VERSION` back to 0.5 for that archive
- [ ] "Verified student" vs "Tec verified" (O4), real venues in `MockFixtures` for screenshots (O5)

### Later
- [x] 1.0 UI (E27), guest browsing (R7-15), invites and the beta badge (N37), one waitlist (N38)
- [ ] 1.0: Notify me + synced Saved, notifications, picker drag, Spanish
- [ ] Post-MVP: organizer approval, profile photos, dark mode

Build 0.9 (2) implements the first optimization pass and the post-create/join primer crash fix.
CI includes mock iOS tests, primer UI regressions, Release packaging, pgTAP, and pinned Deno/Node
push-delivery checks. Remaining physical-device checks are listed in [QA.md](docs/QA.md).
