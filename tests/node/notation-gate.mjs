// The notation gate (DESIGN.md section 7). Runs every .txt game in a folder
// through pk-kubb-score's released Notation 2 reader (the copies in
// tests/vendor/pk-kubb-score, at the tag in its SOURCE): the grammar's canonical
// form, its canonical writer, and kubb.js `analyze`.
//
//   node tests/node/notation-gate.mjs [dir] [--allow-warnings]
//
// dir defaults to tests/fixtures/games. Set $PK_KUBB_SCORE to a
// pk-kubb-score checkout to try its site/assets files instead of the copies.
//
// A game fails on: a grammar error in the canonical form (CanonicalGame: the
// engine is a program, and programs write the canonical form), a file that the
// canonical writer would change, no [Win] header, a kubb.js winner that differs
// from the [Win] header (or that kubb.js only took from the header because the
// turns never end the game), any "Couldn't read" warning, or position lines
// that change how kubb.js reads the game (they may only add places). Every other
// kubb.js warning is printed, and fails the run unless --allow-warnings is
// passed. Exit 0 only when everything passes.
//
// The round trip: when a game has a <name>.places.json beside it (what the
// engine's score sheet kept, in its own frame: tools/sheetplaces.lua), every
// point on its pitch and felled lines, as the grammar reads them, is turned back
// into the engine's frame and must be one the sheet kept, within the notation's
// precision (half a centimetre), each used once, and a line must give all of
// them: a pitch line every kubb thrown in, a felled word every kubb its baton
// counts. What the file leaves out is counted, not failed
// (core/notation.positionLines says when it does).

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

export async function loadPkKubbScore() {
  const override = process.env.PK_KUBB_SCORE;
  const root = override ? join(override, 'site', 'assets') : join(here, '..', 'vendor', 'pk-kubb-score');
  const parserPath = join(root, 'notation-parser.js');
  const canonicalPath = join(root, 'canonical.js');
  const kubbPath = join(root, 'kubb.js');
  for (const p of [parserPath, canonicalPath, kubbPath]) {
    if (!existsSync(p)) {
      throw new Error(`pk-kubb-score not found: ${p} is missing. `);
    }
  }
  const { parse } = await import(pathToFileURL(parserPath).href);
  const { canonicalize } = await import(pathToFileURL(canonicalPath).href);
  const { analyze, parseGame } = await import(pathToFileURL(kubbPath).href);
  return { root, parse, canonicalize, analyze, parseGame };
}

const SIDE = { 'team a': 'A', a: 'A', 'team b': 'B', b: 'B' };
const POSITION_LINE = /^[@~^*][ab] /;

// The text without its position lines.
export function stripPositions(text) {
  return text.split('\n').filter(l => !POSITION_LINE.test(l)).join('\n');
}

// What kubb.js makes of a game, without the positions themselves.
function reading(text, analyze) {
  const skip = new Set(['lines', 'source', 'advantageLine']);
  return JSON.stringify(analyze(text), (k, v) => (skip.has(k) ? undefined : v));
}

// The notation's frame back to the engine's (core/notation.fromPitch).
export function fromPitch([across, depth], half) {
  return [across - 2.5, half === 'a' ? 4 - depth : 4 + depth];
}

const TOLERANCE = 0.005 + 1e-9;

// Each written point (notation frame) matched to a kept one (engine frame),
// each kept point used once. Returns an error or null.
function matchPoints(written, kept, half) {
  if (!kept) return `${written.length} written, the sheet kept none`;
  if (written.length !== kept.length) return `${written.length} written, the sheet kept ${kept.length}`;
  const used = kept.map(() => false);
  for (const p of written) {
    const [x, y] = fromPitch(p, half);
    const i = kept.findIndex(([kx, ky], j) => !used[j] && Math.abs(kx - x) <= TOLERANCE && Math.abs(ky - y) <= TOLERANCE);
    if (i < 0) return `${p.map(v => v.toFixed(2)).join(',')} (engine ${x.toFixed(3)},${y.toFixed(3)}) is not a place the sheet kept`;
    used[i] = true;
  }
  return null;
}

const pointsOf = entries => entries.flatMap(e => Array(e.count).fill(e.at));

// The round trip for one game: errors, and how much was written of what was kept.
export function roundTrip(parsed, places) {
  const errors = [];
  const n = { pitchKept: 0, pitchWritten: 0, wordsKept: 0, wordsWritten: 0, points: 0 };
  places.turns.forEach((kept, i) => {
    const turn = parsed.turns[i];
    const where = `turn ${kept.n}`;
    if (!turn) { errors.push(`${where}: in the sheet, not in the file`); return; }
    for (const l of turn.lines) {
      if (l.half !== kept.half) errors.push(`${where}: a ${l.mark}${l.half} line, and the half under attack is ${kept.half}`);
      if (l.precision !== 'point') errors.push(`${where}: a ${l.mark}${l.half} line in cells; the engine writes points`);
    }
    if (kept.inkast && kept.inkast.length) n.pitchKept++;
    const pitch = turn.lines.find(l => l.mark === '@');
    if (pitch) {
      n.pitchWritten++;
      if (pitch.entries.some(e => e.mark !== null)) errors.push(`${where}: the pitch line marks a kubb s or p`);
      const pts = pointsOf(pitch.entries);
      n.points += pts.length;
      const e = matchPoints(pts, kept.inkast, kept.half);
      if (e) errors.push(`${where}: pitch line: ${e}`);
    }
    kept.batons.forEach(b => { if (b && b.length) n.wordsKept++; });
    const felled = turn.lines.find(l => l.mark === '*');
    if (felled) {
      if (felled.entries.length !== kept.batons.length) errors.push(`${where}: ${felled.entries.length} felled words for ${kept.batons.length} batons`);
      felled.entries.forEach((word, bi) => {
        if (word === null) return;
        n.wordsWritten++;
        const pts = pointsOf(word);
        n.points += pts.length;
        const e = matchPoints(pts, kept.batons[bi], kept.half);
        if (e) errors.push(`${where}: felled word ${bi + 1}: ${e}`);
      });
    }
    for (const l of turn.lines) {
      if (l.mark === '~' || l.mark === '^') errors.push(`${where}: a ${l.mark} line, which the engine does not keep`);
    }
  });
  if (parsed.turns.length !== places.turns.length) errors.push(`${parsed.turns.length} turns in the file, ${places.turns.length} in the sheet`);
  return { errors, n };
}

