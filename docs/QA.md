# masUNO QA script

Run this before each TestFlight build, on physical phones (two, plus a third for the last-spot race) with the exact build being sent (SPEC §9).
Use test school accounts (O4) on `masuno-prod`, or allowlisted accounts until Tec issues them, one per phone: **Phone A** hosts, **Phone B** joins. File anything that fails as a Trello
bug with a screenshot. Sections 1–8 need the live backend.

Before you start: delete the app from both phones, turn location on, and note the build number from Settings.

## 1. Sign-in and onboarding

- [ ] Fresh install → Welcome → **Get started** → Create account → We're checking your account. Privacy & Terms opens the real page. There's no Find your school.
- [ ] The location primer is the first map open, not a Welcome step; it doesn't trigger the iOS prompt until you allow it on the map.
- [ ] Create account with a school address posts "New sign-up waiting for approval" to the team Discord within a minute, with the approve and reject lines.
- [ ] Create account with any other address (Gmail, another school, `@mail.tec.mx`) shows "masUNO is just for Tec students right now." (with the launch campus's name). A password under 8 characters and an address that already has an account each show their own message.
- [ ] While waiting, **Check again** says "Not yet." Quit and reopen: still on We're checking your account. **Sign out** returns to Welcome, and signing back in returns to the waiting step.
- [ ] Run the approve line in the SQL editor, then **Check again** (or leave the app and come back): You're in → Set up profile.
- [ ] Run the reject line for a second waiting account: signing in with it then fails, and the same address can sign up again.
- [ ] There's no Google, Microsoft or Apple button, and no way into Find your school (school SSO is kept in the code but unused, N36).
- [ ] Name, class year and at least one sport are required. A rude name shows "Please keep it friendly."
- [ ] Agreeing to the guidelines lands on the map.
- [ ] Quit the app after approval but before agreeing to the guidelines, then reopen: it continues at the same step.
- [ ] Sign out of an account that finished onboarding: the app returns to Welcome, and **I already have an account** goes straight to the map.
- [ ] Review account: **I already have an account** signs in with the review password and lands on the demo campus, with no wait for approval.
- [ ] A Tec test account used for App Review lands on the demo campus too.
- [ ] A waiting account can't do anything through the API either: `complete_profile` answers `pending_approval`.
- [ ] Sign out, then sign in with a different school account: the school's page asks for the password again, and the new account's profile loads.

## 2. Map

- [ ] First open asks for location. **Allow** and, near Tec, the map centers on you.
- [ ] Pins show the sport emoji. A game starting within the hour says "Soon".
- [ ] Search by title, sport, place and host first name. Filter by each of the 5 sports.
- [ ] Tapping a pin opens the popup, panning off screen closes it, and the bookmark fills green.
- [ ] **Count me in** opens details (you land on the court).
- [ ] Joined (not host): popup **Leave** instead of Details. Host keeps Details + Edit game.
- [ ] Two overlapping pins open a group sheet.
- [ ] Phone B leave: Phone A court and popup update without a manual refresh. A bookmarked full game that opens shows "A spot just opened in …".
- [ ] Tapping "N games nearby" refreshes the map.

## 3. Hosting (Phone A)

- [ ] Add game with no name, no location and a past time: each shows its own error.
- [ ] Create a game. The map jumps to it and it's in Me › Hosting.
- [ ] A fourth upcoming game is refused: "You can host up to 3 upcoming games."
- [ ] Edit the game. Players can't go below the number going.
- [ ] A game name with a filtered word is refused, in English and Spanish.

## 4. Joining and the last spot (both phones)

- [ ] Phone B joins: "You're in" shows immediately, and Phone A sees them in Who's going after a refresh.
- [ ] Phone B leaves. The count goes back on both phones.
- [ ] **Last-spot race:** the host can't join their own game, so this needs a third phone. With one spot left,
  two non-host phones tap Join at the same moment. One gets in; the other sees "Someone just took the last spot." and the game shows Full.
- [ ] Event detail shows each state correctly: Open, You're in, Full, Hosting, Ended, Cancelled.

## 5. Auto-repost

- [ ] Fill a game with auto-repost on, then have a player leave.
- [ ] Phone A's Hosting card says "Reposted just now".
- [ ] On another phone the pin says "Spot open" and draws on top of nearby pins.
- [ ] With auto-repost off, nothing changes when a player leaves.

## 6. Group chat

With `chat_enabled` off on the project (0.5, and 0.6 until the check below passes there):

- [ ] Opens from You're in, Hosting and Me. Shows the pinned card and rows for created, joined and left.
- [ ] There's no composer and no sample messages. Me cards say "Group chat" with no count.
- [ ] The host can edit the meet-up spot; the pinned card and timeline update.

With `chat_enabled` on (0.6, E26). Phone A hosts, Phone B joined:

- [ ] The first time each phone opens a chat, "Before you chat" comes up. **Not now** goes back; **I agree** doesn't ask again, in this chat or any other.
- [ ] Phone A sends a message. It shows on Phone B within a couple of seconds, without refreshing, as "Name · Host · time".
- [ ] Phone B replies. Phone A, sitting on Me, shows "Group chat · 1 new" after a refresh; opening the chat clears it.
- [ ] Phone B joins or leaves while Phone A has the chat open: the "joined" or "left" row appears on its own.
- [ ] Airplane mode on Phone B: a sent message says "Not sent · Tap to retry". Back online, tapping it sends it once.
- [ ] A message with a filtered word or a link never leaves the composer, and says why.
- [ ] A third account that isn't in the game can't open the chat.
- [ ] Touch and hold Phone A's message on Phone B: **Report message** sends, and the team-chat alert says "chat message". **Block** hides Phone A's messages at once.
- [ ] Phone A cancels the game: both chats lose the composer and say the chat is closed.
- [ ] Set `chat_enabled` back to `false`: after a relaunch the composer and messages are gone, with no error.

## 7. Safety

- [ ] Report a person and a game. "Thanks — we'll review this within 24 hours." The team-chat alert arrives within a minute.
- [ ] Phone B blocks Phone A: A's games and name disappear **without refreshing**.
- [ ] Phone A can no longer see B's games or name after a refresh, and neither can join the other's game.
- [ ] Settings › Blocked people lists the name. Unblock brings the games back.
- [ ] A moderator bans an account: its next action lands on "Your account is suspended".

## 8. Cancel and delete

- [ ] Phone A cancels a game. It leaves the map, and Phone B sees "cancelled this game".
- [ ] Phone A deletes their account from Settings: signed out, hosted games cancelled, joined spots freed.
- [ ] Signing in again with that school account starts onboarding from the beginning, including You're verified and Set up profile.

## 9. Bad conditions

- [ ] **Airplane mode:** on the map, in Me and on an unopened game. No blank or endlessly spinning screen; retry works once back online.
- [ ] **Create account in airplane mode:** shows "You're offline.", and works once back online.
- [ ] **Failed actions in airplane mode:** Join and Leave undo themselves with a short message.
- [ ] **Location denied:** the map stays on campus with the "Turn on location" banner, which opens iOS Settings.
- [ ] **Far from campus:** the map lands on your campus, or the demo campus for a review account.
- [ ] Largest text size and the smallest phone available: nothing is cut off on the core screens.

## 10. Release checks

- [ ] Settings: Privacy & Terms opens, Contact us opens mail, and the version is right.
- [ ] Add to calendar opens prefilled with no permission prompt. Open in Maps works.
- [ ] Invite a friend shares the app's own App Store link, or is hidden if the Apple ID isn't set yet.
- [ ] Saved games survive quitting and reopening the app.
- [ ] The app icon shows on the home screen.
- [ ] No "coming soon" text, sample data or debug menus anywhere. Long-pressing the avatar on the map does nothing.
- [ ] The rest of the App Review checklist in SPEC §10.4 is green.
