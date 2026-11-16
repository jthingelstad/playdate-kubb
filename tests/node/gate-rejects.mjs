// Checks that the notation gate rejects what it must: every game in
// tests/fixtures/bad fails (the four 2026-11-22-1200 to -1500 games for
// their positions only), and a $PK_KUBB_SCORE that points nowhere fails loudly.
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
check(/grammar: line 9/.test(bad.stdout), 'grammar error is reported with its line');
check(/winner is Team A, \[Win\] header says Team B/.test(bad.stdout), 'winner mismatch is reported');
// positions (the game writes them since 2026-11-16)
check(/position 5\.20,3\.00 after "c:2I" is off the pitch/.test(bad.stdout), 'a position off the pitch is reported');
check(/"c:2I" has 3 positions for 2 kubbs/.test(bad.stdout), 'more positions than the token counts is reported');
check(/"c:-" has 1 positions for 0 kubbs/.test(bad.stdout), 'positions on a miss are reported');
check(/kept as a comment/.test(bad.stdout), 'positions that do not parse are reported');
check(/reads differently in kubb\.js with its positions taken out/.test(bad.stdout), 'a reading changed by positions is reported');

const missing = run([], { ...process.env, PK_KUBB_SCORE: join(here, 'no-such-pk-kubb-score') });
check(missing.status === 2 && /pk-kubb-score not found/.test(missing.stderr), 'missing pk-kubb-score fails loudly');

console.log(`gate-rejects: ${passed} passed, ${failed} failed`);
process.exitCode = failed ? 1 : 0;
