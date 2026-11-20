# Saved players

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

## Saved players

docs/PLAYERS.md (the agreed plan; built). Pure: `core/roster.lua`
(`tw.roster`, `test_roster.lua`) and `core/history.lua` (`tw.history`, `test_history.lua`);
the datastore part is `source/players.lua` (`tw.players`).

- **A player** (`core/roster`): `{ key, name, id, level, made, last, totals }`. `key` is
  `p<n>`, never reused (`r.nextKey`); `name` keeps `core/names` rules; `id` is
  `notation.baseId(name)` and unique on the roster (`roster.canName`: `empty`, `taken`,
  `full`), so a player has the same id in every game file; `level` is one of
  `tw.plan.LEVELS` (the throw's); `totals` are counters (`roster.TOTALS`: games, wins,
  resigned, batons, hits, field, base, kings, kingMisses, illegal, I, R, P, Q). At most
  `roster.tune.max` (40). `roster.valid(d)` cleans what the datastore gives back (never an
  error at launch); `roster.sorted` is most recently played first.
- **A history** (`core/history`, one file per player): the last `history.tune.games` (20)
  games `{ d, f, team, side, res, vs, b, h, k, lv }`, drill records as `core/drills.record`
  keeps them (by drill id), and the last 10 level changes. `history.gameStats(g)` reads a
  finished sheet by player id (a baton with `E` is not a hit, as in kubb.js);
  `history.foldGame(r, hs, g, { keys, levels, date, file })` adds a game to the saved
  players in it (`keys`: player id to roster key; guests and the Playdate have none);
  `history.foldDrill`, `history.setLevel` (logs the change).
- **Files** (`source/players.lua`): datastore `players` (the roster, about 300 bytes a
  player) and `player-<key>` (a history, about 3 KB); self-test runs use `selftest-`
  in front of both. `players.load()` makes the roster the first time from the old files:
  the names typed for matches (`names`) become players (the defaults aside), and the drill
  records (`drills`) go to the first of them (`You` when there was none); the old files
  are left as they were. `players.today()`, `players.now()` give the dates.
- **PLAYERS** (`scenes/players.lua`, the title's fourth item; no board, the Drills board's
  look): the roster on a black panel (+ NEW PLAYER, then the players most recently played
  first, each with their level) and the chosen player's figures (games, wins, hit rate,
  kings, kubbs in, the last ten games as bars of hits over batons with a dot for a win). A
  opens a player: NAME (A: the keyboard), LEVEL (left/right, saved at once and logged in
  the history), GAMES (their recent games), REMOVE (a confirm card: the history goes, game
  files stay), with their drill bests. A new player is typed (scenes/names in mode `"player"`, which refuses a
  taken name and shows why) and lands on their LEVEL row. Self-test `players`.
- **The title** has four items in two rows of two (four do not fit across at 16 px):
  VS PLAYDATE, PASS + PLAY / PRACTICE, PLAYERS; left/right go in reading order, up/down
  change row.
- **TEAMS** (`scenes/teams.lua`, pure state in `core/lineup.lua`, `test_lineup.lua`):
  PASS + PLAY and VS PLAYDATE open it in place of the names step (title -> teams ->
  options -> play). Three columns: Team A, the black bench (START, + PLAYER, + GUEST, then
  the saved players on no team), Team B (the Playdate against VS PLAYDATE). Left/right on
  a player send them toward that side (bench to a team, a team to the bench), anywhere else
  change column; hold A + up/down moves a team's player up or down the order (the order
  is the rotation of "Throwing order"); A on a team's name types it; + PLAYER makes a saved
  player, + GUEST one for this match only (not saved, no key); either goes straight onto an
  empty team (`lineup.seatNew`: Team A, else Team B when it is not the Playdate's), so a
  first match needs no trip through the bench (RC review, 2026-11-15). Six a side
  (`lineup.tune.size`); a player is on one side. A team's name is the one typed, else the
  player's for a team of one, else `Team <first player>`. The lineup is kept per mode
  (datastore `teams`, saved players only) and offered again. `lineup.teams(L)` is
  `core/match`'s teams: players `{ name, key, level, guest }`. Self-test `teams`.
- **In a match** (`core/match`, `scenes/match`): `m.lineup` (`match.lineupOf`) keeps each
  engine player's key, level and guest flag beside the engine's ids; `s.thrower` is
  `{ id, name, key, level }`. The hand-off card names the turn's first thrower (passed the
  Playdate), the team on the throw line, the kubbs' inkaster when someone else, and the
  turn's batons by player (`KIM 2 · MAX 2 · ALEX 1 · DANA 1`). Before a throw by another
  player of the same team the **pass card** (`cards.pass`, `rcards.pass`) says who takes
  the Playdate, for which batons (`BATONS 3 AND 4`) or the kubbs, at what level. On either
  card B opens the **change list** (`match.candidates`, `rcards.change`): the team's
  players, those the rules refuse with why (`TWO BATONS ALREADY`, `NEEDS ANOTHER
  THROWER`); A hands the throw over (`match.changeThrower`), saved at once. The rail reads
  `TEAM: PLAYER` for a team of several. The winner card gives each of the winning team's
  players' hits over batons, three to a line. A finished match is folded into its saved
  players' histories (`core/history.foldGame`, not for scripted matches). No pass card for
  the Playdate's team or with `skipHandoff`. Self-test `match-teams` (three against two,
  one baton handed over, `order.checkSheet` on the sheet).
- **The save** is version 2 (`m.order`, `m.lineup`, `opts.teams`); a version 1 save is
  deleted at launch and never resumed (Jamie, 2026-11-15, decision 9).
- **The throw level** is the thrower's (docs/PLAYERS.md section 6): `throw.levelFor(s)`
  reads `s.level` before the System Menu's "Level". The match sets `s.ts.level` from
  `setup.thrower.level` for every throw (and again when the thrower is changed); a player
  without one (a guest at the default, a match without saved players: nil) and the
  Playdate's team fall back to the System Menu. Practice: left/right on the drills menu
  choose who is practising (NO PLAYER, then the roster; kept in datastore `practice`),
  shown on the menu's rail; a drill run and OPEN PITCH (`main.lua`,
  `drills.practiceLevel()`) throw at that player's level, and the run's record goes to
  their history (`history.foldDrill`); NO PLAYER keeps the System Menu's level and the
  Playdate's own `drills` records. Levels are the throw's: beginner, club, pro.
- **The game file** writes `[Throw Levels "k pro, m club"]` after `[Mode]` when the
  match had levels (`notation.render`'s `meta.levels`, from `m.lineup`), each player by
  the id `[Team X Players]` gives them (since engine 0.7.1: initials on a team of more than
  one, no prefix for a team of one; `notation.fileIds`); the vendored
  grammar and kubb.js accept the extra header. The games list's footer adds `3 V 2
  PLAYERS` for teams of several (`gamefile.parse`'s `players`). A player's page has a
  GAMES row: their recent games, newest first, each opening its file's score sheet
  (`scenes/sheet`, the file read from `games/`).
