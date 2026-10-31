// Used by personal-release.yml. Rewires a CI build so it updates from THIS
// repository's GitHub releases instead of the upstream Readest servers.
//   usage: node .github/scripts/personal-stamp.mjs <version>
//   env:   REPO    owner/repo, e.g. "alice/readest"
//          PUBKEY  your Tauri updater public key (from `tauri signer generate`)
// Nothing here is committed; it only edits the CI checkout before building.
import fs from 'node:fs';

const [version] = process.argv.slice(2);
const { REPO, PUBKEY } = process.env;
if (!version || !REPO || !PUBKEY) {
  console.error('usage: REPO=owner/repo PUBKEY=... node personal-stamp.mjs <version>');
  process.exit(1);
}

const app = 'apps/readest-app';
const base = `https://github.com/${REPO}/releases/latest/download`;

const edit = (file, fn) => {
  const before = fs.readFileSync(file, 'utf8');
  const after = fn(before);
  if (after === before) throw new Error(`personal-stamp: no change applied to ${file}`);
  fs.writeFileSync(file, after);
  console.log(`stamped ${file}`);
};

// 1. App version (tauri.conf.json reads it from package.json).
edit(`${app}/package.json`, (s) => {
  const j = JSON.parse(s);
  j.version = version;
  return JSON.stringify(j, null, 2) + '\n';
});

// 2. Desktop updater: trust your key, check your releases.
edit(`${app}/src-tauri/tauri.conf.json`, (s) => {
  const j = JSON.parse(s);
  j.plugins.updater.pubkey = PUBKEY;
  j.plugins.updater.endpoints = [`${base}/latest.json`];
  return JSON.stringify(j, null, 2) + '\n';
});

// 3. In-app update code paths (Android, portable/AppImage installs, changelog).
edit(`${app}/src/services/constants.ts`, (s) =>
  s
    .replace(
      /^const LATEST_DOWNLOAD_BASE_URL = .*$/m,
      `const LATEST_DOWNLOAD_BASE_URL = '${base}';`,
    )
    .replace(
      /^export const READEST_NIGHTLY_UPDATER_FILE = .*$/m,
      `export const READEST_NIGHTLY_UPDATER_FILE = '${base}/latest.json';`,
    )
    .replace(
      /(export const READEST_UPDATER_PUBKEY =\s*)'[^']*'/,
      (_, head) => `${head}'${PUBKEY}'`,
    ),
);
