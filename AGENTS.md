# AGENTS.md

Operating rules for agents working in this repository. They are mandatory, not advisory.

## 1. Git Workflow

These rules assume the repository is hosted on GitHub. Where it has no GitHub remote, the GitHub-specific steps (PRs, issues, releases) do not apply; branching, commit, and testing rules apply to every Git repository.

**Never modify code directly on the default branch.** Always create a new branch first.

- The default branch may be `main` or `master`; `<default-branch>` below means whichever it is.
- Sync before branching: `git switch <default-branch> && git pull --ff-only`.
- Create a branch: `git switch -c <type>/<short-description>`.
  - Examples: `feat/oauth-login`, `fix/null-pointer-on-logout`, `chore/bump-deps`.
  - `<type>` is one of the commit types listed below.
- Keep branches small and single-purpose. One branch solves one problem.
- Keep the branch current by rebasing on `<default-branch>`; do not merge `<default-branch>` into it.
- Never rewrite history that has already been pushed to a shared branch.

### Commits

Every commit message follows Conventional Commits:

```
<type>: <subject>

<body>

<footer>
```

- `<type>` is required and must be one of: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- `<subject>`: imperative mood, lowercase, no trailing period, 72 characters or fewer. Example: `feat: add OAuth login`.
- `<body>`: optional. Explain what changed and why, not how. Wrap at 72 characters.
- `<footer>`: optional. Link issues (`Closes #123`) and mark breaking changes with `BREAKING CHANGE: <description>`.
- One logical change per commit. Do not mix refactoring with behavior changes.
- Never commit generated artifacts, secrets, credentials, or local config.

### Issues

- Search before creating: `gh issue list --search "<keywords>"`. Never open a duplicate.
- Read the full issue and all its comments before starting; check for a linked PR to avoid repeating work.
- Create issues with `gh issue create`. Title: short, imperative, no trailing period.
  - Bug body: **Context**, **Expected**, **Actual**, **Reproduce**.
  - Feature body: **Problem**, **Proposal**, **Alternatives**.
- Use only labels that already exist in the repository. Never invent or create labels.
- One issue per problem. Do not bundle unrelated work; link related issues instead.
- Reference the issue in commits and in the PR body. Use a closing keyword (`Closes #123`, `Fixes #123`, `Resolves #123`) only when the PR fully resolves it; otherwise use `Refs #123`.
- Let the merge close the issue. Do not close it by hand first; verify it is closed after merge.
- A PR links to an issue and closes it automatically only when the PR targets `<default-branch>`; a PR targeting any other branch links nothing and closes nothing.
- Never edit, close, reopen, reassign, or label an issue without explicit user approval. Never rewrite someone else's issue text; comment instead.

### Pull Requests

- Push the branch and open a PR with `gh pr create`.
- **The commit message is what lands, and therefore what the release reads.** Under GitHub's default squash settings a single-commit PR puts the *commit message* on `<default-branch>` and ignores the PR title, while a multi-commit PR puts the *PR title*. Make the PR title identical to the commit subject so neither case can be wrong.
- Put `BREAKING CHANGE:` in the commit footer, never only in the PR description. A squash merge carries the PR's commit messages into the result but not its description, so a breaking change noted only in the description ships as a minor bump.
- PR body must contain:
  - **Summary** — what this changes and why, plus the version the merge would publish, written as `v0.1.2 -> v1.0.0`, or an explicit statement that it publishes nothing. A summary whose version is a major must quote the user's approval for it.
  - **Changes** — bullet list of the concrete edits.
  - **Testing** — the exact commands run and their result.
  - **Issues** — `Closes #123` when applicable.
- Do not open a draft PR unless asked. Do not open a PR before the test suite passes.
- Address review feedback with new commits; do not force-push a PR under review unless asked.

### Merging

- Repository owners merge with **squash and merge** only (`gh pr merge --squash`), producing exactly one commit on `<default-branch>`.
- Never use a merge commit or rebase merge. Never push directly to `<default-branch>`.
- Before merging, the commit messages and the PR title must both be valid Conventional Commit messages, and the CI must be green.
- Delete the source branch after merging.

## 2. Testing

