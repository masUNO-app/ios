# masUNO 0.9: App Store submission readiness

**Audited:** Nov 19, 2026 · branch `path-to-1.0` at `2de4f5a` · Xcode 27.2 (27B52), iOS 27.2 SDK
**Scope:** what stands between this repo and a clean first-pass App Review for **0.9**, plus the screenshot plan (iPhone and iPhone Duo). Anything that can wait is tagged **for 1.0**.
**Method:** read the code, migrations and website repo; built Release for device (unsigned) and Debug for the simulator; captured screens on an iPhone 18 Pro and on the iPhone Duo (folded and open) from Device Hub. No app code was changed.
**Owners:** Ethan (iOS screens, submission) · Emilio (Supabase, data layer) · Arianna (design, icon, framing) · Ricardo (lead, listing, policy, testers)

> **The repo wins.** The brief said 0.9 has no chat, push, Saved, Spanish or profile photos. The build actually has group chat (read-only or live behind `chat_enabled`), push notifications (sending gated by `push_enabled` on the server), Saved synced to the account, a full Spanish UI, invite codes with a waitlist, guest browsing, dark mode and a fifth sport, padel. Only profile photos are truly absent. Appendix A lists every place the brief and the repo disagree.

---

## 1. Verdict

**Not yet.** The binary is in good shape:

- It builds clean in Release (0.9, build 9, iOS 18.0+).
- It ships no debug menus, mocks or keys, and both privacy manifests are present.
- Every UGC requirement is built and backed by the server: guidelines agreed at sign-up, a text filter, report, block, Blocked people, Contact us, and a delete-account flow that really deletes.

What blocks a first-pass approval is everything around the binary. **Group chat and notifications ship in 0.9** (decided Nov 19). Eight blockers:

1. Turn group chat on in prod before upload, and declare it in the listing, privacy label and age rating. With `chat_enabled` off, every joined game's main button, **Open group chat**, leads to a screen with no composer.
2. Turn notifications on in prod the same way. The app asks for permission and shows six notification switches, but nothing sends until `push_enabled` is true and the APNs key is in place.
3. Rewrite the review notes. They describe a one-time code, a **Join game** button and a flag icon, and none of those exist.
4. Complete the privacy label and manifest. Precise location, a device token and install ID, notification-open tracking, and class year and sports all leave the device and aren't declared.
5. Update the Privacy & Terms page. It still describes school SSO sign-in, Saved stored only on the phone, and "notifications in a later version". It also needs a content-license line, which the "Yes, we have the rights" answer depends on.
6. Set a new build number. Build 9 is almost certainly on TestFlight already.
7. Confirm prod is ready: migrations, flags, review accounts, demo cron.
8. Fix the screenshot data. The fixtures show real teammates and clock-relative times like "11:31 PM".

All eight are small. About **12–15 focused hours** across the team, most of it prod setup, two-phone QA and copy. The iPhone Duo layout is **not** a 0.9 blocker. Recommendation: skip Duo screenshots for 0.9 and do the inner-display layout in 1.0 (§7).

---

## 2. Blockers (fix before submitting 0.9)

