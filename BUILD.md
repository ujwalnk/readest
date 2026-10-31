# Personal Readest build

This repository is a personal fork of [Readest](https://github.com/readest/readest) with two changes:

1. **Premium unlock patch.** The Plus/Pro/Lifetime checks that gate local features are switched off, so those features work without a subscription.
2. **Personal release pipeline.** A GitHub Actions workflow builds Linux, Windows, macOS and Android installers on every push, publishes them to this repo's GitHub Releases, and the installed apps update themselves from those releases.

Readest is licensed under the AGPL-3.0, and its maintainer has said users are free to build and modify it. This is for personal use. If you ever distribute a modified build to other people, the AGPL requires you to make the corresponding source code available to them, and the license notices in the code must stay intact.

---

## What the premium unlock patch changes

One file: `apps/readest-app/src/utils/access.ts`.

Almost every premium check in the app goes through a single function, `isCustomizationAllowed()`. The patch makes it always return `true`:

```ts
export const isCustomizationAllowed = (
  _plan: UserPlan,
  _customizationPurchased: boolean,
): boolean => true;
```

This unlocks: third-party cloud sync (WebDAV / Google Drive / S3), offline TTS audio downloads, Audiobookshelf offline downloads, Nearby BookDrop pairing, custom translators and dictionaries (your own LLM or DeepL key), custom TTS services, and Send-to-Readest email-in.

**What it does not unlock:** Readest's own hosted services ("Readest Voice" TTS and the hosted DeepL proxy). Their plan and quota limits are enforced on Readest's servers, so no client-side change can unlock them.

An existing unit test (`src/__tests__/utils/customization-access.test.ts`) expects free users to be denied, so it fails after the patch. That is expected.

---

## How the release pipeline works

Files involved:

| File | Purpose |
| --- | --- |
| `.github/workflows/personal-release.yml` | The build and release workflow. The only workflow in this repo. |
| `.github/scripts/personal-stamp.mjs` | Run during each CI build. Sets the build version and points the app's updater at *this* repository's releases and at your signing key. It edits the CI checkout only; nothing is committed. |

What happens on every push to `main`/`master` (or when started manually):

1. A release is created on GitHub, tagged like `v0.12.16-2026103107-run5`, marked as a **pre-release**.
2. Four builds run in parallel: Linux (x86_64), Windows (x64 installer), macOS (universal), Android (arm64 APK). Each uploads its files to the release.
3. A final step adds the Android entry to `latest.json` (the file the in-app updater reads) and uploads the changelog.
4. If every platform succeeded, the release is promoted from pre-release to **latest**. If anything failed it stays a pre-release, so a half-finished build is never offered as an update.

Build versions look like `0.12.16-2026103107` (package version, then UTC date and hour). This is the same scheme Readest's own nightly builds use, and the app already knows how to compare them. Two builds in the same UTC hour get the same version, so the second one is not offered as an update to the first (you can still install it manually).

> **A release takes a long time.** Expect anywhere from **30 minutes to 1.5 hours** from push to published release, depending on caching and runner load. The first run is the slowest, because nothing is cached yet. Android and Linux are usually the slowest jobs.

---

## Setting it up from scratch

### 1. Fork and clone

1. On GitHub, fork `readest/readest` to your own account.
2. Clone your fork:

   ```bash
   git clone https://github.com/<you>/readest.git
   cd readest
   ```

   Plain `git clone` is enough. You do **not** need `--recurse-submodules`, because GitHub's build runners fetch the submodules themselves (`foliate-js`, `tauri`, and others, listed in `.gitmodules`). Do not build from a ZIP download of the source, because ZIPs leave the submodule folders and the `patches/` folder empty or missing.

   If you want to merge upstream releases later (see below), avoid `--depth 1`, or run `git fetch --unshallow` once.

### 2. Add the files

Copy these into the repo, keeping the same paths:

- `apps/readest-app/src/utils/access.ts` (the patched file)
- `.github/workflows/personal-release.yml`
- `.github/scripts/personal-stamp.mjs`

Delete **every other file** in `.github/workflows/`. The upstream workflows need Readest's private secrets, are hardcoded to the upstream repository, and would fail or waste Actions minutes on every push. The rest of `.github/` (issue templates, `dependabot.yml`, `FUNDING.yml`) is harmless and can stay or go.

### 3. Create the update-signing key

The app only installs an update if it is signed with a key matching the public key built into the app. You need your own pair. This needs Node.js (nothing else; pnpm is not required). Run it **outside** the repo folder:

```bash
npx @tauri-apps/cli@2 signer generate -w personal.key
```

Choose a password (it can be empty). This creates:

- `personal.key`: the **private** key. Secret. Never commit it.
- `personal.key.pub`: the **public** key.

Keep both files, and the password, somewhere safe outside the repo (a password manager is ideal). If you lose the private key you can make a new pair, but apps already installed will not accept updates signed with it; you would reinstall once.

### 4. Create the Android signing keystore

Android refuses to update an app if the new APK is signed with a different key than the installed one, so you need one permanent key. This needs Java's `keytool` (install any JDK, for example from adoptium.net). Again, run it outside the repo:

```bash
keytool -genkeypair -v -keystore release.jks -alias readest -keyalg RSA -keysize 2048 -validity 10000
```

- Pick a password. A random one is fine, since it is only ever read from a GitHub secret (`openssl rand -hex 16` makes one; minimum 6 characters).
- Enter it when asked for the **keystore password**, then again to confirm.
- Answer the name/organisation questions however you like, or press Enter to skip them.
- When it asks for the **key password**, press Enter to reuse the keystore password. The workflow has a single password field and uses it for both, so they must match.
- Type `yes` to confirm.

Convert the file to text for GitHub:

- macOS: `base64 -i release.jks | pbcopy`
- Linux: `base64 -w0 release.jks`
- Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.jks"))`

Back up `release.jks` and its password. **Do not commit the `.jks` file.**

### 5. Add the GitHub secrets

In your repo: **Settings → Secrets and variables → Actions → Secrets** (not Variables) → **New repository secret** (not Environment secret). Names must match exactly:

| Secret | Value |
| --- | --- |
| `TAURI_SIGNING_PRIVATE_KEY` | contents of `personal.key` |
| `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` | the password from step 3 |
| `TAURI_UPDATER_PUBKEY` | contents of `personal.key.pub` |
| `ANDROID_KEY_BASE64` | the base64 text from step 4 |
| `ANDROID_KEY_ALIAS` | `readest` (or the alias you used) |
| `ANDROID_KEY_PASSWORD` | the keystore password from step 4 |

Paste file contents exactly, with no added quotes. If the three `ANDROID_KEY_*` secrets are missing, the build still works but signs the APK with a throwaway key each run (you will see a warning), and every update would require uninstalling first.

### 6. Enable Actions and permissions

- On a fork, open the **Actions** tab and click the button to enable workflows (GitHub disables them on forks by default).
- **Settings → Actions → General → Workflow permissions** → choose **Read and write permissions**.

### 7. Run it

Push to `main`/`master`, or start it by hand: **Actions → Personal Release → Run workflow** (pick the branch, click the green button). The workflow file must already be on that branch for the button to appear.

When it finishes, the installers are under **Releases**. Install a build from your own releases once; from then on the app finds updates in your releases. Builds installed from Readest's official releases trust Readest's key and will never accept yours.

### Things to know

- macOS and Windows builds are not code-signed by Apple/Microsoft, so expect Gatekeeper/SmartScreen warnings.
- The Linux build uses Readest's CEF runtime and is the heaviest.
- If one platform fails, the others still finish and upload. Open the failed job, copy the red error lines, and fix or ask for help. The release stays a pre-release until a full successful run.

---

## When Readest publishes a new release

Goal: bring the upstream changes into this repo, re-apply the premium unlock patch, and let the pipeline build it.

### 1. Pull in upstream

Once, add upstream as a remote:

```bash
git remote add upstream https://github.com/readest/readest.git
```

Then, each time:

```bash
git checkout main
git fetch upstream
git merge upstream/main
```

(Alternatively use GitHub's **Sync fork** button on your fork's page, then `git pull`.)

Git may report conflicts. The files most likely to conflict are `apps/readest-app/src/utils/access.ts` (upstream changed the functions around the patch) and anything under `.github/workflows/` (upstream edited a workflow you deleted). Resolve like this:

- **Deleted upstream workflows come back after the merge.** Delete every file in `.github/workflows/` except `personal-release.yml` again.
- **`access.ts`:** take upstream's version of the file (`git checkout --theirs apps/readest-app/src/utils/access.ts`), then re-apply the patch in step 2 or 3.

If the merge becomes messy, it is fine to take upstream's files wholesale, and re-apply the small patch afterwards.

### 2. Re-apply the premium unlock patch with Claude (recommended)

Upstream may rename or restructure the premium checks, so ask Claude to inspect the new code rather than pasting the old patch blindly.

1. From the repo root, generate a source-only context ZIP:

   ```bash
   ./make_claude_context.sh
   ```

   (Needs `git` and `zip`.) It writes `readest-source-<timestamp>.zip` next to the repo folder, containing the source files only, with no build output or secrets.

2. Upload the ZIP to Claude and use a prompt like this:

   > I've attached the complete Readest source as a ZIP. Readest's maintainer states users are free to build, modify and use it under the AGPL, and this is for my personal build only. Inspect the code, find how the Premium/Plus/Pro/Lifetime/subscription checks restrict local features, and make the premium unlock patch: make the gating checks always allow access so the underlying features work normally. Make no unrelated changes, and preserve the AGPL notices. Last time the change was a single edit in `apps/readest-app/src/utils/access.ts` that makes `isCustomizationAllowed()` always return `true`; check whether that is still where the checks live. Give me the edited files in full so I can copy them in.

3. Copy the edited file(s) Claude returns over the ones in your repo.

### 3. Or apply the patch by hand

If upstream has not moved things, open `apps/readest-app/src/utils/access.ts`, find `isCustomizationAllowed`, and change it to:

```ts
export const isCustomizationAllowed = (
  _plan: UserPlan,
  _customizationPurchased: boolean,
): boolean => true;
```

Search the codebase for any new premium checks that do not go through this function (for example `isPremium`, `userPlan`, `PLAN_REQUIRED`) and check whether anything new needs the same treatment.

### 4. Check, commit, push

```bash
git status                 # no personal.key, release.jks or other secrets listed
git add -A
git commit -m "Merge upstream <version> and re-apply premium unlock patch"
git push
```

The push starts the release pipeline. Watch it under the **Actions** tab, and remember it takes **30 minutes to 1.5 hours**. When the run finishes successfully, the new release becomes "latest" and your installed apps will offer it as an update.

### 5. If a build fails after a merge

A new upstream version can change build requirements (Rust or Node versions, Android NDK version, new submodules, new patch files). The upstream workflow `release.yml` (which you deleted, but can view on Readest's GitHub) shows the versions they currently use. Compare it against `personal-release.yml`, in particular the NDK version, the Linux CEF steps and the action versions, and copy over any changes.

---

## Security checklist

- Never commit `personal.key`, `release.jks` or any password. The public key (`personal.key.pub`) is not secret, but it is also not needed in the repo. All of these live only in GitHub's **Secrets** settings and in your own backups.
- If a private key ever reaches GitHub in a commit, treat it as leaked: generate a new pair, replace the secrets, and reinstall your apps once.
- Keep backups of `personal.key`, `release.jks` and both passwords outside the repo.