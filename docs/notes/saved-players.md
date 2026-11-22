# Saved players

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

## Saved players

docs/PLAYERS.md (the agreed plan; built). Pure: `core/roster.lua`
(`tw.roster`, `test_roster.lua`) and `core/history.lua` (`tw.history`, `test_history.lua`);
the datastore part is `source/players.lua` (`tw.players`).

- **A player** (`core/roster`): `{ key, name, id, level, made, last, totals }`. `key` is
  `p<n>`, never reused (`r.nextKey`); `name` is a generated player name since game 0.12.0
  ("Generated names" below; `core/names` still cleans it, at 16 letters on the device); `id` is
  `notation.baseId(name)` and unique on the roster (`roster.canName`: `empty`, `taken`,
  `full`), so a player has the same id in every game file; `level` is one of
  `tw.plan.LEVELS`, kept but no longer shown or changed (see "The throw level"); `totals` are counters (`roster.TOTALS`: games, wins,
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
  are left as they were. `players.today()`, `players.now()` give the dates. A load never
  changes a kept name: see "Generated names".
- **PLAYERS** (`scenes/players.lua`, the title's fourth item; no board, the Drills board's
  look): the roster on a black panel (+ NEW PLAYER, then the players most recently played
  first) and the chosen player's figures (games, wins, hit rate, kings, kubbs in, the last
  ten games as bars of hits over batons with a dot for a win). A opens a player: NAME (A:
  the Names screen, a new generated name), GAMES (their recent games), REMOVE (a confirm
  card: the history goes, game files stay), with their drill bests. A new player gets a
  name on the Names screen (`scenes/names`, which refuses a taken name and shows why) and
  lands on their page. The LEVEL row went in game 0.12.0 (engine 0.13: a level names only
  the computer). Self-test `players`.
- **The title** has four items in two rows of two (four do not fit across at 16 px):
  VS PLAYDATE, PASS + PLAY / PRACTICE, PLAYERS; left/right go in reading order, up/down
  change row.
- **TEAMS** (`scenes/teams.lua`, pure state in `core/lineup.lua`, `test_lineup.lua`):
  PASS + PLAY and VS PLAYDATE open it in place of the names step (title -> teams ->
  options -> play). Three columns: Team A, the black bench (START, + PLAYER, + GUEST, then
  the saved players on no team), Team B (the Playdate against VS PLAYDATE). Left/right on
  a player send them toward that side (bench to a team, a team to the bench), anywhere else
  change column; hold A + up/down moves a team's player up or down the order (the order
  is the rotation of "Throwing order"); A on a team's name opens the Names screen for a
  generated team name; + PLAYER makes a saved
  player, + GUEST one for this match only (not saved, no key); either goes straight onto an
  empty team (`lineup.seatNew`: Team A, else Team B when it is not the Playdate's), so a
  first match needs no trip through the bench (RC review, 2026-11-15). Six a side
  (`lineup.tune.size`); a player is on one side. A team's name is the one given, else the
  player's for a team of one, else `Team <first player>`. The lineup is kept per mode
  (datastore `teams`, saved players only) and offered again; a kept team name typed on an
  older build stays until it is renamed. A name of two or more words too wide for a column
  even in the label face shows its first word as an initial (`N. REDWOOD`) or without its
  `The` (`scenes/teams` `fitName`); a single word is never cut (a typed name is at most 10
  letters and fits). `lineup.teams(L)` is
  `core/match`'s teams: players `{ name, key, level, guest }`. Self-test `teams`.
- **In a match** (`core/match`, `scenes/match`): `m.lineup` (`match.lineupOf`) keeps each
  engine player's key, level and guest flag beside the engine's ids; `s.thrower` is
  `{ id, name, key, level }`. The hand-off card names the turn's first thrower (passed the
  Playdate), the team on the throw line, the kubbs' inkaster when someone else, and the
  turn's batons by player (`KIM 2 · MAX 2 · ALEX 1 · DANA 1`). Before a throw by another
  player of the same team the **pass card** (`cards.pass`, `rcards.pass`) says who takes
  the Playdate, for which batons (`BATONS 3 AND 4`) or the kubbs. On either
  card B opens the **change list** (`match.candidates`, `rcards.change`): the team's
  players, those the rules refuse with why (`TWO BATONS ALREADY`, `NEEDS ANOTHER
  THROWER`); A hands the throw over (`match.changeThrower`), saved at once. The rail reads
  `TEAM: PLAYER` for a team of several, or the player alone when both do not fit before the
  pips (and for a team of one whose team name does not fit; the pips' KUBBS / BATONS word
  goes first, `hud.railRoom`). The winner card gives each of the winning team's
  players' hits over batons, three to a line. A finished match is folded into its saved
  players' histories (`core/history.foldGame`, not for scripted matches). No pass card for
  the Playdate's team or with `skipHandoff`. Self-test `match-teams` (three against two,
  one baton handed over, `order.checkSheet` on the sheet).
