# Players and teams: the plan

Draft of 2026-11-15. Jamie answered the questions in section 9 the same day: every
recommendation but one (an old saved match is dropped), so each "Recommended" there is
the decision. Built the same day (`AGENTS.md`, "Saved players").

Today a match is two teams of one player each, named as the team (`core/names.teams`), and
the throw is the same for everyone. Jamie decided the throw difficulty, the **Throw level**,
belongs to each player, not to the game, so a group can play together with everyone at a
different level. That needs:

- **saved players**: a name, a Throw level and a history, kept on the Playdate;
- **teams of up to six a side** built from them, passing one Playdate around;
- **a throwing order** inside each team that Rules V4.0 allows, with the game always
  knowing who is throwing, so it can write the right id on the score sheet and use the
  right Throw level.

The rules engine is most of the way there already: `rules.new` takes a `players` list per
team, `g:toss` and `g:throwBaton` take a player id or name, `notation.assignIds` makes ids
unique across both teams, and the notation gate already passes multi-player fixtures
(`2026-12-03-0101-snow-kubbs-v-baton-rouge.txt` has three players on Team A).
The missing parts are the roster, the team builder, the order, and passing the Playdate
inside a team.

## 1. What Rules V4.0 says about teams

From the V4.0 rulebook (usakubb.org):

- **I.B.** Two teams, at least three players a team in a tournament; registered
  players may substitute at any time.
- **II.A.4.** In the 2-4-6 opening, turn 1's two batons are thrown by two different
  players, and turn 2's four batons by at least three different players.
- **II.B.5.** No player throws more than two batons in a round (the glossary's round is
  one turn for each team, so this is per team turn).
- **II.C.** The inkast has no rule on who throws: any player, any number of kubbs.
- There is no maximum team size in V4.0. Six batons and at most two each means three
  players can share a turn; six players throw one each. Six a side is our cap.

A backyard team of one or two cannot keep II.B.5 (one player throws all six, as today; two
throw three each). So the game keeps the rule **as far as the team's size allows**:

- per turn, a player throws at most `max(2, ceil(batons / n))` batons, where `n` is the
  number of players on the team (1 player: 6; 2: 3; 3 to 6: 2);
- the opening's "different players" rule holds whenever the team has enough players
  (two different in turn 1 if `n >= 2`, three different in turn 2 if `n >= 3`).

`kubb.js` does not check either rule, so neither can make a game file fail the gate; the
check lives in our own code and tests.

## 2. A saved player

A player is a record in the datastore. Pure code in `core/roster.lua` (new):

```lua
{ key = "p7",            -- permanent, never reused; history and saves point at it
  name = "Kim",          -- as typed (names.clean rules: letters, spaces, - and ', 10 at most)
  id = "kim",            -- notation.baseId(name): the game file id, unique on the roster
  level = 2,             -- the Throw level (section 6)
  made = "2026-11-15",   -- date added
  last = "2026-11-20",   -- date last played (match or drill), for sorting
  totals = { games = 0, wins = 0, resigned = 0,
             batons = 0, hits = 0, field = 0, base = 0, kings = 0, kingMisses = 0,
             illegal = 0, I = 0, R = 0, P = 0, Q = 0 },
}
```

- **Names are unique on the roster by id**, not only by spelling: "Jo" and "jo-" both give
  `jo`, so the second is refused (`THAT NAME IS TAKEN`). Then two saved players can never
  share an id in a game, and a player's id is the same in every game file they play. The
  `_b` suffix of `notation.assignIds` stays for the one clash left: a saved player whose
  id matches the computer's player (`club`, `backyard`, ...).
- **Renaming** changes `name` and `id` for future games. Game files already written keep
  the old name; the history is keyed by `key`, so it follows the player.
- **Removing** a player deletes the record and its history file. Game files in `games/`
  stay (they are the real record and belong to every player in them). A player in the
  saved match in progress cannot be removed until that match ends or is dropped.

### History

What a player screen needs, folded in once at the end of each match or drill run (never
read back from game files, which would mean parsing every file on the device):

- `totals` above: all-time counts. Hit rate is `hits / batons`. `kings` and `kingMisses`
  give king shots; `I`, `R`, `P` give the inkast (rethrow rate `R / I`, punishments).
