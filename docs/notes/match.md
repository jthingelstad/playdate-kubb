# Match and kubb sets

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

## Match

The title (`scenes/title.lua`, Woodcut look below) offers "VS PLAYDATE" (a match against
the computer), "PASS + PLAY" (the match) and "PRACTICE" (the drills menu, whose OPEN PITCH
is the practice pitch); `main.lua` opens one
scene at a time and rebuilds the System Menu for it (the scene's own item; until engine
0.13 a "Level" item came first; crank traces moved behind the `debug` file on 2026-11-20). Practice is the throw scene exactly as before.

- `core/frame.lua`: the thrower's view frame. Team B's throws are made in the pitch turned
  180 degrees about its center, `(x, y) -> (-x, 8 - y)`, angles + pi, quaternions
  `(0,0,0,1) * q`; the turn is its own inverse. So the throw scene, cameras, flight, HUD
  and physics always throw from y = 0 toward +y, and Team B sees its own baseline at the
  bottom of the screen.
- `core/outcome.lua`: physics to rules. `outcome.pieces(g, side)` gives the engine's pitch
  as `core/world` pieces in the view frame (with `role`, `half` and the world `pose`);
  `outcome.baton(res, pieces, side, illegal)` and `outcome.toss(res, pieces, side, id)`
  turn a `world.result` into the outcome records above (rest poses back in the world frame:
  standing when the long axis is within 45 degrees of vertical; `onTop` when a tossed kubb
  rests clearly above the ground, the nearest piece under it).
