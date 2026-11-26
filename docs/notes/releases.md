# Releases

The release history moved out of `AGENTS.md` (2026-11-17). How to make a release is in
`AGENTS.md` ("Commands", `make release`).

The zip is published on files.thingelstad.com and linked from
https://playdate.thingelstad.xyz/throwing-wood/ (that site's repository).

- 0.1.0 (build 2), 2026-11-14: the first for friends.
- 0.2.0 (build 3), 2026-11-14: HOW TO THROW walks through the real crank; drills set the
  angle.
- 0.9.0 (build 4), 2026-11-15: the last test build before 1.0.0; the crank-clock throw,
  saved players and teams, DOUBLES and THE WALL.
- 0.9.5 (build 5), 2026-11-15: the release candidate for wider play; HOW TO THROW for the
  clock throw, the baton hits pass, drilled kubbs that settle and a target circle that no
  longer locks onto kubbs; build 6 the same day adds HOW TO PLAY, the release-candidate
  polish and the plain-words pass.
- 0.9.6 (build 7), 2026-11-17: the physics-honesty release; the nine audit fixes, throws
  that come down where they are aimed, friction in the bounce (drills run on 0.68 m on
  grass, was 0.88), a row of touching kubbs that falls as a row, and pieces that come to
  rest.

- 0.9.7 (build 8), 2026-11-18. Batons turn over less. Club and Pro aim for a half turn
  and add spin to their drills. Slow impacts can move fallen wood. Open practice keeps
  six batons on the pitch and picks up the oldest for the next throw.
- 1.0.0 (build 17), 2026-11-22: the 1.0 release on Kubb Engine 1.0.0.
- 1.1.0 (build 18), 2026-11-26, on Kubb Engine 1.4.0. Each person throws EASY, STANDARD or
  HARD, set on TEAMS with an A tap (the level is the width of the bars, never a hidden
  miss). Against the Playdate the screen stays on your side: its throws, inkast and raises
  come toward you from your end, with B SPEED 1X/2X/4X (remembered) and A SKIP (the same
  match, no waiting). Raise kubbs in any order: one held view of the group, B NEXT, left
  and right pick the end, the crank tips it; Auto raise moved to the System Menu. THROW TO
  GO (on by default, not in a Kid match): one baton each at the king decides who throws
  first, the person first, written in the game file as `[Engine:first]`.

The bundle id changed on 2026-11-17 from `com.thingelstad.throwingwood` to
`com.throwingwood.playdate`, so every id is rooted at the game's own domain (the iPhone app
will be `com.throwingwood.app`). Saved data lives under `Data/<bundleID>`, so the old folder
is left behind: a Playdate that had an earlier build keeps its players, games and traces in
`Data/com.thingelstad.throwingwood/` and starts fresh under the new id.
