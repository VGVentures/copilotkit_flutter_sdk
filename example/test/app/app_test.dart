import 'package:example/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('App', () {
    testWidgets('renders placeholder home', (tester) async {
      await tester.pumpWidget(const App());

      expect(find.text('CopilotKit'), findsOneWidget);
    });
  });
}
