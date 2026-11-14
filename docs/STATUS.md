# Status

Where the work stands, for whoever picks it up next. Updated 2026-11-14, early morning
(US Central), after the overnight round.

## On `main`

Everything built is merged except the diagnostic timing hooks on branch `soak-profile` (see
"Open problem").

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
  king is judged only once it has toppled (see Open calls).
- **The camera's half circle** (Jamie's idea): in slow motion after a hit the camera goes
  half way round the struck piece and opens out to show the pitch round it. While it turns
  every frame is a full draw, so those frames take 60 ms instead of 40; that keeps its cost
  to about half a second a hit (see Open calls).
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

## Open problem: slow frames late in long matches

Jamie's own play (101 throws in `frames.jsonl`) never had a frame over 121 ms, but the
soaks' long matches (16 turns and more, 20 or so bodies on the pitch counting debris) have
0.2 to 0.4% of flight frames at 200 to 400 ms, a visible hitch. Broken down
(`telemetry/2026-11-14/soak/run2-slow-frames.txt`): the update takes 180 to 350 ms of it
with only the baton awake, the physics about 80 ms of that at about 8 ms a step (four
times its usual), the draw about 30, and the collector ran in every such frame. Holding
the collector off in flight changed nothing (`run3-collector-held.txt`), so it is not the
collector alone. Next: time each part of the update in those frames. The hooks for that
are on branch `soak-profile` (not merged): the Playdate stopped answering USB during its
first soak (below), so they wait until that is understood.

## Changed from the boards on Jamie's word (2026-11-13, playing on the device)

- A piece never changes its look: no grey fallen kubbs, no black resting batons. The light
  on the faces stays.
- No speed lines (they did not follow the baton's turn).
- A SLOW MOTION flag while the slow motion around a hit plays.
- Hit words stay TOK! / KLAK! / KING!.

## Device testing

`nolock` is in the game's Data folder on Jamie's Playdate so it stays awake for unattended
testing over USB (AGENTS.md "Measuring on the device"). **Delete it when the testing is
done.**

**The Playdate stopped answering over USB at about 5:00 this morning** (US Central), during
a soak of the `soak-profile` build started at 04:15: the serial port is there, but it
neither mounts its disk nor relaunches the game. It needs a reset by hand (hold LOCK, MENU
and A together for about ten seconds), then `main` installed again (it has `soak-profile` on it now). Its `soak.txt`
from that run may say what happened.

## To try on the device

- The bursts and knocks at the impact; the king's flash (now only once the king is down).
- The camera's half circle in slow motion: how it looks, and whether half a second more a
  hit is worth it.
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

1. **The camera's half circle costs about half a second a hit** (4.7 s against 4.2 for the
   match case's hit; 0.40 shown speed against 0.42). Recommendation: keep it on as built
   (60 ms frames while it turns). Turning it off is one number
   (`throw.tune.swingDeg = 0`).
2. **The king's burst waits until the king is down.** A king judged falling from the strike
   alone could be a king merely pushed, and its flash and chord read as the game's end, so
   the king's burst can come up to the physics' lead (a fraction of a second) after the hit
   where a kubb's comes at it. Recommendation: keep it so.
3. **PASS + PLAY has no "pass the Playdate" card around raising.** When the defending team
   raises or places punishment kubbs, only the rail's team name says who should hold the
   Playdate. Recommendation: a short card before the defender's settle ("RAISE: <TEAM>, A
   to start") and none after.

## Licence

MIT (`LICENSE`; Jamie, 2026-11-13). The display font stays under the SIL Open Font
License; README.md says what is under which.
