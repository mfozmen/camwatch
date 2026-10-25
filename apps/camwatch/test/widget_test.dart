import 'package:camwatch/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the app starts on the empty camera list', (tester) async {
    app.main();
    await tester.pump();
    expect(find.text('Cameras on your network will show up here.'), findsOneWidget);
  });
}
