# masUNO QA script

Run this before each TestFlight build, on two physical phones with the exact build being sent (SPEC §9).
Use two accounts on `masuno-prod`: **Phone A** hosts, **Phone B** joins. File anything that fails as a Trello
bug with a screenshot. Sections 1–8 need the live backend.

Before you start: delete the app from both phones, turn location on, and note the build number from Settings.

## 1. Sign-in and onboarding

- [ ] Fresh install → welcome → Continue. Privacy & Terms opens the real page.
- [ ] A non-Tec email shows "masUNO is just for Tec students right now."
- [ ] A Tec email gets a code within a minute. Check Junk and note if it landed there.
- [ ] A wrong code shows an error and clears the boxes. Resend is disabled for 30 s.
- [ ] Name, class year and at least one sport are required. A rude name shows "Please keep it friendly."
- [ ] Agreeing to the guidelines lands on the map, in under 2 minutes from install.
- [ ] Quit the app mid-onboarding and reopen: it continues at the same step.
- [ ] Review account: its email shows a password field instead of sending a code, and signs in.

## 2. Map

- [ ] First open asks for location. **Allow** and, near Tec, the map centers on you.
- [ ] Pins show the sport emoji. A game starting within the hour says "Soon".
- [ ] Search by title, sport, place and host first name. Filter by each of the 5 sports.
- [ ] Tapping a pin opens the popup, panning off screen closes it, and the bookmark fills green.
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
- [ ] **Last-spot race:** with one spot left and a third account or Phone A's friend ready, both tap Join at
  the same moment. One gets in; the other sees "Someone just took the last spot." and the game shows Full.
- [ ] Event detail shows each state correctly: Open, You're in, Full, Hosting, Ended, Cancelled.

## 5. Auto-repost

- [ ] Fill a game with auto-repost on, then have a player leave.
- [ ] Phone A's Hosting card says "Reposted just now".
- [ ] On another phone the pin says "Spot open" and draws on top of nearby pins.
- [ ] With auto-repost off, nothing changes when a player leaves.

## 6. Group chat (read-only unless E26 shipped)

- [ ] Opens from You're in, Hosting and Me. Shows the pinned card and rows for created, joined and left.
- [ ] There's no composer and no sample messages.
- [ ] The host can edit the meet-up spot; the pinned card and timeline update.

## 7. Safety

- [ ] Report a person and a game. "Thanks — we'll review this within 24 hours." The team-chat alert arrives within a minute.
- [ ] Phone B blocks Phone A: A's games and name disappear **without refreshing**.
- [ ] Phone A can no longer see B's games or name after a refresh, and neither can join the other's game.
- [ ] Settings › Blocked people lists the name. Unblock brings the games back.
- [ ] A moderator bans an account: its next action lands on "Your account is suspended".

## 8. Cancel and delete

- [ ] Phone A cancels a game. It leaves the map, and Phone B sees "cancelled this game".
- [ ] Phone A deletes their account from Settings: signed out, hosted games cancelled, joined spots freed.
- [ ] Signing in again with that email starts onboarding from the beginning.

## 9. Bad conditions

- [ ] **Airplane mode:** on the map, in Me and on an unopened game. No blank or endlessly spinning screen; retry works once back online.
- [ ] **Failed actions in airplane mode:** Join and Leave undo themselves with a short message.
- [ ] **Location denied:** the map stays on campus with the "Turn on location" banner, which opens iOS Settings.
- [ ] **Far from Monterrey:** the map lands on campus, or the demo campus for a review account.
- [ ] Largest text size and the smallest phone available: nothing is cut off on the core screens.

## 10. Release checks

- [ ] Settings: Privacy & Terms opens, Contact us opens mail, and the version is right.
- [ ] Add to calendar opens prefilled with no permission prompt. Open in Maps works.
- [ ] Invite a friend shares the app's own App Store link, or is hidden if the Apple ID isn't set yet.
- [ ] Saved games survive quitting and reopening the app.
- [ ] The app icon shows on the home screen.
- [ ] No "coming soon" text, sample data or debug menus anywhere. Long-pressing the avatar on the map does nothing.
- [ ] The rest of the App Review checklist in SPEC §10.4 is green.
