// The notation gate (DESIGN.md section 7). Runs every .txt game in a folder
// through pk-kubb-score's strict grammar parser and kubb.js `analyze`
// (the copies in tests/vendor/pk-kubb-score).
//
//   node tests/node/notation-gate.mjs [dir] [--allow-warnings]
//
// dir defaults to tests/fixtures/games. Set $PK_KUBB_SCORE to a
// pk-kubb-score checkout to try its site/assets files instead of the copies.
//
// A game fails on: a grammar error, no [Win] header, a kubb.js winner that
// differs from the [Win] header (or that kubb.js only took from the header
// because the turns never end the game), or any "Couldn't read" warning.
// Every other kubb.js warning is printed, and fails the run unless
// --allow-warnings is passed. Exit 0 only when everything passes.
//
// Positions (the optional "(@ x,y ...)" after an inkast or a baton token,
// which the game writes since 2026-11-16) are errors when: one did not parse
// as positions (kubb.js kept it as a comment, so its token has no `at`), a
// token has more than it counts (an inkast's I + R + P + Y + Q + N, a hit's
// F + B; none on any other baton), one is off the pitch (x 0 to 5, y 0 to
// 8), or the game reads differently in kubb.js with every position taken
// out (they may only add places, never change the game).

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

export async function loadPkKubbScore() {
  const override = process.env.PK_KUBB_SCORE;
  const root = override ? join(override, 'site', 'assets') : join(here, '..', 'vendor', 'pk-kubb-score');
  const parserPath = join(root, 'notation-parser.js');
  const kubbPath = join(root, 'kubb.js');
  for (const p of [parserPath, kubbPath]) {
    if (!existsSync(p)) {
      throw new Error(`pk-kubb-score not found: ${p} is missing. `);
    }
  }
  const { parse } = await import(pathToFileURL(parserPath).href);
  const { analyze, parseGame } = await import(pathToFileURL(kubbPath).href);
  return { root, parse, analyze, parseGame };
}

const SIDE = { 'team a': 'A', a: 'A', 'team b': 'B', b: 'B' };

// The text with every positions comment taken out.
export function stripPositions(text) {
  return text.replace(/[ \t]*\(@[^()]*\)/g, '');
}

// How many kubbs a token counts, the most positions it may carry.
function mostPositions(t) {
  if (t.type === 'inkast') return t.I + t.R + t.P + t.Y + t.Q + t.N;
  if (t.kind === 'hit') return (t.f || 0) + (t.b || 0);
  return 0;
}

// What kubb.js makes of a game, without the positions themselves.
function reading(text, analyze) {
  return JSON.stringify(analyze(text), (k, v) => (k === 'at' || k === 'source' ? undefined : v));
}

// Position errors for one game, and how many positions and tokens with them.
export function checkPositions(text, { analyze, parseGame }) {
  const errors = [];
  let positions = 0, tokens = 0;
  const { turns } = parseGame(text);
  for (const t of turns) {
    const where = `turn ${t.n ?? '?'}`;
    const written = (t.source.match(/\(@/g) || []).length;
    const toks = [...t.inkasts, ...(t.advantage ? [t.advantage] : []), ...t.batons];
    const withAt = toks.filter(k => k.at);
    if (withAt.length !== written) errors.push(`${where}: ${written} positions comments, ${withAt.length} read as positions`);
    for (const c of t.comments) if (c.startsWith('@')) errors.push(`${where}: "(${c})" was kept as a comment`);
    for (const k of withAt) {
      tokens++;
      const most = mostPositions(k);
      const at = k.at.filter(p => !p.thrower);
      positions += at.length;
      if (at.length > most) errors.push(`${where}: "${k.raw}" has ${at.length} positions for ${most} kubbs`);
      for (const p of k.at) {
        if (!(p.x >= 0 && p.x <= 5 && p.y >= 0 && p.y <= 8)) errors.push(`${where}: position ${p.raw} after "${k.raw}" is off the pitch`);
      }
    }
  }
  if (tokens && reading(text, analyze) !== reading(stripPositions(text), analyze)) {
    errors.push('the game reads differently in kubb.js with its positions taken out');
  }
  return { errors, positions, tokens };
}

// Returns { errors: [...], warnings: [...], positions, tokens } for one game's text.
export function checkGame(text, pk) {
  const { parse, analyze } = pk;
  const errors = [];
  const warnings = [];
  try {
    parse(text);
  } catch (e) {
    const at = e.location ? `line ${e.location.start.line}, column ${e.location.start.column}: ` : '';
    errors.push(`grammar: ${at}${e.message}`);
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
  const pos = checkPositions(text, pk);
  for (const e of pos.errors) errors.push(`positions: ${e}`);
  return { errors, warnings, positions: pos.positions, tokens: pos.tokens };
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
  let bad = 0, warned = 0, positions = 0, tokens = 0, placed = 0;
  for (const f of files) {
    const r = checkGame(readFileSync(f, 'utf8'), pk);
    const { errors, warnings } = r;
    positions += r.positions; tokens += r.tokens; if (r.tokens) placed++;
    const name = f.slice(dir.length + 1);
    if (errors.length) bad++;
    if (warnings.length) warned++;
    console.log(`${errors.length ? 'FAIL' : warnings.length ? 'WARN' : 'ok  '} ${name}`);
    for (const e of errors) console.log(`     error: ${e}`);
    for (const w of warnings) console.log(`     warning: ${w}`);
  }
  console.log(`gate: ${files.length} games, ${bad} failed, ${warned} with warnings (pk-kubb-score: ${process.env.PK_KUBB_SCORE ? pk.root : 'vendored copy'})`);
  console.log(`gate: ${positions} positions on ${tokens} tokens in ${placed} games`);
  if (bad) return 1;
  if (warned && !allowWarnings) return 1;
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main(process.argv.slice(2));
}