| # | What | Where | Fix | Est. | Owner |
| --- | --- | --- | --- | --- | --- |
| B1 | **Group chat ships in 0.9, so it has to work on prod during review.** Chat's entry points are always on screen: **Open group chat** in You're in and the host's bar, Me's game cards, the Settings switch. Messaging follows `app_config.chat_enabled` (default `false`, `20261110000000_group_chat.sql:9`). Left off, a reviewer opens a chat with no composer (2.1). The app reads the flag at launch, so it must be on **before** review and stay on. Don't flip it after approval: SPEC §10.4 records the rule against remote flags turning on unreviewed features. | `app_config.chat_enabled` on `masuno-prod`; `GroupChatView`, `ChatViewModel`; `docs/QA.md` §8; `supabase/README.md` step 8 (Realtime broadcast policy) | **Before upload:** <br>• Apply `20261123000000_chat_mentions` to prod. <br>• Check the Realtime broadcast policy (README step 8). <br>• Set `chat_enabled = true`. <br>• Run QA §8 on two phones against prod: send, mention, report a message, block from chat, chat closes on cancel. <br>Then cover it everywhere it's declared: age rating Messaging = Yes, privacy label Emails or Text Messages (B4), review notes and listing lines (§5), policy (B5). | 30 min prod + 1 h two-phone QA | Emilio (prod), Arianna or Ricardo (QA) |
| B2 | **Notifications ship in 0.9, so prod has to send them.** The primer appears after the first join or hosted game (`GameStore.swift:978, 1029`). The waitlist offers "Want a heads-up when you're in?" Settings lists six switches, and full games offer **Alert me if a spot opens**. Sending is gated only on the server (`push_enabled`, default `false`, `20261116000000_notifications.sql:138`). With it off, a reviewer can turn on alerts that never arrive. | `app_config.push_enabled`; Supabase secrets; `supabase/functions/send-push`; `docs/QA.md` §12 | **Before upload:** <br>• Create the APNs key (Admin or App Manager role) and store it in the password manager and Supabase secrets (SPEC §10.1). <br>• Deploy `send-push`. <br>• Set `push_enabled = true` on prod. <br>• Run QA §12 with a **TestFlight build** (production APNs, which matches the Release entitlement): primer, "You're in", spot alert, reminder, game changed or cancelled, chat and mention pushes, Mute, Reply. <br>The privacy label (B4: Device ID) and policy (B5) already need to cover this. | 2 h prod + 1 h QA | Emilio (prod), Ethan (TestFlight build), Arianna or Ricardo (QA) |
| B3 | **The review notes describe a different app.** Sign-in is email and **password** for everyone, not a one-time code. Joining is **Count me in** (on the map popup or the game screen), not "Join game". Who's going uses a **•••** menu, not a flag. | `OnboardingViewModel` (password sign-up and sign-in, waitlist), `EventPopup.swift:80`, `EventDetailView.swift:380`, `WhoIsGoingSheet.swift:110` | Use the corrected notes in §5. | 15 min | Ricardo |
| B4 | **Privacy label and manifest are incomplete.** **Precise location:** "Use my current location" sends the raw device fix as the game's `p_lat`/`p_lng` (`LocationService.currentPlace` → `GameDraftParams`). **Device ID:** `register_device` sends the APNs token and a per-install random ID. **Product interaction:** `notification_opened` is tap tracking for demo-day numbers (NOTIF §5.2). **Other data:** class year, sports, language. None of these are declared. | `MasUno/PrivacyInfo.xcprivacy` (`NSPrivacyCollectedDataTypes`); App Store Connect > App Privacy | Add `PreciseLocation`, `EmailsOrTextMessages` (chat), `DeviceID`, `ProductInteraction` (purposes App Functionality and Analytics) and `OtherDataTypes` to the manifest. Answer App Privacy as in §5. | 30 min manifest + 30 min ASC | Ethan (manifest), Ricardo (ASC) |
| B5 | **Privacy & Terms page and the location wording don't match the build.** The website's `privacy.html` (Nov 11) says: sign-in goes through your school's Microsoft page; Saved lives only on the phone; notifications and Spanish are "coming in a later version"; no analytics. It doesn't mention invite codes, the waitlist, its Google Sheet mirror, the install ID, or a license to show user content (see §5, Content rights). The location purpose string says "It's never shared with other people", and the map primer says "Your exact spot is never shared." Both are false once a host picks "Use my current location": that exact spot becomes the game's place. | `masUNO-app.github.io/privacy.html`; `project.yml` `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`; `MasUno/en.lproj` and `es.lproj/InfoPlist.strings`; `EventMapView.swift:137` | Rewrite the policy sections listed. Move notifications out of "Coming in a later version" into *What we collect*: device token, install ID, notification settings and which notifications you open. Say group chat messaging is on, not "where available". Proposed purpose string: *"masUNO uses your location to center the map and show how far games are. It's only shared if you choose to post a game at your current location."* Map primer: *"…Your location stays on your phone unless you post a game at your current spot."* | 1.5 h policy · 20 min strings + Spanish | Ricardo + Emilio (policy), Ethan (strings) |
| B6 | **Build number.** `CURRENT_PROJECT_VERSION` is `9` on both targets. The "Build 9" commit (`de6ef92`) and the README suggest 0.9 (9) is already on TestFlight, and App Store Connect rejects a duplicate. Marketing version `0.9` ✅. | `project.yml` (`masUNO` and `masUNONotifications`) | Set both to `10` (or one above the highest uploaded), run `xcodegen generate`, and check the scheme still has `-liveAuth YES` (memory: xcodegen wipes manual scheme edits). | 5 min | Ethan |
| B7 | **Prod state can't be confirmed from the repo** (the Supabase MCP isn't authorized in this session). README still lists "apply the newer migrations to prod" as open. | `supabase/migrations` (through `20261123000000_chat_mentions`), `app_config` | Confirm on `masuno-prod`: <br>• All migrations are applied, especially `security_fixes`, `block_privacy` and `chat_mentions`. <br>• The `chat_enabled` and `push_enabled` values match B1 and B2. <br>• `min_supported_version` ≤ `0.9`. <br>• The review1 and review2 accounts exist and land on the demo campus. Has each one finished Make it yours, or will the reviewer see it? <br>• The `refresh-demo-campus` cron shows 6 upcoming games. <br>• The `delete-account` function is deployed. | 1 h | Emilio |
| B8 | **Screenshot data isn't usable.** The fixtures use real teammates: the signed-in user is "Emilio Garza" (the "EG" token on every map), and "Ricardo T." is on the open game. Times follow the wall clock ("Today 11:31 PM", "Tomorrow 1:56 AM"). The open game is "After-work hoops". | `MasUno/Data/Mocks/MockFixtures.swift` (DEBUG-only, never ships) | Add a screenshot world behind `-screenshots YES` (§6): invented people, fixed afternoon and evening times, college titles. | 1.5 h | Ethan |

**Total:** about 3.5 h of app work (B4, B5 strings, B6, B8), 3.5 h of prod setup (B1, B2, B7), 2 h of two-phone QA, 3 h of policy and copy.

**Status (Nov 19, after the fix pass, uncommitted on `path-to-1.0`):**
- **Done in the repo:**
  - B4: manifest lists the nine collected types.
  - B5: purpose string, map primer and Spanish; policy change set in Appendix C.
  - B6: build 10 on both targets; project regenerated, scheme unchanged.
  - B8: `-screenshots YES` world in `MockFixtures`, plus `scripts/screenshots.sh`.
  - S1: Supabase side, migration `20261124000000_delete_signup_request` with pgTAP checks.
  - S2: runbook line in `supabase/README.md`.
  - S4: form placeholder.
- **Still open:**
  - B1, B2, B7: prod flags, APNs, migrations (Emilio).
  - B3: notes into App Store Connect.
  - B5: policy applied on the website, plus Spanish (Ricardo).
  - S5, S6, S7.

---

## 3. Should fix (lower risk, same format)

