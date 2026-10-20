import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the agent in scope on every build and records it.
class const _Probe(final List<CopilotKitAgent> agents) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    agents.add(CopilotAgentScope.of(context));
    return const SizedBox();
  }
}

void main() {
  group(CopilotAgentScope, () {
    late CopilotKitClient client;
    late List<CopilotKitAgent> seen;

    CopilotKitClient newClient(String host) {
      final client = CopilotKitClient(
        runtimeUrl: Uri.parse('http://$host/api/copilotkit'),
      );
      addTearDown(client.close);
      return client;
    }

    setUp(() {
      client = newClient('runtime.test');
      seen = [];
    });

    Widget build(Widget child, {CopilotKitClient? withClient}) =>
        CopilotKit.value(client: withClient ?? client, child: child);

    testWidgets('opens the agent and provides it to its child', (tester) async {
      await tester.pumpWidget(
        build(CopilotAgentScope(agentId: 'ops', child: _Probe(seen))),
      );

      expect(client.agents.keys, ['ops']);
      expect(seen, [same(client.agents['ops'])]);
    });

    testWidgets('shares one agent between scopes with the same id', (
      tester,
    ) async {
      final other = <CopilotKitAgent>[];
      await tester.pumpWidget(
        build(
          Column(
            children: [
              CopilotAgentScope(agentId: 'ops', child: _Probe(seen)),
              CopilotAgentScope(agentId: 'ops', child: _Probe(other)),
              CopilotAgentScope(agentId: 'chat', child: _Probe(other)),
            ],
          ),
        ),
      );

      expect(client.agents.keys, unorderedEquals(['ops', 'chat']));
      expect(seen.single, same(client.agents['ops']));
      expect(other.first, same(client.agents['ops']));
      expect(other.last, same(client.agents['chat']));
    });

    testWidgets('reuses an agent the client already opened', (tester) async {
      final agent = client.agent('ops');

      await tester.pumpWidget(
        build(CopilotAgentScope(agentId: 'ops', child: _Probe(seen))),
      );

      expect(seen, [same(agent)]);
    });

    testWidgets('does not close the agent when removed', (tester) async {
      await tester.pumpWidget(
        build(CopilotAgentScope(agentId: 'ops', child: _Probe(seen))),
      );
      final agent = client.agents['ops']!;

      await tester.pumpWidget(build(const SizedBox()));

      expect(agent.isClosed, isFalse);
      expect(client.agents['ops'], same(agent));
    });

    testWidgets('provides another agent when the id changes', (tester) async {
      Widget scope(String agentId) =>
          build(CopilotAgentScope(agentId: agentId, child: _Probe(seen)));

      await tester.pumpWidget(scope('ops'));
      await tester.pumpWidget(scope('chat'));

      expect(seen.last, same(client.agents['chat']));
      expect(client.agents.keys, unorderedEquals(['ops', 'chat']));
    });

    testWidgets('opens the agent on a new client', (tester) async {
      final other = newClient('other.test');
      await tester.pumpWidget(
        build(CopilotAgentScope(agentId: 'ops', child: _Probe(seen))),
      );

      await tester.pumpWidget(
        build(
          CopilotAgentScope(agentId: 'ops', child: _Probe(seen)),
          withClient: other,
        ),
      );

      expect(seen.last, same(other.agents['ops']));
      expect(seen.last, isNot(same(client.agents['ops'])));
    });

    group('of', () {
      testWidgets('throws a clear error without a scope', (tester) async {
        await tester.pumpWidget(_Probe(seen));

        final error = tester.takeException();
        expect(error, isA<FlutterError>());
        expect(
          (error as FlutterError).message,
          contains('No CopilotAgentScope found in context'),
        );
      });
    });

    group('maybeOf', () {
      testWidgets('returns null without a scope', (tester) async {
        CopilotKitAgent? agent;
        var built = false;
        await tester.pumpWidget(
          Builder(
            builder: (context) {
              agent = CopilotAgentScope.maybeOf(context);
              built = true;
              return const SizedBox();
            },
          ),
        );

        expect(built, isTrue);
        expect(agent, isNull);
      });
    });
  });
}
