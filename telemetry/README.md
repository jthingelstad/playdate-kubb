# Device telemetry

Copies of what the game recorded on a real Playdate, kept so tuning and speed work can be
done away from the device. One folder per day. Nothing here is read by the build or the
tests.

- `traces.jsonl`: every recorded swing, one JSON line each (format at the top of
  `source/core/trace.lua`). Replay with `lua5.4 tools/replay_traces.lua <file>`.
- `frames.jsonl`: one line per throw of frame timing (`AGENTS.md`, "Frame-time log").
- `games/`: the game files the device wrote for finished matches.
- `bench/`: autobench output (`AGENTS.md`, "Measuring on the device").
- `watchdog-reset.txt`: the device's crash log entry when a build hung.

## 2026-11-13

The first day of play, across many builds: times in the files are the device's clock (US
Central). `traces.jsonl` and `frames.jsonl` were copied before the Woodcut play screen was
installed.

| Bench file | Build |
| --- | --- |
| `run1-before-smoothing.txt`, `run1-frames.jsonl` | before the playback smoothing work |
| `run2-smoothing.txt` | with smoothing; the full run with the per-part draw costs |
| `run3-woodcut-play-screen.txt` | with the Woodcut play screen; cut short, match cases only |
| `run4-woodcut-full.txt` | the same build three minutes later, run to the end: the per-part draw costs (found on the device afterwards) |
| `run5-draw-split.txt` | the same play screen with the profiled match case: each flight frame's draw split, and one variant per suspect (outlines, tufts, rough, speed lines) |
| `run6-cheaper-rough.txt` | the rough as two on-screen fills, no speed lines; variants for tufts (16, 8, 0) and the draw estimate |
| `run7-speed-fix.txt` | the fix: no tufts, the estimate rising by a quarter; 0.44 of real time |

`watchdog-reset.txt` is the reset caused by the slow punishment kubb search, since fixed.
