import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

class const _ClientProbe(final void Function(CopilotKitClient client) onBuild)
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    onBuild(CopilotKit.of(context));
    return const SizedBox();
  }
}

void main() {
  final runtimeUrl = Uri.parse('http://runtime.test/api/copilotkit');

  group(CopilotKit, () {
    testWidgets('creates a client from its configuration', (tester) async {
      late CopilotKitClient client;
      Future<Map<String, String>> headers() async => {'a': 'b'};
      void onError(Object error, StackTrace stackTrace) {}

      await tester.pumpWidget(
        CopilotKit(
          runtimeUrl: runtimeUrl,
          headers: headers,
          properties: const {'userId': '42'},
          onError: onError,
          child: _ClientProbe((c) => client = c),
        ),
      );

      expect(client.runtimeUrl, runtimeUrl);
      expect(client.headers, same(headers));
      expect(client.properties, {'userId': '42'});
      expect(client.onError, same(onError));
    });

    testWidgets('keeps the same client across rebuilds', (tester) async {
      final clients = <CopilotKitClient>[];
      Widget build() =>
          CopilotKit(runtimeUrl: runtimeUrl, child: _ClientProbe(clients.add));

      await tester.pumpWidget(build());
      await tester.pumpWidget(build());

      expect(clients, hasLength(2));
      expect(clients.last, same(clients.first));
    });

    testWidgets('disposes the client it created when removed', (tester) async {
      late CopilotKitClient client;
      await tester.pumpWidget(
        CopilotKit(
          runtimeUrl: runtimeUrl,
          child: _ClientProbe((c) => client = c),
        ),
      );
      final agent = client.agent('default');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(agent.isClosed, isTrue);
    });

    group('value', () {
      late _MockCopilotKitClient client;

      setUp(() => client = _MockCopilotKitClient());

      testWidgets('provides the injected client', (tester) async {
        late CopilotKitClient provided;

        await tester.pumpWidget(
          CopilotKit.value(
            client: client,
            child: _ClientProbe((c) => provided = c),
          ),
        );

        expect(provided, same(client));
      });

      testWidgets('does not dispose the injected client', (tester) async {
        await tester.pumpWidget(
          CopilotKit.value(client: client, child: const SizedBox()),
        );

        await tester.pumpWidget(const SizedBox());

        verifyNever(() => client.dispose());
      });

      testWidgets('rebuilds dependents when the client changes', (
        tester,
      ) async {
        final other = _MockCopilotKitClient();
        final provided = <CopilotKitClient>[];
        Widget build(CopilotKitClient c) =>
            CopilotKit.value(client: c, child: _ClientProbe(provided.add));

        await tester.pumpWidget(build(client));
        await tester.pumpWidget(build(other));

        expect(provided, [same(client), same(other)]);
      });
    });

    group('of', () {
      testWidgets('throws a clear error without an ancestor', (tester) async {
        await tester.pumpWidget(_ClientProbe((_) {}));

        final error = tester.takeException();
        expect(error, isA<FlutterError>());
        expect(
          (error as FlutterError).message,
          contains('No CopilotKit found in context'),
        );
      });

      testWidgets('maybeOf returns null without an ancestor', (tester) async {
        CopilotKitClient? client = _MockCopilotKitClient();

        await tester.pumpWidget(
          Builder(
            builder: (context) {
              client = CopilotKit.maybeOf(context);
              return const SizedBox();
            },
          ),
        );

        expect(client, isNull);
      });
    });
  });
}
