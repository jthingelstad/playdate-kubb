# Status

Where the work stands, for whoever picks it up next. Updated 2026-11-13 (evening).

## On `main`

Everything built is merged; no branch holds unmerged work.

- Pass-and-play match and practice, with the rules engine, notation and saved game files.
- Smooth playback of throws (`AGENTS.md`, "Playback").
- The Woodcut look (`docs/design/README.md`): title, hand-off and winner cards, display
  font, launcher card, and the play screen (HUD, piece tones, ground).

## Fixed: the Woodcut play screen had slowed throws on the device

The autobench match case (the same three throws), on the device:

| | Before the play screen | With it | Now |
| --- | --- | --- | --- |
| Total time | 11.2 s | 16.3 s | 10.5 s |
| Shown speed (1.0 = real time) | 0.41 | 0.28 | 0.44 |
| Flight draw (full throw) | 18.0 ms | 23.5 ms | 19.1 ms |

Physics never changed; the draw took the physics' share of each 40 ms frame. Where it went
(`telemetry/2026-11-13/bench/run4` to `run7`): the rough's far quad (+1.8 ms), the grass
tufts (+2.4 ms), and the scene's draw estimate, which jumped to the slowest frame and so
took 1.7 ms a frame more than the draw needed. The 2 px outlines cost next to nothing.
Fixed by drawing the rough as two fills that stay on the screen, dropping the tufts and the
speed lines (speed over niceties, Jamie 2026-11-13), and letting the estimate rise by a
quarter of a step (`throw.tune.estRise`).

## Hit bursts

TOK!, KLAK KLAK! and KING! with synthesized knocks (AGENTS.md "Hit bursts"). The words
are still the board's, pending Jamie's call (Open calls).

## Changed from the boards on Jamie's word (2026-11-13, playing on the device)

- A piece never changes its look: no grey fallen kubbs, no black resting batons. The light
  on the faces stays.
- No speed lines (they did not follow the baton's turn).
- A SLOW MOTION flag while the slow motion around a hit plays.

## Device testing

`nolock` is in the game's Data folder on Jamie's Playdate so it stays awake for unattended
testing over USB (AGENTS.md "Measuring on the device"). Delete it when the testing is done.

## Team names

Entered before each match with the Playdate's keyboard and saved for next time (AGENTS.md
"Match", `scenes/names.lua`).

## VS PLAYDATE

A match against the computer from the title (AGENTS.md "Match"). One level so far:
`scenes/match.tune.cpuScatter` sets how steady it is.

## Raising and punishment by hand

The defending team raises each kubb thrown in (choosing the end) and places punishment
kubbs itself (AGENTS.md "Match", `scenes/settle.lua`).

## Not checked on hardware yet

- The punishment kubb fix (the search that used to trip the watchdog).
- The rough shimmering when the camera zooms or turns.
- The SLOW MOTION flag, the one-look pieces and the new rough, as played.
- The hit bursts and their knocks (how they look and sound at full speed; the king's
  screen flash).
- The hand-cut M, N, W and 8 in the 16 px display font; Roobert loading for labels.
- Raising and punishment by hand: how the two screens read and how the cursor moves.
- VS PLAYDATE: how strong it plays, and whether its think pause feels right.
- Name entry with the real system keyboard (only scripted in the Simulator self-tests).

## Not built yet

1. Saved games and resume, practice drills.
2. In the slow motion of a hit, the camera swings a half circle around it (Jamie's idea,
   2026-11-13): build after the bursts, measure its cost on the device.

## Open calls

- Hit words: the design uses TOK / KLAK / KING; the brief asked for POW / BAM.
- A licence, before the repo goes public.
