import 'dart:async';

import 'package:camwatch/src/live_tile.dart';
import 'package:camwatch/src/player.dart';
import 'package:camwatch/src/player_page.dart';
import 'package:camwatch/src/scan_page.dart';
import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_camera_store.dart';
import 'fake_consent.dart';
import 'fake_player.dart';
import 'fake_store.dart';

class SlowConsent extends FakeConsent {
  SlowConsent() : super(given: false);

  @override
  Future<bool> read() => Future.delayed(const Duration(milliseconds: 500), () => given);
}

void main() {
  final player = FakePlayer();
  setUp(player.opened.clear);
  Future<void> pump(
    WidgetTester tester,
    Future<List<Device>?> Function() scan, {
    FakeConsent? consent,
    FakeCameraStore? saved,
    StreamPlayer Function()? newPlayer,
  }) => tester.pumpWidget(
    MaterialApp(
      home: ScanPage(
        scan: scan,
        newPlayer: newPlayer ?? () => player,
        findPaths: (host, port) async => {'/': PathStatus.open},
        store: FakeStore(),
        consent: consent ?? FakeConsent(),
        saved: saved ?? FakeCameraStore(),
      ),
    ),
  );

  final scanButton = find.widgetWithText(FloatingActionButton, 'Scan network');

  test('portLabel names the graded ports too', () {
    expect([21, 23, 443, 9].map(portLabel), ['FTP 21', 'Telnet 23', 'HTTPS 443', 'Port 9']);
    expect([22, 37777, 34567].map(portLabel), ['SSH 22', 'Dahua 37777', 'XMeye 34567']);
  });

  group('the first scan', () {
    final notice = find.text('Before the first scan');
    final understand = find.widgetWithText(FilledButton, 'I understand');

    testWidgets('asks first and probes nothing until the notice is accepted', (tester) async {
      var probed = false;
      final consent = FakeConsent(given: false);
      await pump(tester, () async {
        probed = true;
        return const [];
      }, consent: consent);
      await tester.tap(scanButton);
      await tester.pump();
      expect(notice, findsOneWidget);
      expect(find.textContaining('Scan only your own network'), findsOneWidget);
      expect(probed, isFalse);
      await tester.tap(understand);
      await tester.pumpAndSettle();
      expect(notice, findsNothing);
      expect(probed, isTrue);
      expect(consent.given, isTrue);
    });

    testWidgets('a dismissed notice scans nothing and is asked again', (tester) async {
      var probed = false;
      final consent = FakeConsent(given: false);
      await pump(tester, () async {
        probed = true;
        return const [];
      }, consent: consent);
      await tester.tap(scanButton);
      await tester.pump();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(notice, findsNothing);
      expect(probed, isFalse);
      expect(consent.given, isFalse);
      expect(scanButton, findsOneWidget);
    });

    testWidgets('two taps while the store is slow open one notice', (tester) async {
      final consent = SlowConsent();
      await pump(tester, () async => const [], consent: consent);
      await tester.tap(scanButton);
      await tester.pump();
      await tester.tap(scanButton);
      await tester.pump(const Duration(seconds: 1));
      expect(notice, findsOneWidget);
      await tester.tap(understand);
      await tester.pumpAndSettle();
      expect(notice, findsNothing);
    });

    testWidgets('a remembered answer is not asked again', (tester) async {
      await pump(
        tester,
        () => Completer<List<Device>?>().future,
        consent: FakeConsent(given: true),
      );
      await tester.tap(scanButton);
      await tester.pump();
      await tester.pump();
      expect(notice, findsNothing);
      expect(find.text('Scanning…'), findsOneWidget);
    });

    testWidgets('a broken store asks every time and still scans', (tester) async {
      var probed = false;
      await pump(tester, () async {
        probed = true;
        return const [];
      }, consent: FakeConsent(given: true)..error = StateError('no store'));
      await tester.tap(scanButton);
      await tester.pump();
      expect(notice, findsOneWidget);
      await tester.tap(understand);
      await tester.pumpAndSettle();
      expect(probed, isTrue);
    });
  });

  group('saved cameras', () {
    const camera = SavedCamera('192.168.1.6', 554);
    const other = SavedCamera('192.168.1.7', 8554);
    final players = <FakePlayer>[];
    FakePlayer newPlayer() {
      final fresh = FakePlayer();
      players.add(fresh);
      return fresh;
    }

    setUp(players.clear);

    /// Two frames, never pumpAndSettle: a live tile's spinner never settles.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    Future<void> ready(WidgetTester tester) async {
      for (final player in players) {
        player.ready();
      }
      await settle(tester);
    }

    testWidgets('stream in a grid before any scan, a tile opens the player', (tester) async {
      await pump(
        tester,
        () async => [],
        saved: FakeCameraStore(const [camera, other]),
        newPlayer: newPlayer,
      );
      await settle(tester);
      expect(find.text('Saved cameras'), findsOneWidget);
      expect(find.text('Kept from earlier scans. Scan to check them again.'), findsOneWidget);
      expect(find.byType(LiveTile), findsNWidgets(2));
      expect(find.text('Find the cameras on your network'), findsNothing);
      expect(scanButton, findsOneWidget);
      await settle(tester);
      expect(players.map((p) => p.opened.single), [
        'rtsp://192.168.1.6:554/',
        'rtsp://192.168.1.7:8554/',
      ]);
      await ready(tester);
      await tester.tap(find.text('192.168.1.6'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(tester.widget<PlayerPage>(find.byType(PlayerPage)).device.rtspPort, 554);
      expect(players.take(2).map((p) => p.disposed), [true, true], reason: 'hidden grid stops');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await settle(tester);
      expect(players, hasLength(5), reason: 'the player page took one, the grid two more');
      expect(players.skip(3).map((p) => p.opened.single), [
        'rtsp://192.168.1.6:554/',
        'rtsp://192.168.1.7:8554/',
      ]);
    });

    testWidgets('the grid stops while the app is in the background', (tester) async {
      await pump(
        tester,
        () async => [],
        saved: FakeCameraStore(const [camera]),
        newPlayer: newPlayer,
      );
      await settle(tester);
      expect(players, hasLength(1));
      // Visible but not the front window, on Windows every click elsewhere: still live.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      expect(players.single.disposed, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settle(tester);
      expect(players.single.disposed, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(players, hasLength(2));
    });

    testWidgets('fills the width: two tiles across on a phone, four on a wide window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final four = [for (var i = 1; i <= 4; i++) SavedCamera('192.168.1.$i', 554)];
      await pump(tester, () async => [], saved: FakeCameraStore(four), newPlayer: newPlayer);
      await settle(tester);
      final phone = tester.getRect(find.byType(LiveTile).first);
      expect(phone.width, closeTo((390 - 32 - 8) / 2, 1));
      expect(tester.getRect(find.byType(LiveTile).at(1)).top, phone.top, reason: 'same row');
      tester.view.physicalSize = const Size(1280, 800);
      await settle(tester);
      final wide = tester.getRect(find.byType(LiveTile).first);
      expect(tester.getRect(find.byType(LiveTile).at(3)).top, wide.top, reason: 'one row of four');
    });

    testWidgets('a camera is named from the tile menu and the name follows it', (tester) async {
      final store = FakeCameraStore(const [camera]);
      await pump(
        tester,
        () async => const [
          Device('192.168.1.6', openPorts: [554]),
        ],
        saved: store,
        newPlayer: newPlayer,
      );
      await settle(tester);
      await ready(tester);
      await tester.tap(find.byTooltip('Options for 192.168.1.6'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name…'));
      await tester.pumpAndSettle();
      expect(find.text('Name this camera'), findsOneWidget);
      expect(find.text('Leave empty to show 192.168.1.6.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), ' Garden ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(store.cameras, [const SavedCamera('192.168.1.6', 554, name: 'Garden')]);
      expect(find.text('Garden'), findsOneWidget);
      await tester.tap(find.text('Garden'));
      await tester.pumpAndSettle();
      expect(find.text('Garden'), findsOneWidget, reason: 'the player page carries the name');
      expect(find.text('192.168.1.6'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await settle(tester);
      await tester.tap(scanButton);
      await tester.pumpAndSettle();
      expect(find.text('Garden'), findsOneWidget, reason: 'the device card carries it');
      expect(find.text('192.168.1.6'), findsOneWidget);
      await tester.tap(find.text('Garden'));
      await tester.pumpAndSettle();
      expect(find.text('Garden'), findsOneWidget, reason: 'so does the report');
      expect(find.text('192.168.1.6'), findsOneWidget);
    });

    testWidgets('an empty name falls back to the address', (tester) async {
      final store = FakeCameraStore(const [SavedCamera('192.168.1.6', 554, name: 'Garden')]);
      await pump(tester, () async => [], saved: store, newPlayer: newPlayer);
      await settle(tester);
      await ready(tester);
      await tester.tap(find.byTooltip('Options for Garden'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename…'));
      await tester.pumpAndSettle();
      expect(find.text('Rename camera'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, 'Garden');
      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(store.cameras, [camera]);
      expect(find.text('Garden'), findsNothing);
    });

    testWidgets('a named camera is unsaved from its device card, not duplicated', (tester) async {
      final store = FakeCameraStore(const [SavedCamera('192.168.1.6', 554, name: 'Garden')]);
      await pump(
        tester,
        () async => const [
          Device('192.168.1.6', openPorts: [554]),
        ],
        saved: store,
        newPlayer: newPlayer,
      );
      await settle(tester);
      await tester.tap(scanButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove from saved'));
      await tester.pumpAndSettle();
      expect(store.cameras, isEmpty);
    });

    testWidgets('can be removed from the tile menu, and put back with Undo', (tester) async {
      final store = FakeCameraStore(const [camera]);
      await pump(tester, () async => [], saved: store, newPlayer: newPlayer);
      await settle(tester);
      await ready(tester);
      await tester.tap(find.byTooltip('Options for 192.168.1.6'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(store.cameras, isEmpty);
      expect(find.text('Removed 192.168.1.6 · RTSP 554'), findsOneWidget);
      expect(find.text('Find the cameras on your network'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(store.cameras, [camera]);
      expect(find.byType(LiveTile), findsOneWidget);
    });

    testWidgets('a found device is saved from its card and unsaved again', (tester) async {
      final store = FakeCameraStore();
      await pump(
        tester,
        () async => const [
          Device('192.168.1.6', openPorts: [554]),
        ],
        saved: store,
      );
      await tester.tap(scanButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save camera'));
      await tester.pumpAndSettle();
      expect(store.cameras, [camera]);
      expect(find.byTooltip('Save camera'), findsNothing);
      await tester.tap(find.byTooltip('Remove from saved'));
      await tester.pumpAndSettle();
      expect(store.cameras, isEmpty);
      expect(find.byTooltip('Save camera'), findsOneWidget);
    });

    testWidgets('a long address beside the ONVIF badge stays on one line', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(
        tester,
        () async => const [
          Device(
            '192.168.100.254',
            openPorts: [80, 554, 8000, 8080, 8554],
            onvifAddress: 'http://192.168.100.254/o',
          ),
        ],
      );
      await tester.tap(scanButton);
      await tester.pumpAndSettle();
      final address = tester.widget<Text>(find.text('192.168.100.254'));
      expect(address.softWrap, isFalse);
      final box = tester.getRect(find.text('192.168.100.254'));
      final badge = tester.getRect(find.text('ONVIF'));
      expect(
        badge.top,
        greaterThanOrEqualTo(box.bottom),
        reason: 'the badge sits under the address',
      );
      final grade = tester.getRect(find.textContaining('Exposed'));
      expect(badge.top, greaterThanOrEqualTo(grade.bottom), reason: 'and under the grade line');
      expect(grade.height, lessThan(30), reason: 'the grade line never wraps');
    });

    testWidgets('the busiest card keeps its ports to two lines on a phone', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(
        tester,
        () async => const [
          Device(
            '192.168.100.254',
            openPorts: [21, 23, 80, 554, 37777],
            onvifAddress: 'http://192.168.100.254/o',
          ),
        ],
        saved: FakeCameraStore(const [SavedCamera('192.168.100.254', 554, name: 'Garden')]),
      );
      await tester.tap(scanButton);
      await tester.pumpAndSettle();
      final ports = tester.getRect(find.textContaining('FTP 21'));
      // The test font is twice as wide as Roboto, so lines are not counted;
      // the column the ports get is, and the badge no longer shares it.
      expect(ports.width, greaterThan(220));
      final badge = tester.getRect(find.text('ONVIF'));
      expect(badge.top, greaterThanOrEqualTo(ports.bottom), reason: 'under the ports');
      final save = tester.getRect(find.byTooltip('Remove from saved'));
      final watch = tester.getRect(find.byTooltip('Watch'));
      expect(watch.left, save.left, reason: 'stacked, not side by side');
    });

    testWidgets('a device without a stream cannot be saved', (tester) async {
      await pump(
        tester,
        () async => const [
          Device('192.168.1.6', openPorts: [80]),
        ],
      );
      await tester.tap(scanButton);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Save camera'), findsNothing);
    });

    testWidgets('a broken store shows the guidance and saves nothing', (tester) async {
      final store = FakeCameraStore(const [camera])..error = StateError('no store');
      await pump(
        tester,
        () async => const [
          Device('192.168.1.6', openPorts: [554]),
        ],
        saved: store,
      );
      await tester.pumpAndSettle();
      expect(find.text('Find the cameras on your network'), findsOneWidget);
      await tester.tap(scanButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save camera'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Save camera'), findsOneWidget);
    });
  });

  testWidgets('starts with guidance and a scan button', (tester) async {
    await pump(tester, () async => []);
    expect(find.text('Find the cameras on your network'), findsOneWidget);
    expect(find.textContaining('Nothing leaves your device'), findsOneWidget);
    expect(scanButton, findsOneWidget);
  });

  testWidgets('shows progress while scanning and disables the button', (tester) async {
    final scanning = Completer<List<Device>?>();
    await pump(tester, () => scanning.future);
    await tester.tap(scanButton);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Scanning your network'), findsOneWidget);
    expect(
      tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed,
      isNull,
    );
    scanning.complete([]);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  for (final (name, finish) in [
    ('finishes', (Completer<List<Device>?> c) => c.complete([])),
    ('fails', (Completer<List<Device>?> c) => c.completeError(StateError('late'))),
  ]) {
    testWidgets('ignores a scan that $name after the page is gone', (tester) async {
      final scanning = Completer<List<Device>?>();
      await pump(tester, () => scanning.future);
      await tester.tap(scanButton);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      finish(scanning);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('says so when the device is not on a local network', (tester) async {
    await pump(tester, () async => null);
    await tester.tap(scanButton);
    await tester.pump();
    expect(find.text('Not on a local network'), findsOneWidget);
    expect(find.textContaining('Wi-Fi or Ethernet'), findsOneWidget);
  });

  testWidgets('guides when nothing answered', (tester) async {
    await pump(tester, () async => []);
    await tester.tap(scanButton);
    await tester.pump();
    expect(find.text('No devices found'), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'Scan again'), findsOneWidget);
  });

  testWidgets('reports a failed scan without the error text', (tester) async {
    await pump(tester, () async => throw StateError('secret'));
    await tester.tap(scanButton);
    await tester.pump();
    expect(find.text('The scan failed'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('lists each device with its ports and ONVIF badge', (tester) async {
    await pump(
      tester,
      () async => const [
        Device('192.168.1.10', openPorts: [80, 554], onvifAddress: 'http://192.168.1.10/onvif'),
        Device('192.168.1.20', openPorts: [8000]),
      ],
    );
    await tester.tap(scanButton);
    await tester.pump();
    expect(find.text('2 devices found'), findsOneWidget);
    expect(find.text('192.168.1.10'), findsOneWidget);
    expect(find.text('HTTP 80 · RTSP 554'), findsOneWidget);
    expect(find.text('SDK 8000'), findsOneWidget);
    expect(find.text('ONVIF'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('192.168.1.10.*ONVIF', dotAll: true)), findsOneWidget);
    expect(find.byTooltip('Watch'), findsOneWidget);
  });

  testWidgets('shows each device\'s grade once its stream is checked', (tester) async {
    final checking = Completer<Map<String, PathStatus>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ScanPage(
          scan: () async => const [
            Device('192.168.1.10', openPorts: [23, 554]),
            Device('192.168.1.20', openPorts: [80]),
            Device('192.168.1.30', openPorts: [80, 443]),
          ],
          newPlayer: () => player,
          findPaths: (host, port) => checking.future,
          store: FakeStore(),
          consent: FakeConsent(),
          saved: FakeCameraStore(),
        ),
      ),
    );
    await tester.tap(scanButton);
    await tester.pump();
    expect(find.text('Checking stream…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('At risk · 1 finding'), findsOneWidget);
    expect(find.text('No issues found'), findsOneWidget);
    checking.complete({'/': PathStatus.open});
    await tester.pump();
    expect(find.text('Checking stream…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Exposed · 2 findings'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('192.168.1.10.*Exposed', dotAll: true)), findsOneWidget);
  });

  testWidgets('a stream check that fails leaves the stream unchecked', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScanPage(
          scan: () async => const [
            Device('192.168.1.10', openPorts: [554]),
          ],
          newPlayer: () => player,
          findPaths: (host, port) async => throw StateError('down'),
          store: FakeStore(),
          consent: FakeConsent(),
          saved: FakeCameraStore(),
        ),
      ),
    );
    await tester.tap(scanButton);
    await tester.pump();
    await tester.pump();
    expect(find.text('At risk · 1 finding'), findsOneWidget);
  });

  testWidgets('a tap on a device opens its report, the watch button the player', (tester) async {
    await pump(
      tester,
      () async => const [
        Device('192.168.1.10', openPorts: [554]),
        Device('192.168.1.20', openPorts: [80]),
      ],
    );
    await tester.tap(scanButton);
    await tester.pump();
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('192.168.1.20.*No stream', dotAll: true)), findsOneWidget);
    // Its own node: a merged card would leave screen readers one tap for two actions.
    expect(tester.getSemantics(find.byTooltip('Watch')).label, isNot(contains('192.168')));
    expect(
      tester.getSemantics(find.text('192.168.1.20')).hintOverrides?.onTapHint,
      'open the security report',
    );
    await tester.tap(find.text('192.168.1.20'));
    await tester.pumpAndSettle();
    expect(find.text('The web page has no HTTPS'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('192.168.1.10'));
    await tester.pumpAndSettle();
    expect(find.text('Anyone on the network can watch the stream'), findsOneWidget);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Watch'));
    // Not pumpAndSettle: the player's spinner never settles and its deadline would fire.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('video')), findsOneWidget);
    expect(player.opened, ['rtsp://192.168.1.10:554/']);
    player.opened.clear();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Watch'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('video')), findsOneWidget);
    expect(player.opened, ['rtsp://192.168.1.10:554/']);
  });

  testWidgets('counts one device in the singular', (tester) async {
    await pump(
      tester,
      () async => const [
        Device('10.0.0.2', openPorts: [8554]),
      ],
    );
    await tester.tap(scanButton);
    await tester.pump();
    expect(find.text('1 device found'), findsOneWidget);
    expect(find.text('RTSP 8554'), findsOneWidget);
  });
}
