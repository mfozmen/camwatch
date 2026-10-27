import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import 'update.dart';

/// The downloaded file's SHA-256 is not the one the release published.
class DigestMismatch implements Exception {}

/// The digest file was not signed by the release signing key: whatever
/// served it, it is not a camwatch release.
class SignatureMismatch implements Exception {}

/// The release signing key's public half; its private half lives only in
/// the release workflow's secret. Rotating it orphans every shipped app.
final updatePublicKey = base64.decode('WG4bUpOqRriz78Mcad5nyCJ8s1DmVzfUpA7JuUzEIjk=');

const _downloads = 'https://github.com/mfozmen/camwatch/releases/download/';
const _loopback = '127.0.0.1';
final _digestLine = RegExp(r'^([0-9a-fA-F]{64})(?:\s+\*?(\S+))?');

/// The digest in a `.sha256` file as `sha256sum` writes it (`<hex>  <name>`):
/// the hex lower-cased and the file it names ('' when it names none); null
/// when the text is not one.
(String, String)? parseDigest(String text) {
  final match = _digestLine.firstMatch(text.trim());
  if (match == null) return null;
  return (match.group(1)!.toLowerCase(), match.group(2) ?? '');
}

/// Downloads [release]'s asset into [into], named as on the release page,
/// after fetching its `.sha256` and the signature of that file next to it:
/// [SignatureMismatch] when [publicKey] does not vouch for the digest, so
/// the asset is never fetched; the file is deleted and [DigestMismatch]
/// thrown when it does not match the digest. Only this repository's release
/// files are fetched (and 127.0.0.1 for tests). [onProgress] gets bytes so
/// far and the total when known; a transfer that stays silent for [idle],
/// or grows past [maxBytes], is given up.
Future<File> downloadVerified(
  Release release, {
  required Directory into,
  required List<int> publicKey,
  void Function(int received, int? total)? onProgress,
  Duration idle = const Duration(seconds: 30),
  int maxBytes = 256 << 20,
}) async {
  final url = release.download;
  if (!url.toString().startsWith(_downloads) && url.host != _loopback) {
    throw ArgumentError.value(url, 'release', 'not a release file of this repository');
  }
  final client = HttpClient();
  final file = File('${into.path}${Platform.pathSeparator}${url.pathSegments.last}');
  try {
    final signature = await _small(client, release.signature, idle);
    final digestFile = await _small(client, release.digest, idle);
    if (!await _signed(digestFile, signature, publicKey)) throw SignatureMismatch();
    final parsed = parseDigest(utf8.decode(digestFile, allowMalformed: true));
    if (parsed == null) throw HttpException('no digest for $url', uri: release.digest);
    final (expected, named) = parsed;
    // The signed line names its file, version included: a signature for
    // another release's file, served in this one's place, proves nothing here.
    if (named != url.pathSegments.last) throw SignatureMismatch();
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
        if (received > maxBytes) throw HttpException('larger than any release', uri: url);
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

/// GitHub answers a release file with a redirect to its download servers;
/// every hop must stay with them (or on the loopback test server), and the
/// chain is followed by hand so a stranger's address is never dialled.
Future<HttpClientResponse> _open(HttpClient client, Uri url, Duration idle) async {
  var target = url;
  for (var hop = 0; hop <= _maxRedirects; hop++) {
    final request = await client.getUrl(target).timeout(idle);
    request.followRedirects = false;
    final response = await request.close().timeout(idle);
    if (response.statusCode == HttpStatus.ok) return response;
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (!response.isRedirect || location == null) {
      throw HttpException('${response.statusCode} from $target', uri: target);
    }
    await response.drain<void>();
    target = target.resolve(location);
    if (!trustedRedirect(target, url)) throw HttpException('redirected off GitHub', uri: url);
  }
  throw HttpException('too many redirects', uri: url);
}

const _maxRedirects = 3;

/// Whether a redirect from [origin] to [target] may be followed: GitHub's
/// own hosts over https, or the loopback test server to itself.
bool trustedRedirect(Uri target, Uri origin) {
  if (origin.host == _loopback) return target.host == _loopback;
  return target.scheme == 'https' &&
      (target.host == 'github.com' || target.host.endsWith('.githubusercontent.com'));
}

/// Whether [signature] (base64 text) is [publicKey]'s Ed25519 signature of
/// [message], the digest file's exact bytes.
Future<bool> _signed(List<int> message, List<int> signature, List<int> publicKey) async {
  List<int> bytes;
  try {
    bytes = base64.decode(utf8.decode(signature).trim());
  } on FormatException {
    return false;
  }
  if (bytes.length != 64) return false;
  return Ed25519().verify(
    message,
    signature: Signature(bytes, publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)),
  );
}

Future<List<int>> _small(HttpClient client, Uri url, Duration idle) async {
  final response = await _open(client, url, idle);
  // A digest or a signature is one line; anything longer is not one.
  final bytes = <int>[];
  await for (final chunk in response.timeout(idle)) {
    bytes.addAll(chunk);
    if (bytes.length > 1024) throw HttpException('too long for $url', uri: url);
  }
  return bytes;
}
