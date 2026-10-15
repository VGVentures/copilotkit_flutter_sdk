import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ToolCallView _call(
  String name, {
  String id = 'c1',
  ToolCallStatus status = ToolCallStatus.inProgress,
  Map<String, Object?> args = const {},
  String? result,
}) {
  return ToolCallView(
    id: id,
    name: name,
    status: status,
    args: args,
    result: result,
  );
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group(ToolRenderer, () {
    testWidgets('renders a call with the builder for its name', (tester) async {
      await tester.pumpWidget(
        _app(
          ToolRenderer(
            name: 'showWeather',
            builder: (context, call) => Text('weather ${call.args['city']}'),
            child: ToolCallWidget(
              call: _call('showWeather', args: const {'city': 'Lima'}),
            ),
          ),
        ),
      );

      expect(find.text('weather Lima'), findsOneWidget);
    });

    testWidgets('falls back to the * builder', (tester) async {
      await tester.pumpWidget(
        _app(
          ToolRenderer(
            name: '*',
            builder: (context, call) => Text('generic ${call.name}'),
            child: ToolCallWidget(call: _call('searchDocs')),
          ),
        ),
      );

      expect(find.text('generic searchDocs'), findsOneWidget);
    });

    testWidgets('prefers the named builder over the fallback', (tester) async {
      await tester.pumpWidget(
        _app(
          ToolRenderer(
            name: '*',
            builder: (context, call) => const Text('generic'),
            child: ToolRenderer(
              name: 'showWeather',
              builder: (context, call) => const Text('weather'),
              child: Column(
                children: [
                  ToolCallWidget(call: _call('showWeather')),
                  ToolCallWidget(call: _call('other', id: 'c2')),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('weather'), findsOneWidget);
      expect(find.text('generic'), findsOneWidget);
    });

    testWidgets('the nearest builder for a name wins', (tester) async {
      await tester.pumpWidget(
        _app(
          ToolRenderer(
            name: 'showWeather',
            builder: (context, call) => const Text('outer'),
            child: ToolRenderer(
              name: 'showWeather',
              builder: (context, call) => const Text('inner'),
              child: ToolCallWidget(call: _call('showWeather')),
            ),
          ),
        ),
      );

      expect(find.text('inner'), findsOneWidget);
    });

    testWidgets('renders every status of the same call', (tester) async {
      Widget build(ToolCallView call) => _app(
        ToolRenderer(
          name: 'showWeather',
          builder: (context, call) => switch (call.status) {
            ToolCallStatus.inProgress => const Text('loading'),
            ToolCallStatus.executing => Text('fetching ${call.args['city']}'),
            ToolCallStatus.complete => Text('result ${call.result}'),
          },
          child: ToolCallWidget(call: call),
        ),
      );

      await tester.pumpWidget(build(_call('showWeather')));
      expect(find.text('loading'), findsOneWidget);

      await tester.pumpWidget(
        build(
          _call(
            'showWeather',
            status: ToolCallStatus.executing,
            args: const {'city': 'Lima'},
          ),
        ),
      );
      expect(find.text('fetching Lima'), findsOneWidget);

      await tester.pumpWidget(
        build(
          _call(
            'showWeather',
            status: ToolCallStatus.complete,
            args: const {'city': 'Lima'},
            result: 'sunny',
          ),
        ),
      );
      expect(find.text('result sunny'), findsOneWidget);
    });
  });
}
