// Real games against the game's own (AGENTS.md "Headless games", "Real games").
//
//   node tools/realgames.mjs <real dir> <game dir> [--json]
//
// Reads two folders of Planet Kubb Notation game files with pk-kubb-score's
// kubb.js (the copy in tests/vendor/pk-kubb-score): games people played and
// scored (a pk-kubb-score checkout's games/ folder) and games the computer
// played with real physics (tools/physmatch.lua --out). Both go through the
// same counting, so every figure has the same denominator on both sides.
// `make realgames` writes the physics matches and runs this. Read only: it
// never writes into either folder.
//
// A score sheet records what each baton took, not where anything stood or how
// it was thrown, so this says where the game's rates differ from real play,
// never why.

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

function blank() {
  return {
    games: 0, skipped: 0, turns: 0, turnsList: [], firstWins: 0, firstKnown: 0, how: {},
    batons: 0, hits: 0, illegal: 0,
    // a baton thrown while the other half has field kubbs standing
    field: { batons: 0, took: [0, 0, 0, 0], kubbs: 0, base: 0 },
    // a baton thrown at the base kubbs: no field kubb standing, a base kubb left
    base: { batons: 0, hits: 0, adv: 0, advHits: 0, line: 0, lineHits: 0, doubles: 0 },
    king: { shots: 0, hits: 0 },
    // turns that started with field kubbs to clear
    clear: { turns: 0, cleared: 0, btc: 0, byField: {} },
    advTurns: 0, playTurns: 0,
    ink: { I: 0, R: 0, P: 0, Q: 0, N: 0 },
    maxTook: 0,
  };
}

// Adds one analyzed game to the totals.
export function addGame(s, g) {
  if (!g.rows.length) { s.skipped++; return; }
  s.games++;
  s.turns += g.rows.length;
  s.turnsList.push(g.rows.length);
  s.how[g.winHow || 'none'] = (s.how[g.winHow || 'none'] || 0) + 1;
  if (g.first && g.winner) { s.firstKnown++; if (g.first === g.winner) s.firstWins++; }
  for (const r of g.rows) {
    s.playTurns++;
    if (r.advantage) s.advTurns++;
    for (const k of Object.keys(s.ink)) s.ink[k] += (r.ink && r.ink[k]) || 0;
    let field = r.startField, base = r.startBase;
    if (r.startField > 0) {
      const c = s.clear;
      c.turns++;
      const row = c.byField[r.startField] || (c.byField[r.startField] = { turns: 0, cleared: 0, btc: 0 });
      row.turns++;
      if (r.btc !== null && r.btc !== undefined) {
        c.cleared++; c.btc += r.btc;
        row.cleared++; row.btc += r.btc;
      }
    }
    for (const b of r.batons) {
      if (b.kind === 'unthrown') continue;
      s.batons++;
      if (b.kind === 'illegal') { s.illegal++; continue; }
      if (b.kind === 'king' || b.kind === 'kingmiss') {
        s.king.shots++;
        if (b.kind === 'king') s.king.hits++;
        continue;
      }
      const f = b.f || 0, k = b.b || 0;
      if (f + k > 0) s.hits++;
      if (f + k > s.maxTook) s.maxTook = f + k;
      if (field > 0) {
        const t = s.field;
        t.batons++;
        t.took[f + k > 3 ? 3 : f + k]++;
        t.kubbs += f;
        t.base += k;
      } else if (base > 0) {
        const t = s.base;
        t.batons++;
        if (k > 0) t.hits++;
        if (k > 1) t.doubles++;
        if (r.advantage) { t.adv++; if (k > 0) t.advHits++; } else { t.line++; if (k > 0) t.lineHits++; }
      }
      field -= f; base -= k;
      if (field < 0) field = 0;
      if (base < 0) base = 0;
    }
  }
}

const pct = (n, d) => d ? (100 * n / d).toFixed(1) + '%' : '-';
const num = (n, d, p = 2) => d ? (n / d).toFixed(p) : '-';
function median(a) {
  if (!a.length) return '-';
  const b = [...a].sort((x, y) => x - y);
  return String(b.length % 2 ? b[(b.length - 1) / 2] : (b[b.length / 2 - 1] + b[b.length / 2]) / 2);
}

