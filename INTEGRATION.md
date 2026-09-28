# Integration guide (for agents)

You are an agent working inside another repository. Your task is to apply the
standards from `nexform-tech/repo-template` to **this** repository. Follow the
steps in order and do the work through a pull request.

Everything here was verified in a sandbox repository; the gotchas at the end are
real, not theoretical.

## 0. Preconditions

- `git` is installed. `gh` is installed and authenticated — check
  `gh auth status`; if either is missing, stop and tell the user how to install it.
- The repository has a GitHub remote: `git remote -v`.
  - **No GitHub remote?** Then the GitHub-specific parts do not apply. Copy only
    `AGENTS.md` and follow its branching, commit and testing rules; skip steps 2–5.
- Determine the default branch — never assume:
  `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`
  It may be `main` or `master`. Step 2 tells you what to do if it is neither.
- Read `AGENTS.md` from the template before you start; you will be following it.

## 1. Fetch the template (disposable)

```bash
gh repo clone nexform-tech/repo-template ../repo-template -- --depth 1
```

Use a **sibling directory** of the target repository. Do not clone inside the
target repository (the sync commit stages everything with `git add -A`), and do
not use `/tmp`: some agent sandboxes do not persist it between commands.

## 2. Install the standards

```bash
cd /path/to/target-repo
../repo-template/scripts/sync.sh .
```

This creates the branch `chore/sync-repo-standards`, copies `AGENTS.md`, and adds
`.releaserc.json` and `.github/workflows/release.yml` **only if they are missing**,
then pushes and opens a PR. Stay on that branch — the remaining steps add to the
same PR.

What you now have: versioning, tagging and GitHub releases work on merge, with no
further configuration. GitHub attaches the source tarball to every release itself.

**If the default branch is neither `main` nor `master`**, edit both files before
going on: the `branches` list in `.releaserc.json` and `on.push.branches` in
`.github/workflows/release.yml` must name the real branch.

## 3. Add the test gate

```bash
cp ../repo-template/examples/ci.yml .github/workflows/ci.yml
```

Then replace the two placeholders with this repository's own toolchain and test
command. **Delete the `exit 1` placeholder** — it fails on purpose so that a green
check can never mean "zero tests ran".

Detect the stack from what the repository already contains, and prefer a command
the repository documents over one you invent:

| Evidence in the repository | Setup step | Test command |
|---|---|---|
| `package.json` | `actions/setup-node@v4` | `npm ci && npm test` |
| `pyproject.toml`, `setup.py`, `tox.ini` | `actions/setup-python@v5` | `pip install -e ".[test]" && pytest` |
| `Cargo.toml` | `dtolnay/rust-toolchain@stable` | `cargo test --all-features` |
| `go.mod` | `actions/setup-go@v5` | `go test ./...` |
| `pom.xml`, `build.gradle` | `actions/setup-java@v4` | `./gradlew test` or `mvn -B test` |
| `Makefile` with a `test` target | — | `make test` |

## 4. Add publishing and packaging only if this repository ships something

Paste the relevant job from the template into **this repository's own**
`.github/workflows/release.yml`, next to the `release` job. Both fragments read
`needs.release.outputs.new_tag`, which is why they cannot live in a separate file.

| The repository ships | Job to paste | Source |
|---|---|---|
| a registry package (npm, PyPI, crates.io) | `publish` | `../repo-template/examples/publish.yml` |
| build artifacts on the release (deb, rpm, tarball, image) | `package` | `../repo-template/examples/package.yml` |
| nothing but source | none — delete nothing, change nothing | — |

Fill in the build/publish steps and replace their `exit 1` placeholders. Registry
credentials belong to this repository, never to the template: define the secret
(`NPM_TOKEN`, `PYPI_TOKEN`, `CARGO_REGISTRY_TOKEN`, …) in this repository's
settings. If the repository publishes, define the secret **before** merging.

## 5. Open the pull request

- Integration PRs must not cut a release: use `chore:` or `ci:` in the commit
  messages **and** in the PR title.
- Keep the PR title identical to the commit subject (see gotcha 1).
- The PR body must contain Summary, Changes, Testing and Issues sections.
- Do **not** merge it yourself unless the user explicitly asks; merging is the
  repository owner's action, and it must be a squash merge.

