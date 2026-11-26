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
  (drawn in display 16, its first stats line without the name) and six of the longest
  generated player names packed by width and cut to their woods (frame 1), and one that
  fits (frame 2).
- `names-fit`: every generated name (both kinds) measured in the label face, display 16
  and display 32 (the widest in its note), each fitting the rail, TEAMS (cut), PLAYERS and
  the Names screen in the label face; then the widest typed names (ten of the widest
  capitals, with a space and marks) fitting every place whole but TEAMS, which cuts them to
  a full stop; frames: the rail with the widest player name, the hand-off card with the
  widest team name and KID RULES, the hand-off card and the rail with the widest typed
  name.
- `soak`: the device soak for one short match (soak.lua), a Kid match against the Kid
  computer (`soak.tune.kid`), the save read back after every throw; `soak.txt` must end with `soak done`, no error and no failed save check.
- `resume`: a match driven to turn 3, saved by the scene, read back through the
  datastore and resumed (frames: the title's B RESUME line, the resumed hand-off card).
- `games`: the games list over three game files the test writes (frames: the list, the
  second game chosen, its score sheet, scrolled by the crank); B twice goes back to the
  title.
- `options`: the match options driven by the d-pad (frames: the defaults, SNOW, the
  RAISING row); A must give snow, six from the start, automatic raising and THROW TO GO on
  (the default, 1.1.0).
- `options-kid`: VS PLAYDATE's COMPUTER stepped left from CLUB to BEGINNER then KID
  (frame: KID with its line); A must give a Kid match (`computer` and `rules` kid, scene
  `bw`) and no throw to go.
- `set-save`: saved data from a build with the kubb set (match.md "Kubb sets"): a kept
  options choice with SET on USA shows five rows in PASS + PLAY (four and THROW TO GO since 1.1.0) (frame 1), keeps its other
  choices and gives the match no set and no computer level; VS PLAYDATE shows COMPUTER as
  the sixth row (club by default, pro after a tap); a match saved with `set = "usa"` resumes (frame 2, its hand-off
  card), plays (frame 3), saves again with the set untouched, and its game file, written
  when the team on turn resigns, is gated.
- `names`: the Names screen through the input provider (frames: the crank stepping a
  player's first word, the second word stepped, a shuffled name refused as taken, a team
  name's first word cranked from The onto an adjective, a typed name); every generated name
  shown is one of its kind, A takes it, B goes back; TYPE A NAME opens the keyboard, an
  all-space name is refused, a typed name is cut to ten letters and loses a digit, SHUFFLE
  goes back to the words, a rename opens a typed name typed and a generated one on the
  generator; a match takes the names.
- `players`: PLAYERS by hand (no LEVEL row since 0.12.0): three generated players made,
  a second Lucky Larch refused, a rename, a removal; then a 0.11.0 roster with typed names
  (oloF, Playdate, Greta, Montgomery) loads unchanged and is not rewritten, plays a
  scripted match with those names and typed guests (a space, mixed case, a mark) on its
  sheet with unique ids (its game file gated), only a rename changes one (opened typed,
  typed again), and a typed new player with a taken id is refused (frames 5 and 6).
- `teams`: TEAMS for PASS + PLAY over five generated players, the order changed with hold
  A, A taps stepping a player's throw level STANDARD -> HARD -> EASY -> STANDARD -> HARD
  (1.1.0; frame 2 the row with HARD) without moving the order, Team A given a generated
  team name on the Names screen, START; the match's player carries `throw = "hard"`.
- `match-teams`: three against two in pass and play, a baton handed over through the
  change list; a person's throw on the meter (no level) and no `[Throw Levels]` in the game
  file (engine 0.13.2).
- `match-kid`: a whole Kid match against the Kid computer from the options' KID (frames:
  the hand-off card with KID RULES, the player's baton and kubb from the Kid line, the
  score sheet, the winner card): three base kubbs a side, every kubb and baton at a kubb
  from the Kid line and the king from the baseline, a person's throw on the Kid meter, the
  computer at kid, the Kid rulings' flag words, and the game file's `[Base kubbs "3"]`, Kid
  `[Rules]` and `[Throw Levels]` naming the computer only; the file is gated.
- `kid-aim`: the player's first baton of a Kid match by hand (frames: first person, the
  plan view): the stance on the Kid line, the flag, three base kubbs a side, the Kid meter's
  bars wider than the standard's at the same throw.
- `settle`: raising a kubb and placing a punishment kubb by hand, on an engine driven to
  turn 3 (frames: the held raise view on the engine's end, after right and left on the
  d-pad (each picks the end on that side; since 1.1.0 the d-pad no longer turns or zooms
  the view), the placement view, a spot refused by the king); the check reads the engine
  after A places it, and that the held camera did not move.
