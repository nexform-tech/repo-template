#!/usr/bin/env bash
# Verify the initial-version bootstrap of the reusable release workflow against
# real repositories. It answers the questions that decide the 0.x line:
#
#   - an untagged repository gets `v0.0.0` on its root commit, and its first
#     `feat:` then releases 0.1.0 instead of 1.0.0;
#   - the bootstrap is a no-op once any release tag exists;
#   - the bootstrapped tag is never reported as a release, not even when the whole
#     history is a single commit and the tag sits on HEAD;
#   - `initial-version: ""` keeps semantic-release's own 1.0.0 first release.
#
# The shell that runs is read out of the workflow itself, so this test cannot
# drift from the pipeline. git, node and npx are required, and the first run needs
# network access: semantic-release and js-yaml are fetched through npx, exactly as
# the workflow fetches semantic-release.
#
# The authenticated github.com push cannot work against local repositories, so
# that one line is redirected to a local bare repository and asserted; everything
# else is the real script. The push URL itself is not exercised here.
#
# Usage: scripts/verify-release-bootstrap.sh
set -uo pipefail

workflow=".github/workflows/release.yml"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
work="$tmp/repos"
mkdir -p "$work"
export npm_config_cache="$tmp/npm-cache"

pass=0
fail=0
ok() { echo "ok   - $1"; pass=$((pass + 1)); }
bad() { echo "FAIL - $1"; fail=$((fail + 1)); }
check() { if [[ "$2" == "$3" ]]; then ok "$1 ($3)"; else bad "$1: expected [$3], got [$2]"; fi; }
die() { echo "error: $*" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)" || die "not inside a git repository"
for tool in git node npx; do command -v "$tool" >/dev/null 2>&1 || die "$tool is required"; done
[[ -f "$workflow" ]] || die "$workflow not found"

# --- read the two steps out of the workflow ---------------------------------

npx --yes js-yaml@4 "$workflow" > "$tmp/workflow.json" 2>/dev/null \
  || die "cannot parse $workflow (npx js-yaml failed; is there network access?)"

node - "$tmp/workflow.json" "$tmp" <<'NODE' || die "cannot read the steps from $workflow"
const fs = require('node:fs');
const [file, out] = process.argv.slice(2);
const doc = JSON.parse(fs.readFileSync(file, 'utf8'));
const steps = doc.jobs.release.steps;
for (const [id, name] of [['bootstrap', 'bootstrap.sh'], ['detect', 'detect.sh']]) {
  const step = steps.find((candidate) => candidate.id === id);
  if (!step || typeof step.run !== 'string') {
    console.error(`no step with id "${id}" and a run block`);
    process.exit(1);
  }
  fs.writeFileSync(`${out}/${name}`, step.run);
}
NODE

# Redirect the authenticated push to a local origin, and fail loudly if that line
# ever moves, so the redirect cannot silently stop covering the step.
sed 's|^git push "https://x-access-token.*|git push origin \\|' \
  "$tmp/bootstrap.sh" > "$tmp/bootstrap-local.sh"
grep -q '^git push origin \\$' "$tmp/bootstrap-local.sh" \
  || die "the push in the bootstrap step changed; update this test"

# --- helpers ----------------------------------------------------------------

semantic_release() { npx --yes semantic-release@25 --dry-run --no-ci 2>&1; }
next_version() { grep -oE 'next release version is [0-9]+\.[0-9]+\.[0-9]+' | tail -1; }

# A throwaway repository with a bare origin and the minimal semantic-release
# configuration the commit analysis needs (no GitHub plugin, no token).
new_repo() { # $1 = name
  local dir="$work/$1"
  git init -q --bare "$dir.git"
  git -C "$dir.git" symbolic-ref HEAD refs/heads/main
  git init -q -b main "$dir"
  cd "$dir" || die "cannot enter $dir"
  git config user.email test@example.com
  git config user.name test
  git remote add origin "$dir.git"
  printf '{\n  "branches": ["main"],\n  "plugins": ["@semantic-release/commit-analyzer", "@semantic-release/release-notes-generator"]\n}\n' \
    > .releaserc.json
}

run_bootstrap() { # $1 = initial version, $2 = $GITHUB_OUTPUT file
  : > "$2"
  GITHUB_OUTPUT="$2" INITIAL_VERSION="$1" GITHUB_TOKEN="test-token" \
    GITHUB_SERVER_URL="https://github.com" GITHUB_REPOSITORY="nexform-tech/test-repo" \
    bash "$tmp/bootstrap-local.sh"
}

