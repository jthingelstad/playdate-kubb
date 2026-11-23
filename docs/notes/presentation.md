# Woodcut look, slow motion, hit bursts and knocks

Subsystem notes moved out of `AGENTS.md` (2026-11-17). The hard rules are also in
`AGENTS.md`; this file keeps the detail and the history. Paths are from the repo root.

## Woodcut type, title, cards and launcher

The look is `docs/design/` (README and boards). What is built of it here:

- **Display font**: Throwing Wood Display (`source/fonts/ThrowingWoodDisplay-16` and `-32`,
  cap height 16 and 32 px): capitals, digits and `! . · % ° + - : , / ' ?`. It is a 1-bit
  rendering of Londrina Solid Black, licensed under the SIL Open Font License 1.1, which
  reserves the name "Londrina Solid", so the rendering has its own name. The licence and
  attribution ship in `source/fonts/OFL.txt` (copied into the pdx); the original TTF and
  licence are in `tools/art/`. At 16 px M, N, W and 8 are cut by hand (`OVERRIDES` in
  `tools/art/build.py`).
- **Labels**: Roobert 10 Bold in capitals, loaded at run time from the system
  (`render.ui.tune.labelPaths`); the system font if that fails. The SDK's font files are not
  copied into the repo. Roobert has no `·`, so `ui.textDots` draws middle dots as 2 x 2
  squares.
- `render/ui.lua` (`tw.render.ui`): the fonts, `ui.text`, `ui.textDots` and `ui.button` (a
  filled disc with A or B and one word). Draw them into a cached image.
- **Title** (`scenes/title.lua`, `boards/Title.png`): `images/title` (the wordmark, band and
  THROWING WOOD, one pre-drawn image) with a menu of what works today (VS PLAYDATE, PASS +
  PLAY, PRACTICE and, since 2026-11-15, PLAYERS, in two rows of two:
  docs/notes/saved-players.md "The title") and A START. The System Menu is as before.
- **Cards**: `core/cards.lua` (pure, `test_cards.lua`) works out what the hand-off and winner
  cards say from the engine and its score sheet: who throws, what the other team's batons
  took last turn (field and base), kubbs to throw in and batons, base kubbs standing, the
  pitch for the map in the receiving team's view, and for the winner the turns, minutes
  (start to finish by the clock: under a minute in the scripted self-tests) and the winner's
  baton hit rate. `render/cards.lua` draws them (`images/winner` is the burst behind the
  winner). Nothing is shown that the game does not know.
- **Launcher** (`source/launcher/`, `imagePath=launcher` in `pdxinfo`): `card.png` 350 x 155,
  `card-highlighted/1..4.png` with `animation.txt` (the last B tips 0, 5.3, 10.7, 16 degrees),
  `icon.png` 32 x 32 (the king) and `launchImage.png` 400 x 240 (the title without its menu,
  the same picture as `images/title`, so the start has no jump).
- **Regenerating**: `python3 tools/art/build.py` renders every one of these images and both
  fonts with headless Google Chrome (the SVG from the design boards, thresholded to pure
  black and white) and Python's standard library; `--preview DIR` also writes 4x previews of
  the font tables. Commit what it writes.

## Slow motion

`playback.speed(t, hitTime)` (`source/core/playback.lua`, tunables `playback.slow`) slows the
picture around the baton's first hit: the physics runs ahead of the screen, so the hit time
is known before it is shown. The slow stretch also gives the physics time to catch up on
the device.
While it plays (`playback.speed` below 1, the ease back included) the throw scene sets
`s.slowMo` and the HUD shows the SLOW MOTION flag (`hud.slow`, `hud.tune.slow`). The pace
slowing because the physics fell behind shows nothing. The `hit` self-test checks the flag
0.1 s after the hit (frames 2 and 3 show it). It is short (Jamie, 2026-11-14: it is for the
impact and must not hold the play up while the baton slides): `hold` 0.12 s after the hit,
then back to real time over `ease` 0.15 s (it was 0.45 and 0.35). On the device a throw
takes as long either way (the hit 6.20 s against 5.78 in the same run,
`telemetry/2026-11-14/bench/run5`): after a hit the physics computes slower than real
time, so the slide plays at the pace it allows with or without the slow motion.

