import 'dart:async';

import 'package:camwatch/src/scan_page.dart';
import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

void main() {
  final player = FakePlayer();
  Future<void> pump(WidgetTester tester, Future<List<Device>?> Function() scan) =>
      tester.pumpWidget(
        MaterialApp(
          home: ScanPage(
            scan: scan,
            newPlayer: () => player,
            findPaths: (host, port) async => {'/': PathStatus.open},
          ),
        ),
      );

  final scanButton = find.widgetWithText(FloatingActionButton, 'Scan network');

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
  });

  testWidgets('a tap on a device with RTSP opens the player, other cards do nothing', (
    tester,
  ) async {
    await pump(
      tester,
      () async => const [
        Device('192.168.1.10', openPorts: [554]),
        Device('192.168.1.20', openPorts: [80]),
      ],
    );
    await tester.tap(scanButton);
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('192.168.1.10.*Watch', dotAll: true)), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('192.168.1.20.*No stream', dotAll: true)), findsOneWidget);
    await tester.tap(find.text('192.168.1.20'));
    await tester.pumpAndSettle();
    expect(find.text('1 device found'), findsNothing);
    expect(find.text('2 devices found'), findsOneWidget);
    await tester.tap(find.text('192.168.1.10'));
    // Not pumpAndSettle: the player's spinner never settles and its deadline would fire.
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
