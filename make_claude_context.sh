
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Readest source-only Claude context generator
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Error: Run this script inside the Readest repository."
    exit 1
}

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT="${1:-$(dirname "$ROOT_DIR")/readest-source-${TIMESTAMP}.zip}"

case "$OUTPUT" in
    /*) ;;
    *) OUTPUT="$PWD/$OUTPUT" ;;
esac

for tool in git zip; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing required tool: $tool"
        exit 1
    }
done

mkdir -p "$(dirname "$OUTPUT")"

if [[ -e "$OUTPUT" ]]; then
    echo "Error: Output already exists: $OUTPUT"
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

DEST="$WORK/readest-source"
mkdir -p "$DEST"

# ------------------------------------------------------------
# Source extensions to retain
# ------------------------------------------------------------

EXTENSIONS=(
    ts tsx js jsx mjs cjs mts cts
    dart rs swift mm m h
    kt kts java
    css scss sass less
    html htm vue svelte
    json yaml yml toml xml
    sh bash
    proto sql graphql gql
    d.ts
)

# Explicit source/config files without conventional extensions.
SPECIAL_FILES=(
    Dockerfile
    Makefile
    CMakeLists.txt
    .npmrc
    .nvmrc
    .node-version
    .gitmodules
)

# ------------------------------------------------------------
# Excluded directories
# ------------------------------------------------------------

EXCLUDED_DIRS=(
    .git
    .github
    node_modules
    vendor
    dist
    build
    out
    target
    .next
    .cache
    .turbo
    .dart_tool
    .gradle
    Pods
    DerivedData
    coverage
    test-results
    fixtures
    samples
    examples
    docs
    documentation
)

is_excluded() {
    local path="$1"
    local part

    IFS='/' read -ra PARTS <<< "$path"

    for part in "${PARTS[@]}"; do
        for excluded in "${EXCLUDED_DIRS[@]}"; do
            [[ "$part" == "$excluded" ]] && return 0
        done
    done

    return 1
}

is_source_file() {
    local file="$1"
    local name="${file##*/}"

    for special in "${SPECIAL_FILES[@]}"; do
        [[ "$name" == "$special" ]] && return 0
    done

    # TypeScript declaration files.
    [[ "$name" == *.d.ts ]] && return 0

    local ext="${name##*.}"

    for allowed in "${EXTENSIONS[@]}"; do
        [[ "$ext" == "$allowed" ]] && return 0
    done

    return 1
}

# ------------------------------------------------------------
# Collect tracked AND untracked source files
# ------------------------------------------------------------

echo "Collecting source files..."

COUNT=0

while IFS= read -r -d '' file; do

    is_excluded "$file" && continue
    is_source_file "$file" || continue

    source="$ROOT_DIR/$file"
    destination="$DEST/$file"

    [[ -f "$source" ]] || continue

    mkdir -p "$(dirname "$destination")"
    cp "$source" "$destination"

    ((COUNT += 1))

done < <(
    git -C "$ROOT_DIR" ls-files --cached --others --exclude-standard -z
)

# ------------------------------------------------------------
# Add Git metadata
# ------------------------------------------------------------

LOCAL_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD)"
BRANCH="$(git -C "$ROOT_DIR" branch --show-current || true)"

[[ -n "$BRANCH" ]] || BRANCH="Detached HEAD"

UPSTREAM_SHA="Not available"
UPSTREAM_REMOTE="Not found"

while IFS= read -r remote; do
    [[ -n "$remote" ]] || continue

    url="$(git -C "$ROOT_DIR" remote get-url "$remote" 2>/dev/null || true)"

    case "$url" in
        *github.com/readest/readest*|*github.com:readest/readest*)
            UPSTREAM_REMOTE="$remote"

            ref="$(
                git -C "$ROOT_DIR" symbolic-ref \
                    --quiet --short \
                    "refs/remotes/$remote/HEAD" || true
            )"

            if [[ -n "$ref" ]]; then
                UPSTREAM_SHA="$(git -C "$ROOT_DIR" rev-parse "$ref")"
            fi
            break
            ;;
    esac
done < <(git -C "$ROOT_DIR" remote)

cat > "$DEST/SOURCE-INFO.txt" <<EOF
Readest source context
=====================

Official repository:
https://github.com/readest/readest

Local branch:
$BRANCH

Local HEAD:
$LOCAL_SHA

Upstream remote:
$UPSTREAM_REMOTE

Latest locally fetched upstream SHA:
$UPSTREAM_SHA

Generated:
$(date -u '+%Y-%m-%d %H:%M:%S UTC')

Purpose:
Source-code context for analysis and modification of
Premium/subscription restrictions.

This archive contains selected source and configuration files.
It is NOT a complete buildable repository.

No dependencies were installed.
No submodules were initialized.
No source files were modified.
EOF

# ------------------------------------------------------------
# Create ZIP
# ------------------------------------------------------------

echo "Creating ZIP..."

(
    cd "$WORK"
    zip -qr "$OUTPUT" readest-source
)

echo
echo "======================================"
echo " Readest Claude Source Archive Ready"
echo "======================================"
echo
echo "Source files: $COUNT"
echo "Local SHA:    $LOCAL_SHA"
echo "Upstream SHA: $UPSTREAM_SHA"
echo "Archive:      $OUTPUT"
echo "Size:         $(du -h "$OUTPUT" | awk '{print $1}')"
echo
echo "Done!"
