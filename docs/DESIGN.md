# Kubb: Throwing Wood — design

A Kubb game for the Playdate. Draft of 2026-11-13, written before any game code.
Jamie agreed to all seven recommendations in section 10 on 2026-11-13, so each
"Recommendation" there is the decision.

Sources: U.S. National Kubb Championship Rules V4.0 (usakubb.org; cited below as II.B.4 and so
on), the Planet Kubb Notation grammar and `kubb.js` from pk-kubb-score (vendored in
`tests/vendor/pk-kubb-score/`),
the 2017 Planet Kubb glossary, and Inside Playdate for SDK 3.1.2.

## 1. What it is

- Title "Kubb: Throwing Wood", repo `~/Projects/playdate-kubb`, bundle
  `com.throwingwood.playdate`, Lua, SDK 3.1.2. A plain Kubb game.
- Modes: Practice (drills), Versus Computer, Pass and Play.
- The crank is the throwing arm. Outcomes come from a physics simulation at real dimensions,
  not from dice.
- Every finished game is saved as a Planet Kubb Notation `.txt` file that the pk-kubb-score
  parser accepts.

## 2. Dimensions and constants (confirmed against Rules V4.0, I.B)

| Piece | Size | Mass used |
|---|---|---|
| Pitch | 5 m x 8 m, centerline at 4 m, six stakes | |
| Kubb (10) | 7 x 7 x 15 cm | 0.40 kg (rules: 0.3 to 0.5) |
| King | 9 x 9 x 30 cm | 1.2 kg (rules: 0.8 to 1.3) |
| Baton (6) | 30 cm long, 4.4 cm diameter | 0.25 kg (rules: 0.2 to 0.3) |

