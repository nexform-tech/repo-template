#!/usr/bin/env bash
# Sync the canonical standards from this template repository into another
# repository, on a branch, and open a pull request for review.
#
# Usage: scripts/sync.sh <path-to-target-repo> [branch-name]
#
# AGENTS.md is always overwritten (this repository is canonical).
# .releaserc.json and the release workflow are only created when missing, because
# each repository extends them (publish plugins, secrets).
set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"
BRANCH="${2:-chore/sync-repo-standards}"

die() { echo "error: $*" >&2; exit 1; }

[[ -n "$TARGET" ]] || die "usage: $0 <path-to-target-repo> [branch-name]"
[[ -d "$TARGET" ]] || die "not a directory: $TARGET"
git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repository: $TARGET"
[[ -z "$(git -C "$TARGET" status --porcelain --untracked-files=no)" ]] || die "uncommitted changes in $TARGET; commit or stash them first"

command -v gh >/dev/null 2>&1 || die "gh is required: https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run: gh auth login"

DEFAULT_BRANCH="$(cd "$TARGET" && gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || true)"
[[ -n "$DEFAULT_BRANCH" ]] || die "cannot determine the default branch of $TARGET (does it have a GitHub remote?)"

echo "syncing into $TARGET (default branch: $DEFAULT_BRANCH)"
git -C "$TARGET" switch "$DEFAULT_BRANCH"
git -C "$TARGET" pull --ff-only
git -C "$TARGET" switch -C "$BRANCH"

cp "$TEMPLATE_DIR/AGENTS.md" "$TARGET/AGENTS.md"
echo "  wrote AGENTS.md"

if [[ -f "$TARGET/.releaserc.json" ]]; then
  echo "  kept  .releaserc.json (already present; plugin lists differ per repository)"
else
  cp "$TEMPLATE_DIR/.releaserc.json" "$TARGET/.releaserc.json"
  echo "  wrote .releaserc.json"
fi

if [[ -f "$TARGET/.github/workflows/release.yml" ]]; then
  echo "  kept  .github/workflows/release.yml (already present)"
else
  mkdir -p "$TARGET/.github/workflows"
  cp "$TEMPLATE_DIR/examples/caller-release.yml" "$TARGET/.github/workflows/release.yml"
  echo "  wrote .github/workflows/release.yml"
fi

if [[ -z "$(git -C "$TARGET" status --porcelain)" ]]; then
  echo "already up to date; switching back to $DEFAULT_BRANCH"
  git -C "$TARGET" switch "$DEFAULT_BRANCH"
  exit 0
fi

echo "next: copy examples/ci.yml to .github/workflows/ci.yml and set the test command"

git -C "$TARGET" add -A
git -C "$TARGET" commit -m "chore: sync repository standards"
git -C "$TARGET" push -u origin "$BRANCH" --force-with-lease

if (cd "$TARGET" && gh pr create \
  --title "chore: sync repository standards" \
  --body "## Summary

Automated sync from \`nexform-tech/repo-template\`: \`AGENTS.md\` is canonical there and is overwritten with the canonical version. This merge publishes nothing, because both the commit message and this title are \`chore:\`.

## Changes

- \`AGENTS.md\` overwritten with the canonical version
- \`.releaserc.json\` added only if it was missing, otherwise kept
- \`.github/workflows/release.yml\` added only if it was missing, otherwise kept

## Testing

Rules and release configuration only, so no code changed and no test suite is affected. If the diff also carries local edits, run this repository's own test command before merging.

## Issues

None. Merge with squash and delete the source branch."); then
  :
else
  echo "note: no pull request created (one may already be open); the branch was pushed"
fi