| # | What | Where | Fix | Est. | Owner |
| --- | --- | --- | --- | --- | --- |
| S1 | **Account deletion leaves the email behind.** `delete_my_account_data` and `auth.admin.deleteUser` remove the profile, games, RSVPs and blocks. The person's row in `private.signup_requests`, keyed by email, survives, and so does its copy in the waitlist Google Sheet. That conflicts with the listing ("Delete your account anytime") and the policy ("removed right away"). | `supabase/functions/delete-account/index.ts`, `public.delete_my_account_data` (`20261109000000_review_fixes.sql`), `private.signup_requests` | ✅ **Done (Supabase side):** `20261124000000_delete_signup_request` deletes the row; the delete trigger sends `removed`. Two assertions added to `safety_and_deletion.test.sql` (not run locally: no Docker; CI's Database job runs them). **Left:** the Apps Script should delete Sheet rows that arrive as `removed`, and Emilio applies the migration to prod. | 30 min left | Emilio |
| S2 | **A deleted review account comes back on the waitlist.** Reviewers often test Delete account. Since `20261119000000_security_fixes`, an allowlisted email that signs up with a password goes through `request_signup`, so re-creating the account from the dashboard probably lands it in `pending` (the waitlist screen). | `public.before_user_created` | ✅ **Resolved:** README step 5 says accounts created in the dashboard skip the sign-up hook, so a re-created review account goes straight in. Added a runbook line (re-create before the next submission). The review notes (§5) still ask reviewers to test deletion on account 2. | — | Emilio |
| S3 | **Listing claims vs the build.** Sports omit padel. Invite-only and the waitlist aren't mentioned, so a downloader will be surprised. Guest browsing isn't mentioned. Caption 6's "verified by email" is wrong: there's no email confirmation, and trust comes from the @tec.mx domain check plus team approval or an invite. | Listing draft | Corrected copy in §5. | 20 min | Ricardo |
| S4 | **Form placeholder** "e.g. After-work hoops" doesn't fit the college voice and shows in an empty-form screenshot. | `GameFormSheet.swift:90` | "e.g. Pickup after class", plus Spanish. | 10 min | Ethan, Ricardo |
| S5 | **App icon is the "temporary one from the designer"** (README D3). The compiled 1024 px icons are opaque in every appearance ✅, but the Icon Composer layers are 1025×1025 and 1025×1024. | `MasUno/AppIcon.icon` | Final icon, with layers at exactly 1024. | 1–2 h | Arianna |
| S6 | **Edge states not exercised live in this audit.** The code handles all three: it falls back to the campus when location is denied or the fix is far away (`EventMapViewModel.centerIfNeeded`), offline shows a notice and retry cards, and Release without keys uses `UnavailableBackend`. | `docs/QA.md` §1–§9 | Run airplane mode, location denied and a far-away simulated location on a physical phone with the **exact** build uploaded. | 1 h | Arianna, Ricardo |
| S7 | **Seller name.** The team is `PU87MU4QAR` (Boys & Girls Clubs of Chicago), so the listing shows that organization as the seller, next to copy saying masUNO is an independent student project. | `project.yml` `DEVELOPMENT_TEAM` | Confirm that's intended (Open questions). | — | Ricardo |
| S8 | **CI's Release build doesn't compile the Duo code.** `build-release` and `test-ios26` use Xcode 26.6, so the Release configuration of the code behind `#if compiler(>=6.4)` (`BarLayout`, `Fold`) is never built in CI; `test-ios27` (Xcode 27.2) builds it in Debug. | `.github/workflows/ios.yml` | Archive locally with Xcode 27.2 (already the case), or move `build-release` to 27.2. | — | Ethan |

---

## 4. For 1.0 (don't block 0.9)

| # | What | Where | Fix | Est. | Owner |
| --- | --- | --- | --- | --- | --- |
| F1 | **iPhone Duo inner display: the map is good, nothing else is laid out for it.** Open landscape (2853×2007): game detail and the form are a centered phone-width column with wide empty margins, and there's no map-plus-detail split. Apple asks for an inner layout that "should look like a natural extension of its iPad layout." | `EventDetailView`, `GameFormSheet`, `ContentView.main` (`NavigationStack`), `Theme.readableColumn` | On the open display, show the map with the selected game's detail beside it (two panes, `NavigationSplitView` or a custom split) once the width is ≥ 2 × `Theme.cardMinWidth`. Game detail: court on the left, info on the right. Form: two columns. | 10–14 h + 3 h frames | Ethan, Arianna |
| F2 | **Duo outer polish.** On the cover display (466 pt wide) the map popup's time line truncates ("starts in 34…") and **Count me in** wraps to two lines. | `EventPopup.swift` | Let the time line wrap. Give the primary button priority or shorten "Details". | 1 h | Ethan |
| F3 | **Duo screenshots and the "Made for iPhone Duo" badge.** They become required in April 2027 for apps built with the iOS 27.1 SDK or later, and we already build with 27.2. | §7 | Capture after F1 and F2. | 1 h | Arianna, Ethan |
| F4 | **Chat and push watch after launch.** Both ship in 0.9; 1.0 is when real volume arrives. | `docs/NOTIF.md` throttles, the report-alert channel | Review the push throttles and quiet hours against real use. Check the moderation load from message reports after the Dec 16 launch. | 1 h | Emilio, Ricardo |
| F5 | **Repeatable screenshots.** | new `scripts/screenshots.sh` (proposal in §6) | Commit the script and the `-screenshots` world. Optionally an `XCUITest` that does the same. | 1–2 h | Ethan |
| F6 | **Partially-open and inner-portrait poses** weren't captured in this audit (only folded and open landscape). | QA.md §11 | Run the §11 checklist in all four poses before 1.0. | 1 h | Ethan |

---

## 5. App Store Connect values

### Listing (corrected against the build; counts measured)

**Name (6/30):** masUNO · fallback *masUNO: Find Your People* (availability ❓)
**Subtitle (27/30):** Groups looking for one more · alt *Make plans, meet your people*
**Category:** Social Networking (primary), Sports (secondary)
**Privacy Policy URL:** https://masuno-app.github.io/privacy (only after B5)
**Support URL:** https://masuno-app.github.io/support ✅ (the page exists; it says "tap join", so consider "tap Count me in")
**Marketing URL:** https://masuno-app.github.io
**Copyright:** 2026 masUNO

**Promotional text (169/170):** *changed: padel added, em dash swapped for a comma to fit*
> College is better when you say yes. Find groups near campus that need one more person and jump in, starting with pickup basketball, soccer, tennis, volleyball and padel.

**Keywords (94/100 bytes):** *changed: `games` swapped for `padel`, since "games" is weak and padel is real*
`college,freshman,campus,friends,activities,meetup,pickup,sports,basketball,soccer,futbol,padel`

**Description (1,818/4,000):** changes are padel, the guest line, the invite-only line, and two lines for group chat and alerts (both ship in 0.9).

