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

The System Menu has "Record" (and the practice pitch's "Pitch: readout", the debug line
after each throw). Record is
on by default while the throw is being tuned (self-tests leave it off). With
Record on, every swing is appended as one JSON line to `traces.jsonl` in the game's Data
folder (Simulator: `~/Developer/PlaydateSDK/Disk/Data/com.throwingwood.playdate/`). It
stays on in the builds for players (their recordings are how the throw gets tuned), so the
file is capped: past `logcap.maxBytes` (1 MB, about 750 swings) it becomes
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
