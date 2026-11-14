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

Status: `docs/STATUS.md` (what is built, what is next, what has not been tried on a
Playdate yet).

## Licence

MIT (`LICENSE`), except:

- The display font, Throwing Wood Display (`source/fonts/`), is a 1-bit rendering of
  Londrina Solid and is under the SIL Open Font License 1.1 (`source/fonts/OFL.txt`; the
  original font and licence are in `tools/art/`).
- `tests/vendor/pk-kubb-score/` holds copies of files from the pk-kubb-score project, the
  home of Planet Kubb Notation, and follows that project's terms.
