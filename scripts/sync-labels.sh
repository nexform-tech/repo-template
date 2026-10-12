#!/usr/bin/env bash
# Apply the canonical label set from .github/labels.yml to repositories on GitHub.
#
# Usage:
#   scripts/sync-labels.sh [--dry-run] [--sleep <seconds>] <owner>/<repo> [...]
#   scripts/sync-labels.sh [--dry-run] [--sleep <seconds>] --org <org>
#
# Idempotent: a missing label is created, an existing one is updated in place only
# after its color or description actually differs, so issues that already carry it
# keep it and a no-op run writes nothing. Labels that exist on the target but not in
# the manifest are left alone - deleting a label removes it from every issue that
# carries it, which is not something a sync should decide on its own.
set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABELS_FILE="$TEMPLATE_DIR/.github/labels.yml"

die() { echo "error: $*" >&2; exit 1; }
usage() {
  echo "usage: $0 [--dry-run] [--sleep <seconds>] <owner>/<repo>... | --org <org>" >&2
  exit 2
}
help() {
  echo "usage: $0 [--dry-run] [--sleep <seconds>] <owner>/<repo>... | --org <org>"
  exit 0
}

DRY_RUN=false
ORG=""
REPOS=()
SLEEP=0.25
WRITES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --org) ORG="${2:-}"; [[ -n "$ORG" ]] || usage; shift 2 ;;
    --sleep) SLEEP="${2:-}"; [[ "$SLEEP" =~ ^[0-9]+([.][0-9]+)?$ ]] || usage; shift 2 ;;
    -h|--help) help ;;
    -*) die "unknown option: $1" ;;
    *) REPOS+=("$1"); shift ;;
  esac
done

[[ -f "$LABELS_FILE" ]] || die "missing $LABELS_FILE"
command -v gh >/dev/null 2>&1 || die "gh is required: https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run: gh auth login"

unquote() { local v="$1"; v="${v#\"}"; v="${v%\"}"; printf '%s' "$v"; }

# The manifest is a flat list in a fixed shape, so it is read with awk rather than
# a YAML library - the repositories this script has to run in are language-agnostic.
read_manifest() {
  awk '
    /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
      if (name != "") print name "\t" color "\t" desc
      name = $0; sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", name)
      color = ""; desc = ""; next
    }
    /^[[:space:]]*color:[[:space:]]*/ {
      color = $0; sub(/^[[:space:]]*color:[[:space:]]*/, "", color); next
    }
    /^[[:space:]]*description:[[:space:]]*/ {
      desc = $0; sub(/^[[:space:]]*description:[[:space:]]*/, "", desc); next
    }
    END { if (name != "") print name "\t" color "\t" desc }
  ' "$LABELS_FILE"
}

declare -A seen=()
count=0
while IFS=$'\t' read -r name color desc; do
  [[ -n "$name" ]] || continue
  name="$(unquote "$name")"; color="$(unquote "$color")"; desc="$(unquote "$desc")"
  [[ "$color" =~ ^[0-9a-fA-F]{6}$ ]] || die "label '$name' has an invalid color: '$color'"
  [[ -n "$desc" ]] || die "label '$name' has no description"
  [[ -z "${seen[$name]:-}" ]] || die "label '$name' is listed twice in $LABELS_FILE"
  seen[$name]=1
  count=$((count + 1))
done < <(read_manifest)
[[ $count -gt 0 ]] || die "$LABELS_FILE defines no labels"

if [[ -n "$ORG" ]]; then
  [[ ${#REPOS[@]} -eq 0 ]] || die "--org and explicit repositories cannot be combined"
  while IFS= read -r slug; do
    if [[ -n "$slug" ]]; then
      REPOS+=("$slug")
    fi
  done < <(gh repo list "$ORG" --limit 500 --json nameWithOwner,isArchived \
             --jq '.[] | select(.isArchived | not) | .nameWithOwner')
fi
[[ ${#REPOS[@]} -gt 0 ]] || usage

# A burst of mutations trips GitHub's secondary rate limit, so writes are spaced
# out and retried. Reads are cheap and are not throttled.
gh_retry() {
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [[ $attempt -ge 3 ]]; then
      return 1
    fi
    attempt=$((attempt + 1))
    sleep "$attempt"
  done
}

write_label() {
  "$@" || return 1
  WRITES=$((WRITES + 1))
  sleep "$SLEEP"
}

fetch_labels() {
  local repo="$1" attempt=1
  while true; do
    if gh api "repos/$repo/labels?per_page=100" --paginate \
         --jq '.[] | "\(.name)\t\(.color | ascii_downcase)\t\(.description // "")"'; then
      return 0
    fi
    if [[ $attempt -ge 3 ]]; then
      return 1
    fi
    attempt=$((attempt + 1))
    sleep "$attempt"
  done
}

if $DRY_RUN; then
  echo "$count labels -> ${#REPOS[@]} repositories (dry run, nothing is written)"
else
  echo "$count labels -> ${#REPOS[@]} repositories"
fi

failures=0
for repo in "${REPOS[@]}"; do
  echo "$repo"
  existing="$(fetch_labels "$repo")" || {
    echo "  FAILED: cannot read the labels of $repo" >&2
    failures=$((failures + 1))
    continue
  }

  declare -A have=()
  while IFS=$'\t' read -r name color desc; do
    if [[ -n "$name" ]]; then
      have["$name"]="$color|$desc"
    fi
  done <<< "$existing"

  created=0 updated=0 unchanged=0
  while IFS=$'\t' read -r name color desc; do
    [[ -n "$name" ]] || continue
    name="$(unquote "$name")"; color="$(unquote "$color")"; desc="$(unquote "$desc")"
    color="${color,,}"
    if [[ -z "${have[$name]+x}" ]]; then
      if $DRY_RUN; then
        printf '  would create  %s\n' "$name"
      elif gh_retry write_label gh label create "$name" --repo "$repo" \
             --color "$color" --description "$desc"; then
        printf '  created       %s\n' "$name"
        created=$((created + 1))
      else
        printf '  FAILED        %s\n' "$name" >&2
        failures=$((failures + 1))
      fi
    elif [[ "${have[$name]}" == "${color}|${desc}" ]]; then
      unchanged=$((unchanged + 1))
    elif $DRY_RUN; then
      printf '  would update  %s\n' "$name"
    elif gh_retry write_label gh label edit "$name" --repo "$repo" \
           --color "$color" --description "$desc"; then
      printf '  updated       %s\n' "$name"
      updated=$((updated + 1))
    else
      printf '  FAILED        %s\n' "$name" >&2
      failures=$((failures + 1))
    fi
  done < <(read_manifest)

  if ! $DRY_RUN; then
    printf '  summary: %s created, %s updated, %s already correct\n' \
      "$created" "$updated" "$unchanged"
  fi
  unset have
done

if [[ $failures -gt 0 ]]; then
  echo "done with $failures failure(s)" >&2
  exit 1
fi
if $DRY_RUN; then
  echo "done (dry run, nothing was written)"
else
  echo "done, $WRITES label(s) written"
fi
