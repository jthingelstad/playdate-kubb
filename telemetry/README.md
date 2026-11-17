# Device telemetry

Copies of what the game recorded on a real Playdate, kept so tuning and speed work can be
done away from the device. One folder per day. Nothing here is read by the build or the
tests.

- `traces.jsonl`: every recorded swing, one JSON line each (format at the top of
  `core/trace.lua`). Replay with `lua5.4 tools/replay_traces.lua <file>` in kubb-engine.
- `frames.jsonl`: one line per throw of frame timing (`docs/notes/performance.md`, "Frame-time log").
- `games/`: the game files the device wrote for finished matches.
- `bench/`: autobench output (`docs/notes/performance.md`, "Measuring on the device").
- `watchdog-reset.txt`: the device's crash log entry when a build hung.

## 2026-11-13

The first day of play, across many builds: times in the files are the device's clock (US
Central). `traces.jsonl` and `frames.jsonl` were copied before the Woodcut play screen was
installed.

| Bench file | Build |
| --- | --- |
| `run1-before-smoothing.txt`, `run1-frames.jsonl` | before the playback smoothing work |
| `run2-smoothing.txt` | with smoothing; the full run with the per-part draw costs |
| `run3-woodcut-play-screen.txt` | with the Woodcut play screen; cut short, match cases only |
| `run4-woodcut-full.txt` | the same build three minutes later, run to the end: the per-part draw costs (found on the device afterwards) |
| `run5-draw-split.txt` | the same play screen with the profiled match case: each flight frame's draw split, and one variant per suspect (outlines, tufts, rough, speed lines) |
| `run6-cheaper-rough.txt` | the rough as two on-screen fills, no speed lines; variants for tufts (16, 8, 0) and the draw estimate |
| `run7-speed-fix.txt` | the fix: no tufts, the estimate rising by a quarter; 0.44 of real time |
| `run8-bursts.txt` | with the hit bursts: 0.44 (0.45 without them); the first burst's image loading made a 173 ms frame, since moved to launch |
| `run9-resume-save-cut-short.txt` | the resume save timed (pack 42 ms, write 68, read 20); cut short by mounting the disk |
| `run10-resume-save.txt` | the same, run to the end |
| `run11-save-no-copy-cut-short.txt`, `run12-save-no-copy-cut-short.txt` | the save handing the datastore the live tables (pack 0.5 ms); cut short |
| `run13-bursts-at-touch.txt` | bursts timed by the first touch: still 250 to 320 ms of shown time late, the physics not yet at the topple |
| `run14-bursts-predicted.txt` | the fall judged at the impact: bursts 2 to 6 ms after it; 0.43 |
| `run15-camera-half-circle.txt` | the camera's half circle at 40 ms a frame: 0.36 against 0.42 without it, the hit 6.4 s against 4.2 |

`watchdog-reset.txt` is the reset caused by the slow punishment kubb search, since fixed.

## 2026-11-14

The overnight QA build, after midnight (US Central).

| Bench file | Build |
| --- | --- |
| `run1-half-circle-variants.txt` | the half circle's variants: at 40 ms a frame the hit takes 6.7 s, at 60 ms 4.7, without it 4.2 (0.34, 0.40, 0.42); the open view costs nothing measurable |
| `run2-final-main.txt` | final `main` after the night's merges: 0.39 to 0.40 (0.41 without the half circle), the hit 4.6 to 4.8 s, nothing starved; bursts 4 to 12 ms after the impact |
| `run3-collector-held.txt` | the collector held off in flight (not merged): 0.39, the same as without the hold (0.40) |
| `run4-after-reset.txt` | the shorter slow motion, the first run after the Playdate's reset by hand: everything slower, the physics too (4.95 ms a step against 3.95), so not comparable with the runs before |
| `run5-slow-motion-shorter.txt` | the shorter slow motion against the old one in the same run: the hit 6.20 s against 5.78, 0.30 against 0.31 of real time; the slide after a hit is bound by the physics either way |
| `run6-ground-texture.txt` | grass with its texture against flat grass in the same run: the three throws 10.61 s against 10.69 (0.43 both), 3.88 against 3.84 ms a physics step; hit and miss settle sooner, the drill later |
| `run7-sand-snow.txt` | sand and snow against grass in the same run: the three throws 11.4 s on sand, 15.0 on snow, 11.3 on grass (11.4 flat); a physics step 3.96, 4.88 and 4.08 ms. Snow's slides run longer and cost more a step (more steps sliding in contact); sand stops sooner |
| `run8-sets-far-band.txt` | the kubb sets' first version, a black head band on every kubb: the three throws 13.5 s with USA and 13.3 with Wisconsin against 12.0 and 12.3 classic (about a tenth of the shown speed), so it was cut |
| `run9-sets-near-only.txt` | the sets painted from 20 px only (far kubbs as classic): 11.9 s with USA and 11.8 with Wisconsin against 11.5 and 11.8 classic, within the noise |

