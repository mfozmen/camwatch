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

/// Asks [api] (GitHub's latest-release endpoint) and returns the release when
/// it is newer than [current] and has a build for [abi]. Throws when the API
/// cannot be reached or does not answer 200.
Future<Release?> fetchLatestRelease(Uri api, {required String current, required Abi abi}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(api);
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('${response.statusCode} from $api', uri: api);
    }
    return newerRelease(await utf8.decodeStream(response), current: current, abi: abi);
  } finally {
    client.close();
  }
}

/// Reads GitHub's release JSON; null unless it is newer than [current] and
/// carries an https asset built for [abi].
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
    if (url == null || url.scheme != 'https') return null;
    return Release(tag.substring(1), url);
  }
  return null;
}

final _version = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$');

List<int>? _parts(String version) =>
    _version.firstMatch(version)?.groups([1, 2, 3]).map((n) => int.parse(n!)).toList();

bool _newer(String tag, String current) {
  final a = _parts(tag);
  final b = _parts(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}