- **The save** is version 2 (`m.order`, `m.lineup`, `opts.teams`); a version 1 save is
  deleted at launch and never resumed (Jamie, 2026-11-15, decision 9).
- **The throw level** is the thrower's (docs/PLAYERS.md section 6), but since Kubb Engine
  0.13 it changes only the computer's throw: a person throws on the engine's one meter
  whatever level they have (docs/notes/throw.md "The person's meter"), the Kid meter in a
  Kid match. Since game 0.12.0 a person's level is not shown anywhere (PLAYERS' LEVEL row,
  the level beside each name on PLAYERS and TEAMS and the practice rail went); the roster
  and the history still keep what they had, so nothing saved breaks, and the game file's
  [Throw Levels] names the computer only (engine 0.13.2). The
  System Menu's "Level" is gone (its datastore "level" is still read as the fallback).
  `throw.levelFor(s)` reads `s.level` before that fallback. The match sets `s.ts.level` from
  `setup.thrower.level` for every throw (and again when the thrower is changed); a player
  without one (a guest at the default, a match without saved players: nil) falls back to
  the old System Menu's kept level. The Playdate's player has the match option COMPUTER as its level since
  0.10.0 (engine 0.9); a VS PLAYDATE match saved before that has none and falls back too. Practice: left/right on the drills menu
  choose who is practising (NO PLAYER, then the roster; kept in datastore `practice`),
  shown on the menu's rail; a drill run and OPEN PITCH throw on the meter, and the run's
  record goes to their history (`history.foldDrill`); NO PLAYER keeps the Playdate's own
  `drills` records. Levels are the computer's: kid (0.15), beginner, club, pro.
- **The game file** writes `[Throw Levels "playdate club"]` after `[Mode]` when the
  computer plays (engine 0.13.2, `match.fileLevels`: the computer's players only; none in
  pass and play), each player by the id `[Team X Players]` gives them (since engine 0.7.1:
  initials on a team of more than one, no prefix for a team of one; `notation.fileIds`); the vendored
  grammar and kubb.js accept the extra header. The games list's footer adds `3 V 2
  PLAYERS` for teams of several (`gamefile.parse`'s `players`). A player's page has a
  GAMES row: their recent games, newest first, each opening its file's score sheet
  (`scenes/sheet`, the file read from `games/`).

## Generated names

Since game 0.12.0 (Kubb Engine 0.15; kubb-engine docs/NAMES.md, the owner's decision of
2026-11-21 that the Playdate switches too) no name is typed. Every player, guest and team
name is two words from the engine's lists (`core/namegen`, `core/namewords`): a player
`<adjective> <wood>` ("Mighty Maple"), a team `<adjective> <noun>`, `The <noun>` or `<wood>
<noun>`, at most 16 letters.

- **The Names screen** (`scenes/names`, state in `source/device/namepick.lua`, pure and
  tested on the desktop, `test_namepick.lua`): the black panel says whose name it is, the
  name (display 32, else 16: the widest generated name is 189 px there), its game file id
  and what comes next; on the right three rows, FIRST WORD, SECOND WORD and SHUFFLE. Up/down
  choose a row; the crank (a word every 24 degrees, the raw direction, as the score sheet
  scrolls) or left/right step that word to the next that makes a name, or on SHUFFLE roll a
  new one. A team's first word runs through The, every adjective and every wood, so one row
  reaches all three team shapes. A takes the name (a refused one stays, with THAT NAME IS
  TAKEN), B goes back. It opens on the name being changed, or a rolled one. Self-tests
  `names`, `players`, `teams`.
- **16 letters.** `core/names` cuts a name at `names.max` (10) wherever the roster, the
  lineup and the load clean one; `device/enginetune` sets it to `namegen.max` (16) at launch.
  Self-test `names-fit` measures every generated name in the game's faces (widest: player
  140 px, team 148 px in the label face; 189 in display 16; about 380 in display 32) and
  checks each place's last fallback: the rail (146 px before the pips), TEAMS (cut, as
  above), PLAYERS and the Names screen. The hand-off, pass and settle cards drop a name too
  wide for display 32 to display 16 (`rcards` `bigName`), as the winner card did; the
  winner card's players, when cut, show a generated name's wood's first seven letters
  (`REDWOOD 22/29`) and a typed name's first six, as before; the score sheet's rail cuts
  two long team names to initials, then leaves its right side out.
- **Kept names.** The owner decided (kubb-engine docs/NAMES.md 10.2, Jamie,
  2026-11-21): "Saved players keep their typed names until someone renames them." A
  player saved with a typed name on a build before 0.12.0 keeps it, shown as it is on every
  screen, in matches and on their score sheets; the load never rewrites the roster. Only
  a rename changes it, and a rename is the Names screen, so it gives a generated name
  (nothing is typed anywhere). A kept team name likewise stays until renamed. New players,
  guests and team names are generated. On the Playdate a name never leaves the device, so
  there is nothing to protect by replacing one. (Build 12 replaced kept names at load;
  build 13 does not, and the self-test `players` checks a 0.11.0 roster loads unchanged.)
