# Physics fuzz

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

## Physics fuzz

`tools/physfuzz.lua` (2026-11-16) looks for physics defects. Each iteration draws one seeded throw the
game could make and runs it to rest the game's own way (`autothrow.choose` and
`autothrow.launch`, then `world.step`). The checks in `tools/physcheck.lua` run after every
step. It then runs the same throw again mirrored and at half the time step. Failures are
grouped into clusters, ranked by how often a realistic throw meets them, and each has a
command that replays it. Everything is pure Lua and lives in `tools/`, so the game does
no extra work for it.

- `make physfuzz N=2000 SEED=1 SURFACE=Grass`, or `lua5.4 tools/physfuzz.lua --n 2000 --seed 1
  [--surface Grass|Sand|Snow] [--only energy,penetration,rest,finite,mirror,dt,aim] [--kind
  baton|kubb] [--top 20] [-v]`.
  - `--repro <seed>:<i>` replays iteration i verbosely:
    - the pieces and the throw;
    - each step's deepest overlap over 2 mm and every rise in energy;
    - the verdicts at 480 Hz, flat and mirrored, and over the launch neighbourhood.
  - The throw is the same whatever `--n`, `--only` or `--kind`.
  - `--dump file [--every n]` writes the trace in `tools/physdump.lua`'s format.
  - `--case` prints the throw as a pinned case.
  - `--set world.key=value` (or `collide.`, `check.`) tries a tunable.
  - `--dist` prints each check's worst value per throw as quantiles. Set a threshold to 0 to
    see every throw's value.
  - `--selftest` checks that the monitor and the replayed launch leave every throw the same,
    bit for bit (60 iterations: 56 throws, 0 differences).
  - `--grid drill|tilt [--seeds 24]` sweeps a control exhaustively, on every surface unless
    `--surface` is given:
    - drill: every spin tap at releases 105, 135 and 165, with the mark 4.6, 6.0 and 7.5 m
      out, into an empty far half;
    - tilt: every tilt at a lone field kubb from 3, 5.27 and 8 m, at releases 60 and 90.

    Throw k of a cell draws the mark's x, the ground and the swing, the same for every step
    of the control. Odd k are clean and even k are the computer at club (aim error). The
    output has:
    - a table for each cell: the checks' failures, and for a drill the run-on from the first
      touch, its sideways part, the rest from the mark (`tools/drillscatter.lua --only 3`'s
      measures), and how many rest in the far half;
    - a table for each step of the control, with the sideways part's standard error;
    - a line on whether the sideways part is monotonic (no step goes back by more than 2
      standard errors) and mirrored (side(+k) - side(0) against side(0) - side(-k)).

    The drill grid takes 12 s (4536 throws) and the tilt grid 14 s (3888).
- **What a throw is.** Each throw has a realism class, which weights the "realistic rate":
  - clean (15%, weight 1): no mistakes;
  - real (55%, weight 1): the computer at club, scale 1;
  - loose (15%, weight 0.5): beginner;
  - wild (15%, weight 0.1): beginner at 2.5 times the mistakes, with tilt up to 25 degrees,
    tumble x0.5 to 1.6 and speed x0.85 to 1.15.

  The target splits as follows: a drilled kubb 20%, a baton at field kubbs 40%, at base kubbs
  28%, at the king 12%.

  The far half's layout is one of these:
  - a lone kubb;
  - a row along or across the throw, at gaps of 0, 5, 10, 30 or 70 mm;
  - a cluster of 3 to 6 with some lying;
  - a kubb leaning 8 to 22 degrees on a lying one;
  - groups and debris by the basket.

  Base kubbs are each missing one time in five. Two in five throws move the arc by up to
  45 degrees.

  The throw also carries the B + left/right control as the throw scene sets it. A drill's spin
  taps are uniform over -3 to +3. A baton's tilt is 0 half the time, otherwise ±5 to ±20.
  `autothrow` plans with neither, so `withControls` passes them to `plan.solve` (`q.spin`,
  which `drill.solveAt` and `drill.slideFor` see) and to `plan.launch` (`opts.spin`,
  `opts.tilt`), exactly as `scenes/throw.lua` does. Spun drills and tilted batons get
  cluster rows of their own. A layout with anything lying is run to rest first. An aim iteration (6%)
  throws the plan's clean baton at a lone kubb from 3, 5.27 or 8 m, as `tools/aimsweep.lua`
  does.
