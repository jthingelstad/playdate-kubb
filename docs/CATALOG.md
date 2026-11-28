# Playdate Catalog

What Panic asks for to sell Kubb: Throwing Wood in the Playdate Catalog, and where the
game stands against it. Read 2026-11-17 from help.play.date ("Submit to Catalog",
"Publishing in Catalog" and the UX checklist); check those pages again before submitting.

## How it goes

1. **Apply** (the form on help.play.date/developer/submit-to-catalog): country, name,
   email, the title's name, genre and tags, a description, whether generative AI made any
   content (and how), a price, three screenshots and a zipped `.pdx`. Review takes 1 to 3
   weeks. Sent 2026-11-27: "The application" below.
2. **After acceptance**: the Catalog Sales Agreement, an NDA, Stripe and a tax interview;
   the asset checklist; the build through Panic's build form. Releases go out every
   other Tuesday.
3. **Terms**: price $1 to $100, the developer keeps 75%, non-exclusive (the game can be
   sold elsewhere too).

## The application (sent 2026-11-27)

Jamie sent the application on 2026-11-27 through Panic's form
(forms.panic.com/catalog-submit, linked from "Submit to Catalog"). Panic answers by email,
usually in 1 to 3 weeks; a title they pass on can be changed and sent again.

- **Build**: 1.1.1 (build 19) on Kubb Engine 1.4.1, tag `v1.1.1`, the zip from
  `make release` (`ThrowingWood-1.1.1.pdx.zip`).
- **Screenshots** (three, 400x240, from `make selftest` on that build):
  `match-opening-02` (aiming a baton, WIND BACK on the clock), `burst-02` (TOK! in slow
  motion) and `match-opening-06` (kubbs thrown in beside the king, "16 CM AWAY").
- **Genre**: Sports. Tabletop on that form means board and card games, not lawn games.
- **Price**: $3 to $5, a range for review only (the Catalog's floor is $1).
- **Description** (for Panic's review, not shown in Catalog), as it stood on the form
  before sending:

  > Kubb: Throwing Wood is backyard Kubb, the Swedish lawn game, made for the Playdate.
  > You throw with the crank by winding it back and flinging forward to throw, being
  > careful to release at the right moment. Every throw is a physics simulation at the
  > real size of a tournament pitch. Batons tumble, kubbs topple into each other, and
  > what happens comes from how you threw. You can play the full rules against the
  > Playdate, from a forgiving Kid game up to Pro, or pass and play with friends in
  > singles or teams. Every finished game is kept as a real Kubb score sheet. I am an
  > expert Kubb player and built this powerful Kubb Engine to power Throwing Wood.

- **Generative AI**: answered Yes, with:

  > Code was written with Claude (Anthropic) under my close direction. Claude also
  > drafted the on-screen text and the 1-bit art (drawn as code/SVG, no
  > image-generation models), which I directed and edited. Sounds are my own
  > recordings of real kubbs; the font is Londrina Solid (OFL).

### The content rule

Panic: "Your title shouldn't use generative AI for art, audio, music, text, or dialog."
Code written with AI assistance is allowed. The on-screen words (menus, HOW TO PLAY, HOW
TO THROW, cards, the burst words) and the Woodcut art (`docs/design/`, drawn by
`tools/art/build.py`) were drafted with Claude, so the application says so in the answer
above rather than leaving it for Panic to find. If Panic passes on the title for this,
either make the words and art the developer's own and apply again, or ask Panic how the
rule applies (catalog-submissions@play.date).

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
| Frame log behind `debug` | done (1.1.1, build 19): `frames.jsonl` is written only while the `debug` file is in the Data folder, as the crank traces have been since 2026-11-20, so a buyer's Data folder holds only their players, saves and games and the System Menu has no developer item |

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
