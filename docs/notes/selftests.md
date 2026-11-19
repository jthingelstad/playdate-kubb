# Simulator self-tests

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

## Simulator self-tests

- `Playdate Simulator <abs pdx> selftest=<name> out=<abs dir>`: arguments after the pdx
  arrive in `playdate.argv` (item 1 is the pdx). Launching the binary directly works; no
  `open` needed.
- A scenario is `source/selftest/<name>.lua`, imported from `main.lua`, registering
  `tw.selftest.scenarios.<name> = { step = function(ctx) ... end }`. `step` runs once per
  frame until it returns true; `ctx:capture()` saves `<name>-NN.png` (400x240) and
  `<name>-NN@2x.png` (800x480).
- Lua `print` does not reach the Simulator's stdout, and `playdate.file` writes only inside
  the game's Data folder. So the runner writes `DONE`/`FAIL` to
  `~/Developer/PlaydateSDK/Disk/Data/com.throwingwood.playdate/selftest/<name>.done`, and
  the Makefile copies it to `build/selftest/` and checks it and the PNG sizes.
- The Simulator (SDK 3.1.2) often segfaults as it quits, after the scenario has written its
  marker; now and then the crash leaves it hanging until the timeout (`SIM_TIMEOUT`, 300 s). The Makefile
  counts a timed-out run by its `DONE` marker when there is one (and says so), so these
  are not failures; a run with no marker still is.
- The Simulator connects to a Playdate plugged in over USB when it starts. Self-tests do not
  touch the device, but do not unplug or reboot it.
- Screenshots for Jamie are the 2x frames. The 1x frames are for agent checks.
- Film mode: with `film=1` after `out=` the runner also saves every frame (1x) as
  `<out>/<name>-f00001.png` and on, 50 to a second of shown time (the scripted input's
  pace). `sh tools/film.sh` builds the game, films the scenarios in `tools/film.py`'s
  `REEL`, cuts them into one reel (plays and held stills, in order) and encodes
  `build/film/throwing-wood-<version>.mp4` (800 x 480, 50 fps, H.264, about 0.8 MB for 26
  s) and `.gif` (400 x 240, 25 fps, two colours, about 0.5 MB), with ffmpeg. The same
  build gives the same files. For the sites (thingelstad.xyz shows a GIF inline; an MP4
  artifact there downloads).
- Files in `source/selftest/` whose names start with `_` are helpers, not scenarios (the
  Makefile skips them). A scenario may set `ctx.note` to a one-line string; the runner
  appends it to the `DONE` marker (the throw scenarios put `avg_ms`/`max_ms` of
  update + draw there).