World coordinates in meters: x across (-2.5 to 2.5), y downfield (0 = Team A's baseline,
8 = Team B's), z up. The simulation always works in these units; only the renderer knows
about pixels.

## 3. Camera (the hard problem, settled first)

At true scale from eye level with a normal lens, a base kubb 8 m away is 5 px tall and 2 px
wide: `docs/camera/a-eye-level-true-scale.png`. That is unplayable, and scaling the pieces up
would make the physics a lie. The answer is both ideas from the brief: a telephoto aim camera
and a follow camera, plus a minimap for the whole pitch. Pieces are always drawn at true scale.

**Aim camera** (`b-aim-camera-field.png`, `c-aim-camera-baseline.png`). A crane shot from
behind the thrower: 3 m behind the throwing line, 3.4 m up, long lens (focal length 880 to
1000 px, a 23 to 26 degree field of view). It shows the target half only.

- Guarantee: a standing kubb on the far baseline is at least 12 px tall and 5 px wide. Field
  kubbs near the centerline are about 17 x 8 px, the king about 37 px tall.
- The lens is too long to show the full 5 m width near the centerline, so the camera moves
  with the player and pans with the swivel. The view is always centered on where the baton is
  pointed.
- From an advantage line the camera moves forward with the throwing line and keeps the same
  framing rule (farthest live target at least 12 px tall).
- The pitch is not dithered (Jamie, 2026-11-13: it makes things hard to see). White ground,
  2 px black lines, stakes as solid posts (3/4 inch by 6 inches, no shadow), a sparse rough outside the sidelines and past the
  far baseline. Kubbs read by a black outline, a black
  face away from the light and a solid black shadow; a piece looks the same lying down. The look
  is "Woodcut" (`docs/design/README.md` and its boards). The mockups here predate it and
  still show a dithered pitch.
- The raised viewpoint shows each kubb's top face and a hard black ground shadow, which is what
  makes a white box readable on a white pitch in 1 bit.
- First person and the plan view (Jamie, 2026-11-15, after play-testing an over-the-shoulder
  crane for the aim arc): aiming a baton or a drill is first person, this crane straight
  behind the thrower, looking just past the target circle. While B is held (planning the
  arc, tilt or spin) the camera swings out over the right shoulder, lower and wider, and
  zooms out until the whole target half, the planned arc and the circle are in view (far
  kubbs about 4 to 9 px tall); letting B go swings it back. Both moves take 0.4 s, eased.
  The fixed high drill view went with it; a drill shows its planned arc too. docs/notes/throw.md "The aim camera".

**HUD** (the Woodcut layout, `docs/design/README.md`). The pitch keeps a clear area in the
middle of the screen; the HUD sits around it: a black rail along the top (team, projectile
and number of it, targets left), the minimap at the bottom left, the clock (section 4) at
the bottom right with a prompt above it (`WIND BACK`, an inverted `FLICK!`, `EASE OFF`,
`CRANK DOWN`) and the planned tilt or spin beside it. After the release a result flag
(`3 DOWN`, `MISS`, `HELICOPTER`) sits left of the clock, and at rest the verdicts (power,
release, steadiness, and which way the nerves took it) along the bottom and a drill's
distance from its circle. The debug readout is off unless the practice pitch's "Pitch:
readout" is on (2026-11-15: the loft plaque, power chip and drill callout went with the stop on the notch).

**Minimap.** A 45 x 72 px top-down pitch in the bottom left corner at 9 px per meter: every kubb
as a 2 px dot, the king as 3 px, the aim line, the advantage line. It is the only view of the
whole pitch and it is always on during aiming.

**Follow camera.** On release the camera leaves the crane and flies to an **impact camera**
(`d-impact-camera.png`): low (about 0.9 m), 2.5 to 3 m from the predicted first contact, kubbs
about 35 px tall, so tipping, rocking and dominoes are visible. It tracks the baton on the way
in. The flight lasts 0.8 to 1.2 s, which is also when the physics is computed ahead (section 5).
After everything comes to rest it holds for a beat, then returns to the aim camera.

**Kubb tossing** uses the same aim camera (the target is the same half), and the impact camera
on the landing spot to show the dig, the cut and any clack.

**Raising view** (`e-raising-view.png`). Near top-down close-up of the fallen kubbs, one at a
time, with both footprints outlined.

The mockups come from `tools/camera_mockup.py` (pure Python, same projection math the game
will use). They are sketches of framing and legibility, not of final art.

## 4. Controls

The throw (Jamie and Tyler, 2026-11-15, after play-testing the stop on the notch): one way
to throw, modelled on how a real player throws, the same for batons and drilled kubbs.

- The d-pad positions. A and B are modifiers of the d-pad. The crank throws.
- **Point and throw.** A player who never presses A or B can play: the target starts on a
  kubb, the player stands behind it, the arc is chosen for them; they only crank. A (moving
  yourself) is the first level of control, B (the plan) the most advanced. Neither is
  needed.
- **Throw level** (Beginner, Club, Pro) sets how wide the gauge's targets are and how much
  a miss costs. It belongs to the player who throws (named players are planned in
  `docs/PLAYERS.md`); until players exist it is one setting in the System Menu.

### The three steps before the throw (in any order)

| Input | Does |
|---|---|
| D-pad | **Target.** Move a 0.5 m circle over the far half (a little past it: 3 m either side, 3.5 to 8.6 m out). For a baton it is where the throw goes: a clean throw comes down on its center, and with the circle on a standing kubb or the king its center goes through that piece at half the piece's height, so it meets the face instead of landing at the foot, bouncing and going over (a play test, 2026-11-16: "all of them went clean over the field kubb"); for a kubb, where it should come to rest. It starts on the nearest live target (standing field kubbs, else base kubbs, else the king), and stays wherever the d-pad leaves it: it never locks onto a kubb, so a player can aim off one to allow for the wind (Tyler's play test, 2026-11-15: the lock made 8 m too easy). A circle moved by hand stays put for the next throw. |
| Hold A + d-pad | **Position.** Walk: left/right along the throwing line, down to step back (up to 3 m), up to come forward as far as the line allows (the advantage line in a match; king shots and kubbs from the baseline). The player always faces the target: the swivel is worked out, never set. Until A is used the player stands straight behind the target, as far forward as allowed (clamped inside the line's ends). |
| Hold B + d-pad up/down | **Plan the arc.** Moves the release target on the gauge's forward side half an hour (15 degrees) at a time. Until B is used the arc follows the target: 3 o'clock at base kubbs, half past 3 at the king, 4 o'clock at field kubbs, half past 1 for a drilled kubb. |
| Hold B + d-pad left/right | **Plan the tilt** (baton): a tap tilts the baton's spin plane 5 degrees left or right, up to 20 (Jamie, 2026-11-15), to steer it after the first kubb it hits in a group. **Plan the spin** (kubb): taps add spin about the long axis left or right, on top of the small spiral every drill gets from the wrist. Spin holds a drilled kubb steady in the air (a gyroscope), so it lands nose first about as it left the hand; once down it moves it only a little, either way (Jamie, 2026-11-16: "at most… one to three rotations"). Measured (2026-11-15, `tools/tiltgroups.lua`): tilt turns the baton after its first hit by only about 0.15 degrees per degree; spin is up to three taps of 22 rad/s each way. |

Everything the plan sets shows on the gauge and the HUD while aiming.

### The throw: the crank as a clock

The crank is the throwing arm. Read it as a clock: 6 is the arm hanging straight down,
the backswing goes up the left side (7, 8, 9, 10, 11, 12) and the forward swing up the right
(5, 4, 3, 2, 1). The forward swing is anti-clockwise (`swing.tune.forwardSign`, set on
hardware 2026-11-13).

**Crank direction** (Jamie, 2026-11-19: "a playdate user was super confused because he was
turning the crank opposite of the direction I thought made sense. He says even though he
knows it now it is still backward to him. That feels like a left - right hand pref for
playdate crank."). A device setting flips it: the scene's own System Menu item on every
scene with a throw ("Pitch", "Drill", "Match") has the choice "flip crank". It turns
`forwardSign` over for the whole device (`source/device/crank.lua`; the core is never
edited, the game sets the tune value at launch and on a flip), is kept in the datastore
`crank` (`{ flipped = true }`, today's direction by default) and says CRANK FLIPPED in the
prompt flag. A wind-up in progress is dropped, never thrown. Everything that reads the crank
as the arm flips with it (the swing, the dial's arm, the settle scene's tip); the score sheet
and games list scroll with the raw crank and do not. The dial is the arm, not the crank: back
stays up the left and forward up the right whichever way the crank turns. One setting per
device, not per player (yet). HOW TO THROW's first step and a nudge say it exists: a player
who turns the crank forward from 6 three times (60 degrees or more each, `throw.tune.nudge*`)
with no throw sees CRANK BACKWARD? MENU, PITCH: FLIP CRANK over the prompt until a wind-up
starts.

| Clock | Backswing (power) | Clock | Forward swing (release) |
|---|---|---|---|
| 6 to 7 | dead zone: the throw has not started | 5 | low and flat (field kubbs, a line drive) |
| 9 | about 4 m | half past 3 | king shot |
| 10 | 8 m | 3 | normal throw at a base kubb |
| 10 to 11 | longer throws (corner to corner is 9.4 m, about 10:20) | 1 to 2 | high: drilling a kubb |
| 11 to 12 | overpowered | | |

- **The gauge** is a dial with the arm on it. On the back side it marks the **power
  target**: the backswing this throw needs, from the distance to the target and the arc
  planned (a flatter arc needs more). On the forward side it marks the **release target**:
  where to stop. Both are ranges, not points; the Throw level sets their width. Walking,
  moving the target or changing the plan moves them at once.
- **Backswing.** The crank crossing 7 going back starts the wind-up; how far back it goes
  (the farthest point) sets the power. Inside the power target the throw has the speed it
  needs. Short of it the throw goes short; past it, long. Past 11 is overpowered: more
  speed than any throw on the pitch needs, which can smash through a group of field kubbs
  with a low, hard throw, but every step past the target makes every other error worse.
- **Forward swing.** The crank must pass 6 to throw. The throw leaves where the crank
  stops (its farthest forward point). That sets the launch angle: 5 o'clock is about 12
  degrees, 3 o'clock about 32, half past 1 about 47, 12 o'clock about 62 (a line through
  these). Inside the release target the launch is the planned arc; outside it the throw
  leaves at the angle the crank stopped at and the physics makes it short, long or high.
- **Flick speed** scales the power: a fast flick (about 1000 deg/s and over, to be tuned) gives
  all the power of the backswing, a slow one as little as 20 percent.
- **Steadiness** of the forward swing: a shaky flick pulls the throw sideways and wobbles
  the baton; a very shaky one is a helicopter (illegal, II.B.1). Overpowering makes both
  worse. A planned tilt and the shake add up toward the helicopter limit (30 degrees).
- **Nerves** (2026-11-16). Even a clean swing is not a machine: every throw, the player's
  and the computer's alike, goes a little off the planned line (an angle, so the miss in
  metres grows with the range) and a little long or short (a share of the throw). How much
  is set by the level, and grows with the power of the throw, the swing's roughness and
  overpowering. The draws come from the match's seeded random stream (the computer) or
  from the swing itself (the player), so a recorded match replays exactly.
- **The baton's turn** (2026-11-16). The wrist sets how fast the baton turns end over end.
  A thrower's habit is about one turn over the flight (a little over: 1.1), so the plan's
  rate is that over the clean flight's time, within what the arm and wrist can give (a 2 m
  lob turns only about two thirds of a turn). A slow flick turns it less, and like the
  nerves each throw draws its own turn, more for a beginner, so the same plan lands the
  baton end first one throw and flat the next.
- **What goes wrong.** Stopping before 6 lets the wind-up down (no throw). Cranking on past
  12 is a sky ball: the highest launch, with a large error. The crank swinging back after a
  throw is ignored for a moment, so it does not start a new one.
- **After the throw** the HUD says what happened in a word each: power (SLOW when the backswing was enough but the flick was not, SHORT, ON, LONG),
  release (LOW, ON, HIGH), steadiness (STEADY, SHAKY) and the nerves' side (PULLED LEFT,
  STRAIGHT, PULLED RIGHT: STRAIGHT within 6 cm of the line at the target), and the dial keeps a dot where the
  backswing peaked and where the crank stopped until the next wind-up.

