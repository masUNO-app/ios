# Data

Emilio's layer (spec §8.2): `AuthService`, `GameStore`, the live repositories and,
in 2.0, `NotificationService`. This is the only place that imports `supabase-swift` —
views and view models talk to it through the repository protocols (E1).

Owned by Emilio in `CODEOWNERS`.
