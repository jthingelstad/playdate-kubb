// Planet Kubb Notation 2: the canonical form of a game.
//
// canonicalize(text) reads a game in the lenient form and writes it in the
// canonical form: one spelling of each thing, so that two records of the same
// game are the same bytes. It works token by token. It never merges, splits
// or reorders the tokens of a turn line, and it never invents data. What it
// cannot carry into the canonical form it reports.
//
// The result always parses with the grammar's CanonicalGame rule, and the
// canonical form of a canonical file is the file itself.
import { parse } from './notation-parser.js';

// The header keys the notation defines, in their canonical order. The grammar
// has the same list; the conformance suite checks that they agree.
const KEYS = ['Notation', 'Event', 'Location', 'Start', 'Event date', 'End', 'Duration',
  'Surface', 'Rules', 'Base kubbs', 'Batons', 'Opening', 'Team A', 'Team A Players',
  'Team B', 'Team B Players', 'First', 'Win', 'Scored by', 'Entered by', 'Video',
  'Player note', 'Video offset', 'Stats', 'Scoresheet', 'Source'];
const LINES = ['@a', '@b', '~a', '~b', '^a', '^b', '*a', '*b'];
const HOW = { s: 0, null: 1, p: 2 };
const CODE = { 'miss': '-', 'king-miss': '=', 'king': 'K', 'unthrown': 'X', 'illegal-king': 'E',
  'illegal-throw': 'Z', 'win': 'W', 'resign': 'G' };

function byCodePoint(a, b) {
  const x = Array.from(a), y = Array.from(b);
  for (let i = 0; i < x.length && i < y.length; i++) {
    const d = x[i].codePointAt(0) - y[i].codePointAt(0);
    if (d) return d;
  }
  return x.length - y.length;
}

function headerOrder(a, b) {
  const i = KEYS.indexOf(a), j = KEYS.indexOf(b);
  if (i >= 0 || j >= 0) return (i < 0 ? KEYS.length : i) - (j < 0 ? KEYS.length : j);
  return byCodePoint(a, b);
}

class CannotWrite extends Error {}

const place = (a, b) => a.at[0] - b.at[0] || a.at[1] - b.at[1];
const number = (v, cells) => (cells ? String(v) : v.toFixed(2));
const at = (p, cells) => `${number(p[0], cells)},${number(p[1], cells)}`;

function counted(n, code, most, where) {
  if (n === 0) return '';
  if (n > most) throw new CannotWrite(`${where}: a count before ${code} goes up to ${most}, and this is ${n}.`);
  return (n === 1 ? '' : n) + code;
}

function kubbs(k, where) {
  let body = ['I', 'R', 'P', 'Y', 'Q'].map(c => counted(k[c], c, 10, where)).join('') + counted(k.N, 'N', 5, where);
  // No kubbs thrown, and one of them took the king: the canonical form has
  // no way to say that, and dropping the E would change who won.
  if (body === '' && k.illegalKing) throw new CannotWrite(`${where}: ${k.text} says a kubb thrown in took the king, and counts no kubbs.`);
  if (body === '') body = '0I';
  else if (k.illegalKing) body += 'E';
  return (k.player ? k.player + ':' : '') + body;
}

function baton(b, where) {
  let body;
  if (b.kind === 'hit') {
    body = counted(b.field, 'F', 10, where) + counted(b.base, 'B', 10, where);
    // 0F is a baton that felled nothing: a miss. With an E it says a felled
    // kubb took the king and counts none felled, which cannot be carried.
    if (body === '' && b.illegalKing) throw new CannotWrite(`${where}: ${b.text} says a felled kubb took the king, and counts none felled.`);
    body = body === '' ? '-' : body + (b.illegalKing ? 'E' : '');
  } else body = CODE[b.kind];
  return (b.player ? b.player + ':' : '') + body;
}

// Gather entries that share a cell (and a mark) into one entry with a count.
function gathered(entries, cells, where) {
  if (!cells) return entries;
  const out = [];
  for (const e of entries) {
    const same = out.find(o => place(o, e) === 0 && o.mark === e.mark);
    if (same) same.count += e.count; else out.push({ ...e });
  }
  for (const e of out) {
    if (e.count > 10) throw new CannotWrite(`${where}: a count goes up to 10, and cell ${at(e.at, true)} has ${e.count}.`);
  }
  return out;
}

