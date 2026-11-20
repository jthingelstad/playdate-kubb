// source/core is the Kubb Engine's core/ (jthingelstad/kubb-engine) at a tagged
// release, copied byte for byte, and source/engine/version.lua is the engine's
// version.lua at the same tag (tw.engine.version: the version the title shows
// beside the game's, device/version). Never edit either: fix behaviour in the
// engine, tag a release there, then sync here.
//
//   node tools/vendor-engine.mjs sync [vX.Y.Z]   copy core/ and version.lua at the tag
//                                                (default: the tag in engine-core.json)
//                                                and write engine-core.json
//   node tools/vendor-engine.mjs check           fail if source/core or
//                                                source/engine/version.lua differs
//                                                from engine-core.json
//
// The engine is read from a checkout through git, at the tag and never from its
// working tree: $KUBB_ENGINE, else ../kubb-engine beside this repository. sync
// refuses a tag whose files disagree with that tag's engine.json. check always
// compares source/core with engine-core.json (the file list and a sha256 per
// file), and when an engine checkout is present it also compares engine-core.json
// with the tag's engine.json and commit; without one (CI) it says so and passes on
// the first part alone.
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dest = path.join(root, 'source', 'core');
const manifestPath = path.join(root, 'engine-core.json');
const PREFIX = 'core/';
// the engine's version.lua, vendored beside the core
const VERSION_FILE = 'version.lua';
const versionDest = path.join(root, 'source', 'engine', VERSION_FILE);

const sha = (buf) => createHash('sha256').update(buf).digest('hex');
const fail = (msg) => {
  console.error(msg);
  process.exit(1);
};

function engineDir() {
  const dir = path.resolve(process.env.KUBB_ENGINE || path.join(root, '..', 'kubb-engine'));
  return fs.existsSync(path.join(dir, '.git')) ? dir : null;
}

const git = (dir, args, opts = {}) =>
  execFileSync('git', ['-C', dir, ...args], { maxBuffer: 64 << 20, ...opts });

