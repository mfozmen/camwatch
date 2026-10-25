import 'dart:async';

import 'package:camwatch/src/player_page.dart';
import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

Future<Map<String, PathStatus>> rootOpen(String host, int port) async => {'/': PathStatus.open};

void main() {
  const device = Device('192.168.1.10', openPorts: [80, 554]);
  final connecting = find.text('Connecting…');

  Future<FakePlayer> pump(WidgetTester tester, {FindPaths findPaths = rootOpen}) async {
    final player = FakePlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(device: device, player: player, findPaths: findPaths),
      ),
    );
    await tester.pump();
    return player;
  }

  testWidgets('streams from the first open path', (tester) async {
    final asked = <String>[];
    final player = await pump(
      tester,
      findPaths: (host, port) async {
        asked.add('$host:$port');
        return {'/': PathStatus.needsAuth, '/live': PathStatus.open, '/h264': PathStatus.open};
      },
    );
    expect(asked, ['192.168.1.10:554']);
    expect(player.opened, ['rtsp://192.168.1.10:554/live']);
  });

  testWidgets('says so when every path wants a password', (tester) async {
    final player = await pump(
      tester,
      findPaths: (host, port) async => {'/': PathStatus.needsAuth, '/live': PathStatus.error},
    );
    expect(player.opened, isEmpty);
    expect(find.text('The camera asks for a password'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('the message stays readable when the app theme is light', (tester) async {
    final player = FakePlayer();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.teal),
        home: PlayerPage(
          device: device,
          player: player,
          findPaths: (host, port) async => {'/': PathStatus.needsAuth},
        ),
      ),
    );
    await tester.pump();
    final title = tester.widget<Text>(find.text('The camera asks for a password'));
    expect(title.style!.color!.computeLuminance(), greaterThan(0.5));
  });

  testWidgets('a probe that never answers fails after the connect timeout', (tester) async {
    final player = await pump(
      tester,
      findPaths: (host, port) => Completer<Map<String, PathStatus>>().future,
    );
    expect(connecting, findsOneWidget);
    await tester.pump(connectTimeout);
    expect(find.text('The camera did not answer'), findsOneWidget);
    expect(player.opened, isEmpty);
  });

  testWidgets('fails when no path answers or the probe breaks', (tester) async {
    final player = await pump(tester, findPaths: (host, port) async => {'/': PathStatus.missing});
    expect(player.opened, isEmpty);
    expect(find.text('The camera did not answer'), findsOneWidget);
    await pump(tester, findPaths: (host, port) async => throw StateError('down'));
    expect(find.text('The camera did not answer'), findsOneWidget);
  });

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
        home: PlayerPage(device: device, player: player, findPaths: rootOpen),
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
        home: PlayerPage(device: device, player: player, findPaths: rootOpen),
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
