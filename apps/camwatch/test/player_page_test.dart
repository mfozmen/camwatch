import 'dart:async';

import 'package:camwatch/src/player_page.dart';
import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';
import 'fake_store.dart';

Future<Map<String, PathStatus>> rootOpen(String host, int port) async => {'/': PathStatus.open};

void main() {
  const device = Device('192.168.1.10', openPorts: [80, 554]);
  final connecting = find.text('Connecting…');

  Future<FakePlayer> pump(
    WidgetTester tester, {
    FindPaths findPaths = rootOpen,
    FakeStore? store,
  }) async {
    final player = FakePlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          device: device,
          player: player,
          findPaths: findPaths,
          store: store ?? FakeStore(),
        ),
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

  Future<Map<String, PathStatus>> protected(String host, int port) async => {
    '/': PathStatus.needsAuth,
    '/live': PathStatus.error,
    '/h264': PathStatus.needsAuth,
  };
  final enterPassword = find.text('Enter password');

  Future<void> login(WidgetTester tester, String user, String password) async {
    await tester.enterText(find.widgetWithText(TextField, 'Username'), user);
    await tester.enterText(find.widgetWithText(TextField, 'Password'), password);
    await tester.tap(find.text('Watch'));
    // Not pumpAndSettle: the connecting spinner never settles.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  testWidgets('asks for a password when every path wants one', (tester) async {
    final player = await pump(tester, findPaths: protected);
    expect(player.opened, isEmpty);
    expect(find.text('The camera asks for a password'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(enterPassword, findsOneWidget);
  });

  testWidgets('plays the first protected path with the typed password and keeps it', (
    tester,
  ) async {
    final store = FakeStore();
    final player = await pump(tester, findPaths: protected, store: store);
    await tester.tap(enterPassword);
    await tester.pumpAndSettle();
    await login(tester, 'admin', 'secret');
    expect(store.saved, {'192.168.1.10': const Credentials('admin', 'secret')});
    expect(player.opened, ['rtsp://admin:secret@192.168.1.10:554/']);
    expect(connecting, findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('cancelling the password dialog changes nothing', (tester) async {
    final store = FakeStore();
    final player = await pump(tester, findPaths: protected, store: store);
    await tester.tap(enterPassword);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.saved, isEmpty);
    expect(player.opened, isEmpty);
    expect(enterPassword, findsOneWidget);
  });

  testWidgets('uses the kept password without asking', (tester) async {
    final store = FakeStore()..saved['192.168.1.10'] = const Credentials('admin', 'secret');
    final player = await pump(tester, findPaths: protected, store: store);
    expect(player.opened, ['rtsp://admin:secret@192.168.1.10:554/']);
    expect(find.byType(TextField), findsNothing);
    expect(connecting, findsOneWidget);
  });

  testWidgets('an open path wins over a kept password', (tester) async {
    final store = FakeStore()..saved['192.168.1.10'] = const Credentials('admin', 'secret');
    final player = await pump(
      tester,
      findPaths: (host, port) async => {'/': PathStatus.needsAuth, '/live': PathStatus.open},
      store: store,
    );
    expect(player.opened, ['rtsp://192.168.1.10:554/live']);
  });

  testWidgets('a broken store is the same as an empty one', (tester) async {
    final store = FakeStore()..error = StateError('keystore');
    final player = await pump(tester, findPaths: protected, store: store);
    expect(player.opened, isEmpty);
    expect(enterPassword, findsOneWidget);
    await tester.tap(enterPassword);
    await tester.pumpAndSettle();
    await login(tester, 'admin', 'secret');
    expect(player.opened, ['rtsp://admin:secret@192.168.1.10:554/']);
  });

  testWidgets('a failure with a password offers to change it, showing no secret', (tester) async {
    final store = FakeStore()..saved['192.168.1.10'] = const Credentials('admin', 'secret');
    final player = await pump(tester, findPaths: protected, store: store);
    player.fail('Failed to open rtsp://admin:secret@192.168.1.10:554/');
    await tester.pump(errorGrace);
    expect(find.text('The camera did not let you in'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('rtsp://'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    final username = find.widgetWithText(TextField, 'Username');
    expect(tester.widget<TextField>(username).controller!.text, 'admin');
    await login(tester, 'admin', 'better');
    expect(store.saved['192.168.1.10'], const Credentials('admin', 'better'));
    expect(player.opened.last, 'rtsp://admin:better@192.168.1.10:554/');
    expect(connecting, findsOneWidget);
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
          store: FakeStore(),
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

  testWidgets('a redirect is refused at once and said so, with no address shown', (tester) async {
    final player = await pump(tester);
    player.redirect();
    await tester.pump();
    expect(find.text('The camera tried to send you elsewhere'), findsOneWidget);
    expect(find.textContaining('rtsp://'), findsNothing);
    expect(connecting, findsNothing);
    player.fail('Failed to open rtsp://192.168.1.10:554/');
    await tester.pump(errorGrace);
    expect(find.text('The camera tried to send you elsewhere'), findsOneWidget);
    expect(find.text('The camera did not answer'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(player.opened, ['rtsp://192.168.1.10:554/', 'rtsp://192.168.1.10:554/']);
    expect(connecting, findsOneWidget);
    player.ready();
    await tester.pump();
    expect(find.text('The camera tried to send you elsewhere'), findsNothing);
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
        home: PlayerPage(device: device, player: player, findPaths: rootOpen, store: FakeStore()),
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
        home: PlayerPage(device: device, player: player, findPaths: rootOpen, store: FakeStore()),
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