const standing = (e, cells) => (e.count > 1 ? e.count + 'x' : '') + at(e.at, cells) + (e.mark || '');

function positionLines(turn, where) {
  const out = [];
  const lines = [...turn.lines].sort((a, b) => LINES.indexOf(a.mark + a.half) - LINES.indexOf(b.mark + b.half));
  // How each pitch line's thrown kubbs were reordered, for its lay line to follow.
  const order = {};
  for (const l of lines) {
    const cells = l.precision === 'cell';
    let words;
    if (l.mark === '@') {
      const entries = gathered(l.entries, cells, where).map((e, i) => ({ ...e, i }));
      const from = l.entries.filter(e => e.mark === null);
      entries.sort((a, b) => HOW[a.mark] - HOW[b.mark] || place(a, b) || a.i - b.i);
      if (!cells) order[l.half] = entries.filter(e => e.mark === null).map(e => from.indexOf(l.entries[e.i]));
      words = entries.map(e => standing(e, cells));
    } else if (l.mark === '~') {
      words = order[l.half].map(i => l.entries[i].ends.map(p => at(p, false)).join('/'));
    } else if (l.mark === '^') {
      words = l.entries.map(p => (p ? at(p, false) : '-'));
    } else {
      words = l.entries.map((word, i) => {
        if (word === null) return '-';
        // Field kubbs first, then base kubbs, as in the baton's token.
        const field = [], base = [];
        let left = turn.batons[i].field || 0;
        for (const e of word) {
          const f = Math.min(left, e.count);
          left -= f;
          if (f) field.push({ at: e.at, count: f, mark: null });
          if (e.count - f) base.push({ at: e.at, count: e.count - f, mark: null });
        }
        return [field, base].flatMap(g => gathered(g, cells, where).sort(place).map(e => standing(e, cells))).join('+');
      });
    }
    out.push(l.mark + l.half + ' ' + words.join(' '));
  }
  return out;
}

// Returns { text, reports }: the canonical text, and a line for each thing
// that changed meaning or could not be carried. Throws the grammar's
// SyntaxError when the input is not valid notation, and an Error when it is
// valid but has no canonical form (a turn whose position lines disagree, or a
// count over the canonical limit).
export function canonicalize(text) {
  const game = parse(text);
  const reports = [];
  const out = [];

  const headers = new Map();
  for (const h of game.headers) {
    if (h.key === 'Notation') continue;
    if (headers.has(h.key)) reports.push(`The header ${h.key} is there twice; kept the last.`);
    headers.set(h.key, h.value);
  }
  out.push('[Notation "2"]');
  for (const key of [...headers.keys()].sort(headerOrder)) {
    out.push(`[${key} "${headers.get(key).replace(/[\\"]/g, c => '\\' + c)}"]`);
  }
  if (game.turns.length) out.push('');

  game.turns.forEach((t, i) => {
    const where = `Turn ${i + 1}`;
    if (t.issues.length) throw new CannotWrite(`${where}: ${t.issues[0].message}`);
    if (t.number !== null && t.number !== i + 1) reports.push(`${where}: it was numbered ${t.number}.`);
    const tokens = t.inkasts.map(k => kubbs(k, where));
    if (t.advantage) {
      tokens.push('A');
      if (t.advantage.meters !== null) reports.push(`${where}: dropped the number in ${t.advantage.text}; the canonical form writes A.`);
      if (t.advantage.legacy) reports.push(`${where}: dropped the 2012 marker ${t.advantage.legacy}; the canonical form writes A.`);
    }
    for (const b of t.batons) tokens.push(baton(b, where));
    // A comment in parentheses moves into the note.
    const note = [t.note, ...t.comments].filter(Boolean).join('; ');
    out.push(`${i + 1}. ${tokens.join(' ')}${note ? ' # ' + note : ''}`);
    out.push(...positionLines(t, where));
  });

  const canonical = out.join('\n') + '\n';
  // The writer and the grammar must agree on what canonical is.
  parse(canonical, { startRule: 'CanonicalGame' });
  return { text: canonical, reports };
}

// Whether a text is in the canonical form already.
export function isCanonical(text) {
  try { parse(text, { startRule: 'CanonicalGame' }); return true; } catch { return false; }
}
