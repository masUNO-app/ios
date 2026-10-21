# masUNO (iOS)

Prelim SwiftUI build of the masUNO screens from Figma (`plusone-figma`, Page 1).
iOS 26+, mock data only — no backend, no auth.

## Run

```sh
brew install xcodegen   # once
xcodegen generate       # regenerates MasUno.xcodeproj from project.yml
open MasUno.xcodeproj
```

Debug builds accept `-screen registered|hosted|add|popup` as a launch argument to jump straight to a screen.

## Architecture

MVVM, one folder per layer:

```
MasUno/
├── App/          # @main entry, root ContentView, Route
├── Models/       # Pure data: SportsEvent, Venue, ChatMessage, Sport, Person
├── Services/     # EventStore (source of truth + domain actions), MockData
├── ViewModels/   # Per-screen presentation state & intents
├── Views/        # SwiftUI screens: Map/, Plans/, Chat/, AddEvent/
├── Components/   # Shared UI (Avatar, EventIconTile, OrangeCapsuleStyle, Triangle)
├── Utilities/    # EventFormat date/duration formatting
└── Theme/        # Figma color palette
```

Views bind to `@Observable` view models; view models read/mutate the model layer
(`EventStore`, injected via environment). Views never mutate the store directly.

## Screens

| Figma frame | View | ViewModel |
| --- | --- | --- |
| Sports event map | `Views/Map/EventMapView.swift` | `ViewModels/EventMapViewModel.swift` |
| Sports event map · Popup | `Views/Map/EventPopup.swift` | `EventMapViewModel` |
| Sports event map · Add event | `Views/AddEvent/AddEventSheet.swift` | `ViewModels/AddEventViewModel.swift` |
| Registered events | `Views/Plans/RegisteredEventsView.swift` | `ViewModels/RegisteredEventsViewModel.swift` |
| Hosted events | `Views/Plans/HostedEventsView.swift` | `ViewModels/HostedEventsViewModel.swift` |

Navigation/sheet state lives in `ViewModels/AppViewModel.swift`; data in
`Services/EventStore.swift`; mock content in `Services/MockData.swift`.

Organizer approval (Join requests / Accept–Decline) is post-MVP and intentionally left out — spots are first come, first served.

## TODO

Placeholders and judgment calls from the prelim build that still need a real answer.

### Design
- [ ] Dark mode — the app is forced to light (`.preferredColorScheme(.light)` in `MasUnoApp.swift`); needs a dark palette in `Theme.swift`
- [ ] Profile photos — avatars and the "You" pin show initials / a person icon
- [ ] Group chat screen — `GroupChatView` is a stand-in; no Figma frame yet
- [ ] Settings screen — map Settings is a demo-only menu; Settings on the plans bottom bar does nothing
- [ ] Map styling — MapKit standard style with a warm tint, not the Figma's custom map
- [ ] Review additions not in Figma: popup bookmark toggle, "Hosted by · skill" and "Going:" lines, "Give up your spot" button, empty states
- [ ] Navigation — confirm how users reach Your plans / Hosting (currently the map's bookmark menu) and what the plans bottom bar's Search / Filter should do (currently back to map)

### Product
- [ ] Decide whether non-sport events (music, social, games) belong on the map — currently sports only
- [ ] Confirm the posting window (today + next 2 days) and the sport list (Basketball, Tennis, Soccer, Volleyball)
- [ ] Organizer approval (post-MVP) — Join requests UI from the "Hosted events" frame
- [ ] Report / block

### Backend & auth
- [ ] Student email verification before first RSVP (`EventStore.rsvp`)
- [ ] Persist events — everything is in memory and resets on launch
- [ ] Real-time group chat (or link out to an existing group chat for MVP)
- [ ] Push notifications for bookmarked games when a spot opens (currently an in-app banner)
- [ ] Game reminders before start
- [ ] Real user location (currently a fixed mock coordinate) and real venue search in Add event
- [ ] Replace `MockData` with real data; remove the demo "Simulate a player dropping out" option
