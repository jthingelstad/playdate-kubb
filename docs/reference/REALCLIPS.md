# Real clips: per-throw physics from public Kubb video

A first, small reference set for judging the engine's per-throw physics against real play,
measured frame by frame from public YouTube video (2026-11-16). One record per event is in
`realclips.json` (source link, time in the video, surface, camera, measurements with their
uncertainty, outcome labels). No video, frames or images are kept in the repository.

Whole-match rates are `tools/realgames.mjs` ("Real games" in AGENTS.md); this set is only
about single throws.

## What it is, honestly

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

## Real against the engine

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

## Where the engine sits outside, ranked

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

## What YouTube could not settle, and what would

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

## Methods

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