- `auto-raise`: the System Menu's Auto raise (B REST OF GAME before 1.1.0;
  `match.setAutoRaise`), six a side (match.md "Auto raise"): B's raise at turn 3
  after the pass card (frames: the raise view by hand, the automatic view with
  BY HAND), its first kubb at once and the second after the wait, `autoRaise` in the save
  at once (no side file); A's raise at turn 4 resumed from the datastore raises by itself
  with no pass card (frame 3), then BY HAND clears it in the save, brings the pass card and the rest are
  raised with A; then VS PLAYDATE, A's raise with no card, all by itself, a resign after it
  still the player's. Each part must leave the same pitch and score sheet as a copy raised
  with the match's policy for the side (`cmatch.raisePolicy`, the copy's `m.cpu` set as the
  scene sets it: since engine 0.12 a person's ends are the engine's advice, not
  `g:raise(nil)`'s `apart`). Last, PASS + PLAY resumed into A's automatic raise from an older build's
  `-raise` side file (the first save carries it and the file is deleted): Match: resign there is B's
  (B, the attacker, holds the Playdate; frame 4), A wins, and the game file is gated.
- `watch-skip` (1.1.0, match.md "VS PLAYDATE: the player's end, SPEED and SKIP"): the same
  VS PLAYDATE match twice to turn 4 (the player's throws from seed 5, instant; the
  Playdate's from cpuSeed 7; raising by hand with Auto raise on), first watched with B
  stepping SPEED to 4X, then with A, SKIP, at the start of every Playdate turn and raise.
  Both game files must be the same line for line (bar the clock tags), every Playdate throw
  turned and no player's, and the Playdate's raises shown in the watched run and cut short
  in the skipped one (frames: its aim from the player's end with the plaque, its baton in
  flight, its raise watched, the SKIPPING card).
- `togo` (1.1.0, match.md "Throw to go"): VS PLAYDATE (the card before the player's baton,
  the Playdate's from the player's end, the verdict, turn 1 on the side it gave, a resign at
  turn 2 and a gated game file with `[Engine:first]`); PASS + PLAY with a tie forced on the
  verdict (TIE: THROW AGAIN, round 2's card passes the Playdate); a save during the throw
  to go marked `togo` resumes into round 1, and THROW TO GO off saves `togoOff` (frames:
  the card, the Playdate's baton aimed, the verdict, the tie, round 2's card).
- `throw-level` (1.1.0, saved-players.md "Throw levels"): PASS + PLAY with the first player
  on HARD, then on EASY (frames: the clock on HARD, the narrowest bars a person meets, and
  on EASY); each aim must be planned on that meter, HARD's release bar narrower than
  STANDARD's at the same throw and EASY's bars wider, and `[Throw Levels]` must name it.
- `settle-crank`: the same raise with the crank turned forward (frame: half way up on the
  right-hand end); all the way up must stand it on that end's footprint.
- `seat` (core 1.0, `docs/notes/match.md` "The seat"): a new match's first throw on grass
  and on sand (frames 1 and 3, the aim view; 2 and 4 a low look along Team A's baseline,
  with a dotted plumb line from each kubb's foot that only this test draws), then B's
  raise of a1 by the crank (frame 5, the last frame before it stands) and the next throw
  (frame 6 its first frame, 7 a low look at a1). The check at each throw: every standing
  kubb is drawn off plumb and within its surface's seat (grass 2, sand 3 degrees), and a
  world built from the scene's items has every body at its item's orientation (to 1e-4).
  The match scenarios' `pitchMatchesEngine` (`_match.lua`) also fails a standing kubb drawn
  plumb where the world would seat it.
- Physics scenarios: `hit` (b3 knocked over, stays down, reset), `miss`, `field` (a
  group of field kubbs), `skid`, `skid-sand` and `skid-snow` (the kick after landing on
  each surface), `king`, `low-hard` (the arc planned down to half past 5: a low throw
  takes a field kubb 6.5 m out), `short-throw` and `short-over` (a field kubb 1 m ahead
  of the stance, engine 0.8's short throw: the plan's clean crank throw leaves the plan's
  low hand and topples it; wound three power bands long it heaves up and leaves it
  standing; helpers in `_short.lua`), `burst`, `burst-reset`, `layer`, `knocks`, `drawcalls`,
  `autoreset`, and `bench` (the Bench screen; its note has the Simulator's figures, which
  are the Mac's, not the device's). They set the target circle (and the arc) in `setup`
  and throw the plan's clean swing (`planned`): the default aim is the circle on b3.
- The throw ("The throw" below): `clock-throw` (point and throw, no A or B: the default
  target, stance and arc, wound into the power target and stopped on the release target,
  the default arc for 8 m, 4 o'clock since engine 0.10 (3 o'clock before); a base
  kubb goes down, ON ON STEADY, the verdicts and dots on the next aim), `clock-plan` (A
  walks and the targets move, B moves the arc two ticks from the default arc for the
  distance and the release target is the person's meter's for that distance (engine 0.10
  and 0.13; until 0.13 it was 3 o'clock and club's half width), B tilts, a drill's spin and arc, the
  drill's circle moves freely, `aimAt` snaps a baton's onto b2, and the d-pad moves it off
  b2 without snapping back), `clock-drill` (a drill at half
  past 1 with a tap of spin rests within 1 m of the circle and stays on the pitch; 0.4 m
  before drills ran on, 2026-11-16),
  `clock-letdown` (a flick stopped at 8 o'clock and a slow let-down throw nothing; CRANK
  DOWN while the crank is parked behind 6), `crank-flip` (the crank flipped with
  `throw.flipCrank`, what "crank" calls: CRANK FLIPPED, today's swing winds and is let
  down without a throw, the plan's swing turned the flipped way takes a base kubb down),
  `crank-flip-mid` (flipped in the middle of a wind-up: back to idle, no throw; the flick
  after it only winds), `crank-flip-flight` (flipped with the throw in the air: the recorder
  keeps the swing's samples and the sign it was thrown with), `crank-nudge` (three forward turns from 6 show the hint with the
  practice pitch's words, the wind-up hides it, the throw clears the count; the match's
  wording fits on screen), `gauge` (the prompts: WIND BACK, FLICK! anywhere inside the
  power target, which on the meter is 2 degrees either side at 8 m, EASE
  OFF, none in the flick), `gauge-ghost`, `rearm`, `windup`, `flight` (the trace line read
  back with its plan, at the default arc for 8 m), `helicopter` (a stuttered flick wound 40
  past the power target: on the meter the shake costs less than Pro's did, so a stutter
  alone at 8 m no longer throws a helicopter, engine 0.13), `nerves` (the clean swing with
  the nerves on: a little off the line, STRAIGHT, as the meter promises; PULLED RIGHT
  until 0.13), `aim-center`, `aim-arc`
  (first person and the plan view for targets across the half, every release and stances
  at both ends: "The aim camera"; a drill's arc may rise above the fit box into the gap
  under the rail, counted in its note: one, the half-past-12 drill to the far corner from
  the far end of the line, 22 px against the box's 24, since engine 0.10's drill), `camera-swing` (B held and let go, a baton's and a
  drill's; its note counts the aim frames' graphics calls, camera still and moving), `plan-ticks` (B + the d-pad: a tap is one tick of arc, tilt or
  spin, held it slides a tick a frame to the end of the range; frames: the plan view after
  the slide, SPIN R 0.25; a kubb's spin kept for the side's next kubb in the inkast turn), `clock-gauge` (the clock's states drawn alone, cache on and
  off; since engine 0.16 also a drive's targets with the knee's notch, DRIVE -5° and
  DRIVE -15° and a single-digit ARC 5° with their words), `drive` (engine 0.16, "The drive"
  in throw.md: the default at a kubb 1.5 m from an advantage line, 4 m and 8 m away; B +
  down to the throw's floor and no lower, a tap up from it moving the throw at once, up past
  the knee to ARC again, the floor at 8 m the knee and a drilled kubb's too, the ARC words
  at each; the side view's arc falling from the hand to the kubb's face; the default drive
  thrown on the plan's clean swing: no end over end turn, the kubb down. Frames: ARC at 1.5
  m, the side view at the floor, ARC at 4 m, ARC at 8 m, a drive in flight, at rest), `drive-solves`
  (a drive lowered to its floor at 1.5 m and kept: no solve while walking back, moving the
  circle or cranking, the arc greyed meanwhile; one solve, raised once, when each movement
  stops; a snap, RESET, drilling and back, the drive thrown and the circle retargeting at
  rest, at most one solve each; never two solves in a frame; a match's next throw drops the
  kept release. Frames: walking with the arc greyed, the walk stopped), `cpu-drive` (the
  computer's drive, engine 0.18: VS PLAYDATE at club resumed at a turn where it throws from
  an advantage line at a group about 1.7 m away; its baton is planned on the person's
  default line under the knee, played out with its aim, its arm on the clock, the flight
  and the rest; in the no-turn part of the drive its axis stays up until it touches; the
  scene's `autothrow.choose` times in the note, the Mac's. Frames: its aim (WATCH), its arm
  on the clock, the drive in flight, at rest; "The computer's drive" in throw.md), `howto` (HOW TO THROW: every step done, 17 frames; "HOW TO THROW" below),
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
