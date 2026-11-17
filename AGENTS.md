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
- `make realgames`: plays `REAL_N` (150) physics matches (`REAL_SEED` 2) into
  `build/realgames/` and prints their figures beside the same figures from the games people
  scored in a pk-kubb-score checkout (`tools/realgames.mjs`, see "Real games"). Needs the
  checkout, so it is not part of `make test`.
- `make bench`: the physics benchmark on the desktop (`tools/bench.lua`, three runs of
  `core/bench`, prints each and the best; then the same three runs with a full turn's debris
  asleep on the pitch, and the difference). `lua5.4 tools/bench.lua [runs] [--profile]
  [--micro]` adds the per-phase profile of `world.step` and the micro benchmarks of
  `core/microbench`. See "Measuring on the device" for the device side.
- `make mjref`: the reference-engine comparison, the same throws through `core/world` and
  MuJoCo, into `build/mjref/report.md` (`MJPY`, a Python with `mujoco` and `numpy`; see
  "Reference engine"). Not part of `make test`.
- `make clean`.
- `make release`: a clean build zipped as `build/ThrowingWood-<version>.pdx.zip`, for
  friends to sideload (play.date/account/sideload). Raise `version` and `buildNumber` in
  `source/pdxinfo` for each one (a Playdate keeps the higher build), and the same pair in
  `source/core/version.lua` (`tw.version`: `version`, `build`, `text` "0.9.5 (6)"). pdxinfo
  is the source of truth; `test_version.lua` fails when the two disagree, and `make
  release` runs it before it builds. The title shows `tw.version.text` small in the sky's
  top right corner; the web game gets the same pair through its vendor sync. The zip is published
  on files.thingelstad.com and linked from https://playdate.thingelstad.xyz/throwing-wood/
  (that site's repository). 0.1.0 (build 2), 2026-11-14: the first for friends. 0.2.0
  (build 3), 2026-11-14: HOW TO THROW walks through the real crank; drills set the angle.
  0.9.0 (build 4), 2026-11-15: the last test build before 1.0.0; the crank-clock throw,
  saved players and teams, DOUBLES and THE WALL. 0.9.5 (build 5), 2026-11-15: the release
  candidate for wider play; HOW TO THROW for the clock throw, the baton hits pass, drilled
  kubbs that settle and a target circle that no longer locks onto kubbs; build 6 the same
  day adds HOW TO PLAY, the release-candidate polish and the plain-words pass.

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
  are letters and underscores only. Positions are errors (even with `--allow-warnings`) when
  one does not parse as positions (its token has no `at`), a token has more than it counts,
  one is off the pitch, or `kubb.js` reads the game differently with every position taken
  out; the gate prints how many it saw. `tests/fixtures/bad/` has a game for each.

## pk-kubb-score is vendored

The gate loads `notation-parser.js` and `kubb.js` from `tests/vendor/pk-kubb-score/`, copies
of pk-kubb-score's `site/assets` files (Jamie approved the copy 2026-11-13, so the gate runs
on any machine and on GitHub). Never edit the copies; `make sync-notation` refreshes them
from a checkout at `~/Projects/pk-kubb-score` (or `$PK_KUBB_SCORE`). The checkout itself is
still read only: never write there and never run `npm install` there.

