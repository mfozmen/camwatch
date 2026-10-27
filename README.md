# camwatch

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_camwatch&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=mfozmen_camwatch)
[![Coverage](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_camwatch&metric=coverage)](https://sonarcloud.io/summary/new_code?id=mfozmen_camwatch)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_camwatch&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=mfozmen_camwatch)
[![Release](https://img.shields.io/github/v/release/mfozmen/camwatch)](https://github.com/mfozmen/camwatch/releases/latest)

Find the cameras on your network, see how exposed each one is, and watch the
ones you can reach. On Android and Windows.

- **Discover:** scans your local network for cameras (open camera ports, ONVIF, mDNS),
  then checks each one for FTP, SSH, telnet, HTTPS and the XMeye and Dahua ports.
- **Grade:** flags what makes a camera easy to break into: a stream anyone can
  watch, telnet or the XMeye DVR port left open, a web page without HTTPS, SSH,
  FTP or a vendor control port open.
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

Open camwatch and tap **Scan network**. The first time, it asks you to confirm
that the network is yours or one you may test; after that it probes every address on your
subnet for the usual camera ports, asks for ONVIF cameras and asks over mDNS for
announced services (`_rtsp._tcp`, `_onvif._tcp`; an announced port is listed only once a
connection confirms it), then lists each
device it found with its open ports, an **ONVIF** badge when the camera
answered, and its grade: **Exposed** (red), **At risk** (amber) or **No issues
found** (green). A scan takes a few seconds; the stream of each RTSP device is
checked right after it. Tap a device for its report: every finding with what
to do about it, worst first. The play button next to a device with an RTSP
port watches its stream: camwatch tries the common stream paths and plays the
first one that needs no password. When every path asks for one, enter the camera's
username and password. They go into your device's secure storage (the Android
Keystore, DPAPI on Windows), tied to that address, and are used again the next
time; they are never written to a file or a log. The player reaches the camera
through a relay inside the app: a camera that answers with a redirect is cut
off there, so the stream library never sees the new address, which could be
outside your network, and never follows it.

The bookmark on a device with a stream saves it. Saved cameras fill a live grid
when you open the app, before any scan: each tile plays its stream (with the
kept login when the camera asks for one, a lock when there is none yet), a tap
opens it full screen, and the tile's menu removes it (**Undo** is offered for a
moment). The grid streams only while it is on screen: opening a camera or
leaving the app stops every tile. The list is kept on your device only, next
to the logins; a scan shows the found devices again, with the saved ones marked.

Until camwatch is in the app stores, new versions come from the
[releases page](https://github.com/mfozmen/camwatch/releases). The **Check for
updates** button at the top asks github.com for the newest release; the first
tap explains that this is the only request that ever leaves your network and
asks before sending it. Once accepted, the app also checks quietly each time it
starts and shows a banner when a newer version is out: **Download** opens the
build for your device (the APK for your phone's processor, the Windows setup)
in your browser. Install it over the old one. Nothing about you or your cameras
is sent; **Not now** keeps the app fully offline, and **Stop checking** on a
later check turns it off again.

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

Found a security problem? Report it privately, never in an issue: see
[SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
