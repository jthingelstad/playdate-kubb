// The notation gate (DESIGN.md section 7). Runs every .txt game in a folder
// through pk-kubb-score's strict grammar parser and kubb.js `analyze`.
//
//   node tests/node/notation-gate.mjs [dir] [--allow-warnings]
//
// dir defaults to tests/fixtures/games. pk-kubb-score is found at
// $PK_KUBB_SCORE, else ~/Projects/pk-kubb-score, and is only read.
//
// A game fails on: a grammar error, no [Win] header, a kubb.js winner that
// differs from the [Win] header (or that kubb.js only took from the header
// because the turns never end the game), or any "Couldn't read" warning.
// Every other kubb.js warning is printed, and fails the run unless
// --allow-warnings is passed. Exit 0 only when everything passes.

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

export async function loadPkKubbScore() {
  const root = process.env.PK_KUBB_SCORE || join(homedir(), 'Projects', 'pk-kubb-score');
  const parserPath = join(root, 'site', 'assets', 'notation-parser.js');
  const kubbPath = join(root, 'site', 'assets', 'kubb.js');
  for (const p of [parserPath, kubbPath]) {
    if (!existsSync(p)) {
      throw new Error(`pk-kubb-score not found: ${p} is missing. Set PK_KUBB_SCORE to its checkout.`);
    }
  }
  const { parse } = await import(pathToFileURL(parserPath).href);
  const { analyze } = await import(pathToFileURL(kubbPath).href);
  return { root, parse, analyze };
}

const SIDE = { 'team a': 'A', a: 'A', 'team b': 'B', b: 'B' };

// Returns { errors: [...], warnings: [...] } for one game's text.
export function checkGame(text, { parse, analyze }) {
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
  return { errors, warnings };
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
  let bad = 0, warned = 0;
  for (const f of files) {
    const { errors, warnings } = checkGame(readFileSync(f, 'utf8'), pk);
    const name = f.slice(dir.length + 1);
    if (errors.length) bad++;
    if (warnings.length) warned++;
    console.log(`${errors.length ? 'FAIL' : warnings.length ? 'WARN' : 'ok  '} ${name}`);
    for (const e of errors) console.log(`     error: ${e}`);
    for (const w of warnings) console.log(`     warning: ${w}`);
  }
  console.log(`gate: ${files.length} games, ${bad} failed, ${warned} with warnings (pk-kubb-score at ${pk.root})`);
  if (bad) return 1;
  if (warned && !allowWarnings) return 1;
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main(process.argv.slice(2));
}
