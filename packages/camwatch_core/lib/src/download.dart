import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'lan.dart';
import 'update.dart';

/// The downloaded file's SHA-256 is not the one the release published.
class DigestMismatch implements Exception {}

const _downloads = 'https://github.com/mfozmen/camwatch/releases/download/';
final _hex64 = RegExp(r'^[0-9a-fA-F]{64}');

/// The digest in a `.sha256` file as `sha256sum` writes it (`<hex>  <name>`),
/// lower-cased; null when the text is not one.
String? parseDigest(String text) => _hex64.firstMatch(text.trim())?.group(0)?.toLowerCase();

/// Downloads [release]'s asset into [into], named as on the release page,
/// after fetching its `.sha256` next to it; the file is deleted and
/// [DigestMismatch] thrown when the two disagree. Only this repository's
/// release files are fetched (and 127.0.0.1 for tests). [onProgress] gets
/// bytes so far and the total when known; a transfer that stays silent
/// for [idle] is given up.
Future<File> downloadVerified(
  Release release, {
  required Directory into,
  void Function(int received, int? total)? onProgress,
  Duration idle = const Duration(seconds: 30),
}) async {
  final url = release.download;
  if (!url.toString().startsWith(_downloads) && !isLocalIpv4(url.host)) {
    throw ArgumentError.value(url, 'release', 'not a release file of this repository');
  }
  final client = HttpClient();
  final file = File('${into.path}${Platform.pathSeparator}${url.pathSegments.last}');
  try {
    final expected = parseDigest(await _text(client, release.digest, idle));
    if (expected == null) throw HttpException('no digest for $url', uri: release.digest);
    final response = await _open(client, url, idle);
    final total = response.contentLength < 0 ? null : response.contentLength;
    final sink = file.openWrite();
    final digests = <Digest>[];
    final hasher = sha256.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback(digests.addAll),
    );
    var received = 0;
    try {
      await for (final chunk in response.timeout(idle)) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
    hasher.close();
    if (digests.single.toString() != expected) throw DigestMismatch();
    return file;
  } catch (_) {
    if (await file.exists()) await file.delete();
    rethrow;
  } finally {
    client.close(force: true);
  }
}

Future<HttpClientResponse> _open(HttpClient client, Uri url, Duration idle) async {
  final request = await client.getUrl(url).timeout(idle);
  // GitHub serves release files through a redirect to its CDN; nothing else is followed.
  request.followRedirects = true;
  request.maxRedirects = 3;
  final response = await request.close().timeout(idle);
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('${response.statusCode} from $url', uri: url);
  }
  return response;
}

Future<String> _text(HttpClient client, Uri url, Duration idle) async {
  final response = await _open(client, url, idle);
  // A digest file is one line; anything longer is not one.
  final bytes = <int>[];
  await for (final chunk in response.timeout(idle)) {
    bytes.addAll(chunk);
    if (bytes.length > 1024) throw HttpException('digest file too long', uri: url);
  }
  return utf8.decode(bytes, allowMalformed: true);
}