- **Recent games**, the last `history.tune.games` (20): date, game file name, team name,
  side, won or lost or resigned, the other team's name, and this player's batons, hits,
  kubbs thrown in and the level they played at. A to open the file in `scenes/sheet`.
- **Drills**: today's records (`core/drills.fold`: best, runs, points, possible, last ten)
  kept per player instead of once for the Playdate.
- **Level log**: the last 10 level changes (date, from, to), so a player can see how they
  have come on.

Only finished matches count. A match left for the title is dropped as now; a resign counts
as a game lost (and `resigned`).

### Where it is kept, and the limits

The Playdate has no fixed quota for game data; the costs that matter are the time to
encode and decode JSON on the device (a datastore write of a match at turn 4 was 68 ms)
and memory. So:

- `players` (one datastore file): the roster, every record above without the recent games
  and drills. About 300 bytes a player; **at most 40 players** (`roster.tune.max`), about
  12 KB. Read when the title opens the players or teams screen, written when a player is
  added, changed or removed, and once at the end of a match.
- `player-<key>` (one file per player): recent games, drills and level log, about 3 KB.
  Read only on that player's screen, and written at the end of a match or drill run for
  the players in it (12 small writes at most, behind the winner card, which is a still
  image).

Totals are counters that never grow; recent games are capped, so nothing grows without
bound. 40 players come to about 130 KB in all.

### What happens to today's saves

- `names` (the last names typed): on the first launch with this build, each saved name
  becomes a player at the default level, unless one with that id exists. Then `names` is
  no longer read.
- `drills` (the Playdate's own records): handed to the first player made from `names`
  ("You" if there is none), so nobody's bests vanish.
- `match` (a match in progress, `core/save`): a save from before this build has no
  roster keys, so it is deleted at the first launch (Jamie, 2026-11-15: decision 9).

## 3. Entering names

The Playdate's system keyboard (`playdate.keyboard`) is already in `scenes/names` and costs
us nothing to draw. A name is typed **once, when a player is made**; after that players are
picked from a list. That is what makes twelve players workable: the first evening costs
twelve names, every evening after it costs none.

The cheaper alternative, a crank-driven letter wheel, is slower to use than the keyboard
for a ten-letter name and would be ours to build and test; not recommended.

Guests: someone who plays once can be added from the team screen like anyone else and
removed afterwards, or added as a **guest**, a player with a name and level for this match
only: their id is in the game file, nothing is saved. Guests are in (decision 3).

## 4. Building the two teams

PASS + PLAY: title -> **teams** (new) -> options -> play. The teams screen replaces the
names step. VS PLAYDATE: title -> teams with only Team A open (the Playdate is Team B) ->
options -> play.

The teams screen (`scenes/teams.lua`, pure state in `core/lineup.lua`):

```
 TEAM A            PLAYERS            TEAM B
 SNOW KUBBS                           BATON ROUGE
 1 ALEX   L3       > KIM      L2      1 SAM    L1
 2 MAX    L4         LEE      L3      2 DANA   L2
                     + NEW PLAYER
                     + GUEST
   A START   B BACK                 CRANK: ORDER
```

- The middle column is the roster, most recently played first, with each level beside the
  name. The d-pad moves; **left or right sends the chosen player to that team**, and from
  a team back to the middle. A team holds six.
- On a team, the order shown is the **rotation** (section 5). Hold A and press up or down
  (or turn the crank) to move a player up or down it.
- The team name is the top row of each column: A on it opens the keyboard. Default: a team
  of one is that player's name (as today's files); a bigger team is `TEAM <first player>`.
  The last team names used for the same players are offered again.
- `+ NEW PLAYER` makes a player (keyboard, then the level) and puts them on the roster
  where the cursor is. `+ GUEST` the same, not saved (if Jamie wants guests).
- **A START** once both teams have a player (Team A only, against the Playdate). The
  lineup is remembered (`teams` datastore file) and offered next time.
- Left or right on a player who is in the saved match in progress does nothing (that match
  must be ended or dropped first): one player cannot be in two matches.

A rematch keeps the lineup and the options, as it keeps the options today.

## 5. The throwing order