- **The checks** (`physcheck.tune`; each threshold measured with `--dist`, grass, seed 2,
  1500 iterations):
  - **energy.** In flight, kinetic plus potential energy may not rise by more than 1e-6 J
    in a step: only gravity and the air act, so any rise is rounding. None did.
    - After the first contact, `energyStep` is 5 mJ a step and `energyCum` is 20 mJ above
      the lowest since that contact.
    - The push apart (`pushRate`) is a velocity, so it adds energy. An overlap at the
      penetration check's 5 mm pushes a baton off a kubb at 0.22 m/s, about 4 mJ, and the
      penetration check already counts that.
    - Tuned up from 2 mJ (`test_physics`' bar) and 10 mJ. Those flagged that push as a
      separate defect. A throw's worst step rose 5.3 mJ at the 99th percentile.
  - **penetration.**
    - A pair or the ground counts when it is deeper than 5 mm for 0.02 s (`penHold`, a frame
      at 50 fps), or deeper than 20 mm at the end of any one step (`penDeep`). The time is
      kept for each pair and each body on its own, so overlaps of different pieces in
      successive steps never add up.
    - At rest, 2 mm (`penRest`). The measured worst was 0.7 mm between pieces and 0.56 mm in
      the ground.
    - Tuned from "5 mm at the end of any step". A one-step dip that the next step pushes out
      is never seen, and it was most of what that bar flagged. The 5 mm figure is the
      physics audit's bar ("Edge on edge").
  - **rest.** The following each count as a failure:
    - "no rest": still awake at `world.tune.maxTime` (12 s);
    - "creep": a piece slower than 0.1 m/s and 1 rad/s moves 2 cm within 1 s;
    - "wake cycles": a piece falls asleep and is woken more than 3 times.

    The measured worst creep on grass was 8 mm, and wake cycles reached 5.
  - **finite.** The following each count as a failure:
    - a NaN or an infinity;
    - a piece faster than 1.25 times the fastest the launch could reach, plus 3 m/s;
    - a spin over 200 rad/s;
    - a centre past x ±12 m, y -6 to 20 m, or z 12 m.

    None was found.
  - **dt and mirror.** These compare verdicts: the sorted toppled ids, and for a drilled
    kubb whether it landed in.
    - dt compares 240 Hz with 480 Hz.
    - The mirror check reflects the throw and the pitch in x = 0 and compares. It runs on
      flat ground, because the turf's texture is not symmetric.
    - A difference counts as a failure only when it is stable. The launch velocity and spin
      are scaled by 1+k for k in ±0.3%, ±0.1%, ±0.01% and 0. Each side's majority verdict
      must hold at least 6 of those 7 times, and the two majorities must differ.
    - Otherwise the difference is "marginal": a throw on a knife edge, which the table counts
      but does not call a failure. This replaced a single 1e-4 nudge, which called most
      knife edges failures.
  - **aim.** The plan's clean baton hits a lone kubb at 5.27 m every time and at 8 m 98%
    ("Aimed through the piece"). The table gives a Wilson 95% interval.
- **Pinned cases.** `tests/lua/test_physcases.lua` runs every `tests/lua/physcases/*.lua`
  through `physcheck.runCase`, and `make test` runs it. A case is plain data:
  - the pieces and the surface;
  - throws, each with a captured launch `state` or a `plan` (`px, py, tx, ty, release,
    aimZ`), and a `groundSeed`;
  - `expect`: `toppled` (exactly these), `hits` (at least this one), and `clean` (no check
    finds anything).

  `clean-baton-field-5m.lua` throws six clean batons at a lone field kubb 5.27 m out, on
  six ground seeds, and every one must topple it. It was rebuilt from a replayed report's
  geometry only.
- **Making a case:**
  - **From a fuzz failure.** Run `lua5.4 tools/physfuzz.lua --repro <seed>:<i> [--surface
    ...] --case > tests/lua/physcases/<name>.lua`. Set `expect` to what the throw should do,
    say why in the header, and drop any piece that does not matter. The launch is captured
    exactly, so the case replays bit for bit until the physics changes.
  - **From a replayed report.**
    - Take the geometry only: the stance, the target and the pieces near it, the release
      and the aim height, given as a `plan`.
    - Leave out names, report text and ids. The repository is public.
    - Use several ground seeds rather than one.
  - A case that pins a defect still to be fixed belongs in the fixing PR, not before it,
    because `make test` must pass.
- **Run times** (2026-11-16, this Mac, Lua 5.4):
  - one reference throw with the monitor takes 0.013 s (`--only
    energy,penetration,rest,finite`);
  - with the mirror, 480 Hz and their neighbourhoods, a throw takes 0.044 to 0.049 s;
  - 1000 iterations take 44 s, Sand or Snow at 3000 take 137 s, and Grass at 20000 takes
    986 s of CPU (19 minutes with three other runs beside it);
  - the pinned cases take 0.04 s.
- **First findings** (2026-11-16). The table below covers the failures, and the notes after it
  give their causes. The first defect is fixed (see its note); the table keeps the rates
  found before it. The rates come from the runs above, made before the
  penetration time was kept per pair: a 2000-iteration grass rerun with it gives penetration
  3.9% (from 4.7%), the other checks within their noise. Repro commands are `lua5.4 tools/physfuzz.lua
  --repro <seed>:<i> [--surface ...]`.

  | defect | check | grass | sand | snow | repro | real? | fix |
  |---|---|---|---|---|---|---|---|
  | a baton sinks into a kubb or the king | penetration | 4.7% | 4.1% | 4.5% | 1:66, 1:5977 (66 mm) | real | fixed 2026-11-16: `capsuleBox` clips to the feature |
  | a piece resting on a piece never sleeps | rest, no rest | 0.92% | 0.91% | 0.85% | 1:10 | real | fixed 2026-11-16: sleep on a resting support |
  | 240 Hz disagrees with 480 Hz | dt | 0.86% | 0.91% | 1.15% | 1:433 | step-size error | accepted |
  | energy rises with an overlap (the push) | energy | about 0.45% | 0.45% | 0.22% | 1:645, 1:6360 | real, same overlap | fixed with the first |
  | a resting kubb keeps being woken | rest, wake cycles | 0.26% | 0.54% | 0.20% | 1:14364 (21 times) | real | mostly fixed with the one above; a baton's creep is left |
  | a baton dips into the ground | penetration ground | 0.08% | 0.55% | under 0.1% | 1:846, 1:5548 | real | ground margin from spin, small |
  | a pair bounce adds energy | energy | 0.03% | 0.32% | under 0.1% | 1:2106 (0.38 J), sand 1:1921 (0.83 J) | real | bound the pair's bounce, small to medium |
  | the mirror disagrees | mirror | 0.04% | 0.09% | 0% | 1:19670 | solver order | accepted |
  | a baton creeps on snow | rest, creep | 0% | 0% | 0.12% | snow 1:1458 | real, minor | with wake cycles |
  | NaN, escape, impossible speed | finite | 0% | 0% | 0% | | | |

  The rates are realistic rates, from seed 1 at 20000 throws on Grass and 3000 each on Sand
  and Snow; a rate in this table is summed over a defect's clusters. The aim claims hold: a
  clean baton hit at 5.27 m 373 of 373 times (99 to 100%) and at 8 m 414 of 415 (99 to 100%;
  98% claimed).
  - **The drill grid.** No check fails beyond the energy cluster: 6 of 4536 throws, the pair
    bounce or the push.
    - Spin is not monotonic. One tap rolls a drill sideways most, about 10 to 16 cm. Two and
      three taps roll it 0 to 5 cm, on every surface. One tap also cuts the run-on: on grass
      it is 54 cm, against 91 cm at none and 76 cm at three.
    - The attitude at the touch explains it. One tap lands the kubb nose down at 34 to 38
      degrees, none lands it at 50 and two or more at 43 to 46. A moderate spin lets the air
      turn the kubb before it lands (precession), and a bigger one holds it (a gyroscope).
      That looks like physics rather than a solver defect.
    - Left and right mirror once the wrist's spiral is taken out (`--set drill.spiral=0`):
      the worst gap is 1.3 standard errors. With the spiral, one tap left is -19 rad/s and
      one right is +25, and grass shows a 3.1 standard-error gap at ±1.
    - Whether one tap should roll the most is a design question, not a defect.
    - With the turn in flight substepped (2026-11-16) the grid keeps its shape: grass
      run-on by tap -3..+3 is 72, 66, 53, 93, 52, 67, 76 cm (was 75, 70, 54, 95, 53, 71,
      75), the gap at one tap -12.7 cm (was -11.3). The precession is converged and MuJoCo
      shows it too (reference engine, finding 2).
  - **The tilt grid.** Tilt is monotonic and mirrored on every surface. It sends the baton
    0.33 to 0.51 cm a degree across the line, and hits stay at 78 to 83%. Penetration shows
    up in 8.7% of these throws, more than in the fuzz, because every one strikes a lone kubb
    squarely. It is the first defect again. With it fixed (and the flight fix in both),
    penetration shows up in 1.0% (grass 9.0 -> 1.2%, sand 6.9 -> 1.0%, snow 11.0 -> 0.9%).

  - **A baton sinks into a kubb or the king** (4.7% of all throws; up to 66 mm into the
    king, 1:5977; most last 0.02 to 0.05 s).
    - `collide.capsuleBox` makes one contact at the closest point, plus the end spheres.
      When the baton strikes, its spin jumps (to about 40 rad/s) and the closest point moves
      along it, so the baton keeps approaching at the new point.
    - Four times the solver iterations give the same depth.
    - The fuzzer's diagnosis needed one change. In 1:66 the baton lay along a kubb's
      upright edge, not a face (the rounded edge's normal was level), so a clip against
      faces alone would miss it. The overlap grew 2.5 -> 18.9 mm over five steps as the
      baton turned about its one contact.
    - Fixed 2026-11-16: the segment is clipped to the face or edge the closest point is
      on, with a `sphereBox` contact at each end of the clipped piece (Physics, "A baton
      along a face or an edge"). Not bit-identical.
    - Measured, seed 1, before -> after (realistic rates; main at 5160562, with the
      flight fix and the drill substeps):

      | check | grass (2000) | sand (1000) | snow (1000) |
      |---|---|---|---|
      | penetration | 4.74 -> 0.83% | 5.49 -> 1.35% | 4.76 -> 1.06% |
      | energy | 0.12 -> 0.25% | 0.50 -> 0.63% | 0 -> 0.12% |
      | rest | 1.00 -> 1.27% | 1.48 -> 0.98% | 0.49 -> 0.80% |
      | any | 6.31 -> 3.40% | 7.42 -> 3.84% | 6.13 -> 3.17% |

    - What is left is mostly the open case in Physics ("a baton turning about a rounded
      edge"). The energy rises are one step each, 6 to 10 mJ (5 grass throws against 2):
      a contact at a clipped end that starts inside pushes out.
    - Rest moves within its noise. Before the flight fix it rose (1.21 -> 1.70% on grass),
      from wake cycles of a kubb a baton rests on; the sleep fix below clears those.
  - **A kubb gains energy in a pair bounce** (drilled kubbs into groups, more often when
    spun: up to 0.83 J in one step, sand 1:1921).
    - The bounce pass in `world.step` (section 7) gives each contact a target of `-e * v0`
      from its own approach speed. Several contacts of one rotating pair each bounce at full
      target.
    - With `restitutionIterations` 0, sand 1:1921 rises not at all, and 1:2106 rises
      0.38 -> 0.20 J.
    - What is left is friction the four passes do not converge, with the warm start. It is
      gone at 16 iterations, with `warm` 0, or with `pairMu` 0.
    - Fix: hold the pair's bounce to its approach energy, by scaling the pair's targets or
      by bouncing at the pair's deepest contact only. Small to medium.
  - **A piece resting on a piece never sleeps** (mostly the leaning layout, and a drill on
    a group).
    - When a kubb falls flat on top of a lying one and does not touch the ground, it stays
      awake at 0.00 m/s until 12 s (1:10). The sleep test in `world.step` needs
      `groundImpulse > 0`.
    - The throw is judged right, because `world.result` applies the leaner rule. It just
      runs the full 12 s (2880 steps).
    - Fixed 2026-11-16 (Physics, "Sleep"): a piece held up by a sleeping or static piece,
      or by an awake one that is on the ground, sleeps; pieces pressing on each other
      sleep in the same step. Pinned: `kubb-on-kubb-sleeps` (1:64, 12 s -> 1.35 s) and
      `kubbs-stay-asleep` (1:1658: woke 6 times until 11.8 s -> none, 1.31 s).
    - Measured on main at 21519af (seed 1, realistic rates, before -> after):

      | check | grass (2000) | sand (1000) | snow (1000) |
      |---|---|---|---|
      | rest | 1.27 -> 0.19% | 0.98 -> 0.25% | 0.80 -> 0.18% |
      | any | 3.40 -> 2.31% | 3.84 -> 3.10% | 3.17 -> 2.56% |

      Every "no rest" is gone (grass 0.87%, sand 0.73%, snow 0.61%). Wake cycles of a
      kubb drop from 5 to 3 throws on grass and stay at 2 on sand and 1 on snow; what is
      left is a kubb a creeping baton keeps touching (below). The other checks are
      unchanged.
    - Throws that ended in one of these now end at about 1.3 s instead of 12. In matches
      the effect is small, because few throws met it: `tools/throwprof.lua --n 20` gives
      415 -> 409 steps a throw (the games diverge, so that is within their noise), and the
      slow tail stays at 17% of steps. 150 physics matches (`make realgames`): 20.2 ->
      19.9 turns a game; two or more per hit 16.0 -> 16.9%, cleared every field kubb 61.9
      -> 63.6%, king toppled 94.9 -> 93.7%: within noise. `make bench` is unchanged (lone
      0.001, air 0.005, ground 0.011, multi 0.017 ms).
  - **Energy climbs while a baton lies against a kubb** (aim at 3 m: up to 26 mJ, 1:645).
    - The baton slides into the kubb and the push apart adds the energy back, mJ by mJ.
    - It is the same overlap as the first defect, seen through the push. On main before
      the flight fix the clip took the climbs at 3 m from 0.37% to 0, and energy from
      0.62% to 0.07% of grass throws. With the flight fix there are no climbs either way.
  - **A baton dips into the ground** (up to 12.6 mm, 1:846; 0.55% on sand).
    - A pair contact changes the baton's spin within the step. Its end then reaches past
      the ground's speculative margin, which was set from the speed before the step. The
      push takes about ten steps to lift it out.
    - Fix: grow the ground margin by the spin the step can add, or run a second ground pass
      after the pair solve. Small.
  - **240 Hz against 480 Hz** (stable in about 0.9%; marginal in a further 9%, which is not
    counted). Run at 960 Hz (`--set world.dt=0.0010416666666666667`), 3 of the 4 tried
    agree with 480 Hz (1:433 among them), so the 240 Hz step is the one that is off.
    This is ordinary step-size error on grazing contacts. Halving the step doubles the cost
    (rejected 2026-11-13 for the other direction), so it is accepted.
  - **The mirror** (stable 0.1% on sand, close to 0 on grass and snow). The solver visits
    contacts in the same order in both worlds, and on sand's high friction and dig that
    order shows. It is fair for a sequential-impulse solver.
  - **A baton creeps on snow and keeps a kubb waking** (0.1%, snow 1:1458; on grass a
    leaning kubb woke 21 times, 1:14364). The baton
    propped against the row slides 2.8 cm over 5 s. Each touch wakes the kubb, which
    sleeps again five times.
