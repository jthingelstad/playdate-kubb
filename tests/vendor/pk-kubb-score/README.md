# Vendored from pk-kubb-score

`notation-parser.js` (generated from the Planet Kubb Notation grammar by Peggy) and
`kubb.js` (the scorer) are copies from Jamie Thingelstad's pk-kubb-score project, the
home of Planet Kubb Notation. The notation gate (`tests/node/notation-gate.mjs`) runs
every game file through them: here, the files the self-tests' matches write (kubb-engine
gates the games its own tools write, with its own copies).

Copied 2026-11-13. Do not edit these files here. To take a newer version, run
`make sync-notation` with pk-kubb-score checked out beside this repository (or
`$PK_KUBB_SCORE`), read the diff, run `make test` and `make selftest`, and commit.
`package.json` only marks the folder as ES modules.
