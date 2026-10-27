# Contributing

Thanks for helping. This is the short version of the rules; the full ones,
written for the maintainer and the review agents, are in [CLAUDE.md](CLAUDE.md).

## Set up

```bash
git clone https://github.com/<you>/camwatch && cd camwatch
git config core.hooksPath .githooks    # checks commit messages
flutter pub get                        # the Flutter version is pinned in the root pubspec.yaml
```

Then run what CI runs:

```bash
dart format .
dart analyze --fatal-infos
(cd packages/camwatch_core && dart run coverage:test_with_coverage)
(cd apps/camwatch && flutter test --coverage)
dart run tool/coverage_gate.dart packages/camwatch_core/coverage/lcov.info apps/camwatch/coverage/lcov.info
```

On Windows, building the app locally needs Developer Mode (plugin symlinks).

## The rules that will be checked

- **One issue per pull request.** Pick an open issue (or open one first, with a
  `priority/*` label); say `Closes #N` in the PR. Skip issues labelled `WIP`.
- **Test first.** Write a failing test, make it pass, then tidy. Line coverage
  is 100% in both packages and the gate fails the build under that. Tests use
  fakes and 127.0.0.1 only: no real camera, no internet.
- **Conventional Commits** for every commit and for the PR title:
  `feat: …`, `fix: …`, `docs: …`, `refactor: …`, `test: …`, `ci: …`. The hook
  rejects anything else and a subject over 72 characters.
- **English only** in code, comments, docs, commits and app text.
- **The privacy promise holds.** Nothing leaves the local network (the one
  opt-in exception is the update check), credentials only in OS secure
  storage, no new permission or dependency without a reason in the issue,
  backups stay off, every platform stays first-class. A change that would
  break one of these needs the maintainer's agreement before the work.
- **No real network details.** Never put a real IP address, camera name or a
  screenshot of a real network in an issue, a PR or a test.
- **README stays current** in the same PR as any user-visible change.

## What happens to a pull request

CI runs format, analysis, both test suites, the coverage gate, the Android and
Windows builds, SonarCloud and an AI review. Findings are settled in the same
PR. `main` only takes squash merges through a PR.

**From a fork**, SonarCloud and the AI review are skipped: they need secrets
the fork does not get, and a skipped required check counts as passed. The
maintainer runs them before merging by pushing the fork's commit to a branch
of this repository and opening a pull request from it; findings go back to the
original PR, which is then merged.

## Reporting a security problem

Not here: see [SECURITY.md](SECURITY.md).