// The comparison as rows of [label, real, game]; a row with one cell is a heading.
export function rows(a, b) {
  const both = fn => [fn(a), fn(b)];
  const out = [];
  const add = (label, fn) => out.push([label, ...both(fn)]);
  out.push(['Games']);
  add('games read', s => String(s.games));
  add('turns a game (mean)', s => num(s.turns, s.games, 1));
  add('turns a game (median)', s => median(s.turnsList));
  add('won by the team that threw first', s => pct(s.firstWins, s.firstKnown));
  add('ended on the king', s => pct(s.how.king || 0, s.games));
  add('batons thrown', s => String(s.batons));
  add('batons that took a kubb', s => pct(s.hits, s.batons - s.king.shots));
  add('illegal throws', s => pct(s.illegal, s.batons));
  out.push(['Batons at field kubbs (a field kubb standing when thrown)']);
  add('batons', s => String(s.field.batons));
  add('missed', s => pct(s.field.took[0], s.field.batons));
  add('took one kubb', s => pct(s.field.took[1], s.field.batons));
  add('took two', s => pct(s.field.took[2], s.field.batons));
  add('took three or more', s => pct(s.field.took[3], s.field.batons));
  add('of those that hit: two or more', s => pct(s.field.took[2] + s.field.took[3], s.field.batons - s.field.took[0]));
  add('field kubbs a baton', s => num(s.field.kubbs, s.field.batons));
  add('most kubbs with one baton', s => String(s.maxTook));
  add('base kubb down early (II.B.4a)', s => pct(s.field.base, s.field.batons));
  out.push(['Clearing the field (turns that began with field kubbs)']);
  add('turns', s => String(s.clear.turns));
  add('cleared every field kubb', s => pct(s.clear.cleared, s.clear.turns));
  add('batons to clear, when cleared', s => num(s.clear.btc, s.clear.cleared));
  const sizes = new Set([...Object.keys(a.clear.byField), ...Object.keys(b.clear.byField)].map(Number));
  for (const n of [...sizes].sort((x, y) => x - y)) {
    const cell = s => {
      const r = s.clear.byField[n];
      return r ? `${pct(r.cleared, r.turns)} in ${num(r.btc, r.cleared, 1)} (${r.turns})` : '-';
    };
    add(`  ${n} field kubb${n === 1 ? '' : 's'}: cleared, batons (turns)`, cell);
  }
  add('turns thrown from an advantage line', s => pct(s.advTurns, s.playTurns));
  out.push(['Batons at base kubbs (no field kubb standing)']);
  add('batons', s => String(s.base.batons));
  add('took a base kubb', s => pct(s.base.hits, s.base.batons));
  add('  from the baseline (8 m)', s => `${pct(s.base.lineHits, s.base.line)} (${s.base.line})`);
  add('  from an advantage line', s => `${pct(s.base.advHits, s.base.adv)} (${s.base.adv})`);
  add('took two base kubbs', s => pct(s.base.doubles, s.base.batons));
  out.push(['The king']);
  add('king shots', s => String(s.king.shots));
  add('toppled the king', s => pct(s.king.hits, s.king.shots));
  out.push(['Throwing kubbs in']);
  add('kubbs thrown in (I)', s => String(s.ink.I));
  add('rethrown (R) per kubb thrown in', s => pct(s.ink.R, s.ink.I));
  add('punishment kubbs (P) per kubb thrown in', s => pct(s.ink.P, s.ink.I));
  add('rescues (Q) per kubb thrown in', s => pct(s.ink.Q, s.ink.I));
  add('came to rest on another (N) per kubb', s => pct(s.ink.N, s.ink.I));
  return out;
}

export function readFolder(dir, analyze) {
  const s = blank();
  for (const f of readdirSync(dir).sort()) {
    if (!f.endsWith('.txt')) continue;
    addGame(s, analyze(readFileSync(join(dir, f), 'utf8')));
  }
  return s;
}

function render(table, names) {
  const w = [0, names[0].length, names[1].length];
  for (const r of table) if (r.length === 3) for (let i = 0; i < 3; i++) if (r[i].length > w[i]) w[i] = r[i].length;
  const lines = [`${''.padEnd(w[0])}  ${names[0].padStart(w[1])}  ${names[1].padStart(w[2])}`];
  for (const r of table) {
    if (r.length === 1) lines.push('', r[0]);
    else lines.push(`${('  ' + r[0]).padEnd(w[0] + 2)}${r[1].padStart(w[1])}  ${r[2].padStart(w[2])}`);
  }
  return lines.join('\n');
}

async function main(argv) {
  const dirs = argv.filter(a => !a.startsWith('--'));
  if (dirs.length !== 2) {
    console.error('usage: node tools/realgames.mjs <real games dir> <game dir> [--json]');
    return 2;
  }
  for (const d of dirs) {
    if (!existsSync(d)) { console.error(`realgames: no folder ${d}`); return 2; }
  }
  const kubb = join(here, '..', 'tests', 'vendor', 'pk-kubb-score', 'kubb.js');
  const { analyze } = await import(pathToFileURL(kubb).href);
  const real = readFolder(resolve(dirs[0]), analyze);
  const game = readFolder(resolve(dirs[1]), analyze);
  if (!real.games || !game.games) { console.error('realgames: a folder has no games'); return 2; }
  if (argv.includes('--json')) console.log(JSON.stringify({ real, game }, null, 1));
  else console.log(render(rows(real, game), ['real games', 'the game']));
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then(c => process.exit(c));
}