```
The best parts of college happen when someone says "we need one more."

masUNO shows you groups around Tec de Monterrey that are one or two people short — and looking for you. Tap in, see who's going, and show up. No asking around, no awkward "can I join?" moment. Just a yes, and a group that's glad you came.

We're starting with pickup sports, because a game that's one player short is the easiest invitation there is.

FIND SOMETHING TO DO
• See what's happening near you on a map: basketball, soccer, tennis, volleyball and padel to start
• Check the time, the place, how many spots are left and who's going
• Join with one tap, then open the spot in Apple Maps to get there
• Full groups drop off the map, so everything you see has room for you
• Once you're in, say hi in the group chat and get a heads-up if the time or place changes
• Save a full game and we'll let you know the moment a spot opens
• Not sure yet? Browse as a guest before you make an account

START SOMETHING
• Post a game in under a minute: what, when, where and how many people you need
• Add a meet-up spot so people know exactly where to find you
• Edit or cancel anytime, and everyone going sees the change

JUST FOR TEC STUDENTS
• Sign up with your @tec.mx email, so everyone on masUNO is a fellow student
• masUNO is invite-only for now: a friend's invite code gets you in right away, or join the waitlist
• Others see only your first name, last initial and class year
• Report or block anyone from the Who's going list. Our team reviews every report within 24 hours
• Delete your account anytime in Settings

First week or fourth year, new in town or just new to the group, there's a spot waiting for you. Find it on masUNO.

masUNO is an independent student project and isn't affiliated with or endorsed by Tecnológico de Monterrey.
```

**Claim check** (every factual line traced to code):

| Claim | Verdict | Evidence |
| --- | --- | --- |
| Full groups drop off the map | ✅ | `GameStore.mapGames` filters `isFull`, cancelled and ended |
| Join with one tap | ✅ | **Count me in** on the map popup joins at once (`AppViewModel.joinAndOpen`) |
| Open in Apple Maps | ✅ | **Open in Maps** on game detail; Apple Maps, or a choice of Apple or Google Maps when Google Maps is installed (`EventDetailView` `confirmationDialog("Open in")`) |
| Edit or cancel; people going see the change | ✅ | **Edit game** in the host's action bar; **Cancel game** in the More menu and in the form; realtime game lists (`20261112000000_games_realtime`); the "game changed" push only if `push_enabled` |
| Who's going with report/block | ✅ (wording) | It's a **•••** menu with **Report {name}** and **Block {name}**, not a flag (`WhoIsGoingSheet.swift:110`) |
| First name, last initial, class year | ✅ | Who's going row shows "Alex R." and "Class of 2027"; the onboarding preview says the same |
| Meet-up spot | ✅ | Form field **Meet-up spot (optional)**; shown under the place on detail |
| Group chat once you're in | ✅ if B1 is done | **Open group chat** on You're in; messaging needs `chat_enabled = true` on prod |
| Heads-up if the time or place changes | ✅ if B2 is done | "Game changed" push, always on (no switch); needs `push_enabled = true` and the APNs key |
| Alert when a spot opens | ✅ if B2 is done | **Alert me if a spot opens** on a full game (`set_spot_alert`), Settings › "A spot opens up" |
| Sports | ⚠️ was 4, really 5 | `activities` seed includes padel (`20261107000000_initial_backend.sql:509`) |
| Reports reviewed within 24 h | ✅ consistent | The app says "We'll look into it within a day" (`ReportSheet`) |
| Delete account in Settings | ✅ | Settings › **Delete account** → **Delete account** (the `delete-account` Edge Function); see S1 |
| Sign in with @tec.mx | ✅ with caveat | Only open-campus domains can sign up (auth hook); access is invite code or team approval; no email confirmation |

### App Review notes (replace the draft)

The draft is wrong about the sign-in method, the button labels and the report icon. Exact on-screen wording is in **bold**:

```
masUNO is for students at Tec de Monterrey. New accounts use a school email (@tec.mx) and a password, and are let in by our team or with a member's invite code. The review accounts above are pre-approved and sign in with a password; they open on a demo campus with joinable games that refresh daily.

To sign in: Get started → I already have an account → enter the email and password → Sign in. If asked, fill in Make it yours and tap I agree on "Before you play" (our community guidelines).

To join: tap a pin on the map, then Count me in (or Details → Count me in). To host: tap Add game (the green + button at the bottom of the map), fill it in, then Create game.

Group chat: after joining, Open group chat lets the people going to that game message each other (only members of that game can read it, and it closes 24 hours after the game ends). Demo hosts don't reply; to see a conversation, sign in with both review accounts on two devices and join the same game. Touch and hold someone's message → Report message or Block [name]. Notifications are optional: the app asks after your first join, and Me → Settings → Notifications has the switches.

To report or block: open a game → Who's going → tap ••• next to a name → Report [name] or Block [name]. To report a game: the ••• button at the top right of the game screen → Report game. Reports go to our moderation team and are reviewed within 24 hours. Blocked people and their games disappear right away. To undo: tap your initials at the bottom right of the map (Me) → the gear (Settings) → Blocked people → Unblock.

To delete an account: Me → Settings → Delete account → Delete account. Please use review account 2 if you test deletion, so account 1 stays available.

There is no Sign in with Apple because masUNO doesn't offer any third-party or social login; accounts are masUNO's own email-and-password accounts, limited to students at an open campus.
```

The chat lines assume B1 is done (`chat_enabled` on in prod for the whole review). Message actions are in `GroupChatView.messageActions` (**Report message**, **Block {name}**).

### App Privacy (derived from what the code sends)

Collected: **Yes**. Tracking: **No** (no ads SDK, no IDFA, no `AppTrackingTransparency`; the manifest has `NSPrivacyTracking = false`).

| Data type | Linked | Purposes | Why (code) |
| --- | --- | --- | --- |
| Contact Info › Email Address | Yes | App Functionality | `signUp`/`signIn(email:password:)`; never shown to others |
| Contact Info › Name | Yes | App Functionality | `complete_profile` first and last name; others see first name and last initial |
| Location › **Precise Location** | Yes | App Functionality | "Use my current location" sends the device fix as the game's coordinates (`LocationService.currentPlace` → `create_game p_lat/p_lng`) |
| User Content › Other User Content | Yes | App Functionality | Games (title, notes, place, meet-up spot), reports and notes, blocks |
| Identifiers › User ID | Yes | App Functionality | Supabase user ID |
| Identifiers › **Device ID** | Yes | App Functionality | APNs token plus a random per-install ID (`register_device`, `PushNotificationService.refreshRegistration`) |
| Usage Data › **Product Interaction** | Yes | **Analytics**, App Functionality | `notification_opened` (tap tracking for metrics), bookmarks and spot alerts (`set_bookmark`, `set_spot_alert`) |
| Other Data › Other Data Types | Yes | App Functionality | Class year, sports you play, app language (`complete_profile p_grad_year/p_interests/p_locale`), beta-tester badge |
| User Content › Emails or Text Messages | Yes | App Functionality | Group chat (`send_message`, including @mentions); purged 30 days after the game ends |

