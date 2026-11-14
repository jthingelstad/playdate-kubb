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

`watchdog-reset.txt` is the reset caused by the slow punishment kubb search, since fixed.
