# masUNO iOS — Project Specification

**Rev. 7 · 2026-11-05, updated Nov 6 and Nov 10** · replaces rev. 6 (Nov 3), `PLAN.md` (rev. 2) and earlier revisions. Rev. 7 records what's done, keeps the 0.5 submission on **Mon Nov 9** by moving all remaining backend work into Fri–Sun Nov 6–8, and adds the **1.0 UI** from the new Figma (§7.7).
**Team:**
- **Ethan Wen** — frontend: the iOS app's screens, view logic and App Store submission; **for 0.5 also the Swift data layer** (rev. 7, N21).
- **Emilio** — backend: Supabase (tables, rules, RPCs, functions, jobs, sign-in, notifications).
- **Arianna** — design: Figma, app icon, website pages, decks, screenshots, design QA.
- **Ricardo** — team lead and outreach: users, beta testers, hosts, copy, demo days, launch.

**Program:** App Accelerator: Startup to 1000 — Demo Day #1 **Thu Nov 5**, Demo Day #2 **Thu Nov 19**, Demo Day #3 **Thu Dec 3**, Product Launch **Wed Dec 16**

**Status (Tue Nov 10):**
- **0.5 submits Thu Nov 12** — the program manager moved the first submission from Mon Nov 9 (N34). If its must-haves aren't on prod by then, N20's slip rule applies: submit the day they are, with **Mon Nov 16** (together with 0.6) as the hard backstop. The last resubmit that can be live for Demo Day #2 is **Fri Nov 13**.
- **Backend is live on dev and prod:** PR #12 (merged Nov 9) added the schema, RLS, RPCs, the auth hook, the text filter, the demo campus, report alerts and `delete-account`, with pgTAP tests in CI. `masuno-prod` was set up on Nov 10 (B12): migrations, `delete-account`, auth hook, redirect URL, the 3 allowlisted accounts, demo campus games and the keep-alive job.
- **The app runs on live data:** PR #13 (B7, live repositories) is in review. With it, every 0.5 screen works on `masuno-dev` in the simulator, and `LiveIntegrationTests` pass there. Release builds point at prod (Nov 10, the local `Config.xcconfig`).
- **School sign-in is configured but untested:** the Azure provider is on in both projects with tenant `organizations` (N35), but no one has signed in with a real Tec account yet (B21). Real students can't sign in until Tec IT approves the app, if it must (K19). Before they can, the hook needs a tenant check (B22).
- **Still missing for submission (Nov 11):** real-phone and two-phone QA, and the listing (O7). The app icon (D3), the Support page (D4) and `AppConfig.appStoreID` (E15) are in, along with a privacy manifest (`PrivacyInfo.xcprivacy`).
- **1.0 UI is designed:** the Figma file "masuno figma" has per-sport flows (basketball, tennis, soccer, volleyball, padel), group chat for each sport, Me and Settings, plus `DESIGN.md` v2.0 in the project. This is the 1.0 look (§7.7); what's built is the 0.5 look.
- `com.masuno.app` registered on the Boys & Girls Clubs of Chicago developer team (Oct 28).

> **How to read this.** §0–§6 are the plan: releases, scope, calendar, who does what, how we work. §7–§9 are the product and technical spec (§7.1–§7.6 = 0.5 UI, §7.7 = 1.0 UI). §10–§13 are release steps, risks, decisions and what comes after. Items marked **⚑** need sign-off (§12).
>
> **IDs:** **E** = Ethan, **B** = backend (Supabase is Emilio's; B5–B7 are Ethan's for 0.5), **D** = Arianna (design), **O** = Ricardo (outreach).
>
> **Status words** in §5: **Done** (merged / delivered) · **Built** (on mock data, needs live wiring) · **To do** · **Not confirmed** (no evidence in the repo, Figma or Trello — owner please update).
>
> **Estimates** are focused build hours for one developer working with AI coding tools, including self-testing, excluding program sessions and code review.
>
> **Times:** program sessions are 5:00–6:30 pm Central (6:00–7:30 pm Eastern for Ethan).

---

## 0. Summary

- **Two UI versions** (rev. 7, N23):
  - **0.5 UI** = what's built today (green design system, SF Pro, blue pins, §7.1–§7.6). It ships in 0.5 and 0.6 as is.
  - **1.0 UI** = the new Figma + `DESIGN.md` v2.0 (sport colors, court headers, "+1" open-spot tokens, rounded type, §7.7). It ships in 1.0.
  - Where the two disagree, the built app wins for 0.x and the Figma wins for 1.0.
- **Builds:**
  - **Build 0.1 — Demo Day #1 (Nov 5):** the redesigned app on mock data, on TestFlight (internal).
  - **0.5 — submitted Thu Nov 12** (moved from Mon Nov 9 by the program manager, N34): the real app on `masuno-prod` with Tec sign-in, hosting, joining and everything App Review requires. The same build goes to the external TestFlight beta. Aim: live before Demo Day #2 (Nov 19), so the last resubmit is Fri Nov 13.
  - **0.6 — fast follow, submitted Mon Nov 16:** review and beta fixes, anything cut from 0.5, and group chat messaging if it's live (§3). 0.5 UI. Also the hard backstop for 0.5.
  - **1.0 — after Demo Day #3:** the 1.0 UI, notifications, synced Saved games, Spanish and polish. Beta Tue Dec 1, submitted Tue Dec 8, live for the Product Launch (Dec 16).
- **Coders, split for 0.5** (N21):
  - **Emilio** builds Supabase only: tables, rules, RPCs, auth hook, school sign-in (Azure provider), safety, delete-account, prod.
  - **Ethan** builds everything in Swift, including the data layer (`AuthService`, `GameStore`, live repositories), because his screens are done and the backend is the critical path.
  - They meet at one contract (§8.5, `docs/API.md`) and the Swift repository protocols (E1), now due **Fri Nov 6 at noon**.
- **Hours left (Nov 10):** Ethan ≈ 37 h (about 7 h for 0.5: B7 review fixes, the E25 two-phone check, the SSO spike, real-phone and two-phone QA, the RC and E15; 30 h for 1.0); Emilio ≈ 28 h (about 4 h for 0.5: the hook tenant check B22, the SSO spike, report alerts and backups; 24 h for 1.0); plus group-chat messaging for 0.6 (B20 + E26, ~9 h). **The critical path is now school sign-in** (B21, B22, K19) and the release candidate, not the backend.
- **Arianna (~5 h/week)** has finished the 1.0 look in Figma. By Sun Nov 8 she delivers the app icon (Fri), the website pages (Sat) and 0.5 screenshots (Sun). After that she draws the screens the 1.0 Figma doesn't have yet (onboarding, states, safety, notifications) in the 1.0 style.
- **Ricardo (~5 h/week)** gets people:
  - Supabase access for Emilio first (unconfirmed and blocking), and the team Gmail (Contact us, review accounts).
  - Tec IT answers and test school accounts (O4), venues, beta testers, hosts and real games.
  - The policy and App Store copy, Spanish translation, demo-day stories and numbers.
  - The launch push and moderation.
- **No domain, no custom email.** Sign-in goes through the school's account, so we send no sign-in email; the team Gmail is only for Contact us and review accounts; the policy and support pages live on `masuno-app.github.io`; report alerts go to the team chat; both Supabase projects stay on the free plan.

---

## 1. What changed

### This revision (rev. 7, Nov 5; N30–N33 added Nov 6; N34–N35 added Nov 10)