- `core/match.lua`: one plain table `m` (the engine game, start time, mode, per-turn toss
  count) that a resume can save. `match.setup(m)` raises lying kubbs and places punishment
  kubbs with the engine's policies, then returns the next throw in the view frame (kind,
  projectile, pieces, `forwardY` = how far forward the thrower may walk, `advY`, `targets`,
  `label` such as "Team B  baton 2 of 6", `thrower` = `{ id, name }` of the player who
  throws it, from `core/order`); `match.resolve(m, res, illegal)` applies a
  finished throw (as that player) and sets `m.text` (the result line); `match.resign` (the
  next thrower's `G`), `match.file`. `m.order` is the throwing order; the save keeps it.
- `scenes/match.lua`: phases handoff (the full-screen hand-off card before each team's turn,
  A to play), settle (below), play (the throw scene set up by `throw.prepare`: pieces, lines, projectile,
  targets; `s.auto = false` stops it in mode `done` after the rest hold) and over (the
  winner card; the game file was written to `games/` in the Data folder, DESIGN 7; A is a
  rematch, B the title). The
  engine rules on a throw as soon as it is at rest, so the result line shows during the
  rest hold; then the next throw is set up from the engine's state plus the turn's debris
  (below): standing pieces are where the engine says (kubbs pushed out are put back, raised
  and punishment kubbs appear).
- Out kubbs stay on the pitch (Jamie, 2026-11-13): the engine keeps every kubb thrown this
  round as one of its pieces wherever it lies (Rules engine, "Judged at the final
  position"), so `outcome.pieces` has them and later kubbs hit them. They leave the pitch
  when the round is judged (picked up for a rethrow, or a punishment kubb). After a toss
  that is not the last of its round `m.text` says where the kubb lies now (`kubb in for
  now`, `kubb out for now`, `own half hit: kubb out`); after the last one it says the
  judgment (`kubb in`/`all in`, `kubb out: rethrown`/`2 out: rethrown`, `out twice:
  punishment kubb`, `on a kubb: lowered`, rescues). The label's `of` is the throws made plus
  those left in the round, so it grows when a judgment adds rethrows.
- Debris (`core/debris.lua`, carried by `core/match`): within a turn every thrown baton
  lies where it came to rest and every kubb it toppled that the engine took off the pitch
  lies where it fell. `match.setup` gives them as `s.debris` (core/world pieces in the view
  frame, full pose and z, `toppled`, asleep) and a per-turn baton body id `s.batonId`
  (`baton1` ..); `match.worldPieces(s)` is pieces then debris, the bodies a throw's world
  starts with. `match.resolve` (`match.carryDebris`) moves the debris to where the throw
  left it, adds the new baton and newly downed kubbs; a throw the engine puts back (`Z`)
  leaves the earlier debris as it was and only adds its baton. The debris is kept in the
  world frame and turned for Team B. A debris kubb is down in the world (`wasToppled`), so
  hitting it again tops nothing up; a standing kubb it is pushed into counts for this throw
  as a direct hit would. The hand-off (a new turn), the end of the game and a resign clear
  it. During the inkast the engine keeps the tossed kubbs on the pitch lying (in or out); debris
  also carries their exact rest pose (tilt, height) while the engine's pose is the one they
  came to rest at, so they are shown and simulated as they landed until raised or picked up.
  A kubb lowered at the judgment no longer matches and is shown flat; one whose support was
  picked up keeps its spot but drops its exact pose (it would float).
  Standing pieces (2026-11-16, physics audit item 4): every kubb the engine has standing and
  the king also keep their exact rest pose (tilt, height, which end is down), so a kubb a
  throw left tilted is met tilted by the next throw instead of being stood up straight.
  These outlast the turn (the pieces stay on the pitch; `debris.begin` keeps only them). A
  standing kubb at rest tilted less than its tipping point leans back unless something holds
  it: in 80 physics matches before this change (`tools/physmatch`'s path, 40 each on seeds 2
  and 3) throws moved 1,539 standing pieces without toppling them and 1,528 came to rest
  within 1 degree of upright; the 11 that did not (1.6 to 23.6 degrees) each had a lying
  baton or a downed kubb within 25 cm holding them, debris that is picked up at the end of
  the turn. With the change 13 throws in those 80 matches met a tilted kubb. So when what may have propped one has gone
  (a new turn, the inkast's kubbs raised, a judgment that lifted kubbs or picked any up for a rethrow, a rescue or a punishment: `d.settle`),
  `match.setup` calls `match.settleStanding`: the world runs every carried piece tilted over
  `settleDeg` or raised over `settleGap` to rest once, from the pitch as it is now, and the
  engine's pose follows where it settled. One that topples or leaves the pitch while settling
  was knocked by clearing the pitch and is stood back up where the engine has it (no exact
  pose). A kubb leaning on a neighbour by its own weight is past its tipping point, and the
  leaner rule already has it down; a standing pose past the tipping point (the inkast's
  45-degree rule, `outcome.tune.standingCos`, can call one standing) is not carried, and is
  stood up straight as before. Cost: the check is a few multiplies per standing piece; a
  settle that runs is about 170 steps with one body awake (1.8 to 2.6 ms on the desktop,
  roughly a second on the device), once per turn that left a tilted piece (1 run in 80
  matches). In the scene the
  debris items follow the engine's pieces; a lying baton is a `baton` item of `render/world`
  (drawn like the flying baton from its cached pose, nothing prepared); the minimap draws
  debris as 1 px dots like other toppled pieces. Cost: `make bench` runs its throw again with
  six lying batons and ten downed kubbs asleep (about +16% per step on the desktop over the
  whole run, +9% in the collision phase; all of it in the pair loop's sphere checks between
  awake bodies and the sleeping debris); a sleeping body costs nothing else until woken.
- Raising and punishment kubbs by hand (`scenes/settle.lua`, boards `Raising.png` and
  `Punish.png`, which were sketches): when the engine's next need is a raise or a
  punishment kubb, the match's phase is `settle` and the defending team does it, its name
  on the rail. In PASS + PLAY a card comes first (Jamie, 2026-11-14; `core/cards.settle`,
  `render/cards.settle`, `s.settleCard`): PASS THE PLAYDATE TO the defender, how many
  kubbs it raises and punishment kubbs it places, THEN HAND IT BACK TO the attacker, A to
  start; none against the Playdate, whose player holds it already, and none after. Raise: since 1.1.0 (Kubb Engine 1.4, "Raising in any order")
  one held 3D view of the whole group of lying kubbs (`render/world` with its own camera,
  `camera.fromEnd(nil, pts, settle.tune.raiseBox, kind)`, in the viewer's frame: kind
  `"raise"` when the viewer is the raiser, `"end"` when the Playdate raises and the player
  watches from their end). It frames the lying kubbs and their ends' footprints only, padded
  to at least `groupMinWidth` (3.6 m) wide; framing the whole half with the baselines and
  the king, as the session's raise camera does, left a kubb about 8 px high on the 400 x 240
  screen. The camera is held for the whole raise and moves only when the raising side
  changes. Each end the engine allows is drawn on the ground as its 7 x 7 footprint, the
  chosen one dotted with STANDS HERE (MOVED CLEAR when II.D.5 slid it), and a small
  triangle over the chosen kubb marks it when more than one is lying. **B NEXT** steps to
  the next lying kubb in the order `need().lying` gave at the start of the raise (any order:
  the rules engine takes `g:raise(choice, nil, id)` for any lying kubb); **left/right** pick
  the end on that side of the screen (an end the engine does not allow stays unpicked and
  its flag says why, THAT END IS OUT, THAT END IS BLOCKED; the plaque `lr END` shows only
  when both ends are open); **A** raises the chosen end. The crank (Jamie, 2026-11-13) tips
  the kubb as before: forward onto its right-hand end on screen, backward onto its left,
  `crankPerRaise` (270) degrees from lying to standing (`raising.tipPose`, pure and
  tested), and all the way up raises it on that end. The end offered first is the engine's
  own choice (`g:raiseOptions(id)`, `raising.choose` under the defender's policy). The rail
  counts the raises of this side's raise. Until 1.1.0 the view was one kubb at a time in
  the engine's order, behind and above it, the d-pad turning and zooming the view
  (`lookTurn`, `lookZoom`, `zoomMin`, `zoomMax`, `raiseNear` and the other raise-camera
  tunes are gone with it). Punish: the
  defender's half from above (40 px a metre), grey keep-out circles a baton length from
  the stakes and the king, the kubbs on it, and a cursor kubb the d-pad moves (faster the
  longer it is held); `raising.punishmentCheck` runs as it moves, a refused spot shows why
  (TOO NEAR A STAKE, TOO NEAR THE KING, ON A KUBB) and A there does nothing; A elsewhere
  places it (`g:placePunishment`). The cursor starts at `raising.autoPunishment`'s spot. The
  still parts are one image redrawn only on a change. Scripted matches (`seed`,
  `instant`, or `autoSettle` in the scene's options) leave both to the engine
  (`match.setup`). Self-tests `settle` and `settle-crank`.
- Auto raise (Jamie's Settings sheet, 2026-11-20: "yes this should be on all platofrms."):
  since 1.1.0 the System Menu's checkmark **Auto raise** (`main.lua`, shown in a match whose
  raising is by hand; `match.setAutoRaise`), in place of the raise view's B REST OF GAME
  plaque (B is NEXT now). Ticked, it hands every raise to the game for the rest of the
  match: both teams' raises, this turn's and every later one's, as the web's MENU, Raising
  does (one setting for the match on the device, not one per team); the kubb on screen is
  raised on the engine's own end. The menu's tick follows the match when the menu opens
  (`playdate.gameWillPause`). Each automatic raise
  shows its kubb, tipping toward the engine's end over the last `settle.tune.autoTip`
  (0.4 s) of `settle.tune.autoWait` (0.7 s, the web's wait), with **B BY HAND** and
  RAISING FOR THE REST OF THE GAME, then makes the call A makes on the engine's end
  (`g:raise(choice, policy, id)` with `raising.choose` under
  the defender's policy: `settle.new`'s `policyFor`, which `scenes/match` gives as
  `cmatch.raisePolicy(m, side)`, else `g.raisePolicy`), so the pitch, the score sheet and
  the game file are exactly a match raised by hand without the crank on the engine's ends
  (self-test `auto-raise` checks it against a copy raised with `cmatch.raisePolicy`).
  The end the raise view offers first is that same choice. B BY HAND (or unticking Auto raise) gives the raising
  back, starting with the kubb on screen. Punishment kubbs are still placed by hand (the
  web's does the same); the match option RAISING: AUTOMATIC (`autoSettle`) still leaves
  both to the engine with no view. In PASS + PLAY the pass card waits while the game is
  raising: it comes before the first thing the defender does by hand (a punishment kubb,
  or the rest of the raises after BY HAND), so a turn with only raises never changes hands.
  Until that card the attacker holds the Playdate, so Match: resign then is the attacker's
  (`scene.holder`: in the settle phase the defender's only once its card has been shown;
  a match resumed into an automatic raise has had no card either); the rail goes on naming
  the team whose kubbs are raised.
  Against the Playdate the Playdate raises its own; since 1.1.0 the player watches it
  (below, "VS PLAYDATE: the player's end, SPEED and SKIP"). **Raising by side** (Kubb
  Engine 0.12, `core/match.raisePolicy`): the engine raises the Playdate's kubbs by its
  level (pro `par`, club `apart`, beginner `first`) and a person's by its advice
  (`cpu.advice`, `par`: the end that leaves the fewest kubbs one behind another on a
  baton's path), and the raise view offers that end first. `scenes/match` says which
  sides the computer plays outright, `cpu = { "B" }` against the Playdate and `cpu = {}`
  in PASS + PLAY, to `match.new` and again on a resume (`m.cpu`, not saved); without it
  PASS + PLAY would raise a person's kubbs `apart`. Saved: since engine 0.9 the
  choice is in the save itself (core/save's `autoRaise`, true or absent), written at once
  when Auto raise is ticked (B REST OF GAME before 1.1.0) and when BY HAND or unticking turns it off, and passed back to the match on a
  resume (`opts.autoRaise`). Builds before 0.10.0 kept it in a datastore file beside the
  match, `<save key>-raise` ("match-raise"; "selftest-match-raise" in self-tests),
  `{ start = the match's start, raise = "auto" }`. A match resumed from such a build reads
  that file once (`oldRaiseFile`): it raises for itself when the file names its start (a
  file left from an abandoned match does nothing), and the file is deleted right after the
  next save, which carries the choice, so it is never in neither place. A rematch starts
  by hand.
- Names (`scenes/names.lua`, board `Names.png`; pure rules in `core/names.lua`, tested; as
  built before saved players: since 2026-11-15 TEAMS comes in its place and the Names
  screen names one player or team, generated or typed, docs/notes/saved-players.md):
  PASS + PLAY asks for both teams' names, VS PLAYDATE for the player's, on the board's
  black panel beside the Playdate's system keyboard (`playdate.keyboard`): whose name it
  is, the name as typed (cap 32, cap 16 when wider than `bigMax`), UP TO 10 LETTERS, the
  game file id, and what comes next. A name keeps letters, spaces, hyphens and
  apostrophes, ten at most, and needs a letter; OK takes it, the keyboard's cancel goes
  back a step (from the first, to the title). The last names are saved
  (`playdate.datastore` "names") and offered again. The match gets them as
  `opts.names`, the engine's teams (one player each, named as the team), so cards,
  labels and the game file use them. `main.lua`: title -> `names` -> `options` -> `play`; the winner
  card's A is `rematch`, the same options again with no names screen. Self-test `names`
  (scripted, no keyboard: `names.type`, `ok`, `back`).
- Match options (Jamie, 2026-11-14: "the game options for the match you are starting";
  `scenes/options.lua`, pure rows in `core/matchopts.lua`, tested): after TEAMS, before
  every match (PASS + PLAY and VS PLAYDATE). Four rows: SURFACE (grass, sand, snow),
  OPENING (2-4-6, or six from the start), RAISING (by hand, or automatic: the engine's
  policies, `autoSettle`; against the Playdate "by hand" is the player's side only, as
  before), WIND (off, light, strong; "Wind"), since 1.1.0 THROW TO GO (on or off, below "Throw to
  go"; the Playdate's own row, last in PASS + PLAY, before COMPUTER against the Playdate;
  six rows are drawn 26 px apart) and, against the Playdate only, COMPUTER
  (kid, beginner, club, pro; club by default; KID makes a Kid match, below): the Playdate's throw level, a match option since
  engine 0.9 (Jamie, 2026-11-20: "yes this should be a real per game setting"). The level
  goes on the Playdate's player in the lineup (`cpuLevel` in `scenes/match`), so its throws
  (`throw.levelFor`), its raising (engine 0.12), the game file's [Throw Levels] and a
  resume carry it. A person's level no longer changes their throw (engine 0.13: every
  person throws on the one meter, docs/notes/throw.md "The person's meter"); it is still
  their roster entry's and the game file still names it. A match saved before 0.10.0 has
  no level on the Playdate's player and goes on at the level the old System Menu "Level"
  kept in the datastore (the item is gone since 0.13), as it did. The core has no SET row since 0.9 ("Kubb sets"). Up/down choose a row, left/right change it (the chosen row black, with arrows),
  a line under the rows says what the row is for; A starts, B goes back to TEAMS. The
  choice is kept (`playdate.datastore` "matchopts", `matchopts.valid` on reading) and
  offered next time. `main.lua`: title -> `teams` -> `options` -> `play`; a rematch keeps
  the options; a resumed match keeps its raising (the save's `opts.autoSettle`; surface and
  opening are the engine's own). Self-test `options`.
- Saved games and resume (`core/save.lua`, pure and tested): as soon as each throw is
  ruled on (at rest, so leaving for the title during the rest hold cannot give the throw
  back), before every settle step and after every raise and punishment kubb placed by hand
  the match scene saves the match in progress (`scene.persist` to `playdate.datastore` "match"); a finished match
  deletes it; leaving for the title keeps it. Scripted matches (`seed`, `instant`,
  `noSave`) never save, and self-test runs (`tw.selftestRun`) save under their own key
  (`scene.saveKey()`, "selftest-match"), so they never touch a player's saved match.
  `save.write(m, opts, writer)` hands the writer the live engine game, sheet, debris and
  clock (no copy: copying cost 43 ms on the device at turn 4; the datastore write itself
  is 68 ms, at the frame that already sets the next throw up); the sheet's `current` turn,
  the one table reached two ways, is detached for the write and kept as `currentIndex`.
  `save.pack` is the same as a checked plain copy for the tests (`save.plain` refuses
  shared tables, functions and mixed tables); `save.unpack` puts the `rules.Game` and
  `notation.Sheet` metatables back.
  `tests/lua/test_save.lua` plays 40 seeded games saved and restored every 7th action
  and needs the same game file as straight through. With a save, the title shows `B
  RESUME <A> V <B>, TURN n` beside A START (`RESUME TURN n` when the teams' names would
  run into it, `title.resumeText`); without one, while HOW TO THROW has not been seen, the
  same place says `NEW? PRACTICE > HOW TO PLAY` (`title.new`'s hint) (a save that does not read back is ignored,
  never a crash at launch); `main.lua` opens `resume` from it (the match
  scene's `opts.resume`, its names and VS kept for a rematch). Self-test `resume`.
  A new engine does not refuse a saved match: the save holds the engine's state, not its
  throws, and the Playdate keeps no replay or hashes to check, so a match saved on an
  older engine resumes and plays on under the new one (only a save `version` other than
  2 is refused, `save.unpack`). Engine 0.9 to 0.13 (2026-11-21) changed nothing in
  `core/save` or `core/matchopts`: matches saved by 0.10.0 on 0.9 (VS PLAYDATE at pro,
  PASS + PLAY with RAISING: AUTOMATIC and with REST OF GAME on) and a save left by a build
  before 0.9 (with `set`, no computer level) resumed on 0.13 headless, played
  to a winner with physics and wrote game files the notation gate passes; a kept
  "matchopts" with `set` still validates. A resume sets the computer's sides again
  (`m.cpu`) before its first settle.
- **VS PLAYDATE: the player's end, SPEED and SKIP** (game 1.1.0, Kubb Engine 1.4). Against the
  Playdate the screen stays on the player's side for the whole match. The Playdate's
  inkast and throws are set up in the thrower's frame as always, then shown from the
  player's end: `throw.endCamera` (`camera.fromEnd(c, pts, endBox, "end")`) and the world,
  HUD, wind and minimap turned (`render.world.setTurned`; the minimap's cache key carries
  the flag), so its batons come toward the camera. Its raises open a settle in watch mode
  (`opts.watch`, `opts.view` = the player's side): the held raise view from the player's
  end, each kubb tipping to the engine's end as in Auto raise, no plaques but the watch
  bar. PASS + PLAY is unchanged: the pitch turns at the hand-off and every throw is made
  from the bottom of the screen.
  During the Playdate's turn (its throws, its inkast and its raises) a plaque at the foot
  of the screen (`render/watchbar`) says **B SPEED 1X** and **A SKIP**. B steps the speed
  1X -> 2X -> 4X -> 1X: the think time, the flight and the rest hold run on `dt * speed`
  (the physics is computed ahead, so the throws are the same at any speed). The speed is
  kept on the device (`playdate.datastore` "watch", `{ speed = 1|2|4 }`; not in self-test
  runs) and shown on the plaque. A skips the rest of the Playdate's turn: a SKIPPING card
  ("same throws, no waiting") is drawn while its throws are made instantly
  (`ts.instant`, the same plan and the same physics) and its remaining raises are made at
  once with `g:raise(nil, policy)`; skipping ends when a person's throw is set up. Skip
  gives the same match: self-test `watch-skip` plays one seed watched (SPEED stepped to
  4X) and one skipped and needs the same game file (bar the clock tags).
- **Throw to go** (game 1.1.0, Kubb Engine 1.4 `core/togo`; DESIGN Q1). The match option
  THROW TO GO (ON by default, kept in `playdate.datastore` "togo", `{ on = bool }`; not
  offered in a Kid match) decides who throws first with one baton a side at the king
  before turn 1. It runs when the option is on, the match is not a Kid match, nothing has
  been thrown and a person throws first on some side (`togoWanted` in `scenes/match`).
  The steps are CLIENTS.md's five: each side's set-up from `match.togoSetup(m, side)`
  thrown with the usual throw scene (a person's circle starts at
  `king.y - togo.tune.markerShort`, the arc at `togo.arc()`, no wind: `throw.setTogo`), the
  Playdate's baton from `togo.cpuThrow(setup, rng, level)`, each on its own world,
  measured with `togo.gap(res, setup.batonId)`, the verdict from `togo.decide`, then
  `match.setFirst(m, first, togo.text(...))`, which the game file writes as
  `[Engine:first]` (the notation gate passes it). Order: the person first, then the
  Playdate (A then B in PASS + PLAY). A card comes before each person's baton: THROW TO
  GO (with PASS THE PLAYDATE TO in PASS + PLAY for the second baton and every baton of a
  later round), the thrower's name, what to do. A flag after each baton says how far it
  lies from the king (`0.42 M`) or KING DOWN. The verdict card says e.g. TEAM B THROWS
  FIRST (YOU THROW FIRST for the player), 0.42 M AGAINST 0.88 M, or TEAM A FELLED THE
  KING; TIE: THROW AGAIN and BOTH KINGS DOWN: THROW AGAIN start round 2 (A throw again).
  The Playdate's baton shows from the player's end with the watch bar; SKIP makes it at
  once. A Match: resign during it is queued until the throw at hand is done.
  The save: a match saved during the throw to go keeps the engine game as it was before
  it (turn 1, no first thrower set) and the top-level flag `togo = true`; a resume throws
  it again from round 1 (`opts.togoPending`). A save with the option off has
  `togoOff = true`, so a resumed match does not start one. `core/save` ignores both
  fields, and a save from 1.0.0 (neither field, past turn 1, or before the first throw)
  resumes as before: past turn 1 nothing changes; at the start of turn 1 it plays the
  coin-flip order it had. Self-test `togo`.
- **The seat** (Kubb Engine 1.0, kubb-engine docs/notes/physics.md "The seat"): the
  throw's world leans a kubb standing plumb (its pose a turn about the vertical alone, as
  `outcome.pieces` gives every kubb the engine has standing) up to its surface's `seat`
  (grass 2 degrees, sand 3, snow 1.5, the grid 0) when it is built (`world.addPiece`, by
  `world.seat`). The Playdate builds its pictures from its own items, so the throw scene
  puts every plumb kubb in its seat as it sets the items (`throw.standUp` for practice,
  `setItem` for a match's pieces and debris: `world.seat` with the same view-frame point
  and the scene's surface, and the height a box rests at), and the world built from those
  items then takes them as given. Without it a kubb raised, placed or newly stood was drawn
  plumb and stepped by up to its seat at the throw's first frame; headless on 1.0 with the
  scene's rule (two matches each on grass, sand and snow, 836 throws) the drawn and the
  built pose of every standing kubb at a throw's start are the same (0.00000 degrees; 441
  of 5341 were drawn seated from plumb), and the pose drawn at a throw's start against the
  last throw's rest for a kubb that did not move differs by at most 0.18 degrees (snow; a
  millimetre). The other side's view is the same lean (the seed is side A's point, the
  direction turned with the frame). The raise close-up (`scenes/settle`) draws the standing
  neighbours in their seats the same way (a kubb stands about 50 px tall there, so its seat
  is 1 to 3 px at the top; in the aim view a base kubb 8 m away is 12 px, under a pixel). The
  raised kubb itself is never drawn plumb: the crank's last step to standing raises it and
  the view moves on in the same update, so the next picture of it is the throw scene's,
  already seated. Practice: a kubb keeps the seat it was stood up with when the pitch's
  surface changes (System Menu "Pitch"), until RESET or a fall stands it again; the world
  takes it as given, so nothing steps.
  A match saved on 0.14.0 (core 0.18) and resumed: the save holds the engine's poses (x,
  y, standing, angle) and the debris's exact rest poses, and on 0.18 an untouched kubb's
  rest pose is exactly plumb, so on 1.0 every standing kubb that has not moved takes its
  seat at the first throw after the resume (drawn so from the first frame); one that a
  throw moved keeps its kept pose. That is what a match begun on 1.0 does with the same
  kubbs. Nothing else of a save is read differently: no format changed (kubb-engine
  docs/VERSIONING.md 1.0.0), `core/save`, `core/roster`, `core/history`, `core/names` and
  `core/gamefile` are byte for byte 0.18's, so the names, teams, throw levels, saved
  players and their histories and the game files read as before (checked headless: a
  grass and a sand match saved at turn 4 on 0.18, unpacked on 1.0, names kept, 8 of 8
  standing kubbs seated).
- Games list (`scenes/games.lua`, board `Games.png`; `core/gamefile.lua` pure and tested
  over every fixture): the title's System Menu "Games" opens it. Every finished game in
  `games/`, newest first (file names start with the date): the date, the teams with a
  crown on the winner, turns and minutes; the chosen row is black; the footer gives its
  baton hit rates and the baton the king fell to. Crank (`crankRow` degrees a row) or
  up/down moves; A shows the score sheet (the game file as written, scrolled by the crank
  or up/down; B back; the same viewer as the match's, `scenes/sheet`); B goes to the title. Files are read and parsed only as their rows
  come on screen; each screen is one image redrawn only on a change. Self-test `games`.
- VS PLAYDATE (`scenes/match` with `opts.vs = "B"`; `main.lua` opens it as `"vs"`, and a
  rematch keeps it): the player is Team A (its lineup from TEAMS), the
  Playdate Team B "Playdate" (the
  engine's team names, so cards, labels and the game file say so; mode "Vs Playdate").
  Its throws come from `core/autothrow` (`choose(setup, rng, scale)`, scatter times
  `scene.tune.cpuScatter`, seeded from the clock): it chooses as its turn comes up, the
  scene shows that stance and aim (`throw.showAim`, `s.watching`: a WATCH prompt over the
  clock, its circle where its plan says, the clock with its plan's targets) for
  `cpuThink` s, then `throw.autoLaunch`: its arm plays on the clock (back, then forward
  to where it stops, `cpuSwingTime`) and the throw leaves as it made it, mistakes
  included; its kubbs are drilled ("The throw"). It raises
  and places punishment kubbs with the engine's policies (no settle screen); the player
  settles by hand. No hand-off card before the Playdate's turn. The System Menu resign is
  always the player's and waits for the player's turn. It throws at the match option
  COMPUTER, on its lineup entry (see "Match options"). Its batons leave the hand of their
  own plan (`fire` with `a.plan`'s `handZ`, `handFwd`, `handTip`), not through
  `autothrow.launch`, so the 0.9 note about that call's hand changes nothing here. Self-test
  `match-vs` (a whole match at COMPUTER pro with the System Menu on beginner, the player's
  throws seeded, its game file gated and naming the computer pro).
- Kubb toss: a drilled kubb, always from the baseline ("Drilling"); a kubb with no
  `a.drill` from the computer is lobbed (`world.launchKubb`, end over end, no tilt), drawn
  as one more box item.
- Stay put (Jamie, 2026-11-14): in `throw.prepare` a team's batons after its first of a
  turn keep a stance the player walked to with A (`s.stanceSet`, `s.stanceSide`,
  `s.stanceKind`), clamped to where this baton may stand (a king shot pulls it back to
  the baseline), and the circle stays on its target while that stands. Otherwise, and
  for every kubb, the stance is behind the circle, which starts on the nearest live target.
  Self-test `match-opening` checks both.
- Advantage line: A + d-pad walks between `backMax` behind the baseline and `forwardY` (the
  engine's advantage line; king shots are from the baseline). A baton's stance starts
  on the line (Jamie, 2026-11-14: from there you are far more accurate, so the camera comes
  up with you, not held back at the baseline). While aiming, yours or the Playdate's, an
  inverted flag under the rail says `ADVANTAGE LINE  2.4 M` (`hud.advantage`, its text made
  once a throw, `s.advText`). The line is drawn on the pitch (2 px, dashed 2 on 2 off; the
  centerline is 6 on 4 off) and on the minimap. Self-test `match-whole` checks the start
  and the flag.
- **A Kid match** (Kubb Engine 0.15; kubb-engine docs/notes/kid-mode.md): the options' COMPUTER
  row offers KID first (`core/matchopts`), which sets `opts.rules = "kid"`; `scenes/options`
  drops it in PASS + PLAY (no COMPUTER row there), `scenes/match` passes it to `match.new`
  as `rules`, and the game keeps it (`g.rules`), so a resume and a rematch play Kid too.
  The engine does the rules: three base kubbs a side (x = -1, 0, 1), every kubb and every
  baton at a kubb thrown from the Kid line 2 m in front of the thrower's baseline (or the
  advantage line when that is nearer the middle; the king from the baseline), an early
  king stood back up, no punishment kubbs (a kubb out twice is stood at the fair spot) and
  helicopters that count. The scene takes `setup.kid` and `setup.kidY`: the stance starts
  on the line for kubbs too (`forwardLimit`), the flag says `KID LINE  2.0 M`
  (`hud.kidLineText`), the line is drawn thin and solid on the pitch (`render.world.kidY`,
  1 px, in the frame and layer keys) and as a solid row on the minimap, a person's throw is
  on the Kid meter (docs/notes/throw.md "The Kid meter"), and the hand-off card says KID
  RULES. The result flag's words are the Kid rulings' (`hud.short`): KING STOOD BACK UP
  (a kubb thrown in, or a baton that took nothing else), `2 DOWN: KING BACK UP`, OUT TWICE:
  STOOD UP FAIR; never GAME OVER or PUNISHMENT in a Kid match. Self-tests `match-kid` (a
  whole Kid match against the Kid computer, its game file gated), `kid-aim` and
  `options-kid`.
- Camera: the aim camera frames the setup's `targets` (standing field kubbs, else base
  kubbs, else the king) and looks `camera.tune.aim.lookBeyond` past the nearest of them
  (`camera.lookDistFor`, never nearer than `lookMin`); base kubbs on the far baseline give
  the practice framing.
- System Menu "Match": sheet (Jamie, 2026-11-14: "see the scoresheet for a game in
  progress"; `scene.showSheet`): once nothing is in the air, the game file so far
  (`match.file`, no `End`) on `scenes/sheet`, opened at its last line, the rail with the
  teams, the turn and the surface; the crank or up/down scrolls, B goes back. The match
  waits under it (a throw, the Playdate's think, a card) and carries on where it was.
  Self-test `match-sheet`. Resign (the team on turn gives up, `G`; it waits until nothing is in
  the air, and is dropped if that throw ended the team's turn; chosen while the defender
  settles, it is the defender's, which holds the Playdate then, and waits for the
  defender's own turn: self-test `settle-resign`) or title (leave: the match is dropped and no file is written). A game file whose name is taken
  gets `-2`, `-3`, ... before `.txt`. Pass and play
  has one Playdate, so the team on turn is whoever holds it.
- The match tells the throw scene what the HUD shows: the rail (`throw.setRail`: team,
  projectile, number of it, and the field and base kubbs still to topple, or KING) and,
  after a throw is resolved, the result flag (`throw.setFlag`, `hud.short` of the
  result). Per frame it adds, from the throw scene, a dozen-entry target scan for the camera. Once per throw (not per frame) it builds the
  engine's pieces and outcome tables and rebuilds the items: expect one longer frame on the
  device when a throw is resolved and the next set up.

## Kubb sets

Not on the Playdate since 2026-11-20 (Jamie's Settings sheet: sets are a look for the web
and the iPhone; "We exclude Playdate here becaue the black & white display and size of
display makes this irrelevnat, plus the CPU cannot handle it."). Every piece draws one
way, bare wood (what was the classic set). From 2026-11-14 to 2026-11-20 the match options
had a SET row (classic, USA, Sweden, Minnesota, Wisconsin) that painted the kubbs' heads
and the king's crown near the camera (`render.world.sets`, `setFrom`, `setDetailFrom`);
the USA set cost 154 draw calls a flight frame against 134 classic, and every kubb painted
had cost a tenth of the shown speed on the device. That code, the `sets` self-test, the
autobench's USA and Wisconsin cases and the soak's set per match are gone; the history is
in git before this change.

Since engine 0.9 the core's `matchopts` has no SET row (sets are the web's and the iPhone's,
through the room's options) and `matchopts.apply` sets no `opts.set`, so `scenes/options`
has no filter of its own. Saved data from a build with SET still loads: a kept "matchopts"
choice keeps its other choices (`matchopts.valid` reads only the rows it has, so the set
number is dropped the next time the choice is written), and a match saved with `opts.set`
resumes, plays and carries the field on in its saves without drawing it (core/save writes
what it was given). No game file ever had a set in it. Self-test `set-save`.

The VS PLAYDATE opponent throws at the match's COMPUTER level; a match saved before 0.10.0
without one uses the throw level the old System Menu "Level" kept (datastore "level").
The tagged engine gives Club and Pro their drill spin and baton turnover.
