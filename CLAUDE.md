# camwatch

An open-source app that finds the cameras on your local network, tells you how
safe each one is, and plays the streams it can reach. Flutter, on Android and
Windows for now. No account, no server, no trackers.

## Privacy promise

These hold end-to-end. Any change that would break one needs explicit maintainer agreement.

1. **Nothing leaves the local network.** Every connection goes to an address `isLocalIpv4` accepts (`packages/camwatch_core/lib/src/lan.dart`) or to the WS-Discovery / mDNS multicast group. No analytics, crash reporting or ad SDK. The one exception is the opt-in update check and install (`packages/camwatch_core/lib/src/update.dart` and `download.dart`): off until the user accepts its notice, the app then asks `github.com` where its latest-release page redirects, reads the version from that answer without following it, and on the user's tap fetches the release file, its digest and the digest's signature from `github.com` and its download servers; nothing about the user goes with any of it.
2. **Credentials only in OS secure storage** (`flutter_secure_storage`: Android Keystore, Windows DPAPI). Never in settings files, logs or exports. An RTSP URL with `user:password@` is never logged or shown.
3. **No permission without a reason.** Android permissions are limited to network ones (INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE) plus REQUEST_INSTALL_PACKAGES, which the in-place update needs to hand a signature-checked APK to the system installer (GitHub-distributed builds only: a store build must drop this permission and the installer, app stores forbid self-updating); each arrives with the issue that needs it.
4. **Backups off.** `allowBackup="false"` and `res/xml/data_extraction_rules.xml` exclude everything.
5. **Every platform is first-class.** CI tests on Linux and Windows and builds the Android and Windows app. A change that works on one OS only is not done.

## Commands

```bash
flutter pub get                                   # resolve the Dart workspace (one root pubspec.lock)
dart format .                                     # format (page width 100, analysis_options.yaml)
dart analyze --fatal-infos                        # strict analysis
(cd packages/camwatch_core && dart run coverage:test_with_coverage)   # core tests + lcov
(cd apps/camwatch && flutter test --coverage)                         # app tests + lcov
dart run tool/coverage_gate.dart packages/camwatch_core/coverage/lcov.info apps/camwatch/coverage/lcov.info
python tool/check_comments.py origin/main...HEAD   # narrative comments this branch adds (CI warns, --strict fails)
(cd apps/camwatch && flutter run)                  # run the app
(cd apps/camwatch && flutter build apk --debug)    # Android; also `windows`
```

Flutter lives in `~/flutter` (its version is pinned in the root `pubspec.yaml`). Add dependencies with `dart pub add` (or `flutter pub add`) in the package that needs them; commit the root `pubspec.lock`. Every new dependency goes past the `privacy-auditor` agent. On Windows, local plugin builds need Developer Mode (symlinks).

## Architecture

A monorepo and a Dart pub workspace.

```
packages/camwatch_core/   pure Dart, no Flutter: subnet math, discovery, RTSP/ONVIF parsing, security rules
apps/camwatch/            the Flutter app: Android and Windows
tool/                     the coverage gate, comment check, desktop packaging, the app icon
```

Dependencies point one way: the app imports the core, the core never imports Flutter or the app. Logic that needs no UI belongs in the core.

## Testing (TDD)

All new production code is written test-first: RED (one minimal failing test, watch it fail for the right reason) → GREEN (minimal code) → REFACTOR (tests stay green). Line coverage is 100% for both packages, enforced by `tool/coverage_gate.dart` in CI and tracked in SonarCloud. The one exception is native glue `flutter test` cannot load: it goes between `// coverage:ignore-start` and `// coverage:ignore-end` (also excluded in `sonar-project.properties`), stays thin behind an interface, and the logic around it is tested with fakes.

- Tests mirror the source tree (`lib/src/lan.dart` → `test/lan_test.dart`).
- No network in tests: discovery and streams are tested against fakes and loopback servers on 127.0.0.1, never real cameras or the internet.
- Bug fixes start with a regression test.
- No real IP addresses, camera names or screenshots of a real network in the repository, issues or PRs.

## Language

All code, comments, docs, commit messages and app text are in English. The maintainer chats in Turkish; that does not leak into the repo.

## Workflow