// The tag's commit, its engine.json and its core/ files ({ 'core/x.lua': Buffer }),
// and its version.lua (a Buffer).
function readTag(dir, tag) {
  let commit;
  try {
    commit = git(dir, ['rev-parse', '--verify', '--quiet', `refs/tags/${tag}^{commit}`], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    fail(`kubb-engine at ${dir} has no tag ${tag} (git fetch --tags there)`);
  }
  const engine = JSON.parse(git(dir, ['show', `${commit}:engine.json`], { encoding: 'utf8' }));
  const names = git(dir, ['ls-tree', '-r', '--name-only', commit, '--', 'core'], { encoding: 'utf8' })
    .split('\n')
    .filter(Boolean)
    .sort();
  const files = {};
  for (const n of names) files[n] = git(dir, ['show', `${commit}:${n}`]);
  let version = null;
  try {
    version = git(dir, ['show', `${commit}:${VERSION_FILE}`], { stdio: ['ignore', 'pipe', 'ignore'] });
  } catch {
    // a tag from before the engine had a version.lua
  }
  return { commit, engine, files, version };
}

// What engine.json says core/ and version.lua hold, keyed by path.
const engineCore = (engine) =>
  Object.fromEntries(
    Object.entries(engine.files || {})
      .filter(([f]) => f.startsWith(PREFIX) || f === VERSION_FILE)
      .sort(([a], [b]) => (a < b ? -1 : 1)),
  );

// Differences between two { path: sha256 } maps, as lines.
function compare(have, want, haveName, wantName) {
  const bad = [];
  for (const f of Object.keys(want)) {
    if (!(f in have)) bad.push(`${f} is in ${wantName} but not in ${haveName}`);
    else if (have[f] !== want[f]) bad.push(`${f} differs from ${wantName}`);
  }
  for (const f of Object.keys(have)) if (!(f in want)) bad.push(`${f} is in ${haveName} but not in ${wantName}`);
  return bad;
}

function vendored() {
  const out = {};
  for (const f of fs.readdirSync(dest).sort()) {
    const p = path.join(dest, f);
    if (fs.statSync(p).isDirectory()) out[`${PREFIX}${f}/`] = 'a directory';
    else out[PREFIX + f] = sha(fs.readFileSync(p));
  }
  if (fs.existsSync(versionDest)) out[VERSION_FILE] = sha(fs.readFileSync(versionDest));
  return out;
}

const readManifest = () => JSON.parse(fs.readFileSync(manifestPath, 'utf8'));

const mode = process.argv[2];
if (mode === 'sync') {
  const dir = engineDir();
  if (!dir) fail('no kubb-engine checkout: set KUBB_ENGINE or clone it beside this repository');
  const tag = process.argv[3] || readManifest().tag;
  if (!/^v\d+\.\d+\.\d+$/.test(tag || '')) fail(`${tag} is not a release tag (vX.Y.Z)`);
  const { commit, engine, files, version } = readTag(dir, tag);
  if (`v${engine.version}` !== tag) fail(`${tag}'s engine.json says version ${engine.version}`);
  if (!version) fail(`${tag} has no ${VERSION_FILE}: the title shows the engine's version from it`);
  const hashes = Object.fromEntries(Object.entries(files).map(([f, b]) => [f, sha(b)]));
  hashes[VERSION_FILE] = sha(version);
  const bad = compare(hashes, engineCore(engine), `${tag}'s core/`, `${tag}'s engine.json`);
  if (Object.keys(hashes).some((f) => f.slice(PREFIX.length).includes('/')))
    bad.push(`${tag}'s core/ has a subfolder; this script copies a flat core/`);
  if (bad.length) fail(`refusing ${tag}:\n  ` + bad.join('\n  '));
  fs.rmSync(dest, { recursive: true, force: true });
  fs.mkdirSync(dest, { recursive: true });
  for (const [f, b] of Object.entries(files)) fs.writeFileSync(path.join(dest, f.slice(PREFIX.length)), b);
  fs.mkdirSync(path.dirname(versionDest), { recursive: true });
  fs.writeFileSync(versionDest, version);
  const manifest = {
    source: 'jthingelstad/kubb-engine core/',
    tag,
    version: engine.version,
    commit,
    files: hashes,
  };
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
  console.log(`vendored kubb-engine ${tag} (${commit.slice(0, 7)}): ${Object.keys(files).length} files in source/core and source/engine/${VERSION_FILE}`);
} else if (mode === 'check') {
  const m = readManifest();
  const bad = compare(vendored(), m.files || {}, 'source/core', 'engine-core.json');
  if (bad.length) fail('source/core or source/engine does not match engine-core.json (never edit them; make vendor-sync):\n  ' + bad.join('\n  '));
  const dir = engineDir();
  if (!dir) {
    console.log(`source/core and source/engine match engine-core.json (kubb-engine ${m.tag}, ${Object.keys(m.files).length} files); no kubb-engine checkout, so not checked against the tag`);
  } else {
    const { commit, engine } = readTag(dir, m.tag);
    const more = compare(m.files, engineCore(engine), 'engine-core.json', `${m.tag}'s engine.json`);
    if (commit !== m.commit) more.push(`${m.tag} is ${commit.slice(0, 7)} in kubb-engine, engine-core.json says ${m.commit.slice(0, 7)}`);
    if (engine.version !== m.version) more.push(`${m.tag}'s engine.json says version ${engine.version}, engine-core.json ${m.version}`);
    if (more.length) fail('engine-core.json does not match kubb-engine:\n  ' + more.join('\n  '));
    console.log(`source/core and source/engine match kubb-engine ${m.tag} (${m.commit.slice(0, 7)}, ${Object.keys(m.files).length} files)`);
  }
} else {
  console.error('usage: node tools/vendor-engine.mjs sync [vX.Y.Z] | check');
  process.exit(2);
}
