# Playdate Catalog

What Panic asks for to sell Kubb: Throwing Wood in the Playdate Catalog, and where the
game stands against it. Read 2026-11-17 from help.play.date ("Submit to Catalog",
"Publishing in Catalog" and the UX checklist); check those pages again before submitting.

## How it goes

1. **Apply** (the form on help.play.date/developer/submit-to-catalog): name, email,
   location, a description, screenshots and a zipped `.pdx`. Review takes 1 to 3 weeks.
2. **After acceptance**: the Catalog Sales Agreement, an NDA, Stripe and a tax interview;
   the asset checklist; the build through Panic's build form. Releases go out every
   other Tuesday.
3. **Terms**: price $1 to $100, the developer keeps 75%, non-exclusive (the game can be
   sold elsewhere too).

## Content rule to settle first

Panic: "Your title shouldn't use generative AI for art, audio, music, text, or dialog."
Code written with AI assistance is allowed. The game's code fits. Its on-screen words
(menus, HOW TO PLAY, HOW TO THROW, cards) and its art direction were drafted with AI
assistance, so before applying either the words and art are the developer's own, or Panic
is asked how the rule applies (catalog-submissions@play.date).

## The game

| Requirement | State |
|---|---|
| `pdxinfo`: name, author, description, bundleID, version, buildNumber, imagePath | done |
| Launcher: card 350x155, highlighted card animation, icon 32x32, launch image 400x240 | done (`source/launcher/`) |
| Reduce Flashing respected | done: the king's full-screen invert is skipped when it is on (`render/burst.lua`) |
| Saves on quit and sleep | done: `playdate.gameWillTerminate` and `deviceWillSleep` save a match in progress (`main.lua`, `scenes/match.saveNow`); it was already saved before every throw |
| A match resumes after a relaunch | done (B RESUME on the title) |
| Data folder stays small | done: traces and frame logs are each kept to about 1 MB (`logcap`) |
| No network, no accelerometer | done |
| Before the Catalog build | turn the frame log off by default and keep it behind the `debug` file (crank traces moved there on 2026-11-20, with the System Menu's Record item gone), so a buyer's System Menu has no developer item; raise the version to 1.0.0 |

## Listing assets

All 1-bit, from the Simulator with Device Appearance off.

- **Screenshots**: at least one still and one GIF, 400x240; about four in all. The GIF
  must be under 10 seconds (`tools/film.sh`'s reel is about 26 s: cut a shorter one).
- **Catalog art** (1-bit, no alpha): Billboard 380x180, Wide 380x90, Small 185x90,
  Header 400x208.
- **Website art**: Feature 1600x960, Wide 1600x480, Small 800x480, Header 1200x400.
- **A primary category** (sports).

## Accessibility disclosure

A draft of the facts for the listing (the words to be the developer's own):

- **Inputs**: the crank throws (wind back and flick); the d-pad moves the target circle;
  A held walks the thrower, B held shows the plan view and with up/down or left/right
  sets the arc, tilt or spin. No accelerometer, no microphone.
- **Held buttons**: A and B are held to walk and to plan; never needed during the throw.
- **Timing and precision**: no time limit and no quick reactions; turns wait for the
  player. Where the crank stops sets the arc, so a throw takes a steady hand on the
  crank; what counts as on is wide for a short throw and narrow for a long one, and a
  match against the KID computer plays the Kid rules on a much wider meter (bars about
  five times as wide at 6 m), with throws from 2 m nearer and nothing called a foul.
- **Text entry**: optional. A name (a player, a guest, a team) is either chosen from word
  lists with the crank or the d-pad, or typed with the Playdate's system keyboard (up to
  10 letters); nothing has to be typed to play. Names stay on the device.
- **Audio**: knocks and the king's chord are feedback only; the game plays fully muted.
- **Flashing**: a king knocked over inverts the whole screen for 2/30 s; off with
  Settings > Accessibility > Reduce Flashing.