How it plays (Jamie and Tyler's examples):

1. An 8 m baton at a base kubb: target it, pull back to 10, stop at 3.
2. A king shot: target the king, pull back to 10, stop between 3 and 4.
3. A field kubb group from the advantage line: target, pull back to 11 (the risk), flick
   fast and stop at 5.
4. Drilling: target the spot, pull back to 9 or 10, stop at 1 to 2, spin planned with B.

The computer throws the same way: it plans a target and an arc and makes a swing with
mistakes in it, and the gauge shows its arm going back and forward as it throws.

### Kubbs (drilling)

Always from the baseline (II.C.1). A drilled kubb is thrown with the same physics as a
baton (Jamie, 2026-11-16): it leaves the hand nose down, held by its back end, with a
small spiral about its long axis from the wrist (always some, even with no spin planned);
spin planned with B is more of it. A spun kubb is a gyroscope and comes down nose first
about as it left the hand; with only the wrist's spiral the air turns it steeper and less
the same each time. On the ground it is a kubb like any other: an edge that strikes the
turf bites (grass holds a little, sand a lot, snow lets it skate), and otherwise it keeps
its energy, bounces, wobbles and runs on, on grass about a metre at the drill's arc (a
lower, faster drill farther), and it ends turned every way. Jamie (2026-11-16): "it is
impossible to stop that much energy with just the ground and grass -- except a perfect
dug in corner that just drops but that is exceedingly rare", and "good drillers roll into
other kubbs": a drill that runs into a lying kubb stops by it. Spin moves a landed kubb a
little either way, never several turns ("at most… one to three rotations"). The target
circle is where a clean drill most likely ends; the game solves the clean drill that lands
short of it by its average run on at the arc and distance planned, and the aim arc shows
where it lands. Every mapping is a tunable in `tw.drill.tune` (`source/core/drill.lua`).

