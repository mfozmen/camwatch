import 'package:camwatch/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the app starts on the scan screen', (tester) async {
    app.main();
    await tester.pump();
    expect(find.text('Find the cameras on your network'), findsOneWidget);
    expect(find.text('Scan network'), findsOneWidget);
  });
}
