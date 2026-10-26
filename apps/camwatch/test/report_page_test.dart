import 'package:camwatch/src/report_page.dart';
import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Device device,
    Map<String, PathStatus>? streams, {
    VoidCallback? onWatch,
  }) => tester.pumpWidget(
    MaterialApp(
      home: ReportPage(device: device, streams: streams, onWatch: onWatch),
    ),
  );

  testWidgets('a red device lists every finding with its advice, worst first', (tester) async {
    var watched = false;
    await pump(tester, const Device('192.168.1.10', openPorts: [23, 80, 554]), {
      '/': PathStatus.open,
    }, onWatch: () => watched = true);
    expect(find.text('192.168.1.10'), findsOneWidget);
    expect(find.text('Exposed'), findsOneWidget);
    expect(
      find.text('Anyone on your network can get in. Fix the red items first.'),
      findsOneWidget,
    );
    expect(find.text('Open ports: Telnet 23 · HTTP 80 · RTSP 554'), findsOneWidget);
    final titles = [
      'Anyone on the network can watch the stream',
      'Telnet is open',
      'The web page has no HTTPS',
    ];
    for (final title in titles) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.textContaining('Set a password on the camera'), findsOneWidget);
    final tops = [for (final title in titles) tester.getTopLeft(find.text(title)).dy];
    expect(tops, [tops[0], tops[1], tops[2]]..sort());
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Watch'));
    expect(watched, isTrue);
  });

  testWidgets('an amber device explains the grade', (tester) async {
    await pump(tester, const Device('192.168.1.10', openPorts: [80]), const {});
    expect(find.text('At risk'), findsOneWidget);
    expect(find.text('Easier to break into than it needs to be.'), findsOneWidget);
    expect(find.text('The web page has no HTTPS'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('a green device says there is nothing to fix', (tester) async {
    await pump(tester, const Device('192.168.1.10', openPorts: [80, 443]), const {});
    expect(find.text('No issues found'), findsOneWidget);
    expect(find.text('Nothing to fix on its open ports and stream.'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('a device whose stream is still being checked says so', (tester) async {
    await pump(tester, const Device('192.168.1.10', openPorts: [554]), null);
    expect(find.text('Checking the stream…'), findsOneWidget);
    expect(find.text('The stream has not been checked yet'), findsNothing);
  });
}
