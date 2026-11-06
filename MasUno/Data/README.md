# Data

The app's boundary with Supabase (spec §8.2). Ethan builds it for 1.0 (N21) and Emilio reviews.
This is the only place that imports `supabase-swift`: views and view models talk to it through the
protocols here, which match [`docs/API.md`](../../docs/API.md).

- `AuthService.swift`, `Repositories.swift`: the protocols (E1). Changing them takes both coders.
- `Mocks/`: `MockBackend` implements every protocol with the RPC rules, for previews and tests. DEBUG only.
- Coming: `GameStore` (B6), live `AuthService` (B5), live repositories (B7), `NotificationService` (B16, 2.0).