The game must know who throws every baton and kubb **before** the throw, for the Throw
level and the score sheet. Pure code in `core/order.lua` (new), tested on its own and in
the headless games.

### Batons

Each team has a **rotation**: its players in the order of the teams screen. Each turn the
batons are dealt from the rotation in **blocks**, as evenly as possible over as many
players as there are batons:

| players | 6 batons | 4 batons (turn 2) | 2 batons (turn 1) |
|---|---|---|---|
| 1 | 6 | 4 | 2 |
| 2 | 3, 3 | 2, 2 | 1, 1 |
| 3 | 2, 2, 2 | 2, 1, 1 | 1, 1 |
| 4 | 2, 2, 1, 1 | 1, 1, 1, 1 | 1, 1 |
| 5 | 2, 1, 1, 1, 1 | 1, 1, 1, 1 | 1, 1 |
| 6 | 1 each | 1, 1, 1, 1 | 1, 1 |

- Blocks keep both rules (section 1) by construction, and mean the Playdate changes hands
  as few times as the rules allow: a player throws their batons in a row.
- **The rotation moves on** past the players who threw an extra baton (past everyone dealt
  when all threw the same), so the doubles go round the team: with four players the two
  who throw two each change turn by turn, and in the opening a team's players who did not
  throw in its turn 1 throw first in its turn 3.
- **Changing the thrower.** On the pass card (below) B opens the team's list: any player
  whose turn's batons the rules still allow can take this baton. The player it replaces
  takes the new thrower's next baton, if they had one (a swap), so the rest of the turn
  keeps its shape. Real teams change who throws to suit the shot (the best
  king shooter takes the king); this keeps that, and keeps the rules.

### The inkast

The kubbs are thrown by the team's **inkaster**: by default the player who throws this
turn's first baton, so the Playdate is not passed between the inkast and the batons, and it
can be changed the same way on the pass card. Rethrows and punishment kubbs are the same player's. Real teams tend
to have one or two specialist inkasters, so a fixed inkaster is closer to real play than
dealing kubbs round the team (decision 5).

### What the sheet says

