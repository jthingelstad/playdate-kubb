# Speed and measuring on the device

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

## Measuring on the device

The autobench measures a build on the Playdate with nobody pressing anything:

1. Build and install `build/ThrowingWood.pdx` (data disk mode, copy to `/Games`).
2. Create an empty file named `autobench` in the game's Data folder
   (`/Data/com.throwingwood.playdate/`), eject, and launch the game
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

### The performance check

`source/perfbench.lua` (2026-11-20) measures what a player feels, the same fixed scenes
every run, each repeated, so two builds can be compared and the spread told from the
change. An empty file named `perfbench` in the game's Data folder runs it at launch (the
game deletes the flag first; several minutes; auto-lock off, recorder and frame log off,
so `traces.jsonl` and `frames.jsonl` are untouched). It appends to `perf.txt`: a new VS
PLAYDATE match and a resume (under its own key `perfbench-match`, deleted after),
`plan.solve` at 1, 1.5, 3 and 8 m and a drill, the computer's `autothrow.choose` per level
on a baseline, toss and field setup from a real match, the aim view with the circle moving
(the plan solved every frame) at a kubb 1 m and 6 m away, the same through the scene's own
update with a scripted d-pad (the plan every other frame, then every frame), and four throws through the throw
scene as in a match (into a close cluster of six field kubbs from 5 m and from 1 m, an 8 m
baton at a base kubb, a drilled kubb settling): release to rest, the live flight's frames
and their real frame time (mean, sd, max; the calm tail's frames counted apart, they are
held by design), update and draw per frame, starved frames, physics steps and ms per step,
memory. Each throw runs once uncounted, then five times: median [min-max]. Read `perf.txt`
and delete it when done.

