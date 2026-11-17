# Physics

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

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
  throw comes down where it is aimed: the world's centre within 0.1 mm of `carry` with no
  drag and about 2 mm with it (`carry`'s own step), since the flight's position is
  stepped by the trapezoid (below, "Free flight"). Before 2026-11-16 the world came down
  2 to 4 cm short and 2 to 4 ms early, the fixed step's error. `plan.solve` costs 11 us (baton) and
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
- Sleep (`world.step`, phase 8): a piece sleeps once it has moved slower than the sleep
  thresholds for `sleepTime` while held up. Held up means one of these, in that step:
  - it pressed on the ground;
  - it pressed on a sleeping or static piece (`b.restStep`);
  - it pressed on an awake piece that is itself on the ground or on a sleeping or static
    piece, or asleep (`b.propStep`, `b.propBy`).

  Until 2026-11-16 only the ground counted, so a kubb lying flat on a lying kubb stayed
  awake at 0.00 m/s for the full 12 s. Pieces pressing on each other also wait for each
  other: one that is ready waits while an awake piece it presses on (`b.mateStep`,
  `b.mateMin`, the least of their sleep timers) still needs more than a step, so they sleep
  in the same step. One that slept first left the other the warm started push from the
  ground for their shared weight, which kicked it and woke the sleeper again (a kubb woke
  6 times and the baton on it 5, until 11.8 s; 1:1658). A piece knocked later still wakes
  everything it touches (`test_physics`: "a kubb resting on a lying kubb sleeps, and wakes
  when the one under it is knocked"). The record is three numbers and a reference on each
  body, set in the store loop: no tables in the step.
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
- **Free flight** (2026-11-16, from the reference engine's finding 3). A body with no
  contact this step moves by the trapezoid: x += (v before the step's forces + v after) / 2
  x dt, which is exact under gravity alone and drops nothing of the drag's turn. Until
  then it moved by the step's end velocity (x += v dt after v += g dt), which loses g dt^2
  / 2 a step: over a flight 2.0 to 2.9 cm short and 2 to 4 ms early at every loft and
  speed against MuJoCo and `flight.carry`. Now within +0.05 to +0.34 cm and +0.1 to +0.5
  ms of MuJoCo (`make mjref`, flight cases; their D 0.54 -> 0.05 at most). A body with any
  contact record this step (`b.cStep`, stamped in stage 3) moves as before, so contacts,
  rests and stacks are untouched. Both copies (the full step's stage 5 and the lone flight)
  do it the same way; the velocity before the forces is kept per awake body in `OVX`,
  `OVY`, `OVZ` (file scope, no tables a step). Cost: an add and a multiply per coordinate
  (`make bench`: lone 0.001, air 0.005, ground 0.010 to 0.011, multi 0.016 to 0.017 ms
  a step, the same as before within the bench's resolution). `test_wind` now measures its
  crossing at 0.2 m, in the air: an upright baton touches the ground with its centre
  about 0.15 m up and pivots, so a crossing at 0.15 m measured the landing. Not
  bit-identical: every throw (a launch 2 to 3 cm longer at the same speed).
- **The turn in flight** (2026-11-16, from the reference engine's finding 2). A drilled
  kubb in the air (the projectile with `b.aeroK`, until its first contact) takes the air's
  turn and the gyroscopic term in `world.tune.flightTurns` (4) substeps of the step, in
  `flightTurn`, called by the lone flight and by stage 5 of the full step (stage 1 skips
  both terms for it). It works in the kubb's own frame: the air past it is turned against
  the spin each substep, the air's turn is a kick to the two cross axes, and a kubb's
  square section (Ix = Iy) makes the gyroscopic term an exact turn of the cross spin at
  (Ix - Iz) wz / Ix (Euler's equations). The attitude is normalized and the rotation and
  world inertia made once at the end, so it costs about a third more than one plain step
  for that body (lone drill step 1.5 -> 2.0 us on the desktop), nothing for anything else.
  Before, both terms were applied once a 1/240 s step to a kubb spinning at 25 to 69
  rad/s: up to 3 degrees too steep at the touch. The nose in flight, the last sample
  before the touch, against MuJoCo (72 drill cases): within 0.5 degrees (mean 0.11),
  was 2.9 (mean 1.28); at 240 Hz now within 0.2 degrees of the same engine at 9600 Hz.
  A baton is left alone: its slower turn moves its landing by 0.02 degrees, and
  substepping it changed the bench scenario for nothing. What players get: the same
  drills, the nose at the touch 0.2 degrees less steep on average, run-on within noise
  (`tools/drillscatter.lua --only 3`, grass loft 30: median 138 cm, was 139).
- **Friction in the bounce** (2026-11-16, from the reference engine's finding 1). Stage 7
  of `world.step` (the restitution passes) now solves each contact's friction as well as
  its normal, capped at mu times the contact's whole normal impulse (`r[K_LN]`, the bias
  passes' and the bounce's together). `solve(tk, list, n)` runs over a list: stages 4 and
  6 pass every record (`REC`), stage 7 the bounce group (`BOUNCE`, file scope): the
  contacts that bounce, with their target -e v0 in `r[K_REST]`, and the other contacts of
  the pieces that bounce, held at their relax target. Before, friction was solved only in
  the bias passes, which for a speculative contact take only the approach speed past the
  gap still to close; the rest of the impact and the bounce came with no friction. So a
  landing kept 0.56 to 0.89 of its speed along the ground (mean 0.75, by where the step
  fell) against Coulomb's and MuJoCo's 0.41. Now (`make mjref`, landing cases, bare):
  - speed kept: grass 0.47 to 0.51 (MuJoCo 0.41), sand 0.35 (0.28), snow 0.82 (0.80);
  - the same landing started 2, 6 or 10 mm up: spread 0.02 on grass (was 0.33), 0.04 on
    sand (0.33), 0.00 on snow (0.07);
  - run on, median: grass 1.10 m (MuJoCo 1.15, was 2.56), sand 0.62 (0.74, was 1.56),
    snow 6.99 (7.01, was 8.16);
  - D by scenario, before (main at 5160562) -> after (on top of the `capsuleBox` clip):
    broadside 0.087 -> 0.031, domino 0.059 -> 0.041, drill 0.192 -> 0.072, end on 0.272
    -> 0.138, king 0.158 -> 0.030, landing 0.639 -> 0.430, tip 0.027 -> 0.025; drop
    0.083 -> 0.104 (a kubb dropped on sand at 1 m/s
    bounces 0.020 of its speed, was 0.010, against 0.03 asked and MuJoCo's 0).
  The held contacts get friction too. Without it (tried) the king, broadside and end-on
  cases move back toward before (king D 0.124) and a row of two struck 7 cm apart falls
  as before; with it, a row of four face to face struck on the front kubb falls less
  than MuJoCo's at low power (below; fixed 2026-11-17 by the next item). The turf terms (`texture.drag`, `grip`, the
  bite) are not retuned: none was tuned against the shortfall (drag and grip came for
  the creep and the slide on an end, the bite on Jamie's word), and the turf now takes
  the same share of a landing as before or less (game against bare run on: grass 0.49 ->
  0.64, sand 0.33 -> 0.37, snow 0.26 -> 0.29). `drill.tune.slide` is measured again
  ("Drilling", "The aim allowance"). Cost (the desktop, best of 30): lone 0.001, air
  0.005, ground 0.010 to 0.011 ms a step as before; multi 0.016 to 0.017 -> 0.018 and the
  bench throw 0.0131 -> 0.0146 to 0.0149 ms (about a tenth more where pieces collide: the
  bounce passes now run the friction rows too); the whole match case 0.005 to 0.006 as
  before. Not bit-identical: every throw with a contact. What players get:
  - a baton kicks on less after landing: the 8 m/s test throw 0.21 m on grass in play
    (0.55 bare; MuJoCo bare 0.48; was 2.98 bare), and over the kick sweep (loft 35, 6 to
    9 m/s, tumble 5 to 9) grass median 0.19 m in play (was 0.82), bare 0.41 (MuJoCo 0.46);
  - batons that skip off the grass arrive at the kubb with about half their speed (2 to
    4 m/s, were 4 to 8); `tools/groundstats.lua` grass slide after touching down 1.01 m
    (was 1.50), hits 7.3% (12.7%);
  - a clean drill runs on less and spreads wider for its length ("Drilling", "On the
    ground"): grass at half past 1 median 0.68 m, p10 0.17, p90 1.44 (was 0.88 / 0.44 /
    1.53), loft 30 median 1.26 (1.38); sand median 0.15 and 0.35 (0.19 and 0.37), dead
    stops 26% at half past 1 (11%). Against `docs/reference/REALCLIPS.md` pass 2 (119
    tournament drills; `tools/drillscatter.lua --only 3` now prints its measures), grass
    at half past 1, real / before / after: run on any direction median 0.22 / 0.88 /
    0.68 m; under 0.3 m 61% / 4% / 19%; 0.43 m or more 13% / 91% / 68%; along the throw
    median +0.02 / +0.86 / +0.57 m, p10 -0.16 / +0.38 / +0.12; behind the touch 11%
    (clearly) / 0.3% / 1.0% (at all); last visible motion median 0.37 / 0.42 / 0.50 s.
    About a third of the gap in the median; the rest is the next item. BLAST and THE WALL score less for a clean drill ("Practice
    drills");
  - struck kubbs slide less, and touching rows fall less from one baton:
    `tools/compound.lua --quick`, four in a line face to face, one or more down 75.3%
    of hits (was 98.7), two or more 27.3% (69.3); 3 cm apart 61.5 / 10.3% (94.9 / 32.1);
    before measured at 5160562, after with the `capsuleBox` clip. Since the next item
    (2026-11-17): 93.5 / 53.2%, all four 35.1%; 3 cm apart 76.9 / 17.9%.
    Against MuJoCo, the same 100 throws from 0.03 s before the first touch (grass, bare):
    on the row of four, when the baton reaches the row, MuJoCo fells exactly one (the
    back kubb, the front three leaning) in 60 of 60; ours one in 48, none in 12 (were
    one in 53, two in 6, three in 1, with the `capsuleBox` clip). On a row of two 7 cm
    apart MuJoCo fells 1.33 on average (none 1, one 38, two 21); ours 1.33 (was 1.77,
    two in 46). Since the next item: one or more in 60 of 60, and 1.50 on the row of two.
  - matches (`make realgames`, 150 games, seed 2; real games / before / after, both
    with the `capsuleBox` clip): turns a game 8.9 / 20.2 / 18.7; batons that missed 24.7
    / 14.5 / 18.2%; took two 16.0 / 12.1 / 5.7%, three or more 10.0 / 1.6 / 0.1%;
    cleared every field kubb 83.4 / 61.9 / 63.1%; base kubb from the baseline 32.7 /
    27.6 / 25.6%; the king 83.8 / 94.9 / 94.5%. Shorter games and more misses, nearer the real ones; fewer multi-kubb
    batons, farther from them ("Tuned toward the real games"). The next item's figures
    supersede these.
  `make physfuzz N=2000 SEED=1`, before (main with the `capsuleBox` clip) -> after
  (failed throws): energy 5 -> 5, penetration 14 -> 12, rest 22 -> 26, finite 0 -> 0, dt
  18 -> 20 (marginal 169 -> 88), mirror 2 -> 3 (marginal 58 -> 47); 1163 -> 1087 pieces
  toppled at 240 Hz against 1114 -> 1080 at 480 Hz. Of the five energy rises four are
  under 0.03 J; one drill nose first into a lying kubb (1:728) gains 0.72 J in the step
  after, in the push out of the overlap the impact left (the bias passes); the same
  state stepped by the engine before this change gains 0.08 J. Left open. Before the
  clip (main at 5160562) the change took penetration 83 -> 68 and added a baton glancing
  off a kubb's upright edge that rolled about its own axis at 204 rad/s (1:1177, limit
  200); with the clip that throw is clean.
- **The bounce reaches the row** (2026-11-17). After "Friction in the bounce" one baton
  fell far fewer kubbs from a row of touching kubbs (`tools/compound.lua --quick`, four
  face to face, all four down 16.2% of hits -> 0). The friction was right; three things
  in stage 7 kept the push from crossing the row, plus a warm start bug they exposed:
  - The bounce group stopped at the pieces that bounce and their own contacts, so the
    front kubb's friction and bounce were solved against a second kubb held at its relax
    target, and the third and fourth never saw the impact inside the step. Now the
    group spreads (an island, no tables: a mark on the body) through every pressing
    contact between two awake pieces (kind 2) to all the pieces pressed against them.
  - Four bounce passes do not carry a push across four bodies. When the spread added a
    body (`row`), the passes now run until no impulse changes by `restitutionTol`
    (1e-4 N s), up to `restitutionMaxIterations` (32); a row of four settles in 10 to
    30. Any other bounce keeps `restitutionIterations` (4). Run to convergence there
    too (tried), a sliding contact's friction and its push fed each other pass after
    pass (a spinning baton's corner swung between all of its bounce and none, 1:822; a
    baton on a kubb on the ground crept, 1:669), and the fuzz's energy rises went from 5
    to 24. A joint solve of the sliding and normal rows (tried) left 16 to 17. Row only:
    6. Only the islands that grew go past four (`b.rowStep`, spread like the bounce mark): a bounce elsewhere in the same step keeps its four passes (Codex on #145). `world.bouncePasses` counts the passes.
  - B's arm in a pair record was taken at A's surface, across the speculative gap, so a
    gap-open contact turned B about the wrong point. It is now `p - n*sep - B.pos`.
  - The ground warm start was applied as each record was built, so a body's later
    corners read their approach speed with the earlier corners' warm start in it (a
    resting kubb's corner read -4.03 m/s and bounced: an energy rise in the fuzz,
    1:1305). It is now applied in one loop after every record is built.
  Measured (main at ae88c82 -> this):
  - `tools/compound.lua --quick`, one or more / two or more / all, before "Friction in
    the bounce" / main / now: four touching 97.3 / 74.3 / 16.2, 75.3 / 27.3 / 0, 93.5 /
    53.2 / 35.1; four 3 cm apart 96.2 / 47.4 / 15.4, 61.5 / 10.3 / 0, 76.9 / 17.9 / 1.3;
    three touching 97.3 / 85.1 / 74.3, 98.7 / 81.3 / 62.7, 98.7 / 89.3 / 81.3; three 3
    cm apart 97.4 / 75.0 / 67.1, 94.9 / 60.3 / 33.3, 98.7 / 71.8 / 52.6. Two behind,
    two or more: 7 cm 79.7 / 62.7 / 66.7, 30 cm 54.1 / 54.3 / 62.9. Side by side about
    the same. The match sample, two or more toppled 12.2 / 5.1 / 6.1%.
  - Against MuJoCo (100 throws from 0.03 s before the first touch, grass, bare): the row
    of four, one or more down in 60 of 60 (MuJoCo 60, main 48); three touching agree in
    58 of 60 (main 49); the row of two 7 cm apart 1.50 on average (MuJoCo 1.33, main
    1.33); the row of four struck at the ground 0.57 (MuJoCo 0.82, main 0.17); one kubb
    felled 59 of 60 (MuJoCo 60, main 58), in the air 0.2 s or more 43 (MuJoCo 47, main
    30; mean 0.276 s against 0.322).
  - `make mjref`: the landing cases unchanged (grass 0.47 to 0.51 kept, spread 0.02,
    run on 1.10 m; sand 0.35 / 0.04 / 0.62; snow 0.82 / 0.00 / 6.99). D by scenario:
    broadside 0.032 -> 0.028, domino 0.038 -> 0.043, drill 0.075, drop 0.104, end on
    0.129 -> 0.125, flight 0.025, king 0.031 -> 0.029, landing 0.432, tip 0.025.
  - `tools/batonprobe.lua` (725 touched): toppled 621 -> 619, bounce backs 5 -> 4,
    flew 0.2 s or more 221 -> 260, end first spin lost 106 -> 105.
  - `tools/drillscatter.lua --only 3`: unchanged within a point (grass 47, run on
    median 0.68 m, under 0.3 m 19%, 0.43 m or more 68 -> 69%, along the throw +0.57,
    behind the touch 1.0 -> 1.4%).
  - `make realgames` (real / main / now): turns 8.9 / 18.7 / 19.1; missed 24.7 / 17.6
    / 17.9%; took two 16.0 / 5.7 / 6.3%, three or more 10.0 / 0.2 / 0.2%; cleared 83.4
    / 63.1 / 61.7%; base kubb from the baseline 32.7 / 25.7 / 25.7%; king 83.8 / 94.5 /
    96.6%. Matches barely move: match groups are seldom touching (0.4% of hits).
  - `make physfuzz N=2000 SEED=1`: energy 5 -> 6, penetration 12 -> 12, rest 1 -> 3
    (wake cycles in rows: 1:699, 1:1458, 1:1272), finite 0, dt 20 -> 22 (marginal 88 ->
    83), mirror 3 -> 4 (marginal 47 -> 38); 1:728 rises 0.56 J (was 0.72); toppled 1087
    -> 1110 at 240 Hz, 1080 -> 1089 at 480 Hz.
  - `docs/reference/REALCLIPS.md`: a tight group fell whole 2 of 9 (6 to 55%), groups of
    four or more 0 of 6 (0 to 39%), two or more 8 of 9 (56 to 98%). Ours: four touching
    all 35% (inside), three touching all 81% (above), two or more 53 to 89%.
  - Cost (`make bench`, desktop): 68.0k -> 64.6k steps a second, collision phase 0.051
    -> 0.054 ms a step (with debris 0.055 -> 0.058), multi 0.016 -> 0.017; lone, air,
    ground and the match case as before.
  - Tests: the row hard blow back to 2.0 N s (C had raised it to 2.5); the baton hits
    bound now `flew <= 0.5 * touched`; `kubb-on-kubb-sleeps` launches at 0.98; THE WALL
    best one or more (0.10 grounds on its thirty seeds, one at best; 0.17 and two over
    ninety, 0.20 on main). Not bit-identical: every throw that touches two pieces.
  Still open: the side pass (6 cm to the side of a row, 1 mm clear in MuJoCo, ours
  touches), and three touching falling whole more often than the clips.
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
  - **A baton along a face or an edge** (physics fuzz, 2026-11-16). `collide.capsuleBox`
    made one contact at the closest point, plus the end spheres. A baton lying along a
    kubb's edge or face turned about that one point and its other half sank in: 66 mm into
    the king (1:5977), 19 mm along a kubb's upright edge (1:66). Now, once the closest
    point is within the margin, the segment is clipped to the feature that point is on (a
    face spans two of the box's axes, a rounded edge one, a corner none), and each end of
    the clipped piece more than `CLIP_GAP` (4 cm) from the closest point gets its own
    `sphereBox`: two or three contacts along a face, never a contact off the box. The
    closest point is found on the box less its rounding (as `sphereBox` meets it), and
    either end of the baton is taken instead when it is nearer: for a baton nearly
    parallel to the box the projection creeps, and Codex (PR #139) found an end 2.3 mm
    into the king's rounded edge while the projected point was 5.9 mm clear. A baton
    whose nearest point is beyond the margin returns at once, so flight costs no more.
    A gap of 10 cm left 1.25% penetration in a quick fuzz against 0.50% at 4 cm. The
    pinned cases are `baton-across-kubb-edge` (1:352, 10.9 -> 0.7 mm) and
    `baton-across-king-foot` (1:1227, 22 mm -> none).
  - **Still open: a baton turning about a rounded edge.** Since the flight fix (2026-11-16,
    the trapezoid move) the launches of 1:66 and 1:5977 come down elsewhere, and with the
    clip they still reach 7.4 and 25.5 mm (35 and 65 mm without it). The solver holds
    every contact it is given (after the passes each pushes apart); the overlap grows at
    points it was not given, because the baton swings about a rounded edge and the edge's
    normal turns 10 to 75 degrees a step. With the restitution passes off, 1:66 stays
    under 5 mm.
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
    moved down at up to 2.17 m/s with the old passes at 0.35 and 0.78 m/s with the fix
    (limit 1). Since the `capsuleBox` clip (2026-11-16) the test counts only the steps
    where the baton touches the kubb: one throw kicked the kubb into the air, and its
    landing on a corner a quarter second later, tumbling at 23 rad/s, came down at
    1.55 m/s. That is a landing, not this fault. While touching, the worst is 0.01 m/s.
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
