# Real games

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

## Real games

Jamie (2026-11-15): "in a tournament I would have hit all five down with one baton". How far
is the game from real play? `node tools/realgames.mjs <real dir> <game dir> [--json]` reads
two folders of game files with the vendored `kubb.js` (`analyze`) and counts both the same
way, so every figure has the same denominator on both sides: the 150 games people scored
(`games/` of a pk-kubb-score checkout, read only) and matches the computer played with real
physics (`tools/physmatch.lua --out`). `make realgames` does both. A measuring tool only: it
changes nothing in the game, and what to tune from it is Jamie's call. A score sheet records
what each baton took, not where anything stood or how it was thrown, so it says where the
rates differ, never why. The real games are pro play; `tools/physmatch.lua --level`
(`make realgames REAL_LEVEL=club`) plays the computer at another level against itself.

- **What the real games are: pro** (Jamie, 2026-11-17): "there is no professional kubb.
  So that is essentially the best kubb there is"; some of the recorded players ranked high
  at the world championship and one team won it. All tournament games, often the final
  rounds of a bracket. They are the mark for the pro level; club and beginner sit below
  them on every figure. (2026-11-16 read them as club to high club; superseded.) The
  figures below before 2026-11-17 compare them with the computer at club.
- **The computer's levels** (2026-11-17). A level's gauge forgiveness (`powerHalf`,
  `releaseHalf`, `inGain`, `shakeGain`, `overGain`) helps a player's crank; the computer's
  swing made the same mistakes at every level, so the wider targets forgave it more and
  club and beginner out-threw pro (150 matches seed 2, beginner / club / pro: the king
  97 / 97 / 83%, field kubbs missed 31 / 18 / 25%). Now `autothrow.cpuLevel(name)` throws
  on pro's gauge at every level with that level's nerves and `tumbleSd`, and the swing's
  mistakes are multiplied by `autothrow.tune.swingScale` (beginner 1.6, club 1.3, pro 1).
  Pro's throws are unchanged. `make realgames` per level (150 matches seed 2; real / beginner
  / club / pro): turns a game 8.9 / 25.2 / 20.5 / 17.8; a baton at field kubbs missed 24.7
  / 53.4 / 39.4 / 24.8%, took two 16.0 / 2.3 / 3.7 / 5.7%, three or more 10.0 / 0.1 / 0.1
  / 0.3%; a base kubb from 8 m 32.7 / 6.6 / 16.9 / 33.5%, from an advantage line 51.7 /
  31.1 / 41.6 / 57.8%; the king 83.8 / 58.3 / 73.5 / 82.8%; illegal 0 / 7.7 / 1.6 / 1.1%;
  resigned at the turn limit 0 / 30 / 14 / 19. Swing scale 2 at beginner (and 1.4 at
  club) was tried: 27% helicopters at beginner. The Playdate opponent is club
  (`autothrow.tune.level`), so it is weaker than before (it hit the king 97% and missed
  field kubbs 18%). Pro's single throws match the tournament games; what stays off at
  pro is the multi-kubb batons (two 5.7% against 16%, three or more 0.3% against 10%),
  so pro games run twice as long.
- **How it counts.** A baton is "at field kubbs" when a field kubb stood when it was thrown
  (the turn's `startField` less what earlier batons took), "at base kubbs" when none did
  and a base kubb was left; king shots are `K` and `=`; `X` is not a throw. Clearing the
  field is kubb.js's `btc`. Not throws either: the batons kubb.js marks `void` (written
  after the game ended) and a resign or a win token. `make test` runs it over the fixtures against themselves (that
  it runs, nothing more).
- **First figures** (2026-11-16; 150 real games, 150 physics matches seed 2 after the foot
  catch; real -> the game):
  - Turns a game 8.9 (median 8) -> 21.9 (19); every real game ended on the king, 80% of
    the game's (30 resigned at the 40-turn limit). The team that threw first won 55% -> 53%.
  - **A baton at field kubbs**: missed 25% -> 37%; took one 49% -> 56%; took two 16% -> 7%;
    three or more 10% -> 0.4%; of those that hit, two or more 34% -> 11%; field kubbs a
    baton 1.16 -> 0.71; the most with one baton 7 -> 4.
  - **Clearing the field**: 83% of turns -> 46%, in 3.4 batons -> 4.2. By kubbs to clear:
    three 92% -> 86%, four 88% -> 62%, five 85% -> 40%, six 79% -> 22%, eight 68% -> 4%.
    Up to three kubbs the game is near real play; past that it falls away, which is the
    doubles and triples missing. A turn thrown from an advantage line 14% -> 50%.
  - **A baton at base kubbs**: 35% -> 45% (from the baseline 33% -> 41%; from an advantage
    line 52% -> 54%). The computer is better than real players at 8 m.
  - **The king**: 84% of 179 shots -> 46% of 259.
  - **Kubbs thrown in**: rethrown 14% -> 2.5%, punishment kubbs 1.3% -> 0.1%. Real players
    throw at a tighter group and miss it more; the computer's basket is safe.
  - **A steadier computer does not close it** (`tools/physmatch.lua --scatter`, `make
    realgames REAL_SCATTER=0.6`: every mistake of the computer's swing times that; 150
    matches each, seed 2; real / scatter 1 / 0.6 / 0.3). Base kubbs from 8 m 33% / 41% /
    73% / 98%; the king 84% / 46% / 71% / 98%; a baton at field kubbs missed 25% / 37% /
    17% / 5%, took two 16% / 7% / 11% / 17%, three or more 10% / 0.4% / 0.6% / 1.8%;
    cleared six field kubbs 79% / 22% / 54% / 87%, eight 68% / 4% / 17% / 39%; turns a
    game 8.9 / 21.9 / 20.5 / 14.9; rethrown 14% / 2.5% / 1.9% / 0.8%. At 0.3 the computer
    hits a base kubb from 8 m three times as often as tournament players and still takes
    three with a baton a fifth as often: the gap is not accuracy.
  - What it does not show: the real players' groups. Jamie (2026-11-16): "Multiple fields
    kubbs is all about drilling tight clusters." The sheets agree as far as they can: real
    players rethrow 14% of their kubbs (they drill at a tight group and pay for it), the
    computer 2.5% (its drills rest 0.29 m from the basket on average, so its kubbs stand a
    kubb or two apart). So the first place to look is how tight the game's groups are, the
    computer's and a player's, before the baton or the physics.
