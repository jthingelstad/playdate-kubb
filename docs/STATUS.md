# Status

Where the work stands, for whoever picks it up next. Updated 2026-11-14, early morning
(US Central), after the overnight round.

## On `main`

Everything built is merged except the diagnostic timing hooks on branch `soak-profile` (see
"Slow frames in the soaks").

- Pass-and-play match, VS PLAYDATE (a match against the computer) and practice drills, with
  the rules engine, notation and saved game files.
- Team names before each match; raising kubbs and placing punishment kubbs by hand (the
  crank tips a kubb up in a 3D close-up); the match in progress saved and resumed from the
  title; the games list with score sheets.
- Hit bursts (TOK!, KLAK KLAK!, KING!) with knocks, at the baton's impact; SLOW MOTION flag;
  the camera's half circle round a hit in slow motion.
- Smooth playback of throws (`AGENTS.md`, "Playback"); the Woodcut look
  (`docs/design/README.md`).
- QA tooling: the device soak (`source/soak.lua`, with a breakdown of each slow frame) and
  a self-test run that survives the Simulator's crash on quitting.

## Speed on the device

The autobench match case (the same three throws: a hit, a miss and a drill), shown speed
(1.0 = real time):

| Build | Shown speed | The hit, release to rest |
| --- | --- | --- |
| Before the Woodcut play screen | 0.41 | |
| Woodcut play screen | 0.28 | |
| Speed fix (2026-11-13) | 0.44 | |
| Bursts at the impact | 0.43 | 4.2 s |
| Half circle at 40 ms a frame | 0.34 | 6.7 s |
| Half circle at 60 ms a frame (on `main`) | 0.40 | 4.7 s |

Final `main` (`telemetry/2026-11-14/bench/run2-final-main.txt`): 0.39 to 0.40, the hit 4.6 to
4.8 s, nothing starved; bursts 4 to 12 ms of shown time after the impact.

## Overnight (2026-11-13 to 14)

- **Bursts at the impact** (Jamie: they came a step after the hit). The physics cannot
  reach a topple before the picture reaches the contact (bursts ran 250 to 320 ms of shown
  time late on the device), so a struck kubb is judged falling at its impact from how hard
  it was hit, and a burst for one that then stands is taken back (a double whose second
  kubb stands becomes a clean burst). Now 2 to 6 ms after the impact on the device. The
  king is judged only once it has toppled, so its burst can come a fraction of a second
  after the hit; Jamie kept it so (2026-11-14).
- **The camera's half circle** (Jamie's idea): in slow motion after a hit the camera goes
  half way round the struck piece and opens out to show the pitch round it. While it turns
  every frame is a full draw, so those frames take 60 ms instead of 40; that keeps its cost
  to about half a second a hit. Jamie kept it on as built (2026-11-14).
- **Resume, games list, drills** merged after Codex's findings were fixed.
- **QA.**
  - 500 rules games and 45 physics matches (5 by `make games`, 40 more on another seed:
    6800 throws), every game file through the notation gate with no warnings.
  - The full Simulator self-test suite three times (all 36 scenarios each time) and on
    final `main` (41).
  - `make bench` on the desktop, unchanged.
  - An independent review of every change of the day; its findings were fixed:
    - a merely pushed king got the KING flash;
    - a graze counted as the impact;
    - the Playdate's kubb tosses showed a drill marker they did not go to;
    - BLAST's marker could be moved close for easy points;
    - helicopters scored in drills;
    - leaving during the rest hold gave the throw back on resume;
    - a damaged save could stop the launch;
    - the half circle went round the wrong piece or kept turning after a take-back.
  - The device soak on final `main` (`telemetry/2026-11-14/soak/`): three whole matches
    (16, 25 and 7 turns, 402 throws, 40 minutes) with no error, all 56 save checks good,
    memory steady at about 1.03 MB after collection. Two more soaks: the same.
  - Every Codex finding on PRs #46 to #52 was fixed and answered on its thread.
- **Simulator flake explained.** The Simulator (SDK 3.1.2) segfaults as it quits after
  some scenarios, after the result is written; now and then the crash hangs it until the
  timeout. The Makefile now counts such a run by its marker.

## Slow frames in the soaks: most likely the throw's landing frame

