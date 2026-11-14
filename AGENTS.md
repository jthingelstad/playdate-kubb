# Kubb: Throwing Wood

A Kubb game for the Playdate (Lua, SDK 3.1.2). The design is `docs/DESIGN.md`; read it first.
`CLAUDE.md` is a symlink to this file.

## Repo and pull requests

- GitHub: `jthingelstad/playdate-kubb`, private for now. Jamie plans to make it public, so
  manage it as if it already were: no account ids, email addresses, device serial numbers,
  home-directory paths or personal details in files, commit messages or pull requests.
- `main` takes changes only through a pull request with a green `validate` check on a
  branch that is up to date with `main` (ruleset "main: pull requests on a green
  validate"). Merges are rebase merges; auto-merge is on; branches are deleted on merge.
- `validate` (`.github/workflows/validate.yml`) runs the Lua tests and the notation gate.
  Before opening a pull request run `make test` and `make selftest` locally: the Simulator
  cannot run on GitHub.
- Codex reviews every pull request. Read its inline findings and fix or answer each one
  before calling the work done.
- Other sessions share this checkout. Do side work in a `git worktree`, not by switching
  branches here.

## Commands

- `make build`: `pdc` compiles `source/` to `build/ThrowingWood.pdx`.
- `make test`: the Lua tests (`tests/lua/run.lua` on Lua 5.4) and the notation gate
  (`tests/node/notation-gate.mjs` over `tests/fixtures/games/`, then
  `tests/node/gate-rejects.mjs`, which checks every game in `tests/fixtures/bad/` is refused).
- `make selftest`: builds, then runs every scenario in `source/selftest/` in the Simulator.
  Frames land in `build/selftest/`. Each run takes about 2 seconds.
- `make games`: plays `GAMES_N` (500) seeded random games through the rules engine with
  `tools/games.lua` (no physics; `GAMES_SEED`, default 1), writes them to `build/games/`, then
  runs the notation gate over all of them. Every game must pass with zero warnings. Same seed,
  same files. It prints a count of the rare events it produced (rescues, punishment kubbs,
  early kings, helicopters and so on). Then it plays `PHYS_N` (5) matches with real physics
  (`tools/physmatch.lua`, see "Headless games") into `build/physgames/` and gates them too.
- `make bench`: the physics benchmark on the desktop (`tools/bench.lua`, three runs of
  `core/bench`, prints each and the best; then the same three runs with a full turn's debris
  asleep on the pitch, and the difference). `lua5.4 tools/bench.lua [runs] [--profile]
  [--micro]` adds the per-phase profile of `world.step` and the micro benchmarks of
  `core/microbench`. See "Measuring on the device" for the device side.
- `make clean`.
- `make release`: a clean build zipped as `build/ThrowingWood-<version>.pdx.zip`, for
  friends to sideload (play.date/account/sideload). Raise `version` and `buildNumber` in
  `source/pdxinfo` for each one (a Playdate keeps the higher build). The zip is published
  on files.thingelstad.com and linked from https://playdate.thingelstad.xyz/throwing-wood/
  (that site's repository). 0.1.0 (build 2), 2026-11-14: the first for friends.

Tools are called by full path: SDK at `~/Developer/PlaydateSDK` (no `PLAYDATE_SDK_PATH`),
`/opt/homebrew/opt/lua@5.4/bin/lua5.4` (keg-only), `/opt/homebrew/bin/node`. Install
nothing else without asking.

## Modules and `import`

- Every Lua file uses Playdate's `import "dir/name"` (path from `source/`, no `.lua`). Import
  runs a file once; a second import does nothing and returns nil, so modules do not return
  values.
- One global namespace table, `tw`, made in `source/core/tw.lua`. A module builds a local
  table and stores it as a field: `tw.vec`, `tw.scenes.title`, `tw.selftest`. Callers do
  `import "core/vec"` and then `local vec = tw.vec`.
- `tests/lua/run.lua` defines a global `import` that loads `source/<name>.lua` once the same
  way, so core files run unchanged under desktop Lua and under `pdc`.

## The pure core rule

`source/core/` is pure Lua 5.4: no `playdate.*` and no `CoreLibs` imports. A test fails the
build if either appears. Drawing, input and files live outside `core/` (`main.lua`,
`input.lua`, `recorder.lua`, `scenes/`, `render/`, `selftest/`). Camera, swing, flight
and trace math are in `core/` and tested on the desktop. In per-frame paths avoid making
tables or closures: cameras and scratch arrays are reused, `camera.project` returns
numbers. Playdate floats are 32-bit, desktop doubles: test
outcomes with tolerances, never bit-exact.

## Tests

- Lua: add `tests/lua/test_<thing>.lua`. Use `test(name, fn)`, `expect.eq`, `expect.near`,
  `expect.truthy`. The runner picks up every `test_*.lua`.
- Notation gate: every game file must pass the pk-kubb-score grammar, `kubb.js` must find the
  same winner as `[Win]`, and warnings fail unless `--allow-warnings` is passed. Player ids
  are letters and underscores only.

## pk-kubb-score is vendored

The gate loads `notation-parser.js` and `kubb.js` from `tests/vendor/pk-kubb-score/`, copies
of pk-kubb-score's `site/assets` files (Jamie approved the copy 2026-11-13, so the gate runs
on any machine and on GitHub). Never edit the copies; `make sync-notation` refreshes them
from a checkout at `~/Projects/pk-kubb-score` (or `$PK_KUBB_SCORE`). The checkout itself is
still read only: never write there and never run `npm install` there.

## Rules engine

`source/core/rules.lua` (`tw.rules`) is Rules V4.0 as a pure state machine. It knows nothing
about physics: it asks for the next action and takes resolved throws (the outcome records
below) and the defender's choices. Helpers: `core/pitch.lua` (dimensions, halves, stakes,
`advantageMeters`), `core/rect.lua` (oriented rectangles), `core/raising.lua` (II.D raising
and II.D.11 punishment geometry), `core/notation.lua` (score sheet and game file).

```lua
local g = tw.rules.new{ teams = { A = { name = "Jamie", players = { { name = "Jamie" } } },
                                  B = { name = "Playdate", players = { { name = "Club" } } } },
                        surface = "Grass", opening = "2-4-6" --[[ or "six" ]], first = "A",
                        raisePolicy = "apart" }
local n = g:need()
```