`soak/` holds the device soak's `soak.txt` (`docs/notes/performance.md`, "Measuring on the device"):

| Soak file | Build |
| --- | --- |
| `run1-final-main.txt` | final `main`: three whole matches (16, 25 and 7 turns, 402 throws, 40 minutes), no error, 56 save checks good, memory steady at about 1.03 MB after collection; 223 flight frames over 200 ms (worst 302), all in the long matches |
| `run2-slow-frames.txt` | the same matches' kind with each slow frame broken down: the update 180 to 350 ms where the physics took about 80 (only the baton awake, about 8 ms a step) and the draw about 30; the heap grew 15 to 28 KB in each (its `gc +N KB` is the net growth, not memory freed: the label was wrong), about ten times a usual flight frame |
| `run3-collector-held.txt` | a try at holding the collector off in flight and catching up in the rest hold (not merged): no better, the slow frames unchanged (`gc` as in run2: net growth) |
| `run4-profiled-stopped.txt` | branch `soak-profile`, each slow frame's update split by part: the throw's flight 70 to 105 ms (nearly all of it the physics), the bursts and camera 0 to 3, and 130 to 230 ms in the match scene's own update. These are the throw's landing frames (the physics' last calm-tail stretch, then the engine's ruling and the save), labelled by the mode the frame began in. Two matches finished (23 and 25 turns); the Playdate stopped answering USB during the third and needed a reset by hand, with nothing in its crash log |
| `run5-match1-classic.txt` | 2026-11-14 10:25, `main` with the advantage line, stay put, the basket inkast, the low throw and the sets: the first match (classic set, 25 turns, 196 throws) finished with no error, 27 save checks good, memory 0.92 to 1.09 MB; 132 frames over 200 ms (worst 319), the landing frames as in run4. Stopped there by a disk mount, so the USA and Wisconsin matches did not run |

`traces.jsonl` and `frames.jsonl` (copied 13:45 Central): every swing and throw on the device
so far. The last 13 swings (13:33 to 13:36, `"release":"stop"`) are Jamie's first with the
release where the crank stops: launch angles from -27 to 137 degrees against a loft set of 23
to 35, most batons landing 1 to 2.6 m out. Two causes: the stop was called when the flick
fell to half its peak speed (on several the crank was still turning at about 300 deg/s),
and every degree off the notch counted in full. Fixed by calling the stop only when the
crank all but halts (`releaseStopDps`) and the forgiving notch (`releaseTolDeg`,
`releaseGain`). These lines end at the old release, so they replay as unfinished under the
new rule.

## 2026-11-15

The first play test of the clock throw (PR #91), practice at Club level, about 9:00 to 9:20
(US Central). `traces.jsonl` is the device's whole file; its 24 `"release":"clock"` lines
are the new throw (13 batons, 9 drilled kubbs, some thrown badly on purpose). What they
showed:

- The power verdict ignored the flick: the first throw had its backswing on the target and
  a 534 deg/s flick, went 2.6 m of 8 and said ON (now SLOW).
- Flicks ran 830 to 1620 deg/s, most past `fullFlickDps` (1000); every swing measured steady
  (shake 0.06 to 0.13).
- Baton stops ran late against 3 o'clock: for a 90 degree plan they stopped at 84 to 120,
  median about 106, so throws went high and long (8 to 10.8 m for 8). Drills stopped on
  their half past 1 plan (median about 135).
- Drills at 3 taps of spin moved 4 to 22 cm sideways after landing, nowhere near what a
  spun kubb does.