- **Latest figures**: "Tuned toward the real games", the last bullet ("Into the group",
  2026-11-16), with seeds 2, 3 and 4.

- **Single throws against real video** (2026-11-16): `docs/reference/REALCLIPS.md` and
  `realclips.json`, 220 events measured frame by frame from public video beside the
  engine's figures, with intervals and a ranked list of where the engine sits outside.
  Pass 2 (198 events, a tournament cage camera calibrated by a homography on the painted
  lines, engine at `3703fe4`): a real drill on grass moves a median 0.22 m from its first
  touch to rest (61% under 0.3 m) against the engine's 0.88 m (4%); touching groups do not
  all fall (every kubb 2 hits in 9), which withdraws pass 1's 16 of 16.

### How tight the groups are

`lua5.4 tools/clusters.lua [--n 60] [--seed 2] [--drill 1] [--baton 1] [--raise
apart|together]` (Jamie approved the measuring, 2026-11-16; no game changes) plays physics
matches with the computer's mistakes scaled separately for its kubbs and its batons, and at
the first baton of every turn with two or more field kubbs standing measures each one's gap
to its nearest neighbour (edge to edge), the group's spread and the largest group chained
by gaps of 15 cm or less; then what the turn's batons at field kubbs took. 60 matches each,
seed 2:

| kubbs x, batons x, raised | gap (mean) | within 7 cm | within 15 cm | largest group | took two | three + | turns |
|---|---|---|---|---|---|---|---|
| real tournament games | | | | | 16% | 10% | 8.9 |
| 1, 1, apart (the game) | 39 cm | 3% | 18% | 1.4 | 6.7% | 0.4% | 21.0 |
| 0.5, 1, apart | 41 | 2% | 14% | 1.3 | 5.4% | 0.3% | 18.6 |
| 0.25, 1, apart | 44 | 5% | 20% | 1.5 | 6.2% | 0.7% | 19.6 |
| 0, 1, apart | 26 | 19% | 60% | 3.3 | 8.4% | 5.3% | 15.7 |
| 1, 1, together | 23 | 36% | 60% | 2.5 | 11.9% | 1.4% | 18.9 |
| 0.25, 1, together | 29 | 30% | 53% | 2.5 | 10.7% | 2.0% | 18.7 |
| 0.25, 0.6, together | 24 | 37% | 61% | 3.1 | 18.0% | 4.2% | 13.1 |
| 0, 0.6, together | 18 | 9% | 81% | 4.3 | 14.3% | 18.3% | 5.9 |

- **The physics can do it.** With every kubb drilled clean onto one spot, raised toward
  each other and a steadier baton, a baton takes two or more 33% of the time (real 26%)
  and a game takes 5.9 turns (real 8.9). The game's doubles and triples are missing because
  its groups are loose, as Jamie said, not because a baton cannot take three.
- **The game's groups are loose**: a field kubb's nearest neighbour is 39 cm away on
  average and only 3% stand within 7 cm (a kubb's width); the largest group a baton could
  chain through is 1.4 kubbs of 5.
- **Which end is raised matters as much as the drill.** The engine's default policy raises
  each kubb on the end farthest from the others (`apart`); `together` alone halves the
  gap (39 -> 23 cm) and doubles the doubles (6.7% -> 11.9%). Which a real defender picks
  is a rules and play question for Jamie.
- **A steadier arm does not tighten the group until it is perfect** (x0.5 and x0.25 are
  no tighter than x1; x0 is). Not explained yet: at x0 every drill is the same throw and
  meets the same ground (the ground's seed is the throw's), so the likely floor is the
  ground's patches and kubbs knocking the ones already there, not the swing. That is the
  next thing to measure before anything is tuned.
- Not measured: a player's drills (the tool throws the computer's).
- **Lying, before raising** (2026-11-16): the tool also measures the same gaps when the
  inkast is judged, before the defender raises anything. On the game of the day before
  (seed 2, 60 matches) the lying kubbs were 11.7 cm apart and 21% touching, standing 24.6
  cm; since the computer drills into the group ("Tuned toward the real games", "Into the
  group") 6.5 cm and 35% lying, 17.6 cm standing. `--set world.name=value` sets a
  `world.tune` number.

### Tuned toward the real games

Jamie (2026-11-16): "You have standing approval to. Pursue this work, update both web and
play date versions, deploy as needed." The first pass changes only how the computer throws
(`core/autothrow`); the physics, the rules and a player's own throw are as they were.

- **Why its groups were loose.** One drill is accurate (it rests 26 cm from its mark, 9 cm
  with half the mistakes, 5 cm with a quarter). But every drill went to the same mark, came
  down on the kubb already lying there and skipped about a metre. That, not the swing, is
  why a steadier arm did not tighten the group.
- **The spot** (`autothrow.spot(s, side)`, `tune.spot*`). A toss goes to the clear spot
  nearest the basket on a small grid: not within a kubb of a field kubb in the far half, and
  with none in the lane it comes down in (a lying kubb 12 cm short of the spot, a standing
  one 60 cm). Steps along the throw cost a tenth of steps across (`spotCostY`), so the
  kubbs go down in one line along the throw: `tools/compound.lua` has two kubbs one
  behind the other both falling 60 to 72% of the time at gaps to 15 cm, side by side about
  10%. No spot nearer the centre line than `spotMinY` or the sideline than `spotMaxX`.
- **The lane** (`tune.laneHalf`, `laneDeep`). A baton at field kubbs aims at the front kubb
  of the lane with the most kubbs standing in it (within 7 cm across and 60 cm behind),
  across the middle of the lane; the nearest front on a tie, so a lone kubb is thrown at
  as before.
- **Mistakes by range and for a drill.** A baton's mistakes are multiplied by its range
  over `rangeRef` 7 m (never under `rangeMin` 0.45 or over `rangeMax` 1.2): a 3 m throw at
  a field kubb is not as wild as an 8 m one. A drilled kubb's are multiplied by
  `drillScale` 0.2: tournament players drill to a hand's width. (Replaced by the shared
  nerves on 2026-11-16, below: `rangeRef`, `rangeMin` and `rangeMax` are gone;
  `drillScale` stays.)
