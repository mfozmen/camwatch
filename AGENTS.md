# Codex instructions

Read `CLAUDE.md` before changing or reviewing this repository. It is the shared
project guide for Claude and Codex: follow its privacy promise, architecture,
testing, language, branch and PR rules. Never read `.env` or keystores.

## Code Review Rules

Check changed code against `CLAUDE.md`:

- Flag any traffic that can leave the local network, any third-party SDK or
  telemetry, and any credential or `user:password@` URL that can reach a log,
  file or backup.
- Flag cross-platform breakage and untested logic. Cite the file and line for
  each finding. Do not approve or merge on the author's behalf.
