# Kubb: Throwing Wood

Kubb, the lawn game with batons and a king, on the Playdate. Wind the crank back, flick it
forward and let the baton go. Play a friend by passing the Playdate back and forth, or take on
the Playdate itself. Every finished game is saved as a score sheet in Planet Kubb Notation.

Play it: test builds to sideload are at https://playdate.thingelstad.xyz/throwing-wood/.

Design: `docs/DESIGN.md`. Working rules and commands: `AGENTS.md`.

```
make build      # build/ThrowingWood.pdx
make test       # Lua unit tests and the notation gate
make selftest   # scripted Simulator runs, frames in build/selftest/
```

Needs the Playdate SDK 3.1.2 at `~/Developer/PlaydateSDK`, Lua 5.4 from Homebrew
(`lua@5.4`) and Node. The notation parser the tests use is vendored in
`tests/vendor/pk-kubb-score/`.

What is built and how it works: `AGENTS.md` and `docs/notes/`.

## License

MIT (`LICENSE`), except:

- The display font, Throwing Wood Display (`source/fonts/`), is a 1-bit rendering of
  Londrina Solid and is under the SIL Open Font License 1.1 (`source/fonts/OFL.txt`; the
  original font and licence are in `tools/art/`).
- `tests/vendor/pk-kubb-score/` holds copies of files from the pk-kubb-score project, the
  home of Planet Kubb Notation, and follows that project's terms.
