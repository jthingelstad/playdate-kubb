# Reference engine

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

## Reference engine

`make mjref` (`tools/mjref/`, 2026-11-16) runs the same throws through `core/world` and
through MuJoCo, a general rigid-body engine. Where the two disagree, our collision model is
the first suspect. The comparison checks mechanics, not materials: both engines get the
game's own sizes, masses, inertias, friction, bounce and rolling resistance. The report
goes to `build/mjref/report.md`, with every number in `report.json`.

- Setup: any Python 3 with `mujoco` and `numpy`. Create a venv anywhere
  (`python3 -m venv <dir>`, then `<dir>/bin/pip install mujoco numpy`), then
  `make mjref MJPY=<dir>/bin/python`. `MJPY` defaults to `python3`.
- Runtime: 5 to 12 minutes on a 10-core Mac, depending on what else is running. Our engine takes 7 s for all 1063 cases in
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
- A drill's nose in flight (`noseDeg`) is read at the last sample before the touch. The
  first sample after it already carries the impact's turn.
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
     falls.** Fixed 2026-11-16 ("Physics", "Friction in the bounce"): a landing keeps
     0.47 to 0.51 of its ground speed on grass (MuJoCo 0.41), the same from any step
     phase, and runs on 1.10 m (MuJoCo 1.15). What it was:
     - A baton landing at 0 to 60 degrees kept 0.56 to 0.89 of its ground speed (mean
       0.75) against MuJoCo's 0.41, and ran on 2.5 m against 1.2 on grass, 1.4 against
       0.75 on sand. Started 2 or 10 mm up, the same landing kept 0.59 or 0.79.
     - Cause: friction was solved only in the bias passes, capped at mu times the normal
       impulse found there, which for a speculative contact removes only the approach
       speed past the gap still to close. The restitution passes (stage 7) then added the
       rest of the impact and the bounce with no friction.
     - The turf drag and grip were not tuned against it (they came for the creep and the
       slide on an end) and are unchanged; `drill.tune.slide` was measured again.
     - A row of four face to face struck at low power, where MuJoCo fells the back kubb
       every time and ours felled none in 12 of 60, is fixed 2026-11-17 ("Physics", "The
       bounce reaches the row"): 60 of 60. Still open: when the baton
       passes 6 cm to the side of the row, 1 mm clear of it in MuJoCo, ours touches it.
  2. **A drill's attitude in flight is limited by the time step.** Fixed 2026-11-16
     ("Physics", "The turn in flight"): the nose in flight is now within 0.5 degrees of
     MuJoCo in every drill case (mean 0.11; was 2.9, mean 1.28). What it was:
     - The headline (loft 30, one tap: 51 degrees against MuJoCo's 40) was mostly the
       metric. It read the first sample after the touch, when the impact is already
       turning the kubb. `compare.py` now reads the last sample in the air: 39.7 degrees
       against 37.1 before the fix, 37.1 against 37.1 after.
     - The step error was real but small: `aeroTurn` and `gyro` once a 1/240 s step, up to
       3 degrees too steep.
     - Not a defect: one tap rolls a drill sideways most and lands it lowest (33 to 37
       degrees, yaw 22 to 37 degrees at the touch). That is precession under the air's
       turn. It is converged (the same at 240 Hz with substeps, 2400 and 9600 Hz) and
       MuJoCo agrees. Left and right differ at one tap because the wrist's spiral makes
       them -19 and +25 rad/s; with `drill.spiral=0` they mirror exactly.
  3. **Free flight lands 2 to 3 cm short of the aim.** Fixed 2026-11-16 ("Physics",
     "Free flight"): the flight is stepped by the trapezoid and lands within +0.05 to
     +0.34 cm and +0.1 to +0.5 ms of MuJoCo. What it was:
     - MuJoCo matches `flight.carry` to 1 mm. Ours comes down through 0.3 m 2.0 to 2.9 cm
       short, and 2 to 4 ms early, at every loft and speed (7.18 against 7.21 m at loft 30,
       9 m/s).
     - Cause: `world.step` and the lone flight integrate semi-implicitly (v += g dt, then
       x += v dt), which drops g dt t / 2. `flight.carry` integrates by midpoint.
     - Fix: in flight, x += v dt + g dt² / 2 (one line in each of the two copies), or make
       `carry` step as the engine does. Small, but every aim carries it.
  4. **Low strikes on a standing kubb need 10 to 26 percent more J in ours.**
     - On grass at h 0.02, J is 0.403 in ours against 0.345 (0.435 before the bounce
       friction); at h 0.04 0.320 against 0.296 (was equal). Snow is the same or worse at
       h 0.04 to 0.06 (0.373 and 0.745 against 0.296 and 0.639), and ours is not monotone
       there.
     - High strikes match exactly: grass h 0.08 to 0.14 gives the same J in both, and both
       sit within 7 percent of the rigid-pivot estimate.
     - Iterations (16) and warm starting change nothing. At 960 Hz ours moves to 0.373.
     - Cause: time-step error while the box rotates fast about a sliding edge: the corner
       contacts of `collide.groundBox` at 240 Hz.
     - No cheap fix. Accept it unless play shows foot hits feel wrong.
  5. **Smaller ones:**
     - An end-first landing (phi 90) runs on 4.4 m in ours against 3.5 to 3.9 m (4.2 to
       4.7 before the bounce friction).
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
