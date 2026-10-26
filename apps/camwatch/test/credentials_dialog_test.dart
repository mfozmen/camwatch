import 'package:camwatch/src/credentials_dialog.dart';
import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final username = find.widgetWithText(TextField, 'Username');
  final password = find.widgetWithText(TextField, 'Password');
  final watch = find.widgetWithText(FilledButton, 'Watch');

  Future<List<Credentials?>> open(WidgetTester tester, {Credentials? current}) async {
    final results = <Credentials?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(await askCredentials(context, current: current)),
            child: const Text('ask'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('returns what was typed and hides the password while typing', (tester) async {
    final results = await open(tester);
    expect(find.text('Camera password'), findsOneWidget);
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    await tester.enterText(username, 'admin');
    await tester.enterText(password, 'secret');
    await tester.tap(watch);
    await tester.pumpAndSettle();
    expect(results, [const Credentials('admin', 'secret')]);
    expect(find.text('Camera password'), findsNothing);
  });

  testWidgets('the username is taken as typed', (tester) async {
    await open(tester);
    final field = tester.widget<TextField>(username);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });

  testWidgets('follows the theme of the screen that asks, not the app', (tester) async {
    final dark = ThemeData(brightness: Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        home: Theme(
          data: dark,
          child: Builder(
            builder: (context) =>
                TextButton(onPressed: () => askCredentials(context), child: const Text('ask')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(AlertDialog))).brightness, Brightness.dark);
  });

  testWidgets('the password can be shown, still as a password to the keyboard', (tester) async {
    await open(tester);
    expect(tester.widget<TextField>(password).autocorrect, isFalse);
    expect(tester.widget<TextField>(password).enableSuggestions, isFalse);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<TextField>(password).obscureText, isFalse);
    expect(tester.widget<TextField>(password).keyboardType, TextInputType.visiblePassword);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(tester.widget<TextField>(password).obscureText, isTrue);
  });

  testWidgets('needs a username before it can be submitted', (tester) async {
    final results = await open(tester);
    expect(tester.widget<FilledButton>(watch).onPressed, isNull);
    await tester.enterText(username, 'admin');
    await tester.pump();
    expect(tester.widget<FilledButton>(watch).onPressed, isNotNull);
    await tester.enterText(password, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(results, [const Credentials('admin', '')]);
  });

  testWidgets('starts from the current login and returns null on cancel', (tester) async {
    final results = await open(tester, current: const Credentials('admin', 'old'));
    expect(tester.widget<TextField>(username).controller!.text, 'admin');
    expect(tester.widget<TextField>(password).controller!.text, 'old');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, [null]);
  });
}
