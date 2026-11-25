import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/recording_client.dart';

void main() {
  group(CopilotNavigatorObserver, () {
    late RecordingClient client;

    setUp(() => client = RecordingClient());

    List<Object?> navigations() => [
      for (final call in client.calls)
        if (call.method == 'recordTrajectoryEvent' &&
            call.arguments.first == TrajectoryBuiltInEvent.navigation)
          call.arguments.last,
    ];

    Future<GlobalKey<NavigatorState>> pump(
      WidgetTester tester,
      CopilotNavigatorObserver observer,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [observer],
            initialRoute: '/',
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => Text('${settings.name}'),
            ),
          ),
        ),
      );
      return navigator;
    }

    testWidgets('records pushes, replacements and pops', (tester) async {
      final navigator = await pump(tester, CopilotNavigatorObserver());

      navigator.currentState!.pushNamed('/deals');
      await tester.pumpAndSettle();
      navigator.currentState!.pushReplacementNamed('/deal');
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();

      expect(navigations(), [
        {'from': null, 'to': '/', 'navigationType': 'push'},
        {'from': '/', 'to': '/deals', 'navigationType': 'push'},
        {'from': '/deals', 'to': '/deal', 'navigationType': 'replace'},
        {'from': '/deal', 'to': '/', 'navigationType': 'traverse'},
      ]);
    });

    testWidgets('records to the client it is given', (tester) async {
      final other = RecordingClient();
      final navigator = await pump(
        tester,
        CopilotNavigatorObserver(client: other),
      );

      navigator.currentState!.pushNamed('/deals');
      await tester.pumpAndSettle();

      expect(navigations(), isEmpty);
      expect(other.calls, hasLength(2));
    });

    testWidgets('records nothing without a CopilotKit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [CopilotNavigatorObserver()],
          home: const Text('home'),
        ),
      );

      expect(find.text('home'), findsOneWidget);
    });

    test('records nothing before it is on a navigator', () {
      CopilotNavigatorObserver().didPush(
        MaterialPageRoute<void>(builder: (_) => const SizedBox()),
        null,
      );
    });
  });
}