| # | Change | Why | Sign-off |
| - | --- | --- | --- |
| N34 | **0.5 submits Thu Nov 12**, moved from Mon Nov 9 by the program manager. Status then: the backend merged on Nov 9 (PR #12), prod was set up on Nov 10 (B12), and B7 is in review (PR #13). If the must-haves aren't on prod by Thu Nov 12, N20's slip rule still applies: submit the day they are, with Mon Nov 16 (with 0.6) as the hard backstop. The last resubmit that can be live for Demo Day #2 is Fri Nov 13. Chat messaging (B20 + E26) moves to 0.6. | Program schedule change; the original weekend plan also needed ~28 h of backend work in three days (K1). | Program manager (Nov 10) |
| N35 | **Prod's Azure tenant stays `organizations`, not locked to Tec** (replaces "lock to the tenant" in §8.4 and §8.10). Instead, the auth hook checks that an Azure sign-up came from the campus's own tenant, `universities.tenant_id` (B22). B22 must be live before real students can sign in on prod. It's a server change, so it doesn't wait for an app release. | `organizations` admits any work or school tenant, and that tenant's admin can give a user any email address, including an unverified `@tec.mx` one. A tenant lock would fix that but tie the project to one campus, against N32. A per-campus tenant check fixes it either way. | ⚑ Emilio (B22) |
| N20 | **0.5 still submits Mon Nov 9.** Nothing backend is in the repo yet, so all remaining 0.5 work moves into Fri–Sun Nov 6–8: contract freeze Fri noon, backend core Sat, go/no-go #2 Sun noon, RC + Beta App Review Sun evening (§4.1). If sign-in, join or delete account isn't live on prod by Sun noon, 0.5 submits the day they are, with Mon Nov 16 as the hard backstop. | Team plan (Nov 5): review waits are long, so submit as early as possible. A mock build can't pass review (2.1). | ⚑ Ricardo, Emilio (weekend hours) |
| N21 | **Ethan owns the Swift data layer for 0.5:** `AuthService` (B5), `GameStore` (B6), live repositories (B7) and the instant block hiding in `GameStore` (part of B8). Emilio stays on Supabase. Reverses N7 for 0.5; Emilio keeps `NotificationService` (B16) in 1.0. | Ethan's 0.5 screens are done; this halves Emilio's critical path. Rev. 6's balancing rule already pointed this way. | ⚑ Emilio |
| N22 | **Contract freeze moves to Fri Nov 6 (noon).** E1 is marked Done on Trello but isn't in the repo (screens still use `SportsEvent`/`EventStore`), so it's reopened. `docs/API.md` is due the same day. | Nov 4 freeze was missed; B3 and B5–B7 build against it. | — |
| N23 | **Two UI versions.** Everything built today is the **0.5 UI** (§7.1–§7.6, green Figma frames `341:*`). The new Figma and `DESIGN.md` v2.0 are the **1.0 UI** (§7.7), built in 1.0 as E27. If they conflict, 0.x follows the build and 1.0 follows the Figma. | Keeps the Nov 16 build stable; gives the redesign a release of its own. | Decided (Ethan, Nov 5) |
| N24 | **1.0 UI vs locked decisions:** a few Figma details conflict with earlier decisions (interests on Who's going, calendar-sync and name-visibility rows in Settings, "Delete game", "· Read" receipts, mic glyph, font). Listed in §7.7.6 with defaults; signed off as R7-4 to R7-10. | The 1.0 frames shouldn't quietly undo privacy and scope decisions. | ⚑ Arianna, Ricardo |
| N25 | **D2 (frames for screens built from the spec) is now drawn in the 1.0 style and built in 1.0**, merged with D8. 0.5 ships those screens as built from §7.5–§7.6. 0.6 no longer swaps in onboarding frames. | No point drawing 0.5-style frames that 1.0 replaces a month later. | — |
| N26 | **0.6 stays the Mon Nov 16 fast follow** and doubles as the backstop if 0.5 slips. It no longer swaps in onboarding frames (N25). | Keeps the Nov 9 build small. | — |
| N27 | **Release blockers found in the code** added to E14 and §10.4: Settings shows "Privacy & Terms — Coming soon"; the chat composer says "Messages are coming soon"; Invite shares an App Store *search* link; the mock location at Tec; the empty app icon; Delete account isn't wired. | Each one is an App Review 2.1 or 5.1.1(v) risk. | — |
| N28 | **Auto-repost (N17) look:** the 1.0 Figma has no toggle and no "Reposted …" line yet. 0.5 ships the built toggle and line (0.5 UI); Arianna draws it in the 1.0 style (D11 → 1.0). The bump pin ("Spot open") still needs building (E25). | Built on mocks; the server half is in B3. | — |
| N30 | **Contract gaps closed in `docs/API.md` (E1):** `game_activity` becomes an append-only table, because `leave_game` deletes the `rsvps` row a view would read; new `my_blocks()`, because RLS hides blocked people's names from Blocked people; `create_game` returns `game_cards` like every other game write; new error codes `not_authenticated` and `suspended`; `game_cards` gains `host_grad_year` and `sort_at`; `app_config` and `activities` are readable signed out; new `AppConfigRepository`. | The rev. 7 contract couldn't support these screens as written. | Decided (Nov 6); backend not started, so this is the contract |
| N31 | **Frontend for 0.5 finished on mocks, Nov 6** (`ethan/e1-contract`): every screen runs on the E1 models, `GameStore` and `AuthService`; `EventStore`, `MockData` and the old models are deleted; chat is the read-only fallback. Choices made along the way: no default place in the game form (pick one, or see an error); the "Turn on location" banner shows only when location is denied, since it would be wrong for a reviewer who has it on but is far away (they still land on campus); a map can't pull to refresh because dragging pans it, so tapping "N games nearby" refreshes; Invite a friend is hidden in Release until `AppConfig.appStoreID` is set; bumped games aren't "listed first in search", because map search only filters pins and has no list; **Release builds run on `UnavailableBackend` until B5 + B7**, so they can't show mock data, and can't sign in either. | Nothing left in Swift can move without the backend. | — |
| N32 | **masUNO launches at Tec but isn't locked to it.** Which campuses are open is data (`universities.signup_enabled`), so the launch campus can change, or more can open, without an app release (§8.10). The app no longer hard-codes `@tec.mx`, "Tec" or the Monterrey map center. Tec stays the only launch plan; no other campus is being built for now. | If Tec doesn't work out, the team shouldn't have to resubmit to App Review to move. | Decided (Ethan, Nov 6) |
| N33 | **Sign-in is school single sign-on, replacing email codes.** "Continue with school account" is the only sign-in: Supabase's Azure (Microsoft Entra ID) provider for Tec, opened through supabase-swift `signInWithOAuth` in an ephemeral `ASWebAuthenticationSession` (§7.5, §8.4). Google Workspace schools (later campuses) would use the Google provider restricted to the school's domain. No consumer social login and no public email + password sign-up. Dates don't change, but **real students can't sign in until Tec's tenant allows the app** (K19, R7-14). | University email filters often delay or quarantine one-time codes, so students get stuck at sign-in. Guideline 4.8 exempts education apps that require an existing education account; consumer login or open sign-up would make Sign in with Apple, or an equivalent privacy-focused login, required. | Decided (Ethan, Nov 6); ⚑ Emilio (B2, B4), Ricardo (O4) |
| N29 | **Trello is behind:** the 0.5 list still says "submit Sat Nov 21", most card dates are rev. 5's, and Ricardo/Arianna/Emilio cards show no progress. Each owner updates their cards to §5 at the Fri Nov 6 go/no-go (§6). | The plan only works if status is visible. | — |

### Rev. 6 (still in force unless changed above)

| # | Change | Why | Sign-off |
| - | --- | --- | --- |
| N11 | *(Date kept by N20: Mon Nov 9.)* Submit 0.5 early; build 0.9 folded into 0.5; one release candidate goes to App Review and the external TestFlight beta on the same days. | App Store Connect review waits are long. | ⚑ |
| N12 | *(Dates moved by N20 into Fri–Sun Nov 6–8.)* 0.5 needs the live backend — a mock-data build can't pass review (report, block and delete account must really work; guideline 2.1). | Follows from N11. | ⚑ Emilio |
| N13 | 0.6 fast follow (Mon Nov 16) takes anything cut from 0.5 (§3 cut order). | Keeps the 0.5 build small. | — |
| N14 | **Group chat in 0.5, with a fallback.** The chat screen stays as built; real messaging (Chat v1, Appendix A) is a 0.5 stretch goal (B20 + E26). **If messaging isn't live on prod by the Sun Nov 8 release candidate, the submitted build drops the composer and mock messages** and ships the read-only game hub (§7.6.9). | A disabled "coming soon" composer or fake messages would be rejected under 2.1. | Decided (team, Nov 3) |
| N15 | Bookmarks + Saved list in 0.5, stored on the phone only. Syncing and "Notify me if a spot opens" in 1.0 (B15, E17). | Already built. | — |
| N16 | Add to calendar, Invite a friend, Google Maps option (E19) and Past games + Edit profile & interests (E21) in 0.5. Edit profile needs `complete_profile` live; otherwise it moves to 0.6. | Already built. | — |
| N17 | Auto-repost in 0.5 (MVP): host toggle (on by default) that bumps a game when a full game frees a spot. Backend in B3 (§7.6.11, §8.3, §8.5). | Hosts want traction, not a manual bump. | Decided (team, Nov 3) |
| N18 | Onboarding is built from §7.5 copy. *(Frames now come with the 1.0 UI, N25.)* | Unblocks 0.5. | — |
| N19 | Padel as a fifth sport (game form, map filter, interests). Backend: `padel` in the `activities` seed (B1). | Team decision Nov 3. **Done in the app (PR #6).** | Emilio (B1 seed) |

### Rev. 5 (still in force)

| # | Change | Why | Sign-off |
| - | --- | --- | --- |
| N6 | **Roles:** Ethan frontend, Emilio backend, Arianna design, Ricardo outreach. All work in §5 re-assigned. | Team decision. | — |
| N7 | *(Changed by N21 for 0.5: Ethan builds the Swift data layer.)* **Split at the data layer:** Emilio owns `AuthService`, the repositories and `GameStore` (Swift), not just the database. | Keeps Supabase knowledge in one head and evens out the coders' hours (otherwise Ethan would carry ~105 h). | — |
| N8 | **Supabase access:** Ricardo's organization stays the owner (rev. 2 decision 10), but Emilio is added as an **Owner** of it; or Ricardo transfers the organization to Emilio. | The backend developer needs full control (billing-free plan, secrets, members). | ⚑ |
| N10 | **Repo setup task (E0)** for Ethan, due Nov 1: access, branch protection, folders, config template, `CODEOWNERS`, PR template, README. `CODEOWNERS` moves from B11 to E0. | Emilio can't start B1 until the repo is ready for two coders. | — |
| N9 | **Design leads the build:** Arianna delivers frames for each screen before Ethan builds it (§4.2), and reviews screenshots in UI PRs. | Rev. 4 had no designer; several 0.5 screens have no frame. | — |

### Rev. 4 (still in force)

N1 builds at each demo day, 0.5 before Demo Day #3, 1.0 after it, launch Dec 16 · N2 smaller 0.5, notifications and polish in 1.0 · N3 no domain or custom email (Gmail SMTP *(dropped by N33)*, GitHub Pages, team-chat alerts, free Supabase) · N4 one-page Privacy & Terms.

### From rev. 2 (carried over)

| # | Change | Why | Sign-off |
| - | --- | --- | --- |
| C1 | Releases with fixed scope replace the open backlog. | Rev. 2 ≈ 95 dev-days; about 16 are available. | — |
| C2 | *(Reversed by N14: group chat in 0.5, read-only fallback.)* **No chat screen** during the program; meet-up spot and Who's going live on Event detail. Chat v1 design kept in Appendix A. Reverses decision 3. | A disabled "Messages are coming soon" composer invites an App Review 2.1 rejection; hub + timeline costs ~8 h. | ⚑ |
| C3 | *(Timing changed by N16: in 0.5.)* **"Add to Calendar" button** (EventKitUI, no permission prompt) in 1.0 instead of calendar sync. Reverses decision 14. | 1.5 h instead of ~16 h; edited games don't update the calendar entry. | ⚑ |
| C4 | **No profile photos** during the program; initials avatars. | No storage, upload or image moderation. | ⚑ |
| C5 | **Names show as "First L."** (e.g. "Emilio G.") to others; no name-visibility setting. | Privacy-forward default, no settings screen. | ⚑ |
| C6 | Notifications in **1.0**. | Biggest single item (~19 h) and needs an APNs key (created in the B&GC developer account). | ⚑ |
| C7 | Notification outbox drained by a 1-minute `pg_cron` job. | Batching and retries in one place. | — |
| C8 | `profiles` (public card) split from `profile_private` (own row only). | Fixes rev. 2's RLS: views couldn't read the host's name. | — |
| C9 | `events.going_count` stored, with `check (going_count <= capacity)`. | Correct counts with blocks; overbooking impossible. | — |
| C10 | `events.ends_at` set by trigger. | `timestamptz + interval` can't be a generated column. | — |
| C11 | *(N33 adds a primer screen in onboarding; the iOS prompt itself still waits for the map.)* Location asked when the map first opens; notifications (1.0) after the first join or hosted game. | Better grant rates; shorter onboarding. | — |
| C12 | App Review uses a hidden **demo campus** with auto-refreshed games. | Reviewers always see joinable games; real users never see fake ones. | — |
| C13 | Apple account: B&GC team; all four of us already have access. Still needed for 1.0: an APNs key. | `com.masuno.app` registered Oct 28. | — |
| C14 | *(Dropped by N33: no sign-in email.)* Raise Supabase's auth-email limit (30/hour default with custom SMTP). | A demo-day or launch post could exceed 30 sign-ups an hour. | — |
| C15 | Metrics from one SQL view + App Store Connect; no analytics SDK. | Demo-day numbers at ~2 h cost. | — |
| C16 | Minimum-version gate in 0.5. | Lets 1.0 force an update if needed. | — |
| C17 | `supabase/` lives in the `ios` repo. | One PR can change client and database together. | — |

**Still locked from rev. 2:** Supabase; Tec school-account SSO only (Microsoft Entra via Supabase Azure provider, N33), no consumer social login or public sign-up; sports only (Basketball, Tennis, Soccer, Volleyball, Padel — N19); no organizer approval; launching at Tec de Monterrey (N32); English first with strings externalized; venue search + pin + current location; 7-day posting window; light mode only; sign-in gates the app; no skill level; soft cancel; separate dev and prod projects.

---

## 2. Goals & release criteria

**Goals**
1. A build to show at every demo day; 0.5 submitted Mon Nov 9 and on the App Store before Demo Day #2 (Nov 19) if review allows, Demo Day #3 at the latest (Demo Day #2 runs from the external TestFlight beta if review is still pending); 1.0 on the App Store for the Product Launch.
2. A Tec student can sign up, find or post a game, join it and know where to show up, in under 2 minutes from install.
3. Pass App Review's user-generated-content rules: agree to guidelines, text filter, report, block, act on reports within 24 h, contact info in the app, in-app account deletion.
4. Numbers for each demo day: beta testers, verified sign-ups, games hosted, joins, games that filled.

**Not in scope during the program:** photos, calendar sync, dark mode, Android/web, organizer approval, recurring games, non-sport activities, opening a second campus (the app is ready for it, N32), our own domain or branded email.

**Release criteria for 0.5 and 1.0**
- Core loop works on two physical phones against `masuno-prod`, including two people racing for the last spot.
- App Review checklist (§10.4) all green.
- 0.5: no crash in the Sun Nov 8 two-phone QA pass. 1.0: no crash in the last 3 days of TestFlight (Xcode Organizer).
- Every user-facing string in the String Catalog; VoiceOver can complete the core loop (full accessibility pass in 1.0).
- 0.5: Arianna has checked the RC against the green `341:*` frames and this spec (differences noted). 1.0: each screen matches its 1.0 frame (§7.7) or the difference is noted.

**Demo-day targets** (testers, sign-ups, games) are set by Ricardo (O1, still open) and reported before each demo day (O10).

---

## 3. Releases & scope

| Build | UI | Channel | Shown at | Contents |
| --- | --- | --- | --- | --- |
| **0.1 Prototype** | 0.5 | TestFlight (internal) | Demo Day #1, Thu Nov 5 | Green design system and every 0.5 screen. Mock data. |
| **0.5** | 0.5 | App Store (release on approval) + external TestFlight beta, submitted Thu Nov 12 (N34) | Demo Day #2, Thu Nov 19 (live, or from TestFlight if review is slow) | Everything in "0.5 scope" below, on `masuno-prod`. |
| **0.6** | 0.5 | App Store, release on approval, Mon Nov 16 | Demo Day #3, Thu Dec 3 | Everything in "0.6 scope" below. |
| **1.0 beta** | 1.0 | TestFlight | Demo Day #3 (sneak peek) | 1.0 UI + notifications and synced Saved working end to end. |
| **1.0** | 1.0 | App Store, manual release | Product Launch, Wed Dec 16 | Everything in "1.0 scope" below. |

### 0.5 scope (submit Thu Nov 12 — N34)
**Must work live — the App Review checklist (§10.4); never cut:**
- School SSO sign-in ("Find my school" → "Continue with school account"); App Review test account, with the allowlisted password path as fallback; onboarding (Welcome → Location primer → Sign in to join (sheet) → Find your school → School sign-in (system web sheet) → You're verified → Set up profile, including the guidelines agreement → (1.0) Notification primer); suspended-account and update-required screens.
- Map from the database: pins with "Soon", popup, recenter, campus fallback when location is off or > 15 km away (reviewers aren't in Monterrey).
- Game form: add/edit with server validation; Where's the game? (search + current location); meet-up spot; cancel game.
- Event detail (all six states), join/leave with server-enforced capacity and optimistic UI, Who's going.
- Safety: report person or game, block/unblock, Blocked people, text filter, report alerts, bans.
- Settings: Location, Blocked people, Community guidelines, Privacy & Terms (live link, not "Coming soon"), Contact us, version, Sign out, **Delete account (really deletes)**.
- App icon; no placeholders, "coming soon" text, DEBUG menus, mock data or mock location in the Release build.

**Also in 0.5 (already built; cut to 0.6 in the order below if they aren't live on dev by Sat Nov 7 evening):** Me (Going, Hosting, Past), group chat (N14 — messaging if B20 + E26 land, otherwise read-only), bookmarks + Saved list on the phone (N15), Add to calendar, Invite a friend, Google Maps option, Edit profile & interests (N16), map search and sport filter, basic empty/error/offline states.

**Auto-repost (N17) is MVP:** the toggle, hosting-card line and bumped pin are built (E25), and the server bump is live (B3, PR #12). It still needs the two-phone check before the RC. It is not on the cut list, but the toggle can't ship as a dead setting.

**Group chat in 0.5 is the read-only hub** (N14, N34): the 0.5 RC has no composer. Messaging (B20 + E26) is built behind `app_config.chat_enabled`, which is off until the two-phone check passes on that project.

### 0.6 scope (submit Mon Nov 16)
- Fixes from App Review and the external beta.
- Anything cut from 0.5 (cut order below), turned back on once it's live on prod.
- **Group chat messaging** (B20 + E26, Appendix A items 1–4), only if two phones exchange messages on prod by the 0.6 RC; otherwise 0.6 keeps the read-only hub, and messaging moves to 1.0. The switch is `app_config.chat_enabled` on the server: off, the same build shows the read-only hub, so the decision needs no new build.
- **Invite a friend**: `AppConfig.appStoreID` was set on Nov 11.
- Prod migrations stay compatible with 0.5, since 0.5 is the build people have.
- Server-only fixes (B22, report alerts, demo campus) ship to prod as they're ready, with no app release.
- If 0.5 slips past Mon Nov 16, 0.5 and 0.6 become one submission.

### 1.0 scope
- **1.0 UI (§7.7, E27):** sport colors, court/field headers with the player lineup, "+1" open-spot tokens, sport-tinted pins/popups/Me cards/chat, rounded type, new copy ("Count me in", "Room for N more"), Settings icon tiles, form suggestion chips; plus 1.0-style frames for screens the Figma doesn't have yet (D2/D8).
- Notifications: a spot opened (Saved games), game changed, game cancelled, 30-min reminder, new game matching your interests, host updates; Notifications section in Settings; permission asked after the first join or hosted game.
- Saved synced to the account (B15), "Notify me if a spot opens" on full games.
- Spanish localization (strings, dates, sport names, notification text).
- Location picker drag-to-adjust; "Happening now" state; "changed since you joined" banner.
- "A spot opened" push to people who saved a game (pairs with auto-repost).
- Group chat messaging, if it missed 0.5 (B20, E26, Appendix A).
- Full accessibility pass; metrics view; fixes from 0.5 feedback.

### After the program (§13)
Chat push and retention, profile photos, calendar sync, name-visibility setting, dark mode, links that open a specific game, organizer approval, recurring games, non-sport activities, new campuses, own domain/email.

### Cut order if we slip
- **0.5 → 0.6**, decided at the Sat Nov 7 evening check and again at the Sun Nov 8 noon go/no-go: (1) Edit profile & interests; (2) group chat — first fall back to read-only (drop the composer and mock messages), then hide its entry points if even that isn't live; (3) Invite a friend; (4) Past games; (5) sport filter; (6) map search; (7) offline banner (keep retry). Hide cut features in the Release build — never ship a button that does nothing.
- **If sign-in, join or delete account isn't live on prod by Sun Nov 8 noon:** don't submit a mock build. Keep going and submit the day they're live (aim Tue–Wed Nov 10–11); hard backstop Mon Nov 16 together with 0.6. Demo Day #2 then shows the TestFlight build, labelled as beta. If only allowlisted accounts can sign in by then, R7-14 applies.
- **1.0** — (1) form suggestion chips and join animation (§7.7); (2) Google Maps option; (3) drag-to-adjust; (4) "changed since you joined" banner; (5) host-update notifications; (6) court art simplified to a plain sport-color band with the lineup tokens (keeps the rest of the 1.0 UI).
- **Never cut** anything on the App Review checklist.

---

## 4. Timeline

### 4.1 Key dates

The submission stays on **Mon Nov 9**. All remaining 0.5 work happens Fri–Sun Nov 6–8, so the backend, the data layer and the release candidate run in parallel all weekend.

| Date | Milestone | Exit check |
| --- | --- | --- |
| Sat Oct 31 → **overdue** | Access | Emilio is an Owner on the Supabase organization (O2); team Gmail exists (O3). Neither is confirmed — **must be done tonight (Thu Nov 5)**. |
| Sun Nov 1 | Kickoff | Repo ready (E0) ✅. §12 decisions and demo-day targets (O1) still open. |
| Tue Nov 3 | Rev. 6 | Frontend PRs merged ✅ (#5, #6). |
| Wed Nov 4 | ~~Contract freeze~~ · Build 0.1 | Contract missed → Fri Nov 6. UI pass merged ✅ (#7). 0.1 upload not confirmed (E6). |
| **Thu Nov 5** | **Demo Day #1** · Rev. 7 | Build 0.1 on a real phone. O2 + O3 done tonight. Rev. 7 shared in the team chat. |
| **Fri Nov 6** | **Contract freeze** (noon) · Dev up · **Go/no-go #1** (evening) | Noon: `docs/API.md` + E1 protocols, models and mocks merged. Evening: `masuno-dev` exists and seeds (B1); auth hook + review accounts on dev (B4); `GameStore` on mock repositories (B6); latency test (O5) and policy copy (O6) in; app icon (D3). Call: everyone confirms they can work the weekend (R7-1, R7-2). |
| **Sat Nov 7** | Backend core | Noon: `create/update/cancel/join/leave_game` + `game_cards` on dev (B3 part 1); a real Tec account signs in on dev (B2; ⚠ may need admin consent, K19); `masuno-prod` created (B12). Evening: report, block, text filter, demo campus, auto-repost on dev (B3 part 2); `AuthService` (B5) and live repositories (B7) working against dev; Privacy & Terms + Support pages live (D4); listing copy in App Store Connect (O7). **Evening check:** apply the cut order (§3). |
| **Sun Nov 8** | **Go/no-go #2** (noon) · Release candidate (evening) | Morning: SSO spike on a real iPhone (B21; ⚠ needs a real Tec account); safety backend (B8), delete-account (B9), migrations, Auth settings, demo campus + allowlisted accounts on prod; live wiring done (E24, E25, E14). **Noon:** on prod, the app signs in (R7-14 if only allowlisted accounts can), creates, joins, leaves, cancels, reports, blocks and deletes the account — or submission slips (§3). Afternoon: two-phone QA (`docs/QA.md`); screenshots (D7). Evening: Release build uploaded and sent to Beta App Review; §10.4 all green. |
| ~~Mon Nov 9~~ | ~~Submit 0.5~~ → Thu Nov 12 (program manager, N34) | Backend merged that day (PR #12). |
| **Tue Nov 10** | Prod set up | `masuno-prod` has the migrations, `delete-account`, auth hook, redirect URL, Azure provider, allowlisted accounts, demo campus games and keep-alive (B12) ✅. Release builds point at prod (E14) ✅. B7 in review (PR #13). |
| **Wed Nov 11** | Release candidate | Merge B7; SSO spike (B21); E25 two-phone check; app icon (D3) and Support page (D4) in; listing in App Store Connect (O7); two-phone QA on prod (`docs/QA.md`); screenshots (D7); RC uploaded and sent to Beta App Review. |
| **Thu Nov 12** | **Submit 0.5** | Must-haves pass on prod, or N20's slip rule applies (submit the day they do; backstop Mon Nov 16). Manual release if R7-14 applies. B22 live on prod before real students can sign in. |
| Nov 12–13 | In review | Rejection → reply and resubmit within 24 h. **Last resubmit to be live for Demo Day #2: Fri Nov 13.** External beta opens when Beta App Review clears and a real Tec account can sign in (O8, R7-14). |
| **Mon Nov 16** | Submit 0.6 | Review/beta fixes + anything cut from 0.5. **Also the hard backstop for 0.5** if it slipped on Sun Nov 8. |
| **Thu Nov 19** | **Demo Day #2** | 0.5 live (or TestFlight if review is still pending); first metrics. |
| Nov 25–27 | Thanksgiving break | No program sessions; light work only. |
| **Tue Dec 1** | 1.0 beta | 1.0 UI + notifications working in TestFlight. |
| **Thu Dec 3** | **Demo Day #3** | 0.x live; 1.0 beta shown. |
| **Tue Dec 8** | **Submit 1.0** | Manual release. |
| **Fri Dec 11** | 1.0 resubmit cutoff | — |
| **Mon Dec 14** | Release 1.0 | Or the moment it's approved, if later. |
| **Wed Dec 16** | **Product Launch** | 1.0 live; waitlist email sent; launch deck. |

**Weekend hour by hour (Fri Nov 6 – Sun Nov 8).** Both coders keep a shared note of what's live on dev, and nobody waits on a review for more than 4 hours.

| | Ethan | Emilio | Arianna | Ricardo |
| --- | --- | --- | --- | --- |
| **Fri** morning | E1 protocols + models + mocks; pair with Emilio on `API.md` | `API.md`; B1 `masuno-dev` + `supabase init` + seed | App icon (D3) | Venue list (O5); Tec IT questions (O4) |
| **Fri** afternoon/evening | `GameStore` on mocks (B6) | Auth hook + allowlist + review accounts (B4); register the Entra app so O4 can include its consent link (B2); start B3 tables | Website pages (D4) | Latency test (O5); policy + support copy (O6); go/no-go call |
| **Sat** morning | Run `AuthService` (B5) on dev: review password path once B4 is up, school sign-in once B2 is up | B3 part 1 (games RPCs, `game_cards`); finish the Azure provider (B2); create `masuno-prod` (B12) | D4 pages live | Listing copy (O7); a real Tec account for B2 (O4) |
| **Sat** afternoon/evening | Live repositories (B7) + live wiring (E24) | B3 part 2 (report, block, filter, demo campus, auto-repost, `game_activity`) | DD2 deck can wait — rest | Enter listing + URLs in App Store Connect; recruit beta testers (O8) |
| **Sun** morning | SSO spike with Emilio (B21); E24/E25 finish; release hygiene (E14) | SSO spike on a real iPhone (B21); safety alerts + bans (B8); delete-account (B9); migrations, Auth settings, demo campus and allowlisted accounts on prod | — | Moderation rota posted (O11) |
| **Sun** noon | **Go/no-go #2** — everyone | | | |
| **Sun** afternoon/evening | Two-phone QA; upload RC; Beta App Review | Fix what QA finds on the server side | Two-phone QA; screenshots (D7) | Two-phone QA |
| **Mon** | **Submit 0.5** (E15) | On call | — | — |

### 4.2 Week by week

Program weeks shown; the Wednesday Team Session doubles as our weekly sync.

| Week | Ethan (frontend + Swift data layer) | Emilio (Supabase) | Arianna (design) | Ricardo (outreach) |
| --- | --- | --- | --- | --- |
| **Done** (Oct 29–Nov 4) | Repo (E0); design system (E2); every 0.5 screen on mocks (E3–E13, E17, E19, E21); padel; iPad/Duo layout | — (nothing in the repo yet) | 1.0 UI in Figma (all five sport flows, group chat ×5, Me, Settings) + `DESIGN.md` v2.0 | Not confirmed |
| **Wk 7** (Nov 2–8) · DD1 Thu · **0.5 RC Sun** | 0.1 on TestFlight (E6); contract + protocols (E1); `GameStore` (B6); SSO screens (E5); `AuthService` (B5); live repositories (B7); live wiring (E24, E25); release hygiene (E14); RC + QA Sun | **Everything for 0.5, Fri–Sun:** dev setup (B1), auth hook (B4), Azure provider + Entra app (B2), schema/RPCs (B3), safety (B8), delete-account (B9), prod + demo campus (B12), SSO spike (B21) | DD1 deck (D5); app icon (D3) Fri; Privacy & Terms + Support pages (D4) Sat; screenshots (D7) + 0.5 design QA (D6) Sun | **O2 + O3 Thu night**; Tec IT questions + a real Tec account (O4), venues + latency test (O5), policy copy (O6) Fri; listing (O7) Sat; kickoff decisions + targets (O1) |
| **Wk 8** (Nov 9–15) · **submit 0.5 Thu** | Merge B7; RC Wed; submit 0.5 Thu (E15); answer review; chat messaging (E26) and 0.6 fixes; start 1.0 UI (E27: tokens, pins, popup, Me cards) | SSO spike (B21), tenant check (B22), report webhook, backups; fixes from review; chat backend (B20) for 0.6 | Resolve 1.0 conflicts (D12) Wed; start 1.0 frames for missing screens (D2/D8) | Beta testers once Beta App Review clears (O8); moderation (O11) |
| **Wk 9** (Nov 16–22) · submit 0.6 Mon · DD2 Thu | Submit 0.6 Mon; 1.0 UI: court headers, detail, chat, Who's going (E27) | 1.0 backend start: notification backend (B13) | DD2 deck (D5); 1.0 frames for missing screens (D2/D8) by Sun; 1.0 tokens as Figma variables (D13) | Beta + real games (O8, O9); DD2 numbers (O10) |
| **Wk 10** (Nov 23–29) · Thanksgiving | 1.0: notification screens (E16), Saved sync (E17), restyle onboarding/safety/states from D2 frames (E27) | `send-push` (B14), Saved backend (B15), `NotificationService` (B16) | Design QA of 0.x release | Spanish translation (O12); beta feedback summary (O8) |
| **Wk 11** (Nov 30–Dec 6) · DD3 Thu | 1.0 beta Tue; Spanish (E18), picker drag + banner (E20), 0.x fixes | Metrics (B17), Spanish notifications (B18), 0.x fixes | DD3 deck (D5); 1.0 design QA (D6); Spanish layout check (D9) | DD3 story + numbers (O10) |
| **Wk 12** (Dec 7–13) | Accessibility + tests (E22); submit 1.0 Tue (E23) | Notification tests, prod checks (B19) | 1.0 screenshots (D7); launch deck (D5) | Launch-week games (O9); PR/FAQ final; launch plan (O13) |
| **Wk 13** (Dec 14–16) | Release 1.0 Mon | On call | Product Launch | Waitlist email + launch posts (O13); on call |

```mermaid
gantt
  title masUNO releases through Product Launch (rev. 7)
  dateFormat YYYY-MM-DD
  axisFormat %b %d
  section Program
  Demo Day 1              :milestone, 2026-11-05, 0d
  Contract freeze         :milestone, 2026-11-06, 0d
  Go/no-go 2              :milestone, 2026-11-08, 0d
  Submit 0.5              :milestone, 2026-11-12, 0d
  Submit 0.6              :milestone, 2026-11-16, 0d
  Demo Day 2              :milestone, 2026-11-19, 0d
  Demo Day 3              :milestone, 2026-12-03, 0d
  Product Launch          :milestone, 2026-12-16, 0d
  section Builds
  0.1 prototype           :done, 2026-10-29, 2026-11-05
  0.5 backend wiring RC   :crit, 2026-11-06, 2026-11-12
  0.5 in App Review       :2026-11-12, 2026-11-19
  0.6 fast follow         :2026-11-10, 2026-11-16
  1.0 build               :2026-11-10, 2026-12-08
  1.0 in App Review       :2026-12-08, 2026-12-14
  section Ethan
  0.5 screens on mocks    :done, 2026-10-29, 2026-11-05
  Data layer wiring RC    :crit, 2026-11-06, 2026-11-09
  0.6 and 1.0 UI          :2026-11-10, 2026-12-08
  section Emilio
  Supabase for 0.5        :crit, 2026-11-06, 2026-11-09
  Tests CI fixes          :2026-11-09, 2026-11-15
  Notifications backend   :2026-11-16, 2026-12-08
  section Arianna
  1.0 UI in Figma         :done, 2026-11-01, 2026-11-05
  Icon pages screenshots  :crit, 2026-11-06, 2026-11-09
  1.0 frames for gaps     :2026-11-10, 2026-11-22
  Decks and design QA     :2026-11-16, 2026-12-16
  section Ricardo
  Access copy listing     :crit, 2026-11-05, 2026-11-08
  Beta testers and games  :2026-11-09, 2026-12-01
  Launch outreach         :2026-12-01, 2026-12-16
```

---

## 5. Work split

For 0.5, everything in Swift is Ethan's (screens and the data layer); everything in `supabase/` is Emilio's. The contract in §8.5 (`docs/API.md`) and the Swift repository protocols (E1) are the interface. Ethan and Emilio review each other's PRs; Arianna reviews screenshots in PRs that change a screen.

**Status:** as of Tue Nov 10, from the repo (`main` @ `8e2c90e`, PR #13), both Supabase projects and Trello. Arianna's and Ricardo's rows only show what's visible in the repo, on the website or on Trello. "Not confirmed" means nothing visible yet, so the owner should update Trello.

### 5.1 Ethan — frontend + Swift data layer

| ID | Work | Release | Est. | Due | Status | Done when |
| --- | --- | --- | --- | --- | --- | --- |
| E0 | Repo setup (§6). | 0.1 | 2 h | Nov 1 | **Done** (#4) | Emilio clones, builds and opens a PR blocked until Ethan approves. |
| E1 | **Contract + domain models** with Emilio: `Profile`/`PersonSummary`, `Activity`, `Place`, `Game`, `DomainError`; `AuthService`, `GameRepository`, `ProfileRepository`, `SafetyRepository`, `AppConfigRepository` protocols + mocks. | 0.5 | 3 h | **Fri Nov 6 (noon)** | **Done** (#9); sign-in amended by N33 (E5, B5) | Protocols merged; B3 and B5–B7 build against them. |
| E2 | Green design system (§7.1); colors in the asset catalog; String Catalog; DEBUG gallery. | 0.1 | 6 h | Nov 4 | **Done** (#5, #7) | No hard-coded colors in views. |
| E3 | Navigation shell (§7.3) + update-required + suspended screens; `masuno://game/<id>`. | 0.1 | 2 h | Nov 4 | **Done** | All routes reachable. |
| E4 | Map + popup redesign (341:1979, 341:2046), incl. iPad / iPhone Duo layout. | 0.1 | 5 h | Nov 4 | **Done** (#5, #7) | Matches the frames on mock data. |
| E5 | Onboarding (§7.5) + suspended screen; **replace the Email and Code screens with the SSO screens (N33), +3 h**. | 0.5 | 4 h + 3 h | Sat Nov 7 | **Built**; review-account sign-in works on `masuno-dev` (#13); school sign-in untested (B21) | Signs in for real once B5 lands; Debug's mock backend signs in without the web sheet; `ContractTests` and the README's `-screen` names match the new steps. 1.0 restyles it from D2 frames. |
| E6 | Build 0.1 to TestFlight. | 0.1 | 1 h | Nov 5 | **Not confirmed** | On TestFlight for Demo Day #1. |
| E7 | Game form add/edit/cancel, validation. | 0.5 | 6 h | — | **Built** | Create/edit/cancel round-trip on `masuno-dev` (via E24). |
| E8 | Where's the game?: search + current location. | 0.5 | 3 h | — | **Built** | Spot set by search or by location. |
| E9 | Live map: location prompt, campus fallback (> 15 km) + banner, tap "N games nearby" to refresh (N31); remove the mock location. | 0.5 | 3 h | Sun Nov 8 | **Built**: real location, campus fallback, denied banner; mock location is DEBUG-only; real games on dev with B7 (#13, in review) | Map shows real games; App Review (far away) lands on campus. |
| E10 | Event detail (§7.6.4). | 0.5 | 7 h | — | **Built** | Each state reachable with DEBUG launch arguments; last-spot race shows the right message on two phones. |
| E11 | Safety screens (§7.6.6). | 0.5 | 5 h | — | **Built** | Blocked person's games and name vanish without refreshing. |
| E12 | Me: Going, Hosting. | 0.5 | 4 h | — | **Built** | Matches 341:2165/341:2240 (0.5 version). |
| E13 | Settings + Delete account. | 0.5 | 2.5 h | Sun Nov 8 | **Built**; Privacy & Terms opens the live D4 page; `delete-account` is deployed on dev and prod; check on a phone | Delete account signs you out and the account is gone. |
| E14 | **States + release hygiene**: empty/error/offline basics; app icon; launch color; Release → prod; DEBUG-only demo tools (`-screen`, gallery, `simulateDropOut`); **remove "Coming soon" text, the disabled chat composer (unless E26), the App Store search invite link, the mock location** (N27); hide cut features. | 0.5 | 3 h | Sun Nov 8 | **Built**, with the app icon (D3), `AppConfig.appStoreID` and the privacy manifest in on Nov 11. Release → prod done Nov 10 (local `Config.xcconfig`; archive from Ethan's Mac or copy the values from the password manager) | Release build has no DEBUG menus, mock data, placeholder text or dead buttons; airplane mode never strands a screen. |
| E15 | Submit 0.5: set `AppConfig.appStoreID` from the App Store Connect app record (the ID exists before approval, so Invite a friend can ship); privacy label, age rating, review notes; Ricardo enters the listing (O7). | 0.5 | 2 h | ~~Mon Nov 9~~ → **Thu Nov 12** (N34) | To do | 0.5 submitted. |
| B5 | **`AuthService` (Swift)** — *moved to Ethan (N21)*: add the supabase-swift v2 package (not in `project.yml` yet); school sign-in with `signInWithOAuth` (§8.4, N33), `sso_provider` → provider for Azure and Google, review password path, callback errors, the Swift changes listed in `docs/API.md`, session persistence, expired-session and suspended detection, `complete_profile` + `accept_guidelines`. Run it on dev with `-liveAuth YES`. | 0.5 | 4 h | Sat Nov 7 | **Done** (#11): the review password path signs in on `masuno-dev` (#13); the school path is checked in B21 | Onboarding signs in for real on `masuno-dev`. |
| B6 | **`GameStore` (Swift)** — *moved to Ethan (N21)*: `@Observable`, `LoadState`, optimistic join/leave + rollback, error-code → `DomainError`, instant local hiding after a block; replaces `EventStore`; remove `SkillLevel`, `Venue`, `Person.you`. | 0.5 | 5 h | Fri Nov 6 | **Done** | Store unit tests green on mock repositories. |
| B7 | **Live repositories** (`supabase-swift` v2) — *moved to Ethan (N21)*: games, profiles, safety; `ActivityCatalog` cached with a built-in fallback of the 5 sports. | 0.5 | 6 h | Sat Nov 7 | **Built**, PR #13 in review (CI green); `LiveIntegrationTests` pass on `masuno-dev` | Mock ↔ live is a one-line switch. |
| E24 | **Live wiring**: move screens onto E1 models + `GameStore`/`AuthService`; delete `EventStore`/`MockData` from Release; group chat on live data — messaging if B20 + E26 land, otherwise the read-only fallback (N14); Saved persisted on the phone (N15). | 0.5 | 6 h | Sun Nov 8 (morning) | **Built**; every 0.5 screen checked on `masuno-dev` in the simulator (#13); real phone to do | Every 0.5 screen works on `masuno-dev` with no mock data. |
| E25 | **Auto-repost** (N17): form toggle, hosting-card line, bumped pin ("Spot open", drawn on top for 2 h); wired to `auto_repost` / `reposted_at`. | 0.5 | 1.5 h | Sun Nov 8 | **Built** (toggle, "Reposted …" line, bump pin); server half live (#12); two-phone check open | Player leaves a full game → host card shows "Reposted just now" and the pin is bumped on another phone. |
| E26 | **Group chat messaging** (N14; moved to 0.6 by N34): send with optimistic insert + retry, live updates, unread counts, text filter, report a message. | 0.6 | 4 h | 0.6 RC (Sun Nov 15) | **Built** (Nov 10): messages, composer, optimistic send with retry, live channel plus a 15 s check, unread counts, report and block from a message; tested on mocks. Two phones on dev and prod to do | Two phones exchange messages on prod — or the RC has no composer. |
| E19 | Add to Calendar, Invite a friend, Google Maps option. | 0.5 | 2.5 h | — | **Built**; `AppConfig.appStoreID` set Nov 11, so Invite a friend shows in Release | Calendar editor opens prefilled with no permission prompt; invite shares the app's App Store link. |
| E21 | Me: Past games + Edit profile & interests. | 0.5 | 3 h | — | **Built** on the live `ProfileRepository` (#13) | Edited interests save and reload from the server. |
| E17 | Saved: local list (0.5) **built**; sync + Notify me (1.0). | 0.5 / 1.0 | 1.5 h | Nov 29 | Local version **built** | Saved survives reinstall; Notify me works. |
| | *0.5 remaining (Nov 10): B7 review fixes 0.5 h, E25 check 0.5 h, SSO spike 1 h, real-phone smoke test on prod 1 h, two-phone QA + RC 2 h, E15 2 h* | | *~7 h; E26 (4 h) in 0.6* | | *~75 h already built* | |
| E27 | **1.0 UI pass** (§7.7, N23): 1.0 tokens + rounded type (2 h); sport colors on pins, popup with tail, "+1" tokens (2 h); court/field headers ×5 with the lineup and "Room for N more" (4 h); Me cards + profile band (1.5 h); chat sport band, bubbles, join pill (1.5 h); Who's going rows, Settings icon tiles, form suggestion chips, copy (1 h); restyle onboarding/safety/states from D2 frames. | 1.0 | 12 h | Tue Dec 1 (start Nov 10) | — | 1.0 beta matches the 1.0 frames (or differences noted by Arianna). |
| E16 | Notification screens. | 1.0 | 3.5 h | Nov 29 | — | Tapping each notification type opens the right game. |
| E18 | Spanish. | 1.0 | 2 h | Dec 4 | — | Whole app readable in Spanish. |
| E20 | Picker drag + "Happening now" + changed banner. | 1.0 | 3.5 h | Dec 5 | — | Drag sets a spot; banner shows after a host edit. |
| E22 | Accessibility + UI tests. | 1.0 | 4 h | Dec 7 | — | Core loop with VoiceOver at XXL text. |
| E23 | 0.x fixes + 1.0 submission. | 1.0 | 3 h | Dec 8 | — | 1.0 submitted. |
| | **Ethan remaining** | | **0.5 ~7 h · 0.6 ~4 h (E26) · 1.0 ~30 h · ≈ 41 h** | | | |

### 5.2 Emilio — backend (Supabase)

**Nov 10:** the 0.5 backend is in `main` (PR #12) and on both projects (prod set up by Ethan, B12). What's left for 0.5 is school sign-in (finish B2 with the B21 spike, then the B22 tenant check), report alerts (B8) and backups. Chat (B20) moves to 0.6 (N34). The Swift data layer (B5–B7) is Ethan's (N21). If something won't make its slot, say so in the team chat the same day.

| ID | Work | Release | Est. | Due | Depends on | Status | Done when |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B1 | **Supabase dev setup**: `masuno-dev`, CLI, `supabase init` in `supabase/`, seed script (Tec, with `short_name` 'Tec', `sso_provider` 'azure' and `signup_enabled` on (N32, N33); **5 sports incl. padel**, Ricardo's venues, test users, games), `Config.xcconfig` values for dev. | 0.5 | 3 h | **Fri Nov 6 (morning)** | O2, O5 | **Done** (#12) | `supabase db reset` works locally for Ethan too. |
| — | **`docs/API.md`**: table names, RPC signatures, error codes (§8.5), agreed with Ethan's E1. | 0.5 | (in B3) | **Fri Nov 6 (noon)** | E1 | **Done** with E1, in PR #9 (N30, N32) | Merged; both coders approve. |
| B4 | **Auth hook changes for SSO** (§8.4, N33): deny by default, check the provider and the server-side email; `auth_allowlist`; 3 allowlisted password accounts on the demo campus (2 for App Review, 1 for QA's third phone). `sign_in_method` is gone. | 0.5 | 2 h | Fri Nov 6 (evening) | B1 | **Done** (#12; pgTAP-tested; on prod Nov 10, where an outside address and an `@tec.mx` password sign-up are both refused). The tenant check is B22 | Called with sample payloads, the hook refuses a non-campus address and a password sign-up on an `@tec.mx` address; a review account signs in with a password. |
| B2 | **Entra app + Azure provider** (§8.4, §10.1, N33). Register first: multi-tenant app without personal accounts, Supabase callback URLs for both projects, minimum scopes, `email` and `xms_edov` claims, client secret; give Ricardo the client ID and admin-consent link for O4. Then turn on Supabase's Azure provider (tenant per §8.4) and add `masuno://auth-callback` to Redirect URLs in `masuno-dev` and `masuno-prod`. | 0.5 | 1.5 h | Registered Fri Nov 6 (evening); done Sat Nov 7 (morning) | A real Tec account from O4 for the last check (⚠ K19) | **In progress**: the Azure provider is on in dev and prod (tenant `organizations`, N35), and both redirect to Microsoft; no real Tec sign-in yet; confirm the Entra app lists prod's callback URL | A real Tec account signs in on dev, or Microsoft's page shows that admin consent is needed (K19); a personal Microsoft account and another organization's account are refused. |
| B3 | **Schema, RLS, RPCs** (§8.3–§8.5). Part 1 by **Sat Nov 7 noon**: tables, `game_cards`, `my_profile` with campus fields, `university_lookup` (N32, N33), `create/update/cancel/join/leave_game`. Part 2 by **Sat Nov 7 evening**: report/block, text filter, demo campus + daily refresh, **auto-repost** (`auto_repost`, `reposted_at` in `leave_game`/`update_game`), `game_activity` table for chat system rows (N30). | 0.5 | 14 h | Sat Nov 7 noon / evening | E1, B1 | **Done** (#12) | Every 0.5 RPC works from the SQL editor as a test user. |
| B8 | **Safety backend**: report-alert webhook to team chat, bans (`banned_at` rejected in every write RPC). (Instant local hiding is in Ethan's B6.) | 0.5 | 2.5 h | Sun Nov 8 (morning) | B3, O1 (chat pick) | **Built** (#12): bans block every write; the report-alert trigger is in, and the Discord webhook is set up on both projects (`supabase/README.md` step 6) | Report alert arrives within a minute; banned user's writes fail. |
| B9 | **`delete-account` Edge Function.** | 0.5 | 2 h | Sun Nov 8 (morning) | B3 | **Done** (#12; deployed on dev and prod). Hosted games are now deleted along with the account, not cancelled | Deleting cancels hosted games and frees joined spots. |
| B12 | **Prod project**: latency test (Ricardo, Fri Nov 6), create `masuno-prod` (Sat), migrations, Auth settings migrations don't carry (Azure provider, tenant lock, Redirect URLs, auth hook), demo campus + allowlisted accounts (Sun morning), keep-alive + weekly backup (§8.1). | 0.5 | 1.5 h | Sat Nov 7 / Sun Nov 8 | B3, O5 | **Done** Nov 10 (Ethan): `masuno-prod` in `us-east-1`; migrations, `delete-account`, hook, redirect URL, Azure provider, 3 allowlisted accounts, demo campus (6 games, daily refresh on), keep-alive secrets (run green). **Left:** weekly `supabase db dump` | A TestFlight build runs on prod. |
| B21 | **SSO spike:** one real Tec account signs in on a physical iPhone end to end (sheet → callback → auth hook → profile). Check the alert behavior and the email claim. Pair with Ethan, who owns the Swift side. | 0.5 | 1 h | Sun Nov 8 (morning), before the RC and external beta | B2, B4, B5, a real Tec account from O4 (⚠ K19) | To do; only the Tec account is missing. Also record the hook payload's tenant field for B22 | The "Confirm on a device" list in §8.4 is filled in with what happened. |
| B22 | **Hook tenant check** (N35): for an Azure sign-up, read the tenant ID from the token (the `tid` claim, or the issuer `https://login.microsoftonline.com/<tid>/v2.0`, whichever B21 shows the hook receives) and require it to equal the campus's `universities.tenant_id`; refuse if it's missing or different. Set Tec's `tenant_id` to `c65a3ea6-0f7c-400b-8934-5a6dc1705645` (O4 confirms it). New migration + pgTAP cases. | 0.5 | 1.5 h | Before real students can sign in on prod (R7-14) | B21 | To do | A sign-up from another tenant with an `@tec.mx` email is refused; a real Tec account gets in. |
| B20 | **Chat v1 backend** (N14; moved to 0.6 by N34; Appendix A items 1–4). | 0.6 | 5 h | Sat Nov 14 | B3 | **Built** (Nov 10, migration `20261110000000_group_chat`); pgTAP tests pass; applied to `masuno-dev` with chat on (Nov 10); not on prod yet | Two members exchange messages on dev; non-members can't read them. |
| | *0.5 left (Nov 10): B21 1 h, B22 1.5 h, report webhook 0.5 h, backup 0.5 h* | | *~3.5 h; B20 (5 h) in 0.6* | | | | |
| B10 | **Database tests** (pgTAP): last-spot race, RLS visibility, blocks, bans, posting window, auth hook (provider and domain rules). | 0.5 | 2 h | Thu Nov 12 | B3 | **Built** (#12): auth hook, game rules, RLS, blocks, bans, reports and deletion in `supabase/tests/database`; green in CI. The last-spot race stays a two-phone check (`docs/QA.md`) | A deliberately broken policy fails CI. |
| B11 | **CI** (GitHub Actions): iOS build + unit tests, plus the database tests. | 0.5 | 1.5 h | Thu Nov 12 | E0 | **Built**: `database.yml` (#12) and `ios.yml` (#13, green). `main` requires a review but no status checks yet, so Ethan still has to add both as required checks | Ethan adds it as a required check on `main`. |
| B13 | Notification backend: device tokens, preferences, outbox, 1-min drain job, 5-min reminder job, interest matches (max 2/day), changed/cancelled, host updates. | 1.0 | 8 h | Nov 28 | — | — | Each row of §8.7 produced by the right trigger. |
| B14 | `send-push` Edge Function (APNs token auth, collapse per game, invalid-token cleanup). | 1.0 | 4 h | Nov 29 | APNs key | — | Test push reaches a TestFlight build from prod. |
| B15 | Saved backend: `bookmarks`, `toggle_bookmark`, spot-opened fan-out, repository calls. | 1.0 | 1 h | Nov 28 | B13 | — | Leaving a full game queues a notification for everyone who saved it. |
| B16 | `NotificationService` (Swift): token registration, preferences repository. | 1.0 | 1.5 h | Nov 28 | B13 | — | Token appears in `device_tokens` after permission. |
| B17 | Metrics view + moderation SQL snippets. | 1.0 | 2 h | Dec 2 | — | — | "How many sign-ups yesterday?" is one query. |
| B18 | Spanish on the server. | 1.0 | 1.5 h | Dec 4 | O12 | — | Spanish phones get Spanish notifications. |
| B19 | Notification tests + 0.x fixes + prod checks. | 1.0 | 6 h | Dec 8 | — | — | Triggers covered by pgTAP; prod migrations applied before 1.0 release. |
| | **Emilio remaining** | | **0.5 ~3.5 h · 0.6 ~5 h (B20) · 1.0 24 h · ≈ 33 h** | | | | |

**Pairing rule (rev. 7):** Ethan and Emilio pair Fri Nov 6 morning to freeze `API.md` against E1, and again Sat Nov 7 on the first live `supabase-swift` call (B7 against B3 part 1) and Sun Nov 8 on the SSO spike (B21). Ethan builds B6 on mocks Friday, so nothing he does waits on Emilio until B5/B7 on Saturday. Both keep a shared "live on dev" list in the team chat.

### 5.3 Arianna — design

| ID | Task | For | ~Hours | Due | Status |
| --- | --- | --- | --- | --- | --- |
| D1 | Finalize the green system + token table. | 0.1 | 3 | Nov 1 | **Done in effect** — 0.5 tokens are in code (§7.1); superseded for 1.0 by `DESIGN.md` v2.0 (Trello card still open — close it) |
| — | **1.0 UI in Figma**: five sport flows (map, popup, game details, You're in, Who's going), Add game, group chat ×5 + Chat rules + Edit meet-up, Me, Settings; `DESIGN.md` v2.0. | 1.0 | — | Nov 5 | **Done** (§7.7) |
| D3 | **App icon** (1024 × 1024, no transparency) + launch-screen color. In the 1.0 style is fine — it ships in 0.5. | 0.5 | 2 | ~~Fri Nov 6~~ → **Wed Nov 11** (RC) | **Done** (Nov 11): 1024 × 1024 icon in the asset catalog; launch color uses `Background` |
| D4 | **Website pages** on `masuno-app.github.io`: Privacy & Terms and Support, using Ricardo's copy (O6). Can use the 1.0 web tokens (`DESIGN.md` §9). | 0.5 | 3 | ~~Sat Nov 7~~ → **Wed Nov 11** | **Done** (Nov 11): `masuno-app.github.io/privacy` and `/support` are both live |
| D5 | Deck design for Demo Days #1–#3 and the Product Launch (Ricardo writes the story). DD3 and Launch decks show the 1.0 UI. | DD1–Launch | 6 | Nov 5, Nov 19, Dec 3, Dec 16 | DD1 not confirmed |
| D6 | **Design QA**: 0.5 RC against the green `341:*` frames and §7 (Sun Nov 8); 1.0 beta against §7.7 frames (Dec 2); Trello bugs with screenshots; screenshot review in UI PRs. | All | 1.5 per build | Nov 8, Dec 2 | — |
| D7 | **App Store screenshots** (6.9") from the release candidate — 0.5 UI for 0.5; redo in the 1.0 UI for 1.0. Real Monterrey venues only (no San Francisco map or "[Padel venue near Tec]" placeholders). | 0.5 / 1.0 | 3 | ~~Sun Nov 8~~ → **Wed Nov 11** / Dec 8 | To do |
| D12 | **Resolve 1.0 conflicts** (§7.7.6): agree defaults for R7-4…R7-10 and R7-15 with Ricardo and update the Figma (e.g. Who's going rows, Settings rows, "Cancel game", no "· Read", no mic glyph). | 1.0 | 1 | Wed Nov 11 | To do |
| D2 + D8 | **1.0-style frames for screens the Figma doesn't have yet** (N25): onboarding (Welcome → Location primer → Sign in to join (sheet) → Find your school → School sign-in (system web sheet; iOS and the school own it, so it's in the flow but not drawn) → You're verified → Set up profile → (1.0) Notification primer) + update-required + suspended; Event detail Full / Hosting / Ended / Cancelled; report sheet, block dialog, Blocked people; empty/error/offline; group chat read-only variant; Saved list + empty state; Notifications settings; Notify me; "Happening now"; "changed since you joined" banner; picker drag; **auto-repost toggle, hosting-card line and bumped pin (D11)**. | 1.0 | 8 | **Sun Nov 22** | In progress: Sign in to join and Find your school are drawn |
| D13 | **1.0 tokens as Figma variables** + hand-off table for E27 (sport colors, person colors, radii, glass recipes — §7.7.2). | 1.0 | 1 | Fri Nov 20 | Partly done (in `DESIGN.md`) |
| D9 | Spanish layout check: long strings, truncation, buttons. | 1.0 | 1 | Dec 4 | — |
| D10 | *Optional:* small SwiftUI PRs (spacing/color tweaks found in design QA), reviewed by Ethan. | — | — | Any time | — |

### 5.4 Ricardo — team lead & outreach

| ID | Task | For | ~Hours | Due | Status |
| --- | --- | --- | --- | --- | --- |
| O1 | **Kickoff as team lead**: sign off §12 (rev. 6 + rev. 7) decisions; set demo-day targets; pick the report-alert chat. | All | 1 | **Fri Nov 6** | In progress (Trello) |
| O2 | **Supabase access**: add Emilio as Owner of the organization (or transfer it). | 0.5 | 0.5 | **Tonight, Thu Nov 5** — overdue, blocks B1 | Not confirmed |
| O3 | **Team Gmail** with 2-step verification; shared password manager. | 0.5 | 0.5 | **Tonight, Thu Nov 5** — overdue; needed for Contact us and review accounts, no longer blocks sign-in (N33) | **Done in effect**: `official.masuno.app@gmail.com` is Contact us and the review-account base; Ricardo confirms 2-step verification and the password manager |
| O4 | **Tec IT questions (N33):** confirm Tec uses Microsoft 365; get Tec's tenant ID confirmed (public lookup, Nov 6: `c65a3ea6-0f7c-400b-8934-5a6dc1705645`); confirm whether Tec IT must grant admin consent for the masUNO Entra app, and send IT the consent link from B2 if so; ask whether MFA, location or managed-device rules apply; request 2–3 test student accounts (one for App Review, usable by a reviewer abroad, without MFA if IT allows). Still check whether staff share `@tec.mx` (K12). **Separately, line up one real Tec student to try sign-in on dev (B2, B21); that doesn't need IT to reply.** | 0.5 | 1 | Fri Nov 6 — ⚠ ask today, but the answer depends on Tec IT (K19) | Not confirmed |
| O5 | **Venue list** (10–15 real places near Tec, incl. padel) for seed data and the demo campus; **latency test** from a phone in Monterrey. | 0.5 | 2 | Fri Nov 6 (both) | Not confirmed |
| O6 | **Policy + support copy** from §10.2; Emilio checks every data claim. | 0.5 | 2 | **Fri Nov 6** | Not confirmed |
| O7 | **App Store listing**: name, subtitle, description, keywords, promo text, support/privacy URLs, entered in App Store Connect. Describes only what that version does — mention group messaging only if B20 shipped in that build. | 0.5 / 1.0 | 2 | ~~Sat Nov 7~~ → **Wed Nov 11** / Dec 7 | Not confirmed |
| O8 | **Beta**: recruit 15–30 Tec students; manage the external TestFlight group once Beta App Review clears the 0.5 RC (~Nov 10); feedback form; weekly summary. | 0.5 | 5 | Nov 8 – Dec 1 | To do |
| O9 | **Hosts & real games**: 2–3 real games in beta week (by DD2) and launch week; short clip for the decks. | DD2–Launch | 4 | Nov 19, Dec 16 | To do |
| O10 | **Demo-day stories, scripts and numbers.** DD2 shows the App Store build, or TestFlight if review is still pending. | DD1–Launch | 6 | Nov 5, Nov 19, Dec 3, Dec 16 | DD1 not confirmed |
| O11 | **Moderation rota** with Arianna, from the Nov 8 RC (App Review may test reports). | 0.5 onward | 10 min/day | From Nov 8 | To do |
| O12 | **Spanish translation** of the String Catalog export, incl. 1.0 copy (§7.7.5). | 1.0 | 3 | Nov 29 | — |
| O13 | **Launch**: waitlist email, social posts, program deliverables, February campus-launch plan. | Launch | 5 | Dec 16 | — |

---

## 6. How we work

- **Repo:** `masUNO-app/ios` — `MasUno/` (app), `supabase/` (migrations, functions, tests, seed), `docs/` (this spec, `API.md`, `QA.md`). Rev. 7 replaces `docs/SPEC.md`.
- **Code ownership:** `MasUno/Views`, view models, design system → Ethan. `MasUno/Data` → Ethan for 0.5 (N21; Emilio reviews), both from 1.0. `supabase/` → Emilio. `CODEOWNERS` requests both on `MasUno/Data/`.
- **Branches:** `main` protected; short-lived branches; one approving review from the other coder; squash merge; review within 24 h — **within 2 h during Fri–Sun Nov 6–8**.
- **Contract first:** `docs/API.md` and the Swift protocols are the boundary; a change to either is one PR reviewed by both coders.
- **Migrations:** never edit an applied migration; only Emilio pushes to prod, only from `main`, before the matching TestFlight build.
- **Environments:** Debug → `masuno-dev`; TestFlight and App Store → `masuno-prod` from the 0.5 release candidate (beta games are real games).
- **Design hand-off:** 0.x screens follow what's built and the green `341:*` frames; 1.0 screens follow §7.7 and the 1.0 frames marked "Ready". If a 1.0 frame isn't ready, Ethan builds from `DESIGN.md` and Arianna adjusts in design QA.
- **Done means:** check in §5 met · strings in the catalog · run on a real phone · reviewed · CI green (once B11 exists) · (screens) screenshot approved by Arianna.
- **Cadence:** Wednesday Team Session = weekly sync (demo on a phone, hours vs §5, cut decisions, beta feedback). **Extra calls: go/no-go #1 Fri Nov 6 (evening), cut check Sat Nov 7 (evening), go/no-go #2 Sun Nov 8 (noon).**
- **Trello** (board "2026 UnaMas"): rename the 0.5 list to **"MVP · 0.5 — submit Mon Nov 9"**; re-date each card to §5; move B5–B7 cards to Ethan; close D1, open E27, D12, D13 and the merged D2 + D8 card. A card is **Done** only when its "Done when" is true in the repo (E1 was marked Done early). Every card title starts with its owner's name and carries the owner's role label (Frontend = Ethan, Backend = Emilio, Design = Arianna, Marketing = Ricardo), plus a due date from §5. Each person clicks **Join** on their own cards.
- **Secrets:** team Gmail, review-account passwords, the Entra client secret and the APNs key live in the shared password manager — never in the repo or a chat.

---

## 7. Product specification

### 7.1 Design system — 0.5 UI, green theme (as built, E2)

These are the tokens in the asset catalog today (0.5 and 0.6). The 1.0 tokens are in §7.7.2.

| Token | Hex | Use |
| --- | --- | --- |
| `accent` | `#12815A` | Primary buttons, toggles, check badges. White label, 4.9:1. |
| `accentSoft` | `#DDF1E8` | Secondary buttons, status chips, initials avatars, segmented track. |
| `background` | `#F5F4F7` | Screens and sheets. |
| `card` | `#FDFCFE` | Cards, grouped rows, popups. |
| `ink` | `#1F2638` | Titles and body. |
| `muted` | `#5F5C68` / `#73707B` | Secondary text; `#73707B` only for ≥ 18 pt or ≥ 14 pt bold. |
| `pin` | `#2F6FE0` | Map pins only. |
| `destructive` | `#C23B34` | Cancel game, Sign out, Delete account. |
| `error` | `#CB3D3D` | Field errors. |
| `chipSport` | `#DCE4F4` | Interest chips. |

Cards 16–20 pt radius with hairline border; pill buttons ~50 pt; boxed fields with caption labels; Liquid Glass on floating controls. SF Pro, sentence case, light mode only.

### 7.2 Copy & voice

| Concept | Use | Instead of |
| --- | --- | --- |
| Thing you host/join | **game** — Add game, Edit game, Join game, Cancel game | event |
| Sport field | **Sport** | Activity |
| Capacity | **Players** — "6 players" (helper "Including you"); edit "6 players · 3 going" | Spots |
| Status | "3 going · 3 spots left", "1 spot left", "Full" | "2/3 \| 1 Spot left" |
| Names | "Emilio G." for others; full name only on your own Me card | full names |
| Cancel dialog | "Cancel After-work hoops?" / "We'll let the 3 people who are going know." / "This can't be undone." / **Cancel game** / **Keep game** | Delete event |
| Leave | **Leave** → **Leave game** | Give up your spot |
| Bottom bar | **+ Add game** | + Add event |
| Before you go (0.5) | "Alex can see you joined. Say hi in the group chat so people know to wait for you." — if group chat falls back to read-only (N14), use "Alex can see you joined. Check where to meet and who's going." | — |
| Before you go (1.0) | …+ "We'll remind you 30 min before." | — |
| Group chat (0.5) | Button **Group chat**, with no count and no composer in the read-only chat (N14). With E26: "Group chat · 2 new" and composer "Message" | — |
| Saved | **Saved** list; bookmark **Bookmark** / **Remove bookmark** | Bookmarked |
| Validation | Hint "Give it a real name, not just the sport"; "Add a name so people know what they're joining."; "9:00 AM has already passed today. Pick a later time." | — |

### 7.3 Navigation

```
Launch → version check → session?
├─ None → Onboarding (§7.5)
├─ Suspended → "Your account is suspended" + support email
└─ Signed in → Map
     ├─ Search · Saved → Event detail
     ├─ Pin → Popup (bookmark) → Details / Join game → Event detail
     ├─ Filter · Recenter (above the avatar) · + Add game → Game form → Where's the game?
     └─ Avatar → Me
          ├─ Gear → Settings → Blocked people · Community guidelines · Privacy & Terms · Delete account
          ├─ Edit profile & interests
          ├─ Going → Event detail · Leave · Group chat · Past (14 days)
          └─ Hosting → Edit → Game form → Cancel · Group chat
Event detail → Who's going (report/block) · Report game · Open in Maps (Apple/Google) · Add to calendar · Invite a friend · Group chat (going or hosting)
Group chat → Who's going · Where to meet (host)
[1.0] Notification tap → Event detail
```

### 7.4 Figma frames → releases

Frames: `https://www.figma.com/design/5eKA3f0I90VVABrAuNMFD2/masuno-figma?node-id=<id with - for :>`. The file now holds both versions: the green `341:*` frames are the reference for the **0.5 UI** (as built), and the per-sport rows `408:*` / `413:*` (plus the restyled `341:*` Me, Settings, Add game and chat frames) are the **1.0 UI** (§7.7). Where a `341:*` frame has since been restyled in Figma, the build is the 0.5 reference.

**0.5 UI (built — E-tasks wire it to live data)**

| Screen | Reference | Notes |
| --- | --- | --- |
| Map, Popup | 341:1979, 341:2046 (green version) | Blue pins, no mic glyph, bookmark, popup follows its pin; iPad/Duo layout (#7) |
| Add game, Error | 341:1849, 341:3054 (green version) | + Meet-up spot + Auto-repost toggle (N17) |
| Choose location | 341:2646 | Search + current location |
| Event detail (6 states), You're in | Built from §7.6.4 | "Join game", "N going · N spots left" copy |
| Who's going | 341:2309 (green version) | Flag → Report / Block; names + Host badge only |
| Me Going/Hosting, Edit / Cancel game | 341:2165/2240/2703/2840 (green version) | Initials; "Auto-repost on" / "Reposted …" line |
| Settings | 0.5 rows (§7.6.7) | No notification, calendar or name-visibility rows |
| Group chat, Chat rules, Edit meet-up | 341:1791, 341:2420, 341:2507 (green version) | Read-only fallback unless B20 + E26 land |
| Onboarding, safety sheets, states | Built from §7.5–§7.6 copy | No frames in 0.5 (N25) |

**1.0 UI (Figma — built in E27)**

| Row in Figma | Frames (node) | 1.0 task |
| --- | --- | --- |
| 1 · Find a game and join (basketball) | Map 341:1979, Popup 341:2046, Game details 408:3506, You're in 408:3632, Who's going 408:6285 | E27 · D12 |
| 2 · Host a game | Add game 341:1849, Choose location 341:2646, Error 341:3054 | E27 (+ suggestion chips) · D2/D8 adds auto-repost (D11) and picker drag |
| 3 · Tennis | Discover 408:2770, Game details 408:3893, Who's going 408:5199, You're in 408:4516 | E27 |
| 4 · Soccer | 408:2952, 408:4032, 408:5407, 408:4670 | E27 |
| 5 · Volleyball | 408:3138, 408:4203, 408:5732, 408:4856 | E27 |
| 6 · Padel | 408:3324, 408:4374, 408:6057, 408:5042 | E27 |
| 7 · Group chat | Basketball 341:1791, Tennis 413:9386, Soccer 413:9479, Volleyball 413:9576, Padel 413:9670; Who's going 341:2309; Chat rules 341:2420; Edit meet-up 341:2507 | E27 (+ E26 messaging if it missed 0.5) |
| 8 · Me and settings | Me Going 341:2165, Me Hosting 341:2240, Edit game 341:2703, Cancel game 341:2840, Settings 341:2144 | E27 · E16 (notification toggles) |
| *Not drawn yet* | Onboarding other than Sign in to join and Find your school, detail states, safety sheets, states, Saved, notifications, Happening now, banner, picker drag, auto-repost | D2 + D8 by Sun Nov 22 |

### 7.5 Onboarding & sign-in (E5 screens · B5 `AuthService` · 1.0 frames in D2)

*Campus names below come from `university_lookup`: "Tec" at launch. If the list can't load or more than one campus is open, the copy says "campus" and "school account" instead (N32).*

1. **Welcome** — "Find your next game" / "Pickup games around Tec, one or two players short — and looking for you." **Continue**. Footer link: Privacy & Terms.
2. **Location primer** — says the map uses your location to show nearby games, and that it never leaves your phone. **Continue**.
3. **Sign in to join (sheet)** — "Quick check before you join" / "Sign in with your school account so other players know you're a verified student. Takes about 30 seconds." **Find my school** is the only way in; **Not now** closes the sheet. In 0.5 it follows the Location primer with no game behind it (R7-15).
4. **Find your school** — "You'll sign in with the account your school gave you. masUNO never sees your password." Searchable list from `university_lookup` (badge, name, email domain), with a retry card if it can't load, and "Don't see your school? masUNO is just for these campuses right now." **Continue with school account** starts sign-in for the chosen school; the choice picks the provider and sign-in hint, but doesn't decide who gets in. Footer link, for App Review and demo days: **Use a review account** opens email + password, for sign-in only, with no way to create an account.
5. **School sign-in (system web sheet)** — the school's own sign-in page, shown by iOS in `ASWebAuthenticationSession`. masUNO doesn't build, style or see any of it, including the password. Cancelling returns to Find your school. If the auth hook refuses the account: "masUNO is just for Tec students right now. Use your Tec school account." (with several campuses open: "masUNO isn't open at your school yet."). Once the tenant is locked, Microsoft's page refuses other schools' accounts itself, so this message is for accounts in Tec's tenant that the hook refuses. If the school requires admin approval, Microsoft usually shows its own page in the sheet; if it sends an error back, the app says "Your school hasn't approved masUNO yet."
6. **You're verified** — "You're verified" with the school's name, then **Continue**. Shown once, when `my_profile` has no row yet.
7. **Set up profile** — three steps:
   - **About you:** first name, last name (filled in from the school sign-in, editable), class year; preview "Emilio G. · Class of 2029" with "This is how others see you."
   - **Interests:** "What do you play?" Five sports, at least one.
   - **Community guidelines:** four rules + "You can report or block anyone from the Who's going list." **I agree** (required).
8. **(1.0) Notification primer** — shown after your first join or hosted game (C11), not during first-run onboarding.

The iOS location prompt appears when the map first opens (C11); if denied, the map centers on campus with a banner linking to iOS Settings.

**Coming back:** after sign-in, `my_profile` decides the next step, so an unfinished account resumes where it stopped and a finished one goes to the map. An expired session reopens at Find your school; signing out or deleting the account starts at Welcome.

### 7.6 Feature specs

#### 7.6.1 Map (E4, E9)
- Default view: your location if you're within ~15 km of your campus; otherwise your campus's center (from `my_profile`; Tec ≈ 25.6514, −100.2895, and the demo campus for review accounts). The "Turn on location" banner shows when location is denied (N31). The campus fallback is required: App Review is not in Monterrey. Recenter button sits right above the avatar. *(DEBUG builds can pin "you" at Tec with `-mockLocation YES`.)*
- Shows games that aren't cancelled, ended or full, start within 7 days, and whose host isn't blocked either way.
- Pins: blue with sport emoji; "Soon" if starting within 60 min (1.0 adds "Now"). Selected pin grows with a halo; others dim.
- Popup: a map callout above the selected pin that grows out of it, moves with the map and closes when the pin scrolls off screen. Host initials, title, "Basketball · Hosted by Alex G.", spots left, time, address, attendee avatars, bookmark; **Details** + **Join game** / **View game** / **Edit game**.
- Bookmark button next to search opens **Saved** (N15).
- Search (title, sport, place, host first name) and sport filter. Standard Apple map style.

#### 7.6.2 Game form (E7)
- Sport, Game name (1–40), Date (today to +6 days), Start time, Duration (30 min–3 h), Location (→ picker; required, no default: "Pick where the game is."), Meet-up spot (optional, ≤ 80), Players (2–22; editing can't go below the number going), Notes (optional, ≤ 280).
- Errors shown in the form and enforced by the server; start must be in the future and within 7 days; max 3 upcoming hosted games per person.
- Edit: "Changes are shared with everyone going." Time/place/meet-up edits record a change time (1.0 uses it for the banner and notification).

#### 7.6.3 Where's the game? (E8, E20)
0.5: search suggestions near campus and "Use my current location" → **Set location** saves name, address and coordinates. 1.0: drag the map under a fixed pin; the address updates as you go.

#### 7.6.4 Event detail (E10)

| State | Chip | Bottom bar |
| --- | --- | --- |
| Open | Open · N spots left | **Join game** |
| You're in | ✓ You're in · N going · N spots left | **Open group chat** · **Invite a friend** |
| Full | Full | "Spots open up when someone leaves — check back." 1.0: **Notify me if a spot opens** |
| Hosting | You're hosting · N going | **Open group chat** · **Edit game**; prompt to add a meet-up spot if empty |
| Ended | This game has ended | none |
| Cancelled | Alex cancelled this game | none |

- Body: map header, title, sport and host, date/time ("Starts in 35 min · about 1 hour"), address, meet-up spot, **Open in Maps** (Apple or Google if installed), **Add to calendar** (going/hosting), notes, Who's going. Bookmark in the toolbar.
- Invite a friend: share sheet with "Join me for After-work hoops — Today · 7:35 PM at … N spots left on masUNO:" + the App Store link (no deep link to the game until after the program).
- Menu: going → Leave game, Report game; not going → Report game; hosting → Cancel game.
- Join shows "You're in" immediately and rolls back if the server says the game filled: "Someone just took the last spot." If someone you blocked is going: "Someone you blocked is going."

#### 7.6.5 Me (E12, E21)
Card: initials, your full name, "Class of 2029 · Tec de Monterrey", "Verified student" badge (if O4 confirms staff don't share the student domain; otherwise "Tec verified"), interests. Going and Hosting lists with **Group chat** (**· N new** once E26 ships); Past (last 14 days, collapsed) under Going; **Edit profile & interests** (first/last name ≤ 30, class year, ≥ 1 sport; preview "Emilio G. · Class of 2029"). Empty states "No games yet. Find one on the map." / "Host a game in under a minute."

#### 7.6.6 Safety (E11 screens · B3/B8 backend)
- **Who's going:** names, Host badge, "(you)", flag → Report / Block. "Only the masUNO team sees reports."
- **Report** (person or game): Harassment or hate · Inappropriate content · Spam or fake · Made me feel unsafe · Something else (+ note). Then "Thanks — we'll review this within 24 hours." and **Block** for people.
- **Block:** "You won't see each other's games or names, and neither of you can join the other's games." Hidden immediately on the phone, then on the server. Undo in Settings › Blocked people.
- **Text filter:** English + Spanish word list on titles, notes, meet-up spots and names. Message: "Please keep it friendly — try different wording."
- **Bans:** moderators set them in the dashboard; the app then shows the suspended screen.

#### 7.6.7 Settings (E13; Notifications E16)
- *[1.0]* Notifications: Games that match your interests · A spot opens up · Game reminders · Updates on games you host.
- Privacy & safety: Location (opens iOS Settings) · Blocked people · Community guidelines.
- About: Privacy & Terms (website) · Contact us (team Gmail) · Version.
- Account: Sign out · **Delete account** ("We'll cancel games you're hosting, remove you from games you joined, and delete your profile. This can't be undone.").

#### 7.6.8 Empty, error, offline (E14)
Map with no games: "No open games right now. Start one?" Failed loads show a retry card; failed actions show a short message and undo the optimistic change; offline shows "You're offline — showing the last games we loaded."

#### 7.6.9 Group chat (N14, E24/E26, B20)
- Header: game title, "N going", avatar stack → Who's going.
- Pinned card: date/time, place, meet-up spot; host sees **Edit** → "Where to meet" sheet ("Pinned at the top of the chat so nobody has to ask.", ≤ 80, text filter, **Save**).
- Timeline: messages ("Maya C. · Host · 5:42 PM") and system rows — created, joined, left ("1 spot open"), meet-up updated, time/place changed, cancelled ("Chat closed").
- Composer (when `chat_enabled` is on): text filter, no links, ≤ 1000 characters; touch and hold a message to copy, report or block; a message that didn't send says "Not sent · Tap to retry". The chat closes when the game is cancelled and 24 hours after it ends.
- With messaging only (E26): "Before you chat" rules sheet once per account; opening marks the chat read ("Group chat · N new"). The read-only chat has neither.
- **Submission rule:** if messaging isn't live on prod by the Sun Nov 8 RC, the submitted build ships the **read-only fallback**: pinned card + system rows only, no composer, and the "Before you go" copy reverts (§7.2). System rows come from `game_activity`, an append-only table the RPCs write to (B3, N30).

#### 7.6.10 Saved (N15, E17)
Bookmark on the popup, Event detail and the Saved list; filled green icon when saved. 0.5 stores bookmarks on the phone (survive relaunch, not reinstall). 1.0 syncs them (`bookmarks`, B15) and adds "Notify me if a spot opens".

#### 7.6.11 Auto-repost (N17, E25, B3 — 0.5)
- **Form:** "Auto-repost" toggle under Players, on by default, with "If someone drops out, we'll bump your game back to the top of the map." Saved with the game.
- **Trigger (server):** when a full game frees a spot — a player leaves (`leave_game`) or the host raises Players (`update_game`) — and `auto_repost` is on and the game isn't cancelled or ended, set `events.reposted_at = now()`.
- **Bump (app):** for 2 hours after `reposted_at`, the game's pin draws above other pins with a "Spot open" label (instead of "Soon"). The app orders `game_cards` by `sort_at` (`coalesce(reposted_at, created_at)`) desc.
- **Host:** hosting cards show "Auto-repost on", or "Reposted 25 min ago" after a bump.
- **Not in 0.5:** notifying anyone (1.0 pairs it with the "A spot opened" push to people who saved the game).

### 7.7 1.0 UI — "Room for one more" (E27 · D2/D8/D12/D13)

Source of truth: the Figma file "masuno figma" (rows 1–8, §7.4) and `DESIGN.md` v2.0 in the project. This section is the build summary and the decisions that go with it; `DESIGN.md` has the full recipes. **0.5 and 0.6 keep the 0.5 UI (§7.1–§7.6); everything here lands in the 1.0 beta (Tue Dec 1).** Navigation (§7.3), behavior (§7.6) and the backend don't change, except where noted.

#### 7.7.1 The idea
"Can I join?" becomes "We're looking for you." The 1.0 UI keeps the native iOS structure and adds sport-flavored whimsy: each sport's color, court and field art, rounded type, and people as colored initials. **The dashed "+1" open-spot token is the brand mark** — on pins, popups, cards, Who's going and the chat. One green action per screen; no skill levels, ratings or competitive language.

#### 7.7.2 Tokens (replace §7.1 in 1.0)

| Token | 0.5 (built) | 1.0 | Use |
| --- | --- | --- | --- |
| `primary` (was `accent`) | `#12815A` | `#12825A` | The one action color: primary buttons, toggles, Host/You labels |
| `mint` (was `accentSoft`) | `#DDF1E8` | `#DDF1E8` | Secondary buttons ("Not now", "Keep game", "+ Add game") |
| `bg` (was `background`) | `#F5F4F7` | `#F2F2F7` | Screens |
| `surface` (was `card`) | `#FDFCFE` | `#FDFCFE` | Cards, popups, sheets, others' chat bubbles |
| `surface-2` | — | `#F5F4F7` | Composer tray, secondary fills |
| `ink` / `ink-2` | `#1F2638` / `#5F5C68` | same | Text; ink on every colored fill except `primary` |
| `danger` (was `destructive`) | `#C23B34` | `#C42B2B` | Sign out, Cancel game, Delete account |
| `pin` | `#2F6FE0` | *(removed)* | Pins use the sport color |
| `chipSport` | `#DCE4F4` | *(removed)* | Chips use the sport color |
| Sport colors | — | Basketball `#F2853A` · Tennis `#C7D93D` · Soccer `#3DB26F` · Volleyball `#A99CF6` · Padel `#56BDE8` | That sport's pin, court header, chat band, my bubbles, send button, chip, settings tile |
| Person colors | `accentSoft` initials | Pastels: `#FFD15C` `#B59CF7` `#FF9F80` `#7FD8A0` `#FF9CC2` `#5FD6C8` `#F2B56B` | Assigned from the user ID so a person keeps one color everywhere |
| You | — | `#74C0F5` | The current user, always (keep it out of the others' palette) |
| Radii | 16–20 | Cards 22 · sheets 34–38 · pills/inputs/chips fully rounded · tiles 12 | |
| Type | SF Pro | **SF Pro Rounded** in the app (`.fontDesign(.rounded)`), heavier weights; Nunito in Figma and on the web (R7-10) | |

Light mode only, as before. Contrast: ink on every sport color and `#74C0F5`; white only on `primary`.

#### 7.7.3 Components
- **Avatar / person token:** initials on the person's pastel, 2 px white ring in stacks, "+N" bubble. Sizes 26 / 30 / 36–42 / 72.
- **"+1" token:** 2 px dashed ink circle with "+1"; one per open spot; filled with the sport color in chat. Joining animates your avatar into the first open token, then "You're in!".
- **Map pins:** teardrop in the sport color with the emoji; "Soon" tag; people tokens under the pin (no "+2 spots" text); selected pin ~1.3×, others 40%. Auto-repost bump keeps its "Spot open" tag and draws on top (E25).
- **Popup / game card:** `surface` card with a tail from its bottom edge to the pin; order: sport line, title, people + "+1" tokens with "Room for N more", time, place, actions (**Details** · **Count me in**). The same card (minus tail) is the Me card: Going → **Leave** · **Group chat · N new**; Hosting → **Edit** · **Group chat · N new**.
- **Full-bleed court header (Game details, You're in):** ~400 pt court/field art in the sport color with faint lines; attendees placed on the court as tokens, open spots as "+1"; a rounded content sheet overlaps it; glass back and `•••` buttons on top. Five drawings — basketball half court, tennis, soccer pitch with stripes, volleyball net, padel glass-wall court — built as SwiftUI `Shape`s, not images.
- **Game details content:** title, "Basketball · Hosted by Alex R.", **"Room for N more"** + **Who's going ›**, host note card ("Alex says"), time/place/meet-up card with **Open in Maps** (or **Add to calendar** once you're in), then the action bar.
- **Liquid Glass everywhere:** prominent green (the one primary action), mint (secondary), plain (navigation, quiet actions), sport-tinted (send button, chips).
- **Who's going sheet:** grabber, "Who's going" + "N going", glass ×; rows with a 42 pt avatar, name + green HOST tag, a second line (R7-4), and `•••` → Report / Block (none on your own row); a "+1 Room for N more" row; a gray safety note with a shield: "Anything feel off? Tap ••• next to anyone to report or block them. Only the masUNO team sees reports."
- **Group chat:** 175 pt sport band with faint court lines; title, "🎾 Tennis · 3 going", glass avatar stack → Who's going; floating pinned card (time, place, meet-up with clock/pin/flag icons); day pill; system line "Priya created the chat · 3 going"; their bubbles on `surface`, mine in the sport color; **join pill** "+1 Emilio took a spot · room for one more" / "took the last spot · game is full"; glass composer "Message" + sport-tinted send. Read-only variant (no composer) if messaging isn't live.
- **Me:** sky-blue (`#74C0F5`) profile band with the 72 pt avatar; name, "Class of 2029 · Tec de Monterrey", "Verified student"; **Plays** chips in each sport's color; **Edit profile and sports**; Going / Hosting glass segmented control; cards as above; "+ Add game" mint button on Hosting.
- **Settings:** grouped `surface` cards, 36 pt colored icon tiles, title + subtitle, toggle or chevron (rows per R7-5); Sign out as a centered glass pill in `danger`.
- **Add / Edit game:** stacked field cards; location card with map thumbnail and mint **Change**; "Players" stepper "9 spots · 3 joined"; optional notes under **"What would help someone new say yes?"** with suggestion chips ("I have an extra ball", "Coming alone is fine", "Come for part of it") that append to the notes; errors as red outline + inline message, never alerts.

#### 7.7.4 Screens that change (vs 0.5)

| Screen | What's new in 1.0 |
| --- | --- |
| Map | Sport-colored teardrop pins with people tokens; "N games nearby" chip; search + Saved glass bar; **+ Add game** green pill, filter, recenter, avatar |
| Popup | Sport-tinted card with tail; "+1" tokens; **Count me in** |
| Event detail | Court header with lineup; "Room for N more"; "Alex says" note; caption "One tap and you're in. Change your mind anytime." |
| You're in | "You're in!" + "Alex knows you're coming. Say hi in the group chat, or just show up." (read-only fallback: "…Check where to meet and who's going."); **Open group chat** · **Invite a friend**; Add to calendar in the card |
| Who's going | Sheet as §7.7.3; `•••` instead of a flag |
| Group chat | Sport band, pinned card, join pill, sport bubbles |
| Me | Profile band, Plays chips, sport-colored cards with token rows |
| Settings | Icon tiles; 1.0 notification rows (E16) |
| Add / Edit game | Field cards, suggestion chips, spots stepper copy |
| Not drawn yet | Onboarding other than Sign in to join and Find your school, detail states, safety sheets, empty/error/offline, Saved, notification primer, Happening now, changed banner, picker drag, auto-repost → D2 + D8 (Nov 22) |

#### 7.7.5 Copy changes in 1.0 (String Catalog keys stay; values change)

| 0.5 | 1.0 |
| --- | --- |
| **Join game** | **Count me in** |
| "3 going · 3 spots left" / "1 spot left" | "Room for 3 more" / "Room for one more"; on cards "3 joined · room for 6 more" |
| "Full" | "Full" (unchanged) |
| "Edit profile & interests" | "Edit profile and sports" |
| "Interests" (Me) | "Plays" |
| Notes label | "What would help someone new say yes?" (optional) |
| Before you go | "Alex knows you're coming. Say hi in the group chat, or just show up." |
| — | "One tap and you're in. Change your mind anytime." (under Count me in) |
| — | Host note label "Alex says" |
| Time "Today, 7:35 PM" | "Today · 7:35 PM"; "Sun, Nov 8 · 10:00 AM" (the `·` separator everywhere) |

Spanish for the new strings comes with O12 (`DESIGN.md` §7 has the first glossary: Quién va, Ya estás dentro, Detalles del partido, Pronto, Descubrir).

#### 7.7.6 Where the 1.0 Figma conflicts with earlier decisions

Defaults below apply unless signed off otherwise (§12, R7-4…R7-10, R7-15). Arianna updates the frames to match (D12).

| # | Figma 1.0 shows | Conflicts with | Default for 1.0 |
| --- | --- | --- | --- |
| R7-4 | Who's going rows: "Class of 2027 · Basketball · Running" (interests visible; "Running" isn't a sport) | §8.8 and the Privacy page: "interests are private"; others see first name, last initial and class year | **"Class of 2027"** only. If the team wants sports shown, change §8.8, §10.2 and the live Privacy page first (Emilio checks), and show only the five sports. |
| R7-5 | Settings rows "Add games to my calendar" and "Who can see your name" | C3 (no calendar sync; one-off Add to calendar button) and C5 ("First L." for everyone, no setting) | **Drop both rows**; keep the Add to calendar button. Revisit after the program (§13). |
| R7-6 | "Delete game" / "Delete Sunday pickup soccer?" | Soft cancel (§7.2, `cancel_game`): the game stays visible as "Cancelled" | **"Cancel game"** / "Cancel Sunday pickup soccer?" with the same layout. |
| R7-7 | "· Read" under my chat bubbles | D1 removed "· Read"; per-message read receipts aren't in Chat v1 (only `chat_reads` for unread counts) | **No "· Read"** in 1.0. |
| R7-8 | Mic glyph in the search bar | No voice search (D1 removed it) | **No mic glyph.** |
| R7-9 | `DESIGN.md`: Spanish is the primary market | "English first, strings externalized"; Spanish in 1.0 | **No change:** the app follows the phone's language from 1.0; development language stays English. |
| R7-10 | Nunito everywhere | SF Pro in 0.5 | **SF Pro Rounded** in the app (`DESIGN.md` allows it; no bundled font); Nunito in Figma and on the website. |
| R7-15 | Sign in to join opens over a game with **Not now**, so people browse signed out and sign in when they join | "Sign-in gates the app" (§1); signed-out game reads aren't in `docs/API.md` or B3 | **0.5 keeps the gate:** the sheet follows the Location primer with no game behind it. Browse-first is a separate 1.0 decision, because it needs a contract and RLS change. |
| — | Find your school lists Illinois Tech and UIC | Tec-only launch (N32) | **Concept only.** The list comes from `university_lookup`, so it shows Tec alone at launch. |
| — | "Your spot is held while you sign in." and campus locations under school names | No hold in `join_game`; no column for a campus location | **Ethan removes both from the frames.** |
| — | Placeholder content: San Francisco map and addresses, "[Padel venue near Tec]", a warm map overlay | Monterrey launch; standard Apple map style (§7.6.1) | Use Monterrey venues in frames, decks and screenshots; standard map style in the app. |

---

## 8. Technical specification

### 8.1 Architecture & environments
- **Client:** SwiftUI, `@Observable`, iOS 26 target (Liquid Glass — confirm in `project.yml`), XcodeGen, `supabase-swift` v2 behind repository protocols; mocks for previews and tests.
- **Layers:** Views + view models (Ethan) → `GameStore` + `AuthService` + repositories (Ethan for 0.5, rev. 7 N21) → Supabase (Emilio). Views never import the Supabase SDK.
- **Backend:** Supabase Postgres with RLS on every table; Auth (school SSO through the Azure provider + allowlisted review passwords); Edge Functions for `delete-account` and (1.0) `send-push`; `pg_cron` + `pg_net` for jobs.
- **Projects:** `masuno-dev` and `masuno-prod` in Ricardo's organization, with Emilio as an Owner; both on the **free plan** (2 active projects allowed). Free projects pause after a week without activity and have no automatic backups, so a daily GitHub Action pings prod and Emilio runs `supabase db dump` weekly into private storage (it contains personal data).
- **Region:** no Mexico region. Before creating prod, compare round-trip times from a phone in Monterrey (Ricardo) to throwaway projects in `us-east-1`, `us-east-2` and `us-west-1`; pick the fastest. It can't be moved later.
- **Secrets:** anon key in a git-ignored `Config.xcconfig` per configuration (template checked in); service-role key, Entra client secret and APNs key only in Supabase secrets.

### 8.2 Client modules
- **Ethan:** design system (E2; 1.0 tokens in E27) · navigation + version gate (E3) · `LocationService` (E9) · calendar editor (E19) · all views and view models · for 0.5 also `AuthService` (B5), `GameStore` (B6) and live repositories (B7).
- **Emilio:** reviews `MasUno/Data` · `NotificationService` (B16, 1.0).
- **Shared:** protocols, domain models and mocks (E1: `MasUno/Models`, `MasUno/Data`, `MasUno/Data/Mocks`); `ActivityCatalog` (cached, with a built-in fallback of the 5 sports).

### 8.3 Schema

```sql
universities (id uuid pk, name text,                                 -- 'Tec de Monterrey'
  short_name text,                                                    -- 'Tec', used in onboarding copy (N32)
  email_domain text unique,                                           -- 'tec.mx' (exact match)
  sso_provider text null,                                             -- 'azure' at launch; 'google' for later Workspace schools; null on the demo campus
  tenant_id text null,                                                -- Tec's Entra tenant, once O4 confirms it
  student_email_pattern text null,                                    -- set if O4 finds staff share the domain
  center_lat float8, center_lng float8, timezone text,                -- 'America/Monterrey'
  signup_enabled bool default true, is_demo bool default false)       -- hidden App Review campus (C12)

activities (slug text pk, kind text, label_en text, label_es text, emoji text, sort_order int,
  postable bool default false, interest_selectable bool default false, active bool default true)

profiles (id uuid pk references auth.users on delete cascade,        -- public card (C8)
  university_id uuid references universities, first_name text, last_initial char(1),
  grad_year int, created_at timestamptz default now())

profile_private (user_id uuid pk references profiles on delete cascade,   -- own row only
  last_name text, locale text default 'en', guidelines_accepted_at timestamptz,
  banned_at timestamptz null)                                         -- service role only

profile_interests (user_id uuid references profiles on delete cascade,
  activity_slug text references activities, primary key (user_id, activity_slug))

events (id uuid pk default gen_random_uuid(), university_id uuid, host_id uuid references profiles,
  activity_slug text references activities,
  title text check (char_length(title) between 1 and 40),
  starts_at timestamptz, duration_minutes int check (duration_minutes in (30,60,90,120,180)),
  ends_at timestamptz not null,                                       -- trigger (C10)
  capacity int check (capacity between 2 and 22),                     -- includes host
  going_count int not null default 1, check (going_count between 1 and capacity),  -- C9
  notes text check (char_length(notes) <= 280),
  place_name text, place_address text, lat float8, lng float8,
  meet_point text null check (char_length(meet_point) <= 80),
  material_change_at timestamptz null, cancelled_at timestamptz null,
  auto_repost bool not null default true, reposted_at timestamptz null,  -- N17 (§7.6.11)
  created_at timestamptz default now(), updated_at timestamptz)

rsvps (event_id uuid references events on delete cascade, user_id uuid references profiles on delete cascade,
  role text check (role in ('host','player')), joined_at timestamptz default now(),
  primary key (event_id, user_id))

blocks  (blocker_id uuid, blocked_id uuid, created_at timestamptz default now(),
  primary key (blocker_id, blocked_id))                               -- + index (blocked_id, blocker_id)
reports (id uuid pk, reporter_id uuid null references profiles on delete set null,
  target_user_id uuid null, target_event_id uuid null, reason text, note text null,
  status text default 'open', created_at timestamptz default now(), resolved_at timestamptz null)
app_config (key text pk, value jsonb)                                 -- min_supported_version, support_email, privacy_url
auth_allowlist (email text pk, note text,                             -- App Review, demo-day and QA accounts
  university_id uuid references universities)                         -- their campus (the demo campus, or Tec for a demo-day account)

-- 1.0 (B13, B15):
bookmarks (event_id, user_id, created_at, primary key (event_id, user_id))
notification_prefs (user_id pk, interest_match bool default true, spot_open bool default true,
  reminders bool default true, hosting bool default true)
device_tokens (token text pk, user_id uuid, environment text, updated_at timestamptz)
notification_outbox (id bigserial pk, user_id uuid, kind text, event_id uuid, payload jsonb,
  created_at timestamptz default now(), locked_at timestamptz, sent_at timestamptz,
  attempts int default 0, error text)
```

**Read views (RLS applies, `security_invoker`):** `game_cards` (event + host first name/initial/class year + `going_count`, `spots_left`, `my_role`, `my_joined_at`, `has_blocked_attendee`, `auto_repost`, `reposted_at`, `sort_at = coalesce(reposted_at, created_at)` (the app orders by `sort_at desc`); 1.0 `is_bookmarked`), `game_attendees(event_id)` (excludes blocked people), `my_profile` (includes the campus's name, short name, domain and center), `university_lookup` (every campus with an `sso_provider` that isn't `is_demo`, open or closed, with `signup_enabled`, `sso_provider` and `tenant_id`; readable signed out; closed campuses stay listed so existing accounts can sign back in, N32, N33). `game_activity` (N30) is an append-only table.

### 8.4 Security & sign-in
- **Policies:** `profiles` readable within your university except blocked pairs; `profile_private` own row only; `events`/`rsvps` readable within your university unless the host is a blocked pair; all writes through RPCs; `reports` insert-only via RPC; `universities`, `activities`, `app_config` read-only; `auth_allowlist` no client access. Signed out, `universities` is readable only through `university_lookup`'s columns and rows. Helpers `is_active(uid)` and `is_blocked_pair(a, b)`.
- **Sign-in (N33):** "Continue with school account" only. For Tec (Microsoft 365) this is Supabase's Azure provider, opened as described in the iOS flow below. Google Workspace schools would use the Google provider restricted to the school's domain (the `hd` hint up front, the auth hook as the real check). No consumer social login and no public email + password sign-up: Guideline 4.8 exempts education apps that require an existing education account, and either addition would make Sign in with Apple, or an equivalent privacy-focused login, required.
- **iOS sign-in flow (0.5).** Values below are Tec's; the app reads them from `university_lookup` and hard-codes none (N32):
  1. **Continue with school account** on Find your school calls supabase-swift v2 `auth.signInWithOAuth(provider: .azure, redirectTo: masuno://auth-callback, scopes: "openid email profile", queryParams: [(name: "domain_hint", value: "tec.mx")], configure: { $0.prefersEphemeralWebBrowserSession = true })`. The provider comes from `sso_provider` and the hint from `email_domain`. The hint skips Microsoft's email-based discovery step and should send students straight to Tec's federated sign-in page.
  2. The SDK opens the school's page in `ASWebAuthenticationSession`, taking the callback scheme `masuno` from `redirectTo`. The ephemeral setting comes from `configure`; Apple says it's the only way to avoid the system "masUNO wants to use … to sign in" alert. The cost: students re-enter their school password if they ever sign in again, after signing out, reinstalling or an expired session.
  3. On callback, the same call finishes the PKCE exchange (the SDK's default flow) and returns the session, or throws if the callback carries an error. The before-user-created auth hook is still the gate: only an active university domain or an `auth_allowlist` address gets through. A new account then sees You're verified → Set up profile.
  4. Add `masuno://auth-callback` to Supabase Auth → URL Configuration → Redirect URLs on both projects. The `masuno` URL scheme is already registered in the app target (`project.yml`, E3).
  5. iOS shows the school's sign-in page, and it belongs to the school. masUNO doesn't build, style or see any of it, including the password.
- **Entra app registration (B2):** registered in a team-owned tenant (§10.1) with supported account types **Multiple Entra ID tenants**, the `organizations` audience: other organizations yes, personal Microsoft accounts no. Web redirect URIs: `https://<project-ref>.supabase.co/auth/v1/callback` for `masuno-dev` and `masuno-prod`. Scopes: `openid`, `email`, `profile`, nothing else. Tec IT grants tenant-wide consent, if it's needed, at `https://login.microsoftonline.com/<tec-tenant-id>/adminconsent?client_id=<client-id>`.
- **Supabase Azure provider settings (N35):** Azure Tenant URL is `https://login.microsoftonline.com/organizations` on both projects (set on dev, and on prod Nov 10), never `common`, which allows personal Microsoft accounts. It is **not** locked to Tec's tenant, because the tenant is set once per Supabase project and would tie the project to one campus (N32). `organizations` admits every other organization's accounts, so the auth hook checks the tenant instead (B22, below): `universities.tenant_id` is the per-campus check. A public lookup on Nov 6 shows `tec.mx` as a federated domain on tenant `c65a3ea6-0f7c-400b-8934-5a6dc1705645`; O4 confirms it with Tec IT. These are dashboard settings on each project, not migrations (B12).
- **Email claim:** Supabase's Azure provider requires the token to include an email address, so configure the optional `email` claim and verify on `masuno-dev` which claim carries the `@tec.mx` address (`email` vs `upn`/`preferred_username`). Also add `xms_edov`, which Microsoft only returns alongside `email`, so Supabase can tell whether the domain is verified; without it, another tenant could present an unverified `@tec.mx` address.
- **Auth hook (before user created) is the real gate.** It's a Postgres function, available on the free plan. Allow only an active `universities.email_domain` with sign-up enabled (and `student_email_pattern` if set), or an `auth_allowlist` address. Otherwise reject with `email_not_allowed`. Deny by default — Supabase's sample allows unknown domains. Verify the email claim server-side (from the hook's payload, never from the client or the school picked in the app). Check the provider too: the email provider has to stay on for review passwords, so it's allowlist-only, otherwise anyone could sign up with a password on an `@tec.mx` address. **Check the tenant (B22, N35):** for an Azure sign-up, the token's tenant must equal the campus's `tenant_id`, otherwise another organization's admin could give a user an `@tec.mx` email and get in. The hook only runs for new users, so existing accounts at a closed campus can still sign in. Users created through the Admin API (service-role key) skip the hook.
- **App Review accounts:** primary is a real test school account from Tec IT (O4), entered in the review notes. Add it to `auth_allowlist` with the demo campus, so reviewers see joinable games instead of a possibly empty Tec map. Fallback if Tec won't issue one: two Gmail aliases (e.g. `official.masuno.app+review1@gmail.com`) in `auth_allowlist` with passwords, created by Emilio with the email already confirmed and attached to the demo campus through `auth_allowlist.university_id`. Password sign-in works only for `auth_allowlist` addresses and isn't presented as a sign-up option; the review notes say so. **Use a review account** is a small visible link in the Release build, not a DEBUG tool: reviewers get the Release build, Guideline 2.1(a) asks for a demo account, and 2.5.19 bars hidden features.
- **Demo-day and QA accounts:** also allowlisted password accounts. A demo-day account can point `university_id` at Tec to show real games; QA's third phone needs one more account for the last-spot race (B4).
- **Confirm on a device (B21, record the results here):**
  - Does the alert stay away with an ephemeral session?
  - Does `domain_hint` reach Microsoft through Supabase and open Tec's page?
  - Which claim carries the `@tec.mx` address?
  - What does a student see if admin consent is needed?
  - Which `user_metadata` keys hold the name, and does Supabase Auth store anything beyond name, email and account ID?

### 8.5 API contract (frozen Fri Nov 6 in `docs/API.md`; sign-in amended by N33)

`docs/API.md` has the exact signatures and wins over this summary. RPCs are `security definer`, pin `search_path`, check `auth.uid()` and `is_active()`, and raise a short code that `GameStore` maps to `DomainError`. Every game write returns the updated `game_cards` row. Any RPC can also raise `not_authenticated`, and any write `suspended`.

**`university_lookup`** (readable signed out) feeds Find your school: name, short name, `email_domain`, `sso_provider`, `tenant_id`, `signup_enabled`, plus id and map center. It replaces `open_universities`.

| RPC | Purpose | Errors |
| --- | --- | --- |
| `complete_profile(first, last, grad_year, interests[], locale)` | Create/update profile; sets the campus on creation, from `auth_allowlist.university_id` if the address is listed, otherwise the email domain | `invalid_text`, `invalid_input` |
| `accept_guidelines()` | Record agreement | — |
| `create_game(…, auto_repost)` | Validate sport, 7-day window, limit, text; insert game + host | `invalid_time`, `invalid_text`, `limit_reached`, `invalid_input` |
| `update_game(id, …, auto_repost)` | Host only; players ≥ going; record material changes; if capacity rises on a full game and `auto_repost`, set `reposted_at` | `not_found`, `not_allowed`, `cancelled`, `ended`, `capacity_below_going`, `invalid_time`, `invalid_text` |
| `cancel_game(id)` | Host only; soft cancel | `not_found`, `not_allowed`, `ended` |
| `join_game(id)` | Lock row; reject cancelled/ended/host/blocked; `full` if no spots; idempotent | `full`, `cancelled`, `ended`, `blocked`, `not_found` |
| `leave_game(id)` | Lock row; remove; decrement; if the game was full and `auto_repost`, set `reposted_at` | `not_found`, `not_allowed` (host), `ended` |
| `report(user?, game?, reason, note?)` | Insert report → alert | `invalid_input` |
| `block(user_id)` / `unblock(user_id)` | Own blocks | `invalid_input` |
| `my_blocks()` | Names for Blocked people, which RLS otherwise hides | — |
| *1.0:* `register_device`, `toggle_bookmark`, `set_notification_prefs` | | — |

### 8.6 Jobs & functions (Emilio)
- `delete-account` (B9): cancels upcoming hosted games, leaves joined games under lock, keeps reports with the reporter removed, deletes the auth user.
- **Report alerts** (B8): a database webhook on `reports` posts a short message (reason, target, dashboard link — no personal details) to the team's Discord or Slack via an incoming webhook.
- **Demo campus refresh** (B3): a daily `pg_cron` job keeps 4–6 upcoming games on the hidden campus.
- *1.0:* `send-push` (B14), drained every minute by `pg_cron`: claims up to 100 rows, respects preferences and blocks, APNs token auth, one collapse ID per game, 3 retries, drops dead tokens. Start with a 1-hour test: one push from the Edge Function to a TestFlight build. A reminder job runs every 5 min for games starting in 25–35 min.

### 8.7 Notifications (1.0)

| Notification | To | When | Setting |
| --- | --- | --- | --- |
| A spot opened in [game] | People who saved it | A full game frees a spot | A spot opens up |
| [game] starts in 30 min | Everyone going | Reminder job | Game reminders |
| New [sport] game near you | Interested users (max 2/day) | Game created | Games that match your interests |
| [game] changed | Everyone going | Time/place/meet-up edit | Always on |
| [game] was cancelled | Everyone going | Host cancels | Always on |
| Ricardo G. joined · 2 spots left | Host | Join/leave | Updates on games you host |

### 8.8 Privacy & data
Your phone's location never leaves the phone. The school's sign-in gives us your name, school email and the account ID sign-in needs, and nothing else. Email stays in Supabase Auth and is never shown to anyone; Supabase Auth also keeps the name from sign-in, and both go when the account is deleted. Others see first name, last initial and class year; interests are private. Reports are kept for moderation; deleted accounts are removed right away (reports stay, without the reporter). No analytics SDK; crashes come from Xcode Organizer.

### 8.9 Metrics (B17; counted by hand for DD2)
`metrics_daily` (dashboard only): sign-ups, finished onboarding, games created, joins, unique joiners, games that filled, repeat hosts, reports. Plus App Store Connect for TestFlight testers and downloads. Ricardo turns these into demo-day numbers (O10).

### 8.10 Changing or adding a campus (N32)

masUNO launches at Tec. To open somewhere else, no app release is needed:

1. **Emilio:** insert the `universities` row (name, short name, email domain, SSO provider, center, timezone), plus `student_email_pattern` if staff share the domain. Set up its provider: the Google provider restricted to its domain, or, for another Microsoft school, nothing in Auth (the project already uses `organizations`, N35): set its `tenant_id` and the hook's tenant check (B22) does the rest. Seed its venues.
2. **Emilio:** set `signup_enabled = true` on it. To close Tec, set it to `false` on Tec's row. Existing Tec accounts keep working and can sign back in; only new sign-ups stop, through the auth hook.
3. **Ricardo:** ask its IT the O4 questions (which provider, tenant, user or admin consent, test accounts) and test sign-in with a real student account.
4. **Ricardo + Arianna:** update what lives outside the app: Privacy & Terms and Support pages, App Store listing and screenshots, beta recruiting.

With one campus open, onboarding names it. With several, it says "school account", and each person's games stay scoped to their own campus by RLS. A person's campus is set when their profile is created, and there's no moving between campuses.

---

## 9. Testing

| Layer | What | Owner |
| --- | --- | --- |
| Database | Last-spot race (two sessions), `going_count` never above players, RLS visible/invisible, blocks both ways, bans, posting window, text filter, auth hook (each provider, other domains, password sign-up refused) | Emilio |
| Data layer | `GameStore` join/leave + rollback, error mapping, `AuthService` states, callback errors | Ethan (0.5) |
| Sign-in spike | One real Tec account on a physical iPhone, end to end (B21) | Emilio, Ethan |
| Screens | Form validation, event-state logic, one UI smoke test | Ethan |
| Design QA | 0.x builds vs the green frames and §7; 1.0 vs §7.7 frames; screenshots in UI PRs | Arianna |
| Manual | `docs/QA.md` two-phone script: school sign-in, core loop, block/report, delete account, offline, location denied, far away, big text, small phone — run by Arianna and Ricardo on each build | Arianna, Ricardo |
| Beta | 15–30 Tec students from ~Nov 10 (once Beta App Review clears the 0.5 RC); feedback form; weekly summary | Ricardo |

---

## 10. Release plan

### 10.1 Accounts & access
- Developer team: Boys & Girls Clubs of Chicago; App ID `com.masuno.app`. All four of us already have access, so everyone can be an internal TestFlight tester from build 0.1, and Ricardo can enter the listing and manage external testers.
- **APNs key for 1.0 (by Nov 22, before B14):** created by whoever has the Admin role, or App Manager with access to Certificates, Identifiers & Profiles. The `.p8` file goes straight into the password manager and Supabase secrets.
- **Supabase:** Ricardo adds Emilio as an Owner of the organization (O2).
- **Microsoft Entra (B2):** Emilio registers the app under a free Azure account, in its default directory. An app registration can't move between tenants later. The client secret goes in the password manager and Supabase secrets. Secrets expire and an expired one stops every school sign-in, so put the date in the team calendar.
- After the program: ask ECC/B&GC whether the app stays on their team or moves to our own account.

### 10.2 Privacy & Terms — one page (O6 copy → D4 page)
Plain language, at `masuno-app.github.io/privacy`, linked from onboarding, Settings and App Store Connect. Not legal advice; keep it true to what the app does — Emilio checks every data claim.
1. **Who we are** — a student project in the App Accelerator; contact: team Gmail.
2. **What we collect** — school email (sign-in only, never shown), name (others see first name + last initial), class year, sports you like, games you host or join, reports and blocks you make, (1.0) a notification token.
3. **What we don't** — from your school's sign-in we receive your name, school email and an account ID and nothing else: no contacts, no files, no calendar; your school's sign-in page belongs to your school, and we never see your school password; your phone's location never leaves your phone; no ads, no selling data, no tracking.
4. **Who sees what** — other students at your campus see your first name, last initial, class year and the games you're in; only the masUNO team sees reports.
5. **Deletion** — delete your account in Settings and your data is removed right away (reports stay, without your name).
6. **Rules** — be respectful, no harassment or hate, no spam; we can remove content and suspend accounts; you play at your own risk and are responsible for your own safety at games.
7. **Changes** — we'll update this page and the date at the top.

### 10.3 TestFlight
- Internal (team members added in App Store Connect): every build from 0.1. Upload of 0.1 for Demo Day #1 is not confirmed (E6).
- External: the 0.5 release candidate goes to Beta App Review on Sun Nov 8, the day before App Review. Ricardo manages the public link and testers. Testers sign in with their own Tec accounts, so the beta can't open until real students can sign in (K19). 0.6 and 1.0 beta builds go to the same group.

### 10.4 App Review checklist (green before the Wed Nov 11 RC, again before each later submission)
- [ ] A real test school account from Tec IT (O4) in the notes, signing in from outside Mexico without a code the reviewer can't receive. Fallback if Tec won't issue one: the allowlisted review-only password login, and the notes say where the **Use a review account** link is, that it's reachable only for `auth_allowlist` addresses and that it isn't a sign-up option. Either way, the demo campus shows joinable games.
- [ ] Notes state plainly: "masUNO is only for verified university students; sign-in uses the student's existing school account. Here is a test account."
- [ ] Notes explain: why there's no Sign in with Apple (Guideline 4.8 education exemption), the demo campus, how to report and block, that reports are handled within 24 h. If messaging is on (0.6): where group chat is, that it's only between people going to the same game, and how to report a message.
- [ ] Guidelines agreed before use; text filter; report person and game; block works instantly; Blocked people undo.
- [ ] Contact us in the app (team Gmail) and support URL (website) in App Store Connect.
- [ ] Privacy & Terms URL in the app (**the Settings row opens it — no "Coming soon"**) and in App Store Connect; privacy label answered.
- [ ] Delete account in the app, and it really deletes (B9 wired in E13).
- [ ] No placeholders, no "coming soon", no DEBUG menus (`-screen`, component gallery, `simulateDropOut`), no mock data or mock location; group chat either sends real messages or has no composer (N14); cut features hidden; Auto-repost really bumps the game on prod; screenshots from the real build; listing doesn't promise messaging or anything not in this version.
- [ ] Invite a friend shares the app's own App Store URL (`apps.apple.com/app/id<Apple ID>` from App Store Connect), not a search link.
- [ ] App icon in the asset catalog.
- [ ] Location purpose string explains the use; (1.0) notifications asked in context.
- [ ] Age-rating questionnaire answered (user-generated content; messaging only if `chat_enabled` is on in prod for that submission).
- [ ] Map lands on the demo campus for review accounts far from any campus.
- [ ] Exact submitted build tested on a physical phone.

### 10.5 Release steps
- **0.5 — Thu Nov 12** (moved from Mon Nov 9, N34):
  - ✅ Tue Nov 10: prod migrations, Auth settings (§8.4), review accounts and demo campus (B12).
  - Wed Nov 11 morning: cut check — apply the cut order to anything not live on prod; Ricardo's listing is in App Store Connect. Emilio and Ethan run the SSO spike (B21).
  - Wed Nov 11 afternoon/evening: two-phone QA on prod; Arianna's screenshots; Ethan uploads the release candidate and sends it to Beta App Review.
  - Thu Nov 12: go/no-go — must-haves live on prod, or submission slips (§3). Ethan submits, with release on approval (manual release if R7-14 applies).
  - On rejection, Ethan replies the same day and resubmits within 24 h. Last resubmit to be live for Demo Day #2: Fri Nov 13.
- **0.6 — Mon Nov 16:** fixes + anything cut from 0.5; release on approval. Prod migrations must stay compatible with 0.5.
- **1.0 — Tue Dec 8:**
  - Beta (1.0 UI + notifications) on TestFlight Tue Dec 1, shown at Demo Day #3.
  - Submit with manual release. Last resubmit Fri Dec 11.
  - Release Mon Dec 14, or on approval if later.
  - Emilio applies prod migrations **before** release and keeps them compatible with 0.x, since some people won't update right away. Raise `min_supported_version` only if 0.x truly breaks.
  - New screenshots and listing for the 1.0 UI (D7, O7).
- **Launch day — Wed Dec 16:**
  - Smoke test the App Store build on two phones.
  - Ricardo sends the waitlist email (O13).
  - Everyone watches report alerts and crashes into the evening.

### 10.6 Moderation (O11)
Alert in team chat → on-call person (Ricardo or Arianna) checks the report in the dashboard within 24 h → dismiss, cancel the game, clear an offending name, or ban (Emilio's saved SQL, B17; Emilio does it until then) → mark resolved → if anyone may be in danger, tell them to call 911 (the emergency number in both Mexico and the US) or campus security, and keep records. Log actions in a shared sheet.

---

## 11. Risks

| # | Risk | Likelihood | Impact | Mitigation | Owner |
| - | --- | --- | --- | --- | --- |
| K1 | *(Mostly retired Nov 10: the backend is in `main` and on prod.)* **Supabase not live on prod in time for submission** | Low | **High** | Swift data layer moved to Ethan (N21); `API.md` + E1 frozen Fri noon; B3 in two drops Sat; chat messaging (B20) treated as 0.6; cut check Sat evening; go/no-go #2 Sun noon; never submit a mock build — if must-haves slip, submit the day they're live, backstop Mon Nov 16 | Emilio, Ethan |
| K2 | Access blockers (O2 Supabase Owner, O3 team Gmail, O4 Tec IT answers) still not done | **High** | High | Due tonight (Thu Nov 5); B1 Fri morning can't start without O2, and B2 Sat morning can't finish without a real Tec account from O4 (K19) | Ricardo |
| K3 | 0.5 rejected or stuck in review past Demo Day #2 | Medium | Medium | §10.4 checklist; submit Thu Nov 12 (N34), which leaves one day for a resubmit; resubmit within 24 h, last by Fri Nov 13; external TestFlight beta in parallel; worst case DD2 from TestFlight; 0.6 Mon Nov 16 | Ethan |
| K4 | *(Retired by N33: no sign-in email.)* Codes from Gmail land in Tec's junk folder | — | — | Replaced by school SSO | — |
| K5 | *(Retired by N33: no Gmail SMTP.)* Gmail daily cap or app-password revocation | — | — | Replaced by school SSO | — |
| K6 | No one's role can create the APNs key | Low | Medium | Check roles before Nov 22; ask the B&GC Admin if needed. 1.0 still ships the 1.0 UI, Spanish and Saved without push | Ethan |
| K7 | **1.0 is now bigger** (1.0 UI ~12 h on top of notifications, Spanish, Saved sync) and spans Thanksgiving | High | Medium | Start E27 the week of Nov 10 while 0.5 is in review; D2 + D8 frames by Nov 22; 1.0 cut order (§3) simplifies the court art first | Ethan, Arianna |
| K8 | Thanksgiving / end-of-term squeeze 1.0 | High | Medium | Emilio's notification backend Nov 21–28; 1.0 cut order | Both coders |
| K9 | Free Supabase project pauses or loses data | Low | Medium | Daily ping, weekly dump | Emilio |
| K10 | Empty map at launch (end of semester) | High | Medium | Real games lined up for beta and launch weeks; real campus push in February | Ricardo |
| K11 | Last-spot race or data bug | Low | High | Row lock + capacity check + race test (B10) | Emilio |
| K12 | "Verified student" untrue if staff share `@tec.mx` | Medium | Low | O4; pattern check or "Tec verified" badge | Ricardo |
| K13 | Group chat read as placeholder content (2.1), or messaging (B20 + E26) not ready | Medium | High | Sun Nov 8 rule: real messaging on prod, or the read-only fallback with no composer and no mock messages (§7.6.9) | Ethan, Emilio |
| K14 | Reviewers far from Monterrey see an empty map | High without fallback | High | Campus fallback (§7.6.1) + demo campus with auto-refreshed games (C12); remove the mock location (E9/E14) | Ethan, Emilio |
| K15 | Rushed RC ships a crash or a mock leftover | Medium | High | Known leftovers listed in N27 / E14; DEBUG-only tools; two-phone QA Sun Nov 8 | Ethan, Arianna |
| K16 | **1.0 UI quietly undoes privacy or scope decisions** (interests on Who's going, calendar-sync and name-visibility rows) | Medium | Medium | §7.7.6 defaults; D12 updates the Figma by Nov 11; Privacy page changes before any data becomes visible | Arianna, Ricardo, Emilio |
| K18 | **Tec doesn't work out as the launch campus** (no traction, IT won't approve sign-in, end of semester) | Medium | High | Campus is data, not code (N32); the move is a server change plus the non-app steps in §8.10, including that school's IT approval | Ricardo, Emilio |
| K17 | **Status drift**: Trello says done when the repo doesn't (E1), or shows no progress when work happened | High | Medium | Trello update at each go/no-go; "Done" means the "Done when" check passes in the repo (§6) | Everyone |
| K19 | **Top auth risk: Tec's tenant requires admin consent for the masUNO Entra app.** Until Tec IT grants it, real students can't sign in. Tec's rules may also require MFA or block sign-ins from abroad, which a reviewer's test account can't get past. | **High** | **High** | Try a real Tec account on dev as soon as B2 is up, which answers this without waiting for IT; contact Tec IT early (O4, today) with the client ID and consent link; ask for minimum scopes only, or have IT register the app in Tec's own tenant; test on a real iPhone (B21); the allowlisted review/demo login is the fallback for demo days. If real students still can't sign in at the Sun Nov 8 go/no-go, R7-14 decides | Ricardo, Emilio |
| K21 | **Spoofed `@tec.mx` sign-up from another Microsoft tenant** while prod uses `organizations` (N35): that tenant's admin sets a user's email to an `@tec.mx` address, and today's hook checks only the domain and provider | Medium once sign-in is public | High | B22 tenant check live on prod before real students can sign in or the external beta opens; until then, only Tec accounts that IT has approved and the allowlist are expected | Emilio |
| K20 | App Review argues masUNO is a social app, not an "education app", and asks for Sign in with Apple | Medium | High | Clear review notes (§10.4). Contingency: Sign in with Apple plus a school-email verification step | Ethan |

---

## 12. Decisions

### Rev. 7 — sign off at the Fri Nov 6 go/no-go (R7-1 and R7-2 in the team chat tonight)

| # | Decision | Default |
| - | --- | --- |
| R7-1 | N20 — submit 0.5 Mon Nov 9 on the live backend; all 0.5 work Fri–Sun Nov 6–8; go/no-go #2 Sun Nov 8 noon; backstop Mon Nov 16 | Approve (Ricardo); Emilio and Ethan confirm the weekend hours |
| R7-2 | N21 — Ethan owns `AuthService`, `GameStore` and the live repositories for 0.5 | Approve (Emilio) |
| R7-3 | N23 — built app = 0.5 UI; Figma + `DESIGN.md` v2.0 = 1.0 UI | Decided (Ethan, Nov 5) |
| R7-4 | Who's going rows in 1.0 show class year only (not interests) | Approve, or change the privacy policy first (§7.7.6) |
| R7-5 | No calendar-sync or name-visibility rows in 1.0 Settings | Approve |
| R7-6 | "Cancel game" (soft cancel) instead of "Delete game" in 1.0 | Approve |
| R7-7 | No "· Read" receipts in 1.0 chat | Approve |
| R7-8 | No mic glyph in 1.0 search | Approve |
| R7-9 | App language follows the phone from 1.0; English stays the development language | Approve |
| R7-10 | SF Pro Rounded in the app; Nunito in Figma and on the web | Approve (Arianna) |
| R7-11 | N32 — launch at Tec, but keep the campus as data so it can change without a release | Decided (Ethan, Nov 6) |
| R7-12 | N33 — sign-in is "Continue with school account" only: Supabase's Azure (Microsoft Entra ID) provider for Tec via `signInWithOAuth` in an ephemeral `ASWebAuthenticationSession`; the Google provider restricted to the school's domain for later Google Workspace schools | Decided (Ethan, Nov 6) |
| R7-13 | N33 — no consumer social login and no public email + password sign-up, which keeps the Guideline 4.8 education exemption (no Sign in with Apple required) | Decided (Ethan, Nov 6) |
| R7-14 | K19 — what happens if only allowlisted accounts can sign in at the Sun Nov 8 go/no-go | ⚑ Ricardo signs off; Ethan agrees (Nov 6). Still submit Mon Nov 9, with manual release, so the review slot isn't lost; release and open the external beta only once a real Tec account signs in on prod. Otherwise N20's slip rule applies |
| R7-16 | N35 — prod's Azure tenant stays `organizations`; the hook checks each campus's `tenant_id` (B22) | Decided (Ethan, Nov 10); ⚑ Emilio builds B22 |
| R7-17 | N34 — 0.5 submits Thu Nov 12; 0.6 stays Mon Nov 16 | Program manager (Nov 10) |
| R7-15 | Browse before sign-in (§7.7.6) | 0.5 keeps the gate (Ethan, Nov 6). ⚑ Team decides for 1.0 by Wed Nov 11 (D12); default is to keep the gate |

### Rev. 6 (Nov 3)

| # | Decision | Default |
| - | --- | --- |
| R6-1 | N11/N12 — submit 0.5 Mon Nov 9 on the live backend *(schedule compressed by R7-1)* | Approve |
| R6-2 | N14 — group chat in 0.5; messaging (B20 + E26) is a stretch; read-only fallback if it misses the RC | Decided (team, Nov 3) |
| R6-3 | N15/N16 — Saved (on the phone), calendar, invite, Google Maps, Past, Edit profile in 0.5 if live by feature freeze | Approve |
| R6-4 | N17 — Auto-repost is MVP (0.5) | Decided (team, Nov 3); its 1.0 look moves into D2 + D8 (N28) |

### Kickoff (Sun Nov 1) — still awaiting Ricardo (O1)

| # | Decision | Default |
| - | --- | --- |
| D-1 | C2 — no chat screen during the program *(reversed by R6-2)* | Superseded |
| D-2 | C3 — Add to Calendar button instead of sync *(in 0.5 per N16)* | Approve |
| D-3 | C4 — no photos during the program | Approve |
| D-4 | C5 — "First L." names | Approve |
| D-5 | C6/N2 — notifications in 1.0 | Approve |
| D-6 | N3/N4 — Gmail, GitHub Pages, one-page policy, free Supabase | Approve |
| D-7 | N6–N9 — roles, data-layer split *(changed by R7-2 for 0.5)*, Supabase access for Emilio, design leads the build | Approve |
| D-8 | Demo-day targets (testers, sign-ups, games) | Ricardo sets |
| D-9 | Team chat for report alerts (Discord or Slack) | Ricardo picks |

---

## 13. After the program

| When | What |
| --- | --- |
| January 2027 | Chat push and retention (Appendix A items 8–9) if not done, profile photos with moderation, calendar sync, name-visibility setting, links that open a specific game |
| Start of Tec's Feb–Jun semester | Campus launch (Ricardo): club hosts, recurring games, posters; own domain + email provider if the team wants them; Supabase Pro for backups |
| Later | Organizer approval, non-sport activities, IIT/UIC (new `universities` rows and their sign-in, §8.10), dark mode, meet-up photo, pin clustering |

---

## Appendix A — Chat v1 design (parked)

*Rev. 6: pulled forward as a 0.5 stretch goal (N14, B20/E26) — items 1–4 for 0.5, items 8 (push) and 9 (retention) still later. Items 6 (consent sheet) and 7 (unread) are built. If it misses the Nov 8 RC, it lands in 0.6 or 1.0.*

*Nov 10: built for 0.6 as items 1–7 and 9 (`docs/API.md`, Group chat). Differences from the list below: writes go through RPCs, not RLS inserts; system rows stay in `game_activity`; consent is `profiles.chat_rules_accepted_at`; the channel carries only a ping and the app reads the rows; messages are deleted 30 days after the game, and with the sender's account. Push (item 8) is still later.*


1. **Tables:** `chat_messages` (event, sender, kind system/user, body ≤ 1000, `client_id`, soft delete), `chat_reads`; `profile_private.chat_guidelines_accepted_at`; `app_config.chat_enabled`.
2. **Policy:** members of a game may post while it isn't cancelled and ended < 24 h ago, after accepting chat rules, if not banned and `chat_enabled` is on (checked in RLS).
3. **Abuse:** 20 messages/min limit, text filter, blocked senders hidden, reportable messages.
4. **Realtime:** Broadcast from Database on a private `game:<id>:chat` channel limited to members.
5. **Client:** latest 50 messages, then live; older pages by time; optimistic send with dedupe; "Tap to retry".
6. **Consent:** "Before you chat" sheet (Figma 341:2420), stored server-side.
7. **Unread:** "Group chat · N new" on Me cards; marked read on open.
8. **Push:** collapsed per game, ≤ 1 per 5 min, never to the sender; new setting "Group chat messages".
9. **Retention:** read-only 24 h after the game; message text deleted after 30 days.
10. **Estimate:** ~5–7 developer-days including the game-hub screen.

---

## Sources

- Supabase — [Login with Azure (email claim, tenant URL, `xms_edov`)](https://supabase.com/docs/guides/auth/social-login/auth-azure), [Pricing (free plan: 2 active projects, paused after 1 week inactive, no backups)](https://supabase.com/pricing), [Auth hooks (free-plan availability)](https://supabase.com/docs/guides/auth/auth-hooks), [Before User Created hook](https://supabase.com/docs/guides/auth/auth-hooks/before-user-created-hook), [Regions](https://supabase.com/docs/guides/platform/regions)
- supabase-swift — [`AuthClient.swift` at v2.55.6 (`signInWithOAuth`)](https://github.com/supabase/supabase-swift/blob/v2.55.6/Sources/Auth/AuthClient.swift)
- Microsoft — [Register an app](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app), [Grant admin consent](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/grant-admin-consent), [Auth code flow (`domain_hint`)](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow), [Optional claims (`email`, `upn`, `xms_edov`)](https://learn.microsoft.com/en-us/entra/identity-platform/optional-claims-reference), [Publisher verification and user consent](https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview)
- Apple — [Developer Forums: ephemeral sessions and the sign-in alert](https://developer.apple.com/forums/thread/775685), [App Review Guidelines (2.1(a) demo accounts, 2.5.19 hidden features, 4.8 Login Services)](https://developer.apple.com/app-store/review/guidelines/), [App Review (2.1 placeholder content; support and privacy links)](https://developer.apple.com/distribute/app-review/), [Program roles](https://developer.apple.com/help/account/manage-your-team/roles/), [TN3152: Calendar access levels](https://developer.apple.com/documentation/technotes/tn3152-migrating-to-the-latest-calendar-access-levels), [Offering account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app), [Guideline 1.2 checklist (forums)](https://developer.apple.com/forums/thread/807358)
- Program schedule — App Accelerator calendar, Weeks 7–13 (team copy)
- Design — Figma "masuno figma" (file `5eKA3f0I90VVABrAuNMFD2`, rows 1–8) and `DESIGN.md` v2.0 in the masUNO project (Nov 5)
- Status — `masUNO-app/ios` `main` @ `96b270c` (Nov 4) and the Trello board "2026 UnaMas" (read Nov 5)