- The repository has a test suite. Run it before **every** commit and **every** push.
- All tests must pass. A failing suite blocks the commit, the push, and the PR.
- Never delete, skip, weaken, or comment out tests to make a suite pass. Fix the cause.
- Add tests for every new behavior and every bug fix.
- If a test failure is pre-existing and unrelated, report it explicitly instead of ignoring it.
- Do not commit code you know to be broken.

## 3. Versioning and Releases

- Releases are automated by `semantic-release` in the `Release` workflow (`.github/workflows/release.yml`) on every push to `<default-branch>`: it computes the next version from the commit prefixes, creates the tag, and creates the GitHub release. Publishing is a separate, language-specific `publish` job in the same workflow, and it is skipped when nothing was released.
- The release level is determined by the merged commit prefix: `feat` → minor, `fix`/`perf` → patch, `BREAKING CHANGE:` → major. Every other type (`docs`, `style`, `refactor`, `test`, `build`, `ci`, `chore`) produces no release. An incorrect prefix therefore ships an incorrect version.
- **A major release requires the user's explicit approval, with the version spelled out.** Only `BREAKING CHANGE:` in a commit footer and the `!` shorthand (`feat!:`, `fix!:`) reach a major version, so writing one is a decision, not a description. Before you write either, read the current version from the newest `vX.Y.Z` tag (the bootstrapped `v0.0.0` counts when it is the only one) and tell the user exactly what the merge would publish, as `v0.1.2 -> v1.0.0`, then wait for their confirmation. Never write either marker without that confirmation, and never write it merely to be accurate. Without it, make the change backward-compatible — a new optional parameter, a new name beside the old one, a deprecation notice, the old behaviour kept — and ship it as `feat:` or `fix:`.
- **Never hide a real break behind a minor version either.** If the change cannot be made backward-compatible, stop and ask for the major release, stating the transition as above, instead of downgrading the commit to `feat:`: a silently minor bump breaks whoever pinned a major tag. A major version is a promise about the public surface, so only the user makes it.
- The release job never commits to `<default-branch>`. Do not add `@semantic-release/git` to `.releaserc.json`.
- Because nothing is committed back, the version field in the manifest (`package.json`, `pyproject.toml`, `Cargo.toml`) stays at its placeholder, `0.0.0-semantic-release`, and CI overwrites it only in the publish workspace. Never edit that field and never treat it as the current version; the git tag is the only source of truth.
- **Never tag, publish, or edit releases by hand** — no `git tag`, `npm publish`, `twine upload`, `cargo publish`, `docker push`, or `gh release create`, and no hand edits to version numbers or `CHANGELOG.md`. The release workflow owns all of that, including the registry credentials.
- Repositories start on the `0.x` line. semantic-release has no option for the initial version and would publish `1.0.0` for the first release of a repository with no tag, whatever the commit type; the only lever is a pre-existing tag, so the `Release` workflow bootstraps `v0.0.0` on the root commit itself before it runs semantic-release. The first `feat:` then publishes `0.1.0` and the first `fix:` publishes `0.0.1`. Merge the standards before the first feature so that the bootstrap runs first, and never create that tag by hand. A repository that must keep semantic-release's `1.0.0` first release passes `initial-version: ""` to the reusable workflow, which skips the bootstrap.
- `0.x` does not soften a breaking change: `BREAKING CHANGE:` always produces `major`, and `semver.inc("0.1.0", "major")` is `1.0.0`. Do not use `0.x` to keep breaking changes in the `0.y.0` range.

## 4. Required Tooling

- **`git` is always required.** Use it for all version control operations. If it is missing, stop and tell the user to install it, including the command for their platform. Do not install tooling unless the user approves.
- **`gh` is required whenever the repository has a GitHub remote** (detect with `git remote -v`). If it is missing, stop and tell the user to install it; the PR, issue, and release steps cannot be completed without it.
- Use `gh` for all GitHub operations: repositories, issues, PRs, reviews, releases, CI status.
- Do not call the GitHub API with `curl` or `wget` when `gh` can do the job.
- Confirm authentication with `gh auth status` before GitHub operations; if unauthenticated, tell the user to run `gh auth login`.

## 5. Reporting

- State the branch, the commit hashes, and the PR URL when reporting completed work.
- Report test commands and their results verbatim.
- Never claim a task is complete when tests fail, CI is red, or a step was skipped.