Synced 2026-11-16 for optional positions on the pitch (Jamie: "Approved also for the
extending of the notation system."): a comment that starts with `@` after kubbs thrown in or
a baton, `2I (@ b6 c7)` or exact meters `(@ 1.32,5.87)`, seen from Team A's baseline, `^`
for where the thrower stood. The parser and `kubb.js` put them on the token as `at`. The
game writes them since 2026-11-16 ("Positions" under "Notation conventions").

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
pose unless its center left the pitch (II.B.7: put back). It stays as the throw left it, not
stood up straight: core/debris carries its exact body pose ("Debris" below).

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
- **Positions** (2026-11-16, the notation's optional `(@ ...)`; Jamie: "the biggest
  limitation of the scoresheet system I created is it doesn't note pitch position for
  anything"): exact meters `x,y` with two decimals after the token, before any `# note`:
  `3. max:2I (@ 4.39,4.61 4.34,5.21) max:F (@ 4.39,4.61) alex:B (@ 1.50,8.00)`. The frame
  is the pitch seen from Team A's baseline all game: `notation.pitchXY` is the engine's
  x + 2.5 (the left sideline, as someone on Team A's baseline facing Team B sees it, is
  x = -2.5; `test_positions` proves it with the aim camera and the base kubbs) and y as is,
  clamped to 0..5 and 0..8 (the grammar has no minus sign). The sheet keeps them as data in
  the engine's frame beside the token (`t.inkastAt[pid]`, a baton's `at`, through
  `Sheet:inkAt` and `Sheet:baton(pid, token, at)`); `turnLine` converts them and never
  writes more than the token counts (`kubb.js` warns on that).
  - A baton: where each kubb its token counts stood before the throw, its F kubbs then its B
    (each in id order); also for `nFE`/`BE`. None for `-`, `Z`, `E` alone, `K`, `=`, `G`,
    `X`, nor for a base kubb toppled early and raised (II.B.4a: not in the token).
  - An inkast: written once, as the batons begin (`Game:_inkastPositions`), when every
    kubb is raised and every punishment kubb placed (afresh if `match.settleStanding` moves
    one before the first baton): each kubb thrown this turn that is in
    play, where it stands, in the order of its last throw, on the token of the player who
    made that throw (`k.inkBy`, `k.tossSeq`); a punishment kubb on the token that counts
    its P. A rescued kubb (Q) has the place it was thrown back in to; a kubb lowered from on
    top of another (N) where it was raised after; a kubb out of play has none.
  - A game that ends during the inkast (king toppled by a kubb, `E`; a resign before the
    batons) writes no inkast positions: nothing was raised. An early king by a baton keeps
    the token's F places (`2FE (@ ...)`).
  - Not written: `^` (where the thrower stood). The engine's outcomes carry no stance, and
    the throw's stance is not kept to the rules engine; plumbing it through `core/match`
    for both the player's and the computer's throws is left for later.
  - A save from before positions loads (no `inkastAt`, `at`, `inkBy`, `tossSeq`): its
    turns render without them, and a turn in progress gives its kubbs to its one inkaster
    (none when it had several). `core/gamefile` drops comments in parentheses before it
    counts tokens.
  - On screen (`scenes/sheet`: the games list, a player's GAMES, a match's own sheet) the
    positions are left out (`gamefile.shown`): they would fill the 400 px screen, and the
    view reads as it did before. The file keeps them.

## Headless games

`tools/thrower.lua` is a random thrower with no physics: hit or miss by distance and skill,
neighbours toppled or pushed, inkast landing spots with scatter, and rare events on purpose
(rescues, punishment kubbs, kubbs on top of others, helicopters, own-half hits, early base
kubbs and kings, resigns). Its rates are `thrower.tune`. `thrower.playGame(seed, check)`
plays one game; `tests/lua/test_games.lua` plays 50 and checks invariants after every
action; `tools/games.lua` writes N games. Teams have one to six players and who throws is
`core/order`'s ("Throwing order"); now and then a team gives a baton or its kubbs to
another player (`changeThrower`, `changeInkaster`, from a generator of their own, so the
throws are the same without them), and every sheet is checked with `order.checkSheet`.
`tests/fixtures/games/` holds thirteen generated games (a six-a-side and a two against
four among them), the two hand-written ones and one physics match with positions
(`tools/physmatch.lua --n 40 --seed 2`, six against two); `make test` gates them. The thrower sometimes aims at a kubb
of this turn lying out near the target half and knocks it toward the middle (`chaseOut`),
so games have kubbs knocked in before the round is judged; `make games` prints
`knockedIn`/`knockedOut` and the sheets' `R`, `P`, `Q`, `N` counts.

`core/autothrow.lua` is the computer thrower, and it throws the player's way (DESIGN 4):
for a match setup it picks a target, stands behind it (`plan.stance`), takes the default arc
(`plan.arcFor`), solves the plan at a level (`plan.solve`, `autothrow.tune.level`, club),
makes a synthetic swing (`autothrow.swing`: core/swing's result fields with seeded mistakes)
and launches it with `plan.launch`. `choose(setup, rng, scale, level)` returns the launch
fields (`x, y, swivel, loftDeg, speed, tumbleRate, tilt, legal`), the solve as `a.plan`
(target `tx, ty`, `back`, `release`, the gauge's ranges) and the swing as `a.swing` (`back`,
`releaseAngle`: where the computer's arm goes on the gauge), and for a kubb `a.drill`
(`markerX`, `markerY` from the line, and world.launchDrill's `noseDown, rollLand, spin,
wobble`); `autothrow.launch(w, s, a)` puts it into a world. Batons go at the
nearest live target's center, or among field kubbs down the lane with the most of them
("Tuned toward the real games" below) (from the advantage line, but never nearer than `minRange`, 2
m: a slow lofted baton under 2 m nearly always missed; the king from the baseline). Kubbs
are drilled at the drill arc to the basket (Jamie, 2026-11-14): the corner of the far half
nearest the centre line by a sideline (`basketX`, `basketY`), the one that already has more
field kubbs near it, so a turn's kubbs group and one that runs goes out for a rethrow; since
2026-11-16 to the clear spot nearest the basket (`autothrow.spot`), not onto the kubbs
already there: in a line along the throw when the turn has 2 or 3 kubbs to throw, in a
cluster round the first ones when it has `clusterFrom` (4) or more (Jamie's words in
"Drilling"). It aims short by the drill's run on (`plan.solve` with `q.surface`, so
`drill.slideFor`), and a lying kubb short of a spot by that run on is in its lane, so one
already down just past a spot is its backstop. The
swing's mistakes (`scale` multiplies them all; 0 is the clean swing): backswing sd
`backSd` 2.5 degrees, release sd `releaseSd` 4.5, a flick between 1050 and 1400 deg/s (full
power) except `softChance` 5% between 850 and 1000 (short), shake even between 0 and
`shakeMax` 0.22 except `shakyChance` 1.5% between 0.25 and 0.6, pull either way; then
`plan.launch` with `nerves` drawn from the same stream (the player's nerves, "Nerves";
none at scale 0). Before the nerves (2026-11-16) the sds were 5, 9 and 0.44 and the swing
was the only error, multiplied by the range ("Tuned toward the real games"). Measured with physics on grass at club
(2026-11-15, 300 to 400 throws each): a base kubb from 8 m 41%, a field kubb from 2 to 5 m
56 to 59%, the king from 4 m 49%, 1% helicopters; a drill rests 0.29 m from the basket on
average, 3% out. Over 40 physics matches (seed 2): 25.3 turns a game, batons hit a base
kubb 45% and a field kubb 59% of the time, 1% helicopters, 2% of drilled kubbs rethrown,
30 won on the king and 10 resigned at the turn limit (the old lobbing thrower over 20:
5 resigned). `tools/physmatch.lua` prints these counts after its games. After the baton
hits pass ("Physics", "Baton hits"; `tools/batonprobe.lua --rates 400`, its own set-ups):
base kubbs 44% -> 48%, a field kubb 2 to 5 m out 64% -> 71%, the king 51% either way;
40 physics matches (seed 2) 20.4 -> 25.9 turns, base 42% -> 48%, field 58% -> 61% (more
kubbs knocked down means more come back as field kubbs, so games run longer).
After the tight groups ("Tuned toward the real games", 2026-11-16) 150 physics matches
(seed 2): 14.6 turns a game, batons hit a base kubb 39% and a field kubb 79%, 149 won on
the king and 1 resigned.
`tools/physmatch.lua [--n --seed --out --maxturns --surface --scatter -v]` plays whole matches through
`core/match` with every throw run by `core/world` to rest (the match scene's path without
the screen; about 0.7 s a match on a Mac) and writes the game files. Team sizes go round
one to six (game i: Team A `(i - 1) % 6 + 1` players, Team B `(i + 1) % 6 + 1`), and every
sheet is checked with `order.checkSheet`. Past `--maxturns`
(40) the team on turn resigns. With no scatter every baton hits and a game never ends
(every toppled field kubb comes straight back), so the scatter is not zero. Its throws go
into the turn's debris like the match scene's.

`tools/compound.lua [--quick] [--games N] [--tilt deg]` asks whether one baton can take down
two or three kubbs: a deterministic sweep of core/swing batons (power 0.6 to 1.0, lofts 20
to 35) at pairs and triples side by side and pairs in line at 3, 7, 15 and 30 cm gaps, and
rows of three and four end on (touching and 3 cm apart), across a sweep of aim offsets, a domino check, and the spacing of standing field kubbs in physics
matches (about a minute; `--quick` about 10 s).

## Real games

Jamie (2026-11-15): "in a tournament I would have hit all five down with one baton". How far
is the game from real play? `node tools/realgames.mjs <real dir> <game dir> [--json]` reads
two folders of game files with the vendored `kubb.js` (`analyze`) and counts both the same
way, so every figure has the same denominator on both sides: the 150 games people scored
(`games/` of a pk-kubb-score checkout, read only) and matches the computer played with real
physics (`tools/physmatch.lua --out`). `make realgames` does both. A measuring tool only: it
changes nothing in the game, and what to tune from it is Jamie's call. A score sheet records
what each baton took, not where anything stood or how it was thrown, so it says where the
rates differ, never why; and the real games are tournament and club players, the game's
are the computer at club level against itself.

- **What the real games are** (Jamie, 2026-11-16): all tournament games, often the final
  rounds of a bracket, so read them as club to high club play; some are pro (players who
  ranked high at Worlds). They are the mark for those levels, not for a beginner.
- **How it counts.** A baton is "at field kubbs" when a field kubb stood when it was thrown
  (the turn's `startField` less what earlier batons took), "at base kubbs" when none did
  and a base kubb was left; king shots are `K` and `=`; `X` is not a throw. Clearing the
  field is kubb.js's `btc`. Not throws either: the batons kubb.js marks `void` (written
  after the game ended) and a resign or a win token. `make test` runs it over the fixtures against themselves (that
  it runs, nothing more).
- **First figures** (2026-11-16; 150 real games, 150 physics matches seed 2 after the foot
  catch; real -> the game):
  - Turns a game 8.9 (median 8) -> 21.9 (19); every real game ended on the king, 80% of
    the game's (30 resigned at the 40-turn limit). The team that threw first won 55% -> 53%.
  - **A baton at field kubbs**: missed 25% -> 37%; took one 49% -> 56%; took two 16% -> 7%;
    three or more 10% -> 0.4%; of those that hit, two or more 34% -> 11%; field kubbs a
    baton 1.16 -> 0.71; the most with one baton 7 -> 4.
  - **Clearing the field**: 83% of turns -> 46%, in 3.4 batons -> 4.2. By kubbs to clear:
    three 92% -> 86%, four 88% -> 62%, five 85% -> 40%, six 79% -> 22%, eight 68% -> 4%.
    Up to three kubbs the game is near real play; past that it falls away, which is the
    doubles and triples missing. A turn thrown from an advantage line 14% -> 50%.
  - **A baton at base kubbs**: 35% -> 45% (from the baseline 33% -> 41%; from an advantage
    line 52% -> 54%). The computer is better than real players at 8 m.
  - **The king**: 84% of 179 shots -> 46% of 259.
  - **Kubbs thrown in**: rethrown 14% -> 2.5%, punishment kubbs 1.3% -> 0.1%. Real players
    throw at a tighter group and miss it more; the computer's basket is safe.
  - **A steadier computer does not close it** (`tools/physmatch.lua --scatter`, `make
    realgames REAL_SCATTER=0.6`: every mistake of the computer's swing times that; 150
    matches each, seed 2; real / scatter 1 / 0.6 / 0.3). Base kubbs from 8 m 33% / 41% /
    73% / 98%; the king 84% / 46% / 71% / 98%; a baton at field kubbs missed 25% / 37% /
    17% / 5%, took two 16% / 7% / 11% / 17%, three or more 10% / 0.4% / 0.6% / 1.8%;
    cleared six field kubbs 79% / 22% / 54% / 87%, eight 68% / 4% / 17% / 39%; turns a
    game 8.9 / 21.9 / 20.5 / 14.9; rethrown 14% / 2.5% / 1.9% / 0.8%. At 0.3 the computer
    hits a base kubb from 8 m three times as often as tournament players and still takes
    three with a baton a fifth as often: the gap is not accuracy.
  - What it does not show: the real players' groups. Jamie (2026-11-16): "Multiple fields
    kubbs is all about drilling tight clusters." The sheets agree as far as they can: real
    players rethrow 14% of their kubbs (they drill at a tight group and pay for it), the
    computer 2.5% (its drills rest 0.29 m from the basket on average, so its kubbs stand a
    kubb or two apart). So the first place to look is how tight the game's groups are, the
    computer's and a player's, before the baton or the physics.
- **Latest figures**: "Tuned toward the real games", the last bullet ("Into the group",
  2026-11-16), with seeds 2, 3 and 4.

- **Single throws against real video** (2026-11-16): `docs/reference/REALCLIPS.md` and
  `realclips.json`, 22 events measured frame by frame from public video (drills, batons,
  chains) beside the engine's figures, with intervals and a ranked list of where the
  engine sits outside. A small set: read it as directions, not targets.

### How tight the groups are

`lua5.4 tools/clusters.lua [--n 60] [--seed 2] [--drill 1] [--baton 1] [--raise
apart|together]` (Jamie approved the measuring, 2026-11-16; no game changes) plays physics
matches with the computer's mistakes scaled separately for its kubbs and its batons, and at
the first baton of every turn with two or more field kubbs standing measures each one's gap
to its nearest neighbour (edge to edge), the group's spread and the largest group chained
by gaps of 15 cm or less; then what the turn's batons at field kubbs took. 60 matches each,
seed 2:

| kubbs x, batons x, raised | gap (mean) | within 7 cm | within 15 cm | largest group | took two | three + | turns |
|---|---|---|---|---|---|---|---|
| real tournament games | | | | | 16% | 10% | 8.9 |
| 1, 1, apart (the game) | 39 cm | 3% | 18% | 1.4 | 6.7% | 0.4% | 21.0 |
| 0.5, 1, apart | 41 | 2% | 14% | 1.3 | 5.4% | 0.3% | 18.6 |
| 0.25, 1, apart | 44 | 5% | 20% | 1.5 | 6.2% | 0.7% | 19.6 |
| 0, 1, apart | 26 | 19% | 60% | 3.3 | 8.4% | 5.3% | 15.7 |
| 1, 1, together | 23 | 36% | 60% | 2.5 | 11.9% | 1.4% | 18.9 |
| 0.25, 1, together | 29 | 30% | 53% | 2.5 | 10.7% | 2.0% | 18.7 |
| 0.25, 0.6, together | 24 | 37% | 61% | 3.1 | 18.0% | 4.2% | 13.1 |
| 0, 0.6, together | 18 | 9% | 81% | 4.3 | 14.3% | 18.3% | 5.9 |

- **The physics can do it.** With every kubb drilled clean onto one spot, raised toward
  each other and a steadier baton, a baton takes two or more 33% of the time (real 26%)
  and a game takes 5.9 turns (real 8.9). The game's doubles and triples are missing because
  its groups are loose, as Jamie said, not because a baton cannot take three.
- **The game's groups are loose**: a field kubb's nearest neighbour is 39 cm away on
  average and only 3% stand within 7 cm (a kubb's width); the largest group a baton could
  chain through is 1.4 kubbs of 5.
- **Which end is raised matters as much as the drill.** The engine's default policy raises
  each kubb on the end farthest from the others (`apart`); `together` alone halves the
  gap (39 -> 23 cm) and doubles the doubles (6.7% -> 11.9%). Which a real defender picks
  is a rules and play question for Jamie.
- **A steadier arm does not tighten the group until it is perfect** (x0.5 and x0.25 are
  no tighter than x1; x0 is). Not explained yet: at x0 every drill is the same throw and
  meets the same ground (the ground's seed is the throw's), so the likely floor is the
  ground's patches and kubbs knocking the ones already there, not the swing. That is the
  next thing to measure before anything is tuned.
- Not measured: a player's drills (the tool throws the computer's).
- **Lying, before raising** (2026-11-16): the tool also measures the same gaps when the
  inkast is judged, before the defender raises anything. On the game of the day before
  (seed 2, 60 matches) the lying kubbs were 11.7 cm apart and 21% touching, standing 24.6
  cm; since the computer drills into the group ("Tuned toward the real games", "Into the
  group") 6.5 cm and 35% lying, 17.6 cm standing. `--set world.name=value` sets a
  `world.tune` number.

### Tuned toward the real games

Jamie (2026-11-16): "You have standing approval to. Pursue this work, update both web and
play date versions, deploy as needed." The first pass changes only how the computer throws
(`core/autothrow`); the physics, the rules and a player's own throw are as they were.

- **Why its groups were loose.** One drill is accurate (it rests 26 cm from its mark, 9 cm
  with half the mistakes, 5 cm with a quarter). But every drill went to the same mark, came
  down on the kubb already lying there and skipped about a metre. That, not the swing, is
  why a steadier arm did not tighten the group.
- **The spot** (`autothrow.spot(s, side)`, `tune.spot*`). A toss goes to the clear spot
  nearest the basket on a small grid: not within a kubb of a field kubb in the far half, and
  with none in the lane it comes down in (a lying kubb 12 cm short of the spot, a standing
  one 60 cm). Steps along the throw cost a tenth of steps across (`spotCostY`), so the
  kubbs go down in one line along the throw: `tools/compound.lua` has two kubbs one
  behind the other both falling 60 to 72% of the time at gaps to 15 cm, side by side about
  10%. No spot nearer the centre line than `spotMinY` or the sideline than `spotMaxX`.
- **The lane** (`tune.laneHalf`, `laneDeep`). A baton at field kubbs aims at the front kubb
  of the lane with the most kubbs standing in it (within 7 cm across and 60 cm behind),
  across the middle of the lane; the nearest front on a tie, so a lone kubb is thrown at
  as before.
- **Mistakes by range and for a drill.** A baton's mistakes are multiplied by its range
  over `rangeRef` 7 m (never under `rangeMin` 0.45 or over `rangeMax` 1.2): a 3 m throw at
  a field kubb is not as wild as an 8 m one. A drilled kubb's are multiplied by
  `drillScale` 0.2: tournament players drill to a hand's width. (Replaced by the shared
  nerves on 2026-11-16, below: `rangeRef`, `rangeMin` and `rangeMax` are gone;
  `drillScale` stays.)
- **Measured** (150 real games; 150 physics matches seed 2; real / before / after): turns a
  game 8.9 / 21.9 / 14.6; a baton at field kubbs missed 25% / 37% / 21%, took one 49% /
  56% / 57%, took two 16% / 7% / 18%, three or more 10% / 0.4% / 3.4%; cleared the field
  83% / 46% / 70% (five kubbs 85% / 40% / 82%, eight 68% / 4% / 30%); a base kubb from 8 m
  33% / 41% / 42%; the king 84% / 46% / 77%; turns from an advantage line 14% / 50% / 27%;
  kubbs rethrown 14% / 2.5% / 0.4%. `tools/clusters.lua` (60 matches): a field kubb's
  nearest neighbour 39 -> 20 cm, within 15 cm 18% -> 49%, largest group 1.4 -> 2.4 kubbs.
- **Still off.** Three or more with one baton (10% real, 3.4%), so fields of seven and up
  are cleared half as often as real players clear them; games are still half as long
  again; the computer never pays for its group with a rethrow (0.4% against 14%: its
  basket is a safe 25 cm past the centre line and its drill is steadier than its spot is
  bold); it hits a base kubb from 8 m more often than tournament players. The engine
  raises kubbs apart, as real defenders do (Jamie, 2026-11-16). `tools/clusters.lua --set name=value` sets any `autothrow.tune` number for
  a sweep.
- The desktop dumps are not bit-identical with the ones before: the Playdate's throws in
  a match changed on purpose.
- **Since the drill runs on (2026-11-16, "Drilling").** The same 150 physics matches
  (seed 2; real / before / after): turns a game 8.9 / 14.6 / 22.7; a baton at field kubbs
  missed 25% / 21% / 24%, took one 49% / 57% / 68%, took two 16% / 18% / 7.5%, three or
  more 10% / 3.4% / 0.9%; cleared the field 83% / 70% / 53% (five kubbs 85% / 82% / 60%,
  eight 68% / 30% / 15%); a base kubb from 8 m 33% / 42% / 41%; the king 84% / 77% / 80%;
  turns from an advantage line 14% / 27% / 44%; kubbs rethrown 14% / 0.4% / 0.5%,
  punishment kubbs 1.3% / 0% / 0%. `tools/clusters.lua` (60 matches; before / after): a
  field kubb's nearest neighbour 20 -> 25 cm, touching 2.5% -> 0.3%, within 15 cm 49% ->
  20%, spread 45 -> 42 cm, largest group 2.4 -> 1.9 kubbs, turns 14.1 -> 22.6. The
  groups are a line or a cluster in the right place, never five kubbs in a row, but
  looser than real tournament groups: real drillers' kubbs end touching (they roll into
  each other), the game's stop 10 to 30 cm short of the one they run into. The swing's
  mistakes hardly matter now (`--drill` 1 / 2 / 3: took two 7.8 / 7.5 / 7.2%, rethrown
  0.5 / 1.0 / 1.1%); the run on is the scatter. Preferring a spot with a lying kubb just
  past it in its lane (a backstop bonus) was tried and not kept: no change in the takes
  (8.0% two, 0.8% three or more). Rethrows stay rare because a kubb is in when either end
  can be raised in bounds and the basket is 0.75 m past the centre line.
- **Into the group (2026-11-16).** Why the run-on groups stayed loose
  (`tools/drillscatter.lua --only 4`, drills thrown while a kubb lay in the far half, 40
  matches): the grid's spots are fixed to the basket, not to the kubbs that are down, so
  only 39% of later drills reached a lying kubb (70% of the rest went past beside it), and
  31% of those that did came down on top of it. The wood is fine: a drill that runs into
  a kubb at under 1 m/s ends touching it 75 to 89% of the time; one that arrives over
  2 m/s bounces off (20%), as it should. So `autothrow.spot` now aims a later kubb of the
  turn into the group first (`intoSpot`, `tune.into` 1, `intoShort` 0.03): just short of
  the near face of a lying field kubb near the basket (`intoShort` short of it; the face
  is the kubb's half length or half width along the throw by how it lies), where the
  drill's mean rest ends it against that kubb. In a line (2 or 3 kubbs) the front kubb, so
  the line grows toward the thrower; in a cluster (4 or more) the kubb nearest the group's
  middle. The same lane and clear rules as the grid's spots (no other kubb within the
  clear ellipse, none lying 12 cm or standing 60 cm short in the lane); with none clear,
  the grid as before. The swing, the drill and the physics are unchanged; the scatter is
  still the run on. Part 4 after: reached a lying kubb 39 -> 51%, landed on it first 31
  -> 6% of those, ended touching 37 -> 47%, the drill's gap at rest 14 -> 6 cm.
  `tools/clusters.lua` (60 matches, seed 2; before / after), lying as the inkast ends:
  nearest neighbour 11.7 -> 6.5 cm, touching 21 -> 35%, largest group 3.3 of 4.8 -> 4.2 of
  5.0 kubbs; standing at the first baton (after `apart` raising): 24.6 -> 17.6 cm, touching
  0.7 -> 2.8%, within 15 cm 30 -> 52%, spread 42 -> 34 cm, largest group 1.9 -> 2.7. 150
  physics matches each, seed 2 (seeds 3 and 4 in brackets), real / before / after:

  | | real | before | after |
  |---|---|---|---|
  | turns a game | 8.9 | 22.7 (23.3, 23.5) | 21.3 (22.3, 20.8) |
  | a baton at field kubbs: missed | 24.7% | 23.8% | 22.1% |
  | took one | 49.4% | 67.8% | 66.0% |
  | took two | 16.0% | 7.5% (7.3, 7.3) | 10.5% (10.3, 10.0) |
  | three or more | 10.0% | 0.9% (0.8, 0.6) | 1.4% (1.4, 1.4) |
  | cleared the field | 83.4% | 52.8% (50.9, 49.5) | 55.3% (53.2, 54.1) |
  | five kubbs | 84.5% | 59.5% (63.6, 58.0) | 68.9% (68.1, 69.9) |
  | eight kubbs | 67.6% | 14.8% (12.9, 13.6) | 22.3% (20.8, 17.6) |
  | a base kubb from 8 m | 32.7% | 40.8% | 41.9% |
  | the king | 83.8% | 79.6% (71.0, 75.7) | 74.3% (74.7, 74.2) |
  | turns from an advantage line | 14.4% | 43.6% | 41.0% |
  | kubbs rethrown | 14.1% | 0.5% | 0.6% (0.7, 0.6) |
  | punishment kubbs | 1.3% | 0% | 0% |

  The groups now form the way Jamie described (later kubbs run into the ones down and end
  against them), but the takes move only part of the way: the defender's `apart` raising
  undoes most of a touching group (lying 6.5 cm apart, standing 17.6). With `--raise
  together` the same aim gives a standing gap of 10.4 cm, two 16.2%, three or more 4.1%,
  15.2 turns. Tried and not kept: `intoShort` -0.1 to 0.13 (no better than 0.03) and -0.2
  (worse: the drill arrives fast and knocks the group apart), and a lower kubb-on-kubb restitution
  (`world.tune.boxE` 0.05 and 0 in a sweep: more drills end touching, the takes no better;
  the physics is unchanged). Rethrows stay rare: moving the basket nearer the centre line
  (`basketY` 4.5 / 4.35 / 4.2) leaves them at 0.8 / 1.1 / 1.2%; only with `spotMinY` 3.9
  and the basket at x 2.25 as well do they reach 8.5% (two 14.1%, three or more 3.4%, 16.9
  turns, 60 matches). That is a play question for Jamie and not in this change.

- **The drill as a plain body, with the bite (2026-11-16, "Drilling").** `make realgames`,
  150 physics matches seed 2 (real / before / after): turns a game 8.9 / 22.4 / 21.7; a
  baton at field kubbs missed 24.7 / 22.3 / 25.2%, took two 16.0 / 10.7 / 4.9%, three or
  more 10.0 / 1.5 / 0.2%; cleared the field 83 / 55 / 49%; a base kubb from 8 m 32.7 /
  33.6 / 33.4%; the king 84 / 77 / 80%; kubbs rethrown 14.1 / 0.6 / 8.1%, punishment
  kubbs 1.3 / 0 / 1.5%. The inkast now pays for its groups the way real players do, but
  the groups are looser (a drill runs on about a metre), so doubles and triples fell. The
  next step is the computer's aim with the new run on (into the group from farther short),
  not the physics.

- **After the physics audit (2026-11-16).** The nine audit items (the foot catch, the
  baton trip, edge contacts with one wood mu, the standing pose, the baton's tumble from
  the release, the landing bump as a tilted normal, the pair bounce, still-air drag, the
  load-scaled grip) and the aim allowance measured again on them ("Drilling", "The aim
  allowance"). `make realgames`, 150 physics matches seed 2 (real / before the audit /
  after the audit with the old allowance / now):

  | | real | before audit | old allowance | now |
  |---|---|---|---|---|
  | turns a game | 8.9 | 21.7 | 18.6 | 18.3 (median 15.5) |
  | a baton at field kubbs: missed | 24.7% | 25.2% | 20.4% | 20.5% |
  | took one | 49.4% | | 70.0% | 70.1% |
  | took two | 16.0% | 4.9% | 8.8% | 8.7% |
  | three or more | 10.0% | 0.2% | 0.7% | 0.7% |
  | cleared the field | 83.4% | 49% | 57.1% | 56.5% |
  | five kubbs | 84.5% | | 69.3% | 68.9% |
  | eight kubbs | 67.6% | | 10.7% | 7.7% |
  | a base kubb from 8 m | 32.7% | 33.4% | 32.1% | 33.0% |
  | the king | 83.8% | 80% | 81.4% | 80.5% |
  | turns from an advantage line | 14.4% | | 38.6% | 39.4% |
  | kubbs rethrown | 14.1% | 8.1% | 7.9% | 5.6% |
  | punishment kubbs | 1.3% | 1.5% | 1.6% | 1.1% |

  The re-measured allowance moves only the rethrows (a drill aimed short no longer ends
  short of the line as often). `tools/clusters.lua` (60 matches, seed 2; old allowance ->
  now): standing at the first baton, nearest neighbour 37.3 -> 35.5 cm, within 15 cm 22.5
  -> 23.6%, spread 64 -> 60 cm, largest group 1.6 -> 1.7; lying as the inkast ends 15.9 ->
  15.6 cm, touching 13.6 -> 14.6%, largest group 2.7 -> 2.8; turns 18.4 -> 17.8.
  `tools/physmatch.lua --n 40 --seed 2`: 17.8 turns, field 80%, base 40%, king 38 of 49,
  169 of 3108 drilled kubbs rethrown. Still off, biggest first: three or more with one
  baton (0.7% against 10%) and two (8.7 against 16), so fields of six and up are cleared a
  fraction as often (eight: 7.7% against 68%) and games run twice as long. The groups
  are the cause: drilled kubbs lie 15.6 cm apart and stand 35.5 cm apart once raised
  apart. Sweeps (clusters, 60 matches; nothing kept): `--raise together` 15.7 turns, two
  13.2%, three or more 1.8%, standing gap 24.2 cm; with `--baton 0.5` as well 14.5 turns,
  two 14.9%, three 2.3%; the drill's release scatter halved (`pitchSdDps` 15, `yawSdDps`
  7.5, `noseSdDeg` 2) standing gap 30.7 cm, rethrown 1.7%, two 10.2%; `drillScale` 0.1,
  `drillNerves` 0.5 or 0.25, `scatterJerk` 0 or `world.pairE` 0.15 change nothing that
  matters (two 7.1 to 9.3%, three or more 0.3 to 1.0%).

### Nerves

Added 2026-11-16. Before it nothing but the swing's shake put a throw left or right. So a
clean swing was a perfect throw at any range, for the player and the computer alike.
The computer's misses came from a synthetic swing whose mistakes autothrow scaled by
range. Now one model in `core/throwplan` serves both throwers.

- **The model.** `plan.launch(sol, r, opts, out)` with `opts.nerves` makes two draws, each
  a unit normal:
  - `sideDeg = pull x lateralDeg x shake cost + z1 x sdSide`, an angle in degrees added to
    the swivel. Because it is an angle, the miss in metres grows with the range.
  - `lenShare = z2 x sdLen`, never under `lenMin` -0.5. The speed is multiplied by
    `sqrt(1 + lenShare)`, so the carry is about `lenShare` longer or shorter.
  - `sdSide, sdLen = plan.nervesSd(level, back, shake, over, kubb)`. That is the level's
    `nervesDeg` and `nervesLen` times effort, times roughness, times overpower:
    - effort is `1 + effortGain x (plan.reach(back) / effortRefM - 1)`, never under
      `effortMin`. The tunes are 2.5, 8 m and 0.15. So 6 m gives 0.375 and 10 m gives
      1.625, and anything at 5.2 m or under is the floor.
    - roughness is `1 + roughGain x shake`, with `roughGain` 1.
    - overpower is the shake's own multiplier `m`.
    - A drilled kubb also takes `drillNerves` 1.
- **Levels** (`plan.levels`, first guesses):

  | Level | nervesDeg | nervesLen |
  |---|---|---|
  | beginner | 1.6 | 6% |
  | club | 0.8 | 3% |
  | pro | 0.5 | 2% |

  Each is 1 sd for a baton reaching 8 m.
- **Where the draws come from.** `opts.nerves` can be:
  - nil or false: none. This is the default, so every caller and test that does not ask
    gets the plan's clean throw.
  - a stream (`plan.rng`): two draws from it. The computer's `autothrow.choose` passes
    its own `r`, the match's seeded stream, at scale above 0.
  - true: a stream seeded from the swing and the plan (`plan.swingSeed`, a hash of the
    back, release, flick, shake, target and stance). The player's throws use this.

  A recorded match replays from its recorded launch either way.
- **Verdicts.** `out.sideM` and `out.lenM` give the miss at the planned distance, in
  metres. `out.sideV` is -1, 0 or 1: PULLED LEFT, STRAIGHT (within `straightM` 6 cm) or
  PULLED RIGHT. `+` is right, as for the swivel. `out.lenV` is -1, 0 or 1 (within
  `longM` 30 cm). It goes in the trace but is not shown, because the power cell already
  says SHORT/LONG for the swing.
  - `plan.verdictText` returns the side as a fourth value, and `plan.sideText(v)` gives it
    alone.
  - `hud.verdicts(powerV, releaseV, steady, sideV)` draws a fourth cell. The plate is
    sized to the longest word in each cell plus `pad` 4, about 243 px from x 73, which
    stops short of the clock. With no `sideV` it draws the old three-cell plate.
- **The scene.**
  - `throw.nerves` (true) or `s.nerves` switches the player's nerves.
  - The self-test runner sets `throw.nerves` from the scenario's `nerves` field (off
    unless it asks), so a scripted clean swing stays the plan's clean throw.
    The device autobench's hit throw sets `s.nerves = false` for the same
    reason, so its impact and rest timings stay comparable.
  - `s.vSide` holds the verdict.
  - `s.last` and the trace line carry `sideDeg`, `lenShare`, `sideV` and `lenV`.
  - Self-test `nerves` shows the clean planned swing of `clock-throw`, which now goes
    1.42 degrees right and 0.5% long: ON ON STEADY PULLED RIGHT, and a miss (since the
    clean throw is aimed through the kubb at half its height, "Aimed through the piece",
    the draws fall differently: 0.46 degrees right and 3% short before, which clipped b3).
- **The aim fan** was tried and dropped. `plan.spread(sol, range, level)` and
  `plan.fan(sol, px, py, tx, ty, level, out)` give the spread and its two edges at the
  target. Drawn as two dotted ground lines from the thrower's feet, it read as a narrow
  lane: at club level 1 sd at 8 m is about 10 cm, inside the target circle. The geometry
  stays in core for the web or a later try.
- **What it replaced in `core/autothrow`.** The range scaling is gone (`rangeRef` 7,
  `rangeMin` 0.45, `rangeMax` 1.2), and so are the old copy of the stream (now
  `autothrow.rng = plan.rng`, the same numbers) and the shake as the only sideways error.
  Changed or kept:
  - The synthetic swing is half as rough: `backSd` 5 -> 2.5, `releaseSd` 9 -> 4.5,
    `shakeMax` 0.44 -> 0.22. The nerves now do most of the missing.
  - `drillScale` 0.2 stays: the computer drills with a steadier hand than it throws.
  - `laneHalf` and `laneDeep` are unchanged. There is no `laneAim` or `laneLong` to try
    again.
- **Measured.** `make realgames`: 150 physics matches, seed 2, against the 150 real
  games. Before is main at the start of this change.

  | | real | before | after |
  |---|---|---|---|
  | turns a game | 8.9 | 21.3 | 22.4 |
  | a baton at field kubbs: missed | 24.7% | 22.1% | 22.3% |
  | took one | 49.4% | 66.0% | 65.5% |
  | took two | 16.0% | 10.5% | 10.7% |
  | three or more | 10.0% | 1.4% | 1.5% |
  | cleared the field | 83.4% | 55.3% | 54.8% |
  | one field kubb: batons to clear | 1.7 | 1.2 | 1.1 |
  | five kubbs cleared | 84.5% | 68.9% | 62.8% |
  | eight kubbs cleared | 67.6% | 22.3% | 26.0% |
  | a base kubb from 8 m | 32.7% | 41.9% | 33.6% |
  | a base kubb from an advantage line | 51.7% | 80.0% | 84.6% (227 batons) |
  | the king | 83.8% | 74.3% | 77.4% |
  | turns from an advantage line | 14.4% | 41.0% | 41.4% |
  | illegal throws | 0% | 2.4% | 0.7% |
  | kubbs rethrown | 14.1% | 0.6% | 0.6% |

  Probe at club (300 throws each, own set-ups; before / after): a base kubb from 8 m
  41% / 32%, from the advantage line 73% / 73%, a lone field kubb 4 to 7 m out 82% /
  82%, the king 79% / 82%.
- **What the range model cannot do.** The 8 m base rate is on target, and the field game
  and the king are no worse. The base rate from the advantage line stays far above the
  real 52%. Those throws are 5 to 7 m, the same range as most field throws, so nerves
  that hit 52% there miss field kubbs far more than real players do. Two tries were not
  kept:
  - Gentler effort (`effortGain` 1 to 1.2, floor 0.35 to 0.4, club 0.7 to 0.75 degrees
    and 4%) brought the advantage line to 62 to 66%. But field misses rose to 30%, the
    field was cleared 49 to 51% of the time and the king fell to 62 to 69%.
  - A lane aim with a longer lane (`laneAim`, `laneLong`) does not exist in this code to
    rerun.
  Real players likely throw differently at a base kubb from the line, which is a play
  question. Seeds 3 and 4 were not run.

### The baton's tumble

Changed 2026-11-16 (physics audit item 5). Before it the end-over-end rate was a line in
the launch speed alone (`tumbleV1`..`tumbleAt2`: 4.5 rad/s at 4 m/s to 7 at 9.2, clamped 3
to 9). Neither the swing nor the nerves moved it, so a given distance and arc always
landed the baton at the same angle. Real batons vary most in how much they turn, and that
decides an end-first landing or a flat one.

- **Where the numbers come from.** No published measurement of kubb baton spin was found
  (a web search on 2026-11-16 found only the rules: the baton is held by one end, thrown
  underarm, and may turn only end over end). So the range is reasoned from the throw:
  - Held by its end and swung underarm, the baton turns with the hand. With a locked
    wrist that is the arm's rate, the baton centre's speed over `armR` 0.9 m (shoulder to
    the baton's centre: arm 0.65, hand 0.1, half the baton 0.15). That is 4.3 rad/s for a
    2 m lob (3.8 m/s) and 9.8 for an 8 m throw (8.8 m/s).
  - Throwers check or add to it with the wrist, `wristShare` 0.5 of it either way, and
    aim the turn: kubb players speak of about one turn over the flight on a good throw.
    `tumbleTurns` is 1.1, a little over one, which is also where the old table sat at
    8 m (1.09 to 1.16 turns), so the landing measures below held. At 1.0 the probe's
    sweep toppled 79% against 88% and the end-first landings changed character (2 of
    200 lost their spin against 24 of 133); at 1.2 no throw in the sweep landed end first.
  - So 8 m at 3 o'clock is 6.5 rad/s over 1.07 s; 8 m at 4 o'clock 7.0; 9.4 m at half
    past 1 5.2 (the wrist's floor: 1.22 turns); a 2 m lob 6.4 (the wrist's ceiling: 0.63
    turns). The whole range a game throws is about 4 to 10 rad/s.
- **The model.** `plan.tumbleFor(speed, loftDeg)` is `2 pi tumbleTurns / T` for the clean
  flight's time `T` (`plan.flightTime`, flight.predict), held to `arm (1 - wristShare)` ..
  `arm (1 + wristShare)`. `plan.solve` puts it on a baton's solution as `sol.tumble` and
  `sol.flightT`. In `plan.launch` the release sets what the throw gets:
  - the flick's share of it (`flickFrac`: a slow flick is a slow hand and wrist);
  - with nerves, a third seeded draw after the side and the length: `zt x sdTurns` turns
    over the planned flight, `sdTurns` the level's `tumbleSd` times `1 + roughGain x shake`
    times the overpower multiplier (no effort term: the wrist's timing, not the power).
    A drilled kubb makes no third draw, so a drill takes the same two draws as before.
  - never under `tumbleMin` 0 (no backspin). `out.sdTurns` is the sd it had.
  - An early or late release changes the loft and so the flight, not the rate: the turns
    change with it.
- **Levels** (`tumbleSd`, turns, 1 sd; first guesses): beginner 0.2, club 0.1, pro 0.06.
  Club 0.15 was tried first: the computer's king rate fell from 82% to 71%
  (`tools/batonprobe.lua --rates 400`), at 0.08 79%, at 0 82%.
- **The aim** does not depend on the tumble: `plan.solve` aims the baton's centre
  (flight.predict is drag free), so the computer's aim is unchanged. The flight time it
  turns over is the time to the aim height (`sol.flightT`; "Aimed through the piece").
- **Measured** (club; before -> after):
  - `tools/batonprobe.lua --rates 400` (the sweep has no nerves, so it tests the plan's
    rate alone): touched and toppled 89% -> 90% (696 -> 790 touched), fast and left
    standing 30 -> 25, end-first landings that lost three quarters of their spin 17% ->
    22%; the computer at base kubbs 32% -> 29%, a field kubb 84% -> 84%, the king 82% ->
    78%.
  - `tools/physmatch.lua --n 40 --seed 2`: 19.0 -> 17.3 turns a game; base 40% -> 39%,
    field 76% -> 77%, king 35/43 -> 38/50.
  - `make realgames` (150 matches seed 2; real / before / after): turns a game 8.9 / 21.7
    / 17.7; the team that threw first won 55% / 38% / 46%; ended on the king 100% / 82% /
    95%; a baton at field kubbs missed 24.7 / 25.2 / 22.6%, took two 16.0 / 4.9 / 5.7%,
    three or more 10.0 / 0.2 / 0.3%; cleared the field 83 / 49 / 57%; a base kubb from 8 m
    32.7 / 33.4 / 30.7%, from an advantage line 51.7 / 62.2 / 67.6%; the king 83.8 / 79.9 /
    76.3%; turns from an advantage line 14 / 46 / 39%.
  - `make bench`: no step cost (the tumble is worked out once a throw, outside the step).
- **Tools.** `tools/batonprobe.lua --set plan.tumbleTurns=1.1` tries a `plan.tune` value.
  `tools/compound.lua` and `tools/tiltgroups.lua` take the plan's rate at each loft.

### Aimed through the piece

Tyler's play test (2026-11-16): "all of them went clean over the field kubb". A clean
baton was aimed at the target's foot: its centre came down at z = 0 on the kubb's centre,
so it met the kubb low, often landed short of it on an end, bounced and went over.

- **The aim** (Jamie's call): with the circle on a standing kubb or the king (within the
  scene's `snapRadius`, or the computer's target), the clean throw aims the baton's centre
  through the piece at `plan.aimZFor(kind)`, `aimHeightShare` (0.5) of its height: a kubb
  0.075 m, the king 0.15 m. `plan.solve` takes `q.aimZ` and carries to
  `flight.tune.handHeight - aimZ` (no extra carries a frame); `sol.aimZ`, `sol.flightT`
  (to that height) and `sol.tumble` follow it. At the same loft a higher aim needs a little
  more speed and less time. A circle on no piece, and every drill (`drill.solveAt`), keeps
  z = 0. `autothrow` sets the same aim for the computer. `tests/lua/test_aimheight.lua`;
  `lua5.4 tools/aimsweep.lua [--ranges] [--release] [--seeds] [--set
  plan.aimHeightShare=0]` measures it (0 is the old aim at the foot).
- **Measured** (before -> after):
  - `tools/aimsweep.lua`, a lone kubb on grass, release 60 (loft 22), 8 seeds x 5 tumbles
    (0.8 to 1.2 of the plan's) a cell, the aim moved -0.4 to +0.2 m along the line; toppled
    at -0.4 / -0.3 / -0.2 / -0.1 / 0 / +0.1 / +0.2 m and overall, then missed over / short
    of 280:

    | range | aim | -0.4 | -0.3 | -0.2 | -0.1 | 0 | +0.1 | +0.2 | all | over / short |
    |---|---|---|---|---|---|---|---|---|---|---|
    | 3 m | foot | 45 | 52 | 60 | 92 | 100 | 100 | 100 | 79% | 6 / 54 |
    | 3 m | mid-height | 48 | 58 | 88 | 100 | 100 | 100 | 40 | 76% | 32 / 35 |
    | 5.27 m | foot | 52 | 78 | 75 | 95 | 80 | 100 | 100 | 83% | 33 / 15 |
    | 5.27 m | mid-height | 72 | 78 | 80 | 80 | 100 | 100 | 80 | 84% | 39 / 5 |
    | 8 m | foot | 80 | 90 | 75 | 80 | 80 | 100 | 100 | 86% | 38 / 0 |
    | 8 m | mid-height | 80 | 70 | 80 | 92 | 98 | 100 | 100 | 89% | 32 / 0 |

    The clean throw at 5.27 and 8 m now takes the kubb (80 -> 100%, 80 -> 98%); a throw
    20 cm long from 3 m now sails over it more often (100 -> 40%).
  - `tools/batonprobe.lua --rates 400`: the sweep is unchanged (its own aim at the foot:
    826 touched, 93% toppled); the computer at base kubbs 31% -> 28%, a field kubb 85% ->
    93%, the king 80% -> 95%.
  - `tools/drillscatter.lua --only 3`: unchanged to the digit (drills keep their aim).
  - `make realgames` (150 physics matches, seed 2; real / before / after):

    | | real | before | after |
    |---|---|---|---|
    | turns a game | 8.9 | 18.3 | 19.6 |
    | won by the team that threw first | 55.3% | 52.0% | 44.0% |
    | ended on the king | 100% | 92.7% | 88.0% |
    | a baton at field kubbs: missed | 24.7% | 20.6% | 14.2% |
    | took one | 49.4% | 70.1% | 72.2% |
    | took two | 16.0% | 8.7% | 12.3% |
    | three or more | 10.0% | 0.7% | 1.2% |
    | cleared the field | 83.4% | 56.4% | 62.1% |
    | five kubbs | 84.5% | 68.8% | 87.2% |
    | six kubbs | 78.6% | 44.7% | 65.4% |
    | eight kubbs | 67.6% | 8.2% | 16.3% |
    | turns from an advantage line | 14.4% | 39.4% | 34.0% |
    | a base kubb from 8 m | 32.7% | 33.0% | 29.5% |
    | a base kubb from an advantage line | 51.7% | 71.5% | 68.2% |
    | the king | 83.8% | 80.3% | 95.0% |
    | kubbs rethrown | 14.1% | 5.7% | 6.0% |
    | punishment kubbs | 1.3% | 1.1% | 1.0% |
    | illegal throws | 0% | 0.7% | 0.6% |

  - Self-tests: `aim-arc`, `camera-swing`, `clock-throw`, `clock-plan`, `hit`, `miss`,
    `field`, `king`, `low-hard`, `nerves` and `flight` pass.
- **Still off.** The computer now hits the king more often than tournament players (95%
  against 84%) and misses field kubbs less (14% against 25%); base kubbs stay near real
  play. The nerves and levels are not retuned here.
- **The end-first bounce** (looked at, not changed). A baton landing end first on grass
  rises off the ground at up to about 1 m/s. Set down end first at 4 m/s down (flat and
  textured grass): straight down and not turning it plugs (0 m/s); leaning 20 degrees with
  4 m/s forward 0.35 m/s, with its spin 0.91; leaning 10 degrees, spinning, 5 m/s forward
  1.94. With the ground's bounce `e` set to 0 those are 0, 0, 0.77; with the bite at 0
  about the same. So part is the forward speed vaulting over the planted end (mechanics)
  and part the ground's bounce, which the dig takes away only on a steep strike. A
  pointed hardwood end may plug more than that on a leaning strike, but there is no
  measured baton-on-turf figure to tune to, so it stays.

### What scatters a drilled kubb

Since 2026-11-16 (Jamie's words in "Drilling") a drill turns in the air and runs on, so
the first two findings below are history: they are what made the computer's lines too
perfect. Now (`tools/drillscatter.lua`, the same runs): with no mistakes it lands 5 cm
(sd) long or short and 2.5 across, runs on 31 cm (sd 32) and 17 across, and rests 27 cm
from its mark, 25% over 30 cm (textured grass); at the game's drill (x0.2) 28.5 cm and 29%;
at a baton's full mistakes 50 cm and 57%. In 40 matches (3780 drills) 47% go at the basket
itself and 53% at a spot beside the group; 66% touch nothing and rest 25 cm from the mark
(23% over 30), 34% touch a piece and rest 31 cm away (35% over 30); a touched piece moves
4 cm on average (12% over 10 cm). Since the computer drills into the group (2026-11-16,
"Tuned toward the real games"), 3535 drills: 21% at the basket, 79% at a spot by the group
(into it or beside it); 57% touch nothing and rest 24 cm from the mark (19% over 30), 43%
touch a piece and rest 19 cm away (17% over 30: the mark is now where the kubb it runs
into stops it); a touched piece moves 5 cm on average (16% over 10 cm). Parts 1 and 3 are
unchanged (the clean drill and the physics are). Part 4 (`--only 4`) follows the drills
thrown while a kubb lies in the far half: whether they reach a lying kubb or land on one,
their speed when they touch it and how often each speed ends touching, the gap at rest,
how far the struck kubb moves, and for those that never reach one whether they stopped
short, beside or past (figures in "Into the group"). Part 3 (`--only 3`, new) throws the plan's clean drill
onto 12 markers x 24 grounds and reports its attitude at release and at the touch, the
run on (mean, sd, p10, p50, p90, max, dead stops), the rest's pose and yaw, and the time
from touch to rest, and the mean rest along the throw from the mark; the figures are in
"Drilling". Part 5 (`--only 5`, only when asked) measures the aim allowance,
`drill.tune.slide` ("The aim allowance"), and prints it as the table takes it.
`--set name=value` sets a `drill.tune` number (`auto.name` an `autothrow.tune` one),
`--surface` and `--grounds` narrow parts 3 and 5.

`lua5.4 tools/drillscatter.lua [--n 300] [--matches 40] [--seed 2]` (Jamie approved the
measuring, 2026-11-16; no game changes). Part 1 throws the computer's drill at the basket
in an empty half and splits its miss into the air (where it first touches the ground
against its mark) and the ground (from there to rest), with the swing's mistakes scaled
and the ground flat or textured. Part 2 follows every drill of 40 physics matches.

- **The ground does not scatter a clean drill** (until 2026-11-16). With no mistakes it rests 0.4 cm from its
  mark on every one of 300 grounds (sd 0.1 cm): a drill plugs where it lands (it travels
  8 cm back from its first touch, the same every time). The patches change nothing a
  watcher could see.
- **The swing scatters it along the throw, not across.** At the game's drill (`drillScale`
  0.2) it lands 8.7 cm (sd) long or short and 1.1 cm left or right, and rests 4.4 cm from
  the mark on average, 1% over 30 cm. At a baton's full mistakes: 31 cm along, 5 across,
  27 cm from the mark, 27% over 30 cm. Distance is the backswing and the flick; the only
  sideways mistake is the shake.
- **The rest is wood.** In matches 29% of drills touch a piece on the way (1127 lying
  kubbs, 35 standing in 2485 drills): those rest 20 cm from their mark on average and 20%
  of them over 30 cm, against 5 cm and 1% for the 71% that touch nothing. A touched kubb
  is moved 8 cm on average, 29% of them over 10 cm. The spots are a kubb's length and a
  centimetre apart along the throw and the drill is 8.7 cm long or short, so it clips its
  neighbour about as often as that predicts.
- 24% of drills go at the basket itself (the first of a group), 76% at a spot beside it.
- So what loosens the game's groups now is, in order: drills clipping the kubbs already
  down, then the power error along the line. Not the ground, and not sideways aim.
- Flat ground (no texture) is not tighter: with no grass to hold it, the rare shaky drill
  rolls on (across sd 15 cm at the game's drill against 4 textured).
- Jamie (2026-11-16): "Real defenders raise kubbs away from combos." The engine's
  default raising policy (`apart`: the end farthest from the nearest other kubb) stays.
  A stricter rule was tried and not kept: a kubb in line along the throw counted as
  nearer (its distance up the pitch times 0.5, and 0.25), so a raised kubb leaves the
  line a baton carries along. Over 150 physics matches, seed 2 (real / `apart` / 0.5 /
  0.25): turns 8.9 / 14.6 / 16.6 / 17.9; batons that took two 16 / 18 / 16.5 / 16.6%;
  three or more 10 / 3.4 / 3.3 / 3.2%; cleared the field 83 / 70 / 63 / 62%. It moves the
  game away from real play. The defence is not where the gap is: tournament throwers
  take triples off defenders who raise well, so the missing triples are the attack's
  (how tight the drills are, and batons thrown at the line of a group).
  `tools/physmatch.lua --raise apart|together` picks the policy for a run.

## Throwing order

Teams of one to six (docs/PLAYERS.md, the plan for saved players and team pass and play;
step 1 is built). `core/order.lua` (`tw.order`, pure, `test_order.lua`) decides who throws
every baton and kubb before the throw, within Rules V4.0 as far as a team's size allows:

- **II.B.5**: a player throws at most `order.cap(n, batons)` = max(2, ceil(batons / n))
  batons a turn (one player all six, two three each, three to six two each).
- **II.A.4**: the opening's two batons by two different players and its four by at least
  three (`order.distinct`, fewer for a smaller team).
- **Blocks**: each team has a rotation (its players in order); a turn's batons are dealt
  from it as evenly as possible over as many players as there are batons
  (`order.split`: 2, 2, 1, 1 for four players), a player's batons in a row, so the
  Playdate changes hands as few times as the rules allow. The next turn starts past the
  players who threw an extra baton (past everyone dealt when all threw the same): the
  doubles go round the team, and in the opening whoever did not throw opens the team's
  next turn.
- **The inkast**: one inkaster a turn (first throws and rethrows), by default the turn's
  first baton thrower (`o.inkaster`).
- **Changes**: `order.change(o, n, pid, thrown)` gives baton n to another player, swapping
  with that player's first later baton, refused (`team`, `cap`, `distinct`, `thrown`) if
  the turn would break a rule; `order.setInkaster(o, pid)`.
- `order.thrower(o, g)` deals the engine's turn when it is new (`order.sync`) and says who
  throws what `g:need()` asks for (the next baton's thrower also while the defender
  raises). The state is plain tables (`o.A`, `o.B` = `{ ids, start }`, `o.turn`, `o.deal`,
  `o.inkaster`), so `core/save` keeps it as `m.order`; a match saved without one starts a
  fresh order.
- `order.checkSheet(g)`: every turn of a finished sheet against both rules and the teams
  (`kubb.js` checks neither); `test_games`, `make games` and `tools/physmatch.lua` run it.

## Saved players

docs/PLAYERS.md (the agreed plan; built). Pure: `core/roster.lua`
(`tw.roster`, `test_roster.lua`) and `core/history.lua` (`tw.history`, `test_history.lua`);
the datastore part is `source/players.lua` (`tw.players`).

- **A player** (`core/roster`): `{ key, name, id, level, made, last, totals }`. `key` is
  `p<n>`, never reused (`r.nextKey`); `name` keeps `core/names` rules; `id` is
  `notation.baseId(name)` and unique on the roster (`roster.canName`: `empty`, `taken`,
  `full`), so a player has the same id in every game file; `level` is one of
  `tw.plan.LEVELS` (the throw's); `totals` are counters (`roster.TOTALS`: games, wins,
  resigned, batons, hits, field, base, kings, kingMisses, illegal, I, R, P, Q). At most
  `roster.tune.max` (40). `roster.valid(d)` cleans what the datastore gives back (never an
  error at launch); `roster.sorted` is most recently played first.
- **A history** (`core/history`, one file per player): the last `history.tune.games` (20)
  games `{ d, f, team, side, res, vs, b, h, k, lv }`, drill records as `core/drills.record`
  keeps them (by drill id), and the last 10 level changes. `history.gameStats(g)` reads a
  finished sheet by player id (a baton with `E` is not a hit, as in kubb.js);
  `history.foldGame(r, hs, g, { keys, levels, date, file })` adds a game to the saved
  players in it (`keys`: player id to roster key; guests and the Playdate have none);
  `history.foldDrill`, `history.setLevel` (logs the change).
- **Files** (`source/players.lua`): datastore `players` (the roster, about 300 bytes a
  player) and `player-<key>` (a history, about 3 KB); self-test runs use `selftest-`
  in front of both. `players.load()` makes the roster the first time from the old files:
  the names typed for matches (`names`) become players (the defaults aside), and the drill
  records (`drills`) go to the first of them (`You` when there was none); the old files
  are left as they were. `players.today()`, `players.now()` give the dates.
- **PLAYERS** (`scenes/players.lua`, the title's fourth item; no board, the Drills board's
  look): the roster on a black panel (+ NEW PLAYER, then the players most recently played
  first, each with their level) and the chosen player's figures (games, wins, hit rate,
  kings, kubbs in, the last ten games as bars of hits over batons with a dot for a win). A
  opens a player: NAME (A: the keyboard), LEVEL (left/right, saved at once and logged in
  the history), GAMES (their recent games), REMOVE (a confirm card: the history goes, game
  files stay), with their drill bests. A new player is typed (scenes/names in mode `"player"`, which refuses a
  taken name and shows why) and lands on their LEVEL row. Self-test `players`.
- **The title** has four items in two rows of two (four do not fit across at 16 px):
  VS PLAYDATE, PASS + PLAY / PRACTICE, PLAYERS; left/right go in reading order, up/down
  change row.
- **TEAMS** (`scenes/teams.lua`, pure state in `core/lineup.lua`, `test_lineup.lua`):
  PASS + PLAY and VS PLAYDATE open it in place of the names step (title -> teams ->
  options -> play). Three columns: Team A, the black bench (START, + PLAYER, + GUEST, then
  the saved players on no team), Team B (the Playdate against VS PLAYDATE). Left/right on
  a player send them toward that side (bench to a team, a team to the bench), anywhere else
  change column; hold A + up/down moves a team's player up or down the order (the order
  is the rotation of "Throwing order"); A on a team's name types it; + PLAYER makes a saved
  player, + GUEST one for this match only (not saved, no key); either goes straight onto an
  empty team (`lineup.seatNew`: Team A, else Team B when it is not the Playdate's), so a
  first match needs no trip through the bench (RC review, 2026-11-15). Six a side
  (`lineup.tune.size`); a player is on one side. A team's name is the one typed, else the
  player's for a team of one, else `Team <first player>`. The lineup is kept per mode
  (datastore `teams`, saved players only) and offered again. `lineup.teams(L)` is
  `core/match`'s teams: players `{ name, key, level, guest }`. Self-test `teams`.
- **In a match** (`core/match`, `scenes/match`): `m.lineup` (`match.lineupOf`) keeps each
  engine player's key, level and guest flag beside the engine's ids; `s.thrower` is
  `{ id, name, key, level }`. The hand-off card names the turn's first thrower (passed the
  Playdate), the team on the throw line, the kubbs' inkaster when someone else, and the
  turn's batons by player (`KIM 2 · MAX 2 · ALEX 1 · DANA 1`). Before a throw by another
  player of the same team the **pass card** (`cards.pass`, `rcards.pass`) says who takes
  the Playdate, for which batons (`BATONS 3 AND 4`) or the kubbs, at what level. On either
  card B opens the **change list** (`match.candidates`, `rcards.change`): the team's
  players, those the rules refuse with why (`TWO BATONS ALREADY`, `NEEDS ANOTHER
  THROWER`); A hands the throw over (`match.changeThrower`), saved at once. The rail reads
  `TEAM: PLAYER` for a team of several. The winner card gives each of the winning team's
  players' hits over batons, three to a line. A finished match is folded into its saved
  players' histories (`core/history.foldGame`, not for scripted matches). No pass card for
  the Playdate's team or with `skipHandoff`. Self-test `match-teams` (three against two,
  one baton handed over, `order.checkSheet` on the sheet).
- **The save** is version 2 (`m.order`, `m.lineup`, `opts.teams`); a version 1 save is
  deleted at launch and never resumed (Jamie, 2026-11-15, decision 9).
- **The throw level** is the thrower's (docs/PLAYERS.md section 6): `throw.levelFor(s)`
  reads `s.level` before the System Menu's "Level". The match sets `s.ts.level` from
  `setup.thrower.level` for every throw (and again when the thrower is changed); a player
  without one (a guest at the default, a match without saved players: nil) and the
  Playdate's team fall back to the System Menu. Practice: left/right on the drills menu
  choose who is practising (NO PLAYER, then the roster; kept in datastore `practice`),
  shown on the menu's rail; a drill run and OPEN PITCH (`main.lua`,
  `drills.practiceLevel()`) throw at that player's level, and the run's record goes to
  their history (`history.foldDrill`); NO PLAYER keeps the System Menu's level and the
  Playdate's own `drills` records. Levels are the throw's: beginner, club, pro.
- **The game file** writes `[Throw Levels "kim pro, max club"]` after `[Mode]` when the
  match had levels (`notation.render`'s `meta.levels`, from `m.lineup`); the vendored
  grammar and kubb.js accept the extra header. The games list's footer adds `3 V 2
  PLAYERS` for teams of several (`gamefile.parse`'s `players`). A player's page has a
  GAMES row: their recent games, newest first, each opening its file's score sheet
  (`scenes/sheet`, the file read from `games/`).

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
  DOWN while the crank is parked behind 6), `gauge` (the prompts: WIND BACK, FLICK!, EASE
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

## The throw

DESIGN 4 is the rule book (Jamie and Tyler, 2026-11-15, after play-testing the stop on the
notch: "one way to throw, modelled on how a real player throws"). The pure parts are
`core/swing` (the crank only: the clock), `core/throwplan` (`tw.plan`: target, stance and
plan to the clock's targets, and a measured swing to a launch) and `render/hud`'s clock,
verdicts and plan chip; `scenes/throw.lua` puts them together, the same for batons and
drilled kubbs. It replaced the stop on the notch, the A/B + crank swivel and loft, the
double taps, `flight.loftBoost` in the player's throw, the loft plaque, the power chip,
the stop and cut flags, the drill callout and the first HOW TO THROW (written again for
this throw: "HOW TO THROW" below).

- **Controls** (aim mode). The d-pad alone moves the target circle (`s.markerX`,
  `s.markerY`, view frame; 0.5 m across, `throw.tune.markerRadius`), faster the longer it
  is held (`drill.tune.markerSpeed` .. `markerSpeedMax`), kept in `drill.clampMarker`'s
  area (3 m either side, 3.5 to 8.6 m out). It stays where the d-pad leaves it: no
  snapping (Tyler's play test, 2026-11-15: the circle locking onto the kubb made 8 m too
  easy and left no way to aim off it for the wind). A circle moved with the d-pad
  (`s.markerSet`) stays put for the team's next throw while a live target stands within
  `keepNear` (1 m) of it, its default arc read again from the nearest target (`retarget`;
  Codex on #98); one never moved starts
  each throw on a live target (`s.markerOn`, kept while that target stands).
  `throw.aimAt` (self-tests, callers aiming at a piece) still snaps onto a standing target
  within `snapRadius` (0.25 m; `plan.snap` over `s.snaps`). A + d-pad walks (`walkSpeed`,
  along the line, back to `backMax`, up to
  the advantage line for a baton, the baseline for a kubb) and sets `s.stanceSet`; until
  then the stance is `plan.stance`, straight behind the circle as far forward as allowed.
  B + up/down taps move the planned release `plan.tune.arcStepDeg` (15) within
  `releaseMinDeg`..`releaseMaxDeg` and set `s.arcSet`; until then the release is
  `plan.arcFor` the kind of target nearest the circle (base 3 o'clock, king half past 3,
  field 4, a drill half past 1). B + left/right taps: a baton's tilt (`s.tilt`, steps of
  `tiltStepDeg` to `tiltMaxDeg`), a kubb's spin (`s.spin`, to `spinSteps` taps). While A or
  B is held the crank does not throw. The swivel is always the plan's (`s.sol.swivel`).
- **The plan.** `replan(s)` (`throw.replan`) runs `plan.solve` into `s.sol` (reused, no
  tables) only when an input changed (`s.planDirty`: the circle, the stance, the arc, the
  projectile) or the level did. A new throw's circle starts on the live target nearest the
  thrower (`retarget`; it stays on its target while that stands: practice after a throw,
  a team's later batons); the arc, tilt and spin start afresh each match throw. Stay put: a
  team's later batons of a turn keep a stance walked with A. AROUND THE PITCH gives its
  own stance (`setup.playerX`). For self-tests and callers: `throw.aimAt(s, x, y)` (the
  circle, snapping onto a standing target within `snapRadius`), `setStance`, `setArc`, `setTilt`, `setSpin`.
- **The level.** `throw.levelFor(s)`: `s.level` (a named player's, later) or `throw.level`,
  which `main.lua` sets from the System Menu's "Level" (`beginner`, `club`, `pro`; the
  datastore "level", club by default).
- **The throw.** On a release `launch(s, r)` takes `plan.launch(s.sol, r, {projectile,
  tilt, spin, level})` and `fire` launches `world.launchBaton` or `world.launchDrill` with
  its outputs (and the flight prediction the cameras use with the same speed, loft and
  swivel). The swing's let-downs (stopped at or before 6) throw nothing. The recorder adds
  no samples in the swing's cooldown.
- **The Playdate's throws** (`throw.autoLaunch(s, a)`, `s.scripted`): `core/autothrow`'s
  launch as it is, mistakes included (`a.speed`, `a.loftDeg`, `a.swivel`, `a.tumbleRate`,
  `a.tilt`, `a.legal`; a kubb drilled with `a.drill`'s `world.launchDrill` fields, lobbed
  when there is no `a.drill`; `a.drill` with only a circle, the autobench's case, is the
  plan's clean drill onto it). With `a.swing` and not instant the scene goes to mode
  `cpuswing` first: the Playdate's arm on the clock, back to `a.swing.back` over
  `cpuBackShare` of `cpuSwingTime` (0.6 s) and forward to `a.swing.releaseAngle`, then the
  throw, with its dots kept on the clock. `throw.showAim` shows its stance, and its circle
  when `a.plan` says where (`s.cpuTarget`); the clock shows `a.plan`'s targets.
- **The clock** (`hud.clock`, "Drawing speed") is always on in the throw scene: the scene's
  `s.dial` (reused) gets the swing's phase, arm and peak (the idle crank's arm), the plan's
  targets, the dead zone (`swing.tune.startBackDeg`) and overpowered past `overDeg` (150, 11
  o'clock), the last throw's peak and stop as dots (until the next wind-up), and the prompt:
  `WIND BACK` (idle, and winding short of the power target), `FLICK!` (inverted, inside
  it), `EASE OFF` (past it), `CRANK DOWN` (the crank parked behind 6 without arming: it must
  come down through 6 first), nothing during the flick; `WATCH` for the Playdate. In flight
  and at rest the hand stays where the crank stopped. `s.promptText` keeps the prompt for
  self-tests.
- **After a throw** `hud.verdicts(powerV, releaseV, steady, sideV)` (SHORT/ON/LONG,
  LOW/ON/HIGH, STEADY/SHAKY, and the nerves' PULLED LEFT/STRAIGHT/PULLED RIGHT, all
  `plan.launch`'s; "Nerves") shows from rest until the next wind-up, the player's
  throws only (`s.showVerdicts`; a new team's turn clears them). The result flag and the
  slow motion flag sit left of the clock. A drilled kubb's rest distance from the circle (`18 CM AWAY`,
  `s.restText`) is a flag in the plan chip's place (`hud.cutFlag`), at rest and on the next
  aim while no tilt or spin is planned. Decided 2026-11-15: the drill callout went (its
  SHORT/ON/LONG was the power band's, now the verdicts' first cell; its ruler and its 234 px
  plate overlapped the verdicts), and its distance moved to that flag. `hud.planChip` shows
  TILT or SPIN while it is not zero.
- **Readout** (the practice pitch's "Pitch: readout", debug only): `hud.readoutText(s.last)`,
  `back <peak>/<target centre> stop <stop>/<target centre> flick <deg/s> shake <0..1>`, then
  HELICOPTER, and the distance and kubbs down, or a drill's rest distance.
- **Telemetry**: the trace line's result is the swing's fields plus the plan and the launch
  (`writeTrace`, at rest; `core/trace`'s header): `level`, `projectile`, `drillId` (a drill
  run's), `tx`, `ty`, `px`, `py` (from the thrower's line), `plan` and `loft`, `powerLo`,
  `powerHi`, `releaseLo`, `releaseHi`, `planTilt` or `spin`, `launchSpeed`, `launchLoft`,
  `swivelOff` (degrees off the plan's swivel), `tumbleRate`, `tilt`, `legal`, `powerV`,
  `releaseV`, `steady`, the nerves' `sideDeg`, `lenShare`, `sideV`, `lenV`, `distance`, and a drill's `mode`, marker, landing, rest and
  thrower. `frames.jsonl` is unchanged.

## HOW TO PLAY

The rules of Kubb on six cards for someone who has never played (Jamie, 2026-11-15:
"short cards"), written the way a friend explains it on the lawn: plain words, real Kubb
talk, Rules V4.0 as the game plays them. `core/howtoplay.lua` (`tw.howtoplay`, pure,
`test_howtoplay.lua`) holds the cards (`CARDS`: `id`, `title`, `text` paragraphs and what
the little pitch shows: pieces, a throw's arrow, an advantage line) and the paging
(`press`: A and right on, B and left back; B on the first card leaves, A on the last goes
to HOW TO THROW, B on the last is done). `render/howtoplay.lua` draws a card in the
hand-off card's look (white on black, the title in display 32, or 16 when too wide, the
words in the label font wrapped to the column, the pitch from above on the right with
THEM at the top and YOU at the bottom, the page count bottom right) into one 400 x 240
image, and raises an error when the words run past `textBottom`: the `howto-play`
self-test draws every card. `scenes/howtoplay.lua` keeps each card's image once made.

1. THE PITCH: two teams, five kubbs on each baseline, the king in the middle; knock down
   all their kubbs, then the king. 2. BATONS: six a turn, underarm, end over end; a
   helicopter does not count; the 2-4-6 opening. 3. THROW THEM BACK IN: the kubbs you knock
   down come back into your half as field kubbs, stood up where they land; out once is
   thrown again, out twice and you pick the spot. 4. FIELD KUBBS FIRST: a base kubb hit too
   soon is stood back up; field kubbs left standing let the other team step up to the one
   nearest the middle. 5. THE KING LAST: from your baseline once all their kubbs are down;
   too early and you lose, or if a kubb thrown in knocks him over. 6. THE SCORE SHEET: every game
   in Planet Kubb Notation, under the title's System Menu "Games"; A: HOW TO THROW.

## HOW TO THROW

The walkthrough of the clock throw (Jamie, 2026-11-14, of the first one: "an interactive
thing that walks the player through the different steps and meaning of the crank for the
throw"; written again for the clock throw 2026-11-15). It runs over the practice pitch,
so every step is the real thing: the real crank and dial, the real circle, walk and plan,
and real throws at the far base kubbs (recorded like any practice throw). Pure part
`core/howto.lua` (`tw.howto`, `test_howto.lua`); panel `render/howto.lua`; glue in
`scenes/throw.lua` (`throw.showHowTo`, `throw.stopHowTo`, `throw.howtoFrame`).

- **Steps** (`howto.STEPS`, DESIGN 4's order): 1 the crank is your arm (turn it down to 6
  o'clock, not docked: within `howto.tune.bottomDeg`); 2 point and throw (any throw); 3 how
  far back is how far (a throw with the power ON, or `tries` throws); 4 where you stop is
  the arc (the release ON, or `tries`); 5 the d-pad moves the circle (`circleMove` m from
  where it was when the step began); 6 hold A to walk (`walkMove` m); 7 hold B to plan (the
  arc moved and a tilt or spin set); 8 that is the throw. Each step says what to do; once it
  is done it says what it meant (after a throw, that throw's verdicts first: `THAT ONE: ON
  HIGH STEADY`) and A goes on. A quick tap of B (let go within `throw.tune.howtoTap`, 0.3
  s, no d-pad while it was down) skips a step; the last step ends on A or a tap.
- **The panel** (`render.howto.tune`): a black band under the rail (y 14, 64 px: it ends
  above the far base kubbs of the first-person aim), the title in the display font and
  the footer (`TAP B: SKIP`, `A: NEXT`, `A: PLAY`) on its first row, up to three lines in
  the label font; only the title strip while B holds the camera out over the shoulder
  (the plan view's target half starts at y 24). Shown while aiming only (a throw in the
  air is the throw's). One image, redrawn only when `h.rev` changes.
- **The scene** sees the walkthrough's world once a frame (`s.howtoObs`, reused): the crank
  arm, docked, a throw come back to aiming (`s.throws` against `s.howtoThrows`) with its
  verdicts (`s.vPower`, `s.vRelease`, `s.vSteady`), the circle, the stance, the planned
  release, tilt and spin, A pressed and B's tap. `throw.showHowTo` turns a drilling pitch
  back to batons and starts the plan fresh.
- **Where it lives**: the last card of HOW TO PLAY, the drills menu's last item (below:
  A on that card opens the practice pitch with it on, main.lua `"howto"`), and the
  practice pitch's System Menu "Pitch: how to" (chosen while it runs, it ends it). The
  drills menu starts on HOW TO PLAY until HOW TO THROW has been seen: main.lua's `throw.howtoDone` writes the datastore "howto"
  as `{ seen = 2 }` when it ends (finished, skipped through or stopped; not in self-tests;
  0.2.0's walkthrough wrote `seen = true`, so a player who saw that one sees this one).
- Self-test `howto` (above): every step with scripted input fed as the step comes up (the
  throws on the plan's clean swing as it then is, ON ON STEADY), the plan step with B held
  and the camera out, A on the last step, then a second run skipped through with eight
  taps of B; it also checks every line fits the panel in the label font.

## The aim arc

Jamie and Tyler (2026-11-14): "the player should visually see the arc of the baton throw
... like a game of billiards on a computer". While a player aims a baton or a drilled kubb
(not the Playdate's throw), `throw.drawFrame` draws the plan's clean throw over the world
(`drawArc`, outside its caches, no tables): from where the player stands, at the plan's
loft and speed (`arcLaunch`, `s.sol`), onto the target circle (a drill's, 2026-11-15, down
to where the kubb lands short of its circle: `drill.solveAt`'s flight time `sol.T` and
landing `sol.land`, its centre at `drill.tune.landZ`; since 2026-11-16 that is short by the drill's mean run on,
`drill.slideFor`, so the arc ends where it lands and the circle is where it most likely
ends; the circle and the dotted line stay); drawn as the plain parabola from the hand to
that landing in the flight's time, which is within 2 to 4 cm of the flight with the air's
drag (`arcLaunch`); a baton's on a standing kubb or the king (since 2026-11-16) ends at
that piece's near face (`s.aimFace`, set by `replan`) at the plan's aim height
(`sol.aimZ`, "Aimed through the piece"), where the clean throw meets it; dashed (`arcPoints` 24,
every other gap drawn, the first `arcSkip` left out, `arcWidth` 2 px). It shows the plan,
not the throw: the backswing, the flick and where the crank stops still decide it (and the
wind will not show in it).

In first person the arc is nearly edge-on (a line up the middle of the screen through the
circle); the plan view below shows it as an arc. `arc = false` turns the arc off.

## The aim camera

Jamie (2026-11-15, after play-testing the over-the-shoulder crane): "when throwing a baton
we should return to the first person view ... when we hold down B to adjust loft we should
move the camera to that over the shoulder view to see the loft and when B is released come
back to the first person view. Do this for drilling as well", and "Having the camera zoom
out to see more of the pitch". The same for batons and drilled kubbs (`aimCamera` in
`scenes/throw.lua`; the math in `core/camera.lua`, tested in `test_camera.lua`):

- **First person** (the default, `camera.aim` into `s.aimCam`): DESIGN 3's crane straight
  behind the thrower (`camera.tune.aim.side` 0, `back` 3 m, `height` 3.4 m), looking along
  the swivel (the plan's: at the circle), the long lens of the framing rule (the farthest
  live target at least `minTargetPx` tall, `fMin`..`fMax`). It looks `circleBeyond` (1.5 m)
  past the target circle (`camera.lookDistAt`, between `lookMin` and `lookDist`), so the
  circle stays on screen wherever the d-pad puts it. A target close in front (an advantage
  line near the middle: at the long lens it fell under the screen, Codex on #96) is lifted by
  `camera.fitNear`: the circle's near edge stays above `fitBottom` (200), first by raising the
  principal row (to `fitCyMin`), then by widening the lens (to `fitFMin`). The Playdate's aims
  with no circle shown look as before (`lookDistFor` its targets, or `lookDist`).
- **The plan view** (B held, `camera.shoulder` into `s.shCam`, `camera.tune.shoulder`): a
  crane `side` (2.6 m) to the thrower's right, `back` (3.6 m) behind along the aim, `height`
  (3.4 m), turned to the middle of the target half (`lookY` 6 m out, x = 0). Its lens and
  principal point are solved in closed form (a lens shift: verticals stay vertical) so the
  target half (the far baseline `farX` either side, the centerline `nearX`, `pad` beyond,
  the far corners also at `cornerZ`), the planned arc and the circle fill the box
  `left`..`right`, `top`..`bottom` (12..388, 24..200): the longest lens that fits, within
  `fMin`..`fMax` (300..880; it comes out about 340 to 770, far base kubbs 4 to 9 px tall). The
  arc's first quarter (before `throw.tune.arcFitFrom`) is kept inside the sides only: it
  may rise in from the lower edge (`shoulderFit`, scratch arrays, no tables).
- **The swing** (`throw.update`): `s.camMix` goes from 0 (first person) to 1 (the plan
  view) while B is held and back when it is let go, over `shoulder.time` (0.4 s), eased
  (`camera.smooth`); `camera.blend` mixes the two (position, look point and principal point
  straight, the lens in log space). A tap of the arc re-fits the plan view, eased in with
  the time constant `shoulder.refit` (0.15 s; within half a pixel it takes the fit, so the
  camera stops: about 0.45 s), not a jump. The crank throws only with B up, so a throw
  normally starts in first person; one thrown before the swing back has finished starts
  from the camera as it is (the follow camera blends its principal point too). `fire` and
  `throw.prepare` put the mix back to 0. While the camera moves every aim frame redraws the
  world (the frame cache keys on the camera): `camera-swing` counts about 48 graphics calls
  an aim frame with the camera still and about 168 while it moves on batons (a flight frame's
  number), only during the 0.4 s swings and the refit after a tap (`drawcalls`' aim mean,
  no B held, is unchanged: 54.7 before, 54.8 after). With a drill's arc drawn too the
  `camera-swing` means are about 54 still and 173 moving.
- Self-tests: `aim-arc` (first person: the circle on screen and the far base kubb 12 px or
  more; the plan view: the circle on screen and the arc in its box, for targets across the
  half, every release, three stances; then the same for drill circles across the d-pad's
  area), `camera-swing` (first person, half way out, the plan
  view, a tap's re-fit, half way back, first person again, exactly the first frame's
  camera; then a drill's).

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
- **The push** (`core/world`): `world.new{ windX, windY }`. The wind is the air the
  thrown piece's drag acts in ("Physics", the air's drag): `k |r| r` with `r` = wind - v,
  so a zero wind is still air. Over an 8 m baton at 30 degrees (aimed through still air):
  a light cross wind carries it 0.13 m, a strong one 0.35, a strong head wind costs 0.76 m
  and a tail wind adds 0.38; a lobbed kubb (more drag for its weight) 0.20, 0.55, 1.15 and
  0.62. (Before 2026-11-16 the wind pushed with its drag less a still-air drag the game did
  not have, baton k 0.015 and kubb 0.0086: 0.16, 0.44, 0.97, 0.54 for the baton.)
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
`input.swingSteps(back, release, opts)` builds a scripted swing (self-tests, the
autobench): wound `back` degrees behind the bottom, a full flick that stops exactly
`release` degrees past it (`opts`: `frames`, `pause`, `peak`, `lead`, `shaky` for a
stuttered flick); the crank sign is applied for you.

## Tunables

Every number that is a guess lives in one table per module, with a comment:

- `tw.camera.tune` (`source/core/camera.lua`): aim crane (first person), lens range,
  framing rule, how far past the circle it looks (`circleBeyond`), the plan view
  (`shoulder`: crane, fit box, lens range, swing and refit times; "The aim camera"),
  impact camera, follow margins and mid-flight zoom; `tw.camera.minimap` for the minimap.
- `tw.swing.tune` (`source/core/swing.lua`): crank sign (`forwardSign`, the one constant
  to flip if forward feels backwards on hardware), the dead zone (`startBackDeg`), the
  backswing cap, the flick's start and stop speeds (`swingStartDps`, `releaseStopDps`,
  `speedWindow`), the sky ball (`skyDeg`), the cooldown, the flick's power
  (`fullFlickDps`, `minFlickFrac`), the pull and the shake (`roughFull`).
- `tw.plan.tune` (`source/core/throwplan.lua`): the power scale (`reachZeroDeg`, the
  anchors: 9 o'clock 4 m, 10 o'clock 8 m), the loft scale (5 o'clock 12 degrees, 3 o'clock
  32), the default arcs by target (`arc`), `arcStepDeg`, the release's range, `tiltStepDeg`
  and `tiltMaxDeg`, `spinSteps` and `spinPerStep`, the sky ball's extra, the helicopter
  limit, the shake's tilt and pull, overpower, STEADY, the baton's tumble (`tumbleTurns`,
  `armR`, `wristShare`, `tumbleMin`: "The baton's tumble"), the height a clean baton's
  centre goes through a standing piece (`aimHeightShare` 0.5: "Aimed through the piece");
  `tw.plan.levels` (beginner, club, pro: the targets' half widths, the error inside a
  target, the shake and overpower costs, the nerves and `tumbleSd`; `plan.LEVELS` in menu
  order).
- `tw.flight.tune` (`source/core/flight.lua`): gravity, hand height, loft range (5 to 55) and step,
  baton size, wobble. (`boostBelowDeg` and `flight.loftBoost`, the old player's low throw,
  were removed 2026-11-15, as were `swing.tune`'s launch and tumble ranges: the plan's
  scales set the speed, `plan.tumbleFor` the tumble.)
- `tw.scenes.throw.tune` (`source/scenes/throw.lua`): refresh rate, walk speed, how far
  back the player may step, the circle's snap radius (`snapRadius`, `throw.aimAt` only) and how near a live target
  a circle moved by hand must be to stay put (`keepNear`), where the clock shows
  overpowered (`overDeg`), the Playdate's arm on the clock (`cpuSwingTime`,
  `cpuBackShare`), rest hold, practice
  surface, the flight's pacing (`flightRate`, `framePeriod`, `tailPeriod`, `minBudget`;
  `physicsBudget` only for scripted input; see "Playback") and how far ahead the physics
  may record, impact-camera
  slew and baton framing radius, the tossed kubb's tumble (`tossTumble`), the instant
  rest hold, the drilled kubbs kept on the practice pitch (`drillKeep`), the target
  circle (`markerRadius`, `markerSegments`), the aim arc ("The aim arc") and HOW TO
  THROW's tap of B (`howtoTap`).
- `tw.howto.tune` (`source/core/howto.lua`) and `tw.render.howto.tune`: HOW TO THROW's
  pass thresholds (crank at the bottom, tries, how far the circle and the walk must move)
  and its panel ("HOW TO THROW"). `tw.render.howtoplay.tune`: HOW TO PLAY's card layout
  (title, rule, the words' column and bottom, the little pitch).
- `tw.drill.tune` (`source/core/drill.lua`): every drilling mapping (AGENTS.md
  "Drilling").
- `tw.outcome.tune` (`source/core/outcome.lua`): when a body counts as standing, moved or
  turned, and how high a tossed kubb must rest to be on another.
- `tw.autothrow.tune` (`source/core/autothrow.lua`): the computer thrower's level, aim, basket,
  the spot beside the group (`spot*`), the baton's lane (`lane*`), a drill's steadier swing
  (`drillScale`) and the synthetic swing's mistakes. How far off a throw goes with its
  range is the shared nerves (`tw.plan.tune` "Nerves", `plan.levels` `nervesDeg`,
  `nervesLen`).
- `tw.world.tune` (`source/core/world.lua`): step, solver passes, slop and push, contact
  margin, bounce threshold and passes, wood-on-wood friction and bounce (`pairMu`, `pairE`:
  every pair of pieces), sleep and wake
  thresholds, topple angle, out margin, maximum throw time, stake height (0.15 m: a real stake, 6 inches out of the ground).
  `tw.world.surfaces`: one parameter set per ground (grass, sand, snow; ice is a marked
  placeholder): friction, bounce, dig, rolling resistance, and the ground's `texture`
  (Physics, "The ground's texture"). `world.SURFACES` lists the playable ones in order.
- `tw.collide.tune` (`source/core/collide.lua`): `batonRound`, how rounded a box's edges are
  to a baton ("Physics", "Baton hits"). `world.tune.batonTurnHold`: how the ground holds a
  baton's spin.
- `tw.bench` (`source/core/bench.lua`): the benchmark scenario (pieces, throw, seconds,
  and `bench.debris`, the lying batons and kubbs of a full turn).
- `tw.debris.tune` (`source/core/debris.lua`): `matchEps`, how close the engine's pose of a
  piece (a lying tossed kubb, a standing kubb, the king) must stay to the one recorded at
  rest for that exact pose to be used.
- `tw.match.tune` (`source/core/match.lua`): `settleDeg` and `settleGap`, how tilted (0.5
  degrees) or how far off the ground (2 mm) a carried standing piece must be for
  `match.settleStanding` to run it to rest.
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
  (`rail`, `prompt`, `clock`, `verdicts`, `planChip`, `cutFlag`, `flag`, `slow`, ...), and `cache` in each (the
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
- A drilled kubb (`world.launchDrill`) is a plain body released from the swing and
  scattered by seeded normals at launch; the air turns it in flight (`world.aeroTurn`,
  the projectile only) and on the ground it is a kubb like any other ("Drilling").
- **The air's drag** (audit 8, 2026-11-16; before it a throw flew in a vacuum unless there
  was wind). The thrown piece (`w.projectile`, until its first contact) loses `k |r| r` of
  its velocity a second, `r` the air's velocity past it (the wind less its own), `k` = 0.5
  rho Cd A / m per kind (`tw.flight.tune.dragK`, `b.dragK`), right after gravity in both the
  full step and the lone flight (written out in each, no call; they stay identical). From
  the drag tables in White, Fluid Mechanics, Tables 7.2 and 7.3 (after Hoerner), at a
  throw's Reynolds number: the baton, a 0.30 x 0.044 m cylinder turning end over end, Cd
  0.77 side on (L/D 6.8) and 0.95 end on, each times the crossflow principle's mean
  |sin|^3 over the turn (4 / 3 pi): Cd A 0.0049 m^2, k 0.0118 /m; the kubb, a 0.15 x 0.07
  x 0.07 m block tumbling or spiralling about broadside, a quarter of its surface (the
  mean area a tumbling convex body shows) with Cd 1.0: Cd A 0.0130 m^2, k 0.0194 /m. At 10
  m/s that is 1.2 m/s^2 on a baton and 1.9 on a kubb. Small but not nothing: a baton
  aimed 8 m with no drag comes down 0.37 to 0.54 m short (loft 10 to 50), so the aim needs
  3.3 to 4.1% more speed (8.96 to 9.27 m/s at 30 degrees), and a drill aimed to land 6 m out
  0.33 to 0.48 m short (4.2 to 5.1% more speed). It meets the kubbs about 6% slower along
  the ground (7.49 to 7.02 m/s at 8 m on the plan's base arc). Pieces after the first
  contact get none (slow and briefly in the air: a kubb knocked flying at 3 m/s for 0.3 s
  would lose about 5 cm/s). The aim solves with it (`flight.carry`, below). Cost: a square
  root and a few multiplications a step while the piece is in the air (`make bench` with
  the same throw and k = 0 is unchanged: 0.026 ms a step, lone 0.001, air 0.005).
- **The aim's arithmetic** (`core/flight`): `flight.carry(speed, e, h, k)` is how far a
  launch at loft e from h above the ground carries through still air with drag k, and its
  time (midpoint steps of `carryStep` 1/20 s, within 2.5 mm of a fine integration on any
  throw the game makes); `flight.speedForCarry(R, e, h, k)` inverts it (the drag-free speed,
  a scaled step and secant steps to 0.1 um, or until a step stops getting closer, which
  is where the device's 32-bit floats end: 4 or 5 carries; it also returns the flight
  time, which `plan.solve` keeps as `flightT` instead of carrying again). `flight.predict` (the cameras,
  `plan.reachForSpeed`), `throwplan`'s `carrySpeed` (`plan.solve`, `plan.speedFor`),
  `drill.solveAt` (with the kubb's k, to its landing height) and `autothrow.speedFor` all
  use them (a baton aimed at a standing piece carries to `handHeight - aimZ`, its centre
  through the piece at `plan.aimZFor`'s height: "Aimed through the piece"), so a clean
  throw still comes down where it is aimed (the world's centre within
  2 to 4 cm, as before: the fixed step's own error). `plan.solve` costs 11 us (baton) and
  16 us (drill) on the desktop, from 0.7 and 2.1. The power scale is unchanged in metres:
  a backswing carries as far as before and needs a little more speed for it.
  On the device a carry costs about 0.7 ms, and the aim solves every frame the circle or
  the stance moves. The first drag build took the autobench's "aim target" frame from 4.1
  to 10.0 ms of update (32.9 to 27.6 fps). So `plan.solve` makes 6 carries instead of 8
  (desktop results unchanged bit for bit), and the throw scene's arc reads a baton plan's
  `dist` and `flightT` instead of predicting twice a frame. That brings it to 8.6 ms of
  update and 30.5 fps (aim walk 29.7) (2026-11-16).
- **The bite** (2026-11-16, Jamie: "I think we need to add the bite to the ground model…
  it is key… and this is where grass, snow, and sand will act different"). An edge or
  corner that strikes the turf steeply cuts in and is held: a ground contact gets extra
  friction `surf.bite` x ramp x pointed x steep, judged once when the contact first presses
  (the ramp is the dig's: the approach speed past `digSpeed` over `digRamp`, capped at 1;
  `pointed` how much a corner or edge rather than a face meets the ground; `steep` the
  approach speed over the point's whole speed, so a skim barely bites) and kept per corner
  (`b.gBite`), fading by `dt / biteTime` a step while the edge stays down. The patch's
  `digVar` varies it. Grass 0.7 (`biteTime` 0.05 s), sand 2 (0.1 s), snow 0 (packed snow
  lets an edge skate; its plugging is in its dig). Every body has it: batons, lobbed and
  drilled kubbs, the king. Contacts are made before touching (speculative) and an impact
  lasts one step, so the bite is a friction coefficient, not a force cap. Not
  bit-identical: every throw on grass or sand where an edge strikes the ground.
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
  "bench" (shown only with the `debug` flag file, below), runs the identical `core/bench` scenario a chunk of steps per frame, then times
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
    vary by `muVar`, `eVar`, `digVar` (kept per contact in `b.gMf`, `b.gEf`). The patch is
    also tilted: a landing faster than `bumpSpeed` meets a slope of up to `bump` each way
    times its steepness squared (a low skidding drill barely feels it, a baton dropping end
    first does). That step's contact is a kind 4 record: solved like a contact with a still
    body along the tilted normal, stored as the ground's. So the landing is turned and
    nothing is added. Until 2026-11-16 (audit 6) the bump added sideways speed, and over
    180 steep landings a step gained up to 0.35 J. Now the worst step gains 0.6 mJ, which is
    the solver's own residue (0.9 mJ with no bump). Measured against the old bump:
    - end-first batons that lose most of their spin at once: 24% to 15%
    - batonprobe toppled: 88% to 87%
    - the clean drill's run-on (drillscatter 3, cm, loft 47/30): grass 89/156 to 83/155,
      sand 27/47 to 25/45, snow 87/149 to 86/146
    - groundstats hits: grass 9.3% to 11.3%, sand 8.0% to 7.3%, snow 10.0% to 11.3%
  - **Grass holds.** A baton or a lying piece touching the ground loses `drag` of its ground
    speed and spin a second, and `grip` more below `gripSpeed`, so it stops instead of
    creeping. The rates scale with how hard it presses: the step's `load` (above) over its
    weight, never more than 1. A baton propped on a kubb with one end in the grass is held
    less, and a harder push (a landing, a pivot) is left to the contacts' friction. The
    rates were the same however lightly a piece touched until 2026-11-16 (audit 9). Measured
    against the cap and the flat rates:
    - end-first batons that lose most of their spin at once: 13% to 10%
    - batonprobe toppled: 91% to 93%
    - the clean drill's run-on (drillscatter 3, cm, loft 47/30): grass 84/155 to 87/158,
      sand 26/46 to 27/48, snow 88/147 to 89/149
    - groundstats slide: 1.40/0.51/1.74 to 1.46/0.53/1.77 m; hits within a point
    - on an end on sand: 0.010 to 0.013 s a throw (90th percentile 0.017 to 0.037)

    Falling kubbs are left alone (a falling kubb must still fall); a standing one that
    slides is held by its corners' friction, and on snow "A kubb's foot ploughs snow" below.
  - **Snow ploughs** (`plough`, 1/s per m): the drag grows with the distance a piece has
    slid since it last left the ground (`b.plough`, reset off the ground, in the lone
    flight too), so a slide on snow starts slick and ends heavy.
  - **The surfaces.** Grass: high friction, moderate dig, holds. Sand (DESIGN 5): very high
    dig, almost no bounce or slide, soft and packed spots, ridges that turn a landing more,
    drags and grabs hard. Snow (Jamie, 2026-11-14): slick (`mu` 0.25) but soft: a steep
    landing plugs, almost no bounce, icy and soft patches, and it ploughs. Over 400 scripted
    batons (`tools/groundstats.lua --surface`): the slide after touching down is 1.39 m on
    grass, 0.46 on sand, 1.85 on snow; a kubb toppled in 11.5%, 6.0% and 11.8% of throws.
    Since the baton hits pass (below; 300 throws each): 1.76, 0.64 and 1.98 m (1.39, 0.45
    and 1.88 before in the same run); toppled 11.7%, 8.0% and 13.7% (11.7, 6.7, 13.0).
    Physics matches (20 each, seed 7, `tools/physmatch.lua --surface`): 21.1, 29.6 and
    21.6 turns; on sand a baton has to land on its kubb.
  - **Nothing slides on an end**, by friction alone (physics audit item 2, 2026-11-16).
    Until then a baton within 30 degrees of upright sliding on the ground faster than
    `tripSpeed` had spin added toward the way it was going (`trip`, 60 rad/s^2 per m/s,
    120 on sand, 70 on snow) with nothing pushed back and the ground's push ignored. The
    friction at its end already tips it: on grass (0.7) and sand (0.9) a baton leaning
    up to 30 degrees either way cannot stay up (it would need friction under the tangent
    of its lean), so the trip went with no replacement. On snow (0.25) a baton leaning
    back about 14 degrees balances on its end and skates (set down at 4 m/s leaning back
    10 degrees, 0.58 s and 1.58 m on its end without the trip), so a baton on an end
    ploughs snow at its foot like a kubb (below). Measured (a baton set down on an end
    sliding at 0.5 / 1 / 2 / 4 m/s, leaning 10 degrees forward, upright and 10 back, 20
    grounds; seconds on its end, trip -> none): grass 0.08 to 0.40 -> 0.08 to 0.58 s,
    the slides the same within 2 cm (the long ones are at 0.5 m/s, 12 cm); sand 0.07 to
    0.42 -> 0.07 to 0.48 s, within 2 cm; snow 0.09 to 0.43 -> 0.08 to 0.50 s with the
    plough, 0.47 -> 0.48 m at the worst. `tools/groundstats.lua` (300 batons; s on an end
    a throw, slide, toppled): grass 0.007 -> 0.009 s, 1.67 -> 1.64 m, 10.7% -> 11.0%;
    snow 0.006 -> 0.008 s, 1.98 -> 1.90 m, 13.7% -> 13.3%; sand 0.009 -> 0.010 s, 0.61
    -> 0.55 m, 7.3% -> 8.0%. The longer ones are a baton tumbling up over an end and
    falling back, its centre moving at 0.2 to 0.9 m/s, which the trip's spin hurried.
    `tools/batonprobe.lua --quick`: toppled 204 of 233 -> 205 of 229, end-first landings
    that lost their spin 24 of 133 both. `tools/compound.lua --quick` and
    `tools/drillscatter.lua --only 3` unchanged (drills never met the trip). 40 physics
    matches (seed 2): 23.9 -> 25.6 turns, base 36% -> 39%, field 74% both. `make bench`:
    the match case's steps cost the same (ground 0.011, multi 0.017 ms); the bench's own
    throw comes to rest again (1.97 s; 255 collision steps). Not bit-identical: every
    textured throw where a baton slides on an end.
  - **A kubb's foot ploughs snow** (Jamie, 2026-11-15: the texture "does not apply to
    kubbs"; honest since 2026-11-16, physics audit item 1; a baton on an end too since
    item 2). Flat snow's friction (0.25) is
    under the 0.47 a kubb's footprint needs to tip (half its width over half its height),
    so on the corners' friction alone a kubb shoved at its centre glides standing and never
    falls. On snow a standing kubb or the king (within 30 degrees of upright, on the
    ground) whose foot (the point under its centre) slides faster than `footSpeed` (0.3
    m/s) sinks in and ploughs: a resistance at the foot against that slip, at most
    `footMu` (0.3) times the ground's push that step and never past stopping the slip
    (Coulomb, like the corners' friction), so it slows the piece and tips it the way it is
    going. Grass and sand have none: their friction (0.7, 0.9) is past 0.47 already.
    Until 2026-11-16 it was the foot catch, `foot` (grass 25, snow 12) of the slip taken
    away a second whatever the weight, a second grip on top of the corners' friction.
    Measured (a kubb shoved to a speed, 20 grounds; 1 / 1.5 / 2 / 3 m/s; toppled and
    slide; foot catch -> footMu). Snow, at the centre: 55 / 100 / 100 / 100% and 0.16 /
    0.30 / 0.49 / 1.08 m -> 90 / 95 / 95 / 95% and 0.18 / 0.29 / 0.52 / 1.10 m (0% and
    0.20 / 0.46 / 0.82 / 1.86 m with neither); shoved low (3 cm) 30 / 100 / 100 / 100% ->
    55 / 100 / 100 / 100%; a 0.5 m/s nudge stands (0.03 m). A footMu of 0.25 (snow's own
    mu) tipped 50 / 75 / 80 / 80%, 0.4 all of them. Grass without the foot catch: a
    centre shove 100% at 1 m/s and up either way, slides 0.13 / 0.17 / 0.29 / 0.59 ->
    0.15 / 0.20 / 0.33 / 0.64 m; a low shove at 1.5 m/s falls 85% -> 100%; a 0.5 m/s nudge
    stands. Sand unchanged. `tools/groundstats.lua` (300 batons): grass 10.7% -> 10.7%,
    slide 1.67 m both; snow 13.0% -> 13.7%, slide 1.98 m both. `tools/batonprobe.lua
    --quick`: toppled 206 -> 204 of 233. `tools/compound.lua --quick` within its noise
    (four touching end on, all four 20.5% -> 23.3%; three touching 54.8% -> 52.1%); the
    domino table moves in one row (a 1 m/s shove at 8 cm: B falls at 15 cm, not at 7).
    `tools/drillscatter.lua --only 3` run on mean (cm, loft 47 / 30): grass 101 / 175 ->
    102 / 178, snow 110 / 168 -> 103 / 162, sand unchanged. 40 physics matches (seed 2):
    19.0 -> 23.9 turns, base 40% -> 36%, field 76% -> 74% (different games). The match
    case's steps cost the same (`make bench`: ground 0.011, multi 0.016 ms). The bench's
    own throw now leaves the baton wedged on a fallen kubb between two standing ones,
    where the pair contacts' push bias keeps it rocking until `maxTime`, so it runs more
    collision steps (517 against 370) and reads higher per step; the playback calm test
    throws the bench throw at one kubb of the group for that reason. Not bit-identical:
    any textured throw where a standing kubb or the king slides faster than `footSpeed`.
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
- **Baton hits** (Tyler's play test, 2026-11-15: "a baton phased through a kubb", "a fast
  baton barely moved a kubb", "hit twice hard and did not fall", "kubbs feel like they
  glide"). `lua5.4 tools/batonprobe.lua [--quick] [--tyler traces.jsonl] [--rates n]
  [--set name=value]` measures them: a sweep of batons from the baseline at one kubb 8 m
  out (lofts 8 to 50, carries 0.6 m short to 0.35 m long, three grounds), end-first
  landings, a traces file's batons replayed, and the computer's hit rates. No baton passes
  through a kubb (replays of Tyler's 76 batons, with and without wind and debris); three
  things were wrong:
  - **Square edges.** A baton that clipped a kubb's top edge met the top face, normal
    straight up, and pressed the kubb into the grass (it could not tip it with friction
    alone), so it seemed to pass through. `collide.tune.batonRound` (0.01 m): a capsule meets
    a box (a kubb, the king) as a box of half sides 0.01 smaller swept by a 0.01 ball, so an
    edge gives a normal between its faces (`sphereBox`; the contact point stays on the
    baton). Stakes meet boxes square (THE WALL's measurements stand). Boxes meet the ground
    and each other as before.
  - **The bounce.** The restitution passes act on the contacts that bounce and nothing else,
    so a baton's bounce off a standing kubb was applied with nothing holding the kubb's
    footing: part of it drove the kubb into the grass and the ground threw it up the next
    step. Keeping every ground contact in the passes (target 0) fixed that but let a kubb
    tipping onto a lying one sink into it (`test_physics`, the leaner), so it was not kept;
    `pairE` (wood on wood) went from 0.35 to 0.2 instead, which shrinks the bounce that
    escapes. Fixed in the solver on 2026-11-16 and `pairE` is 0.35 again ("The pair bounce
    with its footing" below).
  - **A baton's spin on the ground** was held as one vector by `rollResist`: the angular
    impulse that stops a spin along its own direction. A baton turns most easily about its
    long axis, so any part of its spin along it made that impulse tiny, and a baton landing
    on an end lost all of its spin in the one hard step of the landing and went on without
    turning. Now its spin is held in two parts, each never past stopping: the end-over-end
    turn by the plug (`b.dig`) and `batonTurnHold` (1) of the rolling resistance
    (`surf.roll`), its roll about the long axis by the plug and all of it. The rolling
    resistance is the turf giving under the ground's push, the step's `load`: all of the
    ground's impulse, except in a step where a contact strikes faster than
    `restitutionSpeed`, when only the weight's share. The strike's turn loss is the plug's.
    (Until 2026-11-16, audit 9, a cap of 4 times the weight a step, `rollCap`, kept a
    landing's spike out. It also took a pivot's hard push out.) Boxes keep `rollResist`.
  - **Measured** (the sweep, 747 to 757 throws that touched the kubb; before -> after):
    toppled 90% -> 90%; fast (over 6 m/s at the touch) and left standing 44 -> 29;
    tilted past 25 degrees and back up 8 -> 3; the kubb off the ground (its lowest point
    over 1 cm) 67% -> 65%, for 0.2 s or more 168 -> 140; end-first landings that lost
    three quarters of their spin within 0.05 s 139 of 391 (36%) -> 55 (14%). Tyler's 76
    batons toppled something 42 -> 45 times. A touched king falls 66% either way. Over
    `tools/compound.lua --quick` two kubbs side by side 3 cm apart both fall 5% -> 10%,
    three 11% -> 16%, two in line 30 cm apart 47% -> 32%. Batons keep turning, so they go
    farther on the ground (grass 1.39 -> 1.76 m, `tools/groundstats.lua`) and slide on an
    end as little as before (0.007 -> 0.008 s a throw).
  - **Cost** (`make bench`, desktop): the match case's steps cost the same (lone 0.001,
    ground 0.010 to 0.011, multi 0.014 to 0.016 ms); the bench throw now wakes six bodies
    instead of four (513 collision steps instead of 187), so its own per-step figure reads
    higher for that reason. Not bit-identical: every throw with a baton touching a box or
    the ground, and every wood-on-wood bounce. Box-only scenarios without a bounce over
    0.4 m/s and the lone flight are unchanged (`test_loneflight` holds).
- **Tight rows** (Jamie, 2026-11-15, from a web match: four field kubbs standing in a
  row end on, and "my baton is just bouncing off of them"; "in a tournament I would have
  hit all five down with one baton"). Two things were wrong:
  - **A sleeper was a wall.** A sleeping body is immovable to the solver, and a touch woke
    only the body touched: the kubb the baton struck woke, leaned on its sleeping neighbour
    and stood braced against a wall for that step, so the blow went into the wall and was
    gone (a 1.0 N s blow on the front of four touching kubbs left 0.07 N s in the row), and
    the neighbour woke a step later to nothing. Now a body woken by a touch wakes every
    sleeper it touches in the same step, and so on through the group (`world.step`, after
    the pair loop; `b.wokeStep`). Nothing runs there in a step that wakes nobody, and a
    piece standing clear of the others (over the 2 mm contact margin) is woken as before.
  - **Kubb on kubb friction** was `pairMu` (0.4): a kubb tipped against its neighbour was
    held up by the rub of its edge down the neighbour's face. Two boxes met at `boxMu` (0.2)
    from then until 2026-11-16 ("Edge on edge" below: one friction for all wood again).
  - **Measured** (`tools/compound.lua --quick`, which now sweeps rows of three and four
    end on; before -> after): four touching, any kubb down 26% -> 81% of batons that hit
    the row, all four 0% -> 22%; three touching, all three 1% -> 53%; four 3 cm apart, all
    four 4% -> 24%; two in line and the side by side layouts within 2 points. The
    computer's club throws at the row from that match (400): all four 1% -> 16%, none 44%
    -> 37%; its near-clean throws (200): all four 3% -> 35%, none 23% -> 12%. 40 physics
    matches (seed 2): 25.9 -> 22.5 turns, field kubbs 61% -> 63%. `make bench` is
    unchanged. Not bit-identical: any throw where a woken piece touches a sleeper, or two
    boxes rub. A throw at pieces standing apart that never meet is unchanged.
  - **Pairs the loop passed** (Codex on the web game's sync, 2026-11-15). The pair loop
    skips a pair while both sleep. Two bodies both woken in one step (a baton wakes two
    kubbs that touch each other), or a woken body and a stake, could be such a pair, and
    their contact was missing for that step. The group wake's pass now makes it, once
    (`WT`: where the pair loop was when a body woke; `WPOS`: its place in the queue), and
    wakes nobody for it. The row measurements above are unchanged; 40 physics matches
    (seed 2) 22.5 -> 21.2 turns. Not bit-identical: a step where two touching sleepers,
    or a sleeper touching a stake, wake together.
  - Still true: a baton that clips the top of the front kubb mostly goes over the row, and
    a low sweep slides the row upright more often than it trips it. The foot catch (taken
    out 2026-11-16, "The ground's texture") did not change that on grass: the row shares the blow, moves at a
    quarter of the struck kubb's speed and is stopped by friction within 1 to 2 cm, too
    slow for any foot to trip (a row shoved at 2 m/s: nobody falls, before and after).
- **Edge on edge** (2026-11-16, the physics audit). Box against box made contacts at the
  corners of each box inside the other only, so two kubbs that met where their edges cross
  had no contact there: a kubb lying across a lying kubb at 30 degrees or more fell straight
  through it to the ground, and a kubb tipped into a neighbour turned 20 to 70 degrees sank
  an edge up to 18 mm into it (15 of 45 tips over 5 mm; `tests/lua/test_physics.lua` has
  both). `collide.boxBox` now runs the standard separating-axis test with the nine edge
  axes as well as the six face axes (Ericson, Real-Time Collision Detection 4.4 and 5.1.9):
  - an edge axis that parts the boxes by the margin ends the test (no contacts);
  - if the boxes overlap least along an edge axis (by `EDGE_TOL`, 0.5 mm, less than any
    face axis), one contact at the closest points of the two edges that face each other;
  - otherwise the face of the other box turned most against the reference face is clipped
    to it (`clipFace`), and each point where one of its edges crosses a side of the
    reference face is a contact (crossed lying kubbs: four);
  - corners stay as they were; a crossing within `CLIP_TOL` (1 mm) of a corner is left to
    it. Boxes standing square to each other (every axis within about 1.8 degrees of one of
    the other's: a row of kubbs, aligned debris) have no edge axis that is not a face axis,
    so the nine are skipped, and the clip returns at once when every corner of the
    incident face is within the reference face's sides. An edge axis's overlap is compared
    unnormalized first, so most of them cost no square root.
  - **One wood-on-wood friction.** `boxMu` (0.2) is gone; every pair of pieces meets at
    `pairMu` 0.4 (Engineering ToolBox, friction coefficients: clean dry wood on wood 0.25
    to 0.5, oak on oak sliding 0.48 along the grain and 0.32 across it, wood on wet wood
    0.2). The audit read the low
    value as standing in for these edge contacts. It did not: a row of kubbs stands square,
    edge contacts never arise in it, and with the edges and 0.4 the row stands up to blows
    as it did at 0.4 before "Tight rows". What holds it is the rub of wood on wood: the
    kubbs tip together and end leaning face to face, like books on a shelf, and energy never
    grows (checked step by step). A probe (four touching, a blow at 13 cm, flat ground):
    at 0.2 a 1.6 N s blow fells all four, at 0.4 three; 2.0 N s fells three either way
    round; a tap fells none.
  - **Measured** (before -> after on main at 213e428, after the foot catch came out;
    `tools/compound.lua --quick`): four touching end on, any kubb down 99% -> 69% of batons
    that hit the row, all four 26% -> 0%; four 3 cm apart, all four 21% -> 0%; three
    touching, all three 61% -> 45%, three 3 cm apart 64% -> 41%; two in line and the side by
    side layouts within 4 points. The domino table moves five cells, A or B standing where
    it fell or the reverse (a 12 rad/s tip at 3 cm leaves A leaning on B). On the main
    before that (490bd4a) the rows moved the same way (four touching all four 21% -> 0%),
    and the edges alone, friction left at 0.2, were within the sweep's noise of before (21%
    -> 12%; three 55% -> 51%). 40 physics matches (seed 2): 19.6 -> 18.6 turns, field
    batons hit 75% -> 77%. `tools/batonprobe.lua --quick`, `tools/groundstats.lua` and
    `tools/drillscatter.lua --only 3` were unchanged to the digit (no box meets a box in
    them).
  - **Cost** (desktop): `boxBox` on a touching square pair 3.8 -> 4.2 us (the squareness
    test), on a tipped pair at an angle 2.9 -> 5.0 us, crossed lying kubbs 2.8 -> 6.0 us (and
    four contacts instead of none). A tight row of four turned a few degrees, the second
    after a blow: 0.041 -> 0.050 ms a step at the same friction (the pair phase about a
    third more, the rest from the extra contacts), 0.062 with the new friction (the row
    stays up and touching longer). `make bench` is within its noise (multi 0.016 both).
  - Not bit-identical: any step where two boxes are within the margin of each other and not
    square to each other, or whose crossed faces' edges cross. A square tight row, the
    lone flight and every throw where no box meets a box are unchanged.
- **The pair bounce with its footing** (2026-11-16, the physics audit). The restitution
  passes (world.step, phase 7) now solve a bounce between two pieces together with every
  other contact of those two pieces that pressed this step (`r[K_LNMAX] > 0`: the kubb's
  footing on the ground, a neighbour), each held to the target it had in the relax pass
  (`r[K_RELAX]`, 0 or the small push-out of an overlap) rather than left out. The bounce
  target is still `-e` times the approach speed before the solve (`K_V0`), worked out once.
  A body is marked for this with `b.bounceStep`, the step stamp, so contacts of bodies in no
  pair bounce are untouched. The earlier try held every ground contact to 0, which
  pulled a contact that was pushing out an overlap back to rest and let the leaner sink;
  holding each to its relax target and only on bodies in a pair bounce keeps the leaner.
  - **`pairE` 0.35.** No measured coefficient of restitution for wood on wood turned up; the
    nearest is a wooden ball dropped on concrete, 0.60 (The Physics Factbook,
    "Coefficients of restitution", 2005), and a block meeting a block on an edge or a
    face gives up more than a ball does. 0.35 is the value before 2026-11-15, the low end of
    a plausible 0.35 to 0.5. At 0.5 `test_batonhits` fails (13 of 42 struck kubbs off the
    ground for 0.2 s or more, the limit 30%), so 0.5 was not taken.
  - **The fault is gone.** `test_physics` has it: a baton driven into a standing kubb at 4,
    7 and 10 m/s, three heights, two descents; the kubb's lowest corner, on the ground,
    moved down at up to 2.17 m/s with the old passes at 0.35 and 0.78 m/s now (limit 1).
    Over the batonprobe sweep (764 throws that touched the kubb; steps where a box corner
    on the ground moves down faster than 0.3 m/s): main at 0.2 792 (mean 1.00 m/s, max
    4.00), main at 0.35 877 (1.10, 4.52), this at 0.35 224 (0.72, 2.84).
  - **Measured** (before -> after, main at de58e7a; `pairE` 0.2 -> 0.35 with the fix):
    batonprobe sweep toppled 87% -> 91%, fast and left standing 28 -> 27, bounce-backs
    2 -> 0, off the ground 61% -> 63% and for 0.2 s or more 162 -> 277. The last is mostly
    kubbs kicked at the foot by a skidding baton: the ground now answers in the same step,
    so the kubb keeps more of the kick and flips up and over instead of losing it in a
    second hard step (traced: energy falls every step either way). `tools/compound.lua
    --quick`: rows fall more, four touching end on any kubb 67% -> 99%, all four 0% -> 9%;
    four 3 cm apart any 66% -> 87%, all four 0% -> 7%; three touching all three 52% -> 67%,
    three 3 cm apart 37% -> 51%; two side by side 3 cm both 12% -> 23%, three 7 cm all three
    6% -> 15%; two in line 30 cm 40% -> 52%. Two domino cells move (a 9 rad/s tip with a 3 cm gap
    leaves A standing, a 1 m/s shove at 13 cm with a 15 cm gap leaves B standing). 40 physics
    matches (seed 2): 18.7 -> 19.4 turns, field batons hit 77% -> 78%.
    `tools/drillscatter.lua --only 3` is unchanged to the digit (no pair contact in it).
  - **Cost:** nothing measurable (`make bench`: ground 0.009 to 0.010, multi 0.016 both);
    the extra work is one stamp per bouncing pair and a check per contact in steps that
    have a pair bounce.
  - Not bit-identical: any step with a bounce between two pieces faster than
    `restitutionSpeed`.
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


## Reference engine

`make mjref` (`tools/mjref/`, 2026-11-16) runs the same throws through `core/world` and
through MuJoCo, a general rigid-body engine. Where the two disagree, our collision model is
the first suspect. The comparison checks mechanics, not materials: both engines get the
game's own sizes, masses, inertias, friction, bounce and rolling resistance. The report
goes to `build/mjref/report.md`, with every number in `report.json`.

- Setup: any Python 3 with `mujoco` and `numpy`. Create a venv anywhere
  (`python3 -m venv <dir>`, then `<dir>/bin/pip install mujoco numpy`), then
  `make mjref MJPY=<dir>/bin/python`. `MJPY` defaults to `python3`.
- Runtime: about 5 minutes on a 10-core Mac. Our engine takes 7 s for all 1063 cases in
  both modes. MuJoCo takes the rest: four solver variants at 9600 to 19200 Hz, spread over
  the cores, after about 50 s of restitution calibration.
- The pipeline:
  - `export.lua` writes `params.json` (from `body.kinds`, `world.tune`, `world.surfaces`,
    `flight.tune`, `drill.tune`, `collide.tune`) and `cases.json`.
  - `cases.lua` defines each scenario once, using the game's own launch code
    (`world.batonLaunchState`, `world.drillLaunchState`, `drill.solveAt`, `plan.tumbleFor`).
  - `ours.lua` runs every case through the `world` API, as the game does, headless. Each
    case runs in two modes. "mech" is the flat plane with dig and bite at zero; these are
    the mechanics MuJoCo can model, so this is the comparison. "game" is the surface as
    played (texture, dig, bite; ground seed 1), shown for context.
  - `mjsim.py` builds one MJCF model per case from `params.json` and runs it.
  - `compare.py` computes every metric from both engines' traces with one function, so
    the definitions cannot drift apart.
- Scenarios:
  - Drops: a kubb or a baton lying flat, landing at 1, 2 and 4 m/s on each surface.
  - Baton landings: phi 0 to 165 degrees (90 is end first). Each lands at 7 m/s forward and
    4.5 m/s down, tumbling at 6.5 rad/s, starting 2, 6 or 10 mm up. At 4.5 m/s a 240 Hz
    step covers 1.9 cm, so the three starts meet the ground at different points of a step.
  - Broadside strikes on a standing kubb (h 0.03 to 0.145 m × 2 to 10 m/s) and on the king.
  - Tyler's end-on case: a tumbling baton coming down 0.2, 0.3 or 0.4 m short of a kubb.
  - The tip threshold: a standing kubb struck by a blow J (8 percent grid) at h 0.02 to
    0.14 m, on grass and snow.
  - Dominoes: pairs and rows of three, gaps of 1 mm to 15 cm.
  - The clean drill to a mark 6 m out: lofts 30 and 47, 0 to 3 taps, nose 41/45/49
    degrees, on each surface.
  - Free flight against `flight.carry`.
- Contact parameters (MuJoCo):
  - Solver: elliptic friction cones, `impratio` 10, the Newton solver (200 iterations,
    tolerance 1e-12) and the `implicitfast` integrator.
  - Every pair of geoms that can meet gets an explicit contact pair, with solimp
    `0.99 0.999 0.001 0.5 2`.
  - Ground pairs: friction is the surface's mu. A baton's ground pair is condim 6:
    torsional friction is roll × batonTurnHold, and rolling friction is roll. MuJoCo's
    rolling friction is a length, as `surf.roll` is.
  - Boxes on the ground, and every pair of pieces: condim 3 with pairMu.
  - Drag (`k|v|v`) and the drill's `aeroTurn` torque are applied through `xfrc_applied` to
    the projectile until its first contact, as in `world.step`.
- Restitution: MuJoCo has no coefficient of restitution. Its contact is a damped spring
  (solref = timeconst, dampratio). For each variant and each target e, the damping ratio is
  set by bisection on a drop test: a kubb lying flat lands at 2 m/s, and the result is the
  mean over four starting points a quarter step apart. e is read from the height of the
  bounce. At timeconst 0.002 s and 9600 Hz the ratios are 0.86 for e 0.15 (grass), 0.43
  for pairE 0.35, and 1.4 for e 0.02 to 0.03 (over 1: an overdamped spring still bounces a
  little). Drop checks: grass gives 0.148 / 0.147 / 0.154 at 1 / 2 / 4 m/s against 0.15.
  MuJoCo cannot hold a small e steady across speeds: sand and snow give 0 at 1 m/s and
  0.06 at 4 m/s. Ours gives 0.13 to 0.15 on grass and 0.003 to 0.024 on sand and snow.
- Convergence: four variants. ref is dt 1/9600 with timeconst 0.002; dt2 halves the step;
  stiff and soft use timeconst 0.001 and 0.004. Each variant is calibrated for itself.
  - A metric counts when the spread across the variants is within half its scale. It also
    counts when all four variants sit on the same side of ours and their spread is under
    half their distance from it: they disagree on how much, not on which way.
  - A discrete outcome must agree in all four, or the case is left out.
  - D is the mean over a case's counted metrics of min(1, |ours − MuJoCo| / scale), taking
    the variant nearest ours.
  - Scales: 0.10 m for distances, 0.02 m for apex heights, 15 degrees for angles, 0.2 for
    ratios, 0.05 m for flight distance, and 20 percent for a tip threshold.
  - 1039 of 1063 cases count. MuJoCo is not converged on:
    - the apex and spin kept of a tumbling baton's landing (about half the cases);
    - a drill's run on and rest distance from the mark (about two thirds);
    - how far a struck kubb slides (20 of 35);
    - small restitutions.
  - Those are reported, not scored.
- Headline results (2026-11-16, ranked by size × confidence):
  1. **Impacts lose too little speed to friction, and how much depends on where the step
     falls.**
     - A baton landing at 0 to 60 degrees keeps 0.56 to 0.89 of its ground speed in ours
       (mean 0.75) against MuJoCo's 0.41. With mu 0.7, Coulomb predicts about 0.5.
     - It also runs on twice as far: 2.5 m against 1.2 on grass, 1.4 against 0.75 on sand.
     - The same landing started 2 or 10 mm up keeps 0.59 or 0.79 of its speed in ours.
       MuJoCo is flat at 0.38 to 0.40.
     - Cause, in `world.step`: friction is solved only in the bias passes (`solve`), capped
       at mu times the normal impulse found there. For a speculative contact, that impulse
       only removes the approach speed beyond the gap still to close (target sep/dt). The
       restitution passes (stage 7) then add the rest of the impact impulse and the bounce,
       with no friction at all. A probe of a flat baton at 7 m/s forward and 4.5 down
       matched this exactly: Δv along the ground was 0.7 × (4.5 − gap/dt).
     - The same gap shows in other scenarios: struck kubbs and the king slide farther (king
       hit at 5 cm: 0.53 to 0.80 m against 0.31 to 0.42). Tyler's end-on baton at
       0.3 m short slides into the kubb and topples it where MuJoCo's stops short (phi 120
       to 150). The drill runs on 30 percent farther on grass and snow.
     - MuJoCo is the closer one here: the full impulse times mu is what Coulomb friction
       does to a rigid body on turf. The game's turf drag and grip (`texture.drag`, `grip`)
       and the drill's `slide` table were tuned on top of the shortfall.
     - Fix: solve the friction rows in the restitution passes too, capped by mu times the
       contact's whole normal impulse. That is about 30 lines in stage 7. Then retune the
       texture drag and grip and `drill.tune.slide` (`tools/drillscatter.lua`), and rerun
       `tools/batonprobe.lua` and `make realgames`.
  2. **A drill's attitude in flight is limited by the time step.** At loft 30 with one tap,
     ours lands nose 51 degrees down against MuJoCo's 40. Ours at 2400 Hz gives 38. Turning
     off the gyroscopic term moves it the other way. Cause: `aeroTurn` and the implicit
     gyroscopic step (`gyro`) are applied once per 1/240 s to a body spinning at 25 rad/s or
     more, in the lone flight and in `world.step`. MuJoCo is the closer one: this is
     integration error, not a model choice. Fix: substep only the projectile's rotation in
     flight (4 substeps of aeroTurn, gyro and the quaternion). It is one body, so cheap,
     about 15 lines. Then retune `noseDownDeg` and the slide table.
  3. **Free flight lands 2 to 3 cm short of the aim.**
     - MuJoCo matches `flight.carry` to 1 mm. Ours comes down through 0.3 m 2.0 to 2.9 cm
       short, and 2 to 4 ms early, at every loft and speed (7.18 against 7.21 m at loft 30,
       9 m/s).
     - Cause: `world.step` and the lone flight integrate semi-implicitly (v += g dt, then
       x += v dt), which drops g dt t / 2. `flight.carry` integrates by midpoint.
     - Fix: in flight, x += v dt + g dt² / 2 (one line in each of the two copies), or make
       `carry` step as the engine does. Small, but every aim carries it.
  4. **Low strikes on a standing kubb need 10 to 26 percent more J in ours.**
     - On grass at h 0.02, J is 0.435 in ours against 0.345. Snow is the same or worse at h
       0.04 to 0.06, and ours is not monotone there.
     - High strikes match exactly: grass h 0.08 to 0.14 gives the same J in both, and both
       sit within 7 percent of the rigid-pivot estimate.
     - Iterations (16) and warm starting change nothing. At 960 Hz ours moves to 0.373.
     - Cause: time-step error while the box rotates fast about a sliding edge: the corner
       contacts of `collide.groundBox` at 240 Hz.
     - No cheap fix. Accept it unless play shows foot hits feel wrong.
  5. **Smaller ones:**
     - An end-first landing (phi 90) runs on 5.0 m in ours against 3.5 to 3.9 m. That is
       probably item 1 again after it falls flat.
     - Snow's high-strike threshold is one grid step (8 percent) higher in ours.
     - Dominoes agree (D ≤ 0.16). Ours topples the second kubb a little less often right at
       the threshold.
     - A broadside baton's rebound agrees: 0.22 of its speed in ours against 0.19.
- Where MuJoCo is the less believable one:
  - Its box edges are sharp, while our capsule meets a box as a box rounded by `batonRound`
    0.01.
  - It has no turf: no dig, bite, texture or plough. The "game" column is ours alone.
  - It cannot give a small restitution that holds across speeds.
  - It does not converge on a tumbling baton's bounce height or a drill's run on: they
    change with the contact stiffness. Read those cells as a range, not a reference.
- `tools/physfuzz.lua` (the physfuzz branch) looks for invariant breaks within our engine,
  including a half-time-step check. This compares our engine against another engine. The
  two share no files. Findings 2 to 4 are the kind its dt check should flag.

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
   timings of the throw scene by frame type (aim with the camera still, moving the circle,
   walking, then the hit throw on the plan's swing split into wind-up, flight, impact and rest, with
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

An empty file named `debug` in the same Data folder shows the developer's items on the
practice pitch's System Menu "Pitch": "readout" and "bench" (`tw.debug`, read once at
launch). Without it a player sees only play, how to, reset, drill, batons, the surfaces and
title (RC review, 2026-11-15: a stranger could start the bench, which cannot be stopped).

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
- `render/hud` draws the minimap and the clock as layers: to the screen while their
  inputs change, into an image (on the 8 px grid, through `gfx.setDrawOffset`) once a
  frame repeats the last frame's inputs, then copied until an input changes. The minimap
  layer keys on the pose version and the advantage line; the aim line, player, landing mark
  and baton dot are drawn on top every frame. The other parts (rail, prompt, plan chip,
  rest flag, result flag, slow motion flag, verdicts, readout) are plates: one image each,
  redrawn only when their own key changes, so a frame that changes nothing costs one image
  draw per part. The title (one image per highlighted choice) and the
  match's hand-off and winner cards (`render/cards`, built once per card and kept in
  `s.card`) are each one cached 400 x 240 image, copied every frame: no text is drawn
  while they wait.
- The throw as a clock (DESIGN 4; "The throw"; it replaced `hud.gauge`, the loft plaque,
  the power chip and the drill callout, 2026-11-15): `hud.clock(st)` takes a table the scene owns and
  reuses (`phase`, `arm`, `crank`, `back`, `powerLo/Hi`, `releaseLo/Hi`, `deadDeg`,
  `overDeg`, `lastBack`, `lastStop`, `prompt`; angles are arm degrees, 0 = 6 o'clock,
  backswing negative, drawn on the left). The face (frame, ticks, the dotted dead slice,
  the hatched overpowered slice, the targets as grey slices with a black rim segment, the
  last throw's hollow dots) is one image keyed on those values rounded to whole degrees;
  the hand (thick with a white edge while throwing, thin at the idle crank) and the live
  peak dot go over it, and the whole dial is a layer like the minimap. `hud.tune.clock`
  places it at 351 207, r 30, under the prompt flag. Its calls (the `clock-gauge`
  self-test counts them): 13 a frame while the hand moves with a peak, 6 for an idle
  crank, 1 for a frame that repeats the last, about 66 once when the targets change.
  `hud.verdicts(powerV, releaseV, steady)` (one plate, 73 222 180 15, misses white on
  black) and `hud.planChip(kind, value)` (250 182, `TILT R 5°`, `SPIN L 2`, nothing at 0)
  are plates keyed on their arguments; `hud.cutFlag(text)` in the same place gives a
  drilled kubb's rest distance (never at the same time as the plan chip). The result flag
  (`hud.flag`, right edge 316, y 199) and the slow motion flag (y 182) sit left of the
  clock, widening to the left.
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
  for by `swingPeriod`, measured on the device); the same throw before the clock
  (2026-11-15, gauge and plaque, its old swing): 61/132/158/20; with the clock, the circle
  and the plan's clean throw onto b3: 55/128/140/21 (the clock and the plates are layers
  and images; the circle is two polygons and four lines a pass). Keep flight and impact
  within about 30 of those.
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
  the setup's `markerY`, `throw` keeps it still, `s.markerFixed`), so bests compare. Since
  drills run on (2026-11-16) a clean drill at the marker no longer always scores: over 200
  grounds on an empty pitch it rests within 50 cm 68% of the time at half past 1 (median
  38 cm; 40% at loft 30, median 56 cm), so a clean run scores about 4.1 of 6, against 6
  before the run on and 5.3 before the physics audit (the table's re-measure moved it by
  under 2 points; the audit's ground changes did the rest). `blastCm` stays 50 (a tighter
  30 cm would score a perfect swing 38% of the time).
  AROUND THE PITCH: five batons, each from in front of the next base kubb. An illegal
  throw (a helicopter) scores nothing.
- DOUBLES: six batons from the baseline, each at its own group of standing field kubbs
  (`drills.tune.doubles`, in order: a pair side by side 3 cm apart, a pair in line 3 cm, a
  triple side by side 3 cm, a pair side by side 7 cm, a triple in line 7 cm, a pair side by
  side 15 cm; gaps face to face as in `tools/compound.lua`, centers 4.6 to 6 m out, no
  king). Each baton gets its group stood fresh and the last group's kubbs are cleared
  (`drills.group`, ids `g<baton>k<n>`): every run faces the same six shots, so bests
  compare; a played-down set would leave lone kubbs after a part hit and make the doubles
  depend on earlier misses. A point for each kubb of that baton's group down, and
  `doublesBonus` (1) more when one baton takes two or more (`run.multi` counts them; the
  result card says it). Out of 20 (14 kubbs, six bonuses); always six batons.
- THE WALL: six kubbs drilled (drill mode, marker free: no `markerY`) at the centerline
  stake on the thrower's right (`wallStake`, `pitch.stakes[4]`: x = 2.5, y = 4; no king, it
  stands on the centerline). Each kubb is its own piece (`w1` .. `w6`) and stays on the
  pitch where it rests: `drills.setup` gives every earlier one back with its exact rest
  pose and z. After each throw `drills.tally` takes `res.bodies` (the throw's
  `world.result` bodies, which `scenes/drills` passes from `ts.result`: no accessor in
  `throw` needed), updates every wall kubb's pose (later kubbs move earlier ones) and
  scores `drills.wall(kubbs, n, stakeX, stakeY, out)`: a kubb is in the wall when it lies
  (long axis within 45 degrees of horizontal), its center is on the pitch's width and
  within `wallBand` (0.15 m) of y = 4 with its footprint touching or crossing into the far
  half, and its footprint (an oriented 15 x 7 cm `core/rect`) is within `wallGap` (0.12 m,
  edge to edge) of the stake's circle or of a kubb already in the wall, chained from the
  stake. The score is the wall as it stands after the last throw: a kubb knocked out of it,
  or cut off from the stake, stops counting (the rail's score can go down). Out of 6. On
  the desktop six clean drills stepping in from the stake at 4.1 m build a wall of 4.
- The menu's rows shrink to fit the list above `listBottom` (31 px for six rows, 23 for
  eight). DOUBLES' map draws the six groups as marks, THE WALL's the stake and a wall.
- A run goes through the throw scene one throw at a time, like the match
  (`drills.setup` -> `throw.prepare`, `s.auto = false`; `drills.tally` on the throw's
  `result.toppled`, `result.bodies` and `last.restCm` once it is `done`); the rail counts throws and the
  score. A card gives the score and any new best; A runs it again, B goes back to the menu.
  During a run the System Menu's third item is "Drill": menu (`drills.quit`: leave the run
  part way, nothing recorded) or title. The readout set on the practice pitch reaches the
  run's throw scene (`main.lua` `throwScene`). Each throw's trace line names the drill
  (`s.drillRun`, `drillId`). AROUND THE PITCH's stance is the setup's (`setup.playerX`,
  `throw.prepare`); the circle starts on the nearest kubb. THE HOUSE's kubbs are field kubbs
  to the plan (its arc is 4 o'clock).
- In drill mode (BLAST, THE WALL, and a match's kubb tosses) the rail shows the circle's distance
  and beside it what the caller gave (`throw.setRail`'s first right-hand text: a drill's
  score).
- Self-tests `drills` (the menu, a whole KING SHOTS run with straight scripted batons, the
  result card and the record it leaves, then a second run quit part way), `drills-blast`
  (BLAST's rail keeps its score) and `drills-new` (DOUBLES and THE WALL: the menu, each
  run's first aim and its first throw at rest on the plan's swing).
- HOW TO PLAY is the menu's last item (after THE WALL: the self-tests' menu presses are
  unchanged); it opens the rules cards, whose last card leads into HOW TO THROW ("HOW TO
  PLAY", "HOW TO THROW"), and the menu starts on it until HOW TO THROW has been seen.

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
most (Level, Record, Pitch), so Pitch is an options item that acts when the menu closes
and then reads "play" again; its "how to" starts HOW TO THROW over the pitch (or ends it
while it runs), its "title" goes back to the title screen, its "readout"
turns the debug line under the rail on or off (debug only, 2026-11-15: it was the first
item, a checkmark, which "Level" took; it and "bench" are listed only with the `debug`
flag file, "Measuring on the device"). Its "drill" turns
the pitch to drilling kubbs (next section) and "batons" back; chosen mid-throw, the switch
waits until the scene aims again. "reset" also clears the drilled kubbs.

## Drilling

DESIGN.md section 4 "Kubbs (drilling)". The pure part is `source/core/drill.lua`
(`tw.drill`); the body is `world.launchDrill` next to `world.launchKubb`; the scene part is
the throw scene with `s.drill` on.

- **Jamie on the drill (2026-11-16).** What the drill was, after watching the computer
  drill: "The physics of throwing Kubbs is still really bad. I watched the computer do this
  and there is no Kubb player in the world that could line up 5 Kubbs like this. When thrown
  they just stop dead on the ground, even though they are landing flat. These would be
  rolling and wobbling a TON more. This is why good drillers roll into other kubbs because
  it is impossible to stop that much energy with just the ground and grass -- except a
  perfect dug in corner that just drops but that is exceedingly rare. Plus the Kubbs are
  still "flying" flat, that is also totally unrealistic. They change angle in the air."
  And on the computer's plan, the same day: "The strategy of the driller was right. Like,
  trying to build lines is exactly what drillers do. You either, if you have 2 or 3, you
  would build a line. If you have more than that, you build a big cluster. So the strategy
  is right. It's just that literally it's impossible to throw cubes that consistently, and
  they would never land in anything even closely resembling the way they do in the game
  now." So since then a drill turns in the air and runs on from where it lands, a
  different way every throw; the computer keeps its plan (a line for 2 or 3 kubbs, a
  cluster for more, aimed short so it ends at its spot) and the scatter comes from the
  physics and the swing, never from aiming worse on purpose.

- **Where it shows up.** The match's kubb throws (`throw.prepare` turns `s.drill` on for a
  `projectile == "kubb"` setup; the circle stays where that team left it). The computer
  thrower drills too: `core/autothrow` gives `a.drill` (the basket as the circle and
  `world.launchDrill`'s arguments from `plan.launch`), which `tools/physmatch.lua` launches
  with `autothrow.launch` and `throw.autoLaunch` with `a`'s own speed, loft and swivel. The
  practice pitch drills after "Pitch: drill"
  (`throw.setDrill`): each drilled kubb gets its own id (`d1`, `d2`, ...) and becomes a piece
  of the pitch at rest (`keepDrilled`, the newest `drillKeep`), so later throws hit it; the
  auto stand-up after all far base kubbs are down is skipped while drilling.
- **Aim and launch** are the throw's ("The throw"): the d-pad moves the circle (it never
  snaps), the thrower stands behind it on the baseline (A walks along it or back), the arc
  starts at half past 1 (`plan.tune.arc.drill`), B + left/right is spin in taps
  (`plan.tune.spinPerStep` rad/s about the long axis each, + clockwise from behind, on top
  of the wrist's own spiral: a spun drill holds its attitude in the air, "The body in the air").
  `plan.solve` solves the clean drill onto the circle at the arc's loft (`drill.solveAt`: the
  speed that lands the kubb `drill.slideFor` short of the circle: its mean run on by the
  loft, the ground, the distance and the planned spin; `plan.solve` passes `q.surface` and
  `q.spin`; the allowance does not depend on the spin); the circle is where a clean drill
  most likely ends, not where every one does (it runs on 0.4 to 1.6 m, p10 to p90 on grass
  at half past 1). `plan.launch` judges the swing and gives the
  body through `drill.body` (noseDown, rollLand, spin, wobble). The aim camera is
  the baton's ("The aim camera": first person behind the thrower, looking past the circle,
  and the plan view while B is held, with the drill's planned arc; it replaced
  `camera.drillAim`, the fixed high drill view, 2026-11-15); the ring, cross and dotted line are drawn over it each frame (`drawMarker`),
  and the minimap's aim line goes to the circle. Self-test `clock-drill` (a drill at half
  past 1 with a tap of spin rests within 1 m of the circle on the Simulator: 0.16 m since
  the run on was measured again with the air's drag, 0.28 since the bite, 0.18 before it,
  2026-11-16; 0.4 m before the drill ran on. One drill's rest is spread over half a metre
  either way, so the bound stays 1 m).
- **The band launch** (`drill.launch`, `drill.solve`): the power error against the band is
  shrunk by `inBandGain` inside `bandHalf`, then scales the solved speed by `speedPerPower`
  per unit (never under `speedMinFrac`); the loft is the solved one. Smoothness under
  `cleanAbove` gives a nose-over wobble of up to `wobbleRate` rad/s (its sign is `r.pull`,
  +1 by default). Tilt pushes the swivel by `tiltPushDeg` per degree the way `r.pull` says.
  The cut is `cutSpin` rad/s about the long axis. No throw in the game uses it since
  2026-11-15; it is kept for core/bench, the tools and tests that throw a clean drill
  (`{ power = band, smoothness = 1, tilt = 0 }`, unchanged bit for bit).
- **The body in the air** (`world.drillLaunchState`, `world.launchDrill`, 2026-11-16;
  Jamie: "we didn't treat Kubb throws with the same physics as baton throws"). A drill is
  a plain rigid body released from the swing, like a baton: held by its back end, its long
  axis down the line `noseDownDeg` (45) below the horizontal (a later release lifts the
  nose with the arm, degree for degree), spinning about that axis at the wrist's `spiral`
  (3 rad/s, always: Jamie, "even if the thrower indicates no spin, there would always be
  some small, subtle amount of rotation") plus the planned taps. Nothing is solved back
  from the landing. In flight the air turns it toward broadside to its fall
  (`world.aeroTurn`, `world.tune.aeroK`, the projectile only); a spun drill is a gyroscope
  and holds its attitude, one with only the spiral turns steeper and less the same each
  time. Each throw is scattered at release with seeded normals (`pitchSdDps` 30,
  `yawSdDps` 15, `spinSd` 3 rad/s, `noseSdDeg` 4, each times 1 + `scatterJerk` x a jerky
  swing). Measured (`tools/drillscatter.lua --only 3`, 12 markers x 24 grounds, grass):
  nose down 47 degrees at the touch (sd 21) at half past 1, 56 (sd 19) at loft 30.
  `test_drill` checks the release, the touch, and that spin holds the attitude where the
  air turns an unspun one.
- **On the ground** a drill is a plain kubb: there are no drill-only fields or branches
  left in `core/world` (`digGain`, `edgeRound`, `digBySpin`, `slipDrag`, `rollDrag`,
  `plugGain`, `bumpGain`, the drill-over rule and its settle went on 2026-11-16). It meets
  the turf like every body ("Physics", "The bite"). Grass, the plan's clean drill (run on
  mean / p10 / p90 / max, rest from the circle, touch to rest): half past 1 0.95 / 0.41 /
  1.60 / 3.82 m, 43 cm, 0.78 s; loft 30 1.49 / 0.88 / 2.28 / 4.39 m, 52 cm, 0.92 s. Sand
  0.26 m at half past 1 (12% dead stops under 5 cm), 0.51 at loft 30; snow 0.96 and 1.53
  (no bite: packed snow lets an edge skate). It ends turned every way (yaw to the throw
  0-30 / 30-60 / 60-90: 43 / 31 / 26% on grass at half past 1). Measured after the nine
  physics audit items (2026-11-16), with the aim allowance measured again.
- **What spin does now.** Jamie (2026-11-16): "in the real world spin does move the Kubb
  when it lands… but at most it will move it one to three rotations… not the several the
  game was doing before." Honest physics gives exactly that: spin steadies the drill in the
  air and moves it a little either way on landing, in no steady direction (a square prism
  keeps a quarter of its roll at each edge it pivots on, and which corner strikes first
  decides the way). `test_drill`: across the throw under 0.28 m on average at every tap,
  sand and snow less than grass. It no longer rolls a kubb along the centre line into the
  stake, so the old spin-roll wall is gone (below).
- **The aim allowance** (`drill.slideFor(loftDeg, surface, spin, R)`, `drill.landFor`,
  `tune.slide`, `slideLofts`, `slideR`, `slideRefM`): the clean drill's mean run on past
  where it lands, a table by loft (26 / 37 / 47 / 57) and landing distance R (1.5 to 7.5
  m) per ground, read bilinearly (outside the table, its edge). The run on grows with the
  landing's speed, so `drill.landFor` solves R + slideFor(R) = d (six fixed-point steps,
  never under 0.5 m) and `drill.solveAt` lands the kubb there. Grass at half past 1: 0.20
  m from 1.5 m, 0.88 from 4.5, 0.63 from 7.5; low lofts run on most (1.94 m at loft 26
  from 4.5 m). Measured again after the nine physics audit items (2026-11-16, with the
  air's drag, the foot catch, the tilted landing, the pair bounce and the load-scaled
  grip) by `tools/drillscatter.lua --only 5 --grounds 60`: the plan's clean drill aimed to
  land R m out with no allowance, 3 lines x 60 grounds a cell, the mean rest along the
  throw past R (so it takes in any miss of the flight's own aim); a cell's mean is good
  to 1 to 5 cm, and another 60 grounds move a cell by 5 cm at most. Before, with the table
  measured with no drag, far circles rested up to 0.53 m short (grass 8 to 8.5 m at loft
  30: -0.33, snow -0.13 to -0.25 everywhere); after, the clean drill rests within 0.2 m of
  its circle on average along the throw at every distance from 2.5 to 8.5 m, loft 30 and
  47, every ground (120 drills a point), most within 0.1 (`tools/drillscatter.lua --only
  3`, along: grass -4 / -19 cm to +10 / -5 at half past 1 / loft 30, sand +2 / -12 to +2
  / 0, snow -12 / -21 to +4 / 0). `test_drill` checks the mean rest along the throw within
  0.45 m of each of nine circles over 30 grounds (-0.33 to +0.13 m; 0.7 m for an evening
  while the table was stale); `test_throwplan` the planned drill from a stance under 0.5 m
  off on average over ten grounds (0.38 m; 0.73 while stale); the backstop below 8 of 10
  grounds (9; 87 of 100); `test_autothrow` the computer's basket drill under 0.5 m from
  it on average over 40 grounds and in it (0.4 m) on 40% of them (0.41 m, 20 of 40).
- **Into other kubbs.** A drill that runs into a lying kubb stops by it (0.12 to 0.36 m
  centre to centre in `test_drill`'s backstop) and the struck kubb moves 0 to 20 cm; one
  that lands on top of a kubb shoves it 0.2 to 0.45 m. The drill-over rule below makes it
  a plain kubb at the first touch. In matches (`tools/drillscatter.lua --only 4`) a drill
  that reaches a lying kubb at under 1 m/s ends touching it 75 to 89% of the time, at 1 to
  2 m/s about 60%, over 2 m/s 20 to 33% (it knocks the kubb on or bounces off). The
  computer aims a turn's later kubbs to run into the ones down (`autothrow` `intoSpot`,
  "Tuned toward the real games", "Into the group"); self-test `match-group` shows a turn
  of 3 and a turn of 5 doing it.
- **THE WALL** (practice drill) is hard now. Before 2026-11-16 two taps of spin rolled a
  kubb along the centre line into the stake and six built a wall of 2.8 on average; a real
  drill does not roll like a log, so that way is gone. Clean drills at the stake
  (`drill.solve(2.42, 4.1, 0)`, 30 grounds) build 0.80 on average (0.72 over 60), best 3,
  none on half the grounds; `test_drills` checks a mean of 0.4 or more and a best of 2 or
  more over the 30. The scoring is unchanged: it is a
  practice record, and a wall is what a good driller earns.
- **HUD.** The clock, the verdicts and the plan chip ("The throw"); at rest the kubb's
  distance from the circle (`18 CM AWAY`) in the plan chip's place.
- **Telemetry.** A drill's `traces.jsonl` line is a baton line ("The throw") plus
  `"mode":"drill"`, `markerX/Y`, `landX/Y` (first contact), `restX/Y` and `throwerX`, in
  meters with y from the thrower's baseline (`core/trace.lua` header), and its `spin`.
  `frames.jsonl` writes `"proj":"drill"`.
- **Rules.** A drilled kubb's rest goes through `core/outcome.toss` and `core/match` like a
  lobbed one: short of the middle line or out when its round is judged is a rethrow, out
  twice a punishment kubb (tested in `test_drill.lua` with real physics).
- **Self-tests** `clock-drill` (above), `clock-plan` (the drill's spin and arc, the circle
  moved by the d-pad), `drills-new` (THE WALL's first kubb near the stake).

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
scene at a time and rebuilds the System Menu for it (Level, Record, then the scene's
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
  `label` such as "Team B  baton 2 of 6", `thrower` = `{ id, name }` of the player who
  throws it, from `core/order`); `match.resolve(m, res, illegal)` applies a
  finished throw (as that player) and sets `m.text` (the result line); `match.resign` (the
  next thrower's `G`), `match.file`. `m.order` is the throwing order; the save keeps it.
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
  picked up keeps its spot but drops its exact pose (it would float).
  Standing pieces (2026-11-16, physics audit item 4): every kubb the engine has standing and
  the king also keep their exact rest pose (tilt, height, which end is down), so a kubb a
  throw left tilted is met tilted by the next throw instead of being stood up straight.
  These outlast the turn (the pieces stay on the pitch; `debris.begin` keeps only them). A
  standing kubb at rest tilted less than its tipping point leans back unless something holds
  it: in 80 physics matches before this change (`tools/physmatch`'s path, 40 each on seeds 2
  and 3) throws moved 1,539 standing pieces without toppling them and 1,528 came to rest
  within 1 degree of upright; the 11 that did not (1.6 to 23.6 degrees) each had a lying
  baton or a downed kubb within 25 cm holding them, debris that is picked up at the end of
  the turn. With the change 13 throws in those 80 matches met a tilted kubb. So when what may have propped one has gone
  (a new turn, the inkast's kubbs raised, a judgment that lifted kubbs or picked any up for a rethrow, a rescue or a punishment: `d.settle`),
  `match.setup` calls `match.settleStanding`: the world runs every carried piece tilted over
  `settleDeg` or raised over `settleGap` to rest once, from the pitch as it is now, and the
  engine's pose follows where it settled. One that topples or leaves the pitch while settling
  was knocked by clearing the pitch and is stood back up where the engine has it (no exact
  pose). A kubb leaning on a neighbour by its own weight is past its tipping point, and the
  leaner rule already has it down; a standing pose past the tipping point (the inkast's
  45-degree rule, `outcome.tune.standingCos`, can call one standing) is not carried, and is
  stood up straight as before. Cost: the check is a few multiplies per standing piece; a
  settle that runs is about 170 steps with one body awake (1.8 to 2.6 ms on the desktop,
  roughly a second on the device), once per turn that left a tilted piece (1 run in 80
  matches). In the scene the
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
  RESUME <A> V <B>, TURN n` beside A START (`RESUME TURN n` when the teams' names would
  run into it, `title.resumeText`); without one, while HOW TO THROW has not been seen, the
  same place says `NEW? PRACTICE > HOW TO PLAY` (`title.new`'s hint) (a save that does not read back is ignored,
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
  scene shows that stance and aim (`throw.showAim`, `s.watching`: a WATCH prompt over the
  clock, its circle where its plan says, the clock with its plan's targets) for
  `cpuThink` s, then `throw.autoLaunch`: its arm plays on the clock (back, then forward
  to where it stops, `cpuSwingTime`) and the throw leaves as it made it, mistakes
  included; its kubbs are drilled ("The throw"). It raises
  and places punishment kubbs with the engine's policies (no settle screen); the player
  settles by hand. No hand-off card before the Playdate's turn. The System Menu resign is
  always the player's and waits for the player's turn. Self-test `match-vs` (a whole
  match, the player's throws seeded, its game file gated).
- Kubb toss: a drilled kubb, always from the baseline ("Drilling"); a kubb with no
  `a.drill` from the computer is lobbed (`world.launchKubb`, end over end, no tilt), drawn
  as one more box item.
- Stay put (Jamie, 2026-11-14): in `throw.prepare` a team's batons after its first of a
  turn keep a stance the player walked to with A (`s.stanceSet`, `s.stanceSide`,
  `s.stanceKind`), clamped to where this baton may stand (a king shot pulls it back to
  the baseline), and the circle stays on its target while that stands. Otherwise, and
  for every kubb, the stance is behind the circle, which starts on the nearest live target.
  Self-test `match-opening` checks both.
- Advantage line: A + d-pad walks between `backMax` behind the baseline and `forwardY` (the
  engine's advantage line; king shots are from the baseline). A baton's stance starts
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
scene's `landed`, never during the flight; not in instant mode). Past
`logcap.maxBytes` (1 MB) the file becomes `frames-1.jsonl` (replacing an older one) and a
new one starts (`source/logcap.lua`; checked before each line). Collected with a dozen
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

The System Menu has "Record" (and the practice pitch's "Pitch: readout", the debug line
after each throw). Record is
on by default while the throw is being tuned (self-tests leave it off). With
Record on, every swing is appended as one JSON line to `traces.jsonl` in the game's Data
folder (Simulator: `~/Developer/PlaydateSDK/Disk/Data/com.thingelstad.throwingwood/`). It
stays on in the builds for players (their recordings are how the throw gets tuned), so the
file is capped: past `logcap.maxBytes` (1 MB, about 750 swings) it becomes
`traces-1.jsonl`, replacing an older one, and a new one starts (`source/logcap.lua`;
checked before each line; at most about 4 MB of logs in all). Read both when collecting.
The format is documented at the top of `source/core/trace.lua` (samples are
`[dt, raw crank degrees]` per frame from the first wind-up frame to release or let-down,
not the cooldown after a release, plus the result: what the swing measured, then the
plan and the launch, "The throw"). `lua5.4 tools/replay_traces.lua <file>` replays each
line through the current `core/swing.lua` and prints recorded vs replayed results;
`--current-sign` replays with today's `forwardSign` instead of the recorded one. The test
fixture is `tests/fixtures/traces/sample.jsonl`. Drill lines add the fields in "Drilling"
above; `replay_traces` reads them like any other line (the swing is the same).
