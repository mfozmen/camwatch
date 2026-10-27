import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Directory into;
  final bytes = List<int>.generate(300000, (i) => i * 7 % 251);
  late String digest;
  var digestText = '';
  var digestStatus = 200;
  var assetStatus = 200;
  var stall = false;
  final requests = <String>[];

  setUp(() async {
    digest = sha256.convert(bytes).toString();
    digestText = '$digest  camwatch-0.2.0-windows-x64-setup.exe\n';
    digestStatus = 200;
    assetStatus = 200;
    stall = false;
    requests.clear();
    into = await Directory.systemTemp.createTemp('camwatch-test-');
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((request) async {
      requests.add(request.uri.path);
      if (request.uri.path.endsWith('.sha256')) {
        request.response
          ..statusCode = digestStatus
          ..write(digestText);
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

  test('a release names its digest file next to the asset', () {
    expect(release().digest.toString(), '${release().download}.sha256');
  });

  test('downloads the asset into the folder and checks its digest, reporting progress', () async {
    final seen = <(int, int?)>[];
    final file = await downloadVerified(
      release(),
      into: into,
      onProgress: (received, total) => seen.add((received, total)),
    );
    expect(file.path, endsWith('camwatch-0.2.0-windows-x64-setup.exe'));
    expect(await file.readAsBytes(), bytes);
    expect(seen.last, (bytes.length, bytes.length));
    expect(requests, [
      '/download/v0.2.0/camwatch-0.2.0-windows-x64-setup.exe.sha256',
      '/download/v0.2.0/camwatch-0.2.0-windows-x64-setup.exe',
    ]);
  });

  test('a damaged download is deleted and reported', () async {
    digestText = '${'0' * 64}  camwatch-0.2.0-windows-x64-setup.exe\n';
    await expectLater(downloadVerified(release(), into: into), throwsA(isA<DigestMismatch>()));
    expect(into.listSync(), isEmpty);
  });

  test('a digest file that is not one, or missing, stops the download before it starts', () async {
    digestText = '<html>not a digest</html>';
    await expectLater(downloadVerified(release(), into: into), throwsA(isA<HttpException>()));
    expect(requests, hasLength(1));
    digestStatus = 404;
    await expectLater(downloadVerified(release(), into: into), throwsA(isA<HttpException>()));
  });

  test('an asset that is missing or stalls is reported, nothing left behind', () async {
    assetStatus = 404;
    await expectLater(downloadVerified(release(), into: into), throwsA(isA<HttpException>()));
    expect(into.listSync(), isEmpty);
    assetStatus = 200;
    stall = true;
    await expectLater(
      downloadVerified(release(), into: into, idle: const Duration(milliseconds: 300)),
      throwsA(isA<TimeoutException>()),
    );
    expect(into.listSync(), isEmpty);
  });

  test('only this repository\'s release files are ever downloaded', () async {
    final elsewhere = Release(
      '0.2.0',
      Uri.parse('https://example.com/camwatch-0.2.0-windows-x64-setup.exe'),
    );
    await expectLater(downloadVerified(elsewhere, into: into), throwsArgumentError);
    expect(requests, isEmpty);
  });

  test('the digest text is read as sha256sum writes it', () {
    expect(parseDigest('$digest  camwatch-0.2.0.exe\n'), digest);
    expect(parseDigest('$digest *camwatch-0.2.0.exe'), digest);
    expect(parseDigest(digest.toUpperCase()), digest);
    expect(parseDigest('nope'), isNull);
    expect(parseDigest(''), isNull);
    expect(parseDigest(utf8.decode([0xff, 0xfe], allowMalformed: true)), isNull);
  });
}
