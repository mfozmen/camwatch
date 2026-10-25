import 'dart:async';

import 'package:camwatch/src/player_page.dart';
import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

void main() {
  const device = Device('192.168.1.10', openPorts: [80, 554]);
  final connecting = find.text('Connecting…');

  Future<FakePlayer> pump(WidgetTester tester) async {
    final player = FakePlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(device: device, player: player),
      ),
    );
    await tester.pump();
    return player;
  }

  testWidgets('opens the stream, says it is connecting, then shows the video', (tester) async {
    final player = await pump(tester);
    expect(player.opened, ['rtsp://192.168.1.10:554/']);
    expect(find.text('192.168.1.10'), findsOneWidget);
    expect(connecting, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    player.ready();
    await tester.pump();
    expect(connecting, findsNothing);
    expect(find.byKey(const Key('video')), findsOneWidget);
  });

  testWidgets('tells when the stream fails, without the player message', (tester) async {
    final player = await pump(tester);
    player.fail('Failed to open rtsp://user:secret@192.168.1.10:554/');
    await tester.pump(errorGrace);
    expect(find.text('The camera did not answer'), findsOneWidget);
    expect(find.textContaining('port 554'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('repeated errors do not push the failure back', (tester) async {
    final player = await pump(tester);
    player.fail('first');
    await tester.pump(const Duration(seconds: 2));
    player.fail('second');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('The camera did not answer'), findsOneWidget);
    player.fail('after failure');
    await tester.pump(errorGrace);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an error followed by a picture is not a failure', (tester) async {
    final player = await pump(tester);
    player.fail("Failed to initialize a decoder for codec 'adpcm_g726le'.");
    await tester.pump(const Duration(seconds: 1));
    player.ready();
    await tester.pump(errorGrace);
    expect(find.text('The camera did not answer'), findsNothing);
    expect(connecting, findsNothing);
    player.fail('late audio error');
    await tester.pump(errorGrace);
    expect(find.text('The camera did not answer'), findsNothing);
  });

  testWidgets('gives up after the connect timeout and can try again', (tester) async {
    final player = await pump(tester);
    await tester.pump(connectTimeout);
    expect(find.text('The camera did not answer'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(player.opened, hasLength(2));
    expect(connecting, findsOneWidget);
    player.ready();
    await tester.pump();
    expect(connecting, findsNothing);
    expect(find.byKey(const Key('video')), findsOneWidget);
  });

  testWidgets('an open that throws fails the page', (tester) async {
    final player = FakePlayer()..opening = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(device: device, player: player),
      ),
    );
    player.opening!.completeError(StateError('no'));
    await tester.pump();
    expect(find.text('The camera did not answer'), findsOneWidget);
  });

  testWidgets('an open that fails after the page is gone is ignored', (tester) async {
    final player = FakePlayer()..opening = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(device: device, player: player),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    player.opening!.completeError(StateError('late'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposes the player when the page goes', (tester) async {
    final player = await pump(tester);
    await tester.pumpWidget(const SizedBox());
    expect(player.disposed, isTrue);
  });
}