- Pieces: kubbs have permanent ids `a1`..`a5` (Team A's base kubbs at x = -2..2, y = 0) and
  `b1`..`b5` (y = 8); the king is `king`. `g.kubbs[id]` = `{ id, kind = "base"|"field",
  half = "A"|"B", where = "pitch"|"hand"|"out"|"punish", pose, thrown, established, fouled }`.
  `half` is the half a field kubb belongs to (where it was thrown), not recomputed from y: a
  kubb thrown this turn is a field kubb of the target half on the pitch wherever it lies
  until its round is judged. `where = "out"` means picked up for a rethrow. `fouled` marks a
  thrown kubb that touched the thrower's own half (II.C.4b) until it is judged.
  `g.king.pose`. `g:census()` counts kubbs by `where` (always 10). `g:liesNow(id)` says
  `"in"` or `"out"` for where a thrown kubb lies before it is judged; `g.judgment` is what
  the last judgment did (`thrown, rethrow, punish, rescue, lowered, lifted`), nil after a
  toss that did not end a round.
- State: `g.turn`, `g.attacker`, `g.defender`, `g.phase` (`toss`, `rethrow`, `raise`,
  `punish`, `batons`, `over`), `g.batonsLeft`, `g.advantageY`, `g.winner`, `g.how`,
  `g.sheet` (the notation score sheet).
- `g:need()` returns one of:
  - `{ kind = "toss", side, kubb, rethrow, throwY, half, left }`: the attacker throws kubb
    `kubb` from its baseline `throwY` into `half`. First throws come before rethrows (II.C.6).
    `left` counts this throw and the rest of its round (see "Judged at the final position").
  - `{ kind = "raise", side, kubb, pose, decision }`: the defender raises a lying kubb.
    `decision = { mode, choices, ends }` from `tw.raising.options`; mode is `choice` (both
    footprints clear and in bounds), `forced` (one), `displaced` (none clear: touching the
    obstruction, II.D.5; the defender may still pick the end when both qualify).
  - `{ kind = "punish", side, kubb, half }`: the defender places a punishment kubb.
  - `{ kind = "baton", side, n, of, left, kingShot, throwY, advantageY, targets }`: `throwY`
    is the advantage line when there is one and this is not a king shot, else the baseline.
    `targets` are the standing field kubbs, else the base kubbs, else `{ "king" }`.
  - `{ kind = "over", winner, how }`.
- Actions: `g:toss(outcome, player)`, `g:raise(choiceIndex | nil, policy)` (nil = automatic),
  `g:raiseAll(policy)`, `g:placePunishment(pose)` (returns false and a reason when invalid),
  `g:autoPunishment(policy)`, `g:throwBaton(outcome, player)`, `g:resign(side, player)` (only
  on the resigning team's own turn). `player` is an id or name; it defaults to the team's
  first player. Calling an action out of phase raises an error.
- Raising policies (`tw.raising.policies`): `apart` (default: the end farthest from other
  kubbs), `together`, `first`, or any `function(decision, ctx) -> index`. The punishment
  policy is a `function(candidates, ctx) -> pose`; the default puts it deep in the half and
  away from other kubbs.

### Poses

`{ x, y, standing, angle, onTop }` in world meters. `standing` = upright on an end; `angle`
is the long axis direction for a lying kubb (radians from +x) and the yaw of the square for a
standing one; `onTop` is the id of a kubb it rests on. A lying kubb raised on an end stands on
a 7 x 7 footprint centered 11 cm out along its axis (it pivots on that end's bottom edge).

### Baton outcome

What physics must report for one baton, after everything is at rest:

| Field | Meaning |
|---|---|
| `illegal` | true for an illegal throw (helicopter, II.B.1) |
| `toppled` | ids of every piece whose long axis came within a few degrees of horizontal at any point (II.B.10: one that ends standing on an end is still toppled). May include `"king"`. |
| `kingToppled` | true if the king was toppled (same as `"king"` in `toppled`) |
| `moved` | `{ [id] = pose }`: rest pose of every piece that moved, toppled or not (the king too) |
| `ownHalfHit` | ids of field kubbs in the thrower's own half that the baton touched, even if they did not move (II.B.11) |

The engine also treats any toppled or moved field kubb in the attacker's half as II.B.11.
What it does with them: illegal or II.B.11 throws put everything back and write `Z`; a king
toppled before every kubb is down loses (`E`, also after an illegal throw); toppled field
kubbs go to the defender's hand; a toppled base kubb with a field kubb still standing after
the throw is raised where it was (II.B.4a); a piece moved without toppling stays at its rest
pose unless its center left the pitch (II.B.7: put back).

### Kubb-toss outcome

| Field | Meaning |
|---|---|
| `rest` | rest pose of the thrown kubb: lying (with `angle`), standing on an end, or `onTop = id` when it rests on another kubb |
| `moved` | `{ [id] = pose }`: rest pose of every other piece it moved (field kubbs, base kubbs, the king) |
| `kingToppled` | true if it toppled the king (the throwing team loses) |
| `ownHalfHit` | optional ids of pieces in the thrower's own half it touched (II.C.4b) |

In bounds is the center of the standing kubb against the defender's half (lines are in). A
lying kubb is in if either footprint is. Struck field kubbs stay where they come to rest and
are raised there (II.C.4). Base kubbs a toss moves are stood back where they were. The king
toppled by a thrown kubb ends the game at once (`E`). Everything else waits for the
judgment below.

### Judged at the final position

The ruling (Jamie, 2026-11-13): whether a thrown kubb is in or out is not judged when it
stops. If a kubb is out and a later kubb moves it in, there is no rethrow; the rethrows go
by where every kubb lies once they are all thrown, and they come last.

- **Rounds.** A round is every kubb queued when it starts: the first throws (rescued kubbs
  among them) before the rethrows (II.C.6). While a round has throws left, every thrown kubb
  stays a piece on the engine's pitch at its rest pose (in, out of bounds, short of the
  middle line, in the thrower's own half), a field kubb of the target half, and later kubbs
  can move it. Nothing is judged.
- **The judgment** (`Game:_judge`, when the round's last throw is at rest), on every field
  kubb of the target half as it lies then, established ones included:
  1. a kubb resting on another is lowered beside it (II.D.6, `N`), unless the kubb under it
     is out (it is picked up: the upper kubb lies where it is, no `N`);
  2. an established field kubb that cannot be raised in bounds is rescued (II.C.5a, `Q`):
     back to the attacker as a kubb not yet thrown, thrown in the next round;
  3. a kubb thrown once that cannot be raised in bounds is picked up and rethrown in the
     next round (II.C.5b, II.C.6); so is one thrown once that a rethrow knocked out;
  4. a kubb thrown twice that is still out is a punishment kubb (II.C.5c, II.D.11, `P`).
  Out kubbs leave the pitch at the judgment, all at once. Rounds go on until nothing is left
  to throw; then the defender raises and places punishment kubbs as before.
- **II.C.4b at the final position.** A thrown kubb that touches a field kubb in the
  thrower's own half fouls at once: that kubb is put back (nothing in the own half is
  applied), the note is written, and the thrown kubb is out at the judgment wherever it
  lies by then (it stays on the pitch until then, a piece later kubbs can hit). A thrown kubb
  lying in the thrower's own half at the end without having touched anything is simply out
  (not in bounds). Moving a kubb thrown this turn is never II.C.4b, wherever it lies.
- **A rescue is judged at the end too:** an established kubb knocked out and knocked back in
  before the round ends stays where it lies, no `Q`.

## Notation conventions

`core/notation.lua` keeps the score sheet as the engine runs and renders the game file
(DESIGN.md section 7). `tw.notation.render(game, { start, finish, version, mode })` gives the
text; times are `{ year, month, day, hour, min }` tables passed in (no `os.time` in core);
`tw.notation.filename(start, teamA, teamB)` gives `YYYY-MM-DD-HHMM-<a>-v-<b>.txt`.

- Player ids: lowercased name, spaces and hyphens to `_`, everything else but letters
  dropped; a taken id gets `_b`, `_c`, ... Names in headers lose quotes and brackets; player
  names also lose commas and parentheses (kubb.js splits on them).
- Inkast token per player, in order of first toss: `I` = every first throw this turn
  (rescued kubbs included, so I = kubbs knocked last turn + Q), `R` = every rethrow made,
  `P` = punishment kubbs (also in R), `Q` = rescues, `N` = kubbs that came to rest on another
  (capped at 5, the grammar's limit), `E` = king toppled by a thrown kubb. `Y` is never
  written. No inkast token when there was nothing to throw. `I` and `R` are inked when the
  kubb is thrown; `P`, `Q` and `N` when the round is judged, to the player who made its last
  throw (the grammar takes the letters in any order; the token always writes `IRPQN`).
- When the game ends before the inkast is done (king toppled by a kubb, or a resign), the
  token still counts every kubb that was due, so kubb.js's inkast check holds.
- `nA` follows the inkast: whole meters from the attacker's own baseline to the advantage
  line, rounded down, 0 to 4.
- Batons: `-`, `F`/`nF`, `B`/`nB`, `FB`, `K`, `=`, `Z`, `E` or `nFE`/`BE`, `G`, then `X`
  for each baton left once the game is over (after `K`, `E`, `G` or an inkast `E`).
- Notes (`# a; b`) say what the tokens cannot: `bN toppled a base kubb early; raised
  (II.B.4a)`, `bN hit a field kubb in the thrower's own half; all put back (II.B.11)`,
  `bN pushed a kubb out without toppling; put back (II.B.7)`, `a kubb hit a field kubb in the
  thrower's own half (II.C.4b)`, `bN toppled the king early`, `king toppled by a thrown
  kubb`, `resigned during the inkast`. `bN` is the turn's Nth baton.
- `[Rules "U.S. Championship 4.0, 2-4-6"]` or `"..., six from the start"`.

## Headless games

`tools/thrower.lua` is a random thrower with no physics: hit or miss by distance and skill,
neighbours toppled or pushed, inkast landing spots with scatter, and rare events on purpose
(rescues, punishment kubbs, kubbs on top of others, helicopters, own-half hits, early base
kubbs and kings, resigns). Its rates are `thrower.tune`. `thrower.playGame(seed, check)`
plays one game; `tests/lua/test_games.lua` plays 50 and checks invariants after every
action; `tools/games.lua` writes N games. `tests/fixtures/games/` holds eleven generated games
plus the two hand-written ones; `make test` gates them. The thrower sometimes aims at a kubb
of this turn lying out near the target half and knocks it toward the middle (`chaseOut`),
so games have kubbs knocked in before the round is judged; `make games` prints
`knockedIn`/`knockedOut` and the sheets' `R`, `P`, `Q`, `N` counts.

`core/autothrow.lua` is a scripted thrower for physics: for a match setup it picks where to
stand, swivel, loft, launch speed and tumble (seeded scatter, `autothrow.tune`), aiming
batons at the nearest live target (from the advantage line, but never nearer than
`minRange`, 2 m: a slow lofted baton under 2 m nearly always missed) and tosses at the
basket (Jamie, 2026-11-14): the corner of the far half nearest the centre line by a
sideline (`basketX`, `basketY`), the one that already has more field kubbs near it, so a
turn's kubbs group and one that runs goes out for a rethrow. Over 30 physics matches (seed
7) against the old random spot: 18.9 turns a game against 23.5, 3 resigned at the turn
limit against 5, a rethrow in 20% of inkasts against 18%, advantage lines 2.4 m on average
against 1.1. `tools/physmatch.lua [--n --seed --out --maxturns -v]` plays whole matches through
`core/match` with every throw run by `core/world` to rest (the match scene's path without
the screen; about 0.7 s a match on a Mac) and writes the game files. Past `--maxturns`
(40) the team on turn resigns. With no scatter every baton hits and a game never ends
(every toppled field kubb comes straight back), so the scatter is not zero. Its throws go
into the turn's debris like the match scene's.

`tools/compound.lua [--quick] [--games N] [--tilt deg]` asks whether one baton can take down
two or three kubbs: a deterministic sweep of core/swing batons (power 0.6 to 1.0, lofts 20
to 35) at pairs and triples side by side and pairs in line at 3, 7, 15 and 30 cm gaps across
a sweep of aim offsets, a domino check, and the spacing of standing field kubbs in physics
matches (about a minute; `--quick` about 10 s).

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
  `~/Developer/PlaydateSDK/Disk/Data/com.thingelstad.throwingwood/selftest/<name>.done`, and
  the Makefile copies it to `build/selftest/` and checks it and the PNG sizes.
- The Simulator (SDK 3.1.2) often segfaults as it quits, after the scenario has written its
  marker; now and then the crash leaves it hanging until the 60 s timeout. The Makefile
  counts a timed-out run by its `DONE` marker when there is one (and says so), so these
  are not failures; a run with no marker still is.
- The Simulator connects to a Playdate plugged in over USB when it starts. Self-tests do not
  touch the device, but do not unplug or reboot it.
- Screenshots for Jamie are the 2x frames. The 1x frames are for agent checks.
- Files in `source/selftest/` whose names start with `_` are helpers, not scenarios (the
  Makefile skips them). A scenario may set `ctx.note` to a one-line string; the runner
  appends it to the `DONE` marker (the throw scenarios put `avg_ms`/`max_ms` of
  update + draw there).
- Throw-scene scenarios use `tw.selftest.throwScenario{ script, shots, check, maxFrames }`
  from `source/selftest/_throw.lua`: `script` is an `input.scripted` step list, `shots` an
  ordered list of predicates `fn(scene, frame)` that each capture one frame when they first
  return true, `check(scene)` returns an error string or nil. `tw.selftest.windup(deg, n)`
  and `tw.selftest.flick{deg, ...}` build crank steps in forward degrees and apply the
  crank sign for you. Every scenario must also be imported from `main.lua`.
  `setup(scene)` runs once after the scene is made (`throw.setLayout`, `scene.surface`).
  For physics frames use `tw.selftest.sinceHit(s)` / `sinceContact(s)` (seconds on screen
  relative to the baton's first hit or touch, nil until the physics has found it),
  `restShot(n)` (n frames into the rest; the rest hold is 50 frames) and `item(s, id)`.
  A scenario that runs out of frames reports the scene's mode, playback frame and awake
  bodies in its `FAIL` line.
- `title`: the title with VS PLAYDATE chosen (frame 1), PRACTICE after two right presses
  (frame 2), and A must leave with `practice`.
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
  each surface),
  `autoreset`, and `bench` (the Bench screen; its note has the Simulator's figures, which
  are the Mac's, not the device's). They set loft and position in `setup`, not through the
  controls. Strong throws use loft 30 or less: at full speed and 35 degrees the baton
  lands past the far baseline. These throw scenes run with `loftBoost = false` (the speeds
  they were written for); `low-hard` turns it on: a baton at 5 degrees, faster than the
  swing's full speed, skids into field kubbs 6.5 m out, clear of the king.
- Match scenarios use `tw.selftest.matchScenario{ opts, step, maxFrames, refreshRate }`
  from `source/selftest/_match.lua`: `opts` are `scenes/match` options (`seed` for
  `core/autothrow` throws instead of the crank, `instant`, `skipHandoff`, `maxTurns`),
  `step(ms, ctx, h)` runs after each frame with `h.feed(steps)`, `h.pressA()` and
  `h.idle()` for scripted input. `tw.selftest.pitchMatchesEngine(ms)` checks every item on
  screen against the engine's state and the setup's debris; `tw.selftest.debrisShown(ms)`
  counts the debris kubbs and batons on screen. Scenarios: `match-opening` (crank throws: Team A's two
  opening batons, the hand-off card, Team B's first throw in its turned view),
  `match-toss` (a kubb toss played back and the automatic raising after it),
  `match-debris` (a downed kubb and a lying baton on the pitch for the next throw of the
  turn, that baton among them at rest, gone after the hand-off) and
  `cards` (a scripted match, seed 5: frame 1 the first hand-off with kubbs to throw in
  and a last turn to report, frame 2 the winner card, then A must ask for a rematch) and
  `match-whole` (a scripted match to a winner as fast as the Simulator goes, the d-pad
  walk up to the advantage line on the way; its marker names the game file, which the
  Makefile copies to `build/selftest/games/` and runs the notation gate over). The
  Simulator's floats differ from the desktop's, so the same seed plays a different match
  there than in `tools/physmatch.lua`: the checks do not depend on what happens.

## The release

Jamie and Tyler (2026-11-14, after play testing: hitting a base kubb was far too easy):
"you stop the crank where you release the baton". `core/swing`: the wind-up (back) sets
the power cap as before, the forward flick its speed; the baton is released where the
crank stops (the forward speed over `speedWindow` frames below `releaseStopDps`, 150 deg/s:
the crank all but halted, `how = "stopped"`), or at `releaseMaxDeg` past the bottom if it
never stops (`"over"`). (It was below half the flick's peak: on the device that fired while
Jamie's hand was still turning the crank at 300 deg/s, or well past the stop meant;
`telemetry/2026-11-14/traces.jsonl`.) The power is the flick's
peak (two-frame) speed. The crank is the throwing arm, and a hand swung on an arm leaves
at right angles to it, so the arm's angle past the bottom of the turn at the stop
(`result.releaseAngle`, forward degrees) sets the launch angle, forgivingly (Jamie,
2026-11-14: Jamie's first 13 swings left from -27 to 137 degrees against a 25 to 35 target, as
the crank moves 20 to 30 degrees a frame in a flick): `swing.releaseLoft(target, angle)` is
the loft set when the stop is within `releaseTolDeg` (10) of it, and beyond that the loft
set plus `releaseGain` (1/3) of the rest of the miss, within `releaseLoftMin`/`Max` (-30,
85). Stop early and the baton goes lower and shorter; late and it goes higher. The loft set by A + crank is the target: the dial marks it (`hud.gauge`'s `target`:
a white notch on the forward side, drawn like the full-power notch at the back and a
little longer, `notchIn`; Jamie: "a notch on the forward swing too ... this would be
perfect"), and the readout gives `loft <launch>/<set>`. Seeing what the crank did (Jamie, 2026-11-14:
"I'm not able to see the connection between the crank and what is happening"; no lesson):
after a baton throw the flag above the loft plaque (the drill's cut flag's place) says where
the crank stopped against the notch, `ON THE NOTCH`, `EARLY: LOW` or `LATE: HIGH`
(`swing.releaseMiss`, `throw.STOP_TEXT`, `s.stopText`), and on the next aim the dial keeps
a white dot where it stopped (`hud.gauge`'s `stop`, `s.stopAngle`) with the flag, until the
next wind-up. HOW TO THROW is a walkthrough run by the crank (Jamie, 2026-11-14: a static
card "is not useful ... make it an interactive thing that walks the player through the
different steps and meaning of the crank"; `core/howto`, pure and tested in
`test_howto.lua`, drawn by `render/howto`). The player's crank runs the game's own swing,
armed at the bottom of the turn as a throw is: a big dial that is the crank (both
notches, the wind-up arc, the last stop's dot), a power bar, and a side view of the throw
(the last one solid with where it landed, the full-power throw at the notch dashed, a
kubb 8 m out), with the step's words and a line on the last throw (`ON THE NOTCH`,
`EARLY: LOW`, `LATE: HIGH`, the angle it left at and its carry, or `TOO SLOW` after a
let-down). Steps: 1 wind back to the back notch (full power), 2 flick and stop on the
front notch until one throw is on it, 3 hold A and turn the crank to move the notch
(`notchMoveDeg`, 10), then A plays; B leaves at any step. A throw's launch is
`swing.releaseLoft` and its speed the loft boost's, as on the pitch. It covers the throw
scene (`throw.showHowTo`, `s.howto`: nothing else moves; closing it makes the scene's crank
arm afresh); the System Menu's Pitch, Drill and Match items have "how to", and it shows
once by itself the first time a player aims a baton (`throw.howtoFirst`, off in
self-tests, the autobench and the soak; remembered in the datastore "howto"). In a match
the match scene hands the frame to it before any phase (a hand-off or settle card, the
Playdate's think), and draws it, so everything waits under it (Codex on #81; self-test
`match-howto`). Self-test `howto` drives it with the crank (frames: each step, a throw on
the notch carrying 8.9 m, the notch moved); `release-stop` and `release-early` check the
verdict and show the dot (frame 4). The throw
scene launches the player's batons at that angle (the loft boost still goes by the loft
set), and drilled kubbs the same way (Jamie, 2026-11-14: "the player should only need to
learn how the crank works for throwing once"; "Drilling"); the computer's throws are
unchanged. Trace lines carry
`"release":"stop"`, `releaseAngle` and `launchLoft`; older lines replay with the old rule
(`passRelease`: released as the arm passed the bottom, at the loft set). The throw-scene
self-tests written before it keep the old rule (`throwScenario`'s `stopRelease = true` opts
in; `burst-reset` and `drawcalls` set `passRelease`); `release-stop` (stopped on the
target: 30 degrees, lands 8.4 m out) and `release-early` (20 short of the bottom, 50
short of the notch: about 17 degrees, lands 6.3 m out) test it.

## The aim arc

Jamie and Tyler (2026-11-14): "the player should visually see the arc of the baton throw
... like a game of billiards on a computer", and then (Jamie): "an actual arc ... from where
the baton would be released up into the air and then landing". While a player aims a baton
(not a drill, not the Playdate's throw), `throw.drawFrame` draws the arc over the world
(`drawArc`, outside its caches, no tables): where a clean throw at the loft set goes from
where the player stands and points (`flight.predict`'s arc with the loft boost,
`arcLaunch`), at full power: the farthest this aim reaches, the arc the camera is framed
for (it once shrank with the backswing while winding, and a short arc lands under the
view's lower edge, so it vanished: Codex on #74; the plaque's power fill shows the
wind-up); dashed (`arcPoints` 24, every other gap
drawn, the first `arcSkip` left out, `arcWidth` 2 px) with a small ring where it lands. It
shows the aim, not the throw: the flick and where the crank stops still decide it (and the
wind will not show in it).

From straight behind the thrower an arc is edge-on (a line), so the aim camera stands over
the shoulder (Jamie chose it, 2026-11-14): `camera.tune.aim.side` (1.0 m) to the right,
looking at the same ground point. `fitArc` (in `aimCamera`, every aim frame) keeps the
full-power arc under `arcTop` and inside `arcSide`, and where it lands above `arcBottom`
(230): a low hard throw first touches down about 4 m out, under the long lens's lower edge
(Codex on #74). The arc may rise in from the lower edge (at 5 degrees only its last few
points show); where it lands always shows. The camera first looks up (the principal row
lowered as far as `arcMaxCy`, 158: the kubbs keep their size, the pitch sits lower), then
widens its lens for what is still over (never wider than `arcMinF`). At the default 35
degrees the arc fits by looking up alone; at 55 the lens widens; at 5 it widens a little
(a far kubb 11 px against 12.5). Self-test `aim-arc`: mid wind-up, every loft from 5 to 55
from the middle and both ends of the line turned both ways, the ring wholly on screen and
the arc inside the margins (`throw.arcBox`). `arc = false` turns the arc
and the fit off (the crane still stands to the side). `drawcalls`: aim frames 61 calls
against 39 (the arc's lines; aim frames wait on the player, not the physics).

## Wind

Jamie and Tyler (2026-11-14): "optional in a game to turn on wind ... some indicator in the
game that would indicate where the wind is blowing, and wind would affect the baton throws
and kubb throws ... while they're in the air". The match options' WIND row (off, light,
strong; `opts.wind`, kept by the save, a resume and a rematch).

- **The air** (`core/wind`, pure, `test_wind.lua`): `wind.levels` light 2.5 and strong 6
  m/s. Each turn rolls a direction and a speed (`wind.turn`: the level's mean times
  `turnLow` to `turnHigh`); each throw is a gust of it (`wind.gust`: speed +-`gust`,
  direction +-`gustDeg`), so no two throws meet quite the same air. The match scene
  (`s.windLevel`, `s.windRng` from `opts.windSeed`, the seed or the clock) turns it into
  the thrower's view frame (`wind.vector`; Team B's is turned like the pitch) and hands it
  to the throw scene (`throw.setWind(s, wx, wy, text)`); practice has none.
- **The push** (`core/world`): `world.new{ windX, windY }`; `windForce` gives the thrown
  piece (`w.projectile`, until its first contact) its drag in the moving air less its
  drag in still air, `k (|r| r + |v| v)` with `r` = wind - v and `k` =
  `world.tune.windK` per kind (0.5 rho Cd A / m: baton 0.015, kubb 0.0086). With no wind it
  is nothing at all (still-air throws are bit-identical; the throws were tuned in still
  air). Applied right after gravity in both the full step and the lone flight, which stay
  identical with wind. Over an 8 m baton at 30 degrees: a light cross wind carries it 0.16
  m, a strong one 0.44, a strong head wind costs 0.97 m and a tail wind adds 0.54; a lobbed
  kubb half that. Cost: one call a step while the piece is in the air (two square roots),
  nothing without wind.
- **The indicator** (`hud.wind`): an arrow across the minimap's middle the way the wind
  blows in the thrower's view, longer the stronger, and `WIND n M/S` on a label above the
  minimap, while aiming and in flight. The aim arc does not show the wind: judging it is
  the player's.
- The Playdate's own throws do not allow for the wind yet. Self-test `match-wind` (a
  strong-wind match: the label, the speed, Team B's turn).

## Input provider

Scenes never read `playdate.buttonIsPressed`/`getCrankChange` directly; they read an input
provider (`source/input.lua`, `tw.input`): `p:advance()` once per frame, then
`p:held(name)`, `p:pressed(name)` (names `left right up down a b`), `p:crank()` (raw
degrees this frame, `getCrankChange` sign: negative = anti-clockwise), `p:crankPos()`
(`getCrankPosition`: 0 = up, 180 = the bottom of the turn), `p:docked()`,
`p:dt()`. `input.device()` wraps the hardware (dt measured, capped at 0.1 s);
`input.scripted(steps, dt)` plays a step list (`n`, `hold`, `press`, `crank`, `cranks`,
`docked`) at a fixed 1/50 s, with the crank starting at the bottom (or `startPos`).
The wind-up starts only when the crank crosses the bottom of the turn going back
(`swing.armAngle`, `swing.crossedBack`); the throw scene feeds the swing nothing before that.

## Tunables

Every number that is a guess lives in one table per module, with a comment:

- `tw.camera.tune` (`source/core/camera.lua`): aim crane, lens range, framing rule,
  impact camera, follow margins and mid-flight zoom; `tw.camera.minimap` for the minimap.
- `tw.swing.tune` (`source/core/swing.lua`): crank sign (`forwardSign`, the one constant
  to flip if forward feels backwards on hardware), wind-up and swing thresholds, full power
  speed and backswing, launch speed and tumble ranges, smoothness and tilt, and the release
  where the crank stops (`releaseStopDps`, `releaseMaxDeg`, `releaseTolDeg`, `releaseGain`,
  `releaseLoftMin`/`Max`; "The release"; `releaseDropFrac` is the old release's).
- `tw.flight.tune` (`source/core/flight.lua`): gravity, hand height, loft range (5 to 55) and step,
  `boostBelowDeg` (under it a baton is thrown harder, `flight.loftBoost`: full power carries
  as far as at that loft; the throw scene's own batons only, not the computer's),
  baton size, wobble.
- `tw.scenes.throw.tune` (`source/scenes/throw.lua`): refresh rate, walk speed, how far
  back the player may step, swivel and loft gearing, double-tap time, rest hold, practice
  surface, the flight's pacing (`flightRate`, `framePeriod`, `tailPeriod`, `minBudget`;
  `physicsBudget` only for scripted input; see "Playback") and how far ahead the physics
  may record, impact-camera
  slew and baton framing radius, the tossed kubb's tumble (`tossTumble`), the instant
  rest hold, and for drilling the drilled kubbs kept on the practice pitch (`drillKeep`)
  and the marker ring (`markerRadius`, `markerSegments`).
- `tw.drill.tune` (`source/core/drill.lua`): every drilling mapping (AGENTS.md
  "Drilling"). `tw.camera.tune.drill`: the fixed drill aim camera.
- `tw.outcome.tune` (`source/core/outcome.lua`): when a body counts as standing, moved or
  turned, and how high a tossed kubb must rest to be on another.
- `tw.autothrow.tune` (`source/core/autothrow.lua`): the scripted thrower's loft, aim and
  scatter.
- `tw.world.tune` (`source/core/world.lua`): step, solver passes, slop and push, contact
  margin, bounce threshold and passes, wood-on-wood friction and bounce, sleep and wake
  thresholds, topple angle, out margin, maximum throw time, stake height (0.15 m: a real stake, 6 inches out of the ground).
  `tw.world.surfaces`: one parameter set per ground (grass, sand, snow; ice is a marked
  placeholder): friction, bounce, dig, rolling resistance, and the ground's `texture`
  (Physics, "The ground's texture"). `world.SURFACES` lists the playable ones in order.
- `tw.bench` (`source/core/bench.lua`): the benchmark scenario (pieces, throw, seconds,
  and `bench.debris`, the lying batons and kubbs of a full turn).
- `tw.debris.tune` (`source/core/debris.lua`): `matchEps`, how close the engine's pose of a
  lying tossed kubb must stay to the one recorded at rest for that exact pose to be used.
- `tw.render.world.tune` and `tw.render.hud.tune`: shadow direction (also the light that
  shades the faces), the tones (`awayBelow`; a piece is never grey and keeps its look
  standing, falling or lying, with outline and detail sized by its length at its
  distance), outline and grain sizes, the ground (`lineWidth`, `dash`/`dashGap`,
  `advDash`, `roughPattern`, `rough`, `outsideFrom`, `roughFar`), stakes (`stakeHeight`,
  `stakeThick` at their true size, `stakeMinPx` the thinnest; no shadow), the baton's
  bands, the king's drawing (`kingCrown`, `kingCollar`, `kingCollarTop`, `kingRing`,
  `kingDiamond`, `kingDetailFrom`: drawing only, the physics king stays a plain box; the
  `king` scenario shows it), the kubb set (`set`, `setFrom`, `setDetailFrom`; the
  sets themselves are `render.world.sets`, see "Kubb sets"), HUD fonts (`labelFont`, `displayFont`) and every HUD box
  (`rail`, `prompt`, `gauge`, `plaque`, `chip`, `flag`, `slow`, `callout`, ...), and `cache` in each (the
  image caches of "Drawing speed"; `false` draws everything from scratch every frame, with
  the same pixels), and `layer` in `render.world.tune` (the background layer of "Drawing
  speed").
- `tw.render.burst.tune` (`source/render/burst.lua`): the hit bursts' phase lengths, the
  double's second star, the anchor lift, the chips; `tw.burstpick.tune` the double's window and the fall judged at the impact (`fallV`, `fallW`, `judgeFor`, `grazeFor`);
  `tw.sound.tune` (`source/sound.lua`) the knocks' volume and rate spread and the king's
  chord ("Knocks"); `throw.tune.knockLate`.
- `tw.playback.paceTune`, `tw.playback.calm`, `tw.playback.slow` (`source/core/playback.lua`):
  the pace of the picture, the calm tail and the slow motion ("Playback", "Slow motion").
- `tw.scenes.title.tune`, `tw.render.cards.tune`, `tw.render.ui.tune`: where the title's
  menu, the cards' lines, pips and pitch map, and the ringed buttons sit (screen pixels
  from the design boards), and the system paths tried for the label font.
- `tw.raising.tune` (`source/core/raising.lua`): the search that slides an obstructed
  footprint clear, and the punishment candidate grid. Stake radius and other piece sizes are
  in `tw.pitch`.

## Physics

DESIGN.md section 5. Pure Lua in `source/core/`: `quat`, `body`, `collide`, `world`,
`playback`, `bench`.

- Units are meters, kilograms, seconds, radians. World axes: x across the pitch, y from
  Team A's baseline (y = 0) to Team B's (y = 8), z up; the ground is z = 0.
- A body is one flat table of numbers (`core/body.lua`): position, velocity, quaternion,
  world angular velocity, its rotation matrix `r11..r33` (column 3 is the local z axis, the
  long axis of every piece) and world inverse inertia. Kinds: `kubb` and `king` (boxes),
  `baton` (capsule, solid-cylinder inertia), `stake` (a static capsule post: infinite
  mass, never wakes or moves). Sizes are DESIGN 2, not tunables.
- `world.new{ surface, pieces, stakes }` adds the six stakes (`stake1..6`, `core/pitch`
  order, unless `stakes = false`) and then the pieces (`{id, kind, x, y, yaw}` standing, or
  a full pose `qw..qz`, `z`, `toppled` for a piece already down). `world.launchBaton(w, x,
  lineY, swivel, loftDeg, speed, tumbleRate, tiltDeg)` takes the stage 1 swing outputs
  (tilt is a real tilted spin axis); `world.launch` throws any body, a kubb included;
  `world.launchKubb(w, id, x, lineY, swivel, loftDeg, speed, tumbleRate)` lobs kubb `id`
  like a clean baton (upright in the hand, end over end, no tilt).
  `world.step` advances one fixed step (1/240 s), `world.run`, `world.isAtRest`,
  `world.result` (touched, stakesTouched, toppled, kingToppled, outNotToppled, rest poses,
  firstContact, firstHit).
- Toppled means the long axis came within `toppleDeg` of horizontal. There is no tipping
  state machine: tipping, rocking back and falling come out of the contacts.
- The leaner rule (Jamie, 2026-11-13): a kubb or king that comes to rest propped on another
  piece is down if it would fall with the prop taken away. `body.wouldFall` is the test: the
  plumb line through the centre misses the end face it stands on (a kubb past about 25
  degrees from upright, the king past about 17). `world.step` applies it when a box goes to
  sleep, never while it is still rocking; `world.result` applies it to anything still moving
  when the throw ran out of time; `world.add` applies it to a piece placed already leaning.
- `core/playback`: compute ahead and play back. Poses are recorded every 1/50 s of
  simulated time (per body, only from the first frame it moved); the screen shows any time
  between two records (`playback.poseAt` interpolates) at the pace of "Playback" below.
- The pure core rule applies: no `playdate.*` in these files; the clock is passed in
  (`os.clock` on the desktop, `playdate.getElapsedTime` on the device).
- Tests: `tests/lua/test_quat.lua`, `tests/lua/test_physics.lua` (rest and sleep, energy,
  tipping thresholds against the analytic values, dominoes, baton hits and misses,
  surfaces, stakes, determinism, playback). Outcomes are tested with tolerances.
- Benchmark: `make bench` on the desktop; on the device the System Menu "Pitch" item, set to
  "bench", runs the identical `core/bench` scenario a chunk of steps per frame, then times
  30 draws of the throw scene, shows ms per step, steps per 20 ms frame (overall and in
  the collision phase), total time and draw ms per frame, and appends one line to
  `bench.txt` in the Data folder. Real time needs 4.8 steps per 20 ms frame.
- Speed. The device is about 500 times slower than a Mac on this code, and not evenly:
  a Lua function call costs about 9 us there, a C call (`math.sqrt`) about 4 us, a new
  table about 54 us and a closure about 35 us, and reading fields from many different
  tables in turn costs several times reading one table (cache misses). So the hot paths of
  `core/world` and `core/collide` are written out in full: no helper calls per pair,
  contact or solver pass, comparisons instead of `math.abs/min/max`, one record table per
  solver contact read with `<const>` indices, ground contacts and contacts with a sleeping
  or static body specialized, and the pair loop jumps over runs of sleeping bodies. The
  arithmetic is term for term the plain version's, so results did not change: a change to
  these files should keep a dump of every body after a fixed scenario bit-identical on the
  desktop, or say why not.
- Lone flight (`world.loneFlight`, on): when exactly one body is awake and it cannot reach
  the ground or any other body within this step (its height above the ground, and above the
  top of every other body, beats its speed plus a step of gravity and its spin, with a
  millimetre to spare), `world.step` runs only that body's share of the full step: the
  same arithmetic in the same order, no pair or ground search. The baton in the air is most
  of a throw's steps (561 of the match case's 1107 on the desktop); those steps cost a fifth
  of a full step there (0.0016 against 0.0078 ms). `tests/lua/test_loneflight.lua` checks
  every body every 10 steps of the match case's throws is identical with it off and on, and
  a dump of every body after every step of the default bench and 12 games was identical.
  `w.loneStep == w.steps` marks a lone step for the benches.
- `world.prof`: set it to `world.newProf(clock)` and `world.step` adds the seconds of each
  phase (`world.PHASES`) into it; nil costs one test per phase.
- The ground's texture (Jamie, 2026-11-14: "in a real game of Kubb there is always random
  stuff because of the surface"). Every surface a game can be played on carries a
  `texture` (`world.SURFACES`: grass, sand, snow). The ground stays a flat plane; what a
  flat plane leaves out is put back where it is cheap:
  - **Patches.** The ground is cut into `cell` (0.25 m) patches, each with five numbers in
    -1..1 from an integer hash of the patch and the throw's seed. They are read only when
    a ground contact is new (no tables, no calls): the patch's friction, bounce and dig
    vary by `muVar`, `eVar`, `digVar` (kept per contact in `b.gMf`, `b.gEf`), and a steep
    landing faster than `bumpSpeed` is turned sideways by up to `bump` times its approach
    speed times the steepness squared (its travel only; at the contact point it gave an
    edge landing a wild spin), so a low skidding drill is barely turned and a baton
    dropping end first is.
  - **Grass holds.** A baton or a lying piece touching the ground loses `drag` of its ground
    speed and spin a second, and `grip` more below `gripSpeed`, so it stops instead of
    creeping. Standing or falling kubbs are left alone (a falling kubb must still fall).
  - **Snow ploughs** (`plough`, 1/s per m): the drag grows with the distance a piece has
    slid since it last left the ground (`b.plough`, reset off the ground, in the lone
    flight too), so a slide on snow starts slick and ends heavy.
  - **The surfaces.** Grass: high friction, moderate dig, holds. Sand (DESIGN 5): very high
    dig, almost no bounce or slide, soft and packed spots, ridges that turn a landing more,
    drags and grabs hard. Snow (Jamie, 2026-11-14): slick (`mu` 0.25) but soft: a steep
    landing plugs, almost no bounce, icy and soft patches, and it ploughs. Over 400 scripted
    batons (`tools/groundstats.lua --surface`): the slide after touching down is 1.39 m on
    grass, 0.46 on sand, 1.85 on snow; a kubb toppled in 11.5%, 6.0% and 11.8% of throws.
    Physics matches (20 each, seed 7, `tools/physmatch.lua --surface`): 21.1, 29.6 and
    21.6 turns; on sand a baton has to land on its kubb.
  - **Nothing slides on an end.** A baton within 30 degrees of upright, touching the
    ground and sliding faster than `tripSpeed`, is tipped toward the way it is going
    (`trip` rad/s^2 per m/s): its foot catches.
  - **The seed** is the throw's own (`world.seedFrom` of the launch position and
    velocities, set in `world.launch`): the same throw meets the same ground (replays,
    tests, the autobench), every other throw its own. `world.new{ groundSeed = n }` fixes
    it; `world.new{ texture = false }` is the plain surface (the mechanics tests in
    `test_physics.lua` use it, and `tools/groundstats.lua --flat`).
  - **Measured** (`lua5.4 tools/groundstats.lua [--n --seed --surface --flat]`: 400 scripted
    batons at the base kubbs): on grass a baton slid on an end 0.050 s a throw before, 0.008
    with the texture; slid 2.1 m after touching down, 1.4; came to rest in 2.12 s of
    simulated time, 1.85; toppled a kubb in 12.5% of throws, 11.5. A drill still rests
    within 0.27 m of its marker, and the cuts part by 17 cm on average, A right of B on 59
    grounds of 60 (`test_drill.lua`). Physics matches run longer (23.9 turns against 19.9
    over 40, seed 7): the scripted thrower aims a little short and counted on the skid,
    which is what a real player has to unlearn from surface to surface.
  - On the device (`telemetry/2026-11-14/bench/run6`, against flat grass in the same run):
    the three match-case throws 10.61 s against 10.69 (0.43 of real time both), a physics
    step 3.88 against 3.84 ms. The autobench has a flat-grass variant.
  - The 32-bit device Lua: the patch is `math.floor` (a true integer); `//` leaves a float
    that `&` and `>>` refuse there (the desktop's 64-bit Lua takes it, so only the
    Simulator self-tests catch it). Tests: `test_ground.lua`.
  - This changed every throw on grass on purpose, so dumps after a scenario are not
    identical to before; the lone flight is untouched (no ground in the air).
- Tried and rejected (2026-11-13): `dt` 1/120 halves the steps but fails three behaviour
  tests and the bigger contact margin gives ghost hits; 3 solver iterations instead of 4
  would save about 8% of a collision step but changes the feel, so it was not applied.

## Playback

What a throw looks like on the device is set by three costs per frame: the physics (on
the device a step with nothing in contact costs about 1.9 ms, a step with kubbs in contact
about 29, and the three match-case throws averaged 4.6 to 7.2 ms a step; real time needs 4.8
steps per 20 ms), the draw (about 18 ms in flight, 11 after the hit) and the rest of the
update (device run of 2026-11-13). The device cannot compute a
throw in real time, so the picture always plays slower than real time; the goal is that it
does so steadily. `source/scenes/throw.lua` and `source/core/playback.lua`:

- In flight the display is unlocked (`flightRate` 0) and every frame takes `framePeriod`
  (0.040 s): the physics gets what is left after the update's own work, the draw and the
  display (each measured from the frames before, `drawEst` and `postEst`), at least
  `minBudget`. The estimates rise by `estRise` (a quarter) of a step up and fall by a
  quarter of a step down; jumping straight to the slowest frame left the physics 1.7 ms a
  frame short of what the draw really took (0.38 against 0.45 of real time). Locked at 50 Hz, a frame that ran past 20 ms waited for the next 20 ms tick,
  so frames came at 40 or 60 ms by chance.
- `playback.advance` stops before a step that would run more than half a step past its
  budget (judged by the last step's time), not after.
- The pace (`playback.pace`, `paceTune`): the picture plays at real time while 0.4 s
  (`horizon`) or more is computed ahead of it, slower in proportion below that (never under
  `floor`), changing by at most `rise` per second up and `fall` down. So the picture slows
  smoothly to the rate the physics makes frames, instead of running to the end of what is
  computed and stopping. `playback.speed` (the slow motion) is applied on top: the slower of
  the two wins.
- The calm tail (`playback.calm`): once every awake body moves slower than 0.05 m/s and
  0.5 rad/s, nothing visibly moves and the throw only waits for the sleep timer. The scene
  holds the picture and the camera's aim there, gives the physics `tailPeriod` per frame,
  and when the world is at rest it jumps to the end. Starved frames in the tail are not
  counted.
- Self-tests and the desktop use scripted input, which has no device clock: they get
  `physicsBudget` per frame, as before.


## Measuring on the device

The autobench measures a build on the Playdate with nobody pressing anything:

1. Build and install `build/ThrowingWood.pdx` (data disk mode, copy to `/Games`).
2. Create an empty file named `autobench` in the game's Data folder
   (`/Data/com.thingelstad.throwingwood/`), eject, and launch the game
   (`pdutil <port> run /Games/ThrowingWood.pdx`).
3. At launch the game deletes the flag, runs `source/autobench.lua` (about two minutes)
   and appends to `bench.txt` in the Data folder: the micro benchmarks, the `core/bench`
   physics line (also with the collector stopped, and with a full turn's debris asleep on
   the pitch) and its per-phase profile, the draw
   timings of the throw scene by frame type (aim with the camera still, swivelling,
   walking, then a full throw split into wind-up, flight, impact and rest, with
   `render/world` and HUD part timings), a few drawing primitives, memory and
   `playdate.getStats`, then the match case: three scripted match throws (a hit, a miss and
   a drill) played through the throw scene exactly as in a match, each with its
   `frames.jsonl` line, release to rest in seconds, mean and spread of the frame time,
   frames held in the calm tail, the lowest pace and how frames were drawn (cached, from the
   layer, layer built, full). The match case runs with the defaults and with variants
   (`auto.matchCase(y, label, tune)` overrides `throw.tune`, `render.world.tune` and
   `paceTune` and restores them), then `bench.matchPhysics` with lone flight off and on.
   One run is profiled (`auto.matchCase(y, label, nil, true)`): for every flight frame the
   draw's mean and max split into `render/world` (by its own laps) and the HUD, the display
   time, and the scene's estimate of the two (what the physics loses each frame). The
   other variants switch one part of the look off, so each part's cost reads as shown
   speed. The last line is `autobench done`; then the game carries on. Auto-lock is off
   while the bench runs.
4. Mount the data disk again and read `bench.txt`. Delete it when done with it; never
   touch `traces.jsonl` (crank recordings), `frames.jsonl` or `games/`.

The soak (`source/soak.lua`) is QA, not a benchmark: an empty file named `soak` in the same
Data folder runs `soak.tune.matches` (3) whole scripted matches once at launch (after any
autobench; each with the next kubb set of `soak.tune.sets`: classic, USA, Wisconsin), at a player's real pace through `scenes/match` (playback, slow motion, camera,
bursts, raising and punishment by the engine's policies), bounded at `maxTurns` (24). It
saves the match before every throw under its own key (`soak-match`, match option `saveKey`)
and every `saveCheck` throws reads it back and unpacks it against the live engine; it
writes no game file (option `noFile`) and turns the recorder and frame log off, so
`games/`, `traces.jsonl` and `frames.jsonl` are untouched. Each frame runs under `xpcall`:
an error ends that match with its traceback. `soak.txt` gets per match the turns, throws
and ending, frames over 100 and 200 ms, the slowest frames with the phase and throw mode,
memory after a full collection before and after and the most seen, and the save checks;
then a summary and `soak done` (about 10 minutes a match). Each slow frame listed says
where its time went: the update (of it the physics and its steps), the draw, the bodies
awake and how much the heap grew that frame (`mem`, net of anything the collector freed;
the `gc` figures in `telemetry/2026-11-14/soak/run2` and `run3` are the same number). Self-test `soak` (one short
match).

For hours of testing over USB (benches and installs with nobody at the device), put an
empty file named `nolock` in the same Data folder: while it is there the game never
auto-locks (`main.lua` reads it once at launch). Delete it when the testing is done.

## Drawing speed

On the device a graphics call costs 20 to 50 us (a small `fillPolygon` 41 us,
`drawPolygon` 50 us, `drawLine` 46 us, `setPattern` 33 us), `drawText` about 0.6 ms
and copying a full-screen image about 0.7 ms. So:

- `render/world` keeps the last frame as an image and copies it when a frame shows
  exactly what the last one did. The key is the camera, the item list and its length,
  the pose version, the baton and `render.world.advantageY` (the match's advantage line).
- Each item keeps what depends only on its pose (world corners, the shadow outline, face
  normals and shades). Change a pose only through `render.world.setPose`: it marks the item
  stale and bumps `render.world.poseVersion()`, which is what invalidates the caches. A lying
  baton is an item too (`baton = true`, its axis from the pose): drawn from the cached pose
  each frame like the flying baton, with nothing prepared. After
  changing `render.world.tune` or anything else the caches cannot see, call
  `render.world.invalidate()`: it drops the frame image and every item's prepared shadow
  and shading.
- The layer (`tune.layer`): while the camera holds (it holds after the impact camera has
  settled, and in the calm tail) and some pieces move, the pitch and the pieces that did not
  move in the previous frame are drawn once into a background image; each frame is that
  image, then the moving pieces (and the baton) and any still piece whose screen box
  overlaps them, closed over overlaps, redrawn in the same depth order as a full draw. It
  is dropped when the camera, the item list or a background piece changes. `setPose` with an
  unchanged pose changes nothing. The `layer` self-test draws every layered frame of the hit
  throw a second time from scratch (`render.world.verify`) and needs at least 50 of them
  with no pixel different (66, 0 on the Simulator since the shorter slow motion; 112
  before).
- The device autobench turns the crank recorder and the frame-time log off while it runs
  and restores them after, so its scripted throws never reach `traces.jsonl` or
  `frames.jsonl`.
- `render/hud` draws the minimap and the gauge disc as layers: to the screen while their
  inputs change, into an image (on the 8 px grid, through `gfx.setDrawOffset`) once a
  frame repeats the last frame's inputs, then copied until an input changes. The minimap
  layer keys on the pose version and the advantage line; the aim line, player, landing mark
  and baton dot are drawn on top every frame. The other parts (rail, prompt, loft plaque,
  cut flag, power chip, result flag, callout, readout) are plates: one image each, redrawn
  only when their own key changes, so a frame that changes nothing costs one image draw per
  part. The plaque's power fill is the one thing drawn per frame (one `fillRect`), so
  winding never redraws text. The title (one image per highlighted choice) and the
  match's hand-off and winner cards (`render/cards`, built once per card and kept in
  `s.card`) are each one cached 400 x 240 image, copied every frame: no text is drawn
  while they wait.
- The ground (`render/world`): the rough is a `setPattern` fill whose 8 x 8 phase follows
  the projected middle of the far baseline (64 shifted patterns made once), so it travels
  with the pitch rather than sliding under a screen-fixed pattern. It is drawn as two fills
  that stay on the screen: everything below the projected far edge (`roughFar`), then the
  pitch's footprint white. The far edge is `roughFar` out along the camera's own heading,
  so the two fills hold whichever way it looks (the half circle looks back down the
  pitch). Each surface has its own rough (`roughBySurface`: grass short dashes, sand a
  denser stipple, snow a sparse sprinkle on white); `render.world.setSurface(name)` swaps
  it and drops the caches only when it changes (the throw scene calls it at prepare and
  launch). The three ground quads 120 m wide it replaced cost 2.8 ms a
  flight frame on the device, the two fills about 1.3. All of it is inside the frame cache
  and the layer. There are no grass tufts (about 2 ms a flight frame) and no speed lines
  (both dropped 2026-11-13, speed over niceties).
- The `drawcalls` self-test counts graphics calls per frame by kind (aim, flight, impact,
  rest). Before the Woodcut look: 45/126/99/16 mean; with it: 41/150/110/17; after the
  speed fix (no tufts, no speed lines): 39/134/111/17; with the camera's half circle
  (2026-11-14): 39/134/160/20, the impact frames full draws while the camera turns (paid
  for by `swingPeriod`, measured on the device). Keep flight and impact within about 30 of
  those.
- A new part of the HUD that depends on something must put it in its layer's key, or the
  layer will show a stale image. `make selftest` frames compared pixel for pixel before
  and after (`cache = false` against `true`) catch this.

## Practice drills

PRACTICE on the title opens the drills menu (`scenes/drills.lua`, board `Drills.png`; pure
set-ups, scoring and records in `core/drills.lua`, tested). On the left OPEN PITCH (the
practice pitch below, `main.lua` "pitch") and the drills; on the right the chosen drill's
pitch from above, three lines on what it is, its best, its last ten runs as bars and its
hit rate (records in `playdate.datastore` "drills").

- 8 METERS: six batons at the five base kubbs from the baseline (a point a kubb down; the
  run ends when all five are down). THE HOUSE: six batons at five field kubbs standing
  close at 4.3 m. KING SHOTS: six batons at the king alone (a point each time it falls; it
  is stood back up). BLAST: six kubbs drilled to the marker (a point for resting within
  `blastCm`, 50 cm) to a marker fixed at `blastMarkerY` (6 m, as the menu map draws it:
  the setup's `markerY`, `throw` keeps it still, `s.markerFixed`), so bests compare.
  AROUND THE PITCH: five batons, each from in front of the next base kubb. An illegal
  throw (a helicopter) scores nothing.
- A run goes through the throw scene one throw at a time, like the match
  (`drills.setup` -> `throw.prepare`, `s.auto = false`; `drills.tally` on the throw's
  `result.toppled` and `last.restCm` once it is `done`); the rail counts throws and the
  score. A card gives the score and any new best; A runs it again, B goes back to the menu.
  During a run the System Menu's third item is "Drill": menu (`drills.quit`: leave the run
  part way, nothing recorded) or title. Readout reaches the run's throw scene as in
  practice (`main.lua` `throwScene`).
- In drill mode (BLAST, and a match's kubb tosses) the rail shows the marker's distance
  and beside it what the caller gave (`throw.setRail`'s first right-hand text: a drill's
  score).
- Self-tests `drills` (the menu, a whole KING SHOTS run with straight scripted batons, the
  result card and the record it leaves, then a second run quit part way) and `drills-blast` (BLAST's rail keeps its score).

## Throw scene practice

The practice pitch's surface is the System Menu "Pitch" item's grass, sand or snow
(`throw.setSurface`). A match's surface is the engine's (`g.surface`, written to the game
file's `[Surface]` header): `match.setup` passes it on as `setup.surface` (core/world's
name, `match.surfaceName`) and `throw.prepare` takes it, so the physics and the look follow
the match. The games list's rail shows the chosen game's surface.

Toppled kubbs stay down between throws at their rest poses (the scene's item list, the
render items of `render/world`, carries every piece's pose). System Menu "Pitch" set to
"reset" stands everything back up (`throw.reset`); it also happens by itself after the
throw that leaves every far base kubb down. The System Menu holds three custom items at
most (Readout, Record, Pitch), so Pitch is an options item that acts when the menu closes
and then reads "play" again; its "title" goes back to the title screen. Its "drill" turns
the pitch to drilling kubbs (next section) and "batons" back; chosen mid-throw, the switch
waits until the scene aims again. "reset" also clears the drilled kubbs.

## Drilling

DESIGN.md section 4 "Kubbs (drilling)". The pure part is `source/core/drill.lua`
(`tw.drill`); the body is `world.launchDrill` next to `world.launchKubb`; the scene part is
the throw scene with `s.drill` on.

- **Where it shows up.** The match's kubb throws (`throw.prepare` turns `s.drill` on for a
  `projectile == "kubb"` setup; the marker stays where that team left it). The computer
  thrower (`throw.autoLaunch`, `s.scripted`) still lobs with `launchKubb`, as do
  `core/autothrow` and `tools/physmatch.lua`. The practice pitch drills after "Pitch: drill"
  (`throw.setDrill`): each drilled kubb gets its own id (`d1`, `d2`, ...) and becomes a piece
  of the pitch at rest (`keepDrilled`, the newest `drillKeep`), so later throws hit it; the
  auto stand-up after all far base kubbs are down is skipped while drilling.
- **Aim.** The d-pad moves `s.markerX, s.markerY` (view frame), clamped by
  `drill.clampMarker`, faster the longer it is held. `drill.solve` puts the thrower on the
  baseline straight behind it (x clamped to `throwerXMax`) and solves the clean launch: loft by
  distance, the speed that lands the kubb's edge `slideAllow` short of the marker
  (`flight.tune.handHeight` down to `landZ`), the band center (power) for that distance and
  the flight time. A or B held sets `s.cut` (`drill.CUT_A` = 1 curls right, `CUT_B` = -1
  curls left), read every frame up to the release; in drill mode A and B never swivel or
  loft and do not stop a wind-up. The aim camera is `camera.drillAim`, which steps sideways
  with the thrower so the player lines up behind the marker (the world frame is redrawn
  while it moves, as in a baton walk); the marker ring, cross and dotted line are drawn over it each frame
  in `throw.draw` (`drawMarker`), and the minimap's aim line goes to the marker.
- **Swing to launch** (`drill.launch`): the power error against the band is shrunk by
  `inBandGain` inside `bandHalf`, then scales the solved speed by `speedPerPower` per unit
  (never under `speedMinFrac`). The angle is a baton's (Jamie, 2026-11-14: one throw to
  learn, the band kept): the solved loft is the dial's notch, and where the crank stops
  against it sets the launch angle by the same forgiving rule (`swing.releaseLoft`: within
  10 degrees the solved loft, beyond it a third of the rest of the miss), with the same
  flag (`ON THE NOTCH`, `EARLY: LOW`, `LATE: HIGH`) and dot; a swing under the old release
  keeps the solved loft. Early (for the push and wobble below) is a stop before the
  notch. Smoothness under `cleanAbove` gives a nose-over wobble of up
  to `wobbleRate` rad/s (its sign follows the swing's `how`). Tilt pushes the swivel by
  `tiltPushDeg` per degree (right, left when early). The cut is
  `cutSpin` rad/s about the long axis.
- **The body** (`world.drillLaunchState`): long axis along the horizontal line of flight, the
  nose `noseDownDeg` below the horizontal, spinning at the cut rate; the release roll is
  solved backwards from the flight time so it lands rolled `rollLandDeg` onto a long edge
  (without that the cut's direction flipped with the landing phase). `b.digGain`
  (`body.digGain`, 1 for every other body) multiplies the ground's dig on its new ground
  contacts: with 1 a clean low drill skids 1 to 4 m; `digGain = 3` makes it die near where
  it lands. Nothing else in the solver changed; the bench is the same within noise.
- **Measured on grass** (desktop, `tests/lua/test_drill.lua` asserts the bounds): a clean
  in-band drill first lands about 0.07 m from the marker and rests 0.10 m off on average
  (0.27 m worst over 15 markers, near to far); the band's edges rest within about 0.3 m
  (0.47 m worst far out); 0.2 under the band lands 1.0 to 2.3 m short, 0.15 over lands 0.65
  to 1.65 m long. The cut moves the rest point 5 to 17 cm (10 cm mean), the same both ways.
  A clean drill slides 0.13 m after landing on average (0.35 m worst); a jerky one
  (smoothness 0.35) 2.1 m (0.1 to 5 m). On sand: cut 7 cm mean, slides 0.05 and 0.8 m.
- **HUD.** `hud.plaque` marks the band beside the power fill; `hud.gauge` draws the band
  as a wedge on the disc and its prompt says `WIND TO BAND`, `FLICK!` (inverted) or
  `EASE OFF` while winding; the cut flag says `CUT RIGHT` or `CUT LEFT` while A or B is
  held. After the throw `hud.callout` gives the verdict (`SHORT`, `ON`, `LONG`) in a black
  block and a ruler from SHORT to LONG with the rest point's distance from the marker (cm
  under 1 m). The `hud-drill` scenario shows the band prompts and a long callout.
  `hud.drillReadoutText`: `P <power>/<band> <verdict>  S <smoothness>  cut R|L|-  off
  <land>/<rest> m` (distances from the marker).
- **Telemetry.** A drill's `traces.jsonl` line is a baton line plus `"mode":"drill"`, `band`,
  `verdict`, `cut`, `markerX/Y`, `landX/Y` (first contact), `restX/Y` and `throwerX`, in
  meters with y from the thrower's baseline (`core/trace.lua` header); `launchSpeed` is the
  drill's own. `frames.jsonl` writes `"proj":"drill"`.
- **Rules.** A drilled kubb's rest goes through `core/outcome.toss` and `core/match` like a
  lobbed one: short of the middle line or out when its round is judged is a rethrow, out
  twice a punishment kubb (tested in `test_drill.lua` with real physics).
- **Self-test** `drill`: the practice pitch, marker moved, A held, a wind-up to the band and
  a clean flick; its marker note gives power, band and the landing and rest distances (the
  old release). `drill-stop`: the release where the crank stops, wound into the band and
  stopped on the drill's notch: ON THE NOTCH, the solved loft, rests 0.19 m from the
  marker.

## Woodcut type, title, cards and launcher

The look is `docs/design/` (README and boards). What is built of it here:

- **Display font**: Throwing Wood Display (`source/fonts/ThrowingWoodDisplay-16` and `-32`,
  cap height 16 and 32 px): capitals, digits and `! . · % ° + - : , / ' ?`. It is a 1-bit
  rendering of Londrina Solid Black, licensed under the SIL Open Font License 1.1, which
  reserves the name "Londrina Solid", so the rendering has its own name. The licence and
  attribution ship in `source/fonts/OFL.txt` (copied into the pdx); the original TTF and
  licence are in `tools/art/`. At 16 px M, N, W and 8 are cut by hand (`OVERRIDES` in
  `tools/art/build.py`).
- **Labels**: Roobert 10 Bold in capitals, loaded at run time from the system
  (`render.ui.tune.labelPaths`); the system font if that fails. The SDK's font files are not
  copied into the repo. Roobert has no `·`, so `ui.textDots` draws middle dots as 2 x 2
  squares.
- `render/ui.lua` (`tw.render.ui`): the fonts, `ui.text`, `ui.textDots` and `ui.button` (a
  filled disc with A or B and one word). Draw them into a cached image.
- **Title** (`scenes/title.lua`, `boards/Title.png`): `images/title` (the wordmark, band and
  THROWING WOOD, one pre-drawn image) with a menu of what works today (VS PLAYDATE, PASS +
  PLAY, PRACTICE; d-pad either way) and A START. The System Menu is as before.
- **Cards**: `core/cards.lua` (pure, `test_cards.lua`) works out what the hand-off and winner
  cards say from the engine and its score sheet: who throws, what the other team's batons
  took last turn (field and base), kubbs to throw in and batons, base kubbs standing, the
  pitch for the map in the receiving team's view, and for the winner the turns, minutes
  (start to finish by the clock: under a minute in the scripted self-tests) and the winner's
  baton hit rate. `render/cards.lua` draws them (`images/winner` is the burst behind the
  winner). Nothing is shown that the game does not know.
- **Launcher** (`source/launcher/`, `imagePath=launcher` in `pdxinfo`): `card.png` 350 x 155,
  `card-highlighted/1..4.png` with `animation.txt` (the last B tips 0, 5.3, 10.7, 16 degrees),
  `icon.png` 32 x 32 (the king) and `launchImage.png` 400 x 240 (the title without its menu,
  the same picture as `images/title`, so the start has no jump).
- **Regenerating**: `python3 tools/art/build.py` renders every one of these images and both
  fonts with headless Google Chrome (the SVG from the design boards, thresholded to pure
  black and white) and Python's standard library; `--preview DIR` also writes 4x previews of
  the font tables. Commit what it writes.

## Match

The title (`scenes/title.lua`, Woodcut look below) offers "VS PLAYDATE" (a match against
the computer), "PASS + PLAY" (the match) and "PRACTICE" (the drills menu, whose OPEN PITCH
is the practice pitch); `main.lua` opens one
scene at a time and rebuilds the System Menu for it (Readout, Record, then the scene's
own item). Practice is the throw scene exactly as before.

- `core/frame.lua`: the thrower's view frame. Team B's throws are made in the pitch turned
  180 degrees about its center, `(x, y) -> (-x, 8 - y)`, angles + pi, quaternions
  `(0,0,0,1) * q`; the turn is its own inverse. So the throw scene, cameras, flight, HUD
  and physics always throw from y = 0 toward +y, and Team B sees its own baseline at the
  bottom of the screen.
- `core/outcome.lua`: physics to rules. `outcome.pieces(g, side)` gives the engine's pitch
  as `core/world` pieces in the view frame (with `role`, `half` and the world `pose`);
  `outcome.baton(res, pieces, side, illegal)` and `outcome.toss(res, pieces, side, id)`
  turn a `world.result` into the outcome records above (rest poses back in the world frame:
  standing when the long axis is within 45 degrees of vertical; `onTop` when a tossed kubb
  rests clearly above the ground, the nearest piece under it).
- `core/match.lua`: one plain table `m` (the engine game, start time, mode, per-turn toss
  count) that a resume can save. `match.setup(m)` raises lying kubbs and places punishment
  kubbs with the engine's policies, then returns the next throw in the view frame (kind,
  projectile, pieces, `forwardY` = how far forward the thrower may walk, `advY`, `targets`,
  `label` such as "Team B  baton 2 of 6"); `match.resolve(m, res, illegal)` applies a
  finished throw and sets `m.text` (the result line); `match.resign`, `match.file`.
- `scenes/match.lua`: phases handoff (the full-screen hand-off card before each team's turn,
  A to play), settle (below), play (the throw scene set up by `throw.prepare`: pieces, lines, projectile,
  targets; `s.auto = false` stops it in mode `done` after the rest hold) and over (the
  winner card; the game file was written to `games/` in the Data folder, DESIGN 7; A is a
  rematch, B the title). The
  engine rules on a throw as soon as it is at rest, so the result line shows during the
  rest hold; then the next throw is set up from the engine's state plus the turn's debris
  (below): standing pieces are where the engine says (kubbs pushed out are put back, raised
  and punishment kubbs appear).
- Out kubbs stay on the pitch (Jamie, 2026-11-13): the engine keeps every kubb thrown this
  round as one of its pieces wherever it lies (Rules engine, "Judged at the final
  position"), so `outcome.pieces` has them and later kubbs hit them. They leave the pitch
  when the round is judged (picked up for a rethrow, or a punishment kubb). After a toss
  that is not the last of its round `m.text` says where the kubb lies now (`kubb in for
  now`, `kubb out for now`, `own half hit: kubb out`); after the last one it says the
  judgment (`kubb in`/`all in`, `kubb out: rethrown`/`2 out: rethrown`, `out twice:
  punishment kubb`, `on a kubb: lowered`, rescues). The label's `of` is the throws made plus
  those left in the round, so it grows when a judgment adds rethrows.
- Debris (`core/debris.lua`, carried by `core/match`): within a turn every thrown baton
  lies where it came to rest and every kubb it toppled that the engine took off the pitch
  lies where it fell. `match.setup` gives them as `s.debris` (core/world pieces in the view
  frame, full pose and z, `toppled`, asleep) and a per-turn baton body id `s.batonId`
  (`baton1` ..); `match.worldPieces(s)` is pieces then debris, the bodies a throw's world
  starts with. `match.resolve` (`match.carryDebris`) moves the debris to where the throw
  left it, adds the new baton and newly downed kubbs; a throw the engine puts back (`Z`)
  leaves the earlier debris as it was and only adds its baton. The debris is kept in the
  world frame and turned for Team B. A debris kubb is down in the world (`wasToppled`), so
  hitting it again tops nothing up; a standing kubb it is pushed into counts for this throw
  as a direct hit would. The hand-off (a new turn), the end of the game and a resign clear
  it. During the inkast the engine keeps the tossed kubbs on the pitch lying (in or out); debris
  also carries their exact rest pose (tilt, height) while the engine's pose is the one they
  came to rest at, so they are shown and simulated as they landed until raised or picked up.
  A kubb lowered at the judgment no longer matches and is shown flat; one whose support was
  picked up keeps its spot but drops its exact pose (it would float). In the scene the
  debris items follow the engine's pieces; a lying baton is a `baton` item of `render/world`
  (drawn like the flying baton from its cached pose, nothing prepared); the minimap draws
  debris as 1 px dots like other toppled pieces. Cost: `make bench` runs its throw again with
  six lying batons and ten downed kubbs asleep (about +16% per step on the desktop over the
  whole run, +9% in the collision phase; all of it in the pair loop's sphere checks between
  awake bodies and the sleeping debris); a sleeping body costs nothing else until woken.
- Raising and punishment kubbs by hand (`scenes/settle.lua`, boards `Raising.png` and
  `Punish.png`, which were sketches): when the engine's next need is a raise or a
  punishment kubb, the match's phase is `settle` and the defending team does it, its name
  on the rail. In PASS + PLAY a card comes first (Jamie, 2026-11-14; `core/cards.settle`,
  `render/cards.settle`, `s.settleCard`): PASS THE PLAYDATE TO the defender, how many
  kubbs it raises and punishment kubbs it places, THEN HAND IT BACK TO the attacker, A to
  start; none against the Playdate, whose player holds it already, and none after. Raise: a 3D view of the lying kubb (`render/world` with its own camera,
  in the defender's view frame, behind and above it, far enough back to show the pitch
  round it; the pieces within `raiseNear`), each
  end the engine allows drawn on the ground as its 7 x 7 footprint, the chosen one dotted
  with STANDS HERE (MOVED CLEAR when II.D.5 slid it). The d-pad looks (Jamie, 2026-11-14):
  left/right turn the view round the kubb (`lookTurn` degrees a second), up/down zoom in
  and out (`lookZoom`, between `zoomMin` and `zoomMax` of the starting distance); which
  end is on the right is read again whenever the kubb lies flat. A raises the highlighted
  end (`g:raise(choice)`), which starts on the engine's own choice; only the crank picks
  the other end (Jamie, 2026-11-14). The crank (Jamie,
  2026-11-13) tips it: forward onto its right-hand end on screen, backward onto its left,
  `crankPerRaise` (270) degrees from lying to standing (`raising.tipPose`, pure and
  tested: it pivots on that end's bottom edge onto the footprint), and all the way up
  raises it on that end; an end the engine does not allow will not tip and its flag says
  why (THAT END IS OUT, THAT END IS BLOCKED). Punish: the
  defender's half from above (40 px a metre), grey keep-out circles a baton length from
  the stakes and the king, the kubbs on it, and a cursor kubb the d-pad moves (faster the
  longer it is held); `raising.punishmentCheck` runs as it moves, a refused spot shows why
  (TOO NEAR A STAKE, TOO NEAR THE KING, ON A KUBB) and A there does nothing; A elsewhere
  places it (`g:placePunishment`). The cursor starts at `raising.autoPunishment`'s spot. The
  still parts are one image redrawn only on a change. Scripted matches (`seed`,
  `instant`, or `autoSettle` in the scene's options) leave both to the engine
  (`match.setup`). Self-tests `settle` and `settle-crank`.
- Names (`scenes/names.lua`, board `Names.png`; pure rules in `core/names.lua`, tested):
  PASS + PLAY asks for both teams' names, VS PLAYDATE for the player's, on the board's
  black panel beside the Playdate's system keyboard (`playdate.keyboard`): whose name it
  is, the name as typed (cap 32, cap 16 when wider than `bigMax`), UP TO 10 LETTERS, the
  game file id, and what comes next. A name keeps letters, spaces, hyphens and
  apostrophes, ten at most, and needs a letter; OK takes it, the keyboard's cancel goes
  back a step (from the first, to the title). The last names are saved
  (`playdate.datastore` "names") and offered again. The match gets them as
  `opts.names`, the engine's teams (one player each, named as the team), so cards,
  labels and the game file use them. `main.lua`: title -> `names` -> `options` -> `play`; the winner
  card's A is `rematch`, the same options again with no names screen. Self-test `names`
  (scripted, no keyboard: `names.type`, `ok`, `back`).
- Match options (Jamie, 2026-11-14: "the game options for the match you are starting";
  `scenes/options.lua`, pure rows in `core/matchopts.lua`, tested): after the names, before
  every match (PASS + PLAY and VS PLAYDATE). Five rows: SURFACE (grass, sand, snow),
  OPENING (2-4-6, or six from the start), RAISING (by hand, or automatic: the engine's
  policies, `autoSettle`; against the Playdate "by hand" is the player's side only, as
  before), SET (the kubb set, "Kubb sets") and WIND (off, light, strong; "Wind"). Up/down choose a row, left/right change it (the chosen row black, with arrows),
  a line under the rows says what the row is for; A starts, B goes back to the names. The
  choice is kept (`playdate.datastore` "matchopts", `matchopts.valid` on reading) and
  offered next time. `main.lua`: title -> `names` -> `options` -> `play`; a rematch keeps
  the options; a resumed match keeps its raising (the save's `opts.autoSettle`; surface and
  opening are the engine's own). Self-test `options`.
- Saved games and resume (`core/save.lua`, pure and tested): as soon as each throw is
  ruled on (at rest, so leaving for the title during the rest hold cannot give the throw
  back), before every settle step and after every raise and punishment kubb placed by hand
  the match scene saves the match in progress (`scene.persist` to `playdate.datastore` "match"); a finished match
  deletes it; leaving for the title keeps it. Scripted matches (`seed`, `instant`,
  `noSave`) never save, and self-test runs (`tw.selftestRun`) save under their own key
  (`scene.saveKey()`, "selftest-match"), so they never touch a player's saved match.
  `save.write(m, opts, writer)` hands the writer the live engine game, sheet, debris and
  clock (no copy: copying cost 43 ms on the device at turn 4; the datastore write itself
  is 68 ms, at the frame that already sets the next throw up); the sheet's `current` turn,
  the one table reached two ways, is detached for the write and kept as `currentIndex`.
  `save.pack` is the same as a checked plain copy for the tests (`save.plain` refuses
  shared tables, functions and mixed tables); `save.unpack` puts the `rules.Game` and
  `notation.Sheet` metatables back.
  `tests/lua/test_save.lua` plays 40 seeded games saved and restored every 7th action
  and needs the same game file as straight through. With a save, the title shows `B
  RESUME <A> V <B>, TURN n` beside A START (a save that does not read back is ignored,
  never a crash at launch); `main.lua` opens `resume` from it (the match
  scene's `opts.resume`, its names and VS kept for a rematch). Self-test `resume`.
- Games list (`scenes/games.lua`, board `Games.png`; `core/gamefile.lua` pure and tested
  over every fixture): the title's System Menu "Games" opens it. Every finished game in
  `games/`, newest first (file names start with the date): the date, the teams with a
  crown on the winner, turns and minutes; the chosen row is black; the footer gives its
  baton hit rates and the baton the king fell to. Crank (`crankRow` degrees a row) or
  up/down moves; A shows the score sheet (the game file as written, scrolled by the crank
  or up/down; B back; the same viewer as the match's, `scenes/sheet`); B goes to the title. Files are read and parsed only as their rows
  come on screen; each screen is one image redrawn only on a change. Self-test `games`.
- VS PLAYDATE (`scenes/match` with `opts.vs = "B"`; `main.lua` opens it as `"vs"`, and a
  rematch keeps it): the player is Team A (the name entered, "You" by default), the
  Playdate Team B "Playdate" (the
  engine's team names, so cards, labels and the game file say so; mode "Vs Playdate").
  Its throws come from `core/autothrow` (`choose(setup, rng, scale)`, scatter times
  `scene.tune.cpuScatter`, seeded from the clock): it chooses as its turn comes up, the
  scene shows that stance and aim (`throw.showAim`, `s.watching`: the gauge and loft
  plaque give way to a WATCH prompt; its kubb tosses are lobs aimed like a baton, so
  `showAim` turns the drill marker off for them) for `cpuThink` s, then
  `throw.autoLaunch`. It raises
  and places punishment kubbs with the engine's policies (no settle screen); the player
  settles by hand. No hand-off card before the Playdate's turn. The System Menu resign is
  always the player's and waits for the player's turn. Self-test `match-vs` (a whole
  match, the player's throws seeded, its game file gated).
- Kubb toss: the same aim, loft and crank swing as a baton, always from the baseline; the
  kubb is a real body (`world.launchKubb`) turning at `throw.tune.tossTumble` of the
  swing's tumble with no tilt (no helicopter), drawn as one more box item.
- Stay put (Jamie, 2026-11-14): in `throw.prepare` a team's batons after its first of a
  turn keep the last baton's stance (`playerX`, `playerY`, swivel, loft; `s.stanceSide`,
  `s.stanceKind`), clamped to where this baton may stand (a king shot pulls it back to
  the baseline). The first baton of a turn and every kubb start from the middle of the
  baseline. Self-test `match-opening` checks both.
- Advantage line: the d-pad walks between `backMax` behind the baseline and `forwardY` (the
  engine's advantage line; king shots are from the baseline). A turn's first baton starts
  on the line (Jamie, 2026-11-14: from there you are far more accurate, so the camera comes
  up with you, not held back at the baseline). While aiming, yours or the Playdate's, an
  inverted flag under the rail says `ADVANTAGE LINE  2.4 M` (`hud.advantage`, its text made
  once a throw, `s.advText`). The line is drawn on the pitch (2 px, dashed 2 on 2 off; the
  centerline is 6 on 4 off) and on the minimap. Self-test `match-whole` checks the start
  and the flag.
- Camera: the aim camera frames the setup's `targets` (standing field kubbs, else base
  kubbs, else the king) and looks `camera.tune.aim.lookBeyond` past the nearest of them
  (`camera.lookDistFor`, never nearer than `lookMin`); base kubbs on the far baseline give
  the practice framing.
- System Menu "Match": sheet (Jamie, 2026-11-14: "see the scoresheet for a game in
  progress"; `scene.showSheet`): once nothing is in the air, the game file so far
  (`match.file`, no `End`) on `scenes/sheet`, opened at its last line, the rail with the
  teams, the turn and the surface; the crank or up/down scrolls, B goes back. The match
  waits under it (a throw, the Playdate's think, a card) and carries on where it was.
  Self-test `match-sheet`. Resign (the team on turn gives up, `G`; it waits until nothing is in
  the air, and is dropped if that throw ended the team's turn; chosen while the defender
  settles, it is the defender's, which holds the Playdate then, and waits for the
  defender's own turn: self-test `settle-resign`) or title (leave: the match is dropped and no file is written). A game file whose name is taken
  gets `-2`, `-3`, ... before `.txt`. Pass and play
  has one Playdate, so the team on turn is whoever holds it.
- The match tells the throw scene what the HUD shows: the rail (`throw.setRail`: team,
  projectile, number of it, and the field and base kubbs still to topple, or KING) and,
  after a throw is resolved, the result flag (`throw.setFlag`, `hud.short` of the
  result). Per frame it adds, from the throw scene, a dozen-entry target scan for the camera. Once per throw (not per frame) it builds the
  engine's pieces and outcome tables and rebuilds the items: expect one longer frame on the
  device when a throw is resolved and the next set up.

## Kubb sets

Jamie (2026-11-14): "different Kubb sets... a USA set, Sweden set, Minnesota set,
Wisconsin set", envisioned here and chosen in the match options' SET row
(`core/matchopts`, `opts.set`, kept by the save and a rematch). As real painted sets, only
the kubbs' heads and the king's crown are painted; the bodies stay bare wood, so a piece
reads the same standing, falling or lying, and a face away from the light stays black.
`render.world.sets` (`render/world.lua`):

- **Classic**: bare wood (the default and the practice pitch, `throw.tune.set`).
- **USA**: a black head with three white stars, two black stripes under it; the king's
  crown black with a white star.
- **Sweden**: a black head split by a white bar, and near, the Nordic cross's upright left
  of centre; the crown black with a white Nordic cross.
- **Minnesota**: a deep black head with a white wave (the lakes); the crown black with the
  North Star.
- **Wisconsin**: a cheese head (`world.DOTS`, 2 x 2 holes every 4 px) on a black rim; the
  crown in cheese.

A kubb's head is its local +z end: one raised the other way up wears its paint at the foot,
as a real one would. `render.world.setSet(name)` changes the set and drops the caches only
when it changes; the throw scene owns its set (`throw.setSet`, `s.set`) and sets it at
every draw (render/world is shared with the settle view). Game play first (Jamie, 2026-11-14:
"keep the Kubb set styling simple enough that it doesn't destroy game play"): a piece under
`setFrom` (20 px tall, which is every kubb seen from the throwing line) draws exactly as
classic; nearer, the set's bands, cheese and crown, and from `setDetailFrom` (30 px) the
stars, crosses and waves: the impact camera's close views and the raise view. A first
version gave every far kubb a plain black head band: on the device that cost about a tenth
of the shown speed (the three match-case throws 13.5 s with USA against 12.0 and 12.3
classic, `telemetry/2026-11-14/bench/run8`), so it was cut. Black paint needs no colour
change (the outline's colour). The `drawcalls` self-test with the USA set: 154 calls a flight frame against 134 classic, 183 an
impact frame against 158 (2026-11-14). Self-test `sets` draws every set up close and from
the baseline (frames 1 to 6); the autobench has USA and Wisconsin variants.

## Slow motion

`playback.speed(t, hitTime)` (`source/core/playback.lua`, tunables `playback.slow`) slows the
picture around the baton's first hit: the physics runs ahead of the screen, so the hit time
is known before it is shown. The slow stretch also gives the physics time to catch up on
the device.
While it plays (`playback.speed` below 1, the ease back included) the throw scene sets
`s.slowMo` and the HUD shows the SLOW MOTION flag (`hud.slow`, `hud.tune.slow`). The pace
slowing because the physics fell behind shows nothing. The `hit` self-test checks the flag
0.1 s after the hit (frames 2 and 3 show it). It is short (Jamie, 2026-11-14: it is for the
impact and must not hold the play up while the baton slides): `hold` 0.12 s after the hit,
then back to real time over `ease` 0.15 s (it was 0.45 and 0.35). On the device a throw
takes as long either way (the hit 6.20 s against 5.78 in the same run,
`telemetry/2026-11-14/bench/run5`): after a hit the physics computes slower than real
time, so the slide plays at the pace it allows with or without the slow motion.

The camera's half circle (Jamie, 2026-11-13): once a hit burst fires (baton throws only),
the impact camera orbits the struck piece by `throw.tune.swingDeg` (180) over `swingTime`
(0.8 s of shown time from that piece's impact, `camera.smooth`), the same way it was
already turned off the line of flight, and opens to a higher, wider view by the end
(`camera.tune.impact` `openHeight`, `openDist`, `openF`; `camera.impact`'s `orbit` and
`open`), so the slow motion shows the piece fall and the pitch round it; it stays there
through the rest. It runs on shown time (`s.swingFrom`, reset at launch), so it holds when
the picture holds (the calm tail; when the tail ends inside the turn the camera jumps to
where the turn has got to). While it turns the
camera moves, so those frames are full draws, not the layer, and they take
`swingPeriod` (60 ms) instead of `framePeriod`, leaving the physics its time: on the device
the match case's hit took 6.7 s from release to rest with the half circle at 40 ms a frame,
4.7 s at 60 ms and 4.2 s without it (shown speed over the three throws 0.34, 0.40, 0.42;
the open view costs nothing measurable; 2026-11-14). It goes round the piece its burst is
for (`s.burst.x1, y1`), not the first thing hit, and a burst taken back stops it where it
is (`s.swingStop`). Jamie kept it on at that cost (2026-11-14). `swingDeg = 0`
turns it off (the `layer` self-test does, to test the layer with a still camera; the
autobench has a variant without it). The `burst` self-test checks it starts at the impact.

## Hit bursts

`docs/design/README.md` "Hit effects". When the picture reaches the impact on the first kubb
or king a baton toppled (the moment it was struck, not once it is down: Jamie,
2026-11-13), a pre-drawn burst is put up and to the left of the hit, its long spike's tip
on it (every piece struck has its own knock: "Knocks" below).

- `core/world` stamps each body with `touchT`, the first time anything struck it (in the
  contact store, one test a contact, no arithmetic), and each piece it topples with
  `toppleT` (pieces down before the throw have none). `core/burstpick.pick(w, showTime)`
  (pure, tested) says which burst and when, by the struck pieces' impact times
  (`burstpick.hitTime`: `touchT`, else `toppleT`). The physics cannot reach a topple
  before the picture reaches the impact (the device ran 262 ms of shown time late that
  way), so a kubb or king is judged falling at its impact: toppled already, or struck
  within `judgeFor` (0.5 s) and moving at `fallV` (0.5 m/s) or turning at `fallW`
  (5 rad/s) or more (`burstpick.falling`, which also says whether it is `sure`, that is
  toppled). The king is judged only once it has toppled: its burst inverts the screen and
  plays the game's end, so a king merely pushed must never get it, at the price of a king
  burst that can come up to the physics' lead late (Jamie kept it so, 2026-11-14). A topple more than `grazeFor` (1 s)
  after the first touch was a later blow, so it is timed at the topple. The burst starts when the picture reaches the first falling piece's impact;
  one that was not sure and then comes to rest standing (`burstpick.stoodUp`) is taken back
  (`B.takenBack`: the burst ends at once). `render/burst` keeps how late it started,
  `B.gap`, and the autobench prints it: 2 to 6 ms of shown time on the device (2026-11-13),
  within one slow-motion frame. The king falling within `window` (0.4 s) of the first
  impact, or struck by the time on screen, is `king` (a king that falls later replaces the
  burst showing, from its start, with the king's chord); a second falling kubb struck
  within the window is `double`, else `clean`; nothing for a miss or a touch that leaves
  the kubb standing, and nothing for kubb tosses or drills.
- `render/burst.lua`: three images per kind, `images/burst/<kind>-1..3` (flash, burst with
  the word, break-up) from `tools/art/build.py` (`BURST_*`; 2-bit PNGs with a clear
  ground). Phases run on real seconds (2, 12 and 4 frames at 30 fps), not the slowed throw
  time. The anchor is the baton's first contact point when that was the toppled piece,
  else the piece's pose at its impact, lifted `lift`; it is projected each frame and the
  image kept on screen below the rail. Double: KLAK (first kubb) and KLAK! (second, 3
  frames later). King: the whole screen inverts for the flash
  (`playdate.display.setInverted`), the burst wears the crown. The break-up adds six
  `fillRect` chips. Drawn after `render.world.draw`, outside its caches.
- The king's burst adds a short C-G chord made by the synths at its flash (`sound.king`).
  The words are `BURST_WORDS` in `tools/art/build.py` (rerun it to change them).
- The throw scene keeps the state in `s.burst` (`burst.new`, `reset` at each launch and
  back at aim, `update` in flight and rest, `draw` after the world).
- Until the physics has computed the whole window after the first topple, the kind is
  provisional and re-read each frame: a later topple can still make a clean burst a double,
  or any burst the king's. `throw.reset`, `throw.prepare` and a scene change (`main.lua`
  `open`) clear the burst and the screen inversion.
- Self-tests: `burst` (the hit throw: flash, TOK!, break-up, then aiming again with the
  burst cleared; the burst must start within one shown frame of the impact: 5.8 ms of
  shown time on the Simulator), `burst-reset` (Pitch reset while the burst is up) and `bursts` (every
  burst image on white, for review).

## Knocks

Jamie (2026-11-14): "an audio recording of a Kubb hit. There are multiple to use so they
are not all the same ... if the baton hits multiple kubbs you could play multiple
overlapping files". `source/sounds/knock-1..9.wav`: nine takes of a baton hitting a kubb,
cut from Jamie's recording by `tools/sounds.py` (needs ffmpeg; the raw take stays out of
the repo): the rumble under the take (wind and handling, below about 300 Hz) filtered
out, each hit cut 4 ms before its onset for 0.36 s with its tail faded to silence, the
levels matched (the same RMS over the first 80 ms, the loudest peak -1 dBFS), mono 22050
Hz 16-bit (about 16 KB each). A rumble the filters let through is dropped by level.

- **When.** A knock for every piece struck, as the picture reaches the moment (`touchT`,
  the first touch by anything): kubbs and the king, batons lying on the pitch and the
  stakes (Jamie: "if wood hits wood play a sound"; the ground is not a body, so a landing
  is silent), in practice, matches and drills, batons and kubbs alike, whether it falls or
  not. The throw scene's
  `knocks` (flight and rest, every frame once the thrown piece's first hit is on screen;
  before it nothing else is awake to touch) asks `burstpick.touches(w, t0, t1, out)` (pure,
  tested) for those first touched since the last frame's shown time; the thrown piece
  itself is left out (its touch is the same blow). A knock more than `knockLate` (0.15 s)
  behind the picture is not played (the jump at the end of the calm tail).
- **Which.** `sound.knock()`: a random take, never the last one played and, when it can,
  not one still playing, so knocks that come together (a baton through two kubbs, a
  domino) overlap as different takes; each at a rate of 1 +-`knockRate` (0.06), so no two
  sound alike. One `sampleplayer` per take, made at the first knock.
- `tw.sound.tune`: `knocks` (9), `knockVol`, `knockRate`, `king` (the chord). Sound is off
  in self-tests; self-test `knocks` turns it on at volume 0 over the hit throw: every take
  loads, one knock per piece struck, none before the hit.

## Frame-time log

To tell the deliberate slow motion from dropped frames, every throw (practice and match)
appends one JSON line to `frames.jsonl` in the Data folder (`source/framelog.lua`, on outside
self-tests, no menu item; the line is `core/frametel.encode`, written once in the throw
scene's `landed`, never during the flight; not in instant mode). Collected with a dozen
number fields on one table per throw scene (`s.ft`, reset at launch) and two maxima on the
playback table; nothing is allocated per frame. `traces.jsonl` is separate and unchanged.

```
{"v":1,"time":"2026-11-20 19:42:07","scene":"match","proj":"baton",
 "pre":[41,0.82,20.0,24.1],"slow":[52,1.07,20.6,38.2],"post":[30,0.61,20.3,22.0],
 "starved":3,"stall":44.0,"awake":6,"contacts":27,"bodies":28,"steps":712,"phys":512.3}
```

- `scene` `practice` | `match`; `proj` `baton` | `kubb` (lobbed) | `drill`.
- `pre`, `slow`, `post`: the flight's shown frames before the slow motion, in it
  (`playback.speed` below 1, the ease back included) and after it, each `[frames, real
  seconds, mean frame dt ms, max frame dt ms]`. Frame dt is the device's measured frame time
  without the input's 0.1 s cap (`p.raw`). A throw that hits nothing is all `pre`.
- `starved`: shown frames whose show time was clamped because the physics had not computed
  that far (playback waited; frames in the calm tail are not counted); `stall`: the longest
  run of them, ms of real time. Lines written before 2026-11-13 count the tail too.
- `awake`, `contacts`: the most bodies awake and contacts in any physics step; `bodies`:
  bodies in the world (six stakes included); `steps`: physics steps; `phys`: ms the physics
  took (`playback` busy time). About 200 to 250 bytes a line.

Slow frames inside `slow` with `starved` 0 are the slow motion doing its job. In flight a
frame takes `throw.tune.framePeriod` (40 ms) by design; a mean dt well above that means the
draw or the physics overran its share, and `starved` means the pace could not keep the
picture behind the physics. The `flight` self-test reads its line back.

## Crank traces

The System Menu has "Readout" (the debug line after each throw) and "Record". Record is
on by default while the throw is being tuned (self-tests leave it off). With
Record on, every swing is appended as one JSON line to `traces.jsonl` in the game's Data
folder (Simulator: `~/Developer/PlaydateSDK/Disk/Data/com.thingelstad.throwingwood/`).
The format is documented at the top of `source/core/trace.lua` (samples are
`[dt, raw crank degrees]` per frame from the first wind-up frame to release or let-down,
plus the result). `lua5.4 tools/replay_traces.lua <file>` replays each line through the
current `core/swing.lua` and prints recorded vs replayed results; `--current-sign`
replays with today's `forwardSign` instead of the recorded one. The test fixture is
`tests/fixtures/traces/sample.jsonl`. Drill lines add the fields in "Drilling" above;
`replay_traces` reads them like any other line (the swing is the same).