- **Commits:** Conventional Commits (`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`), checked locally by `.githooks/commit-msg` (`git config core.hooksPath .githooks` once per clone). CI config changes are `ci:`.
- **Issues:** every issue carries exactly one `priority/*` label (`critical`, `high`, `medium`, `low`); open them with `gh issue create --label priority/<level>` or the issue form. `issue-priority.yml` closes an issue without one until it is labelled.
- **Issue dependencies:** before opening an issue, check existing issues for work it requires or blocks. After creating it, record each real prerequisite with GitHub's **Blocked by / Blocking** relationship (`gh api -X POST repos/mfozmen/camwatch/issues/<blocked>/dependencies/blocked_by -F issue_id=<blocking issue's REST id>`; get that id with `gh api repos/mfozmen/camwatch/issues/<blocking> --jq .id`).
- **WIP:** when you start an issue, add the `WIP` label; remove it when the work is merged or abandoned. When choosing the next issue, skip any issue that still has `WIP`.
- **Epics are milestones:** every issue belongs to exactly one milestone, the epic it serves. An epic is closable work: a verb-led Title Case title bounded by named items. Its description is two lines: what it delivers, then `Why: …`. If no open epic fits, open a new one; a closed epic is never reopened. **Order** is the due date, a placeholder: `2099-01-01` is worked on first, `2099-01-02` next, always `T12:00:00Z` (`gh api -X POST repos/mfozmen/camwatch/milestones -f title=… -f description=… -f due_on=2099-01-NNT12:00:00Z`). Take work from the earliest open epic; priority labels rank issues inside it. `close-finished-epics.yml` closes an epic when its last issue closes.
- **Branches:** one branch per feature/fix, `<type>/<slug>` (e.g. `feat/port-scan`), merged via a squash PR whose title is a Conventional Commit and whose body has a summary, context and test plan. `main` is protected by a repository ruleset: every change goes through a PR (docs too), the Flutter, CI script, SonarCloud and AI review checks must pass, and force-push and deletion are blocked. The only bypass is the release deploy key (`RELEASE_DEPLOY_KEY`), which the manual release workflow uses to push its version commit and tag.
- **Releases:** manual (`gh workflow run release.yml`). Python Semantic Release (`releaserc.toml`) bumps both pubspec versions from the Conventional Commits; the workflow builds and attaches the Windows setup and the Android APKs with SHA-256 files, each digest signed (Ed25519, `.sha256.sig`) in a job that runs no repository code. The Android release key comes from the `CAMWATCH_ANDROID_*` secrets and the update signing key from `CAMWATCH_UPDATE_SIGNING_KEY`, never from the repo; the app pins only the public half (`updatePublicKey` in `packages/camwatch_core/lib/src/download.dart`).
- **README stays current:** any user-visible change updates `README.md` in the same PR.
- **UI work uses the design skills:** before changing how anything looks (a screen, a component, spacing, colour, copy on screen), invoke `ui-ux-pro-max` and, where installed, `mobile-app-ui-design`; for layout code, `flutter-build-responsive-layout` and `flutter-fix-layout-issues` (all in `.claude/skills/`). Check the result against them, and put before/after off-screen renders (golden renders in a test, never desktop captures) in the PR.
- **Review agents:** `privacy-auditor` before a PR that adds a dependency, permission or network code; `security-reviewer` (OWASP MASVS plus camwatch's own risks) on changes to network, discovery, credentials, manifests, dependencies or workflows; `ui-reviewer` (renders the changed screens off-screen and judges them against the design skills) after a UI change; `device-tester` to check acceptance criteria on a real phone. Their findings, like the CI reviews', are settled in the same PR. A finding becomes its own issue only when it is outside the PR's scope.
- **Review fallback:** when Claude cannot run (quota, auth, outage), `ai-review.yml` reviews the same range through OpenCode Go (`OPENCODE_API_KEY`), a plain HTTP review of the diff with the same verdict contract.
- **Plan:** the open milestones, by due date, are the roadmap (https://github.com/mfozmen/camwatch/milestones?direction=asc&sort=due_date).

## Comments

Clear code needs no comment. Comment only a non-obvious why, a trap, or a hidden
coupling, in one or two short sentences. No narration, no history, no
commented-out code, no bare issue refs. Before pushing, run
`python tool/check_comments.py origin/main...HEAD`: it costs no tokens.