// Returns { errors: [...], warnings: [...], lines, trip } for one game's text
// (places: its .places.json, or null).
export function checkGame(text, pk, places = null) {
  const { parse, canonicalize, analyze } = pk;
  const errors = [];
  const warnings = [];
  let parsed = null;
  try {
    parsed = parse(text, { startRule: 'CanonicalGame' });
  } catch (e) {
    const at = e.location ? `line ${e.location.start.line}, column ${e.location.start.column}: ` : '';
    errors.push(`grammar (canonical form): ${at}${e.message}`);
  }
  if (parsed) {
    try {
      const c = canonicalize(text);
      if (c.text !== text) errors.push('canonical: the canonical writer would change the file');
      for (const r of c.reports) errors.push(`canonical: ${r}`);
    } catch (e) {
      errors.push(`canonical: ${e.message}`);
    }
  }
  const g = analyze(text);
  const turnWarnings = g.rows.flatMap(r => r.warnings.map(w => `turn ${r.turn}: ${w}`));
  for (const w of [...g.warnings, ...turnWarnings]) {
    if (/Couldn't read/.test(w)) errors.push(`kubb.js: ${w}`);
    else if (/Win header says/.test(w)) errors.push(`kubb.js: ${w}`);
    else warnings.push(w);
  }
  const header = SIDE[(g.headers['Win'] || '').trim().toLowerCase()];
  if (!header) errors.push('no [Win "Team A"] or [Win "Team B"] header');
  else if (g.winHow === 'Win header') errors.push('kubb.js found no ending in the turns; the winner came only from the header');
  else if (g.winner !== header) errors.push(`kubb.js winner is Team ${g.winner}, [Win] header says Team ${header}`);
  const lines = text.split('\n').filter(l => POSITION_LINE.test(l)).length;
  if (lines && reading(text, analyze) !== reading(stripPositions(text), analyze)) {
    errors.push('positions: the game reads differently in kubb.js with its position lines taken out');
  }
  let trip = null;
  if (places && parsed) {
    trip = roundTrip(parsed, places);
    for (const e of trip.errors) errors.push(`round trip: ${e}`);
  }
  return { errors, warnings, lines, trip };
}

export function gameFiles(dir) {
  return readdirSync(dir).filter(f => f.endsWith('.txt')).sort().map(f => join(dir, f));
}

async function main(argv) {
  const allowWarnings = argv.includes('--allow-warnings');
  const dirs = argv.filter(a => !a.startsWith('--'));
  const dir = resolve(dirs[0] || join(here, '..', 'fixtures', 'games'));
  if (!existsSync(dir) || !statSync(dir).isDirectory()) {
    console.error(`gate: no such folder ${dir}`);
    return 2;
  }
  let pk;
  try { pk = await loadPkKubbScore(); }
  catch (e) { console.error(`gate: ${e.message}`); return 2; }

  const files = gameFiles(dir);
  if (!files.length) { console.error(`gate: no .txt games in ${dir}`); return 2; }
  let bad = 0, warned = 0, lines = 0, tripped = 0;
  const sum = { pitchKept: 0, pitchWritten: 0, wordsKept: 0, wordsWritten: 0, points: 0 };
  for (const f of files) {
    const placesPath = f.replace(/\.txt$/, '.places.json');
    const places = existsSync(placesPath) ? JSON.parse(readFileSync(placesPath, 'utf8')) : null;
    const r = checkGame(readFileSync(f, 'utf8'), pk, places);
    const { errors, warnings } = r;
    lines += r.lines;
    if (r.trip) { tripped++; for (const k of Object.keys(sum)) sum[k] += r.trip.n[k]; }
    const name = f.slice(dir.length + 1);
    if (errors.length) bad++;
    if (warnings.length) warned++;
    console.log(`${errors.length ? 'FAIL' : warnings.length ? 'WARN' : 'ok  '} ${name}`);
    for (const e of errors) console.log(`     error: ${e}`);
    for (const w of warnings) console.log(`     warning: ${w}`);
  }
  console.log(`gate: ${files.length} games, ${bad} failed, ${warned} with warnings (pk-kubb-score: ${process.env.PK_KUBB_SCORE ? pk.root : 'vendored copy'})`);
  console.log(`gate: ${lines} position lines`);
  if (tripped) {
    console.log(`gate: round trip in ${tripped} games: ${sum.points} points read back as kept; pitch lines for `
      + `${sum.pitchWritten} of ${sum.pitchKept} turns with kubbs thrown in, felled words for ${sum.wordsWritten} of `
      + `${sum.wordsKept} batons that felled kubbs`);
  }
  if (bad) return 1;
  if (warned && !allowWarnings) return 1;
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main(process.argv.slice(2));
}