The camera's half circle (Jamie, 2026-11-13): once a hit burst fires (baton throws only),
the impact camera orbits the struck piece by `throw.tune.swingDeg` (180) over `swingTime`
(0.8 s of shown time from that piece's impact, `camera.smooth`), the same way it was
already turned off the line of flight, and opens to a higher, wider view by the end
(`camera.tune.impact` `openHeight`, `openDist`, `openF`; `camera.impact`'s `orbit` and
`open`), so the slow motion shows the piece fall and the pitch round it; it stays there
through the rest. It runs on shown time (`s.swingFrom`, reset at launch), so it holds when
the picture holds (the calm tail; when the tail ends inside the turn the camera jumps to
where the turn has got to). While it turns the
camera moves, so those frames are full draws, not the layer, and they take
`swingPeriod` (60 ms) instead of `framePeriod`, leaving the physics its time: on the device
the match case's hit took 6.7 s from release to rest with the half circle at 40 ms a frame,
4.7 s at 60 ms and 4.2 s without it (shown speed over the three throws 0.34, 0.40, 0.42;
the open view costs nothing measurable; 2026-11-14). It goes round the piece its burst is
for (`s.burst.x1, y1`), not the first thing hit, and a burst taken back stops it where it
is (`s.swingStop`). Jamie kept it on at that cost (2026-11-14). `swingDeg = 0`
turns it off (the `layer` self-test does, to test the layer with a still camera; the
autobench has a variant without it). The `burst` self-test checks it starts at the impact.

## Hit bursts

`docs/design/README.md` "Hit effects". When the picture reaches the impact on the first kubb
or king a baton toppled (the moment it was struck, not once it is down: Jamie,
2026-11-13), a pre-drawn burst is put up and to the left of the hit, its long spike's tip
on it (every piece struck has its own knock: "Knocks" below).

- `core/world` stamps each body with `touchT`, the first time anything struck it (in the
  contact store, one test a contact, no arithmetic), and each piece it topples with
  `toppleT` (pieces down before the throw have none). `core/burstpick.pick(w, showTime)`
  (pure, tested) says which burst and when, by the struck pieces' impact times
  (`burstpick.hitTime`: `touchT`, else `toppleT`). The physics cannot reach a topple
  before the picture reaches the impact (the device ran 262 ms of shown time late that
  way), so a kubb or king is judged falling at its impact: toppled already, or struck
  within `judgeFor` (0.5 s) and moving at `fallV` (0.5 m/s) or turning at `fallW`
  (5 rad/s) or more (`burstpick.falling`, which also says whether it is `sure`, that is
  toppled). The king is judged only once it has toppled: its burst inverts the screen and
  plays the game's end, so a king merely pushed must never get it, at the price of a king
  burst that can come up to the physics' lead late (Jamie kept it so, 2026-11-14). A topple more than `grazeFor` (1 s)
  after the first touch was a later blow, so it is timed at the topple. The burst starts when the picture reaches the first falling piece's impact;
  one that was not sure and then comes to rest standing (`burstpick.stoodUp`) is taken back
  (`B.takenBack`: the burst ends at once). `render/burst` keeps how late it started,
  `B.gap`, and the autobench prints it: 2 to 6 ms of shown time on the device (2026-11-13),
  within one slow-motion frame. The king falling within `window` (0.4 s) of the first
  impact, or struck by the time on screen, is `king` (a king that falls later replaces the
  burst showing, from its start, with the king's chord); a second falling kubb struck
  within the window is `double`, else `clean`; nothing for a miss or a touch that leaves
  the kubb standing, and nothing for kubb tosses or drills.
- `render/burst.lua`: three images per kind, `images/burst/<kind>-1..3` (flash, burst with
  the word, break-up) from `tools/art/build.py` (`BURST_*`; 2-bit PNGs with a clear
  ground). Phases run on real seconds (2, 12 and 4 frames at 30 fps), not the slowed throw
  time. The anchor is the baton's first contact point when that was the toppled piece,
  else the piece's pose at its impact, lifted `lift`; it is projected each frame and the
  image kept on screen below the rail. Double: KLAK (first kubb) and KLAK! (second, 3
  frames later). King: the whole screen inverts for the flash
  (`playdate.display.setInverted`), the burst wears the crown. The break-up adds six
  `fillRect` chips. Drawn after `render.world.draw`, outside its caches.
- The king's burst adds a short C-G chord made by the synths at its flash (`sound.king`).
  The words are `BURST_WORDS` in `tools/art/build.py` (rerun it to change them).
- The throw scene keeps the state in `s.burst` (`burst.new`, `reset` at each launch and
  back at aim, `update` in flight and rest, `draw` after the world).
- Until the physics has computed the whole window after the first topple, the kind is
  provisional and re-read each frame: a later topple can still make a clean burst a double,
  or any burst the king's. `throw.reset`, `throw.prepare` and a scene change (`main.lua`
  `open`) clear the burst and the screen inversion.
- Self-tests: `burst` (the hit throw: flash, TOK!, break-up, then aiming again with the
  burst cleared; the burst must start within one shown frame of the impact: 5.8 ms of
  shown time on the Simulator), `burst-reset` (Pitch reset while the burst is up) and `bursts` (every
  burst image on white, for review).

## Knocks

Jamie (2026-11-14): "an audio recording of a Kubb hit. There are multiple to use so they
are not all the same ... if the baton hits multiple kubbs you could play multiple
overlapping files". `source/sounds/knock-1..9.wav`: nine takes of a baton hitting a kubb,
cut from Jamie's recording by `tools/sounds.py` (needs ffmpeg; the raw take stays out of
the repo): the rumble under the take (wind and handling, below about 300 Hz) filtered
out, each hit cut 4 ms before its onset for 0.36 s with its tail faded to silence, the
levels matched (the same RMS over the first 80 ms, the loudest peak -1 dBFS), mono 22050
Hz 16-bit (about 16 KB each). A rumble the filters let through is dropped by level.

- **When.** A knock for every piece struck, as the picture reaches the moment (`touchT`,
  the first touch by anything): kubbs and the king, batons lying on the pitch and the
  stakes (Jamie: "if wood hits wood play a sound"; the ground is not a body, so a landing
  is silent), in practice, matches and drills, batons and kubbs alike, whether it falls or
  not. The throw scene's
  `knocks` (flight and rest, every frame once the thrown piece's first hit is on screen;
  before it nothing else is awake to touch) asks `burstpick.touches(w, t0, t1, out)` (pure,
  tested) for those first touched since the last frame's shown time; the thrown piece
  itself is left out (its touch is the same blow). A knock more than `knockLate` (0.15 s)
  behind the picture is not played (the jump at the end of the calm tail).
- **Which.** `sound.knock()`: a random take, never the last one played and, when it can,
  not one still playing, so knocks that come together (a baton through two kubbs, a
  domino) overlap as different takes; each at a rate of 1 +-`knockRate` (0.06), so no two
  sound alike. One `sampleplayer` per take, made at the first knock.
- `tw.sound.tune`: `knocks` (9), `knockVol`, `knockRate`, `king` (the chord). Sound is off
  in self-tests; self-test `knocks` turns it on at volume 0 over the hit throw: every take
  loads, one knock per piece struck, none before the hit.
