"""Tests for sensitive_paths: which changed files call for the security pass.
No network; one test builds a throwaway git repository. Run by ci.yml:

    python3 .github/scripts/test_sensitive_paths.py
"""

import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sensitive_paths import base_ref, changed_files, sensitive

cases = [
    ("the LAN guard", "packages/camwatch_core/lib/src/lan.dart", True),
    ("a discovery probe", "packages/camwatch_core/lib/src/discovery/port_scan.dart", True),
    ("RTSP parsing", "packages/camwatch_core/lib/src/rtsp_url.dart", True),
    ("ONVIF", "packages/camwatch_core/lib/src/onvif_probe.dart", True),
    ("credential storage", "apps/camwatch/lib/src/credential_store.dart", True),
    ("the Android manifest", "apps/camwatch/android/app/src/main/AndroidManifest.xml", True),
    ("an Android build file", "apps/camwatch/android/app/build.gradle.kts", True),
    ("Android backup rules", "apps/camwatch/android/app/src/main/res/xml/data_extraction_rules.xml", True),
    ("the Windows installer", "apps/camwatch/windows/installer/camwatch.iss", True),
    ("a package's dependencies", "apps/camwatch/pubspec.yaml", True),
    ("the workspace's lock file", "pubspec.lock", True),
    ("a workflow", ".github/workflows/release.yml", True),
    ("a CI script", ".github/scripts/review_range.py", True),
    ("the security reviewer itself", ".claude/agents/security-reviewer.md", True),
    ("Claude Code's project settings", ".claude/settings.json", True),
    ("a screen", "apps/camwatch/lib/src/grid.dart", False),
    ("a test", "packages/camwatch_core/test/lan_test.dart", False),
    ("the README", "README.md", False),
]

failures = 0
for name, path, want in cases:
    got = bool(sensitive([path]))
    ok = got == want
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name} ({path}): got {got}, want {want}")

got = sensitive(["README.md", "packages/camwatch_core/lib/src/lan.dart", "docs/x.md"])
ok = got == ["packages/camwatch_core/lib/src/lan.dart"]
failures += not ok
print(f"{'ok  ' if ok else 'FAIL'} a mixed change names only its sensitive files: got {got}")

for name, env, want in [
    ("a security range wins over the PR base", {"RANGE_BASE": "abc", "BASE_REF": "def"}, "abc"),
    ("the PR base is the fallback", {"BASE_REF": "def"}, "def"),
    ("the default base is main", {}, "origin/main"),
]:
    got = base_ref(env)
    ok = got == want
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: got {got}, want {want}")


# A sensitive file renamed to an ordinary path must still count: git would
# report the rename under its new name only.
with tempfile.TemporaryDirectory() as repo:
    def git(*args):
        subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True)

    git("init", "-q", "-b", "main")
    git("config", "user.email", "t@t")
    git("config", "user.name", "t")
    secret = Path(repo, "packages/camwatch_core/lib/src/lan.dart")
    secret.parent.mkdir(parents=True)
    secret.write_text("the hash\n" * 20, encoding="utf-8")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    git("branch", "base")
    Path(repo, "docs").mkdir()
    git("mv", "packages/camwatch_core/lib/src/lan.dart", "docs/notes.md")
    git("commit", "-q", "-m", "hide it")
    got = sensitive(changed_files("base", cwd=repo))
    ok = got == ["packages/camwatch_core/lib/src/lan.dart"]
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} a renamed sensitive file still counts: got {got}")

sys.exit(1 if failures else 0)
