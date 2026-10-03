#!/bin/zsh

# Runs only in the workflow's disposable checkout. Source conflicts fail closed.
set -euo pipefail
cd "$(dirname "$0")/.."
test -f .root

OLD=$(git rev-parse HEAD)
UPSTREAM_URL=https://github.com/Lakr233/libghostty-spm.git
# Keep upstream tags out of our tag namespace: the fork has its own versions.
TAG=$(git ls-remote --tags --refs "$UPSTREAM_URL" | python3 -c 'import re, sys; tags=[m.group(1) for line in sys.stdin if (m := re.search(r"refs/tags/(\d+\.\d+\.\d+)$", line.strip()))]; print(max(tags, key=lambda tag: tuple(map(int, tag.split(".")))))')
git fetch --no-tags "$UPSTREAM_URL" "refs/tags/$TAG"
UPSTREAM=$(git rev-parse 'FETCH_HEAD^{commit}')
if git merge-base --is-ancestor "$UPSTREAM" HEAD; then
    echo "[+] upstream $TAG is already included; keeping the fork ahead"
    echo "changed=false" >> "$GITHUB_OUTPUT"
    exit 0
fi

# Only the two generated fields bypass textual conflicts. Structural manifest
# changes still go through merge-file; every source conflict stops the rebase.
DRIVER="$RUNNER_TEMP/merge-release-manifest.py"
cp Script/merge-release-manifest.py "$DRIVER"
git config merge.release-manifest.driver "python3 '$DRIVER' %O %A %B"
git config merge.asset-revision.driver true
mkdir -p .git/info
printf '%s\n' 'Package.swift merge=release-manifest' 'Ghostty.build merge=asset-revision' >> .git/info/attributes
git config user.name 'github-actions[bot]'
git config user.email 'github-actions[bot]@users.noreply.github.com'
git rebase "$UPSTREAM"

# Reuse a binary only when all of its native source/toolchain/build inputs match.
# Otherwise choose a fresh tag; never overwrite a published XCFramework.
NATIVE_PATHS=(Ghostty.ref Patches build.sh Script/build-ghostty.sh Script/merge-xcframework.sh
    Script/build.sh Script/build-platform.sh Script/apply-patches.sh Script/prepare-zig-lib.sh Script/support .github/workflows/build.yml)
if git diff --quiet "$OLD" HEAD -- "${NATIVE_PATHS[@]}"; then
    if git cat-file -e "${OLD}:Ghostty.build" 2>/dev/null; then
        git show "${OLD}:Ghostty.build" > Ghostty.build
    else
        echo 1 > Ghostty.build
    fi
else
    REF=$(tr -d '[:space:]' < Ghostty.ref)
    git fetch --tags origin
    PREFIX="upstream.${REF[1,12]}"
    NEXT=$(git tag --list "$PREFIX*" | python3 -c 'import re, sys; prefix=sys.argv[1]; builds=[int(m.group(1) or 1) for line in sys.stdin if (m := re.fullmatch(re.escape(prefix)+r"(?:-([0-9]+))?", line.strip()))]; print(max(builds, default=0)+1)' "$PREFIX")
    echo "$NEXT" > Ghostty.build
fi

# This candidate is never promoted before release.yml replaces and verifies
# the temporary manifest against the selected binary and tests all platforms.
git show "${OLD}:Package.swift" > "$RUNNER_TEMP/previous-manifest.swift"
python3 - "$RUNNER_TEMP/previous-manifest.swift" <<'PY'
import pathlib, re, sys
old = pathlib.Path(sys.argv[1]).read_text()
url = re.search(r'url: "([^"\n]+/GhosttyKit\.xcframework\.zip)"', old)[1]
checksum = re.search(r'checksum: "([0-9a-f]{64})"', old)[1]
path = pathlib.Path('Package.swift')
text = path.read_text()
text = re.sub(r'url: "(?:__DOWNLOAD_URL__|https://github.com/[^"\n]+/releases/download/[^"\n]+/GhosttyKit\.xcframework\.zip)"', lambda _: f'url: "{url}"', text)
text = re.sub(r'checksum: "(?:__CHECKSUM__|[0-9a-f]{64})"', lambda _: f'checksum: "{checksum}"', text)
path.write_text(text)
PY
git add Package.swift Ghostty.build
if ! git diff --cached --quiet; then
    git commit -m 'build: select binary for rebased native sources'
fi
./Script/check-licenses.sh
printf 'changed=true\nprevious=%s\nupstream=%s\n' "$OLD" "$UPSTREAM" >> "$GITHUB_OUTPUT"
echo "[+] prepared upstream $TAG ($UPSTREAM) over $OLD"
