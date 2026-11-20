# Data

Views use the repository protocols and `GameStore`; Supabase SDK calls stay in `Live/`.
The wire contract is [API.md](../../docs/API.md). `MockBackend` implements the same contracts
for Debug previews, UI regression tests and unit tests. Release uses live repositories or
`UnavailableBackend` when configuration is missing.

`GameStore` owns account/guest state, game cache, list membership, attendee freshness and
mutations. `ChatViewModel` owns the current conversation and scene-scoped chat connection.
`AppServices` constructs repositories and the push service; SwiftUI sheets requiring these
objects must receive their environment dependencies at the sheet presentation boundary.

## Read ownership

`SharedReadPool` deduplicates equivalent in-flight reads; it does not cache completed values.
Keys describe resource/query identity, including sorted ID sets and guest campus where needed.
A store is scoped to a session UUID. Reset rotates that UUID and cancels all its pools; every
publisher also checks context because a transport may ignore cancellation. Per-game mutation
versions and publication epochs prevent older reads from undoing newer writes or reads.

Each caller owns a waiter. Cancelling one resumes it immediately, while other callers retain
their request. The last departing waiter cancels the operation. A flight UUID prevents an old
completion from removing a replacement. Attendee requests share a global limit of four per
store, including requests from different screens. Fixed resource labels and elapsed durations
are logged without IDs, messages, names or coordinates; test diagnostics expose pool counts.

A forced read bypasses the attendee freshness check but still shares equivalent in-flight work.
Map face previews request visible single pins and the selected pin. Full attendee responses are
never replaced with incomplete previews. Dirty IDs, count changes and a 120-second freshness
window invalidate attendees. Campus invalidations merge within a bounded delay and drain again
when a ping arrives during a read. Broad invalidation refreshes lists and retained/saved extras.

## Mutation and retention rules

Join/leave, mute, bookmarks and per-person block changes serialize opposing intents. Hosting
writes reject overlapping submissions. No create/join write is automatically replayed after an
uncertain failure; membership failures reconcile with a read. Read acknowledgements keep local
unread cleared on failure and retry on recovery. A newer read during an acknowledgement causes
a follow-up acknowledgement rather than sharing an obsolete server timestamp.

Current map/saved games, navigation/form targets and active writes remain pinned. Joined/hosted
history has a 14-day window; other unpinned entries expire after 15 minutes without access when
pruning runs. Eviction includes their attendee/activity caches. Session reset clears everything
account-specific. Invites load on demand; bookmark import remains retryable until successful.

See [QA.md](../../docs/QA.md) for remaining device and production acceptance checks, and
[API.md](../../docs/API.md) for chat pagination and notification delivery contracts.