- Throw-scene scenarios use `tw.selftest.throwScenario{ script, shots, check, maxFrames }`
  from `source/selftest/_throw.lua`: `script` is an `input.scripted` step list (or
  `fn(scene)` returning one, called after `setup`, so a swing can be built from the
  scene's plan), `shots` an
  ordered list of predicates `fn(scene, frame)` that each capture one frame when they first
  return true, `check(scene)` returns an error string or nil. `tw.selftest.windup(deg, n)`
  and `tw.selftest.flick{deg, ...}` build crank steps in forward degrees and apply the
  crank sign for you; `tw.selftest.planned(s, backOff, stopOff, after, opts)` is a swing
  against the scene's plan (`input.swingSteps`: wound to the power target's centre plus
  `backOff`, a full flick stopped at the release target's centre plus `stopOff`; 0 and 0
  is the plan's clean throw) and `tw.selftest.swingTo(back, stop, after, opts)` one to
  given clock degrees. Every scenario must also be imported from `main.lua`.
  `setup(scene)` runs once after the scene is made (`throw.setLayout`, `scene.surface`,
  and the aim: `throw.aimAt`, `setStance`, `setArc`, `setTilt`, `setSpin`).
  For physics frames use `tw.selftest.sinceHit(s)` / `sinceContact(s)` (seconds on screen
  relative to the baton's first hit or touch, nil until the physics has found it),
  `restShot(n)` (n frames into the rest; the rest hold is 50 frames) and `item(s, id)`.
  A scenario that runs out of frames reports the scene's mode, playback frame and awake
  bodies in its `FAIL` line.
- `title`: the title with VS PLAYDATE chosen (frame 1), PRACTICE after two right presses
  (frame 2), and A must leave with `practice`; frame 3 a new player's title (the HOW TO
  THROW line), frame 4 a resume line with long team names cut to `RESUME TURN 12`.
- `cards-fit`: the winner card with a team name too wide for display 32 beside the burst
  (drawn in display 16, its first stats line without the name) and six ten-letter
  players packed by width (frame 1), and one that fits (frame 2).
- `soak`: the device soak for one short match (soak.lua), the save read back after every
  throw; `soak.txt` must end with `soak done`, no error and no failed save check.
- `resume`: a match driven to turn 3, saved by the scene, read back through the
  datastore and resumed (frames: the title's B RESUME line, the resumed hand-off card).
- `games`: the games list over three game files the test writes (frames: the list, the
  second game chosen, its score sheet, scrolled by the crank); B twice goes back to the
  title.
- `options`: the match options driven by the d-pad (frames: the defaults, SNOW, the
  RAISING row); A must give snow, six from the start and automatic raising.
- `sets`: every kubb set up close (frames 1 to 5: classic, USA, Sweden, Minnesota,
  Wisconsin) and USA from the baseline (frame 6); classic drawn again must match its first
  frame, and every other set must differ from it.
- `names`: the names screen for PASS + PLAY without the keyboard (frames: ASH as typed, a
  long second name drawn smaller); a name with no letter is refused, B goes back, and the
  names become the match's teams.
- `settle`: raising a kubb and placing a punishment kubb by hand, on an engine driven to
  turn 3 (frames: the raise view, the view turned and zoomed out by the d-pad, the
  placement view, a spot refused by the king); the check reads the engine after A places
  it, and that the d-pad turned and zoomed without changing the end.
- `settle-crank`: the same raise with the crank turned forward (frame: half way up on the
  right-hand end); all the way up must stand it on that end's footprint.
- Physics scenarios: `hit` (b3 knocked over, stays down, reset), `miss`, `field` (a
  group of field kubbs), `skid`, `skid-sand` and `skid-snow` (the kick after landing on
  each surface), `king`, `low-hard` (the arc planned down to half past 5: a low throw
  takes a field kubb 6.5 m out), `burst`, `burst-reset`, `layer`, `knocks`, `drawcalls`,
  `autoreset`, and `bench` (the Bench screen; its note has the Simulator's figures, which
  are the Mac's, not the device's). They set the target circle (and the arc) in `setup`
  and throw the plan's clean swing (`planned`): the default aim is the circle on b3.
- The throw ("The throw" below): `clock-throw` (point and throw, no A or B: the default
  target, stance and arc, wound into the power target and stopped at 3 o'clock; a base
  kubb goes down, ON ON STEADY, the verdicts and dots on the next aim), `clock-plan` (A
  walks and the targets move, B moves the arc and tilts, a drill's spin and arc, the
  drill's circle moves freely, `aimAt` snaps a baton's onto b2, and the d-pad moves it off
  b2 without snapping back), `clock-drill` (a drill at half
  past 1 with a tap of spin rests within 1 m of the circle and stays on the pitch; 0.4 m
  before drills ran on, 2026-11-16),
  `clock-letdown` (a flick stopped at 8 o'clock and a slow let-down throw nothing; CRANK
  DOWN while the crank is parked behind 6), `crank-flip` (the crank flipped with
  `throw.flipCrank`, what "flip crank" calls: CRANK FLIPPED, today's swing winds and is let
  down without a throw, the plan's swing turned the flipped way takes a base kubb down),
  `crank-flip-mid` (flipped in the middle of a wind-up: back to idle, no throw; the flick
  after it only winds), `crank-nudge` (three forward turns from 6 show the hint with the
  practice pitch's words, the wind-up hides it, the throw clears the count; the match's
  wording fits on screen), `gauge` (the prompts: WIND BACK, FLICK!, EASE
  OFF, none in the flick), `gauge-ghost`, `rearm`, `windup`, `flight` (the trace line read
  back with its plan), `helicopter` (a stuttered flick at Pro), `aim-center`, `aim-arc`
  (first person and the plan view for targets across the half, every release and stances
  at both ends: "The aim camera"), `camera-swing` (B held and let go, a baton's and a
  drill's; its note counts the aim frames' graphics calls, camera still and moving), `clock-gauge` (the clock's states drawn alone, cache on and
  off), `howto` (HOW TO THROW: every step done, 17 frames; "HOW TO THROW" below),
  `howto-play` (HOW TO PLAY's six cards and the hand-off into HOW TO THROW: "HOW TO
  PLAY" below).
- Match scenarios use `tw.selftest.matchScenario{ opts, step, maxFrames, refreshRate }`
  from `source/selftest/_match.lua`: `opts` are `scenes/match` options (`seed` for
  `core/autothrow` throws instead of the crank, `instant`, `skipHandoff`, `maxTurns`),
  `step(ms, ctx, h)` runs after each frame with `h.feed(steps)`, `h.pressA()` and
  `h.idle()` for scripted input. `tw.selftest.pitchMatchesEngine(ms)` checks every item on
  screen against the engine's state and the setup's debris; `tw.selftest.debrisShown(ms)`
  counts the debris kubbs and batons on screen. Scenarios: `match-opening` (crank throws on
  the plan: Team A's two opening batons from a stance set off the middle and kept, the
  hand-off card, Team B's first throw in its turned view, standing behind its circle),
  `match-toss` (a kubb toss played back and the automatic raising after it),
  `match-group` (the computer drilling a turn of 3 and a turn of 5 into a group, played
  back; the note gives the frames each turn plays in for a film),
  `match-debris` (a downed kubb and a lying baton on the pitch for the next throw of the
  turn, that baton among them at rest, gone after the hand-off) and
  `cards` (a scripted match, seed 5: frame 1 the first hand-off with kubbs to throw in
  and a last turn to report, frame 2 the winner card, then A must ask for a rematch) and
  `match-whole` (a scripted match to a winner as fast as the Simulator goes, the A +
  d-pad walk up to the advantage line on the way; its marker names the game file, which the
  Makefile copies to `build/selftest/games/` and runs the notation gate over). The
  Simulator's floats differ from the desktop's, so the same seed plays a different match
  there than in `tools/physmatch.lua`: the checks do not depend on what happens.
