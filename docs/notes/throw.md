# The throw, aim, input, tunables and playback

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

## The throw

DESIGN 4 is the rule book (Jamie and Tyler, 2026-11-15, after play-testing the stop on the
notch: "one way to throw, modelled on how a real player throws"). The pure parts are
`core/swing` (the crank only: the clock), `core/throwplan` (`tw.plan`: target, stance and
plan to the clock's targets, and a measured swing to a launch) and `render/hud`'s clock,
verdicts and plan chip; `scenes/throw.lua` puts them together, the same for batons and
drilled kubbs. It replaced the stop on the notch, the A/B + crank swivel and loft, the
double taps, `flight.loftBoost` in the player's throw, the loft plaque, the power chip,
the stop and cut flags, the drill callout and the first HOW TO THROW (written again for
this throw: "HOW TO THROW" below).

- **Controls** (aim mode). The d-pad alone moves the target circle (`s.markerX`,
  `s.markerY`, view frame; 0.5 m across, `throw.tune.markerRadius`), faster the longer it
  is held (`drill.tune.markerSpeed` .. `markerSpeedMax`), kept in `drill.clampMarker`'s
  area (3 m either side, 3.5 to 8.6 m out). It stays where the d-pad leaves it: no
  snapping (Tyler's play test, 2026-11-15: the circle locking onto the kubb made 8 m too
  easy and left no way to aim off it for the wind). A circle moved with the d-pad
  (`s.markerSet`) stays put for the team's next throw while a live target stands within
  `keepNear` (1 m) of it, its default arc read again from the nearest target (`retarget`;
  Codex on #98); one never moved starts
  each throw on a live target (`s.markerOn`, kept while that target stands).
  `throw.aimAt` (self-tests, callers aiming at a piece) still snaps onto a standing target
  within `snapRadius` (0.25 m; `plan.snap` over `s.snaps`). A + d-pad walks (`walkSpeed`,
  along the line, back to `backMax`, up to
  the advantage line for a baton, the baseline for a kubb) and sets `s.stanceSet`; until
  then the stance is `plan.stance`, straight behind the circle as far forward as allowed.
  B + up/down taps move the planned release `plan.tune.arcStepDeg` (15) within
  `releaseMinDeg`..`releaseMaxDeg` and set `s.arcSet`; until then the release is
  `plan.arcFor` the kind of target nearest the circle (base 3 o'clock, king half past 3,
  field 4, a drill half past 1). B + left/right taps: a baton's tilt (`s.tilt`, steps of
  `tiltStepDeg` to `tiltMaxDeg`), a kubb's spin (`s.spin`, to `spinSteps` taps). While A or
  B is held the crank does not throw. The swivel is always the plan's (`s.sol.swivel`).
- **The plan.** `replan(s)` (`throw.replan`) runs `plan.solve` into `s.sol` (reused, no
  tables) only when an input changed (`s.planDirty`: the circle, the stance, the arc, the
  projectile) or the level did. A new throw's circle starts on the live target nearest the
  thrower (`retarget`; it stays on its target while that stands: practice after a throw,
  a team's later batons); the arc, tilt and spin start afresh each match throw. Stay put: a
  team's later batons of a turn keep a stance walked with A. AROUND THE PITCH gives its
  own stance (`setup.playerX`). For self-tests and callers: `throw.aimAt(s, x, y)` (the
  circle, snapping onto a standing target within `snapRadius`), `setStance`, `setArc`, `setTilt`, `setSpin`.
- **The level.** `throw.levelFor(s)`: `s.level` (a named player's, later) or `throw.level`,
  which `main.lua` sets from the System Menu's "Level" (`beginner`, `club`, `pro`; the
  datastore "level", club by default).
- **The throw.** On a release `launch(s, r)` takes `plan.launch(s.sol, r, {projectile,
  tilt, spin, level})` and `fire` launches `world.launchBaton` or `world.launchDrill` with
  its outputs (and the flight prediction the cameras use with the same speed, loft and
  swivel). The swing's let-downs (stopped at or before 6) throw nothing. The recorder adds
  no samples in the swing's cooldown.
- **The Playdate's throws** (`throw.autoLaunch(s, a)`, `s.scripted`): `core/autothrow`'s
  launch as it is, mistakes included (`a.speed`, `a.loftDeg`, `a.swivel`, `a.tumbleRate`,
  `a.tilt`, `a.legal`; a kubb drilled with `a.drill`'s `world.launchDrill` fields, lobbed
  when there is no `a.drill`; `a.drill` with only a circle, the autobench's case, is the
  plan's clean drill onto it). With `a.swing` and not instant the scene goes to mode
  `cpuswing` first: the Playdate's arm on the clock, back to `a.swing.back` over
  `cpuBackShare` of `cpuSwingTime` (0.6 s) and forward to `a.swing.releaseAngle`, then the
  throw, with its dots kept on the clock. `throw.showAim` shows its stance, and its circle
  when `a.plan` says where (`s.cpuTarget`); the clock shows `a.plan`'s targets.
- **The clock** (`hud.clock`, "Drawing speed") is always on in the throw scene: the scene's
  `s.dial` (reused) gets the swing's phase, arm and peak (the idle crank's arm), the plan's
  targets, the dead zone (`swing.tune.startBackDeg`) and overpowered past `overDeg` (150, 11
  o'clock), the last throw's peak and stop as dots (until the next wind-up), and the prompt:
  `WIND BACK` (idle, and winding short of the power target), `FLICK!` (inverted, inside
  it), `EASE OFF` (past it), `CRANK DOWN` (the crank parked behind 6 without arming: it must
  come down through 6 first), nothing during the flick; `WATCH` for the Playdate. In flight
  and at rest the hand stays where the crank stopped. `s.promptText` keeps the prompt for
  self-tests.
- **After a throw** `hud.verdicts(powerV, releaseV, steady, sideV)` (SHORT/ON/LONG,
  LOW/ON/HIGH, STEADY/SHAKY, and the nerves' PULLED LEFT/STRAIGHT/PULLED RIGHT, all
  `plan.launch`'s; "Nerves") shows from rest until the next wind-up, the player's
  throws only (`s.showVerdicts`; a new team's turn clears them). The result flag and the
  slow motion flag sit left of the clock. A drilled kubb's rest distance from the circle (`18 CM AWAY`,
  `s.restText`) is a flag in the plan chip's place (`hud.cutFlag`), at rest and on the next
  aim while no tilt or spin is planned. Decided 2026-11-15: the drill callout went (its
  SHORT/ON/LONG was the power band's, now the verdicts' first cell; its ruler and its 234 px
  plate overlapped the verdicts), and its distance moved to that flag. `hud.planChip` shows
  TILT or SPIN while it is not zero.
- **Readout** (the practice pitch's "Pitch: readout", debug only): `hud.readoutText(s.last)`,
  `back <peak>/<target centre> stop <stop>/<target centre> flick <deg/s> shake <0..1>`, then
  HELICOPTER, and the distance and kubbs down, or a drill's rest distance.
- **Telemetry**: the trace line's result is the swing's fields plus the plan and the launch
  (`writeTrace`, at rest; `core/trace`'s header): `level`, `projectile`, `drillId` (a drill
  run's), `tx`, `ty`, `px`, `py` (from the thrower's line), `plan` and `loft`, `powerLo`,
  `powerHi`, `releaseLo`, `releaseHi`, `planTilt` or `spin`, `launchSpeed`, `launchLoft`,
  `swivelOff` (degrees off the plan's swivel), `tumbleRate`, `tilt`, `legal`, `powerV`,
  `releaseV`, `steady`, the nerves' `sideDeg`, `lenShare`, `sideV`, `lenV`, `distance`, and a drill's `mode`, marker, landing, rest and
  thrower. `frames.jsonl` is unchanged.

## HOW TO PLAY

The rules of Kubb on six cards for someone who has never played (Jamie, 2026-11-15:
"short cards"), written the way a friend explains it on the lawn: plain words, real Kubb
talk, Rules V4.0 as the game plays them. `core/howtoplay.lua` (`tw.howtoplay`, pure,
`test_howtoplay.lua`) holds the cards (`CARDS`: `id`, `title`, `text` paragraphs and what
the little pitch shows: pieces, a throw's arrow, an advantage line) and the paging
(`press`: A and right on, B and left back; B on the first card leaves, A on the last goes
to HOW TO THROW, B on the last is done). `render/howtoplay.lua` draws a card in the
hand-off card's look (white on black, the title in display 32, or 16 when too wide, the
words in the label font wrapped to the column, the pitch from above on the right with
THEM at the top and YOU at the bottom, the page count bottom right) into one 400 x 240
image, and raises an error when the words run past `textBottom`: the `howto-play`
self-test draws every card. `scenes/howtoplay.lua` keeps each card's image once made.

1. THE PITCH: two teams, five kubbs on each baseline, the king in the middle; knock down
   all their kubbs, then the king. 2. BATONS: six a turn, underarm, end over end; a
   helicopter does not count; the 2-4-6 opening. 3. THROW THEM BACK IN: the kubbs you knock
   down come back into your half as field kubbs, stood up where they land; out once is
   thrown again, out twice and you pick the spot. 4. FIELD KUBBS FIRST: a base kubb hit too
   soon is stood back up; field kubbs left standing let the other team step up to the one
   nearest the middle. 5. THE KING LAST: from your baseline once all their kubbs are down;
   too early and you lose, or if a kubb thrown in knocks him over. 6. THE SCORE SHEET: every game
   in Planet Kubb Notation, under the title's System Menu "Games"; A: HOW TO THROW.

## HOW TO THROW

The walkthrough of the clock throw (Jamie, 2026-11-14, of the first one: "an interactive
thing that walks the player through the different steps and meaning of the crank for the
throw"; written again for the clock throw 2026-11-15). It runs over the practice pitch,
so every step is the real thing: the real crank and dial, the real circle, walk and plan,
and real throws at the far base kubbs (recorded like any practice throw). Pure part
`core/howto.lua` (`tw.howto`, `test_howto.lua`); panel `render/howto.lua`; glue in
`scenes/throw.lua` (`throw.showHowTo`, `throw.stopHowTo`, `throw.howtoFrame`).

- **Steps** (`howto.STEPS`, DESIGN 4's order): 1 the crank is your arm (turn it down to 6
  o'clock, not docked: within `howto.tune.bottomDeg`); 2 point and throw (any throw); 3 how
  far back is how far (a throw with the power ON, or `tries` throws); 4 where you stop is
  the arc (the release ON, or `tries`); 5 the d-pad moves the circle (`circleMove` m from
  where it was when the step began); 6 hold A to walk (`walkMove` m); 7 hold B to plan (the
  arc moved and a tilt or spin set); 8 that is the throw. Each step says what to do; once it
  is done it says what it meant (after a throw, that throw's verdicts first: `THAT ONE: ON
  HIGH STEADY`) and A goes on. A quick tap of B (let go within `throw.tune.howtoTap`, 0.3
  s, no d-pad while it was down) skips a step; the last step ends on A or a tap.
- **The panel** (`render.howto.tune`): a black band under the rail (y 14, 64 px: it ends
  above the far base kubbs of the first-person aim), the title in the display font and
  the footer (`TAP B: SKIP`, `A: NEXT`, `A: PLAY`) on its first row, up to three lines in
  the label font; only the title strip while B holds the camera out over the shoulder
  (the plan view's target half starts at y 24). Shown while aiming only (a throw in the
  air is the throw's). One image, redrawn only when `h.rev` changes.
- **The scene** sees the walkthrough's world once a frame (`s.howtoObs`, reused): the crank
  arm, docked, a throw come back to aiming (`s.throws` against `s.howtoThrows`) with its
  verdicts (`s.vPower`, `s.vRelease`, `s.vSteady`), the circle, the stance, the planned
  release, tilt and spin, A pressed and B's tap. `throw.showHowTo` turns a drilling pitch
  back to batons and starts the plan fresh.
- **Where it lives**: the last card of HOW TO PLAY, the drills menu's last item (below:
  A on that card opens the practice pitch with it on, main.lua `"howto"`), and the
  practice pitch's System Menu "Pitch: how to" (chosen while it runs, it ends it). The
  drills menu starts on HOW TO PLAY until HOW TO THROW has been seen: main.lua's `throw.howtoDone` writes the datastore "howto"
  as `{ seen = 2 }` when it ends (finished, skipped through or stopped; not in self-tests;
  0.2.0's walkthrough wrote `seen = true`, so a player who saw that one sees this one).
- Self-test `howto` (above): every step with scripted input fed as the step comes up (the
  throws on the plan's clean swing as it then is, ON ON STEADY), the plan step with B held
  and the camera out, A on the last step, then a second run skipped through with eight
  taps of B; it also checks every line fits the panel in the label font.

## The aim arc

Jamie and Tyler (2026-11-14): "the player should visually see the arc of the baton throw
... like a game of billiards on a computer". While a player aims a baton or a drilled kubb
(not the Playdate's throw), `throw.drawFrame` draws the plan's clean throw over the world
(`drawArc`, outside its caches, no tables): from where the player stands, at the plan's
loft and speed (`arcLaunch`, `s.sol`), onto the target circle (a drill's, 2026-11-15, down
to where the kubb lands short of its circle: `drill.solveAt`'s flight time `sol.T` and
landing `sol.land`, its centre at `drill.tune.landZ`; since 2026-11-16 that is short by the drill's mean run on,
`drill.slideFor`, so the arc ends where it lands and the circle is where it most likely
ends; the circle and the dotted line stay); drawn as the plain parabola from the hand to
that landing in the flight's time, which is within 2 to 4 cm of the flight with the air's
drag (`arcLaunch`); a baton's on a standing kubb or the king (since 2026-11-16) ends at
that piece's near face (`s.aimFace`, set by `replan`) at the plan's aim height
(`sol.aimZ`, "Aimed through the piece"), where the clean throw meets it; dashed (`arcPoints` 24,
every other gap drawn, the first `arcSkip` left out, `arcWidth` 2 px). It shows the plan,
not the throw: the backswing, the flick and where the crank stops still decide it (and the
wind will not show in it).

In first person the arc is nearly edge-on (a line up the middle of the screen through the
circle); the plan view below shows it as an arc. `arc = false` turns the arc off.

## The aim camera

Jamie (2026-11-15, after play-testing the over-the-shoulder crane): "when throwing a baton
we should return to the first person view ... when we hold down B to adjust loft we should
move the camera to that over the shoulder view to see the loft and when B is released come
back to the first person view. Do this for drilling as well", and "Having the camera zoom
out to see more of the pitch". The same for batons and drilled kubbs (`aimCamera` in
`scenes/throw.lua`; the math in `core/camera.lua`, tested in `test_camera.lua`):

- **First person** (the default, `camera.aim` into `s.aimCam`): DESIGN 3's crane straight
  behind the thrower (`camera.tune.aim.side` 0, `back` 3 m, `height` 3.4 m), looking along
  the swivel (the plan's: at the circle), the long lens of the framing rule (the farthest
  live target at least `minTargetPx` tall, `fMin`..`fMax`). It looks `circleBeyond` (1.5 m)
  past the target circle (`camera.lookDistAt`, between `lookMin` and `lookDist`), so the
  circle stays on screen wherever the d-pad puts it. A target close in front (an advantage
  line near the middle: at the long lens it fell under the screen, Codex on #96) is lifted by
  `camera.fitNear`: the circle's near edge stays above `fitBottom` (200), first by raising the
  principal row (to `fitCyMin`), then by widening the lens (to `fitFMin`). The Playdate's aims
  with no circle shown look as before (`lookDistFor` its targets, or `lookDist`).
- **The plan view** (B held, `camera.shoulder` into `s.shCam`, `camera.tune.shoulder`): a
  crane `side` (2.6 m) to the thrower's right, `back` (3.6 m) behind along the aim, `height`
  (3.4 m), turned to the middle of the target half (`lookY` 6 m out, x = 0). Its lens and
  principal point are solved in closed form (a lens shift: verticals stay vertical) so the
  target half (the far baseline `farX` either side, the centerline `nearX`, `pad` beyond,
  the far corners also at `cornerZ`), the planned arc and the circle fill the box
  `left`..`right`, `top`..`bottom` (12..388, 24..200): the longest lens that fits, within
  `fMin`..`fMax` (300..880; it comes out about 340 to 770, far base kubbs 4 to 9 px tall). The
  arc's first quarter (before `throw.tune.arcFitFrom`) is kept inside the sides only: it
  may rise in from the lower edge (`shoulderFit`, scratch arrays, no tables).
- **The swing** (`throw.update`): `s.camMix` goes from 0 (first person) to 1 (the plan
  view) while B is held and back when it is let go, over `shoulder.time` (0.4 s), eased
  (`camera.smooth`); `camera.blend` mixes the two (position, look point and principal point
  straight, the lens in log space). A tap of the arc re-fits the plan view, eased in with
  the time constant `shoulder.refit` (0.15 s; within half a pixel it takes the fit, so the
  camera stops: about 0.45 s), not a jump. The crank throws only with B up, so a throw
  normally starts in first person; one thrown before the swing back has finished starts
  from the camera as it is (the follow camera blends its principal point too). `fire` and
  `throw.prepare` put the mix back to 0. While the camera moves every aim frame redraws the
  world (the frame cache keys on the camera): `camera-swing` counts about 48 graphics calls
  an aim frame with the camera still and about 168 while it moves on batons (a flight frame's
  number), only during the 0.4 s swings and the refit after a tap (`drawcalls`' aim mean,
  no B held, is unchanged: 54.7 before, 54.8 after). With a drill's arc drawn too the
  `camera-swing` means are about 54 still and 173 moving.
- Self-tests: `aim-arc` (first person: the circle on screen and the far base kubb 12 px or
  more; the plan view: the circle on screen and the arc in its box, for targets across the
  half, every release, three stances; then the same for drill circles across the d-pad's
  area), `camera-swing` (first person, half way out, the plan
  view, a tap's re-fit, half way back, first person again, exactly the first frame's
  camera; then a drill's).

## Wind

Jamie and Tyler (2026-11-14): "optional in a game to turn on wind ... some indicator in the
game that would indicate where the wind is blowing, and wind would affect the baton throws
and kubb throws ... while they're in the air". The match options' WIND row (off, light,
strong; `opts.wind`, kept by the save, a resume and a rematch).

- **The air** (`core/wind`, pure, `test_wind.lua`): `wind.levels` light 2.5 and strong 6
  m/s. Each turn rolls a direction and a speed (`wind.turn`: the level's mean times
  `turnLow` to `turnHigh`); each throw is a gust of it (`wind.gust`: speed +-`gust`,
  direction +-`gustDeg`), so no two throws meet quite the same air. The match scene
  (`s.windLevel`, `s.windRng` from `opts.windSeed`, the seed or the clock) turns it into
  the thrower's view frame (`wind.vector`; Team B's is turned like the pitch) and hands it
  to the throw scene (`throw.setWind(s, wx, wy, text)`); practice has none.
- **The push** (`core/world`): `world.new{ windX, windY }`. The wind is the air the
  thrown piece's drag acts in ("Physics", the air's drag): `k |r| r` with `r` = wind - v,
  so a zero wind is still air. Over an 8 m baton at 30 degrees (aimed through still air):
  a light cross wind carries it 0.13 m, a strong one 0.35, a strong head wind costs 0.76 m
  and a tail wind adds 0.38; a lobbed kubb (more drag for its weight) 0.20, 0.55, 1.15 and
  0.62. (Before 2026-11-16 the wind pushed with its drag less a still-air drag the game did
  not have, baton k 0.015 and kubb 0.0086: 0.16, 0.44, 0.97, 0.54 for the baton.)
- **The indicator** (`hud.wind`): an arrow across the minimap's middle the way the wind
  blows in the thrower's view, longer the stronger, and `WIND n M/S` on a label above the
  minimap, while aiming and in flight. The aim arc does not show the wind: judging it is
  the player's.
- The Playdate's own throws do not allow for the wind yet. Self-test `match-wind` (a
  strong-wind match: the label, the speed, Team B's turn).

## Input provider

Scenes never read `playdate.buttonIsPressed`/`getCrankChange` directly; they read an input
provider (`source/input.lua`, `tw.input`): `p:advance()` once per frame, then
`p:held(name)`, `p:pressed(name)` (names `left right up down a b`), `p:crank()` (raw
degrees this frame, `getCrankChange` sign: negative = anti-clockwise), `p:crankPos()`
(`getCrankPosition`: 0 = up, 180 = the bottom of the turn), `p:docked()`,
`p:dt()`. `input.device()` wraps the hardware (dt measured, capped at 0.1 s);
`input.scripted(steps, dt)` plays a step list (`n`, `hold`, `press`, `crank`, `cranks`,
`docked`) at a fixed 1/50 s, with the crank starting at the bottom (or `startPos`).
The wind-up starts only when the crank crosses the bottom of the turn going back
(`swing.armAngle`, `swing.crossedBack`); the throw scene feeds the swing nothing before that.
`input.swingSteps(back, release, opts)` builds a scripted swing (self-tests, the
autobench): wound `back` degrees behind the bottom, a full flick that stops exactly
`release` degrees past it (`opts`: `frames`, `pause`, `peak`, `lead`, `shaky` for a
stuttered flick); the crank sign is applied for you.

## Tunables

Every number that is a guess lives in one table per module, with a comment:

- `tw.camera.tune` (`source/core/camera.lua`): aim crane (first person), lens range,
  framing rule, how far past the circle it looks (`circleBeyond`), the plan view
  (`shoulder`: crane, fit box, lens range, swing and refit times; "The aim camera"),
  impact camera, follow margins and mid-flight zoom; `tw.camera.minimap` for the minimap.
- `tw.swing.tune` (`source/core/swing.lua`): crank sign (`forwardSign`, the one constant
  to flip if forward feels backwards on hardware), the dead zone (`startBackDeg`), the
  backswing cap, the flick's start and stop speeds (`swingStartDps`, `releaseStopDps`,
  `speedWindow`), the sky ball (`skyDeg`), the cooldown, the flick's power
  (`fullFlickDps`, `minFlickFrac`), the pull and the shake (`roughFull`).
- `tw.plan.tune` (`source/core/throwplan.lua`): the power scale (`reachZeroDeg`, the
  anchors: 9 o'clock 4 m, 10 o'clock 8 m), the loft scale (5 o'clock 12 degrees, 3 o'clock
  32), the default arcs by target (`arc`), `arcStepDeg`, the release's range, `tiltStepDeg`
  and `tiltMaxDeg`, `spinSteps` and `spinPerStep`, the sky ball's extra, the helicopter
  limit, the shake's tilt and pull, overpower, STEADY, the baton's tumble (`tumbleTurns`,
  `armR`, `wristShare`, `tumbleMin`: "The baton's tumble"), the height a clean baton's
  centre goes through a standing piece (`aimHeightShare` 0.5: "Aimed through the piece");
  `tw.plan.levels` (beginner, club, pro: the targets' half widths, the error inside a
  target, the shake and overpower costs, the nerves and `tumbleSd`; `plan.LEVELS` in menu
  order).
- `tw.flight.tune` (`source/core/flight.lua`): gravity, hand height, loft range (5 to 55) and step,
  baton size, wobble. (`boostBelowDeg` and `flight.loftBoost`, the old player's low throw,
  were removed 2026-11-15, as were `swing.tune`'s launch and tumble ranges: the plan's
  scales set the speed, `plan.tumbleFor` the tumble.)
- `tw.scenes.throw.tune` (`source/scenes/throw.lua`): refresh rate, walk speed, how far
  back the player may step, the circle's snap radius (`snapRadius`, `throw.aimAt` only) and how near a live target
  a circle moved by hand must be to stay put (`keepNear`), where the clock shows
  overpowered (`overDeg`), the Playdate's arm on the clock (`cpuSwingTime`,
  `cpuBackShare`), rest hold, practice
  surface, the flight's pacing (`flightRate`, `framePeriod`, `tailPeriod`, `minBudget`;
  `physicsBudget` only for scripted input; see "Playback") and how far ahead the physics
  may record, impact-camera
  slew and baton framing radius, the tossed kubb's tumble (`tossTumble`), the instant
  rest hold, the drilled kubbs kept on the practice pitch (`drillKeep`), the target
  circle (`markerRadius`, `markerSegments`), the aim arc ("The aim arc") and HOW TO
  THROW's tap of B (`howtoTap`).
- `tw.howto.tune` (`source/core/howto.lua`) and `tw.render.howto.tune`: HOW TO THROW's
  pass thresholds (crank at the bottom, tries, how far the circle and the walk must move)
  and its panel ("HOW TO THROW"). `tw.render.howtoplay.tune`: HOW TO PLAY's card layout
  (title, rule, the words' column and bottom, the little pitch).
- `tw.drill.tune` (`source/core/drill.lua`): every drilling mapping (docs/notes/drills.md
  "Drilling").
- `tw.outcome.tune` (`source/core/outcome.lua`): when a body counts as standing, moved or
  turned, and how high a tossed kubb must rest to be on another.
- `tw.autothrow.tune` (`source/core/autothrow.lua`): the computer thrower's level, aim, basket,
  the spot beside the group (`spot*`), the baton's lane (`lane*`), a drill's steadier swing
  (`drillScale`) and the synthetic swing's mistakes. How far off a throw goes with its
  range is the shared nerves (`tw.plan.tune` "Nerves", `plan.levels` `nervesDeg`,
  `nervesLen`).
- `tw.world.tune` (`source/core/world.lua`): step, solver passes, slop and push, contact
  margin, bounce threshold and passes, wood-on-wood friction and bounce (`pairMu`, `pairE`:
  every pair of pieces), sleep and wake
  thresholds, topple angle, out margin, maximum throw time, stake height (0.15 m: a real stake, 6 inches out of the ground).
  `tw.world.surfaces`: one parameter set per ground (grass, sand, snow; ice is a marked
  placeholder): friction, bounce, dig, rolling resistance, and the ground's `texture`
  (Physics, "The ground's texture"). `world.SURFACES` lists the playable ones in order.
- `tw.collide.tune` (`source/core/collide.lua`): `batonRound`, how rounded a box's edges are
  to a baton ("Physics", "Baton hits"). `world.tune.batonTurnHold`: how the ground holds a
  baton's spin.
- `tw.bench` (`source/core/bench.lua`): the benchmark scenario (pieces, throw, seconds,
  and `bench.debris`, the lying batons and kubbs of a full turn).
- `tw.debris.tune` (`source/core/debris.lua`): `matchEps`, how close the engine's pose of a
  piece (a lying tossed kubb, a standing kubb, the king) must stay to the one recorded at
  rest for that exact pose to be used.
- `tw.match.tune` (`source/core/match.lua`): `settleDeg` and `settleGap`, how tilted (0.5
  degrees) or how far off the ground (2 mm) a carried standing piece must be for
  `match.settleStanding` to run it to rest.
- `tw.render.world.tune` and `tw.render.hud.tune`: shadow direction (also the light that
  shades the faces), the tones (`awayBelow`; a piece is never grey and keeps its look
  standing, falling or lying, with outline and detail sized by its length at its
  distance), outline and grain sizes, the ground (`lineWidth`, `dash`/`dashGap`,
  `advDash`, `roughPattern`, `rough`, `outsideFrom`, `roughFar`), stakes (`stakeHeight`,
  `stakeThick` at their true size, `stakeMinPx` the thinnest; no shadow), the baton's
  bands, the king's drawing (`kingCrown`, `kingCollar`, `kingCollarTop`, `kingRing`,
  `kingDiamond`, `kingDetailFrom`: drawing only, the physics king stays a plain box; the
  `king` scenario shows it), the kubb set (`set`, `setFrom`, `setDetailFrom`; the
  sets themselves are `render.world.sets`, see "Kubb sets"), HUD fonts (`labelFont`, `displayFont`) and every HUD box
  (`rail`, `prompt`, `clock`, `verdicts`, `planChip`, `cutFlag`, `flag`, `slow`, ...), and `cache` in each (the
  image caches of "Drawing speed"; `false` draws everything from scratch every frame, with
  the same pixels), and `layer` in `render.world.tune` (the background layer of "Drawing
  speed").
- `tw.render.burst.tune` (`source/render/burst.lua`): the hit bursts' phase lengths, the
  double's second star, the anchor lift, the chips; `tw.burstpick.tune` the double's window and the fall judged at the impact (`fallV`, `fallW`, `judgeFor`, `grazeFor`);
  `tw.sound.tune` (`source/sound.lua`) the knocks' volume and rate spread and the king's
  chord ("Knocks"); `throw.tune.knockLate`.
- `tw.playback.paceTune`, `tw.playback.calm`, `tw.playback.slow` (`source/core/playback.lua`):
  the pace of the picture, the calm tail and the slow motion ("Playback", "Slow motion").
- `tw.scenes.title.tune`, `tw.render.cards.tune`, `tw.render.ui.tune`: where the title's
  menu, the cards' lines, pips and pitch map, and the ringed buttons sit (screen pixels
  from the design boards), and the system paths tried for the label font.
- `tw.raising.tune` (`source/core/raising.lua`): the search that slides an obstructed
  footprint clear, and the punishment candidate grid. Stake radius and other piece sizes are
  in `tw.pitch`.

## Playback

What a throw looks like on the device is set by three costs per frame: the physics (on
the device a step with nothing in contact costs about 1.9 ms, a step with kubbs in contact
about 29, and the three match-case throws averaged 4.6 to 7.2 ms a step; real time needs 4.8
steps per 20 ms), the draw (about 18 ms in flight, 11 after the hit) and the rest of the
update (device run of 2026-11-13). The device cannot compute a
throw in real time, so the picture always plays slower than real time; the goal is that it
does so steadily. `source/scenes/throw.lua` and `source/core/playback.lua`:

- In flight the display is unlocked (`flightRate` 0) and every frame takes `framePeriod`
  (0.040 s): the physics gets what is left after the update's own work, the draw and the
  display (each measured from the frames before, `drawEst` and `postEst`), at least
  `minBudget`. The estimates rise by `estRise` (a quarter) of a step up and fall by a
  quarter of a step down; jumping straight to the slowest frame left the physics 1.7 ms a
  frame short of what the draw really took (0.38 against 0.45 of real time). Locked at 50 Hz, a frame that ran past 20 ms waited for the next 20 ms tick,
  so frames came at 40 or 60 ms by chance.
- `playback.advance` stops before a step that would run more than half a step past its
  budget (judged by the last step's time), not after.
- The pace (`playback.pace`, `paceTune`): the picture plays at real time while 0.4 s
  (`horizon`) or more is computed ahead of it, slower in proportion below that (never under
  `floor`), changing by at most `rise` per second up and `fall` down. So the picture slows
  smoothly to the rate the physics makes frames, instead of running to the end of what is
  computed and stopping. `playback.speed` (the slow motion) is applied on top: the slower of
  the two wins.
- The calm tail (`playback.calm`): once every awake body moves slower than 0.05 m/s and
  0.5 rad/s, nothing visibly moves and the throw only waits for the sleep timer. The scene
  holds the picture and the camera's aim there, gives the physics `tailPeriod` per frame,
  and when the world is at rest it jumps to the end. Starved frames in the tail are not
  counted.
- Self-tests and the desktop use scripted input, which has no device clock: they get
  `physicsBudget` per frame, as before.