The computer drills the way good drillers do: the first kubb of a turn goes to a spot
near its basket, and each later one is aimed just short of a kubb already down, so it
runs into it and ends against it. With two or three kubbs it builds a line (it aims at
the front kubb, so the line grows toward the thrower); with four or more a cluster (the
kubb nearest the group's middle). Where no kubb leaves a clear lane it falls back to a
clear spot beside the group. Its aim is not made worse on purpose: the scatter is the
swing's and the run on's (`tw.autothrow.tune.into`, `intoShort`).

### Throw levels

| | Beginner | Club | Pro |
|---|---|---|---|
| Power target, half width | 15 degrees | 8 | 4 |
| Release target, half width | 30 degrees | 18 | 10 |
| Error inside a target | a tenth | 0.3 | 0.6 |
| Shake and overpower costs | low | medium | full |
| Nerves: degrees off the line, 1 sd, an 8 m baton | 1.5 | 0.75 | 0.5 |
| Nerves: share long or short, 1 sd, an 8 m baton | 8% | 4% | 2.5% |
| Nerves: the baton's turn, 1 sd, turns over the flight | 0.2 | 0.1 | 0.06 |

First guesses, to be fitted from play (`tw.plan.levels`, `source/core/throwplan.lua`).

### Practice drills

PRACTICE's drills (docs/notes/drills.md "Practice drills") are how a real player practises and how the
throw gets tuned: every throw in a drill is recorded with the drill's name. 8 METERS
(baselines), THE HOUSE, KING SHOTS, BLAST (a bucket of kubbs to drill), AROUND THE PITCH,
and two new ones: DOUBLES (field kubbs in pairs and triples, 3, 7 and 15 cm apart: a point
for every kubb down, a bonus for two or more with one baton) and THE WALL (drill kubbs into
the centerline stake: a point for each kubb that rests in a wall running from the stake
along the centerline).

### Build order

1. This spec. 2. The swing, the plan and the levels (pure core, tested). 3. The controls,
the gauge and the verdicts in the throw scene; the computer throws the same way. 4. DOUBLES
and THE WALL. 5. Jamie and Tyler play the drills; the targets, flick speed, stop detection
and shake limits are fitted from the recordings. 6. The match and HOW TO THROW.

### HOW TO THROW

The walkthrough, on the practice pitch with the real crank and real throws (built
2026-11-15): 1 the crank is your arm (down to 6), 2 point and throw (what the verdicts
mean), 3 how far back is how far (a throw with the power ON), 4 where you stop is the arc
(the release ON), 5 the d-pad aims (it stays where you leave it: aim into a wind), 6 hold A
to walk, 7 hold B to plan (arc, tilt, spin), 8 that is the throw. Step 1 also says where
the crank's direction is flipped ("CRANK FEELS BACKWARD? MENU, PITCH: FLIP CRANK.", the
Playdate's own line: the walkthrough's words are the engine's). Each step goes on once
the player has done it and A is pressed; a tap of B skips one. It follows HOW TO PLAY,
six cards with the rules of Kubb in plain words (the pitch, batons, throwing kubbs back
in, field kubbs first, the king last, the score sheet), the last item of PRACTICE's menu,
which starts on it until HOW TO THROW has been seen; and it is the practice pitch's System
Menu "Pitch: how to".

"The hard way" (land out of bounds and cut back in), nudges and clacks are not special moves;
they fall out of the physics. How much a kubb cuts depends on the surface (section 5): more on
grass, less on sand. The Minnesota slide is the same throw on ice, built last.

## 5. Physics

Pure Lua, 3D rigid bodies, fixed 1/240 s step.

- **Baton:** a capsule (segment plus radius) with full 3D orientation. Ground contact at its
  two end spheres, with friction, so it bounces, skids, and can turn sideways and roll (a
  steamroller, which is legal).
- **Kubbs and king:** boxes. Ground contact at the eight corners with friction and low
  restitution; a bounce between two pieces is solved with their footing and with every
  piece pressed against them, so a baton that strikes the front of a row of touching kubbs
  strikes the row (a row of four falls from one baton about as often as before the bounce
  took its friction: one or more 93% of hits, all four 35%; 2026-11-17). Tipping about an
  edge, rocking back upright, and falling are all the same contact solver, not a state
  machine. A standing kubb sleeps until something touches it. A piece at rest on another
  piece sleeps too, once what holds it up is asleep or on the ground, and pieces resting on
  each other fall asleep together (2026-11-16).
- **Collisions:** capsule against box (closest point on the segment to the box, the box's
  edges rounded by a centimetre: wood is never a knife edge, and a baton that clips a kubb's
  top edge tips it rather than pressing it into the grass; Tyler's play test, 2026-11-15;
  a baton lying along a face or an edge touches it at both ends of the part that lies
  along it, so it cannot pivot on one point and sink in; 2026-11-16),
  box against box (corners of each inside the other, plus edge on edge: the closest points of
  two crossing edges, and the points where the edges of crossed faces cross; 2026-11-16).
- **Ground:** the surface is a game option chosen per game (Jamie, 2026-11-13: "Kubb plays
  very different based on the surface"), and each surface is one set of contact parameters:
  friction, bounce, and a "dig" term that takes extra energy when a corner or edge arrives
  steeply. No surface is even: small patches vary in friction, bounce and dig, and each is
  tilted a few degrees, so a steep landing is turned a little one way or another (never
  sped up).
  - **Grass:** high friction, little bounce, moderate dig, and a bite: an edge that strikes
    steeply cuts in and is held for a moment. A drill runs on about a metre (2026-11-16; it
    used to die where it landed). Batons skid and can steamroll. The grass holds a piece by
    how hard it presses: a baton propped on a kubb with one end in the grass is held less.
  - **Sand:** very high dig and almost no bounce or slide. Edges bite hard, so kubbs
    stop soon after they land and placement is mostly in the air; batons stop where they hit, so there are no
    skids into a second kubb.
  - **Ice** (stage 7): very low friction, for the Minnesota slide.
  The surface is written to the game file's `[Surface]` header, and practice bests and
  computer hit rates are kept per surface. Grass and sand are both tuned on hardware in
  stages 2 and 4.
- **Air:** a thrown baton or kubb feels the air's drag in flight (quadratic, against the air
  moving past it, so the wind is the same drag in moving air): a baton loses about 1.2
  m/s^2 at 10 m/s, a kubb about 1.9 (published drag coefficients for a tumbling cylinder
  and block). The aim allows for it, so a clean throw still lands where it is aimed; over
  8 m it costs a baton about 0.45 m of carry, which the thrower makes up with about 4%
  more speed.
- **Toppled** means the long axis came within a few degrees of parallel to the ground at any
  point. A kubb that falls and ends up standing on an end is still toppled (II.B.10). A kubb
  pushed out of bounds without toppling goes back (II.B.7).
- **Compute ahead.** After release there is no more input, so the result is fixed. The
  simulation runs ahead of the picture during the flight and records poses; playback reads the
  recording at 30 fps. If the device falls behind, playback slows down, which reads as slow
  motion at impact (on top of the deliberate slow motion around the first hit; the
  frame-time log, `frames.jsonl`, tells the two apart per throw). This is the performance plan for Lua on the device; stage 2 measures it on
  hardware before anything is built on top.
- **Numbers.** Playdate Lua uses 32-bit floats and desktop Lua uses doubles, so a throw will
  not replay bit-for-bit across the two. Nothing depends on that: saved games are notation,
  not replays. Tests assert outcomes with tolerances.

## 6. Rules

Rules V4.0 unless a question below changes it.

- **Turn engine:** a pure-Lua state machine: kubb tossing, rethrows, raising, punishment
  placement, batons, end of turn. The Playdate layer only feeds it resolved throws and choices.
- **Order of attack:** field kubbs, then base kubbs, then the king. King shots from the
  baseline even when there is an advantage line.
- **Advantage line:** through the center of the standing field kubb closest to the centerline
  (II.B.2). Batons at kubbs may be thrown from it.
- **King:** toppled by a baton or a kubb before every kubb is down loses the game at once.
- **Own-half field kubbs** hit by a baton go back, along with anything else that baton
  toppled, and the baton is forfeited (II.B.11).
- **Kubb tossing:** in bounds is judged by the kubb's center against the target half; a kubb
  that cannot be raised in bounds is rethrown once after the others, and a second failure makes
  it a punishment kubb, placed by the defender anywhere in their half at least a baton length
  from the king and stakes (II.C.6, II.D.11). A thrown kubb that knocks an established field
  kubb out of bounds sends that kubb back to be thrown again (II.C.5a): this is the rescue,
  `Q`.
- **Judged at the final position** (Jamie, 2026-11-13): in or out is not judged when a kubb
  stops. The kubbs of a round (first throws, then rethrows) all stay on the pitch where they
  lie, out ones too, and later kubbs may move them; when the round's last kubb is at rest
  every kubb is judged where it lies. A kubb on another is lowered (`N`) unless the one under
  it is out; an established kubb out is rescued (`Q`); a kubb thrown once and out is
  rethrown in the next round, all of them picked up at once; a kubb thrown twice and still
  out is a punishment kubb (`P`). A kubb out then knocked in is not rethrown; a rescue knocked
  back in is no rescue. A kubb that touches a field kubb in the thrower's own half (II.C.4b)
  is out whatever happens to it later; that field kubb is put back at once. The king toppled
  by a kubb still loses at once. Details: docs/notes/rules-engine.md "Judged at the final position".
- **Raising:** see Q2.
- Opening batons: see Q1. Early base kubbs: see Q3.

## 7. Notation and game files

One file per finished game in `games/` inside the game's Data folder, named
`YYYY-MM-DD-HHMM-<team-a>-v-<team-b>.txt`, in the README format of pk-kubb-score:

```
[Event "Throwing Wood"]
[Location "Playdate"]
[Start "2026-11-20 19:42"]
[End "2026-11-20 19:58"]
[Duration "16m"]
[Surface "Grass"]
[Team A "Jamie"]
[Team A Players "Jamie (j)"]
[Team B "Playdate"]
[Team B Players "Club (c)"]
[First "Team A"]
[Win "Team B"]
[Scored by "Throwing Wood 1.0.0"]
[Mode "Versus Computer"]
[Rules "U.S. Championship 4.0, 2-4-6"]

1. j:- j:B
2. c:I c:F c:- c:B c:-
3. j:2I j:2F j:- j:B j:- j:- j:B
```

What the recorder writes:

| Event | Notation |
|---|---|
| Kubbs thrown in | `p:5I2R`, `p:2IRP`. No inkast token when there are no kubbs to throw. |
| Rescue | `Q` on the inkast token; the rescued kubb is also counted in `I`. `Y` (a failed attempt) is intent the game cannot see, so it is never written. |
| Kubb resting on another kubb | `N` count (provisional in the grammar): see Q2. |
| Advantage line | `nA`, whole meters from the attacker's baseline, rounded down (so 2A and up is a "meaningful advantage"). |
| Batons | `-`, `F`, `2F`, `B`, `2FB`, `K`, `=` (king shot missed), `Z` (illegal throw, including II.B.11), `E` (king toppled early), `X` for batons left when the game ends. |
| King toppled by a thrown or struck kubb | `4IE`, `2FE`. |
| Resign (menu) | `G` on the resigning team's own turn. |
| Opening 2-4-6 | Turns 1 and 2 simply have two and four baton tokens, like the 2015 games. |
| Notes | `# ...` at the end of the turn, for things the tokens cannot say. |

Unfinished games are kept in the datastore so they can be resumed; they are not written to
`games/` until they end, because a file with no ending draws a parser warning.

**The gate:** a Node test loads `kubb.js` and the generated grammar parser from
`tests/vendor/pk-kubb-score/` (copies of pk-kubb-score's files) and runs both over
every generated game. The grammar must accept every file. `kubb.js` must report the same
winner as the header, and its warnings are listed and reviewed; the target is zero.

## 8. Engineering

```
source/            what pdc compiles
  main.lua         Playdate shell: scenes, input, drawing, files
  core/            pure Lua, no playdate.* : vec, quat, body, collide, world, swing,
                   camera math, rules, notation, ai, drills
  scenes/ render/ selftest/
tests/lua/         unit and scenario tests for core/, run on desktop Lua 5.4
tests/node/        notation gate against pk-kubb-score
tools/             camera mockups, AI-vs-AI game generator, crank trace tools
```

- `core/` uses Playdate's `import`; the desktop test runner supplies an `import` shim, so the
  same files run in both places unchanged.
- **Desktop Lua:** luajit is Lua 5.1 with extensions, so the tests use
  `lua@5.4` from Homebrew, installed 2026-11-13 at `/opt/homebrew/opt/lua@5.4/bin/lua5.4`
  (keg-only). Homebrew's plain `lua` is 5.5, which is not what the Playdate runs.
- **Headless games:** the AI plays itself on the desktop through the same physics and rules,
  producing hundreds of games for the notation gate and for tuning hit rates.
- **Simulator self-test:** `Playdate Simulator <pdx> selftest=<scenario> out=<dir>` (read from
  `playdate.argv`). A scenario scripts crank samples and button presses, saves frames with
  `playdate.simulator.writeToFile`, and quits with `playdate.simulator.exit()`. Lua `print`
  does not reach the Simulator's stdout and Lua can only write text inside the Data folder, so
  the result marker goes there and the Makefile collects it (details in `docs/notes/selftests.md`). Frames are
  saved at 1x for the subagents' own checks and at 2x for anything Jamie looks at.
- `make build`, `make test`, `make selftest` with full SDK paths (`make games` is kubb-engine's); no
  `PLAYDATE_SDK_PATH` needed.

## 9. Stages

Each stage goes to an Opus subagent on its own branch, with this document, the repo's
`AGENTS.md`, and a brief that lists the files it owns and the checks it must pass. Claude
reviews every stage first: runs the tests, looks at the screenshots, reads the diff, and
sends it back with findings until it passes. The stage then goes up as a pull request, Codex
reviews it, and it merges on a green `validate`. Jamie gets a hardware build at the
points marked.

| # | Stage | Handed | Checked by |
|---|---|---|---|
| 0 | Scaffold and harness | This doc; SDK paths | `make test` green with one trivial Lua test and a hand-written game through the Node gate; `make selftest` produces a PNG from the Simulator (this proves the Simulator can be driven from a script on this Mac, the first risk to retire) |
| 1 | Camera and throw feel | Section 3 and 4; the mockup script | Projection unit tests (far base kubb at least 12 px); swing-model tests on synthetic and recorded crank traces (clean is legal, jerky is a helicopter); six scripted screenshots reviewed against section 3. Batons fly on a plain arc with no collisions yet. **Hardware: Jamie tunes the flick.** |
| 2 | Physics | Section 5 | Scenario tests: a nudged kubb rocks and stands, a harder hit topples, a three-kubb domino, baton tumble rate, steep drill loses more energy than a shallow lob; step-rate benchmark on desktop and a timing screen on device. **Hardware: frame rate at impact.** |
| 3 | Rules and notation | Sections 6 and 7; the answered questions | Rules unit tests per rule cited; a random-thrower plays 500 headless games, all through the gate; a bare two-player game playable start to finish in the Simulator with simple lobbed kubbs and automatic raising |
| 4 | Drilling and raising | Sections 4 and 6; glossary entries | Tests: flat drill stops within a set distance, regular and goofy cuts go opposite ways, out and rethrow and punishment, rescue writes `Q`; raising screenshots for free, forced and obstructed kubbs. **Hardware: Jamie tunes drilling.** |
| 5 | Opponent, pass and play, saved games | Q4, Q5 | AI-vs-AI runs: hit rates per level inside agreed bands, all games through the gate; hand-off screen and name entry screenshots; saved-game viewer screenshots |
| 6 | Practice drills | Q6 | Each drill's scoring unit-tested; screenshots |
| 7 | Polish and sound | | Launcher card and icon, menus, crank-docked prompt, sounds, ice surface; full self-test run; a release `.pdx` |

**Design session** (Jamie, 2026-11-13): after the stage 1 hardware session and before stage
4, a Claude Design session lands the look and the screen-by-screen interactions: how pieces,
shadows and lines are drawn, ground cues for depth, the HUD, type, menus, title, launcher
card, and the flows for hand-off, raising, punishment placement, saved games and drills. Its
input is a brief with the constraints and the stage 1 screenshots; its output goes into
`docs/` as the visual spec that stages 4 to 7 are checked against. Crank feel is not a design
question; it is tuned on hardware. Stages 2 and 3 run alongside the session.
The brief is `docs/DESIGN-BRIEF.md`, with the current screens in `docs/brief/`.

**Stage 1 as built** (differences from sections 3 and 4, to revisit in the hardware and
design sessions):

- The 12 px rule pins the aim lens at about 1000 px, so when the aim is on the far baseline
  the centerline and the king's base are below the frame. Once there are field kubbs
  (stage 3) the camera frames the live targets instead.
- Kubbs are lit from the far left: checker face toward the thrower, black +x face, shadow to
  the right. The dot pattern outside the sidelines stops at the far baseline.
- The baton enters the frame about a quarter of the way into its flight, and the lens widens
  mid-flight.
- The aim preview: the line on the minimap, and on the pitch a dashed 3D arc of a clean
  throw at the loft set with a ring where it lands (Jamie and Tyler, 2026-11-14: "like
  billiards on a computer"), at full power: the farthest the aim reaches. So
  the arc reads as an arc, the aim crane stands 1 m to the thrower's right, over the
  shoulder, and looks up (or widens, for a high loft) until the whole arc is on screen.
- The low, hard throw (Jamie, 2026-11-14: a field kubb near the baseline is hit low and
  hard, to roll it into others): loft goes down to 5 degrees, and below 35 a baton is
  thrown harder (`flight.loftBoost`), so full power carries about 8.9 m at any loft: 9.2
  m/s at 35 degrees, 11.8 at 15, 13.6 at 10, 16.8 at 5. A flat throw lands short and
  skids in. (It was 15 degrees at the same top speed: full power landed 5.9 m out.)
  Superseded 2026-11-15 by section 4: the arc planned down to 5 o'clock is the low throw.
- Open: a baton at rest on plain white ground reads as floating; when swivelled, far
  kubbs can pass under the minimap.

**Hit effects** (Jamie, 2026-11-13, for stage 7): a comic-book burst ("POW", "BAM") at the
point where a baton strikes a kubb, designed together with the hit sound. The physics
already records the time and place of the first hit, and the slow motion gives it time to
be read.

**Stage 3 match as built** (the bare two-player game; docs/notes/match.md "Match"):

- It is pass and play on one Playdate (stage 5's mode, without names): teams "Team A" and
  "Team B" with one player each, a hand-off card before each team's turn, and Team B
  throwing from the far baseline with the whole pitch turned 180 degrees, so every throw is
  made from the bottom of the screen. The title offers PASS + PLAY and PRACTICE.
- Kubbs are lobbed, not drilled: the baton's swing, a kubb body turning end over end at
  half the swing's tumble, no cut. The follow and impact cameras are the baton's.
  (Superseded for the players' own kubbs by the drilling prototype: section 4 "Kubbs
  (drilling)"; the computer thrower drills too, through the plan, since 2026-11-15.)
- Raising and punishment placement are automatic (the engine's policies); there is no
  raising view yet.
- The aim camera frames the live targets (field kubbs, else base kubbs, else the king) and,
  for near field kubbs, looks nearer than 7.5 m (1.5 m past the nearest, at least 3 m).
- The advantage line is a 2 px line on the pitch, dashed 2 on 2 off (Woodcut), and a dotted
  row on the minimap.
  The d-pad walks up to it; king shots are from the baseline.
- The System Menu's third item is per scene: "Pitch" on the practice pitch, "Match" in a
  match (resign, or leave to the title without a game file). A resign is the team on turn.
- The game file is written to `games/` in the Data folder when the match ends.
- Within a turn the pitch keeps what the throws left there: each thrown baton lies where it
  came to rest and each kubb it knocked down lies where it fell, as real bodies in the next
  throw's physics (a baton can hit or skid off them, or push one into a standing kubb and
  topple it, which counts for that throw). Tossed kubbs lie where they landed until they
  are raised. The hand-off clears it all and the pitch is the engine's again. The rules
  engine stays the judge: a kubb already down adds nothing when it is hit again.

**Woodcut as built** (type, title, cards and launcher from `docs/design/`; docs/notes/presentation.md
"Woodcut type, title, cards and launcher"):

- The display face is Throwing Wood Display, a 1-bit cut of Londrina Solid Black (SIL OFL
  1.1, renamed because "Londrina Solid" is a Reserved Font Name) at cap 16 and 32; labels are
  Roobert 10 Bold from the system, in capitals.
- The title shows only what works today: PASS + PLAY and PRACTICE (no VS PLAYDATE, no GAMES,
  no rules line). The menu is set in the display face at 16 px.
- The hand-off card says who takes the Playdate, what the other team took last turn ("THE
  FIRST TURN" on turn 1, "TOOK NONE" for a turn with no kubbs), the kubbs and batons to throw,
  and a small map of the pitch with the turn and base count. The winner card gives how it was
  won, turns and minutes, the winner's baton hit rate and whether the game file was saved;
  A is a rematch, B the title. Names are set at 32 px, smaller than the boards.
- The launcher card, its highlight (the last B tipping over), the king icon and the launch
  image are in `source/launcher/`.

Stages 2 and 3 do not depend on each other (rules talks to physics only through "what did
this throw topple and where did things come to rest"), so they run in parallel in separate
worktrees after stage 1.

## 10. Decisions (questions as asked, all recommendations accepted)

**Q1. Opening.** Rules V4.0 use 2-4-6: two batons, then four, then six. The 2015 archive games
use it; the earlier ones use six from the start. *Recommendation:* 2-4-6 by default with a
"six from the start" option. First throw decided by a coin flip now, and by a lag at the king
(closest baton without toppling it, II.A) in stage 7.

**Q2. Raising and stacking.** By the rules the defender raises each kubb, keeping two corners
down, and picks the end only when both footprints are clear and in bounds. A kubb that lands
on top of another is lowered straight down beside it. There are no towers in the U.S. rules.
*Recommendation:* follow the rules; when a human defends they pick ends in the raising view,
with a setting to raise automatically; no tower stacking; write the provisional `N` count
when a kubb comes to rest on another.

**Q3. Base kubbs knocked early.** Rule II.B.4a: the base kubb is stood back up and stays a
base kubb. `kubb.js` warns on a `B` while field kubbs stand. *Recommendation:* record what
counted (`-`, or just the `F` part) and add a note such as `# b3 toppled a base kubb early;
raised`. A baton that takes the last field kubb and then a base kubb counts both: `FB`.

**Q4. Computer opponent.** *Recommendation:* three levels, Backyard, Club and Championship.
The computer throws through the same physics: it works out the throw it wants, then its aim,
power and spin are off by an amount set by the level. Backyard lobs kubbs loosely and throws
at the nearest kubb (about 20% from 8 m). Club groups kubbs near a center stake and looks for
doubles (about 40%). Championship drills tight groups with cuts, throws deep when it has more
kubbs than it can clear, raises to break up lines, and hits about 60% from 8 m.

**Q5. Names, ids and saved games.** *Recommendation:* one player per side in version 1, named
with the Playdate keyboard; the id is the lowercased name with anything but letters removed
(`j` style ids if two names collide). The computer is team "Playdate" with the level as its
player. On the device, a Games list opens a scoresheet view of any saved game with hit % and
efficiency. Files are read off the device in Data Disk mode, and in the Simulator from
`~/Developer/PlaydateSDK/Disk/Data/com.throwingwood.playdate/games/`. Optional extra: a QR
code that opens the game in the Planet Kubb Score stats page.

**Q6. Practice drills.** *Recommendation:* five. 8 Meters (six batons at five base kubbs, hit
% tracked). The House (drill five kubbs; score is how many touch the 2 x 2 baton square at a
center stake once raised). King Shots (from the baseline, streak counted). Blast (a preset
group, clear it in as few batons as possible, with first-baton efficiency). Around the Pitch
(inkast to marked spots, from the Inkastare tips).

**Q7. Lua 5.4.** `brew install lua@5.4` for the desktop tests.
