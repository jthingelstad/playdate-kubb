# Status

Where the work stands, for whoever picks it up next. Updated 2026-11-13.

## On `main`

Everything built is merged; no branch holds unmerged work.

- Pass-and-play match and practice, with the rules engine, notation and saved game files.
- Smooth playback of throws (`AGENTS.md`, "Playback").
- The Woodcut look (`docs/design/README.md`): title, hand-off and winner cards, display
  font, launcher card, and the play screen (HUD, piece tones, ground, speed lines).

## Open problem: the Woodcut play screen slowed throws on the device

Measured with the autobench (`AGENTS.md`, "Measuring on the device"), the same three throws:

| | Before the play screen | With it |
| --- | --- | --- |
| Total time | 11.2 s | 16.3 s |
| Shown speed (1.0 = real time) | 0.41 | 0.28 |
| Mean frame | 42.5 ms | 43.4 ms |
| Starved frames | 2 | 1 |

Physics cost per step is unchanged, and more frames take the full redraw path, so the
extra time is in drawing. Which part is not known: the run was cut short before the
per-part `render/world` breakdown. Next step: run the whole autobench, read that
breakdown for flight and impact, and cut the cost (suspects: the rough pattern fill,
tufts, 2 px outlines, the HUD plates during flight).

## Not checked on hardware yet

- The punishment kubb fix (the search that used to trip the watchdog).
- The rough shimmering when the camera zooms or turns; speed lines during camera moves.
- The hand-cut M, N, W and 8 in the 16 px display font; Roobert loading for labels.

## Not built yet

1. Hit bursts (TOK, KLAK, KING) with sound.
2. Raising kubbs and placing a punishment kubb by hand.
3. A computer opponent.
4. Name entry, saved games and resume, practice drills.

## Open calls

- Hit words: the design uses TOK / KLAK / KING; the brief asked for POW / BAM.
- A licence, before the repo goes public.
