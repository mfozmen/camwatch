import 'dart:ffi';
import 'dart:io';

/// A newer build of the app on GitHub: its version and the asset for this machine.
class Release {
  const Release(this.version, this.download);

  final String version;
  final Uri download;
}

/// GitHub answered 403 or 429: the shared address has spent its budget for
/// now, which is not the same as being unreachable.
class GitHubBusy implements Exception {}

/// The newest release of camwatch, as the page that redirects to its tag.
/// The one request that leaves the local network, opt-in; the web page has
/// no per-address quota the way the API does.
final latestReleasePage = Uri.parse('https://github.com/mfozmen/camwatch/releases/latest');

/// Where that redirect must point, and where the builds are.
const _tagPages = 'https://github.com/mfozmen/camwatch/releases/tag/';
const _downloads = 'https://github.com/mfozmen/camwatch/releases/download/';

const _assetFor = {
  Abi.androidArm64: 'android-arm64-v8a.apk',
  Abi.androidArm: 'android-armeabi-v7a.apk',
  Abi.androidX64: 'android-x86_64.apk',
  Abi.windowsX64: 'windows-x64-setup.exe',
};

/// Asks [page] (GitHub's latest-release page) where it redirects and reads
/// the tag out of that, never following it. Returns the release when it is
/// newer than [current] and has a build for [abi]. Throws [GitHubBusy] on
/// 403 or 429, [HttpException] on any other answer than a redirect to this
/// repository's tag pages, or on nothing within [timeout].
Future<Release?> fetchLatestRelease(
  Uri page, {
  required String current,
  required Abi abi,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final client = HttpClient();
  try {
    return await _fetch(client, page, current: current, abi: abi).timeout(timeout);
  } finally {
    client.close(force: true);
  }
}

Future<Release?> _fetch(
  HttpClient client,
  Uri page, {
  required String current,
  required Abi abi,
}) async {
  final request = await client.getUrl(page);
  request.followRedirects = false;
  final response = await request.close();
  final status = response.statusCode;
  final location = response.headers.value(HttpHeaders.locationHeader) ?? '';
  await response.drain<void>();
  if (status == HttpStatus.forbidden || status == HttpStatus.tooManyRequests) throw GitHubBusy();
  if (status < 300 || status > 399 || !location.startsWith(_tagPages)) {
    throw HttpException('$status from $page', uri: page);
  }
  return releaseFromTag(location.substring(_tagPages.length), current: current, abi: abi);
}

/// The release a tag names, by the release workflow's file naming; null
/// unless it is newer than [current] and there is a build for [abi].
Release? releaseFromTag(String tag, {required String current, required Abi abi}) {
  final suffix = _assetFor[abi];
  if (suffix == null || !_newer(tag, current)) return null;
  final version = tag.replaceFirst('v', '');
  return Release(version, Uri.parse('$_downloads$tag/camwatch-$version-$suffix'));
}

final _version = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$');

List<int>? _parts(String version) {
  final parts = _version.firstMatch(version)?.groups([1, 2, 3]).map((n) => int.tryParse(n!));
  return parts == null || parts.contains(null) ? null : parts.cast<int>().toList();
}

bool _newer(String tag, String current) {
  final a = _parts(tag);
  final b = _parts(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}
