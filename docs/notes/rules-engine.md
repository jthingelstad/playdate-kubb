# Rules engine, notation and throwing order

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

## Rules engine

`source/core/rules.lua` (`tw.rules`) is Rules V4.0 as a pure state machine. It knows nothing
about physics: it asks for the next action and takes resolved throws (the outcome records
below) and the defender's choices. Helpers: `core/pitch.lua` (dimensions, halves, stakes,
`advantageMeters`), `core/rect.lua` (oriented rectangles), `core/raising.lua` (II.D raising
and II.D.11 punishment geometry), `core/notation.lua` (score sheet and game file).

```lua
local g = tw.rules.new{ teams = { A = { name = "Jamie", players = { { name = "Jamie" } } },
                                  B = { name = "Playdate", players = { { name = "Club" } } } },
                        surface = "Grass", opening = "2-4-6" --[[ or "six" ]], first = "A",
                        raisePolicy = "apart" }
local n = g:need()
```

- Pieces: kubbs have permanent ids `a1`..`a5` (Team A's base kubbs at x = -2..2, y = 0) and
  `b1`..`b5` (y = 8); the king is `king`. `g.kubbs[id]` = `{ id, kind = "base"|"field",
  half = "A"|"B", where = "pitch"|"hand"|"out"|"punish", pose, thrown, established, fouled }`.
  `half` is the half a field kubb belongs to (where it was thrown), not recomputed from y: a
  kubb thrown this turn is a field kubb of the target half on the pitch wherever it lies
  until its round is judged. `where = "out"` means picked up for a rethrow. `fouled` marks a
  thrown kubb that touched the thrower's own half (II.C.4b) until it is judged.
  `g.king.pose`. `g:census()` counts kubbs by `where` (always 10). `g:liesNow(id)` says
  `"in"` or `"out"` for where a thrown kubb lies before it is judged; `g.judgment` is what
  the last judgment did (`thrown, rethrow, punish, rescue, lowered, lifted`), nil after a
  toss that did not end a round.
- State: `g.turn`, `g.attacker`, `g.defender`, `g.phase` (`toss`, `rethrow`, `raise`,
  `punish`, `batons`, `over`), `g.batonsLeft`, `g.advantageY`, `g.winner`, `g.how`,
  `g.sheet` (the notation score sheet).
- `g:need()` returns one of:
  - `{ kind = "toss", side, kubb, rethrow, throwY, half, left }`: the attacker throws kubb
    `kubb` from its baseline `throwY` into `half`. First throws come before rethrows (II.C.6).
    `left` counts this throw and the rest of its round (see "Judged at the final position").
  - `{ kind = "raise", side, kubb, pose, decision }`: the defender raises a lying kubb.
    `decision = { mode, choices, ends }` from `tw.raising.options`; mode is `choice` (both
    footprints clear and in bounds), `forced` (one), `displaced` (none clear: touching the
    obstruction, II.D.5; the defender may still pick the end when both qualify).
  - `{ kind = "punish", side, kubb, half }`: the defender places a punishment kubb.
  - `{ kind = "baton", side, n, of, left, kingShot, throwY, advantageY, targets }`: `throwY`
    is the advantage line when there is one and this is not a king shot, else the baseline.
    `targets` are the standing field kubbs, else the base kubbs, else `{ "king" }`.
  - `{ kind = "over", winner, how }`.
- Actions: `g:toss(outcome, player)`, `g:raise(choiceIndex | nil, policy)` (nil = automatic),
  `g:raiseAll(policy)`, `g:placePunishment(pose)` (returns false and a reason when invalid),
  `g:autoPunishment(policy)`, `g:throwBaton(outcome, player)`, `g:resign(side, player)` (only
  on the resigning team's own turn). `player` is an id or name; it defaults to the team's
  first player. Calling an action out of phase raises an error.
- Raising policies (`tw.raising.policies`): `apart` (default: the end farthest from other
  kubbs), `together`, `first`, or any `function(decision, ctx) -> index`. The punishment
  policy is a `function(candidates, ctx) -> pose`; the default puts it deep in the half and
  away from other kubbs.

### Poses

`{ x, y, standing, angle, onTop }` in world meters. `standing` = upright on an end; `angle`
is the long axis direction for a lying kubb (radians from +x) and the yaw of the square for a
standing one; `onTop` is the id of a kubb it rests on. A lying kubb raised on an end stands on
a 7 x 7 footprint centered 11 cm out along its axis (it pivots on that end's bottom edge).

### Baton outcome

What physics must report for one baton, after everything is at rest:

| Field | Meaning |
|---|---|
| `illegal` | true for an illegal throw (helicopter, II.B.1) |
| `toppled` | ids of every piece whose long axis came within a few degrees of horizontal at any point (II.B.10: one that ends standing on an end is still toppled). May include `"king"`. |
| `kingToppled` | true if the king was toppled (same as `"king"` in `toppled`) |
| `moved` | `{ [id] = pose }`: rest pose of every piece that moved, toppled or not (the king too) |
| `ownHalfHit` | ids of field kubbs in the thrower's own half that the baton touched, even if they did not move (II.B.11) |

The engine also treats any toppled or moved field kubb in the attacker's half as II.B.11.
What it does with them: illegal or II.B.11 throws put everything back and write `Z`; a king
toppled before every kubb is down loses (`E`, also after an illegal throw); toppled field
kubbs go to the defender's hand; a toppled base kubb with a field kubb still standing after
the throw is raised where it was (II.B.4a); a piece moved without toppling stays at its rest
pose unless its center left the pitch (II.B.7: put back). It stays as the throw left it, not
stood up straight: core/debris carries its exact body pose ("Debris" below).

### Kubb-toss outcome

| Field | Meaning |
|---|---|
| `rest` | rest pose of the thrown kubb: lying (with `angle`), standing on an end, or `onTop = id` when it rests on another kubb |
| `moved` | `{ [id] = pose }`: rest pose of every other piece it moved (field kubbs, base kubbs, the king) |
| `kingToppled` | true if it toppled the king (the throwing team loses) |
| `ownHalfHit` | optional ids of pieces in the thrower's own half it touched (II.C.4b) |

In bounds is the center of the standing kubb against the defender's half (lines are in). A
lying kubb is in if either footprint is. Struck field kubbs stay where they come to rest and
are raised there (II.C.4). Base kubbs a toss moves are stood back where they were. The king
toppled by a thrown kubb ends the game at once (`E`). Everything else waits for the
judgment below.

### Judged at the final position

The ruling (Jamie, 2026-11-13): whether a thrown kubb is in or out is not judged when it
stops. If a kubb is out and a later kubb moves it in, there is no rethrow; the rethrows go
by where every kubb lies once they are all thrown, and they come last.

- **Rounds.** A round is every kubb queued when it starts: the first throws (rescued kubbs
  among them) before the rethrows (II.C.6). While a round has throws left, every thrown kubb
  stays a piece on the engine's pitch at its rest pose (in, out of bounds, short of the
  middle line, in the thrower's own half), a field kubb of the target half, and later kubbs
  can move it. Nothing is judged.
- **The judgment** (`Game:_judge`, when the round's last throw is at rest), on every field
  kubb of the target half as it lies then, established ones included:
  1. a kubb resting on another is lowered beside it (II.D.6, `N`), unless the kubb under it
     is out (it is picked up: the upper kubb lies where it is, no `N`);
  2. an established field kubb that cannot be raised in bounds is rescued (II.C.5a, `Q`):
     back to the attacker as a kubb not yet thrown, thrown in the next round;
  3. a kubb thrown once that cannot be raised in bounds is picked up and rethrown in the
     next round (II.C.5b, II.C.6); so is one thrown once that a rethrow knocked out;
  4. a kubb thrown twice that is still out is a punishment kubb (II.C.5c, II.D.11, `P`).
  Out kubbs leave the pitch at the judgment, all at once. Rounds go on until nothing is left
  to throw; then the defender raises and places punishment kubbs as before.
- **II.C.4b at the final position.** A thrown kubb that touches a field kubb in the
  thrower's own half fouls at once: that kubb is put back (nothing in the own half is
  applied), the note is written, and the thrown kubb is out at the judgment wherever it
  lies by then (it stays on the pitch until then, a piece later kubbs can hit). A thrown kubb
  lying in the thrower's own half at the end without having touched anything is simply out
  (not in bounds). Moving a kubb thrown this turn is never II.C.4b, wherever it lies.
- **A rescue is judged at the end too:** an established kubb knocked out and knocked back in
  before the round ends stays where it lies, no `Q`.

## Notation conventions

`core/notation.lua` keeps the score sheet as the engine runs and renders the game file
(DESIGN.md section 7). `tw.notation.render(game, { start, finish, version, mode })` gives the
text; times are `{ year, month, day, hour, min }` tables passed in (no `os.time` in core);
`tw.notation.filename(start, teamA, teamB)` gives `YYYY-MM-DD-HHMM-<a>-v-<b>.txt`.

- Player ids: lowercased name, spaces and hyphens to `_`, everything else but letters
  dropped; a taken id gets `_b`, `_c`, ... Names in headers lose quotes and brackets; player
  names also lose commas and parentheses (kubb.js splits on them).
- Inkast token per player, in order of first toss: `I` = every first throw this turn
  (rescued kubbs included, so I = kubbs knocked last turn + Q), `R` = every rethrow made,
  `P` = punishment kubbs (also in R), `Q` = rescues, `N` = kubbs that came to rest on another
  (capped at 5, the grammar's limit), `E` = king toppled by a thrown kubb. `Y` is never
  written. No inkast token when there was nothing to throw. `I` and `R` are inked when the
  kubb is thrown; `P`, `Q` and `N` when the round is judged, to the player who made its last
  throw (the grammar takes the letters in any order; the token always writes `IRPQN`).
- When the game ends before the inkast is done (king toppled by a kubb, or a resign), the
  token still counts every kubb that was due, so kubb.js's inkast check holds.
- `nA` follows the inkast: whole meters from the attacker's own baseline to the advantage
  line, rounded down, 0 to 4.
- Batons: `-`, `F`/`nF`, `B`/`nB`, `FB`, `K`, `=`, `Z`, `E` or `nFE`/`BE`, `G`, then `X`
  for each baton left once the game is over (after `K`, `E`, `G` or an inkast `E`).
- Notes (`# a; b`) say what the tokens cannot: `bN toppled a base kubb early; raised
  (II.B.4a)`, `bN hit a field kubb in the thrower's own half; all put back (II.B.11)`,
  `bN pushed a kubb out without toppling; put back (II.B.7)`, `a kubb hit a field kubb in the
  thrower's own half (II.C.4b)`, `bN toppled the king early`, `king toppled by a thrown
  kubb`, `resigned during the inkast`. `bN` is the turn's Nth baton.
- `[Rules "U.S. Championship 4.0, 2-4-6"]` or `"..., six from the start"`.
- **Positions** (2026-11-16, the notation's optional `(@ ...)`; Jamie: "the biggest
  limitation of the scoresheet system I created is it doesn't note pitch position for
  anything"): exact meters `x,y` with two decimals after the token, before any `# note`:
  `3. max:2I (@ 4.39,4.61 4.34,5.21) max:F (@ 4.39,4.61) alex:B (@ 1.50,8.00)`. The frame
  is the pitch seen from Team A's baseline all game: `notation.pitchXY` is the engine's
  x + 2.5 (the left sideline, as someone on Team A's baseline facing Team B sees it, is
  x = -2.5; `test_positions` proves it with the aim camera and the base kubbs) and y as is,
  clamped to 0..5 and 0..8 (the grammar has no minus sign). The sheet keeps them as data in
  the engine's frame beside the token (`t.inkastAt[pid]`, a baton's `at`, through
  `Sheet:inkAt` and `Sheet:baton(pid, token, at)`); `turnLine` converts them and never
  writes more than the token counts (`kubb.js` warns on that).
  - A baton: where each kubb its token counts stood before the throw, its F kubbs then its B
    (each in id order); also for `nFE`/`BE`. None for `-`, `Z`, `E` alone, `K`, `=`, `G`,
    `X`, nor for a base kubb toppled early and raised (II.B.4a: not in the token).
  - An inkast: written once, as the batons begin (`Game:_inkastPositions`), when every
    kubb is raised and every punishment kubb placed (afresh if `match.settleStanding` moves
    one before the first baton): each kubb thrown this turn that is in
    play, where it stands, in the order of its last throw, on the token of the player who
    made that throw (`k.inkBy`, `k.tossSeq`); a punishment kubb on the token that counts
    its P. A rescued kubb (Q) has the place it was thrown back in to; a kubb lowered from on
    top of another (N) where it was raised after; a kubb out of play has none.
  - A game that ends during the inkast (king toppled by a kubb, `E`; a resign before the
    batons) writes no inkast positions: nothing was raised. An early king by a baton keeps
    the token's F places (`2FE (@ ...)`).
  - Not written: `^` (where the thrower stood). The engine's outcomes carry no stance, and
    the throw's stance is not kept to the rules engine; plumbing it through `core/match`
    for both the player's and the computer's throws is left for later.
  - A save from before positions loads (no `inkastAt`, `at`, `inkBy`, `tossSeq`): its
    turns render without them, and a turn in progress gives its kubbs to its one inkaster
    (none when it had several). `core/gamefile` drops comments in parentheses before it
    counts tokens.
  - On screen (`scenes/sheet`: the games list, a player's GAMES, a match's own sheet) the
    positions are left out (`gamefile.shown`): they would fill the 400 px screen, and the
    view reads as it did before. The file keeps them.

## Throwing order

Teams of one to six (docs/PLAYERS.md, the plan for saved players and team pass and play;
step 1 is built). `core/order.lua` (`tw.order`, pure, `test_order.lua`) decides who throws
every baton and kubb before the throw, within Rules V4.0 as far as a team's size allows:

- **II.B.5**: a player throws at most `order.cap(n, batons)` = max(2, ceil(batons / n))
  batons a turn (one player all six, two three each, three to six two each).
- **II.A.4**: the opening's two batons by two different players and its four by at least
  three (`order.distinct`, fewer for a smaller team).
- **Blocks**: each team has a rotation (its players in order); a turn's batons are dealt
  from it as evenly as possible over as many players as there are batons
  (`order.split`: 2, 2, 1, 1 for four players), a player's batons in a row, so the
  Playdate changes hands as few times as the rules allow. The next turn starts past the
  players who threw an extra baton (past everyone dealt when all threw the same): the
  doubles go round the team, and in the opening whoever did not throw opens the team's
  next turn.
- **The inkast**: one inkaster a turn (first throws and rethrows), by default the turn's
  first baton thrower (`o.inkaster`).
- **Changes**: `order.change(o, n, pid, thrown)` gives baton n to another player, swapping
  with that player's first later baton, refused (`team`, `cap`, `distinct`, `thrown`) if
  the turn would break a rule; `order.setInkaster(o, pid)`.
- `order.thrower(o, g)` deals the engine's turn when it is new (`order.sync`) and says who
  throws what `g:need()` asks for (the next baton's thrower also while the defender
  raises). The state is plain tables (`o.A`, `o.B` = `{ ids, start }`, `o.turn`, `o.deal`,
  `o.inkaster`), so `core/save` keeps it as `m.order`; a match saved without one starts a
  fresh order.
- `order.checkSheet(g)`: every turn of a finished sheet against both rules and the teams
  (`kubb.js` checks neither); `test_games`, `make games` and `tools/physmatch.lua` run it.
