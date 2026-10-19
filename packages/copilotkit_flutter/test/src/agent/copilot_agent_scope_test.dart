import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the agent in scope and records it.
class const _Probe(final List<CopilotAgentBloc> agents)
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    agents.add(context.read<CopilotAgentBloc>());
    return const SizedBox();
  }
}

void main() {
  group(CopilotAgentScope, () {
    late CopilotKitBloc client;
    late List<CopilotAgentBloc> seen;

    // The client is created inside the test, so its events run in the fake
    // async zone of the widget tester, which `pump` advances.
    CopilotKitBloc newClient(String host) {
      final client = CopilotKitBloc(
        runtimeUrl: Uri.parse('http://$host/api/copilotkit'),
      );
      addTearDown(client.close);
      return client;
    }

    setUp(() => seen = []);

    Widget build(Widget child, {CopilotKitBloc? withClient}) =>
        CopilotKit.value(client: withClient ?? client, child: child);

    testWidgets('opens the agent and provides it to its child', (tester) async {
      client = newClient('runtime.test');
      await tester.pumpWidget(
        build(CopilotAgentScope(agentId: 'ops', child: _Probe(seen))),
      );
      await tester.pumpAndSettle();

      final agent = client.state.agents['ops']!;
      expect(client.state.agents, hasLength(1));
      expect(seen, [agent]);
    });

    testWidgets('builds nothing until the agent is open', (tester) async {
      client = newClient('runtime.test');
      await tester.pumpWidget(
        build(CopilotAgentScope(agentId: 'ops', child: _Probe(seen))),
      );

      expect(seen, isEmpty);

      await tester.pumpAndSettle();

      expect(seen, hasLength(1));
    });

    testWidgets('shares one agent between scopes with the same id', (
      tester,
    ) async {
      client = newClient('runtime.test');
      final other = <CopilotAgentBloc>[];
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
      await tester.pumpAndSettle();

      expect(client.state.agents.keys, unorderedEquals(['ops', 'chat']));
      expect(seen.last, same(client.state.agents['ops']));
      expect(other.first, same(client.state.agents['ops']));
      expect(other.last, same(client.state.agents['chat']));
    });

    testWidgets('reuses an agent the client already opened', (tester) async {
      client = newClient('runtime.test')..add(const AgentOpened('ops'));
      await tester.pumpAndSettle();
      final agent = client.state.agents['ops']!;

      await tester.pumpWidget(
        build(CopilotAgentScope(agentId: 'ops', child: _Probe(seen))),
      );

      expect(seen, [agent]);
      expect(client.state.agents['ops'], same(agent));
    });

    testWidgets('does not close the agent when removed', (tester) async {
      client = newClient('runtime.test');
      await tester.pumpWidget(
        build(CopilotAgentScope(agentId: 'ops', child: _Probe(seen))),
      );
      await tester.pumpAndSettle();
      final agent = client.state.agents['ops']!;

      await tester.pumpWidget(build(const SizedBox()));

      expect(agent.isClosed, isFalse);
      expect(client.state.agents['ops'], same(agent));
    });

    testWidgets('provides another agent when the id changes', (tester) async {
      client = newClient('runtime.test');
      Widget scope(String agentId) =>
          build(CopilotAgentScope(agentId: agentId, child: _Probe(seen)));

      await tester.pumpWidget(scope('ops'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(scope('ops'));
      await tester.pumpWidget(scope('chat'));
      await tester.pumpAndSettle();

      expect(seen.last, same(client.state.agents['chat']));
      expect(client.state.agents.keys, unorderedEquals(['ops', 'chat']));
    });

    testWidgets('opens the agent on a new client', (tester) async {
      client = newClient('runtime.test');
      final other = newClient('other.test');
      await tester.pumpWidget(
        build(CopilotAgentScope(agentId: 'ops', child: _Probe(seen))),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        build(
          CopilotAgentScope(agentId: 'ops', child: _Probe(seen)),
          withClient: other,
        ),
      );
      await tester.pumpAndSettle();

      expect(seen.last, same(other.state.agents['ops']));
      expect(seen.last, isNot(same(client.state.agents['ops'])));
    });
  });
}
