#!/usr/bin/env bash
# Sync the canonical standards from this template repository into another
# repository, on a branch, and open a pull request for review.
#
# Usage: scripts/sync.sh [--agents-only] <path-to-target-repo> [branch-name]
#
# AGENTS.md is always overwritten (this repository is canonical).
# .releaserc.json and the release workflow are only created when missing, because
# each repository extends them (publish plugins, secrets).
#
# --agents-only copies AGENTS.md and nothing else. Use it for a repository that is
# not a project and must never get a release pipeline of its own - the organization
# profile repository (nexform-tech/.github) is the case this exists for. Without the
# flag that repository would silently acquire .releaserc.json and a release
# workflow, because it has neither and this script creates what is missing.
set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

AGENTS_ONLY=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --agents-only) AGENTS_ONLY=1 ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

TARGET="${POSITIONAL[0]:-}"
BRANCH="${POSITIONAL[1]:-chore/sync-repo-standards}"

die() { echo "error: $*" >&2; exit 1; }

[[ -n "$TARGET" ]] || die "usage: $0 [--agents-only] <path-to-target-repo> [branch-name]"
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

# Only AGENTS.md is canonical for a repository that is not a project: adding a
# release pipeline there would be an invention, not a sync.
if [[ "$AGENTS_ONLY" == "1" ]]; then
  echo "  kept  .releaserc.json and .github/workflows/release.yml untouched (--agents-only)"
else
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
fi

if [[ -z "$(git -C "$TARGET" status --porcelain)" ]]; then
  echo "already up to date; switching back to $DEFAULT_BRANCH"
  git -C "$TARGET" switch "$DEFAULT_BRANCH"
  exit 0
fi

if [[ "$AGENTS_ONLY" == "1" ]]; then
  echo "next: this repository is not a project; do not add a CI or release pipeline"
else
  echo "next: copy examples/ci.yml to .github/workflows/ci.yml and set the test command"
fi

CHANGES="- \`AGENTS.md\` overwritten with the canonical version"
if [[ "$AGENTS_ONLY" == "1" ]]; then
  CHANGES="$CHANGES
- \`.releaserc.json\` and \`.github/workflows/release.yml\` left untouched on purpose: this repository is not a project, so \`--agents-only\` was used and no release pipeline was added"
else
  CHANGES="$CHANGES
- \`.releaserc.json\` added only if it was missing, otherwise kept
- \`.github/workflows/release.yml\` added only if it was missing, otherwise kept"
fi

git -C "$TARGET" add -A
git -C "$TARGET" commit -m "chore: sync repository standards"
git -C "$TARGET" push -u origin "$BRANCH" --force-with-lease

if (cd "$TARGET" && gh pr create \
  --title "chore: sync repository standards" \
  --body "## Summary

Automated sync from \`nexform-tech/repo-template\`: \`AGENTS.md\` is canonical there and is overwritten with the canonical version. This merge publishes nothing, because both the commit message and this title are \`chore:\`.

## Changes

$CHANGES

## Testing

Rules and release configuration only, so no code changed and no test suite is affected. If the diff also carries local edits, run this repository's own test command before merging.

## Issues

None. Merge with squash and delete the source branch."); then
  :
else
  echo "note: no pull request created (one may already be open); the branch was pushed"
fi