- **Measured** (150 real games; 150 physics matches seed 2; real / before / after): turns a
  game 8.9 / 21.9 / 14.6; a baton at field kubbs missed 25% / 37% / 21%, took one 49% /
  56% / 57%, took two 16% / 7% / 18%, three or more 10% / 0.4% / 3.4%; cleared the field
  83% / 46% / 70% (five kubbs 85% / 40% / 82%, eight 68% / 4% / 30%); a base kubb from 8 m
  33% / 41% / 42%; the king 84% / 46% / 77%; turns from an advantage line 14% / 50% / 27%;
  kubbs rethrown 14% / 2.5% / 0.4%. `tools/clusters.lua` (60 matches): a field kubb's
  nearest neighbour 39 -> 20 cm, within 15 cm 18% -> 49%, largest group 1.4 -> 2.4 kubbs.
- **Still off.** Three or more with one baton (10% real, 3.4%), so fields of seven and up
  are cleared half as often as real players clear them; games are still half as long
  again; the computer never pays for its group with a rethrow (0.4% against 14%: its
  basket is a safe 25 cm past the centre line and its drill is steadier than its spot is
  bold); it hits a base kubb from 8 m more often than tournament players. The engine
  raises kubbs apart, as real defenders do (Jamie, 2026-11-16). `tools/clusters.lua --set name=value` sets any `autothrow.tune` number for
  a sweep.
- The desktop dumps are not bit-identical with the ones before: the Playdate's throws in
  a match changed on purpose.
- **Since the drill runs on (2026-11-16, "Drilling").** The same 150 physics matches
  (seed 2; real / before / after): turns a game 8.9 / 14.6 / 22.7; a baton at field kubbs
  missed 25% / 21% / 24%, took one 49% / 57% / 68%, took two 16% / 18% / 7.5%, three or
  more 10% / 3.4% / 0.9%; cleared the field 83% / 70% / 53% (five kubbs 85% / 82% / 60%,
  eight 68% / 30% / 15%); a base kubb from 8 m 33% / 42% / 41%; the king 84% / 77% / 80%;
  turns from an advantage line 14% / 27% / 44%; kubbs rethrown 14% / 0.4% / 0.5%,
  punishment kubbs 1.3% / 0% / 0%. `tools/clusters.lua` (60 matches; before / after): a
  field kubb's nearest neighbour 20 -> 25 cm, touching 2.5% -> 0.3%, within 15 cm 49% ->
  20%, spread 45 -> 42 cm, largest group 2.4 -> 1.9 kubbs, turns 14.1 -> 22.6. The
  groups are a line or a cluster in the right place, never five kubbs in a row, but
  looser than real tournament groups: real drillers' kubbs end touching (they roll into
  each other), the game's stop 10 to 30 cm short of the one they run into. The swing's
  mistakes hardly matter now (`--drill` 1 / 2 / 3: took two 7.8 / 7.5 / 7.2%, rethrown
  0.5 / 1.0 / 1.1%); the run on is the scatter. Preferring a spot with a lying kubb just
  past it in its lane (a backstop bonus) was tried and not kept: no change in the takes
  (8.0% two, 0.8% three or more). Rethrows stay rare because a kubb is in when either end
  can be raised in bounds and the basket is 0.75 m past the centre line.