run_detect() { # $1 = bootstrap tag, $2 = $GITHUB_OUTPUT file
  : > "$2"
  GITHUB_OUTPUT="$2" BOOTSTRAP_TAG="$1" bash "$tmp/detect.sh"
}

# --- an untagged repository starts on the 0.x line --------------------------

echo "== an untagged repository starts on the 0.x line =="
new_repo fresh
git add -A
git commit -qm "chore: initial scaffold"
echo one > file.txt
git add -A
git commit -qm "feat: first feature"
git push -q origin main
root="$(git rev-list --max-parents=0 HEAD | tail -n 1)"

run_bootstrap 0.0.0 "$tmp/out1" >/dev/null
check "the bootstrap tag is on the root commit" "$(git rev-parse v0.0.0)" "$root"
check "the bootstrap tag reaches the remote" "$(git -C "$work/fresh.git" tag -l)" "v0.0.0"
check "step output" "$(cat "$tmp/out1")" "tag=v0.0.0"
check "a second run is a no-op" \
  "$(run_bootstrap 0.0.0 "$tmp/out1b" 2>&1)" \
  "a release tag already exists; nothing to bootstrap"
check "the first feat releases" "$(semantic_release | next_version)" \
  "next release version is 0.1.0"

run_detect v0.0.0 "$tmp/out2" >/dev/null
check "the bootstrap tag is not a release" "$(cat "$tmp/out2")" "new_tag="

git tag v0.1.0
git push -q origin v0.1.0
run_detect v0.0.0 "$tmp/out3" >/dev/null
check "a real release on HEAD is reported" "$(cat "$tmp/out3")" "new_tag=v0.1.0"

# --- a single-commit history ------------------------------------------------

echo "== a single-commit history =="
new_repo single
git add -A
git commit -qm "feat: first feature"
git push -q origin main
run_bootstrap 0.0.0 "$tmp/out4" >/dev/null
check "the bootstrap tag is on HEAD" "$(git rev-parse v0.0.0)" "$(git rev-parse HEAD)"

semantic_release > "$tmp/single.out" 2>&1
rc=$?
if [[ "$rc" -eq 0 ]] && grep -qi "no relevant changes" "$tmp/single.out"; then
  ok "nothing is released in the same run (exit 0)"
else
  bad "the single-commit run exited $rc"
  tail -20 "$tmp/single.out" | sed 's/^/       /'
fi

run_detect v0.0.0 "$tmp/out5" >/dev/null
check "the bootstrap tag is not reported" "$(cat "$tmp/out5")" "new_tag="

# --- an already released repository -----------------------------------------

echo "== an already released repository is never moved =="
new_repo released
git add -A
git commit -qm "chore: initial scaffold"
git tag v2.3.1
git push -q origin main --tags
check "the bootstrap is a no-op" \
  "$(run_bootstrap 0.0.0 "$tmp/out6" 2>&1)" \
  "a release tag already exists; nothing to bootstrap"
check "no tag was added" "$(git tag -l | tr '\n' ' ')" "v2.3.1 "

# --- a malformed input ------------------------------------------------------

echo "== a malformed initial version fails loudly =="
new_repo malformed
git add -A
git commit -qm "chore: initial scaffold"
git push -q origin main
out="$(run_bootstrap not-a-version "$tmp/out7" 2>&1)"
rc=$?
check "the run fails" "$rc" "1"
check "the failure names the format" \
  "$(grep -o 'initial-version must look like 0.0.0 (or v0.0.0)' <<<"$out")" \
  "initial-version must look like 0.0.0 (or v0.0.0)"
check "no tag was created" "$(git tag -l)" ""
run_bootstrap v0.0.0 "$tmp/out8" >/dev/null
check "a v-prefixed input is accepted" "$(cat "$tmp/out8")" "tag=v0.0.0"

# --- disabled ---------------------------------------------------------------

echo "== initial-version \"\" keeps semantic-release's 1.0.0 =="
new_repo disabled
git add -A
git commit -qm "chore: initial scaffold"
echo one > file.txt
git add -A
git commit -qm "feat: first feature"
git push -q origin main
check "no tag exists, so the bootstrap would have run" "$(git tag -l)" ""
check "the first feat releases 1.0.0" "$(semantic_release | next_version)" \
  "next release version is 1.0.0"

# --- summary ----------------------------------------------------------------

echo
echo "passed: $pass, failed: $fail"
[[ "$fail" -eq 0 ]]
