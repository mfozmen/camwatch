import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// A newer build of the app on GitHub: its version and the asset for this machine.
class Release {
  const Release(this.version, this.download);

  final String version;
  final Uri download;
}

/// The newest release of camwatch; the one request that leaves the local network, opt-in.
final releasesApi = Uri.parse('https://api.github.com/repos/mfozmen/camwatch/releases/latest');

const _assetFor = {
  Abi.androidArm64: 'android-arm64-v8a.apk',
  Abi.androidArm: 'android-armeabi-v7a.apk',
  Abi.androidX64: 'android-x86_64.apk',
  Abi.windowsX64: 'windows-x64-setup.exe',
};

/// Only a file GitHub serves for this repository's releases is ever opened.
const _downloads = 'https://github.com/mfozmen/camwatch/releases/download/';

/// A release listing is a few kilobytes; anything longer is not one.
const _maxReply = 256 * 1024;

/// Asks [api] (GitHub's latest-release endpoint) and returns the release when
/// it is newer than [current] and has a build for [abi]. Throws when the API
/// cannot be reached within [timeout] or does not answer 200.
Future<Release?> fetchLatestRelease(
  Uri api, {
  required String current,
  required Abi abi,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final client = HttpClient();
  try {
    return await _fetch(client, api, current: current, abi: abi).timeout(timeout);
  } finally {
    client.close(force: true);
  }
}

Future<Release?> _fetch(
  HttpClient client,
  Uri api, {
  required String current,
  required Abi abi,
}) async {
  final request = await client.getUrl(api);
  // A 3xx would re-send the request wherever it points; the API alone may hear from us.
  request.followRedirects = false;
  request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
  final response = await request.close();
  if (response.statusCode != 200) throw HttpException('${response.statusCode} from $api', uri: api);
  final body = <int>[];
  await for (final chunk in response) {
    body.addAll(chunk);
    if (body.length > _maxReply) throw HttpException('reply too long', uri: api);
  }
  return newerRelease(utf8.decode(body), current: current, abi: abi);
}

/// Reads GitHub's release JSON; null unless it is newer than [current] and
/// carries an asset built for [abi] among this repository's release downloads.
Release? newerRelease(String json, {required String current, required Abi abi}) {
  final suffix = _assetFor[abi];
  if (suffix == null) return null;
  final release = jsonDecode(json);
  if (release is! Map) return null;
  final tag = release['tag_name'];
  if (tag is! String || !_newer(tag, current)) return null;
  final assets = release['assets'];
  if (assets is! List) return null;
  for (final asset in assets) {
    final name = asset is Map ? asset['name'] : null;
    final link = asset is Map ? asset['browser_download_url'] : null;
    if (name is! String || link is! String || !name.endsWith('-$suffix')) continue;
    final url = Uri.tryParse(link);
    if (url == null || !link.startsWith(_downloads)) return null;
    return Release(tag.replaceFirst('v', ''), url);
  }
  return null;
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
