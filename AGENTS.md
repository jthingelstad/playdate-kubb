# Kubb: Throwing Wood

A Kubb game for the Playdate (Lua, SDK 3.1.2). The design is `docs/DESIGN.md`; read it first.
`CLAUDE.md` is a symlink to this file.

## Private and local

The repo is local only and private until Jamie says otherwise: no GitHub repo, no remote,
no pushing.

## Commands

- `make build`: `pdc` compiles `source/` to `build/ThrowingWood.pdx`.
- `make test`: the Lua tests (`tests/lua/run.lua` on Lua 5.4) and the notation gate
  (`tests/node/notation-gate.mjs` over `tests/fixtures/games/`, then
  `tests/node/gate-rejects.mjs`, which checks every game in `tests/fixtures/bad/` is refused).
- `make selftest`: builds, then runs every scenario in `source/selftest/` in the Simulator.
  Frames land in `build/selftest/`. Each run takes about 2 seconds.
- `make clean`.

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
`scenes/`, `render/`, `selftest/`). Playdate floats are 32-bit, desktop doubles: test
outcomes with tolerances, never bit-exact.

## Tests

- Lua: add `tests/lua/test_<thing>.lua`. Use `test(name, fn)`, `expect.eq`, `expect.near`,
  `expect.truthy`. The runner picks up every `test_*.lua`.
- Notation gate: every game file must pass the pk-kubb-score grammar, `kubb.js` must find the
  same winner as `[Win]`, and warnings fail unless `--allow-warnings` is passed. Player ids
  are letters and underscores only.

## pk-kubb-score is read only

The gate loads `site/assets/notation-parser.js` and `site/assets/kubb.js` from
`~/Projects/pk-kubb-score` (or `$PK_KUBB_SCORE`). Never write there, never run `npm install`
there, never copy its files here.

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
- The Simulator connects to a Playdate plugged in over USB when it starts. Self-tests do not
  touch the device, but do not unplug or reboot it.
- Screenshots for Jamie are the 2x frames. The 1x frames are for agent checks.
