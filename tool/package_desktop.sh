#!/usr/bin/env bash
# Packages the built Windows app: the setup.exe and its .sha256 (sha256sum
# format, LF). Used by the release workflow and, to check the packaging on every
# PR, by flutter.yml.
#
#   tool/package_desktop.sh <version> <out-dir> <Release|Debug>
#
# Run from the repo root after `flutter build windows`. Needs Inno Setup 6
# (choco install innosetup).
set -euo pipefail

version=$1
mkdir -p "$2"
out=$(cd "$2" && pwd)
mode=$3
app=apps/camwatch

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) ;;
  *)
    echo "no desktop package for $(uname -s)" >&2
    exit 1
    ;;
esac

built="$(pwd)/$app/build/windows/x64/runner/$mode" # absolute: iscc resolves paths from the .iss
setup="camwatch-$version-windows-x64-setup"
# MSYS_NO_PATHCONV: Git Bash would turn the /D, /O and /F flags into paths.
MSYS_NO_PATHCONV=1 "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" /Q \
  "/DAppVersion=$version" "/DSourceDir=$(cygpath -w "$built")" \
  "/O$(cygpath -w "$out")" "/F$setup" "$(cygpath -w "$app/windows/installer/camwatch.iss")"
(cd "$out" && sha256sum "$setup.exe" > "$setup.exe.sha256")
ls -l "$out"
