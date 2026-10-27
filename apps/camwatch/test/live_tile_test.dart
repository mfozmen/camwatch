import 'dart:async';

import 'package:camwatch/src/live_tile.dart';
import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';
import 'fake_store.dart';

void main() {
  const camera = SavedCamera('192.168.1.6', 554);
  final players = <FakePlayer>[];
  FakePlayer newPlayer() {
    final player = FakePlayer();
    players.add(player);
    return player;
  }

  setUp(players.clear);

  // Not pumpAndSettle: the spinner never settles and the fake clock would run
  // into the connect timeout.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Future<void> pump(
    WidgetTester tester, {
    Map<String, PathStatus> paths = const {'/': PathStatus.open},
    FakeStore? store,
    bool live = true,
    VoidCallback? onTap,
    VoidCallback? onRemove,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 200,
          child: LiveTile(
            camera: camera,
            live: live,
            newPlayer: newPlayer,
            findPaths: (host, port) async => paths,
            store: store ?? FakeStore(),
            onTap: onTap ?? () {},
            onRemove: onRemove ?? () {},
          ),
        ),
      ),
    ),
  );

  testWidgets('plays the first open path and shows the address', (tester) async {
    await pump(tester);
    await settle(tester);
    expect(players.single.opened, ['rtsp://192.168.1.6:554/']);
    expect(find.text('192.168.1.6'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    players.single.ready();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('video')), findsOneWidget);
  });

  testWidgets('a protected path plays with the kept login, never shown', (tester) async {
    final store = FakeStore()..saved['192.168.1.6'] = const Credentials('admin', 'secret');
    await pump(tester, paths: {'/live': PathStatus.needsAuth}, store: store);
    await settle(tester);
    expect(players.single.opened.single, startsWith('rtsp://admin:secret@192.168.1.6:554/live'));
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('a protected path without a login shows a lock, no stream', (tester) async {
    await pump(tester, paths: {'/live': PathStatus.needsAuth});
    await settle(tester);
    expect(players.single.opened, isEmpty);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('Tap to enter password'), findsOneWidget);
  });

  testWidgets('no path, an error or a redirect shows the camera as off', (tester) async {
    await pump(tester, paths: const {});
    await settle(tester);
    expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);
    expect(find.text('No stream'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pump(tester);
    await settle(tester);
    expect(find.text('No stream'), findsNothing);
    players.last.fail('boom');
    await tester.pump(errorGrace);
    await tester.pump();
    expect(find.text('No stream'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pump(tester);
    await settle(tester);
    expect(find.text('No stream'), findsNothing);
    players.last.redirect();
    await tester.pump();
    expect(find.text('No stream'), findsOneWidget);
  });

  testWidgets('a camera that keeps erroring is off after one grace, player released', (
    tester,
  ) async {
    await pump(tester);
    await settle(tester);
    players.single.fail('audio');
    await tester.pump(const Duration(seconds: 2));
    players.single.fail('audio again');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('No stream'), findsOneWidget);
    expect(players.single.disposed, isTrue, reason: 'a tile that gave up holds no socket');
  });

  testWidgets('a tap reaches the owner, and a screen reader hears what it does', (tester) async {
    var tapped = false;
    await pump(tester, onTap: () => tapped = true);
    await settle(tester);
    expect(tester.getSemantics(find.text('192.168.1.6')).hintOverrides?.onTapHint, 'watch');
    await tester.tap(find.text('192.168.1.6'));
    expect(tapped, isTrue);
  });

  testWidgets('the hint clears the address bar on a phone-sized tile', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 175,
            height: 109,
            child: LiveTile(
              camera: camera,
              live: true,
              newPlayer: newPlayer,
              findPaths: (host, port) async => const {},
              store: FakeStore(),
              onTap: () {},
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    final hint = tester.getRect(find.text('No stream'));
    final address = tester.getRect(find.text('192.168.1.6'));
    expect(hint.bottom, lessThanOrEqualTo(address.top));
    expect(tester.getRect(find.byType(Card)).left, 0, reason: 'no margin of its own');
  });

  testWidgets('Remove sits in the tile menu', (tester) async {
    var removed = false;
    await pump(tester, onRemove: () => removed = true);
    await settle(tester);
    players.single.ready();
    await tester.tap(find.byTooltip('Options for 192.168.1.6'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(removed, isTrue);
  });

  testWidgets('stops the stream while not live and starts again after', (tester) async {
    await pump(tester);
    await settle(tester);
    expect(players, hasLength(1));
    await pump(tester, live: false);
    await settle(tester);
    expect(players.single.disposed, isTrue);
    await pump(tester, live: true);
    await settle(tester);
    expect(players, hasLength(2));
    expect(players.last.opened, ['rtsp://192.168.1.6:554/']);
  });

  testWidgets('starts nothing while not live, and disposes the player with the tile', (
    tester,
  ) async {
    await pump(tester, live: false);
    await settle(tester);
    expect(players, isEmpty);
    await pump(tester);
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    expect(players.single.disposed, isTrue);
  });

  testWidgets('a path check that never answers gives up after the timeout', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveTile(
            camera: camera,
            live: true,
            newPlayer: newPlayer,
            findPaths: (host, port) => Completer<Map<String, PathStatus>>().future,
            store: FakeStore(),
            onTap: () {},
            onRemove: () {},
          ),
        ),
      ),
    );
    await tester.pump(connectTimeout);
    await tester.pump();
    expect(find.text('No stream'), findsOneWidget);
  });
}