Jamie's own play (101 throws in `frames.jsonl`, flight frames only) never had a frame over
121 ms, but the soaks list 0.2 to 0.4% of frames at 200 to 400 ms, about one per throw.
Split by part (`telemetry/2026-11-14/soak/run4-profiled-stopped.txt`), the throw's flight
takes 70 to 105 ms of such a frame (the physics), the bursts and camera almost nothing, and
the match scene's own update 130 to 230 ms. That is the landing frame: the physics' last
stretch of the calm tail (up to its 100 ms `tailPeriod`, the picture already still), then
the engine rules on the throw and the match is saved (the datastore write alone is about 70
ms, more with a full pitch). The soak labelled these frames by the mode they began in
(flight), which hid it; it now writes `play/flight -> rest`, so the next soak will show it.
If so, the cost is a pause of a few tenths of a second before the result flag on a still
picture, not a hitch in the flight. The per-part hooks are on branch `soak-profile` (not
merged).

## The ground's texture and surfaces (2026-11-14)

Grass, sand and snow each have a texture: patches vary in friction, bounce and how far a
landing digs in, steep landings are turned a little off line, pieces stop instead of
creeping, nothing slides along on an end, and snow ploughs (AGENTS.md "Physics", "The
ground's texture"). Slide after touching down, over 400 scripted throws: grass 1.4 m, sand
0.46, snow 1.85. Practice picks the surface in the System Menu; a match plays on its own
surface, chosen on the match options screen before each match, with the opening (2-4-6 or
six from the start) and raising (by hand or automatic). Next: the Playdate opponent aiming
for the surface.

## Changed from the boards on Jamie's word (2026-11-13, playing on the device)

- PASS + PLAY: a card passes the Playdate to the defending team before it raises kubbs
  and places punishment kubbs (2026-11-14).
- The pitch is its bare rectangle: the stakes' shadow lines read as the lines running on
  past the corners, so they are gone. The stakes are real ones, 3/4 inch thick and 6
  inches high (0.019 x 0.15 m), drawn as solid posts (never thinner than 3 px) and the
  same size in the physics, so a drilled kubb can roll into the middle stake (2026-11-14).
- The low, hard throw: loft goes down to 5 degrees, and a low baton is thrown harder, so
  full power carries about 8.9 m at any loft (2026-11-14). In the physics a 5 degree throw
  takes down a field kubb 6.5 m out in up to 14 of 24 throws, against 1 in 24 before.
- The advantage line: a turn's first baton starts on it (the camera with you), and an
  ADVANTAGE LINE flag with its distance shows while you or the Playdate aim from it
  (2026-11-14).
- The score sheet during a match: System Menu "Match: sheet" shows the game so far,
  latest turns first on screen; B goes back (2026-11-14). Sharing a finished one is next.
- Stay put: a team's batons after its first of a turn start where the last was thrown
  from, with its swivel and loft, as a real player stands in one spot until they choose
  to move (2026-11-14). A new turn and every kubb start from the middle.
- VS PLAYDATE: the Playdate tosses its kubbs into the basket, the corner nearest the
  centre line by a sideline, grouping a turn's kubbs in one corner (2026-11-14).

- A piece never changes its look: no grey fallen kubbs, no black resting batons. The light
  on the faces stays.
- No speed lines (they did not follow the baton's turn).
- A SLOW MOTION flag while the slow motion around a hit plays.
- Hit words stay TOK! / KLAK! / KING!.

## Device testing

`nolock` is in the game's Data folder on Jamie's Playdate so it stays awake for unattended
testing over USB (AGENTS.md "Measuring on the device"). **Delete it when the testing is
done.**

The Playdate stopped answering over USB at about 5:00 on 2026-11-14 during a soak of the
`soak-profile` build (the port was there, but it would neither mount its disk nor launch
the game; nothing in its crash log). Jamie reset it by hand; `main` is installed again.

## To try on the device

- The bursts and knocks at the impact; the king's flash (now only once the king is down).
- The camera's half circle in slow motion: how it looks.
- The punishment kubb fix (the search that used to trip the watchdog).
- The rough shimmering when the camera zooms or turns; the hand-cut M, N, W and 8 in the
  16 px display font; Roobert loading for labels.
- Raising and punishment by hand: how the screens read, the cursor, and the crank raise
  (270 degrees from lying to standing).
- VS PLAYDATE: how strong it plays, and its think pause.
- Name entry with the real keyboard; the drills played for real; resume after a real
  restart.

## Open calls

Jamie's to make, one at a time; each has a recommendation.

None.

## Licence

MIT (`LICENSE`; Jamie, 2026-11-13). The display font stays under the SIL Open Font
License; README.md says what is under which.
