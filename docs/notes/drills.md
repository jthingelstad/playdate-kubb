# Practice drills and drilling

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

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
  30 cm would score a perfect swing 38% of the time). Since the friction in the bounce
  ("Physics", 2026-11-16) it is 51% at half past 1 (median 49 cm) and 26% at loft 30
  (median 68 cm), a clean run about 3.1 of 6; the same count just before gave 62% and 47%
  (3.7 of 6). THE WALL is harder too: six clean drills at the stake build 0.19 on average
  over 90 grounds (0.60 before; `test_drills`).
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
  most likely ends, not where every one does (it runs on 0.17 to 1.44 m, p10 to p90 on
  grass at half past 1). `plan.launch` judges the swing and gives the
  body through `drill.body` (noseDown, rollLand, spin, wobble). The aim camera is
  the baton's ("The aim camera": first person behind the thrower, looking past the circle,
  and the plan view while B is held, with the drill's planned arc; it replaced
  `camera.drillAim`, the fixed high drill view, 2026-11-15); the ring, cross and dotted line are drawn over it each frame (`drawMarker`),
  and the minimap's aim line goes to the circle. Self-test `clock-drill` (a drill at half
  past 1 with a tap of spin rests within 1 m of the circle on the Simulator: 0.72 m since
  the friction in the bounce, 0.16 when the run on was measured again with the air's
  drag, 0.28 since the bite, 0.18 before it,
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
  mean / p10 / p50 / p90 / max, rest from the circle, touch to rest): half past 1 0.76 /
  0.17 / 0.68 / 1.44 / 2.53 m, 51 cm, 0.84 s; loft 30 1.36 / 0.59 / 1.26 / 2.27 / 3.98
  m, 69 cm, 1.04 s. Sand 0.21 m at half past 1 (p50 0.15, p90 0.49; 26% dead stops under
  5 cm), 0.45 at loft 30 (p50 0.35, p90 0.94; 6%); snow 0.83 and 1.39 (no bite: packed
  snow lets an edge skate). It ends turned every way (yaw to the throw 0-30 / 30-60 /
  60-90: 50 / 30 / 20% on grass at half past 1). Measured after the friction in the
  bounce (2026-11-16, `tools/drillscatter.lua --only 3`), with the aim allowance measured
  again. Before it (the same tool, the table then): grass mean 0.95 / p10 0.44 / p50 0.88
  / p90 1.53 m at half past 1, 1.53 / 0.82 / 1.38 / 2.47 at loft 30, rest 42 and 56 cm;
  sand 0.26 (p50 0.19, p90 0.57; 11% dead) and 0.50 (p50 0.37, p90 1.00; 1%); snow 0.96
  and 1.51.
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
  never under 0.5 m) and `drill.solveAt` lands the kubb there. Grass at half past 1: 0.18
  m from 1.5 m, 0.70 from 4.5, 0.31 from 7.5; low lofts run on most (1.84 m at loft 26
  from 4.5 m). Measured again once an impact's friction was solved in the bounce
  ("Physics", "Friction in the bounce", 2026-11-16): the cells fell by 0 to 0.67 m (grass
  at half past 1 was 0.20 / 0.88 / 0.63, loft 26 from 4.5 m 1.94), and the clean drill's
  mean rest along the throw from the circle (`--only 3`) went from -8 / -25 cm with the
  old table to +5 / -1 cm (grass, half past 1 / loft 30), sand +2 / 0, snow +2 / +1.
  Before that, measured after the nine physics audit items (2026-11-16, with the
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
  Since the friction in the bounce the run on is shorter but wider for its length, and
  those two bounds are 0.7 m and 30%: `test_throwplan` 0.59 m off, `test_autothrow` 0.60
  m and 15 of 40 in.
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