- **Into the group (2026-11-16).** Why the run-on groups stayed loose
  (`tools/drillscatter.lua --only 4`, drills thrown while a kubb lay in the far half, 40
  matches): the grid's spots are fixed to the basket, not to the kubbs that are down, so
  only 39% of later drills reached a lying kubb (70% of the rest went past beside it), and
  31% of those that did came down on top of it. The wood is fine: a drill that runs into
  a kubb at under 1 m/s ends touching it 75 to 89% of the time; one that arrives over
  2 m/s bounces off (20%), as it should. So `autothrow.spot` now aims a later kubb of the
  turn into the group first (`intoSpot`, `tune.into` 1, `intoShort` 0.03): just short of
  the near face of a lying field kubb near the basket (`intoShort` short of it; the face
  is the kubb's half length or half width along the throw by how it lies), where the
  drill's mean rest ends it against that kubb. In a line (2 or 3 kubbs) the front kubb, so
  the line grows toward the thrower; in a cluster (4 or more) the kubb nearest the group's
  middle. The same lane and clear rules as the grid's spots (no other kubb within the
  clear ellipse, none lying 12 cm or standing 60 cm short in the lane); with none clear,
  the grid as before. The swing, the drill and the physics are unchanged; the scatter is
  still the run on. Part 4 after: reached a lying kubb 39 -> 51%, landed on it first 31
  -> 6% of those, ended touching 37 -> 47%, the drill's gap at rest 14 -> 6 cm.
  `tools/clusters.lua` (60 matches, seed 2; before / after), lying as the inkast ends:
  nearest neighbour 11.7 -> 6.5 cm, touching 21 -> 35%, largest group 3.3 of 4.8 -> 4.2 of
  5.0 kubbs; standing at the first baton (after `apart` raising): 24.6 -> 17.6 cm, touching
  0.7 -> 2.8%, within 15 cm 30 -> 52%, spread 42 -> 34 cm, largest group 1.9 -> 2.7. 150
  physics matches each, seed 2 (seeds 3 and 4 in brackets), real / before / after:

  | | real | before | after |
  |---|---|---|---|
  | turns a game | 8.9 | 22.7 (23.3, 23.5) | 21.3 (22.3, 20.8) |
  | a baton at field kubbs: missed | 24.7% | 23.8% | 22.1% |
  | took one | 49.4% | 67.8% | 66.0% |
  | took two | 16.0% | 7.5% (7.3, 7.3) | 10.5% (10.3, 10.0) |
  | three or more | 10.0% | 0.9% (0.8, 0.6) | 1.4% (1.4, 1.4) |
  | cleared the field | 83.4% | 52.8% (50.9, 49.5) | 55.3% (53.2, 54.1) |
  | five kubbs | 84.5% | 59.5% (63.6, 58.0) | 68.9% (68.1, 69.9) |
  | eight kubbs | 67.6% | 14.8% (12.9, 13.6) | 22.3% (20.8, 17.6) |
  | a base kubb from 8 m | 32.7% | 40.8% | 41.9% |
  | the king | 83.8% | 79.6% (71.0, 75.7) | 74.3% (74.7, 74.2) |
  | turns from an advantage line | 14.4% | 43.6% | 41.0% |
  | kubbs rethrown | 14.1% | 0.5% | 0.6% (0.7, 0.6) |
  | punishment kubbs | 1.3% | 0% | 0% |

  The groups now form the way Jamie described (later kubbs run into the ones down and end
  against them), but the takes move only part of the way: the defender's `apart` raising
  undoes most of a touching group (lying 6.5 cm apart, standing 17.6). With `--raise
  together` the same aim gives a standing gap of 10.4 cm, two 16.2%, three or more 4.1%,
  15.2 turns. Tried and not kept: `intoShort` -0.1 to 0.13 (no better than 0.03) and -0.2
  (worse: the drill arrives fast and knocks the group apart), and a lower kubb-on-kubb restitution
  (`world.tune.boxE` 0.05 and 0 in a sweep: more drills end touching, the takes no better;
  the physics is unchanged). Rethrows stay rare: moving the basket nearer the centre line
  (`basketY` 4.5 / 4.35 / 4.2) leaves them at 0.8 / 1.1 / 1.2%; only with `spotMinY` 3.9
  and the basket at x 2.25 as well do they reach 8.5% (two 14.1%, three or more 3.4%, 16.9
  turns, 60 matches). That is a play question for Jamie and not in this change.

- **The drill as a plain body, with the bite (2026-11-16, "Drilling").** `make realgames`,
  150 physics matches seed 2 (real / before / after): turns a game 8.9 / 22.4 / 21.7; a
  baton at field kubbs missed 24.7 / 22.3 / 25.2%, took two 16.0 / 10.7 / 4.9%, three or
  more 10.0 / 1.5 / 0.2%; cleared the field 83 / 55 / 49%; a base kubb from 8 m 32.7 /
  33.6 / 33.4%; the king 84 / 77 / 80%; kubbs rethrown 14.1 / 0.6 / 8.1%, punishment
  kubbs 1.3 / 0 / 1.5%. The inkast now pays for its groups the way real players do, but
  the groups are looser (a drill runs on about a metre), so doubles and triples fell. The
  next step is the computer's aim with the new run on (into the group from farther short),
  not the physics.

- **After the physics audit (2026-11-16).** The nine audit items (the foot catch, the
  baton trip, edge contacts with one wood mu, the standing pose, the baton's tumble from
  the release, the landing bump as a tilted normal, the pair bounce, still-air drag, the
  load-scaled grip) and the aim allowance measured again on them ("Drilling", "The aim
  allowance"). `make realgames`, 150 physics matches seed 2 (real / before the audit /
  after the audit with the old allowance / now):

  | | real | before audit | old allowance | now |
  |---|---|---|---|---|
  | turns a game | 8.9 | 21.7 | 18.6 | 18.3 (median 15.5) |
  | a baton at field kubbs: missed | 24.7% | 25.2% | 20.4% | 20.5% |
  | took one | 49.4% | | 70.0% | 70.1% |
  | took two | 16.0% | 4.9% | 8.8% | 8.7% |
  | three or more | 10.0% | 0.2% | 0.7% | 0.7% |
  | cleared the field | 83.4% | 49% | 57.1% | 56.5% |
  | five kubbs | 84.5% | | 69.3% | 68.9% |
  | eight kubbs | 67.6% | | 10.7% | 7.7% |
  | a base kubb from 8 m | 32.7% | 33.4% | 32.1% | 33.0% |
  | the king | 83.8% | 80% | 81.4% | 80.5% |
  | turns from an advantage line | 14.4% | | 38.6% | 39.4% |
  | kubbs rethrown | 14.1% | 8.1% | 7.9% | 5.6% |
  | punishment kubbs | 1.3% | 1.5% | 1.6% | 1.1% |

  The re-measured allowance moves only the rethrows (a drill aimed short no longer ends
  short of the line as often). `tools/clusters.lua` (60 matches, seed 2; old allowance ->
  now): standing at the first baton, nearest neighbour 37.3 -> 35.5 cm, within 15 cm 22.5
  -> 23.6%, spread 64 -> 60 cm, largest group 1.6 -> 1.7; lying as the inkast ends 15.9 ->
  15.6 cm, touching 13.6 -> 14.6%, largest group 2.7 -> 2.8; turns 18.4 -> 17.8.
  `tools/physmatch.lua --n 40 --seed 2`: 17.8 turns, field 80%, base 40%, king 38 of 49,
  169 of 3108 drilled kubbs rethrown. Still off, biggest first: three or more with one
  baton (0.7% against 10%) and two (8.7 against 16), so fields of six and up are cleared a
  fraction as often (eight: 7.7% against 68%) and games run twice as long. The groups
  are the cause: drilled kubbs lie 15.6 cm apart and stand 35.5 cm apart once raised
  apart. Sweeps (clusters, 60 matches; nothing kept): `--raise together` 15.7 turns, two
  13.2%, three or more 1.8%, standing gap 24.2 cm; with `--baton 0.5` as well 14.5 turns,
  two 14.9%, three 2.3%; the drill's release scatter halved (`pitchSdDps` 15, `yawSdDps`
  7.5, `noseSdDeg` 2) standing gap 30.7 cm, rethrown 1.7%, two 10.2%; `drillScale` 0.1,
  `drillNerves` 0.5 or 0.25, `scatterJerk` 0 or `world.pairE` 0.15 change nothing that
  matters (two 7.1 to 9.3%, three or more 0.3 to 1.0%).

