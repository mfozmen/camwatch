# camwatch

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_camwatch&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=mfozmen_camwatch)
[![Coverage](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_camwatch&metric=coverage)](https://sonarcloud.io/summary/new_code?id=mfozmen_camwatch)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_camwatch&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=mfozmen_camwatch)
[![Release](https://img.shields.io/github/v/release/mfozmen/camwatch)](https://github.com/mfozmen/camwatch/releases/latest)

Find the cameras on your network, see how exposed each one is, and watch the
ones you can reach. On Android and Windows.

- **Discover:** scans your local network for cameras (open camera ports, ONVIF).
- **Grade:** flags what makes a camera easy to break into: a stream anyone can
  watch, telnet left open, a web page without HTTPS.
- **Watch:** plays the RTSP streams it can reach, with your password when needed.

No account, no server, no trackers. camwatch only ever talks to devices on your
own network, and camera passwords stay in your device's secure storage.

> Early days: the app is being built in the open. See the
> [roadmap](https://github.com/mfozmen/camwatch/milestones?direction=asc&sort=due_date).

## Install

Download the latest release from
[Releases](https://github.com/mfozmen/camwatch/releases/latest):

- **Android:** `camwatch-<version>-android-arm64-v8a.apk` for most phones
  (`-android.apk` works on any).
- **Windows:** `camwatch-<version>-windows-x64-setup.exe`. It installs for you
  only and needs no admin rights.

Each file has a `.sha256` next to it.

## Use

Open camwatch and tap **Scan network**. It probes every address on your
subnet for the usual camera ports and asks for ONVIF cameras, then lists each
device it found with its open ports and an **ONVIF** badge when the camera
answered. A scan takes a few seconds. Tap a device with an RTSP port to
watch its stream: camwatch tries the common stream paths and plays the first
one that needs no password. When every path asks for one, enter the camera's
username and password; they go into your device's secure storage (the Android
Keystore, DPAPI on Windows) and are used again the next time, never written to
a file or a log.

## Only scan networks you own

camwatch probes the devices on the network you are connected to. Use it on your
own network, or one you have permission to test.

## Development

Requires [Flutter](https://docs.flutter.dev/get-started/install) (the version
pinned in the root `pubspec.yaml`). The repo is a Dart pub workspace:

| Path | What |
|---|---|
| `packages/camwatch_core` | pure Dart: subnet math, discovery, RTSP/ONVIF parsing, security rules |
| `apps/camwatch` | the Flutter app: Android and Windows |

```bash
flutter pub get
(cd packages/camwatch_core && dart test)
(cd apps/camwatch && flutter test)
(cd apps/camwatch && flutter run)
```

Contributions go through pull requests with Conventional Commit titles; every
line is covered by tests. See [CLAUDE.md](CLAUDE.md) for the full rules.

## License

[MIT](LICENSE)
