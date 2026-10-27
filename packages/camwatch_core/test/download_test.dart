import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Directory into;
  final bytes = List<int>.generate(300000, (i) => i * 7 % 251);
  late String digest;
  var digestText = '';
  var digestStatus = 200;
  var signatureText = '';
  var signatureStatus = 200;
  late SimpleKeyPair keyPair;
  late List<int> publicKey;

  setUpAll(() async {
    keyPair = await Ed25519().newKeyPair();
    publicKey = (await keyPair.extractPublicKey()).bytes;
  });

  Future<String> sign(String text) async {
    final signature = await Ed25519().sign(utf8.encode(text), keyPair: keyPair);
    return '${base64.encode(signature.bytes)}\n';
  }

  var assetStatus = 200;
  var stall = false;
  var redirectTo = '';
  final requests = <String>[];

  setUp(() async {
    digest = sha256.convert(bytes).toString();
    digestText = '$digest  camwatch-0.2.0-windows-x64-setup.exe\n';
    digestStatus = 200;
    signatureText = await sign(digestText);
    signatureStatus = 200;
    assetStatus = 200;
    stall = false;
    redirectTo = '';
    requests.clear();
    into = await Directory.systemTemp.createTemp('camwatch-test-');
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((request) async {
      requests.add(request.uri.path);
      if (request.uri.path.endsWith('.sig')) {
        request.response
          ..statusCode = signatureStatus
          ..write(signatureText);
        await request.response.close();
        return;
      }
      if (request.uri.path.endsWith('.sha256')) {
        request.response
          ..statusCode = digestStatus
          ..write(digestText);
        await request.response.close();
        return;
      }
      if (redirectTo.isNotEmpty && !request.uri.path.endsWith('/real')) {
        request.response
          ..statusCode = 302
          ..headers.set('location', redirectTo);
        await request.response.close();
        return;
      }
      request.response.statusCode = assetStatus;
      if (stall) {
        request.response.add(bytes.sublist(0, 1000));
        await request.response.flush();
        return;
      }
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (await into.exists()) await into.delete(recursive: true);
  });

  Release release() => Release(
    '0.2.0',
    Uri.parse(
      'http://127.0.0.1:${server.port}/download/v0.2.0/camwatch-0.2.0-windows-x64-setup.exe',
    ),
  );

  test('a release names its digest and signature files next to the asset', () {
    expect(release().digest.toString(), '${release().download}.sha256');
    expect(release().signature.toString(), '${release().download}.sha256.sig');
  });

  test('the request order is signature, digest, asset: nothing big before the proof', () async {
    await downloadVerified(release(), into: into, publicKey: publicKey);
    expect(requests.first, endsWith('.sha256.sig'));
    expect(requests.last, endsWith('setup.exe'));
  });

  test('a digest signed with another key, altered, or unsigned is refused', () async {
    final other = await Ed25519().newKeyPair();
    final forged = await Ed25519().sign(utf8.encode(digestText), keyPair: other);
    signatureText = base64.encode(forged.bytes);
    await expectLater(
      downloadVerified(release(), into: into, publicKey: publicKey),
      throwsA(isA<SignatureMismatch>()),
    );
    signatureText = await sign(digestText);
    digestText = digestText.replaceFirst('setup.exe', 'setup.exe ');
    await expectLater(
      downloadVerified(release(), into: into, publicKey: publicKey),
      throwsA(isA<SignatureMismatch>()),
    );
    expect(requests.where((p) => p.endsWith('setup.exe')), isEmpty, reason: 'never fetched');
    signatureStatus = 404;
    await expectLater(
      downloadVerified(release(), into: into, publicKey: publicKey),
      throwsA(isA<HttpException>()),
    );
    signatureStatus = 200;
    signatureText = 'not base64 at all!';
    await expectLater(
      downloadVerified(release(), into: into, publicKey: publicKey),
      throwsA(isA<SignatureMismatch>()),
    );
    signatureText = 'AAAA';
    await expectLater(
      downloadVerified(release(), into: into, publicKey: publicKey),
      throwsA(isA<SignatureMismatch>()),
      reason: 'well-formed base64 of the wrong length is no signature either',
    );
  });

  test('a signed digest for another file, or another version, is refused', () async {
    digestText = '$digest  camwatch-0.2.0-android-arm64-v8a.apk\n';
    signatureText = await sign(digestText);
    await expectLater(
      downloadVerified(release(), into: into, publicKey: publicKey),
      throwsA(isA<SignatureMismatch>()),
    );
    digestText = '$digest  camwatch-0.1.0-windows-x64-setup.exe\n';
    signatureText = await sign(digestText);
    await expectLater(
      downloadVerified(release(), into: into, publicKey: publicKey),
      throwsA(isA<SignatureMismatch>()),
    );
    expect(requests.where((p) => p.endsWith('setup.exe')), isEmpty, reason: 'never fetched');
  });

  test('the app pins the release signing key', () {
    expect(updatePublicKey, hasLength(32));
    expect(base64.encode(updatePublicKey), 'WG4bUpOqRriz78Mcad5nyCJ8s1DmVzfUpA7JuUzEIjk=');
  });

  test('downloads the asset into the folder and checks its digest, reporting progress', () async {
    final seen = <(int, int?)>[];
    final file = await downloadVerified(
      release(),
      into: into,
      publicKey: publicKey,
      onProgress: (received, total) => seen.add((received, total)),
    );
    expect(file.path, endsWith('camwatch-0.2.0-windows-x64-setup.exe'));
    expect(await file.readAsBytes(), bytes);
    expect(seen.last, (bytes.length, bytes.length));
    expect(requests, [
      '/download/v0.2.0/camwatch-0.2.0-windows-x64-setup.exe.sha256.sig',
      '/download/v0.2.0/camwatch-0.2.0-windows-x64-setup.exe.sha256',
      '/download/v0.2.0/camwatch-0.2.0-windows-x64-setup.exe',
    ]);
  });

  test('a damaged download is deleted and reported', () async {
    digestText = '${'0' * 64}  camwatch-0.2.0-windows-x64-setup.exe\n';
    signatureText = await sign(digestText);
    await expectLater(
      downloadVerified(release(), into: into, publicKey: publicKey),
      throwsA(isA<DigestMismatch>()),
    );
    expect(into.listSync(), isEmpty);
  });

  test('a digest file that is not one, or missing, stops the download before it starts', () async {
    digestText = '<html>not a digest</html>';
    signatureText = await sign(digestText);
    await expectLater(
      downloadVerified(release(), into: into, publicKey: publicKey),
      throwsA(isA<HttpException>()),
    );
    expect(requests, hasLength(2), reason: 'the signature and the digest, no asset');
    digestStatus = 404;
    await expectLater(
      downloadVerified(release(), into: into, publicKey: publicKey),
      throwsA(isA<HttpException>()),
    );
  });

  test('an asset that is missing or stalls is reported, nothing left behind', () async {
    assetStatus = 404;
    await expectLater(
      downloadVerified(release(), into: into, publicKey: publicKey),
      throwsA(isA<HttpException>()),
    );
    expect(into.listSync(), isEmpty);
    assetStatus = 200;
    stall = true;
    await expectLater(
      downloadVerified(
        release(),
        into: into,
        publicKey: publicKey,
        idle: const Duration(milliseconds: 300),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(into.listSync(), isEmpty);
  });

  test('a redirect stays on the same server, never a stranger, and is not chased', () async {
    redirectTo = 'http://127.0.0.1:${server.port}/download/v0.2.0/real';
    final file = await downloadVerified(release(), into: into, publicKey: publicKey);
    expect(await file.readAsBytes(), bytes);
    redirectTo = 'http://example.invalid/camwatch-0.2.0-windows-x64-setup.exe';
    requests.clear();
    await expectLater(
      downloadVerified(release(), into: into, publicKey: publicKey),
      throwsA(isA<HttpException>()),
    );
    expect(requests, hasLength(3), reason: 'signature, digest, asset; nothing after the redirect');
    redirectTo =
        'http://127.0.0.1:${server.port}/download/v0.2.0/camwatch-0.2.0-windows-x64-setup.exe';
    await expectLater(
      downloadVerified(release(), into: into, publicKey: publicKey),
      throwsA(isA<HttpException>()),
    );
    expect(into.listSync(), isEmpty);
  });

  test('a file past the cap is cut off and removed', () async {
    await expectLater(
      downloadVerified(release(), into: into, maxBytes: 1000, publicKey: publicKey),
      throwsA(isA<HttpException>()),
    );
    expect(into.listSync(), isEmpty);
  });

  test('only this repository\'s release files are ever downloaded', () async {
    final elsewhere = Release(
      '0.2.0',
      Uri.parse('https://example.com/camwatch-0.2.0-windows-x64-setup.exe'),
    );
    await expectLater(
      downloadVerified(elsewhere, into: into, publicKey: publicKey),
      throwsArgumentError,
    );
    final lan = Release(
      '0.2.0',
      Uri.parse('http://192.168.1.9/camwatch-0.2.0-windows-x64-setup.exe'),
    );
    await expectLater(downloadVerified(lan, into: into, publicKey: publicKey), throwsArgumentError);
    expect(requests, isEmpty);
  });

  test('a redirect from GitHub may only land on GitHub, over https', () {
    final origin = Uri.parse('https://github.com/mfozmen/camwatch/releases/download/v1/x.exe');
    expect(trustedRedirect(Uri.parse('https://objects.githubusercontent.com/x'), origin), isTrue);
    expect(trustedRedirect(Uri.parse('https://github.com/x'), origin), isTrue);
    expect(trustedRedirect(Uri.parse('http://objects.githubusercontent.com/x'), origin), isFalse);
    expect(
      trustedRedirect(Uri.parse('https://githubusercontent.com.evil.example/x'), origin),
      isFalse,
    );
    expect(trustedRedirect(Uri.parse('https://example.com/x'), origin), isFalse);
  });

  test('the digest text is read as sha256sum writes it: the hex and the file it names', () {
    expect(parseDigest('$digest  camwatch-0.2.0.exe\n'), (digest, 'camwatch-0.2.0.exe'));
    expect(parseDigest('$digest *camwatch-0.2.0.exe'), (digest, 'camwatch-0.2.0.exe'));
    expect(parseDigest(digest.toUpperCase()), (digest, ''));
    expect(parseDigest('nope'), isNull);
    expect(parseDigest(''), isNull);
    expect(parseDigest(utf8.decode([0xff, 0xfe], allowMalformed: true)), isNull);
  });
}