## 6. Verify after the merge

```bash
gh run list --workflow Release --limit 3
gh release list
gh api repos/{owner}/{repo}/releases/{id}/assets   # per-release endpoint, see gotcha 4
```

- An untagged repository starts on the `0.x` line: the first push bootstraps a
  `v0.0.0` tag on the root commit, so the first `feat:` releases `0.1.0` and the
  first `fix:` releases `0.0.1`. Nothing to do — the workflow creates that tag
  itself; never create it by hand. A repository that must keep semantic-release's
  `1.0.0` first release passes `with: initial-version: ""` instead, which skips the
  bootstrap.
- Confirm the release job added **no commit** to the default branch.
- Confirm the expected artifact is attached, if the repository ships one.

## 7. Hand these to the human — they cannot be done through a PR

- **Branch protection:** require the `test` status check on the default branch,
  otherwise the testing rules in `AGENTS.md` are not enforced.
- **Secrets:** any registry token this repository publishes with.
- **Squash settings:** verify they are still the defaults (see gotchas 1 and 2),
  or make sure PR titles match commit subjects.

## 8. Definition of done

- [ ] `AGENTS.md` at the repository root, unmodified from the template
- [ ] `.releaserc.json` present
- [ ] `.github/workflows/release.yml` calling the reusable workflow at a pinned ref
- [ ] `.github/workflows/ci.yml` with the real test command, no placeholder left
- [ ] publish/package jobs added, or deliberately omitted
- [ ] PR opened with a non-releasing, conventional title; CI green
- [ ] after merge: `v0.0.0` is bootstrapped and no release is cut yet; the first
      `feat:` or `fix:` merge cuts a release and attaches any artifact
- [ ] the human has been told about branch protection and secrets

## Gotchas (all verified)

1. **The commit message decides the version, not the PR title.** With GitHub's
   default `squash_merge_commit_title = COMMIT_OR_PR_TITLE`, a **single-commit** PR
   lands the *commit message* on the default branch and ignores the PR title; a
   multi-commit PR lands the *PR title*. Keep them identical and neither case can
   be wrong.
2. **`BREAKING CHANGE:` must be in a commit footer.** With the default
   `squash_merge_commit_message = COMMIT_MESSAGES`, the PR's commit messages are
   carried into the squash commit but the **PR description is not**. A breaking
   change written only in the description ships as a minor bump instead of a major
   one.
3. **Only `feat`, `fix`, `perf` and `BREAKING CHANGE:` produce a release.** `docs`,
   `style`, `refactor`, `test`, `build`, `ci`, `chore` produce none, and the
   publish/package jobs are skipped.
4. **A release's `assets` array in the releases *list* endpoint can be stale.**
   Query `repos/{owner}/{repo}/releases/{id}/assets` when checking whether an
   artifact was attached, or you may conclude a working job failed.
5. **Do not add `@semantic-release/git`** to `.releaserc.json`. The release job
   must never commit to the default branch.
6. **The version field in `package.json` / `pyproject.toml` / `Cargo.toml` is a
   placeholder** (`0.0.0-semantic-release`). CI overwrites it only in the publish
   workspace. Never edit it, and never treat it as the current version — the git
   tag is the only source of truth.
7. **Never tag, publish or edit releases by hand.** No `git tag`, `npm publish`,
   `twine upload`, `cargo publish`, `docker push`, `gh release create`, and no hand
   edits to versions or `CHANGELOG.md`. The one tag that appears without a release,
   the `v0.0.0` starting point, is created by the release workflow itself.
8. **Do not edit `AGENTS.md` in this repository.** The template is the source of
   truth; `sync.sh` overwrites the copy on the next run. Rule changes belong in the
   template.
9. **The template's `v1` tag is movable.** It always points at the newest release,
   so callers get pipeline fixes automatically. Pin a commit SHA instead if that is
   not acceptable.

## Updating later

```bash
git -C ../repo-template pull --ff-only || gh repo clone nexform-tech/repo-template ../repo-template
../repo-template/scripts/sync.sh /path/to/target-repo
```

`AGENTS.md` is overwritten with the canonical version; `.releaserc.json` and the
release workflow are left alone once they exist. The release pipeline itself needs
no action — the pinned `@v1` ref follows the template's releases.
