# Data

The app's boundary with Supabase (spec §8.2). Ethan builds it for 0.5 (N21) and Emilio reviews.
This is the only place that imports `supabase-swift`: views and view models talk to it through the
protocols here, which match [`docs/API.md`](../../docs/API.md).

- `AuthService.swift`, `Repositories.swift`: the protocols (E1). Changing them takes both coders.
- `Mocks/`: `MockBackend` implements every protocol with the RPC rules, for previews and tests. DEBUG only.
- `GameStore.swift`: what screens read and act on (B6). Chat timelines live in `ViewModels/ChatViewModel.swift`, over `ChatRepository` (E26).
- `AppServices.swift`: the one place that picks what's behind the protocols. `UnavailableBackend` fills in for Release without real keys, and for games until the live repositories land (B7).
- `Live/`: the real backend so far: `LiveAuthService` (B5), `LiveCatalog`, and `LiveRows`, the Supabase-free row types that `ContractTests` checks.
- Coming: `NotificationService` (B16, 1.0).
