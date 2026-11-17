# Headless games

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

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
(`plan.arcFor`), solves the plan at a level (`plan.solve` with `autothrow.cpuLevel`,
`autothrow.tune.level`, club; "The computer's levels" under "Real games"),
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
