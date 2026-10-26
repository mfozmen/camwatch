import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:test/test.dart';

const base = 'https://github.com/mfozmen/camwatch/releases/download/v0.2.0/';

String release(String tag, [List<String> names = const []]) => jsonEncode({
  'tag_name': tag,
  'assets': [
    for (final name in names) {'name': name, 'browser_download_url': '$base$name'},
  ],
});

const assets = [
  'camwatch-0.2.0-android-arm64-v8a.apk',
  'camwatch-0.2.0-android-arm64-v8a.apk.sha256',
  'camwatch-0.2.0-android-armeabi-v7a.apk',
  'camwatch-0.2.0-android-x86_64.apk',
  'camwatch-0.2.0-android.apk',
  'camwatch-0.2.0-windows-x64-setup.exe',
  'camwatch-0.2.0-windows-x64-setup.exe.sha256',
];

void main() {
  test('the release API is GitHub over https', () {
    expect(releasesApi.scheme, 'https');
    expect(releasesApi.host, 'api.github.com');
    expect(releasesApi.path, '/repos/mfozmen/camwatch/releases/latest');
  });

  group('newerRelease', () {
    test('names the version and the asset built for this ABI', () {
      final json = release('v0.2.0', assets);
      final found = newerRelease(json, current: '0.1.0', abi: Abi.androidArm64);
      expect(found?.version, '0.2.0');
      expect(found?.download, Uri.parse('${base}camwatch-0.2.0-android-arm64-v8a.apk'));
      expect(
        newerRelease(json, current: '0.1.0', abi: Abi.androidArm)?.download.path,
        endsWith('camwatch-0.2.0-android-armeabi-v7a.apk'),
      );
      expect(
        newerRelease(json, current: '0.1.0', abi: Abi.androidX64)?.download.path,
        endsWith('camwatch-0.2.0-android-x86_64.apk'),
      );
      expect(
        newerRelease(json, current: '0.1.0', abi: Abi.windowsX64)?.download.path,
        endsWith('camwatch-0.2.0-windows-x64-setup.exe'),
      );
    });

    test('compares versions as numbers, not strings', () {
      expect(
        newerRelease(release('v0.10.0', assets), current: '0.9.1', abi: Abi.windowsX64),
        isNotNull,
      );
      expect(
        newerRelease(release('v1.0.0', assets), current: '1.0.0', abi: Abi.windowsX64),
        isNull,
      );
      expect(
        newerRelease(release('v0.1.0', assets), current: '0.1.1', abi: Abi.windowsX64),
        isNull,
      );
    });

    test('is null when nothing fits: no build for the ABI, no https link, no version', () {
      expect(newerRelease(release('v0.2.0', assets), current: '0.1.0', abi: Abi.linuxX64), isNull);
      expect(newerRelease(release('v0.2.0'), current: '0.1.0', abi: Abi.windowsX64), isNull);
      expect(
        newerRelease(release('latest', assets), current: '0.1.0', abi: Abi.windowsX64),
        isNull,
      );
      expect(newerRelease('{}', current: '0.1.0', abi: Abi.windowsX64), isNull);
      final http = release('v0.2.0', assets).replaceAll('https://', 'http://');
      expect(newerRelease(http, current: '0.1.0', abi: Abi.windowsX64), isNull);
    });
  });

  group('fetchLatestRelease', () {
    late HttpServer server;
    final requests = <HttpRequest>[];
    var status = 200;
    final body = release('v0.2.0', assets);

    setUp(() async {
      requests.clear();
      status = 200;
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) {
        requests.add(request);
        request.response
          ..statusCode = status
          ..write(body)
          ..close();
      });
    });
    tearDown(() => server.close());

    Uri api() => Uri.parse('http://127.0.0.1:${server.port}/releases/latest');

    test('asks the API for JSON and reads the release out of the reply', () async {
      final found = await fetchLatestRelease(api(), current: '0.1.0', abi: Abi.windowsX64);
      expect(found?.version, '0.2.0');
      expect(requests.single.headers.value('accept'), 'application/vnd.github+json');
      expect(requests.single.method, 'GET');
    });

    test('is null when the newest release is the one running', () async {
      expect(await fetchLatestRelease(api(), current: '0.2.0', abi: Abi.windowsX64), isNull);
    });

    test('throws when the API does not answer 200', () async {
      status = 503;
      await expectLater(
        fetchLatestRelease(api(), current: '0.1.0', abi: Abi.windowsX64),
        throwsA(isA<HttpException>()),
      );
    });
  });
}
