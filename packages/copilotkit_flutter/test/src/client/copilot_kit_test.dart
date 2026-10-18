import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
      expect(await client.headers!(), {'a': 'b'});
      expect(client.properties, {'userId': '42'});
      expect(client.state, const CopilotKitState());
    });

    testWidgets('provides the client as a bloc', (tester) async {
      late CopilotKitClient fromBloc;
      late CopilotKitClient fromKit;
      await tester.pumpWidget(
        CopilotKit(
          runtimeUrl: runtimeUrl,
          child: Builder(
            builder: (context) {
              fromBloc = context.read<CopilotKitClient>();
              fromKit = CopilotKit.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(fromBloc, same(fromKit));
    });

    testWidgets('calls the headers closure of the latest build', (
      tester,
    ) async {
      late CopilotKitClient client;
      Widget build(String token) => CopilotKit(
        runtimeUrl: runtimeUrl,
        headers: () async => {'Authorization': 'Bearer $token'},
        child: _ClientProbe((c) => client = c),
      );

      await tester.pumpWidget(build('one'));
      final first = client;
      await tester.pumpWidget(build('two'));

      expect(client, same(first));
      expect(await client.headers!(), {'Authorization': 'Bearer two'});
    });

    testWidgets('sends no headers without a headers closure', (tester) async {
      late CopilotKitClient client;
      await tester.pumpWidget(
        CopilotKit(
          runtimeUrl: runtimeUrl,
          child: _ClientProbe((c) => client = c),
        ),
      );

      expect(await client.headers!(), isEmpty);
    });

    testWidgets('reports errors to the onError of the latest build', (
      tester,
    ) async {
      late CopilotKitClient client;
      final reported = <String>[];
      Widget build(String label) => CopilotKit(
        runtimeUrl: runtimeUrl,
        // A run fails when its headers can't be built.
        headers: () async => throw StateError('no token'),
        onError: (error, _) => reported.add(label),
        child: _ClientProbe((c) => client = c),
      );
      await tester.pumpWidget(build('one'));
      await tester.pumpWidget(build('two'));

      client.add(const AgentOpened('default'));
      await tester.pumpAndSettle();
      client.add(const AgentRunRequested('default'));
      await tester.pumpAndSettle();

      expect(reported, ['two']);
    });

    group('fails an assertion in debug mode when', () {
      testWidgets('the runtime url changes', (tester) async {
        Widget build(Uri url) =>
            CopilotKit(runtimeUrl: url, child: const SizedBox());

        await tester.pumpWidget(build(runtimeUrl));
        await tester.pumpWidget(build(Uri.parse('http://other.test/api')));

        expect(tester.takeException(), isA<AssertionError>());
      });

      testWidgets('the properties change', (tester) async {
        Widget build(Map<String, Object?> properties) => CopilotKit(
          runtimeUrl: runtimeUrl,
          properties: properties,
          child: const SizedBox(),
        );

        await tester.pumpWidget(build({'userId': '1'}));
        await tester.pumpWidget(build({'userId': '2'}));

        expect(tester.takeException(), isA<AssertionError>());
      });

      testWidgets('but not for equal properties', (tester) async {
        Widget build(Map<String, Object?> properties) => CopilotKit(
          runtimeUrl: runtimeUrl,
          properties: properties,
          child: const SizedBox(),
        );

        await tester.pumpWidget(build({'userId': '1'}));
        await tester.pumpWidget(build({'userId': '1'}));

        expect(tester.takeException(), isNull);
      });
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
      client.add(const AgentOpened('default'));
      await tester.pumpAndSettle();
      final agent = client.state.agents['default']!;

      // Bloc's close() only completes with a real event loop.
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(Duration.zero);
      });

      expect(agent.isClosed, isTrue);
      expect(client.isClosed, isTrue);
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

        verifyNever(() => client.close());
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