Not collected: contacts, photos, health, financial info, browsing or search history (map search goes to Apple's MapKit, not to us), diagnostics (crash reports reach us only through Apple's opt-in, which isn't developer collection).

**Manifest:** `MasUno/PrivacyInfo.xcprivacy` declares UserDefaults `CA92.1` and `1C8F.1` ✅ (the only required-reason API we use: no file timestamps, disk space or boot time). The collected-data list needs B4's additions. The extension's manifest (`1C8F.1`, no collection) ✅. Dependencies: swift-crypto ships its own manifests; supabase-swift 2.55.6 ships none, and isn't on Apple's list of SDKs that must.

### Age rating inputs

Answer from the build, not the draft:

- **User-generated content:** Yes.
- **Messaging and chat:** Yes. Group chat between people going to the same game ships in 0.9.
- **Location sharing:** games show a host-chosen meeting place, and can be at the host's current location. Answer Yes if the questionnaire asks, and the "Shared Location" descriptor (SPEC §10.4; required from Jan 12, 2027).
- **Dating:** No.
- **Unrestricted web access:** No. Links open Safari or Mail; there's no in-app browser.
- **Gambling, contests, violence, mature themes, medical, alcohol and tobacco:** None.
- **Social media capability question:** answer before upload (SPEC §10.4).
- The policy says users are 17+. Make sure the questionnaire's result and the policy agree. ❓ Ricardo.

### Export compliance
`ITSAppUsesNonExemptEncryption = NO` is in the built Info.plist ✅. Networking is HTTPS only. swift-crypto is used for auth hashing (PKCE), which is exempt. App Store Connect won't ask on upload.

### Content rights
Answer: **"Yes, it contains third-party content and we have the rights."** That's only true once the Terms grant it. `privacy.html` has rules and moderation but **no license line** ⚠️ (B5). Proposed line under *Community rules and safety*:

> You keep ownership of what you post on masUNO (game names, notes, meet-up spots and your profile name). By posting it, you give masUNO permission to store it and show it to other students in the app, for as long as it's on masUNO. That permission ends when you delete the content or your account, except for copies kept with reports for moderation.

---

## 6. Screenshot plan

### Devices and sizes

- **iPhone (as you asked): iPhone 18 Pro, iOS 27.2.** It captures at **1206 × 2622**, which is the **6.3-inch slot**, not the 6.9-inch one. If App Store Connect's Media Manager marks 6.9-inch as mandatory, run the same script on **iPhone 18 Pro Max** (expected 1320 × 2868; confirm on the first capture) and upload that set too. ❓ Ethan, check Media Manager.
- **Format:** `simctl io … screenshot` saves PNGs with an alpha channel, which App Store Connect rejects. Use `--type=jpeg` or flatten before upload.
- **Light mode, English, default text size, status bar 9:41.** The `simctl status_bar` override works on the iPhone and on the Duo, where it renders as the Duo's vertical status column.

### Shot list (6, plus 1 optional; iPhone)

Captions are under 40 characters, sentence case, no period; counts are measured.

| # | Screen and exact state | Data shown | Caption | Framing notes (Arianna) |
| --- | --- | --- | --- | --- |
| 1 | Map with one pin selected: `-screen popup` | 5–6 pins around Tec, pin-group bubbles with initials, the selected basketball popup with **Count me in** | **Groups near you, looking for one more** (37) | Lead shot. The popup is the hero; keep the **+ Add game** pill visible. |
| 2 | Game detail, Open: `-screen detail-open` | Court with 2 players and "+1" open spots, **Room for 4 more**, **Who's going ›**, host note, time and place | **See who's going before you go** (29) | Crop at the time card. The named tokens on the court carry "who's going". |
| 3 | Game detail right after joining (**You're in!**): `-screen detail-in` | "You" on the court, **You're in!**, "…Say hi in the group chat, or just show up.", time and place, **Add to calendar**, **Open group chat** / **Invite a friend** | **Say yes in one tap** (18) | Keep both buttons in frame: the chat button now shows what happens after yes. |
| 4 | Add game, filled: `-screen add-filled` | Sport, name, Date/Start time/Duration, Location card, **Meet-up spot (optional)**, Players, **Create game** | **Start something in under a minute** (33) | Keep the meet-up spot field in frame. |
| 5 | Me, Going tab: `-screen me` | Profile card, **Going / Hosting**, a Coming up game card | **All your plans in one place** (27) | **Invite friends** shows the invite-only model, which is fine. |
| 6 | **Before you play** (community guidelines): `-screen onboarding-guidelines` | Four rules, "You can report or block anyone…", **I agree** | **Just Tec students, playing fair** (31) | Replaces "verified by email": there's no email verification step. Safety reads well for parents and freshmen. |

| 7 *(optional, recommended)* | Group chat: `-screen chat` | Pinned card (time, place, meet-up spot), a few messages from invented players, one "@You" mention highlighted, the composer | **Plan it together before you show up** (35) | Chat ships in 0.9, and it's the "meeting people" moment the brand is about. Put it 3rd or 4th; drop shot 6 if we want to stay at 6. **Never show a push banner** in a frame: the status-bar override can't fake one honestly. |

Everything shown is in 0.9: chat (B1), alerts (B2), and the map's bookmark button for Saved in shot 1.

### Seed data (DEBUG-only screenshot world, B8)

Add `-screenshots YES` to `MockFixtures.world(now:)`. When it's set:

- **People (invented, "First L."):** you are **Andrea Villarreal** ("Andrea V." to others, Class of 2029); others Sofía R., Diego T., Valeria G., Mateo C., Camila P., Luis H., Regina S. No team member's name.
- **Times of day:** games sit at fixed afternoon and evening times (5:30 PM, 6:45 PM, 7:00 PM, 8:00 PM; Sunday 5v5 two days out at 10:00 AM) on a base day: today when captured before 3 PM, tomorrow after. So a 10 PM capture still reads "Tomorrow · 5:30 PM", not "1:56 AM".
- **Games near 25.6514, -100.2895** (same IDs and states as the default fixtures; the cancelled one is left out):
  - "Pickup after class" (basketball, Tec basketball courts, room for 4 more)
  - "Doubles, bring a racket" (tennis, last spot)
  - "Padel after class" (padel, Centro Deportivo Tec, full)
  - "Sunset volleyball" (Parque Distrito Tec, you're going)
  - "Sunday 5v5" (soccer, Estadio Borregos, you're hosting)
  - "Fútbol 7 after class" (soccer, just bumped)
  - "Shootaround before class" (ended, in Past)
- **Host notes:** "First time? Come anyway, we rotate every game." No reported, blocked, cancelled, ended or test content in the screenshot world.
- **Chat (shot 7), on "Sunset volleyball"** (host Mateo C.), meet-up spot "Sand court, by the palm trees". Mateo C.: "Net's up on the sand court. Bring water 🏐". Camila P.: "I can bring a second ball". You: "Perfect. First time playing with you all, see you there!". Mateo C.: "Welcome @Andrea V.! We start with a quick warm-up at 10 to."

### Capture steps (proposal for `scripts/screenshots.sh`, not committed)

```sh
# Build Debug once, then for each device:
UDID=<iPhone 18 Pro udid>
xcrun simctl boot $UDID && xcrun simctl bootstatus $UDID -b
xcrun simctl install $UDID <DerivedData>/Debug-iphonesimulator/masUNO.app
xcrun simctl privacy $UDID grant location com.masuno.app
xcrun simctl ui $UDID appearance light
xcrun simctl status_bar $UDID override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
for s in popup detail-open detail-in add-filled me onboarding-guidelines chat; do
  xcrun simctl terminate $UDID com.masuno.app
  xcrun simctl launch $UDID com.masuno.app -liveAuth NO -mockLocation YES -appearance light -screenshots YES -screen $s
  sleep 8   # the first cold launch on the Duo took ~10 s
  xcrun simctl io $UDID screenshot --type=jpeg out/iphone-$s.jpg
done
```

`-screen` is compiled only into Debug. No debug overlay shows: the component gallery's long-press is DEBUG-only and isn't triggered. **For 1.0 (F5):** commit this script, or turn it into an `XCUITest` that launches each `-screen` and attaches `XCUIScreen.main.screenshot()`.

---

## 7. iPhone Duo

### Readiness findings

| Check | Result |
| --- | --- |
| SDK and Xcode | ✅ Release builds with **Xcode 27.2 (27B52), iOS 27.2 SDK** (`DTSDKName iphoneos27.2`), a release Xcode, not a beta. That's ≥ 27.1, so the app already resizes on the Duo, and Duo screenshots become **required from April 2027** for our builds. |
| Duo-aware code | ✅ Already there: `BarLayout` reads `toolbarVerticalEdge` (vertical bar on the cover display and in open landscape), `Fold.swift` reads the `.division` reserved region (dialogs and the chat column stay off the fold), and `CardGrid` goes by width. ⚠️ CI (Xcode 26) never compiles these paths (S8). |
| "Face ID" text | ✅ None. No biometrics at all. |
| Device-idiom or screen-size checks | ✅ None (`userInterfaceIdiom`, `UIScreen.main` not used). One `horizontalSizeClass` read in `EventMapView`. `UISupportedInterfaceOrientations` is portrait-only, but the Duo's open display runs in landscape anyway (observed). |
| Simulator and capture | Host the Duo in **Device Hub** (Xcode ▸ Open Developer Tool ▸ Device Hub). A headless `simctl boot` brings it up with no displays and SpringBoard crashes. Pose from Device Hub; capture with `simctl io <udid> screenshot --display=<id>`, taking the ID from `simctl io <udid> enumerate` (outer = the 1398 px display, inner = the 2007 px one; IDs change each boot). A display that's off still saves a valid all-black file, so check each image. |

**How each shot looks** (captured Nov 19):

| Screen | Outer, folded (1398 × 2034) | Inner, open landscape (2853 × 2007) |
| --- | --- | --- |
| Map with popup | ✅ Intentional: controls move into the right-hand vertical column, popup fits. ⚠️ "starts in 34…" truncates; **Count me in** wraps (F2). | ✅ Very good: the map fills the canvas, the popup is anchored to its pin, controls are in the side column, **Add game** bottom left. |
| Game detail, Open | ✅ Court plus sheet; back and More sit in the side column; the time card scrolls under the action bar. | ⚠️ Centered phone-width column with wide empty margins on both sides; the court is centered in a band of color. Reads as a stretched phone column. |
| You're in | ✅ Fits; **Open group chat** and **Invite a friend** stack full width. | Not captured (same layout as Open). |
| Group chat | Not captured. | Not captured. By code, the chat column stays off the fold when partially open (`GroupChatView` reads `activeFold`). |
| Add game, filled | ✅ Sheet fits; Location card wraps to two lines; **Create game** pinned. | Not captured. The form is the same centered column (F1). |
| Me | ✅ Fits; the game card's token row runs under the home indicator when scrolled, which is fine. | Not captured. `MeView` and `CardGrid` go two-column in open landscape by code. |
| Before you play | ✅ Fits. | Not captured (`readableColumn`, centered). |

Nothing clipped at the fold in the poses captured. Partially open and open portrait weren't captured (F6).

### Recommendation: **(b) Skip Duo screenshots for 0.9; do the inner layout in 1.0**

- The **outer display already looks intentional**, and the **inner map** is strong.
- **Game detail, the form and onboarding** on the inner display are a phone column centered on a tablet-sized canvas. The app can't show map and detail together, and Apple's bar is "a natural extension of its iPad layout".
- Duo shots are optional until April 2027, so there's no reason to put a half-adapted inner set on the product page now. The badge is worth more after F1.
- Every Duo frame also needs the same fixture fixes as the iPhone set (B8). Shooting twice now would be wasted.
- If the team wants the badge with 0.9 anyway: an **outer-only set** (shots 1, 2, 4, 5, 6) plus **one inner map shot** is honest. That's how the app really looks, nothing stretched. It's the fallback, not the recommendation.

**For 1.0** (before April 2027): F1 (two-pane map + detail on the open display, wide detail, two-column form; 10–14 h + 3 h frames), F2 (1 h), F6 (1 h), then capture (F3).

### Outer and inner counterparts (for 1.0)

| iPhone shot | Outer (1398 × 2034, wider and shorter than an iPhone) | Inner (2853 × 2007 landscape, or 2007 × 2853 portrait) | Caption |
| --- | --- | --- | --- |
| 1 Map + popup | Same state. Less height, so fewer pins above the popup; the vertical control column on the right is new. | Map fills the canvas with the popup. After F1: map plus the selected game's detail side by side, the best "show more" frame. Today the app can't show both, so don't fake it. | Full caption fits on both. Inner can carry "Unfold to see more of campus" if used with the blurb. |
| 2 Detail, Open | Court plus sheet; crop at **Room for 4 more**, Who's going, host note. | Only after F1 (wide detail). Today's centered column would read as stretched. | Fits. |
| 3 You're in | Same composition as 2. | After F1 as part of the split (map + You're in). | Fits. |
| 7 Group chat | Pinned card + 3–4 messages + composer; check the keyboard isn't up. | After F1: the game beside its chat would be the strongest inner frame. Today it's one column; capture to judge. | Fits (35). |
| 4 Add game | Sheet fills the cover; trim to Sport → Players. | After F1 (two-column form); skip until then. | Use the short variant "Start something in a minute" (27) on the narrower outer frame if the layout needs it. |
| 5 Me | Profile card + Going tab. | Two-column Me (profile left, Going right) is plausible by code; capture to confirm. | Fits. |
| 6 Before you play | Fits as is. | **No Duo inner version.** It's a single text column; nothing gained. | Fits. |

### Blurb (use only if the recommendation becomes (a))

- **Promotional text (140/170):** *Unfold iPhone Duo and the map opens up: more of campus, more groups that need one more, all at a glance. College is better when you say yes.*
- **Description sentence (83):** *On iPhone Duo, unfold to see more of what's happening around campus on one big map.*

Both promise only what the inner map does today.

---

## 8. Open questions

**Ethan**
- Is 0.9 (9) already uploaded to TestFlight? If yes, bump to 10 (B6).
- Which TestFlight build goes through the two-phone push and chat QA (B1, B2)? It should be the one you'll submit.
- Does Media Manager mark 6.9-inch as mandatory? If yes, add an iPhone 18 Pro Max pass.

**Emilio**
- On prod: are all migrations applied (including `chat_mentions`)? Is `min_supported_version` ≤ 0.9? Can `chat_enabled` and `push_enabled` be on, with the APNs key and `send-push` deployed, before upload (B1, B2, B7)? Who holds the Admin or App Manager role to create the APNs key?
- Do review1 and review2 exist, on the demo campus, with or without a finished profile? Does the demo cron show 6 upcoming games?
- Does `before_user_created` fire for dashboard-created users? If yes, re-created review accounts land on the waitlist (S2).
- OK to delete the `signup_requests` row on account deletion (S1)?

**Arianna**
- Is the final icon ready (S5)?
- Framing for the six iPhone shots once the `-screenshots` world exists (B8). Should captions sit above the device or replace the status bar?
- Frames for the 1.0 inner-display split (F1).

**Ricardo**
- Policy rewrite and license line (B5, §5 Content rights). Who reviews the data claims? (Emilio, per SPEC §10.2.)
- Is the seller shown as Boys & Girls Clubs of Chicago intended (S7)? Is "masUNO" available as a name?
- Age-rating result vs the policy's "17 or older".
- Spanish for every string B5 and S4 add (the location purpose string, the map primer, the form placeholder).

---

## Appendix A: brief vs repo

| The brief said | The repo says |
| --- | --- |
| No chat in 0.9 | Group chat is built; entry points always show; messaging follows `app_config.chat_enabled`. **Decided Nov 19: ships in 0.9** (B1) |
| No push notifications | Push is built (notification service extension, primer, six settings, `aps-environment production`); sending follows `push_enabled`. **Decided Nov 19: ships in 0.9** (B2) |
| No Saved/bookmarks | Saved and spot alerts are built and **synced to the account** (`set_bookmark`, `set_spot_alert`) |
| No Spanish UI | Full Spanish; Settings › Language (Device language / English / Español); `CFBundleLocalizations en, es` |
| No profile photos | ✅ True: initials tokens only |
| Sign-in: @tec.mx email + one-time code | Email + **password**; invite-only with waitlist (N36–N38); no email confirmation |
| Four sports | Five: padel too |
| Light-mode-only setting | Dark mode supported (System / Light / Dark); screenshots use light |
| "Join game", "+ Add game", flag icon | **Count me in**, **Add game** (plus icon), **•••** menu |
| Hosts can't remove players; a blocked player is removed automatically | ✅ True: `20261121000000_block_privacy` removes active RSVPs in either direction |
| Not in the brief | Guest browsing (map and details without names), invite codes (3 each), beta tester badge, auto-repost, Add to calendar, Invite a friend, Google Maps option |

## Appendix B: readiness checklist

✅ ready · ⚠️ needs work · ❓ can't tell from the repo

**Build and project**
- ✅ Bundle ID `com.masuno.app`, team `PU87MU4QAR`, marketing version `0.9` (built Info.plist)
- ⚠️ Build number `9`, probably already used (B6)
- ✅ 1.0 can follow: `AppConfig.supports` is a numeric compare against server `min_supported_version` (`0.5` in the migrations); no client-side version gate
- ✅ Deployment target iOS 18.0; Xcode 27.2 / iOS 27.2 SDK
- ✅ Release points at prod: `Config.xcconfig` (git-ignored) has a real Release URL and key; the archive pre-build script rejects placeholders; Release without keys falls back to `UnavailableBackend`, never mocks
- ✅ No keys in git history (only the prod project ref, in `supabase/README.md`, which isn't a secret). Note: **the iOS and website repos are public**, so the allowlisted review addresses in `20261109000200_campuses_and_demo.sql` are public, as that migration's comment acknowledges
- ✅ No DEBUG menus, gallery, mocks or test launch arguments in Release (`#if DEBUG` around `MockBackend`, `MockFixtures`, `ComponentGallery`, `openDebugScreen`, the gallery context menu, `mockLocation`); no TODO/FIXME, "coming soon" or placeholder copy in Swift
- ⚠️ Chat and push are in the build; prod flags must be on before upload (B1, B2)
- ✅ Release device build: **succeeded**, 2 harmless warnings (AppIntents metadata skipped)

**Info.plist and capabilities**
- ⚠️ Location purpose string accuracy (B5); it's the only permission string. Notifications need no string.
- ✅ `ITSAppUsesNonExemptEncryption = NO`
- ✅ iPhone only (`UIDeviceFamily 1`), portrait; launch screen color `Background`; `UIRequiresFullScreen` not set (not needed)
- ✅ Entitlements match what ships: `aps-environment production`, communication and time-sensitive notifications, app group
- ✅ `NSUserActivityTypes: INSendMessageIntent` for chat communication notifications
- ✅ Compiled 1024 icon opaque (light, dark, tinted); ⚠️ temporary design (S5)

**Privacy**
- ✅ App and extension manifests exist; required-reason APIs covered
- ⚠️ Collected-data types incomplete (B4); location is uploaded (Precise Location: yes)
- ✅ No analytics or tracking SDKs, no IDFA; ⚠️ first-party notification-open tracking → Product Interaction / Analytics

**Guideline 1.2 and accounts**
- ✅ Guidelines agreed before use (**Before you play** → **I agree**, `accept_guidelines`)
- ✅ Text filter on titles, notes, meet-up spots, names (and chat): `private.clean_text` with English and Spanish lists, plus a client `TextFilter`
- ✅ Report person (Who's going) and report game (More menu, and Past games on Me); block is instant client-side, then server-side; Settings › Blocked people › **Unblock**
- ✅ Contact us in Settings (`mailto:` the support Gmail); also "Forgot your password? Contact us" on Sign in
- ✅ In-app deletion really deletes (Edge Function + `delete_my_account_data` + `deleteUser`); ⚠️ the waitlist email lingers (S1)
- ✅ Privacy & Terms link on Welcome and in Settings; ⚠️ page content (B5)
- ❓ Review accounts work on prod and land on the demo campus (B7); ⚠️ re-creation after deletion (S2)
- ✅ No third-party or social login reachable (the Azure SSO code exists but nothing navigates to it), so Sign in with Apple isn't required (4.8)
- ⚠️ Content-rights line missing from the Terms (B5)

**Stability**
- ✅ Builds clean in Release
- ⚠️ Airplane mode, location denied and far from campus are handled in code; not run live in this audit (S6)
- ✅ Nothing in TODO/FIXME a reviewer could hit; the earlier post-create/join primer crash is fixed (build 0.9 (2)) and has a UI regression (`-screen create-primer`)

## Appendix C: Privacy & Terms changes (B5)

Apply in the website repo's `privacy.html`; the page is from Nov 11 and predates N36 (password sign-in) and the 0.9 decisions. **English only below. Every changed string also needs its Spanish entry in `i18n.js` (Ricardo).** Emilio checks the data claims (SPEC §10.2). Not applied here: the local website clone has uncommitted work on `ethan/waitlist-sync`.

1. **Last updated:** set the publish date.
2. **Replace "When you sign in"** (heading, paragraph and list) with:
   > **When you create an account.** You create an account with your school email address (at Tec, your @tec.mx address) and a password. We store your email and an account ID. Your password is stored only as a secure hash by our sign-in provider; we can't see it.
   > masUNO is invite-only for now. If you use a member's invite code, we record whose code it was. If you join the waitlist, we keep your place in line until you're let in.
3. **"Your games":** change the chat item to *"Messages you send in a game's group chat, the people you @mention, and when you last opened each chat."*
4. **Add under "What we collect":**
   > **Saved games and alerts.** The games you save and the spot alerts you turn on, stored with your account.
   > **Notifications.** If you allow notifications: your device's notification token, an ID for this install of the app, the app version and language, your notification settings, and which notifications you open.
   > **Invites.** Your invite codes and who used them.
5. **"What stays on your phone":** replace the location item with *"**Your location.** The app uses it on your phone to center the map and show how far games are. It's sent to us only if you host a game and choose "Use my current location" as the place: that spot is then saved with the game like any other place."* **Delete** the "Saved games" item (saved games now sync to your account).
6. **"What we don't collect":** replace the analytics item with *"**Ads and tracking.** There are no ads, no third-party analytics tools and no tracking. We do count which notifications get opened, to learn which ones are useful."*
7. **"Why we use it":** replace the last item with *"**Your language setting** picks the language of the app and its notifications. **The sports you play** decide which new games we tell you about."* Add *"**Your notification token and settings** let us send the notifications you've turned on, and nothing else."*
8. **"Where your data is stored…":** delete the Microsoft item. Apple: *"distributes the app, provides the map and place search, and delivers notifications."* Google: *"**Google (Gmail and Google Sheets)** handles the email you send us and our waitlist: if you joined the waitlist, your email and place in line are kept in a Google Sheet only our team can open."*
9. **"Keeping and deleting your data":** add to the list *"Deletes your saved games, notification settings and notification tokens."* and *"Deletes your place on the waitlist."* (true once `20261124000000_delete_signup_request` is on prod). Say it also leaves the Google Sheet only after the Apps Script deletes rows that come in as `removed`.
10. **"Community rules and safety":** add the content license after the rules:
    > You keep ownership of what you post on masUNO: game names, notes, meet-up spots, messages and your profile name. By posting it, you give masUNO permission to store it and show it to other students in the app, for as long as it's on masUNO. That permission ends when you delete the content or your account, except for copies kept with reports for moderation.
11. **Delete the whole "Coming in a later version" section.**
12. **"Your choices":** add *"**Notifications:** turn each kind on or off in Settings › Notifications, or all of them in your iPhone's Settings."*
