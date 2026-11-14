# Vendored from pk-kubb-score

`notation-parser.js` (generated from the Planet Kubb Notation grammar by Peggy) and
`kubb.js` (the scorer) are copies from Jamie Thingelstad's pk-kubb-score project, the
home of Planet Kubb Notation. The notation gate (`tests/node/notation-gate.mjs`) runs
every game file through them.

Copied 2026-11-13. Do not edit these files here. To take a newer version, run
`make sync-notation` on a machine that has pk-kubb-score at `~/Projects/pk-kubb-score`
(or `$PK_KUBB_SCORE`), read the diff, run `make test` and `make games`, and commit.
`package.json` only marks the folder as ES modules.
