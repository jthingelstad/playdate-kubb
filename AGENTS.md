# Kubb: Throwing Wood

A Kubb game for the Playdate (Lua, SDK 3.1.2). The design is `docs/DESIGN.md`; read it first.
`CLAUDE.md` is a symlink to this file.
Selling it in the Playdate Catalog: `docs/CATALOG.md` (what Panic asks for, where the game
stands, the listing assets and the accessibility disclosure).

## Repo and pull requests

- GitHub: `jthingelstad/playdate-kubb` is public. Keep account ids, email addresses, device serial numbers,
  home-directory paths and personal details out of files, commit messages and pull requests.
- `main` takes changes only through a pull request with a green `validate` check on a
  branch that is up to date with `main` (ruleset "main: pull requests on a green
  validate"). Merges are rebase merges; auto-merge is on; branches are deleted on merge.
- `validate` (`.github/workflows/validate.yml`) runs the vendor check, the Lua tests and
  the notation gate.
  Before opening a pull request run `make test` and `make selftest` locally: the Simulator
  cannot run on GitHub.
- Codex reviews every pull request. Read its inline findings and fix or answer each one
  before calling the work done.
- Other sessions share this checkout. Do side work in a `git worktree`, not by switching
  branches here.

## Commands

- `make build`: `pdc` compiles `source/` to `build/ThrowingWood.pdx`.
- `make test`: `make vendor-check`, the Lua tests (`tests/lua/run.lua` on Lua 5.4: the
  Playdate's own modules) and the notation gate's own tests (`tests/node/notation-gate.mjs`
  over `tests/fixtures/games/`, `tests/node/gate-rejects.mjs` over `tests/fixtures/bad/`).
- `make selftest`: builds, then runs every scenario in `source/selftest/` in the Simulator,
  and gates the game files its matches write. Frames land in `build/selftest/`.
- `make vendor-sync TAG=vX.Y.Z` and `make vendor-check`: see "The core is vendored".
- `make bench`: the physics benchmark on the desktop (`tools/bench.lua`; `--micro` adds
  `device/microbench`). The device side: `docs/notes/performance.md`.
- `make games`, `realgames`, `physfuzz`, `mjref` and the core's tests and measuring tools
  are kubb-engine's: run them there.
- `make clean`.
- `make release`: a clean build zipped as `build/ThrowingWood-<version>.pdx.zip`, for
  friends to sideload (play.date/account/sideload). Raise `version` and `buildNumber` in
  `source/pdxinfo` for each one (a Playdate keeps the higher build), and the same pair in
  `source/device/version.lua` (`tw.version`, shown on the title). pdxinfo is the source of
  truth; `test_version.lua` fails when the two disagree, and `make release` runs it first.
  The zip is published on files.thingelstad.com and linked from
  https://playdate.thingelstad.xyz/throwing-wood/ (that site's repository). Each release so
  far: `docs/notes/releases.md`.

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

## The core is vendored

- `source/core/` is the Kubb Engine's `core/` (`jthingelstad/kubb-engine`) at the release
  tag in `engine-core.json`, byte for byte. Never edit `source/core`. Fix behaviour in
  kubb-engine, release it there as a tag, then `make vendor-sync TAG=vX.Y.Z` here (it
  reads the tag from the checkout `../kubb-engine` or `$KUBB_ENGINE` through git, never
  its working tree, and refuses files that disagree with the tag's `engine.json`). Never
  write in the kubb-engine checkout from here.
- `make vendor-check` (in `make test` and CI) fails when `source/core` differs from
  `engine-core.json`; with an engine checkout present it also checks `engine-core.json`
  against the tag.
- The core's rules (pure Lua, no `playdate.*`, no tables per physics step, tolerances not
  bit-exact) and its notes, tests and tools are in kubb-engine's `AGENTS.md`.
- Playdate-only pure modules live in `source/device/` (`version`, `frametel`,
  `microbench`), tested on the desktop like the core and kept free of `playdate.*`.
  Drawing, input and files live in `main.lua`, `input.lua`, `recorder.lua`, `scenes/`,
  `render/` and `selftest/`. In per-frame paths avoid making tables or closures.

## Tests

- Lua: add `tests/lua/test_<thing>.lua` for a `source/device` module. Use `test(name,
  fn)`, `expect.eq`, `expect.near`, `expect.truthy`. The runner picks up every
  `test_*.lua`.
- Notation gate: every game file the game writes must pass the pk-kubb-score grammar with
  zero warnings and `kubb.js` must find the same winner as `[Win]` (`make selftest` runs it
  over the self-tests' matches). `tests/vendor/pk-kubb-score/` holds copies of
  pk-kubb-score's `site/assets` parser and scorer (Jamie approved the copy 2026-11-13).
  Never edit them; `make sync-notation` refreshes them from `../pk-kubb-score` (or
  `$PK_KUBB_SCORE`), which is read only: never write there or run `npm install` there.

## Rules to know before editing

The detail behind each of these is in the subsystem notes below. The rules engine,
notation, physics, throwing order and tunables are kubb-engine's (its `AGENTS.md`).

- **Input**: scenes never read `playdate.buttonIsPressed`/`getCrankChange` directly; they
  read the input provider (`source/input.lua`, `tw.input`), so self-tests can script it.
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

Detail, measurements and history live in `docs/notes/`. Read a file before changing the
part it covers; section names quoted in code comments are headings or bold items there.
The core's notes (rules engine, headless games, real games, physics, physics fuzz,
reference engine) moved to kubb-engine's `docs/notes/`; the files here of those names
only point there, and the core's tools and tests that older notes cite are the engine's.

- `docs/notes/throw.md`: the throw scene, HOW TO PLAY, HOW TO THROW, the aim camera,
  the input provider, playback. Before touching `scenes/throw.lua` or the input.
- `docs/notes/saved-players.md`: the roster, histories, PLAYERS, TEAMS, the save version,
  throw levels. Before touching the players screens or the datastore files.
- `docs/notes/selftests.md`: running the Simulator, film mode, the helpers and every
  scenario. Before adding or changing a self-test.
- `docs/notes/performance.md`: Measuring on the device (autobench, soak, flag files),
  Drawing speed (caches, layers, plates, the clock), Frame-time log, Crank traces. Before
  touching `render/`, the HUD, or anything on a per-frame path.
- `docs/notes/drills.md`: Practice drills, Throw scene practice, Drilling. Before touching
  the practice pitch.
- `docs/notes/match.md`: the match scene, debris, raising and settling, saves, Kubb sets.
  Before touching `scenes/match`.
- `docs/notes/presentation.md`: Woodcut type, title, cards and launcher; Slow motion; Hit
  bursts; Knocks. Before changing the look, the cards, the bursts or the sounds.
- `docs/notes/releases.md`: every release so far.