### Nerves

Added 2026-11-16. Before it nothing but the swing's shake put a throw left or right. So a
clean swing was a perfect throw at any range, for the player and the computer alike.
The computer's misses came from a synthetic swing whose mistakes autothrow scaled by
range. Now one model in `core/throwplan` serves both throwers.

- **The model.** `plan.launch(sol, r, opts, out)` with `opts.nerves` makes two draws, each
  a unit normal:
  - `sideDeg = pull x lateralDeg x shake cost + z1 x sdSide`, an angle in degrees added to
    the swivel. Because it is an angle, the miss in metres grows with the range.
  - `lenShare = z2 x sdLen`, never under `lenMin` -0.5. The speed is multiplied by
    `sqrt(1 + lenShare)`, so the carry is about `lenShare` longer or shorter.
  - `sdSide, sdLen = plan.nervesSd(level, back, shake, over, kubb)`. That is the level's
    `nervesDeg` and `nervesLen` times effort, times roughness, times overpower:
    - effort is `1 + effortGain x (plan.reach(back) / effortRefM - 1)`, never under
      `effortMin`. The tunes are 2.5, 8 m and 0.15. So 6 m gives 0.375 and 10 m gives
      1.625, and anything at 5.2 m or under is the floor.
    - roughness is `1 + roughGain x shake`, with `roughGain` 1.
    - overpower is the shake's own multiplier `m`.
    - A drilled kubb also takes `drillNerves` 1.
- **Levels** (`plan.levels`, first guesses):

  | Level | nervesDeg | nervesLen |
  |---|---|---|
  | beginner | 1.6 | 6% |
  | club | 0.8 | 3% |
  | pro | 0.5 | 2% |

  Each is 1 sd for a baton reaching 8 m.
- **Where the draws come from.** `opts.nerves` can be:
  - nil or false: none. This is the default, so every caller and test that does not ask
    gets the plan's clean throw.
  - a stream (`plan.rng`): two draws from it. The computer's `autothrow.choose` passes
    its own `r`, the match's seeded stream, at scale above 0.
  - true: a stream seeded from the swing and the plan (`plan.swingSeed`, a hash of the
    back, release, flick, shake, target and stance). The player's throws use this.

  A recorded match replays from its recorded launch either way.
- **Verdicts.** `out.sideM` and `out.lenM` give the miss at the planned distance, in
  metres. `out.sideV` is -1, 0 or 1: PULLED LEFT, STRAIGHT (within `straightM` 6 cm) or
  PULLED RIGHT. `+` is right, as for the swivel. `out.lenV` is -1, 0 or 1 (within
  `longM` 30 cm). It goes in the trace but is not shown, because the power cell already
  says SHORT/LONG for the swing.
  - `plan.verdictText` returns the side as a fourth value, and `plan.sideText(v)` gives it
    alone.
  - `hud.verdicts(powerV, releaseV, steady, sideV)` draws a fourth cell. The plate is
    sized to the longest word in each cell plus `pad` 4, about 243 px from x 73, which
    stops short of the clock. With no `sideV` it draws the old three-cell plate.
- **The scene.**
  - `throw.nerves` (true) or `s.nerves` switches the player's nerves.
  - The self-test runner sets `throw.nerves` from the scenario's `nerves` field (off
    unless it asks), so a scripted clean swing stays the plan's clean throw.
    The device autobench's hit throw sets `s.nerves = false` for the same
    reason, so its impact and rest timings stay comparable.
  - `s.vSide` holds the verdict.
  - `s.last` and the trace line carry `sideDeg`, `lenShare`, `sideV` and `lenV`.
  - Self-test `nerves` shows the clean planned swing of `clock-throw`, which now goes
    1.42 degrees right and 0.5% long: ON ON STEADY PULLED RIGHT, and a miss (since the
    clean throw is aimed through the kubb at half its height, "Aimed through the piece",
    the draws fall differently: 0.46 degrees right and 3% short before, which clipped b3).
- **The aim fan** was tried and dropped. `plan.spread(sol, range, level)` and
  `plan.fan(sol, px, py, tx, ty, level, out)` give the spread and its two edges at the
  target. Drawn as two dotted ground lines from the thrower's feet, it read as a narrow
  lane: at club level 1 sd at 8 m is about 10 cm, inside the target circle. The geometry
  stays in core for the web or a later try.
- **What it replaced in `core/autothrow`.** The range scaling is gone (`rangeRef` 7,
  `rangeMin` 0.45, `rangeMax` 1.2), and so are the old copy of the stream (now
  `autothrow.rng = plan.rng`, the same numbers) and the shake as the only sideways error.
  Changed or kept:
  - The synthetic swing is half as rough: `backSd` 5 -> 2.5, `releaseSd` 9 -> 4.5,
    `shakeMax` 0.44 -> 0.22. The nerves now do most of the missing.
  - `drillScale` 0.2 stays: the computer drills with a steadier hand than it throws.
  - `laneHalf` and `laneDeep` are unchanged. There is no `laneAim` or `laneLong` to try
    again.
