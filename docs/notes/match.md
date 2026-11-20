# Match and kubb sets

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

## Match

The title (`scenes/title.lua`, Woodcut look below) offers "VS PLAYDATE" (a match against
the computer), "PASS + PLAY" (the match) and "PRACTICE" (the drills menu, whose OPEN PITCH
is the practice pitch); `main.lua` opens one
scene at a time and rebuilds the System Menu for it (Level, then the scene's
own item; crank traces moved behind the `debug` file on 2026-11-20). Practice is the throw scene exactly as before.

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
  start; none against the Playdate, whose player holds it already, and none after. Raise: a 3D view of the lying kubb (`render/world` with its own camera,
  in the defender's view frame, behind and above it, far enough back to show the pitch
  round it; the pieces within `raiseNear`), each
  end the engine allows drawn on the ground as its 7 x 7 footprint, the chosen one dotted
  with STANDS HERE (MOVED CLEAR when II.D.5 slid it). The d-pad looks (Jamie, 2026-11-14):
  left/right turn the view round the kubb (`lookTurn` degrees a second), up/down zoom in
  and out (`lookZoom`, between `zoomMin` and `zoomMax` of the starting distance); which
  end is on the right is read again whenever the kubb lies flat. A raises the highlighted
  end (`g:raise(choice)`), which starts on the engine's own choice; only the crank picks
  the other end (Jamie, 2026-11-14). The crank (Jamie,
  2026-11-13) tips it: forward onto its right-hand end on screen, backward onto its left,
  `crankPerRaise` (270) degrees from lying to standing (`raising.tipPose`, pure and
  tested: it pivots on that end's bottom edge onto the footprint), and all the way up
  raises it on that end; an end the engine does not allow will not tip and its flag says
  why (THAT END IS OUT, THAT END IS BLOCKED). Punish: the
  defender's half from above (40 px a metre), grey keep-out circles a baton length from
  the stakes and the king, the kubbs on it, and a cursor kubb the d-pad moves (faster the
  longer it is held); `raising.punishmentCheck` runs as it moves, a refused spot shows why
  (TOO NEAR A STAKE, TOO NEAR THE KING, ON A KUBB) and A there does nothing; A elsewhere
  places it (`g:placePunishment`). The cursor starts at `raising.autoPunishment`'s spot. The
  still parts are one image redrawn only on a change. Scripted matches (`seed`,
  `instant`, or `autoSettle` in the scene's options) leave both to the engine
  (`match.setup`). Self-tests `settle` and `settle-crank`.
- Auto raise (Jamie's Settings sheet, 2026-11-20: "yes this should be on all platofrms."):
  the raise view's third plaque, **B REST OF GAME** (the web's and the iPhone's REST OF
  GAME button), raises the kubb on screen at once on the engine's own end, whatever the
  crank had tipped toward, and hands every raise after it to the game for the rest of the
  match: both teams' raises, this turn's and every later one's, as the web's MENU, Raising
  does (one setting for the match on the device, not one per team). Each automatic raise
  shows its kubb for `settle.tune.autoWait` (0.7 s, the web's wait) with **B BY HAND** and
  RAISING FOR THE REST OF THE GAME, then makes the call A makes on the engine's end
  (`g:raise(choice)` with the choice the view started on, `raising.choose` under
  `g.raisePolicy`, which is what `g:raise(nil)` picks), so the pitch, the score sheet and
  the game file are exactly a match raised by hand without the crank (self-test
  `auto-raise` checks it against `g:raise(nil)` on a copy). B BY HAND gives the raising
  back, starting with the kubb on screen. Punishment kubbs are still placed by hand (the
  web's does the same); the match option RAISING: AUTOMATIC (`autoSettle`) still leaves
  both to the engine with no view. In PASS + PLAY the pass card waits while the game is
  raising: it comes before the first thing the defender does by hand (a punishment kubb,
  or the rest of the raises after BY HAND), so a turn with only raises never changes hands.
  Against the Playdate the Playdate raises its own as before. Saved: core/save keeps only
  the options it knows, so the choice is a datastore file beside the match,
  `<save key>-raise` ("match-raise"; "selftest-match-raise" in self-tests), `{ start = the
  match's start, raise = "auto" }`, written when B turns it on, deleted by BY HAND and when
  the match ends; a resumed match raises for itself only when the file names its start
  (`scene.raiseKey`, `persistRaise`, `resumedRaise`), so a file left from an abandoned
  match does nothing. A rematch starts by hand. When core/save keeps it (engine 0.9), it
  moves into the save's `opts`.
- Names (`scenes/names.lua`, board `Names.png`; pure rules in `core/names.lua`, tested):
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
  `scenes/options.lua`, pure rows in `core/matchopts.lua`, tested): after the names, before
  every match (PASS + PLAY and VS PLAYDATE). Four rows: SURFACE (grass, sand, snow),
  OPENING (2-4-6, or six from the start), RAISING (by hand, or automatic: the engine's
  policies, `autoSettle`; against the Playdate "by hand" is the player's side only, as
  before) and WIND (off, light, strong; "Wind"); the core's SET row is not shown on
  the Playdate ("Kubb sets"). Up/down choose a row, left/right change it (the chosen row black, with arrows),
  a line under the rows says what the row is for; A starts, B goes back to the names. The
  choice is kept (`playdate.datastore` "matchopts", `matchopts.valid` on reading) and
  offered next time. `main.lua`: title -> `names` -> `options` -> `play`; a rematch keeps
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
- Games list (`scenes/games.lua`, board `Games.png`; `core/gamefile.lua` pure and tested
  over every fixture): the title's System Menu "Games" opens it. Every finished game in
  `games/`, newest first (file names start with the date): the date, the teams with a
  crown on the winner, turns and minutes; the chosen row is black; the footer gives its
  baton hit rates and the baton the king fell to. Crank (`crankRow` degrees a row) or
  up/down moves; A shows the score sheet (the game file as written, scrolled by the crank
  or up/down; B back; the same viewer as the match's, `scenes/sheet`); B goes to the title. Files are read and parsed only as their rows
  come on screen; each screen is one image redrawn only on a change. Self-test `games`.
- VS PLAYDATE (`scenes/match` with `opts.vs = "B"`; `main.lua` opens it as `"vs"`, and a
  rematch keeps it): the player is Team A (the name entered, "You" by default), the
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
  always the player's and waits for the player's turn. Self-test `match-vs` (a whole
  match, the player's throws seeded, its game file gated).
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

The SET row comes from the vendored core (`core/matchopts.list`), which is not edited
here: `scenes/options` leaves it out (`scene.hidden`, `scene.rows`) and its `apply` drops
`opts.set`, so a new match has none. Saved data from a build with SET still loads and is
never rewritten to drop it: a kept "matchopts" choice keeps its `set` number as it was
(unshown, written back unchanged with the rest), and a match saved with `opts.set` resumes,
plays and carries the field on in its saves without drawing it. No game file ever had a set
in it. Self-test `set-save`. For engine 0.9: the core's `matchopts` should say which rows
each client shows (or move SET to the web's and iPhone's own rows), so the Playdate can
drop its filter.

The VS PLAYDATE opponent uses the System Menu throw level when its roster entry has no level.
The tagged engine gives Club and Pro their drill spin and baton turnover.
