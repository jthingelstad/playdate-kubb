# Kubb: Throwing Wood

A Kubb game for the Playdate (Lua, SDK 3.1.2). The design is `docs/DESIGN.md`; read it first.
`CLAUDE.md` is a symlink to this file.
Selling it in the Playdate Catalog: `docs/CATALOG.md` (what Panic asks for, where the game
stands, the listing assets and the accessibility disclosure).

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
  (`tools/physmatch.lua`, see `docs/notes/headless-games.md`) into `build/physgames/` and gates them too.
- `make realgames`: plays `REAL_N` (150) physics matches (`REAL_SEED` 2) at `REAL_LEVEL`
  (pro: the recorded games are pro play) into `build/realgames/` and prints their figures beside the same figures from the games people
  scored in a pk-kubb-score checkout (`tools/realgames.mjs`, see `docs/notes/real-games.md`). Needs the
  checkout, so it is not part of `make test`.
- `make physfuzz` (`N` 2000, `SEED` 1, `SURFACE` Grass): the physics fuzzer
  (`tools/physfuzz.lua`, see `docs/notes/physics-fuzz.md`). It is a measuring tool, not part of `make test`.
  Its pinned cases are part of `make test`, in `tests/lua/test_physcases.lua`.
- `make bench`: the physics benchmark on the desktop (`tools/bench.lua`, three runs of
  `core/bench`, prints each and the best; then the same three runs with a full turn's debris
  asleep on the pitch, and the difference). `lua5.4 tools/bench.lua [runs] [--profile]
  [--micro]` adds the per-phase profile of `world.step` and the micro benchmarks of
  `core/microbench`. The device side: `docs/notes/performance.md`.
- `make mjref`: the reference-engine comparison, the same throws through `core/world` and
  MuJoCo, into `build/mjref/report.md` (`MJPY`, a Python with `mujoco` and `numpy`; see
  `docs/notes/reference-engine.md`). Not part of `make test`.