Every token carries its thrower's id, as now: `3. kim:4I 2A kim:F kim:- max:2F max:- alex:B
alex:-`. The inkast's `P`, `Q` and `N` go to the player who made the round's last throw (the
engine does this already). A changed thrower needs no note: the tokens say who threw.

### Passing the Playdate inside a team

The hand-off card (before a team's turn) now names the first thrower and the order:

```
PASS THE PLAYDATE TO
KIM
SNOW KUBBS · TURN 7
KIM THROWS IN 4 KUBBS
THEN BATONS: KIM 2 · MAX 2 · ALEX 1 · DANA 1
```

When the thrower changes within the turn, a smaller **pass card** comes up before the
throw: `PASS TO MAX`, `BATONS 3 AND 4`, the Throw level, `A THROW · B CHANGE`. No pass card
for a team of one, or when the same player throws on. The rail shows the thrower's name
beside the team (`SNOW KUBBS · MAX`, baton 3 of 6). The settle card (raising) names the
defending team, as now: anyone on it can raise.

The winner card gives each player of the winning team their batons and hits
(`KIM 4/7 · MAX 3/6`), within the card's lines; the team hit rate stays.

## 6. The Throw level

The throw is being redesigned in another session: the d-pad moves a target circle, A +
d-pad walks, B + d-pad sets the arc and tilt or spin, and the crank throws against a clock
gauge. Its level sets the target ranges' widths and the error gains. This plan only says
where the level comes from and how it reaches the throw:

- **It lives on the player** (`player.level`, an integer `1..levels.count`, default
  `levels.default`; as built, the name of one of the new throw's levels, `tw.plan.LEVELS`:
  beginner, club, pro, default club). Its names, its count and what each changes belong to the throw
  design (`core/levels.lua` or wherever that session puts them); the roster stores only
  the number and refuses one out of range.
- **It is fixed for a match.** At the start, `core/match` copies each player's key, id,
  name and level into `m.lineup` (the save keeps it, so a resume throws at the same
  levels). A level changed during a match counts from the next one.
- **It reaches the throw through the setup.** `match.setup(m)` returns a `thrower`:
  `{ key, id, name, level }`, from `core/order`. `match.resolve` passes `thrower.id` to
  `g:toss` and `g:throwBaton`. `throw.prepare(s, setup)` reads `setup.thrower.level`,
  and the new throw model takes it from there. The throw scene never looks at the roster.
- **Practice and drills** have a player too: the drills menu gets a row `PLAYER  KIM  L2`
  (left or right to change), remembered between runs. OPEN PITCH and every drill throw at
  that player's level, and the drill's records go to that player's history.
- **The Playdate's own level** (Backyard, Club, Championship; DESIGN Q4) is the computer's
  scatter in `core/autothrow`, not a Throw level: the computer does not use the crank.
  The two scales share names (decision 6) when the throw design has three levels.
- **In the game file**, so a sheet can be read for what it was: one extra header,
  `[Throw Levels "alex 3, kim 2, max 4, sam 1"]`. The vendored grammar and `kubb.js`
  accept an extra header (tried: the gate passes it with no warning). It is written
  (decision 7).

## 7. Screens

All in the Woodcut look (`docs/design/README.md`): black panels, the display face for
names, Roobert labels in capitals, ringed A and B buttons, each screen one cached image
redrawn only on a change. None of them has a board; they are built in the existing
boards' style and reviewed from the 2x frames (decision 10).

| Screen | What it shows | New or changed |
|---|---|---|
| Players | the roster as a black list on the left (name, level), the chosen player on the right: games, won-lost, hit rate, the last ten games as bars (the Drills board's layout) | new, a fourth title item, PLAYERS (decision 8) |
| Player | name (A: keyboard), level (left or right), recent games (A opens the sheet), drill bests, REMOVE (a confirm card) | new |
| New player | the Names board's keyboard panel, then the level | changed (`scenes/names` gives one name) |
| Teams | section 4 | new, replaces the names step |
| Hand-off card | names the first thrower and the turn's order | changed |
| Pass card | the next thrower, which batons, the level; B: change | new |
| Change thrower | the team's players, who may take this throw and why not (`TWO BATONS ALREADY`) | new, small list over the pass card |
| Winner card | per-player batons and hits | changed |
| Drills menu | the PLAYER row | changed |
| Games list | the chosen game's players in the footer | changed |

### Pure core and scene code

Pure (`source/core/`, desktop tests, no `playdate.*`):

- `core/roster.lua`: records, add, rename, remove, set level, unique ids, the cap,
  validation of what the datastore gives back (a bad file is ignored, never a crash at
  launch), migration from `names` and `drills`.
- `core/history.lua`: folding a finished engine game (its sheet, by player id) and a
  drill run into players' totals and recent games; summaries for the screens.
- `core/order.lua`: the rotation, dealing batons in blocks, the inkaster, changing a
  thrower and the rule checks, the next thrower for `match.setup`.
- `core/lineup.lua`: the teams screen's state (assign, order, team names, validity) and
  the engine's `teams` from it.
- Changes: `core/match` (lineup, `thrower` in the setup, passing ids), `core/cards`
  (thrower, order, per-player lines), `core/save` (the lineup), `core/notation` (the
  levels header), `core/names` (rules for one name; `names.teams` goes).

Scene code: `scenes/players.lua`, `scenes/player.lua`, `scenes/teams.lua`,
`scenes/names.lua` (one name), `scenes/match.lua` (the pass phase, change thrower,
history written at the end), `render/cards.lua` (the cards), `scenes/drills.lua` (the
player row), `scenes/title.lua` and `main.lua` (the flow and datastore files).

## 8. Build order

Each step is one pull request with `make test` and `make selftest` green and the gate on
every game.

1. **Order in the engine's games.** `core/order.lua` and its tests; `core/match` gets
   lineups of 1 to 6 a side and returns `thrower`; `tools/thrower.lua` and `make games`
   play teams of every size through `core/order` and check every sheet against II.A.4 and
   II.B.5; `tools/physmatch.lua` too. No screens. Fixtures: a 6-a-side game and a 2-v-4.
   *Built* (AGENTS.md "Throwing order").
2. **The roster and history, no screens.** `core/roster.lua`, `core/history.lua`, the
   datastore files, the migration; tests that fold the fixture games into histories and
   that a saved roster reads back. *Built* (AGENTS.md "Saved players"; the histories are
   tested on generated games).
3. **Players screens.** Players, Player, New player, remove; self-test `players` (frames:
   the list, a player, the keyboard step, the remove card). *Built*.
4. **Teams screen.** Replaces the names step for PASS + PLAY and VS PLAYDATE; lineup
   remembered; self-test `teams` (a 3-v-2 built with the d-pad, reordered, started).
   *Built*, in one pull request with step 5.
5. **Teams in a match.** Hand-off card with the order, pass card, change thrower, rail,
   winner card lines, save and resume with the lineup, history folded at the end;
   self-tests `match-teams` (a scripted 3-v-3 to a winner, game file gated) and `pass`.
   *Built* as one self-test, `match-teams` (three against two, a baton handed over, the
   sheet checked against the order's rules).
6. **Throw level wiring.** `setup.thrower.level` to the throw scene, the drills menu's
   player row, drill records per player. Waits on the throw redesign's level interface;
   until then the level is stored and shown but changes nothing. *Built* on the new throw
   (#91): `throw.levelFor(s)` reads the thrower's level; the levels are its beginner,
   club and pro.
7. **Game file and games list.** The `[Throw Levels]` header (if agreed), the games
   list's players, a player's recent games opening their sheets. *Built*, in one pull
   request with step 6.

Steps 1 and 2 do not depend on each other; 3 needs 2; 4 needs 2 (and 3 for NEW PLAYER);
5 needs 1 and 4; 6 needs 5 and the throw redesign.

## 9. Questions and decisions

Asked 2026-11-15. Jamie took every recommendation except 9, where the old save is dropped
instead of resumed. Each "Recommended" below is the decision unless it says otherwise.

1. **The baton rule for small teams.** Keep II.A.4 and II.B.5 as far as the team's size
   allows (section 1), or only enforce them for teams of three or more and let a team of
   one or two throw as it likes? *Recommended:* as far as the size allows.
2. **Blocks or one each.** Batons dealt in blocks (a player throws their two in a row,
   fewest passes of the Playdate), or one baton each round the team? *Recommended:*
   blocks.
3. **Guests.** A guest player for one match, nothing saved? Or everyone who plays is saved,
   and removed later if wanted? *Recommended:* guests (step 4), since a party of twelve
   should not leave twelve players on the roster.
4. **Changing the thrower.** On the pass card with B (section 5), or a fixed order with
   no changes in a match? *Recommended:* B on the pass card.
5. **The inkast.** One inkaster a turn (the default: last turn's first baton thrower,
   changeable), or kubbs dealt round the team in blocks like the batons? *Recommended:*
   one inkaster.
6. **Level names.** Does the Throw level share the computer's names (Backyard, Club,
   Championship) or have its own scale? (Depends on the throw design's level count.)
   *Recommended:* the same names if the throw design has three levels, so "Club" means
   about the same thing for a player and for the Playdate.
7. **The levels header.** Write `[Throw Levels "..."]` in the game file? It is not in the
   Planet Kubb Notation README; it passes the grammar, but pk-kubb-score would not show it
   unless taught to. *Recommended:* yes; it costs one line and keeps the sheet honest.
8. **Where the players live.** A fourth title item, PLAYERS (VS PLAYDATE, PASS + PLAY,
   PRACTICE, PLAYERS), or the title's System Menu beside Games? *Recommended:* the
   title, since the teams screen sends people there anyway.
9. **An old saved match.** Resume a match saved before this build with one player a team
   and no history, or drop it? *Recommended:* resume it. **Decided: drop it** (a test
   build; little is lost).
10. **Boards.** Design the new screens (Players, Teams, Pass card) in a Claude Design
    session first, or build them in the existing boards' style and review the
    screenshots? *Recommended:* build in the existing style (Drills and Names boards
   cover most of it) and review the 2x frames.
11. **VS PLAYDATE teams.** Can several people play together against the Playdate (a team
    of up to six on Team A), or is VS PLAYDATE always one player? *Recommended:* a team;
   it is the same teams screen with Team B taken.
12. **The cap.** 40 saved players enough? *Recommended:* 40.
