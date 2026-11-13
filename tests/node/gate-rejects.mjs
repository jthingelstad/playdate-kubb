// Checks that the notation gate rejects what it must: every game in
// tests/fixtures/bad fails, and a missing pk-kubb-score fails loudly.
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

const missing = run([], { ...process.env, PK_KUBB_SCORE: join(here, 'no-such-pk-kubb-score') });
check(missing.status === 2 && /pk-kubb-score not found/.test(missing.stderr), 'missing pk-kubb-score fails loudly');

console.log(`gate-rejects: ${passed} passed, ${failed} failed`);
process.exitCode = failed ? 1 : 0;
