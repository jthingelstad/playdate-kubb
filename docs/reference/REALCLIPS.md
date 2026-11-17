# Real clips: per-throw physics from public Kubb video

A reference set for judging the engine's per-throw physics against real play, measured
frame by frame from public YouTube video (2026-11-16). One record per event is in
`realclips.json` (source link, time in the video, surface, camera, measurements with their
uncertainty, outcome labels). No video, frames or images are kept in the repository.

Whole-match rates are `tools/realgames.mjs` ("Real games" in AGENTS.md); this set is only
about single throws. The set has 220 events: 198 from pass 2, a calibrated tournament
camera, which is the one to read first; 22 from pass 1, highlight clips, kept below as
written, with what pass 2 changed in it under "Pass 2 against pass 1".

## Pass 2: tournament cage camera (198 events)

### What it is

- Five long tournament recordings from one channel's fixed cage camera: 1080p, 30 fps, a
  wide-angle lens low at a corner of one baseline, looking up the pitch over the whole
  match. The painted lines (baselines, sidelines, the centre line) and the stakes are in
  frame, so the ground is a calibrated ruler, and nothing is cut or chosen for its result.
  The 2026 video of the series was skipped.

  | Video | Segments (calibrations) | Drills | Batons | Into a group | Events |
  |---|---|---|---|---|---|
  | [RTK6pMfhLZk](https://www.youtube.com/watch?v=RTK6pMfhLZk) | A, A2, B, C | 22 | 14 | 7 | 43 |
  | [hR18YZf5xp8](https://www.youtube.com/watch?v=hR18YZf5xp8) | A, B | 41 | 14 | 2 | 57 |
  | [SbjUuNI_rlQ](https://www.youtube.com/watch?v=SbjUuNI_rlQ) | A, A2 | 17 | 13 | 3 | 33 |
  | [RGfefP5-hjQ](https://www.youtube.com/watch?v=RGfefP5-hjQ) | A0, A, B | 15 | 14 | 1 | 30 |
  | [o8l4InhmxsU](https://www.youtube.com/watch?v=o8l4InhmxsU) | A, A2, B | 24 | 10 | 1 | 35 |
  | all | | 119 | 65 | 14 | 198 |

  Every record has `setup: "cage camera"` and its `segment`; `t` is seconds into the video.
- Measured: the near half only (y 0 to about 4.3 m from the camera's baseline), where the
  homography is good to about 0.1 m (Methods). That is the half the far team drills into
  and the near team's batons land in.
- 73 of the 119 drills have a full run-on (landing and rest both seen and placed on the
  ground); the rest have outcome labels only (landed, rest pose, touched another,
  bounces). The drills are tournament drills: most go into one corner of the near half by
  a centre-line stake and pile up there, so 61% touch another kubb.

### Real against the engine

Intervals are 95% Wilson intervals on the counts. Engine figures are at commit `3703fe4`
("Free flight lands where it is aimed", main on 2026-11-16, after the physics audit):
`tools/drillscatter.lua --only 3` (the plan's clean drill, 12 markers x 24 grounds, grass
at half past 1, loft 47), `tools/batonprobe.lua --quick` and `tools/compound.lua --quick`.
Struck-kubb travel in the engine is from a scratch copy of batonprobe's sweep that also
printed the distance from the kubb's start (0, 8) to its rest for every toppled kubb; that
copy is not in the repository.

| Quantity | Real (pass 2) | Engine at `3703fe4` | Inside? |
|---|---|---|---|
| Drill run-on, first touch to rest, along the throw | median 0.02 m, mean 0.06, p10 -0.16, p90 0.29, -0.33 to 0.78 (n 73, each +-0.07 to 0.31, median +-0.16) | mean 0.95 m, sd 0.46, p10 0.43, p50 0.88, p90 1.56 | **No** |
| Drill run-on under 0.3 m | 66 of 73 (90%, 82-95%) | under 10% (p10 is 0.43) | **No** |
| Drill run-on 0.43 m or more (the engine's p10) | 4 of 73 (5%, 2-13%) | 90% | **No** |
| Drill that touched nothing: run-on under 0.3 m | 31 of 33 (94%, 80-98%), median 0.01 m | as above (the clean drill touches nothing) | **No** |
| Drill ends behind its first touch (run-on below 0) | 34 of 73 (47%, 36-58%) | none: the clean drill's p10 is 0.43 m forward | **No** |
| Drill moved in all, first touch to rest (any direction) | median 0.22 m, p90 0.50, max 0.81; under 0.3 m 42 of 69 (61%, 49-72%) | not separated (run-on above) | Real moves are short either way |
| Drill time, first touch to rest | median 0.37 s, mean 0.39, max 0.74 (n 69) | mean 0.78 s, max 1.64 | **No** |
| Drill first touches on an end or corner | 40 of 54 seen (74%, 61-84%) | nose down 47 deg at the touch | Plausible; not a count |
| Drill bounces before rest | 0 in 39, 1 in 16, never 2 or more | not counted by a tool | Not compared |
| Drill rests standing on an end | 1 of 89 (1%, 0-6%) | grass 0% (rest flat 100%) | Yes |
| Drill touches another kubb | 51 of 84 (61%, 50-70%), aimed into a pile | 43% in matches (pass 1's main, part 2 not re-run) | Edge; the real ones aim at piles |
| A directly struck standing kubb (one alone) falls | 40 of 40 (100%, 91-100%) | 93% of touched (261 of 280) | Yes |
| A struck base kubb falls | 29 of 31 (94%, 79-98%) | (same sweep) | Yes |
| Struck field kubb leaves the ground | 14 of 22 clear views (64%, 43-80%) | 58% over 1 cm | Yes |
| Struck field kubb travel, start to rest | median 0.52 m, mean 0.73, max 2.39; under 0.3 m 7 of 25 (28%, 14-48%) | toppled: median 0.65 m, mean 0.99, p90 2.26, max 6.2; under 0.3 m 72 of 261 (28%) | Yes; the engine's tail is longer |
| Baton landing short on an end: plugs | 0 of 9 (0-30%): vaulted on 3, slid or tumbled into the kubb on 6 (it fell 4 times, stood 2) | 15% of end-first landings lose three quarters of their spin | Yes (n small) |
| Tight group (gaps 5 cm or less), one baton: every kubb falls | 2 of 9 hits (22%, 6-55%) | 3 one behind the other touching 72%; 4 touching 13%, 4 at 3 cm 6% | Yes |
| The same, groups of 4 or more | 0 of 7 (0-35%) | 4 touching 13%, 4 at 3 cm 6% | Yes |
| The same, two or more fall | 8 of 9 (89%, 56-98%) | 2 one behind at 3 cm 82%; 2 side by side at 3 cm 23% | Yes for a line |
| Kubbs of a tight group that fall | 24 of 40 (60%, 45-74%) | not summarised | Not compared |

The nine tight-group hits (time, kubbs fell of the group): RTK6 578.5 1 of 5, 592.13 2 of
4, 596.53 2 of 2 (the same cluster three times, so not independent), 260.88 3 of 4; hR18
181.65 3 of 3; SbjU 755.07 2 of 6, 760.57 3 of 4 (4 of 5 with a kubb beside it), 1166.6 3
of 4; o8l4 430.85 5 of 8. Three more hR18 groups whose gaps could not be measured fell 4
of 4, 4 of 4 and 7 of 7. Wider groups (7 to 18 cm): 2 of 4, 2 of 2, 2 of 2, 1 of 2, 3 of
3, 2 of 4.

### Pass 2 against pass 1

- **Confirms: the drill's run-on on grass is far shorter than the engine's.** Pass 1 had
  9 of 9 under 0.3 m with one camera along the throw; pass 2 has 66 of 73 on a calibrated
  ground, median 0.02 m against the engine's 0.88. Pass 1's caveat (every drill went into
  a group, where a lying kubb stops it) does not explain it: the 33 drills that touched
  nothing ran on a median 0.01 m, 31 of them under 0.3. They still came down near a pile,
  so a drill into an empty half is still not measured, but nothing here suggests it runs
  on a metre.
- **Confirms: a struck standing kubb falls** (40 of 40 alone, 29 of 31 base kubbs).
- **Overturns: touching groups do not all fall.** Pass 1 had 16 of 16 from highlight clips
  (two of them titled for their result). Unselected tournament play takes every kubb of a
  tight group 2 times in 9, and a group of four or more 0 times in 7, though two or more
  fall 8 times in 9. The engine (4 touching all fall 13%) is inside that. Pass 1's second
  ranked item is withdrawn: the selection was the finding.
- **Overturns: struck kubbs do leave the ground** (14 of 22 against pass 1's 0 of 2), at
  about the engine's rate (58%). Pass 1's fourth item is withdrawn.
- **Overturns: struck kubbs travel.** Pass 1 had every struck kubb within a kubb length;
  pass 2's median is 0.52 m and the share under 0.3 m (28%) is the engine's to the point.
- **Overturns: drills on an end.** Pass 1 had 1 of 9 grass drills resting on an end and
  ranked the engine's 0% third; pass 2 has 1 of 89, so the engine is inside. Withdrawn.
- New: a real drill ends behind its first touch about half the time (47%), and comes to
  rest in about 0.4 s.

### Where the engine sits outside, ranked

Most confident first. None of these changes anything in `source/`.

1. **The drill's run-on on grass.** Real: median 0.02 m, 90% under 0.3 m. Engine: mean
   0.95, under 10% below 0.43 m. The engine's median is three times the real p90,
   and the per-event uncertainty (median 0.16 m) is a fifth of the gap. Where it lives: the ground contact of a tumbling kubb
   landing on an end or corner in `world.step` and the grass surface's `bite`, `biteTime`
   and friction (`world.surfaces.grass`), and the drill's tumble at the touch
   (`world.launchDrill`, `world.aeroTurn`). Pass 1's direction stands, now with a number:
   a real drill landing on an end loses nearly all of its forward speed at the touch.
2. **The drill's time to rest.** Real median 0.37 s (max 0.74); engine mean 0.78 s (max
   1.64). The same cause as 1 seen from the clock: the real kubb is dead within a dozen
   frames.
3. **Drills end behind their first touch.** 47% of real drills rest behind where they
   first touched (median -0.01 m on an end, -0.06 m flat): the kubb lands on its leading
   end and falls back over it. The engine's clean drill always goes on forward (p10 0.43
   m). Fixing 1 may fix this; check it as its own count.
4. **The struck kubb's tail.** The median and the share under 0.3 m match; the engine's
   p90 (2.26 m) and maximum (6.2 m) run past the real maximum (2.39 m, n 25). Weak: the
   engine's figure is a lone kubb from 8 m, the real ones are field kubbs from 3 to 6 m.
5. **Touched another kubb** (61% real against 43%): not a physics gap. The real drills aim
   at piles; the figure is the throwers', and the engine number is from pass 1's main.

### Methods, pass 2

- **Calibration.** For each segment (a new one wherever the camera was bumped) the four
  corners of the near half, points along the near baseline and sidelines and the centre
  line, and the near stakes were clicked on full-resolution frames. Model: an 8-parameter
  homography after a one-parameter division-model radial distortion, `p_u = c + (p - c) /
  (1 + k1 r^2)` about the image centre. k1 was fixed first from the straightness of the
  painted lines (-0.05 to -0.35 by video), then the homography fitted by Levenberg-Marquardt
  with Huber weights (numpy only). The lens bows the lines visibly at the frame's edges,
  so every calibration carries the term.
- **Error.** Fitted lines: near baseline and sideline 5 to 10 mm rms; lines running away
  from the camera 2 to 11 cm. Held-out points: the king's foot at (2.5, 4.035) read 0.01 to
  0.10 m short in y in every segment and within 0.1 m in x except where the king had been
  set off-centre or reset by hand (up to 0.37 m, checked against the frames); the held-out
  centre-line stakes within about 0.1 m. One video's last calibration (o8l4) fits the
  stakes rather than holding them out. Two calibrations of one SbjU segment clicked
  independently agree to 4 mm rms (10 mm at worst) across the near half and read a 0.3 m
  kubb length as 0.300 to 0.302 m. The far half was left out: the far baseline and stakes
  came out 0.25 to 0.83 m off.
- **Run-on.** The landing (the first frame the kubb touches the ground) and the rest are
  clicked at the kubb's centre and mapped to the ground. Run-on is the rest minus the
  landing projected on the throw (from the far baseline at the landing's x to the landing,
  or from a stance seen in frame); `lateral_m` is the rest across it. Uncertainty per event
  (`run_on_unc_m`): the click error (about 3 px) through the homography's local scale, plus
  3% of the distance from the camera's baseline, plus a 0.02 m floor, in quadrature.
- **Timings** are frame counts at 30 fps (+-1/30 s at each end).
- **Batons and groups.** For every baton that reached the near half: the target (field or
  base kubb), where it first touched (short, on the kubb, long), how it landed (end first
  or flat), the kubbs it struck and how many fell, whether a struck field kubb left the
  ground (seen off the ground in at least one frame), and its rest. Group gaps were
  read off the ground plane before the throw; "tight" is every gap 5 cm or less.
- **Checks.** Each segment was measured from tiled strips of frames around each event, with
  pixel ticks; every helper's output was re-read against its frames
  before pooling, duplicated runs of one segment were merged, and a disputed group (RTK6
  578.5) was settled on fresh zooms.
- Frames and videos were kept outside the repository and the videos deleted afterwards.

## Pass 1: highlight clips (22 events)

### What it is, honestly

- 6 source videos used (of about 25 looked at), 22 events: 14 drilled kubbs (9 on grass, 5
  on sand), 5 baton throws at one or two standing kubbs (6 kubbs struck directly), 3
  baton-into-group chains. That is far short of the 100 drills and 100 baton hits the
  brief hoped for. The intervals below are wide, and most rows are a direction to look in,
  not a number to tune to.
- Why so few: tournament streams (US Nationals, VM i Kubb, 1v1 Worlds) are filmed wide from
  15 to 25 m; at 720p a kubb is 6 to 15 px and a baton a smear, so a hit kubb that wobbles
  and stands, a bounce, or a run on cannot be read. The one stream with a calibrated,
  lined pitch (the 2026 US Nationals cage) is side-on but too far for poses. Backyard and
  slow-motion clips are close enough, but they are few, cut, and often chosen because the
  throw worked (two of the chains are titled for their result).
- Slow motion: every slow-motion clip found is re-encoded at 25 or 30 fps with an unknown
  slow-down (about 4 to 6 times, judged from how long a struck kubb takes to fall). With no
  frame-rate tag and no fixed scale in frame, bounce heights and rebound angles were not
  measured. Those clips give outcomes and sequences only.

### Real against the engine

Intervals are 95% Wilson intervals on the counts. Engine figures are from the tools named,
at `main` on 2026-11-16 (the clean drill, 12 markers x 24 grounds; the baton sweep
`--quick`; `tools/compound.lua --quick`).

| Quantity | Real | Engine | Inside? |
|---|---|---|---|
| Drill on grass: run on from first touch to rest | 9 of 9 under about 2 kubb lengths (0.3 m), most under 1 (camera along the throw, +-1 length) | mean 0.95 m, p10 0.41, p90 1.60 at half past 1 (`drillscatter --only 3`) | **No** (if the camera is right; see below) |
| Drill on sand: run on | 5 of 5 under about 1 kubb length (0.15 m), +-0.5 | mean 0.26 m, p50 0.20, 12% dead stops | Yes, near the low end |
| Drill rests standing on an end | 1 of 14 (1 to 31%); grass 1 of 9 | grass 0% (576 drills), sand 3% | Edge: grass at 0% is below the real share |
| Drill lands first on an end or corner | 6 of 14 (on an end 3, corner 3) | nose down 47 deg at the touch (sd 21) | Plausible; not compared count for count |
| Drill bounces before rest | 0 or 1 each (mean 0.6, +-1) | not counted by a tool | Not compared |
| Drill touches another kubb on the way | 8 of 14 (into a group on purpose) | 43% in matches (`drillscatter` part 2) | Yes |
| A directly struck standing kubb falls | 6 of 6 (61 to 100%) | 93% of touched (251 of 271) | Yes |
| Struck kubb leaves the ground | 0 of 2 clear slow-motion views (0 to 66%) | 61% over 1 cm, 28% for 0.2 s or more | Not settled (n = 2) |
| Struck kubb travel | under 1 kubb length in every case | not summarised | Not compared |
| Baton landing short on an end | 1 of 1 vaulted forward over the planted end into the kubb and toppled it | end first: 10% lose three quarters of their spin (plug), the rest bounce or vault | Consistent (n = 1) |
| Baton landing short and flat | 1 of 1 skidded into the foot, kubb tipped back over it | aim 10 to 20 cm short topples 80 to 100% ("Aimed through the piece") | Consistent (n = 1) |
| A touching group, one baton: all fall | 6 of 6 (2 x 3 cluster) and 10 of 10 (double row); a loose sand cluster 5 to 6 of about 8 | 3 in a line touching: all three 64%; 4 in a line touching: all four 8%, two or more 55% | **No** for the long touching rows (highlights, so biased toward success) |

### Where the engine sits outside, ranked

1. **The drill's run on on grass.** Real drills that came down near the group stopped
   within a kubb length or two, tumbling and flipping as they did; the engine's clean
   drill runs on 0.4 to 1.6 m. Likely cause: the turf takes too little energy from a
   tumbling, edge-first landing (`source/core/world.lua`, the ground contact in
   `world.step` and the grass surface's `bite`, `biteTime` and friction in
   `world.surfaces.grass`). Caution: this cuts against Jamie's own reading ("These would be
   rolling and wobbling a TON more. This is why good drillers roll into other kubbs",
   "Drilling"), the one camera looked along the throw, and every drill measured was aimed
   into or beside a group, where a lying kubb stops it (which is the second half of that
   quote).
   Direction: do not tune from this. Settle it first with side-on footage of drills into an
   empty half (below); if it holds, more loss at an edge or corner strike, not more drag.
2. **Long touching rows falling together.** Real players take six and ten touching kubbs
   with one baton; the engine takes all of four in a touching line 8% of the time and
   stops the chain early (`compound.lua` part 3: a shove at 1 m/s 8 cm up does not tip a
   kubb 3 cm behind). Likely cause: the kubb-on-kubb contact gives back too little of a
   falling kubb's push to the next (`world.tune.pairE` 0.35, `pairMu`, and the pair
   bounce with its footing in `world.step`). The clips are highlights, so the real rate
   is lower than 100%; the direction (chains carry on) is the finding. Direction: a
   domino measurement (`compound.lua` part 3) against filmed hand-tipped rows.
3. **Drills never end on an end on grass.** One real grass drill of nine ended standing
   on its end (one more stood a second before toppling); the engine's clean drill never
   does on grass. Likely cause: the settle of a kubb landing end first (`world.step`, the
   standing pose). Small and low confidence; worth a count when more footage exists.
4. **Struck kubbs hopping** (engine 61% leave the ground). The two clear slow-motion views
   show the kubb pivot on its back edge without leaving the ground. Not settled.

### What YouTube could not settle, and what would

- Bounce height and rebound angle (baton and kubb on turf), the baton's turns in the air
  and its loft, a hit kubb that wobbles and stands: all need a known frame rate and a
  scale in frame. A phone on a tripod side-on to the landing zone, 2 to 3 m away, at 240
  fps, with a tape or a marked 1 m stick on the ground, would give each in one session of
  20 drills and 20 batons. Nothing public found is that close and that well framed.
- The drill's free run on: side-on footage of drills into an empty half. Tournament
  streams have it, but only at 720p from 20 m; a 1080p or 4K archive of the US Nationals
  cage camera would make the lined pitch a calibrated ruler (homography from the 8 x 5 m
  lines).
- Rates with useful intervals (100 or more of each) need that same close camera at a
  tournament or club night, not highlights.

### Methods

- Search: `yt-dlp "ytsearch30:<query>"` over kubb slow motion, slowmo, drilling, inkast,
  tutorial, technique, championship final, VM i Kubb Gotland, US national championship,
  world championship. About 170 unique results; 25 downloaded at 720p or lower (long
  streams in sections), then deleted.
- Events were found on contact sheets (ffmpeg `fps`, `tile`) and read on strips of 8 to 10
  frames a second around each throw.
- Scale: the kubb (7 x 7 x 15 cm) in frame. Run on is counted in kubb lengths from the
  first touch to rest; where the throw runs toward the camera the uncertainty is a whole
  kubb length. No homography was possible on the close clips (no lines in frame).
- Labels: landing (flat, on an end, corner, onto a group), bounces, rest pose (lying,
  standing on an end, on another kubb), touched another kubb, spin seen in the air; for
  batons the target, where it landed, how many kubbs it struck and how many fell.
- Not used: an automatic motion finder over a tournament stream (the compressed wide shot
  flickers everywhere), and tournament batons (too far to see contacts).