Engine 0.5.1 to 0.8.1 on the device (2026-11-20, game 0.9.7 build 8 then 0.9.8 build 9):
the same within the spread everywhere but the short throw's plan. Throws: cluster 5m 61.3
ms a frame both, 8 m base 53.3 and 53.2, drill 43.7 and 43.8; cluster 1m 50.5 to 55.2 ms
(the baton now gets there: toppled 0 then 1, 82 live frames, not 151). Computer choice 14
to 24 ms a throw both, new match 80 ms both, resume 138 and 137 ms, memory after a full
collection 1338 and 1351 KB. The one regression: `plan.solve` at 1.0 m 2.28 to 24.7 ms
(1.5 m 2.4 to 2.7, 3 m and over unchanged), so the aim view moving the circle onto a kubb
1 m away updates in 30.1 ms, not 3.6 (draw 13 ms; about 23 frames a second while the
circle moves at a kubb about 0.4 to 1.4 m away). The cost is the core's: `plan.solve`'s
aim-height bisection calls `speedForCarry` (itself iterative) 20 times, and
`flight.handAt` bisects 30 times. Neither can be cut without changing the hand or the aim
by a few bits, which a patch release may not (fewer `handAt` steps move the hand by 8
micrometres; a regula falsi shortcut held on doubles but not on the Playdate's 32-bit
floats; kubb-engine's docs/notes/throw.md). Engine 0.8.2 drops only the carries whose
answers it already has (the same bits): on the device `plan.solve` at 1 m 25.8 to 22.6 ms,
everything else the same within the spread (vendored 2026-11-20; measured on a build whose
core was byte for byte the v0.8.2 tag's).

The rest is the scene's (`throw.tune.halfRateM`, docs/notes/throw.md "The aim at a short
throw"): while the d-pad moves the circle within 2 m of the stance, the plan is solved every
other frame. The check's "aim d-pad" row drives the scene's own update with a scripted
d-pad at both rates. On the device at a kubb 1 m away, update per frame (draw about 28 ms
either way): 0.8.1 solving every frame 24.6 ms (max 37.0), every other 14.1; 0.8.2 every
frame 20.8 (max 31.4), every other 12.4 (max 31.2), about what the aim at 6 m costs (8 ms).
A frame that solves is still about 31 ms of update; at 6 m the plan solves every frame.

The result of record, 0.9.8 build 9 (ms; the first column has no "aim d-pad" row):

| Row | 0.8.1 | 0.8.1 + every other frame | 0.8.2 + every other frame |
|---|---|---|---|
| plan.solve 1 / 1.5 / 3 / 8 m / drill | 24.7 / 2.70 / 3.01 / 4.40 / 6.82 | 25.8 / 2.75 / 3.06 / 4.45 / 6.85 | 22.6 / 2.61 / 2.84 / 4.05 / 6.23 |
| aim, replan every frame, 1 m / 6 m | 30.1 / 5.12 | 31.6 / 5.06 | 27.9 / 4.89 |
| aim d-pad 1 m, every frame / every other | | 24.6 / 14.1 | 20.8 / 12.4 |
| aim d-pad 6 m (solves every frame) | | 8.5 | 8.1 |
| computer choice, club: base / toss / field | 16.5 / 22.6 / 14.1 | 16.8 / 23.8 / 14.2 | 15.3 / 22.4 / 13.3 |
| new match / save / resume | 80 / 72 / 137 | 81 / 73 / 139 | 80 / 72 / 137 |
| throw frame mean: cluster 5m / 1m / 8 m base / drill | 61.3 / 55.2 / 53.2 / 43.8 | 61.7 / 55.8 / 53.2 / 44.3 | 61.3 / 55.9 / 53.4 / 43.5 |
| toppled: cluster 5m / 1m / 8 m base / drill | 2 / 1 / 1 / 0 | the same | the same |
| memory after a full collection (KB) | 1351 | 1354 | 1354 |

### Engine 0.13 on the device

Kubb Engine 0.9.0 to 0.13.1 (2026-11-21, game 0.10.0 build 10 against 0.11.0 build 11).
The core thinks harder: the pro computer plays `field.line` and `inkast.depth`, and raising
goes by side (0.12: pro `par`, and a person's kubbs by the engine's advice, `par`, a plan
over the kubbs still lying). The check gained two sections for it: **computer decisions**
(one raise decision with eight kubbs lying in a tight group, the whole settle of those
eight in one call, and `autothrow.choose` with eight field kubbs standing in a tight group
and for a toss onto four lying) and **computer turn** (the same through the match scene:
the transition frame where the settle runs, and every frame of the Playdate pro's first
baton at the eight). The 0.9 column is main's build with the same `perfbench.lua` (its
rows that call 0.13's names skip themselves). The frame budget: 20 ms while aiming (50
fps), 40 ms a flight frame (`throw.tune.framePeriod`), and the soak counts frames over 100
and 200 ms.

| Row (device, ms; median) | 0.9.0 | 0.13.1 | 0.13.1 + `device/enginetune` |
|---|---|---|---|
| one raise, 8 lying: apart / par / cpu.raise pro | 0.91 / - / - | 0.85 / 33.6 / 33.2 | 0.93 / 32.6 / 1.34 (apart) |
| settle of the 8: Playdate beginner / club / pro / a person's (advice) | 292 / 293 / 292 / 294 | 290 / 297 / 490 / 482 | 292 / 300 / 298 / 487 (the scene names apart for it: next row) |
| choose, 8 field kubbs standing: beginner / club / pro | 15.1 / 15.4 / 15.0 | 17.2 / 17.3 / 50.2 | 17.1 / 17.4 / 52.2 |
| choose, a toss onto 4 lying: beginner / club / pro | 28.0 / 27.9 / 28.1 | 15.8 / 17.8 / 16.9 | 15.9 / 17.8 / 16.9 |
| choose, the old setups (base / toss / field), pro | 15.0 / 21.7 / 12.6 | 16.5 / 16.3 / 16.6 | 16.9 / 16.6 / 17.1 |
| transition frame: Playdate club / pro raising 8; a person's 8 by RAISING: AUTOMATIC | 315 / 356; 333 | 358 / 550; 535 | 359 / 360; 338 |
| the Playdate pro's first baton at 8 field kubbs: slowest frame / choose frame / flight frame mean | 139 / 55 / 56.6 | 170 / 89 / 54.7 | 121 / 89 / 56.0 |
| plan.solve 1 / 1.5 / 3 / 8 m / drill (0.13: a person's, on the meter at the default arc) | 21.8 / 2.59 / 2.48 / 3.98 / 6.11 | 22.2 / 2.90 / 2.77 / 4.24 / 5.62 | 22.5 / 2.88 / 2.75 / 4.21 / 5.67 |
| aim, replan every frame, 1 m / 6 m | 27.8 / 4.59 | 28.8 / 5.20 | 29.3 / 5.21 |
| aim d-pad 1 m every other / every frame; 6 m | 16.7 / 30.1; 7.8 | 17.0 / 30.3; 8.5 | 17.8 / 31.6; 8.8 |
| new match / save / resume | 79 / 73 / 135 | 79 / 76 / 132 | 80 / 74 / 133 |
| throw frame mean: cluster 5m / 1m / 8 m base / drill | 61.8 / 55.1 / 52.7 / 43.8 | 62.4 / 58.3 / 53.2 / 43.1 | 62.4 / 58.2 / 53.5 / 43.5 |
| memory at launch / after a full collection (KB) | 1336 / 1393 | 1617 / 1449 | 1619 / 1450 |

The throws are not the same throws on the two engines (a baton's default arc goes by the
distance since 0.10, so the plan's clean throw at the cluster from 5 m is lower: it took 2
kubbs, not 1, and played 201 live frames, not 143); their frame time is the same within
the spread. What stalls is the settle: a `par` decision costs 33 ms on the device (about
370 times desktop Lua's 0.06 ms, as `plan.solve` does), and `match.setup` makes every
raise in one call at the end of a turn, with the screen still: eight kubbs went from 292
to 490 ms, and the transition frame from 356 to 550 ms, a half-second freeze. The scene
has no way to spread it, and spreading a still screen over frames would not hide it, so
two plays are switched off on the device, in one place, `source/device/enginetune.lua`
(each with this measurement): the Playdate at pro raises `apart` (`tw.cpu.raising.pro`;
0.12's Gym has `par` and `apart` level at pro against its attacker), and a person's kubbs
raised by RAISING: AUTOMATIC go up `apart` (`scenes/match` names it in core/match's
`raising` for a person's sides when the engine raises them). The advice stays where the
scene spreads it, one kubb a view: the end the raise view offers first and REST OF GAME
(33 ms once a kubb). `field.line` and `inkast.depth` stay on: the pro's choose with eight
field kubbs standing is 50 ms (15 on 0.9), the choose frame 89 ms once while its aim
shows still for `cpuThink`, under the soak's 100 ms. What the engine could offer for the
Playdate: a `par` that costs what `apart` does (an incremental plan over the kubbs still
lying, kept between the raises of one settle, or a cap on the pairs it weighs) or a budget
per decision, and a `match.settle` that can stop after one raise so a client can spread a
settle over frames behind an animation.

### Engine 0.15 on the device

Kubb Engine 0.13.1 to 0.15.0 (2026-11-22, game 0.11.0 build 11 against 0.12.0 build 12,
the same device, one run each of the performance check; 0.12.0's check has a **kid match**
section and Kid in the per-level rows, which 0.11.0 skips). Nothing a player feels moved:
every row common to both is the same within its spread. The one new cost is the Kid rules'
fair spot (`raising.fairSpot`, where a kubb out twice is stood instead of a punishment
kubb): it scans the whole half on the engine's 0.1 m grid with no early exit, 125 ms a spot
with eight kubbs lying in the half, made inside the settle at the end of a turn (a frame
already about 340 ms). `device/enginetune` searches it on a 0.2 m grid (4.: still a valid
spot, within about 0.15 m of the engine's; `test_enginetune`): 42.5 ms.

| Row (device, ms; median) | 0.11.0 (engine 0.13.1) | 0.12.0 (engine 0.15.0, tuned) |
|---|---|---|
| plan.solve 1 / 1.5 / 3 / 8 m / drill | 22.46 / 2.99 / 2.89 / 4.46 / 5.70 | 22.47 / 2.82 / 2.71 / 4.16 / 5.74 |
| one raise, 8 lying: apart / par / cpu pro | 0.89 / 31.75 / 1.26 | 0.91 / 33.81 / 1.31 |
| settle of the 8: Playdate beginner / club / pro / a person's (advice) | 289 / 298 / 298 / 486 | 292 / 299 / 299 / 490 (kid 290) |
| choose, 8 field kubbs: beginner / club / pro | 17.3 / 17.1 / 52.1 | 17.2 / 17.2 / 52.8 (kid 17.5) |
| transition frame: Playdate club / pro raising 8; a person's 8 automatic | 358 / 320; 338 | 358 / 358; 337 |
| the Playdate pro's first baton at 8 field kubbs: slowest / choose / flight mean | 108 / 86 / 56.6 | 117 / 86 / 56.4 |
| aim, replan every frame, 1 m / 6 m | 27.4 / 5.44 | 28.1 / 5.34 |
| aim d-pad 1 m every other / every frame; 6 m | 16.5 / 29.4; 8.4 | 17.0 / 30.2; 8.4 |
| new match / save / resume | 80 / 75 / 133 | 81 / 98 / 132 |
| throw frame mean: cluster 5m / 1m / 8 m base / drill | 62.4 / 58.3 / 53.1 / 43.2 | 62.4 / 58.3 / 53.4 / 43.4 |
| memory at launch / after a full collection (KB) | 1619 / 1450 | 1680 / 1500 |
| Kid: plan.solve on the Kid meter 2 / 3 / 6 m / drill | - | 2.43 / 2.75 / 3.35 / 6.31 |
| Kid: the Kid computer's choose, base / toss / field | - | 15.1 / 14.2 / 14.1 |
| Kid: fair spot, 8 lying in the half (engine grid / 0.2 m) | - | 125.3 / 42.5 |

`par` still costs 33 ms a decision, so enginetune's 1. and 2. stay. Save's 98 ms is one run
(73 to 105; the untuned 0.12.0 run had 75). The soak on 0.12.0 (match 3 a Kid match against
the Kid computer, `soak.tune.kid`): 3 matches, no error, 42 save checks, none failed, 59426
frames, 258 over 200 ms in 41 minutes; the slowest frame 393 ms (a flight ending, as on
earlier builds). An earlier, untuned run's first match had one 987 ms frame where a turn
ended (rest to aim: a settle); the tuned run's three matches had none over 393, and no
standard match's settle path changed between the engines.

### Engine 0.16: the drive

Kubb Engine 0.15.1 to 0.16.0 (2026-11-22, game 0.12.1 build 14 against 0.13.0 build 15).
The check gained a **drive** section (a drive's `plan.solve` at the floor and
`plan.arcFloor` at 1.5 and 3 m, then the aim at a kubb 1.5 m from an advantage line
through the scene's update: nothing pressed, B held, B held with down tapped to the floor
and back, with the `plan.solve` calls each part made) and a **drive 1.5m** throw (the
default at a cluster 1.5 m from an advantage line). In the Simulator (the Mac, not the
device; for the shape only): nothing pressed makes no solve; B held makes none (the floor is
not worked out until B + down); down to the floor and back makes one floor solve and one
plan solve a step. The floor at 1.5 m costs 0.60 ms there and at 3 m 4.8 ms (the bisection:
every step a `speedForCarry`), against 0.17 for a default plan; in desktop Lua 0.06 and
0.52 ms against 0.02. By the ratio of `plan.solve` at 1 m (22.5 ms on the device, 0.08 in
desktop Lua) the floor from 2 m out is about 150 ms on the device: once when B + down first
steps ARC at a throw (a still frame with the camera out), and the scene never pays it per
frame (docs/notes/throw.md "The drive": the floor is kept, and a kept drive raised to a new
floor waits while the circle moves).

What the engine could offer for the Playdate: a floor that does not cost 24 carries (the
floor is where the planned speed reaches `speedFor(driveBackMaxDeg)` or the line stops
being one the hand can make: a closed form for the drag-free carry, then a few secant
steps, or a regula falsi from the knee), so that `plan.arcFloor` and a plan raised to the
floor cost what a default plan does.

The soak (`source/soak.lua`) is QA, not a benchmark: an empty file named `soak` in the same
Data folder runs `soak.tune.matches` (3) whole scripted matches once at launch (after any
autobench; since 0.12.0 the third, `soak.tune.kid`, a Kid match against the Kid computer), at a player's real pace through `scenes/match` (playback, slow motion, camera,
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
practice pitch's System Menu "Pitch": "readout" and "bench", and records the crank traces
("Crank traces" below) (`tw.debug`, read once at launch). Without it a player sees only play, how to, reset, drill, batons, the surfaces and
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

## Frame-time log

To tell the deliberate slow motion from dropped frames, every throw (practice and match)
appends one JSON line to `frames.jsonl` in the Data folder (`source/framelog.lua`, on outside
self-tests, no menu item; the line is `device/frametel.encode`, written once in the throw
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

Traces are recorded only while the `debug` file is in the game's Data folder at launch
(above; Jamie's Settings sheet, 2026-11-20: "yes this is debug info, move it."). Until
then the System Menu had a "Record" item, on by default; it is gone, and a player's
System Menu has no recording switch. Self-tests leave it off. To collect traces: put an
empty file named `debug` in the Data folder (on the device: `pdutil <port> datadisk`,
then `Data/com.throwingwood.playdate/` on the PLAYDATE disk; Simulator:
`~/Developer/PlaydateSDK/Disk/Data/com.throwingwood.playdate/`), relaunch the game, throw,
and copy `traces.jsonl` (and `traces-1.jsonl`) off. Every swing is appended as one JSON
line to `traces.jsonl`. Without the file nothing is written, and traces already on a
device stay where they are, never deleted (a device that recorded before this keeps its
files). The file is capped: past `logcap.maxBytes` (1 MB, about 750 swings) it becomes
`traces-1.jsonl`, replacing an older one, and a new one starts (`source/logcap.lua`;
checked before each line; at most about 4 MB of logs in all). Read both when collecting.
The format is documented at the top of `source/core/trace.lua` (samples are
`[dt, raw crank degrees]` per frame from the first wind-up frame to release or let-down,
not the cooldown after a release, plus the result: what the swing measured, then the
plan and the launch, "The throw"). kubb-engine's `lua5.4 tools/replay_traces.lua <file>` replays each
line through the current `core/swing.lua` and prints recorded vs replayed results;
`--current-sign` replays with today's `forwardSign` instead of the recorded one. The test
fixture is `tests/fixtures/traces/sample.jsonl`. Drill lines add the fields in "Drilling"
above; `replay_traces` reads them like any other line (the swing is the same).