- `make clean`.
- `make release`: a clean build zipped as `build/ThrowingWood-<version>.pdx.zip`, for
  friends to sideload (play.date/account/sideload). Raise `version` and `buildNumber` in
  `source/pdxinfo` for each one (a Playdate keeps the higher build), and the same pair in
  `source/core/version.lua` (`tw.version`: `version`, `build`, `text` "0.9.6 (7)"). pdxinfo
  is the source of truth; `test_version.lua` fails when the two disagree, and `make
  release` runs it before it builds. The title shows `tw.version.text` small in the sky's
  top right corner; the web game gets the same pair through its vendor sync. The zip is published
  on files.thingelstad.com and linked from https://playdate.thingelstad.xyz/throwing-wood/
  (that site's repository). Each release so far: `docs/notes/releases.md`.

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
from the sibling checkout `../pk-kubb-score` in the throwingwood folder (or `$PK_KUBB_SCORE`). The checkout itself is
still read only: never write there and never run `npm install` there.

Synced 2026-11-16 for optional positions on the pitch (Jamie: "Approved also for the
extending of the notation system."): a comment that starts with `@` after kubbs thrown in or
a baton, `2I (@ b6 c7)` or exact meters `(@ 1.32,5.87)`, seen from Team A's baseline, `^`
for where the thrower stood. The parser and `kubb.js` put them on the token as `at`. The
game writes them since 2026-11-16 ("Positions" in `docs/notes/rules-engine.md`).

The web game (kubb.thingelstad.xyz, at throwingwood.com) runs `source/core` unchanged:
its `vendor/core/` is this repository's `source/core/` copied byte for byte (its `npm run
vendor:sync` and `vendor:check`, run from that repository). So a change to `source/core`
is a change to the web game at its next sync: keep the core pure and portable, fix core
behaviour here (never in the copy), and never write in that checkout from here.

## Rules to know before editing

The detail behind each of these is in the subsystem notes below.

- **Rules engine** (`core/rules.lua`): a pure state machine that knows nothing about
  physics. Physics hands it outcome records (the fields are in "Baton outcome" and
  "Kubb-toss outcome", `docs/notes/rules-engine.md`); an action called out of phase raises
  an error. Kubbs are `a1`..`a5`, `b1`..`b5` and `king`; `g:census()` is always 10.
- **Judged at the final position** (Jamie, 2026-11-13): a thrown kubb is not judged in or
  out when it stops. Every kubb of a round stays a piece on the pitch until the round's
  last throw is at rest, then all are judged at once; rethrows come last. Moving a kubb
  thrown this turn is never II.C.4b.
- **Notation**: player ids are letters and underscores only; `Y` is never written; a
  position comment never holds more places than its token counts; positions are in Team
  A's frame (`notation.pitchXY`); no `os.time` in core (times are passed in). Screens
  show sheets without positions (`gamefile.shown`); the file keeps them. Every game the
  engine writes must pass the notation gate with zero warnings (`make games`).
- **Throwing order** (`core/order`): who throws is decided before the throw within II.B.5
  and II.A.4; `order.checkSheet` checks every finished sheet in `test_games`, `make games`
  and `tools/physmatch.lua`.
- **Real-play measuring** (`make realgames`, `tools/clusters.lua`,
  `tools/drillscatter.lua`) changes nothing in the game; what to tune from it is Jamie's
  call, and play questions (raising policy, the basket) are his.
- **Tunables**: every number that is a guess lives in its module's `tune` table with a
  comment (the list is in `docs/notes/throw.md`, "Tunables"). Piece sizes are DESIGN 2,
  not tunables.
- **Input**: scenes never read `playdate.buttonIsPressed`/`getCrankChange` directly; they
  read the input provider (`source/input.lua`, `tw.input`), so self-tests can script it.
- **Physics** (`core/world`, `core/collide`): meters, kilograms, seconds, radians; x across,
  y from Team A's baseline (0) to Team B's (8), z up; a fixed step of 1/240 s. The hot
  paths are written out in full for the device (no helper calls per pair, contact or
  pass; no tables or closures a step). A change there should keep a dump of every body
  after a fixed scenario bit-identical on the desktop, or say why not. Outcomes are
  tested with tolerances.
- **Pinned physics cases**: `tests/lua/physcases/*.lua`, run by `make test` through
  `tests/lua/test_physcases.lua`; how to make one from a fuzz failure is in
  `docs/notes/physics-fuzz.md`.
- **The view frame** (`core/frame`): Team B's throws are made in the pitch turned 180
  degrees, so the throw scene, cameras, flight, HUD and physics always throw from y = 0
  toward +y. `core/outcome` turns results back into the world frame.
- **Drawing**: change a piece's pose only through `render.world.setPose`; after changing
  `render.world.tune` or anything else the caches cannot see, call
  `render.world.invalidate()`. A new HUD part that depends on something must put it in its
  layer's key, or the layer shows a stale image (`make selftest` compares frames with
  `cache = false` and `true`). Keep the `drawcalls` self-test's flight and impact counts
  within about 30 of those in `docs/notes/performance.md`.
- **Saved data**: player keys `p<n>` are never reused; `roster.valid` cleans what the
  datastore gives back and never errors at launch; removing a player deletes the history
  and keeps the game files. Self-test runs put `selftest-` in front of the players files
  and save a match under `selftest-match`, the soak under `soak-match`, and matches with
  `noSave` never save: none of them may touch a player's saved data. A version 1 match save is
  deleted at launch and never resumed.
- **Self-tests**: a scenario is `source/selftest/<name>.lua` and must also be imported
  from `main.lua`; files starting with `_` are helpers. A Simulator that segfaults on quit
  after writing `DONE` is not a failure; a run with no marker is. The Simulator connects
  to a Playdate plugged in over USB: do not unplug or reboot it. Screenshots for Jamie are
  the 2x frames.
- **On the device**: the flag files `autobench`, `soak`, `nolock` and `debug` go in the
  game's Data folder. Read `bench.txt` and delete it when done, delete `nolock` when the
  testing is done, and never touch `traces.jsonl`, `frames.jsonl` or `games/` (players'
  recordings and games).

## Subsystem notes

Detail, measurements and history live in `docs/notes/`. Read a file before changing
the part it covers; section names quoted in code comments (`docs/notes/physics.md
"Friction in the bounce"`) are headings or bold items in these files.

- `docs/notes/rules-engine.md`: Rules engine (Poses, Baton outcome, Kubb-toss outcome,
  Judged at the final position), Notation conventions, Throwing order. Before touching
  `core/rules`, `core/notation`, `core/gamefile`, `core/order` or the outcome records.
- `docs/notes/headless-games.md`: the random thrower, `core/autothrow` (the computer
  thrower), `tools/physmatch.lua`, `tools/compound.lua`. Before changing how the computer
  throws or the headless tools.
- `docs/notes/real-games.md`: Real games (the computer's levels, How tight the groups are,
  Tuned toward the real games, Nerves, The baton's tumble, Aimed through the piece, What
  scatters a drilled kubb). Before tuning levels, nerves, the aim or the computer's
  drills, or comparing with recorded games.
- `docs/notes/saved-players.md`: the roster, histories, PLAYERS, TEAMS, the save version,
  throw levels. Before touching `core/roster`, `core/history`, `core/lineup` or the
  datastore files.
- `docs/notes/selftests.md`: running the Simulator, film mode, the helpers and every
  scenario. Before adding or changing a self-test.
- `docs/notes/throw.md`: The throw, HOW TO PLAY, HOW TO THROW, The aim arc, The aim
  camera, Wind, Input provider, Tunables, Playback. Before touching `scenes/throw.lua`,
  `core/swing`, `core/throwplan`, `core/camera`, `core/wind` or a `tune` table.
- `docs/notes/physics.md`: Physics (the air's drag, the bite, sleep, free flight,
  friction in the bounce, the bounce reaches the row, the ground's texture, baton hits
  and the rest of the physics history). Before any change to `core/world`,
  `core/collide`, `core/body` or `core/flight`.
- `docs/notes/physics-fuzz.md`: `tools/physfuzz.lua`, its checks, clusters and pinned
  cases. When a physics change needs checking or a fuzz failure needs a case.
- `docs/notes/reference-engine.md`: the MuJoCo comparison (`make mjref`). When measuring
  the physics against a reference.
- `docs/notes/performance.md`: Measuring on the device (autobench, soak, flag files),
  Drawing speed (caches, layers, plates, the clock), Frame-time log, Crank traces. Before
  touching `render/`, the HUD, or anything on a per-frame path.
- `docs/notes/drills.md`: Practice drills, Throw scene practice, Drilling (the drilled
  kubb, the aim allowance). Before touching `core/drill`, `core/drills` or the practice
  pitch.
- `docs/notes/match.md`: Match (the view frame, outcomes, `core/match`, the match scene,
  debris, raising and settling, saves) and Kubb sets. Before touching `core/match`,
  `scenes/match`, `core/debris` or `core/save`.
- `docs/notes/presentation.md`: Woodcut type, title, cards and launcher; Slow motion; Hit
  bursts; Knocks. Before changing the look, the cards, the bursts or the sounds.
- `docs/notes/releases.md`: every release so far.