- **Measured.** `make realgames`: 150 physics matches, seed 2, against the 150 real
  games. Before is main at the start of this change.

  | | real | before | after |
  |---|---|---|---|
  | turns a game | 8.9 | 21.3 | 22.4 |
  | a baton at field kubbs: missed | 24.7% | 22.1% | 22.3% |
  | took one | 49.4% | 66.0% | 65.5% |
  | took two | 16.0% | 10.5% | 10.7% |
  | three or more | 10.0% | 1.4% | 1.5% |
  | cleared the field | 83.4% | 55.3% | 54.8% |
  | one field kubb: batons to clear | 1.7 | 1.2 | 1.1 |
  | five kubbs cleared | 84.5% | 68.9% | 62.8% |
  | eight kubbs cleared | 67.6% | 22.3% | 26.0% |
  | a base kubb from 8 m | 32.7% | 41.9% | 33.6% |
  | a base kubb from an advantage line | 51.7% | 80.0% | 84.6% (227 batons) |
  | the king | 83.8% | 74.3% | 77.4% |
  | turns from an advantage line | 14.4% | 41.0% | 41.4% |
  | illegal throws | 0% | 2.4% | 0.7% |
  | kubbs rethrown | 14.1% | 0.6% | 0.6% |

  Probe at club (300 throws each, own set-ups; before / after): a base kubb from 8 m
  41% / 32%, from the advantage line 73% / 73%, a lone field kubb 4 to 7 m out 82% /
  82%, the king 79% / 82%.
- **What the range model cannot do.** The 8 m base rate is on target, and the field game
  and the king are no worse. The base rate from the advantage line stays far above the
  real 52%. Those throws are 5 to 7 m, the same range as most field throws, so nerves
  that hit 52% there miss field kubbs far more than real players do. Two tries were not
  kept:
  - Gentler effort (`effortGain` 1 to 1.2, floor 0.35 to 0.4, club 0.7 to 0.75 degrees
    and 4%) brought the advantage line to 62 to 66%. But field misses rose to 30%, the
    field was cleared 49 to 51% of the time and the king fell to 62 to 69%.
  - A lane aim with a longer lane (`laneAim`, `laneLong`) does not exist in this code to
    rerun.
  Real players likely throw differently at a base kubb from the line, which is a play
  question. Seeds 3 and 4 were not run.

### The baton's tumble

Changed 2026-11-16 (physics audit item 5). Before it the end-over-end rate was a line in
the launch speed alone (`tumbleV1`..`tumbleAt2`: 4.5 rad/s at 4 m/s to 7 at 9.2, clamped 3
to 9). Neither the swing nor the nerves moved it, so a given distance and arc always
landed the baton at the same angle. Real batons vary most in how much they turn, and that
decides an end-first landing or a flat one.

