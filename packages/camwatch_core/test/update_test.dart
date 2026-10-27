import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:test/test.dart';

const tagPage = 'https://github.com/mfozmen/camwatch/releases/tag/';
const downloads = 'https://github.com/mfozmen/camwatch/releases/download/';

void main() {
  test('the release page is GitHub over https, not the rate-limited API', () {
    expect(latestReleasePage.toString(), 'https://github.com/mfozmen/camwatch/releases/latest');
  });

  test('redirectedTag reads the tag pages of this repository, absolute or relative', () {
    expect(redirectedTag(latestReleasePage, '${tagPage}v0.2.0'), 'v0.2.0');
    expect(redirectedTag(latestReleasePage, '/mfozmen/camwatch/releases/tag/v0.2.0'), 'v0.2.0');
    expect(
      redirectedTag(latestReleasePage, 'https://github.com/someone/else/releases/tag/v1'),
      isNull,
    );
    expect(
      redirectedTag(latestReleasePage, 'https://github.com.example${tagPage.substring(18)}v1'),
      isNull,
    );
    expect(redirectedTag(latestReleasePage, ''), isNull);
  });

  group('releaseFromTag', () {
    test('names the version and the asset built for this ABI, by convention', () {
      final found = releaseFromTag('v0.2.0', current: '0.1.0', abi: Abi.androidArm64);
      expect(found?.version, '0.2.0');
      expect(found?.download, Uri.parse('${downloads}v0.2.0/camwatch-0.2.0-android-arm64-v8a.apk'));
      expect(
        releaseFromTag('v0.2.0', current: '0.1.0', abi: Abi.androidArm)?.download.path,
        endsWith('camwatch-0.2.0-android-armeabi-v7a.apk'),
      );
      expect(
        releaseFromTag('v0.2.0', current: '0.1.0', abi: Abi.androidX64)?.download.path,
        endsWith('camwatch-0.2.0-android-x86_64.apk'),
      );
      expect(
        releaseFromTag('v0.2.0', current: '0.1.0', abi: Abi.windowsX64)?.download.path,
        endsWith('camwatch-0.2.0-windows-x64-setup.exe'),
      );
    });

    test('compares versions as numbers, not strings', () {
      expect(releaseFromTag('v0.10.0', current: '0.9.1', abi: Abi.windowsX64), isNotNull);
      expect(releaseFromTag('v1.0.0', current: '1.0.0', abi: Abi.windowsX64), isNull);
      expect(releaseFromTag('v0.1.0', current: '0.1.1', abi: Abi.windowsX64), isNull);
    });

    test('a tag with a path trick, query, fragment or file suffix is no version', () {
      for (final tag in [
        'v0.2.0/../../x',
        'v0.2.0?x=1',
        'v0.2.0#f',
        'v0.2.0%2F..',
        'v0.2.0.sha256',
      ]) {
        expect(
          releaseFromTag(tag, current: '0.1.0', abi: Abi.windowsX64),
          isNull,
          reason: tag,
        );
      }
    });

    test('is null for an ABI without a build, a tag that is no version or a huge number', () {
      expect(releaseFromTag('v0.2.0', current: '0.1.0', abi: Abi.linuxX64), isNull);
      expect(releaseFromTag('latest', current: '0.1.0', abi: Abi.windowsX64), isNull);
      expect(
        releaseFromTag('v99999999999999999999.0.0', current: '0.1.0', abi: Abi.windowsX64),
        isNull,
      );
      expect(releaseFromTag('0.2.0', current: '0.1.0', abi: Abi.windowsX64)?.version, '0.2.0');
    });
  });

  group('fetchLatestRelease', () {
    late HttpServer server;
    final requests = <HttpRequest>[];
    var status = 302;
    var location = '${tagPage}v0.2.0';
    var hang = false;
    var body = '<html></html>';

    setUp(() async {
      requests.clear();
      status = 302;
      location = '${tagPage}v0.2.0';
      hang = false;
      body = '<html></html>';
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) {
        requests.add(request);
        if (hang) return;
        if (location.isNotEmpty) request.response.headers.set('location', location);
        request.response
          ..statusCode = status
          ..write(body)
          ..close();
      });
    });
    tearDown(() => server.close());

    Uri page() => Uri.parse('http://127.0.0.1:${server.port}/releases/latest');

    test('reads the version from the redirect without following it', () async {
      final found = await fetchLatestRelease(page(), current: '0.1.0', abi: Abi.windowsX64);
      expect(found?.version, '0.2.0');
      expect(found?.download.toString(), '${downloads}v0.2.0/camwatch-0.2.0-windows-x64-setup.exe');
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.uri.query, isEmpty);
      expect(requests.single.contentLength, lessThanOrEqualTo(0));
    });

    test('is null when the newest release is the one running', () async {
      expect(await fetchLatestRelease(page(), current: '0.2.0', abi: Abi.windowsX64), isNull);
    });

    test('a redirect anywhere but this repository\'s release pages is refused', () async {
      location = 'https://github.com.example/mfozmen/camwatch/releases/tag/v9.9.9';
      await expectLater(
        fetchLatestRelease(page(), current: '0.1.0', abi: Abi.windowsX64),
        throwsA(isA<HttpException>()),
      );
      location = 'https://github.com/someone/else/releases/tag/v9.9.9';
      await expectLater(
        fetchLatestRelease(page(), current: '0.1.0', abi: Abi.windowsX64),
        throwsA(isA<HttpException>()),
      );
    });

    test('a busy GitHub is reported as such, not as unreachable', () async {
      for (final busy in [403, 429]) {
        status = busy;
        location = '';
        await expectLater(
          fetchLatestRelease(page(), current: '0.1.0', abi: Abi.windowsX64),
          throwsA(isA<GitHubBusy>()),
        );
      }
    });

    test('throws when the page does not redirect, without reading its body', () async {
      status = 200;
      location = '';
      body = 'x' * (4 << 20);
      final sw = Stopwatch()..start();
      await expectLater(
        fetchLatestRelease(page(), current: '0.1.0', abi: Abi.windowsX64),
        throwsA(isA<HttpException>()),
      );
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('gives up on a server that never answers', () async {
      hang = true;
      await expectLater(
        fetchLatestRelease(
          page(),
          current: '0.1.0',
          abi: Abi.windowsX64,
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
