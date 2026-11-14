# Kubb: Throwing Wood

A Kubb game for the Playdate. The crank is the throwing arm, outcomes come from a physics
simulation at real dimensions, and every finished game is saved in Planet Kubb Notation.

Design: `docs/DESIGN.md`. Working rules and commands: `AGENTS.md`.

```
make build      # build/ThrowingWood.pdx
make test       # Lua unit tests and the notation gate
make selftest   # scripted Simulator runs, frames in build/selftest/
```

Needs the Playdate SDK 3.1.2 at `~/Developer/PlaydateSDK`, Lua 5.4 from Homebrew
(`lua@5.4`) and Node. The notation parser the tests use is vendored in
`tests/vendor/pk-kubb-score/`.

Status: stage 1, camera and throw feel. An endless practice loop from the baseline: walk,
swivel, loft, wind up and flick the crank; the baton flies a plain arc (no collisions yet).
`lua5.4 tools/replay_traces.lua <traces.jsonl>` replays recorded crank swings.