- **Where the numbers come from.** No published measurement of kubb baton spin was found
  (a web search on 2026-11-16 found only the rules: the baton is held by one end, thrown
  underarm, and may turn only end over end). So the range is reasoned from the throw:
  - Held by its end and swung underarm, the baton turns with the hand. With a locked
    wrist that is the arm's rate, the baton centre's speed over `armR` 0.9 m (shoulder to
    the baton's centre: arm 0.65, hand 0.1, half the baton 0.15). That is 4.3 rad/s for a
    2 m lob (3.8 m/s) and 9.8 for an 8 m throw (8.8 m/s).
  - Throwers check or add to it with the wrist, `wristShare` 0.5 of it either way, and
    aim the turn: kubb players speak of about one turn over the flight on a good throw.
    `tumbleTurns` is 1.1, a little over one, which is also where the old table sat at
    8 m (1.09 to 1.16 turns), so the landing measures below held. At 1.0 the probe's
    sweep toppled 79% against 88% and the end-first landings changed character (2 of
    200 lost their spin against 24 of 133); at 1.2 no throw in the sweep landed end first.
  - So 8 m at 3 o'clock is 6.5 rad/s over 1.07 s; 8 m at 4 o'clock 7.0; 9.4 m at half
    past 1 5.2 (the wrist's floor: 1.22 turns); a 2 m lob 6.4 (the wrist's ceiling: 0.63
    turns). The whole range a game throws is about 4 to 10 rad/s.
- **The model.** `plan.tumbleFor(speed, loftDeg)` is `2 pi tumbleTurns / T` for the clean
  flight's time `T` (`plan.flightTime`, flight.predict), held to `arm (1 - wristShare)` ..
  `arm (1 + wristShare)`. `plan.solve` puts it on a baton's solution as `sol.tumble` and
  `sol.flightT`. In `plan.launch` the release sets what the throw gets:
  - the flick's share of it (`flickFrac`: a slow flick is a slow hand and wrist);
  - with nerves, a third seeded draw after the side and the length: `zt x sdTurns` turns
    over the planned flight, `sdTurns` the level's `tumbleSd` times `1 + roughGain x shake`
    times the overpower multiplier (no effort term: the wrist's timing, not the power).
    A drilled kubb makes no third draw, so a drill takes the same two draws as before.
  - never under `tumbleMin` 0 (no backspin). `out.sdTurns` is the sd it had.
  - An early or late release changes the loft and so the flight, not the rate: the turns
    change with it.
- **Levels** (`tumbleSd`, turns, 1 sd; first guesses): beginner 0.2, club 0.1, pro 0.06.
  Club 0.15 was tried first: the computer's king rate fell from 82% to 71%
  (`tools/batonprobe.lua --rates 400`), at 0.08 79%, at 0 82%.
- **The aim** does not depend on the tumble: `plan.solve` aims the baton's centre
  (flight.predict is drag free), so the computer's aim is unchanged. The flight time it
  turns over is the time to the aim height (`sol.flightT`; "Aimed through the piece").
- **Measured** (club; before -> after):
  - `tools/batonprobe.lua --rates 400` (the sweep has no nerves, so it tests the plan's
    rate alone): touched and toppled 89% -> 90% (696 -> 790 touched), fast and left
    standing 30 -> 25, end-first landings that lost three quarters of their spin 17% ->
    22%; the computer at base kubbs 32% -> 29%, a field kubb 84% -> 84%, the king 82% ->
    78%.
  - `tools/physmatch.lua --n 40 --seed 2`: 19.0 -> 17.3 turns a game; base 40% -> 39%,
    field 76% -> 77%, king 35/43 -> 38/50.
  - `make realgames` (150 matches seed 2; real / before / after): turns a game 8.9 / 21.7
    / 17.7; the team that threw first won 55% / 38% / 46%; ended on the king 100% / 82% /
    95%; a baton at field kubbs missed 24.7 / 25.2 / 22.6%, took two 16.0 / 4.9 / 5.7%,
    three or more 10.0 / 0.2 / 0.3%; cleared the field 83 / 49 / 57%; a base kubb from 8 m
    32.7 / 33.4 / 30.7%, from an advantage line 51.7 / 62.2 / 67.6%; the king 83.8 / 79.9 /
    76.3%; turns from an advantage line 14 / 46 / 39%.
  - `make bench`: no step cost (the tumble is worked out once a throw, outside the step).
- **Tools.** `tools/batonprobe.lua --set plan.tumbleTurns=1.1` tries a `plan.tune` value.
  `tools/compound.lua` and `tools/tiltgroups.lua` take the plan's rate at each loft.

### Aimed through the piece

Tyler's play test (2026-11-16): "all of them went clean over the field kubb". A clean
baton was aimed at the target's foot: its centre came down at z = 0 on the kubb's centre,
so it met the kubb low, often landed short of it on an end, bounced and went over.

- **The aim** (Jamie's call): with the circle on a standing kubb or the king (within the
  scene's `snapRadius`, or the computer's target), the clean throw aims the baton's centre
  through the piece at `plan.aimZFor(kind)`, `aimHeightShare` (0.5) of its height: a kubb
  0.075 m, the king 0.15 m. `plan.solve` takes `q.aimZ` and carries to
  `flight.tune.handHeight - aimZ` (no extra carries a frame); `sol.aimZ`, `sol.flightT`
  (to that height) and `sol.tumble` follow it. At the same loft a higher aim needs a little
  more speed and less time. A circle on no piece, and every drill (`drill.solveAt`), keeps
  z = 0. `autothrow` sets the same aim for the computer. `tests/lua/test_aimheight.lua`;
  `lua5.4 tools/aimsweep.lua [--ranges] [--release] [--seeds] [--set
  plan.aimHeightShare=0]` measures it (0 is the old aim at the foot).
- **Measured** (before -> after):
  - `tools/aimsweep.lua`, a lone kubb on grass, release 60 (loft 22), 8 seeds x 5 tumbles
    (0.8 to 1.2 of the plan's) a cell, the aim moved -0.4 to +0.2 m along the line; toppled
    at -0.4 / -0.3 / -0.2 / -0.1 / 0 / +0.1 / +0.2 m and overall, then missed over / short
    of 280:

    | range | aim | -0.4 | -0.3 | -0.2 | -0.1 | 0 | +0.1 | +0.2 | all | over / short |
    |---|---|---|---|---|---|---|---|---|---|---|
    | 3 m | foot | 45 | 52 | 60 | 92 | 100 | 100 | 100 | 79% | 6 / 54 |
    | 3 m | mid-height | 48 | 58 | 88 | 100 | 100 | 100 | 40 | 76% | 32 / 35 |
    | 5.27 m | foot | 52 | 78 | 75 | 95 | 80 | 100 | 100 | 83% | 33 / 15 |
    | 5.27 m | mid-height | 72 | 78 | 80 | 80 | 100 | 100 | 80 | 84% | 39 / 5 |
    | 8 m | foot | 80 | 90 | 75 | 80 | 80 | 100 | 100 | 86% | 38 / 0 |
    | 8 m | mid-height | 80 | 70 | 80 | 92 | 98 | 100 | 100 | 89% | 32 / 0 |

    The clean throw at 5.27 and 8 m now takes the kubb (80 -> 100%, 80 -> 98%); a throw
    20 cm long from 3 m now sails over it more often (100 -> 40%).
  - `tools/batonprobe.lua --rates 400`: the sweep is unchanged (its own aim at the foot:
    826 touched, 93% toppled); the computer at base kubbs 31% -> 28%, a field kubb 85% ->
    93%, the king 80% -> 95%.
  - `tools/drillscatter.lua --only 3`: unchanged to the digit (drills keep their aim).
  - `make realgames` (150 physics matches, seed 2; real / before / after):

    | | real | before | after |
    |---|---|---|---|
    | turns a game | 8.9 | 18.3 | 19.6 |
    | won by the team that threw first | 55.3% | 52.0% | 44.0% |
    | ended on the king | 100% | 92.7% | 88.0% |
    | a baton at field kubbs: missed | 24.7% | 20.6% | 14.2% |
    | took one | 49.4% | 70.1% | 72.2% |
    | took two | 16.0% | 8.7% | 12.3% |
    | three or more | 10.0% | 0.7% | 1.2% |
    | cleared the field | 83.4% | 56.4% | 62.1% |
    | five kubbs | 84.5% | 68.8% | 87.2% |
    | six kubbs | 78.6% | 44.7% | 65.4% |
    | eight kubbs | 67.6% | 8.2% | 16.3% |
    | turns from an advantage line | 14.4% | 39.4% | 34.0% |
    | a base kubb from 8 m | 32.7% | 33.0% | 29.5% |
    | a base kubb from an advantage line | 51.7% | 71.5% | 68.2% |
    | the king | 83.8% | 80.3% | 95.0% |
    | kubbs rethrown | 14.1% | 5.7% | 6.0% |
    | punishment kubbs | 1.3% | 1.1% | 1.0% |
    | illegal throws | 0% | 0.7% | 0.6% |

  - Self-tests: `aim-arc`, `camera-swing`, `clock-throw`, `clock-plan`, `hit`, `miss`,
    `field`, `king`, `low-hard`, `nerves` and `flight` pass.
- **Still off.** The computer now hits the king more often than tournament players (95%
  against 84%) and misses field kubbs less (14% against 25%); base kubbs stay near real
  play. The nerves and levels are not retuned here.
- **The end-first bounce** (looked at, not changed). A baton landing end first on grass
  rises off the ground at up to about 1 m/s. Set down end first at 4 m/s down (flat and
  textured grass): straight down and not turning it plugs (0 m/s); leaning 20 degrees with
  4 m/s forward 0.35 m/s, with its spin 0.91; leaning 10 degrees, spinning, 5 m/s forward
  1.94. With the ground's bounce `e` set to 0 those are 0, 0, 0.77; with the bite at 0
  about the same. So part is the forward speed vaulting over the planted end (mechanics)
  and part the ground's bounce, which the dig takes away only on a steep strike. A
  pointed hardwood end may plug more than that on a leaning strike, but there is no
  measured baton-on-turf figure to tune to, so it stays.

### What scatters a drilled kubb

Since 2026-11-16 (Jamie's words in "Drilling") a drill turns in the air and runs on, so
the first two findings below are history: they are what made the computer's lines too
perfect. Now (`tools/drillscatter.lua`, the same runs): with no mistakes it lands 5 cm
(sd) long or short and 2.5 across, runs on 31 cm (sd 32) and 17 across, and rests 27 cm
from its mark, 25% over 30 cm (textured grass); at the game's drill (x0.2) 28.5 cm and 29%;
at a baton's full mistakes 50 cm and 57%. In 40 matches (3780 drills) 47% go at the basket
itself and 53% at a spot beside the group; 66% touch nothing and rest 25 cm from the mark
(23% over 30), 34% touch a piece and rest 31 cm away (35% over 30); a touched piece moves
4 cm on average (12% over 10 cm). Since the computer drills into the group (2026-11-16,
"Tuned toward the real games"), 3535 drills: 21% at the basket, 79% at a spot by the group
(into it or beside it); 57% touch nothing and rest 24 cm from the mark (19% over 30), 43%
touch a piece and rest 19 cm away (17% over 30: the mark is now where the kubb it runs
into stops it); a touched piece moves 5 cm on average (16% over 10 cm). Parts 1 and 3 are
unchanged (the clean drill and the physics are). Part 4 (`--only 4`) follows the drills
thrown while a kubb lies in the far half: whether they reach a lying kubb or land on one,
their speed when they touch it and how often each speed ends touching, the gap at rest,
how far the struck kubb moves, and for those that never reach one whether they stopped
short, beside or past (figures in "Into the group"). Part 3 (`--only 3`, new) throws the plan's clean drill
onto 12 markers x 24 grounds and reports its attitude at release and at the touch, the
run on (mean, sd, p10, p50, p90, max, dead stops), the rest's pose and yaw, and the time
from touch to rest, and the mean rest along the throw from the mark; the figures are in
"Drilling". Part 5 (`--only 5`, only when asked) measures the aim allowance,
`drill.tune.slide` ("The aim allowance"), and prints it as the table takes it.
`--set name=value` sets a `drill.tune` number (`auto.name` an `autothrow.tune` one),
`--surface` and `--grounds` narrow parts 3 and 5.

`lua5.4 tools/drillscatter.lua [--n 300] [--matches 40] [--seed 2]` (Jamie approved the
measuring, 2026-11-16; no game changes). Part 1 throws the computer's drill at the basket
in an empty half and splits its miss into the air (where it first touches the ground
against its mark) and the ground (from there to rest), with the swing's mistakes scaled
and the ground flat or textured. Part 2 follows every drill of 40 physics matches.

- **The ground does not scatter a clean drill** (until 2026-11-16). With no mistakes it rests 0.4 cm from its
  mark on every one of 300 grounds (sd 0.1 cm): a drill plugs where it lands (it travels
  8 cm back from its first touch, the same every time). The patches change nothing a
  watcher could see.
- **The swing scatters it along the throw, not across.** At the game's drill (`drillScale`
  0.2) it lands 8.7 cm (sd) long or short and 1.1 cm left or right, and rests 4.4 cm from
  the mark on average, 1% over 30 cm. At a baton's full mistakes: 31 cm along, 5 across,
  27 cm from the mark, 27% over 30 cm. Distance is the backswing and the flick; the only
  sideways mistake is the shake.
- **The rest is wood.** In matches 29% of drills touch a piece on the way (1127 lying
  kubbs, 35 standing in 2485 drills): those rest 20 cm from their mark on average and 20%
  of them over 30 cm, against 5 cm and 1% for the 71% that touch nothing. A touched kubb
  is moved 8 cm on average, 29% of them over 10 cm. The spots are a kubb's length and a
  centimetre apart along the throw and the drill is 8.7 cm long or short, so it clips its
  neighbour about as often as that predicts.
- 24% of drills go at the basket itself (the first of a group), 76% at a spot beside it.
- So what loosens the game's groups now is, in order: drills clipping the kubbs already
  down, then the power error along the line. Not the ground, and not sideways aim.
- Flat ground (no texture) is not tighter: with no grass to hold it, the rare shaky drill
  rolls on (across sd 15 cm at the game's drill against 4 textured).
- Jamie (2026-11-16): "Real defenders raise kubbs away from combos." The engine's
  default raising policy (`apart`: the end farthest from the nearest other kubb) stays.
  A stricter rule was tried and not kept: a kubb in line along the throw counted as
  nearer (its distance up the pitch times 0.5, and 0.25), so a raised kubb leaves the
  line a baton carries along. Over 150 physics matches, seed 2 (real / `apart` / 0.5 /
  0.25): turns 8.9 / 14.6 / 16.6 / 17.9; batons that took two 16 / 18 / 16.5 / 16.6%;
  three or more 10 / 3.4 / 3.3 / 3.2%; cleared the field 83 / 70 / 63 / 62%. It moves the
  game away from real play. The defence is not where the gap is: tournament throwers
  take triples off defenders who raise well, so the missing triples are the attack's
  (how tight the drills are, and batons thrown at the line of a group).
  `tools/physmatch.lua --raise apart|together` picks the policy for a run.
