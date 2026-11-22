// Checks that the notation gate rejects what it must: every game in
// tests/fixtures/bad fails (each a canonical Notation 2 game but for one fault:
// a grammar error, the wrong winner, a point off the pitch, the engine's old
// "(@ ...)" positions comment, a felled word short of its baton's kubbs, and a
// point that does not round-trip to what the sheet kept), and a $PK_KUBB_SCORE
// that points nowhere fails loudly.
import { spawnSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const gate = join(here, 'notation-gate.mjs');
const badDir = join(here, '..', 'fixtures', 'bad');
let failed = 0, passed = 0;
const check = (ok, what) => { if (ok) passed++; else { failed++; console.log(`FAIL ${what}`); } };

const run = (args, env = process.env) => spawnSync(process.execPath, [gate, ...args], { encoding: 'utf8', env });

const bad = run([badDir, '--allow-warnings']);
check(bad.status === 1, `gate exits 1 on ${badDir} even with --allow-warnings (got ${bad.status})`);
for (const f of readdirSync(badDir).filter(f => f.endsWith('.txt'))) {
  check(bad.stdout.includes(`FAIL ${f}`), `gate rejects bad/${f}`);
}
check(/grammar \(canonical form\): line 10/.test(bad.stdout), 'grammar error is reported with its line');
check(/winner is Team A, \[Win\] header says Team B/.test(bad.stdout), 'winner mismatch is reported');
// Notation 2's position lines and the canonical form
check(/line 13, column 14: Expected position/.test(bad.stdout), 'a point off the pitch is reported');
check(/1300-old-positions-comment\.txt\n\s+error: grammar \(canonical form\)/.test(bad.stdout), 'the old (@ ...) comment is not canonical');
check(/Word 1 of the felled line has 1 kubb, and baton 1 \(2F\) felled 2/.test(bad.stdout), 'a felled word short of its kubbs is reported');
check(/round trip: turn 3: pitch line: 3\.50,2\.00 .* is not a place the sheet kept/.test(bad.stdout), 'a point that does not round-trip is reported');
check(/reads differently in kubb\.js with its position lines taken out/.test(bad.stdout), 'a reading changed by position lines is reported');

const missing = run([], { ...process.env, PK_KUBB_SCORE: join(here, 'no-such-pk-kubb-score') });
check(missing.status === 2 && /pk-kubb-score not found/.test(missing.stderr), 'missing pk-kubb-score fails loudly');

console.log(`gate-rejects: ${passed} passed, ${failed} failed`);
process.exitCode = failed ? 1 : 0;
