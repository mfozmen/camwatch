import 'package:camwatch/src/update_button.dart';
import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_consent.dart';

final newer = Release('0.2.0', Uri.https('github.com', '/mfozmen/camwatch/releases/x.apk'));

void main() {
  final button = find.byTooltip('Check for updates');
  final notice = find.text('Check for updates?');
  final banner = find.text('camwatch 0.2.0 is out');

  Future<({List<int> checks, List<Uri> opened})> pump(
    WidgetTester tester, {
    required FakeConsent consent,
    Future<Release?> Function()? check,
    bool browser = true,
  }) async {
    final checks = <int>[];
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const Text('body'),
          appBar: AppBar(
            actions: [
              UpdateButton(
                consent: consent,
                check: () {
                  checks.add(1);
                  return check?.call() ?? Future.value(null);
                },
                open: (url) async {
                  if (!browser) throw Exception('no handler');
                  opened.add(url);
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    return (checks: checks, opened: opened);
  }

  testWidgets('sends nothing until the notice is accepted', (tester) async {
    final consent = FakeConsent(given: false);
    final log = await pump(tester, consent: consent);
    expect(log.checks, isEmpty);
    await tester.tap(button);
    await tester.pump();
    expect(notice, findsOneWidget);
    expect(find.textContaining('github.com'), findsOneWidget);
    expect(log.checks, isEmpty);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
    expect(log.checks, isEmpty);
    expect(consent.given, isFalse);
  });

  testWidgets('an accepted notice is remembered and checks at once', (tester) async {
    final consent = FakeConsent(given: false);
    final log = await pump(tester, consent: consent);
    await tester.tap(button);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
    await tester.pumpAndSettle();
    expect(consent.given, isTrue);
    expect(log.checks, hasLength(1));
    expect(find.text('You have the newest version'), findsOneWidget);
  });

  testWidgets('a newer release shows a banner whose Download opens its link', (tester) async {
    final log = await pump(tester, consent: FakeConsent(), check: () async => newer);
    await tester.pumpAndSettle();
    expect(log.checks, hasLength(1), reason: 'checked on start, no tap');
    expect(banner, findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(log.opened, [newer.download]);
    expect(banner, findsNothing);
  });

  testWidgets('says so when no browser opens the link', (tester) async {
    await pump(tester, consent: FakeConsent(), check: () async => newer, browser: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open a browser'), findsOneWidget);
  });

  testWidgets('Stop checking forgets the consent', (tester) async {
    final consent = FakeConsent();
    final log = await pump(tester, consent: consent);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop checking'));
    await tester.pumpAndSettle();
    expect(consent.given, isFalse);
    await tester.tap(button);
    await tester.pump();
    expect(notice, findsOneWidget);
    expect(log.checks, hasLength(2), reason: 'start and the tap, not the one after');
  });

  testWidgets('the banner keeps to the list column on a wide window', (tester) async {
    tester.view.physicalSize = const Size(1280, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, consent: FakeConsent(), check: () async => newer);
    await tester.pumpAndSettle();
    final banner = find.byType(MaterialBanner);
    final box = tester.getRect(find.descendant(of: banner, matching: find.byType(Material)).first);
    expect(box.width, lessThanOrEqualTo(600));
    expect(box.center.dx, 640);
    expect(
      tester.getTopLeft(find.text('body')).dy,
      greaterThanOrEqualTo(box.bottom),
      reason: 'pushes the body down, never covers it',
    );
  });

  testWidgets('Later hides the banner', (tester) async {
    await pump(tester, consent: FakeConsent(), check: () async => newer);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
  });

  testWidgets('a quiet start check says nothing when there is nothing new or no answer', (
    tester,
  ) async {
    await pump(tester, consent: FakeConsent(), check: () async => throw Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await pump(tester, consent: FakeConsent());
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failed manual check says so', (tester) async {
    await pump(tester, consent: FakeConsent(), check: () async => throw Exception('offline'));
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Could not reach github.com'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Could not reach github.com'), findsOneWidget);
  });

  testWidgets('a busy GitHub is named, with Retry', (tester) async {
    await pump(tester, consent: FakeConsent(), check: () async => throw GitHubBusy());
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('GitHub is busy, try again later'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a broken store counts as not asked yet', (tester) async {
    final consent = FakeConsent()..error = Exception('no keystore');
    final log = await pump(tester, consent: consent);
    await tester.pumpAndSettle();
    expect(log.checks, isEmpty);
    await tester.tap(button);
    await tester.pump();
    expect(notice, findsOneWidget);
  });
}
