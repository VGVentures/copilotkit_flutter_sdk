import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitBloc extends Mock implements CopilotKitBloc;

void main() {
  setUpAll(() => registerFallbackValue(const AgentOpened('fallback')));

  group(CopilotContext, () {
    late _MockCopilotKitBloc client;

    /// The events added to [mock], in order.
    List<CopilotKitEvent> eventsOf(_MockCopilotKitBloc mock) =>
        verify(() => mock.add(captureAny())).captured.cast<CopilotKitEvent>();

    setUp(() => client = _MockCopilotKitBloc());

    Widget build(
      Object? value, {
      String description = 'Current user',
      Set<String>? agentIds,
      CopilotKitBloc? withClient,
    }) {
      return CopilotKit.value(
        client: withClient ?? client,
        child: CopilotContext(
          description: description,
          value: value,
          agentIds: agentIds,
          child: const SizedBox(),
        ),
      );
    }

    testWidgets('adds the entry on mount', (tester) async {
      await tester.pumpWidget(build({'name': 'Ada'}));

      final added = eventsOf(client).single as ContextAdded;
      expect(added.entry.description, 'Current user');
      expect(added.entry.value, {'name': 'Ada'});
    });

    testWidgets('adds the agent ids to the entry', (tester) async {
      await tester.pumpWidget(build(1, agentIds: {'ops'}));

      final added = eventsOf(client).single as ContextAdded;
      expect(added.entry.agentIds, {'ops'});
    });

    testWidgets('replaces the entry when the agent ids change', (tester) async {
      await tester.pumpWidget(build(1, agentIds: {'ops'}));

      // The same ids in another set: nothing to replace.
      await tester.pumpWidget(build(1, agentIds: {'ops'}));
      await tester.pumpWidget(build(1, agentIds: {'ops', 'chat'}));

      final events = eventsOf(client);
      final added = events.first as ContextAdded;
      expect(events[1], ContextRemoved(added.entry.id));
      expect((events[2] as ContextAdded).entry.agentIds, {'ops', 'chat'});
      expect(events, hasLength(3));
    });

    testWidgets('updates the entry when the value changes', (tester) async {
      await tester.pumpWidget(build({'name': 'Ada'}));

      await tester.pumpWidget(build({'name': 'Grace'}));

      final events = eventsOf(client);
      final added = events.first as ContextAdded;
      expect(events, [
        added,
        ContextUpdated(added.entry.id, const {'name': 'Grace'}),
      ]);
    });

    testWidgets('replaces the entry when the description changes', (
      tester,
    ) async {
      await tester.pumpWidget(build(1));

      await tester.pumpWidget(build(1, description: 'Unread'));

      final events = eventsOf(client);
      final added = events.first as ContextAdded;
      expect(events[1], ContextRemoved(added.entry.id));
      expect((events[2] as ContextAdded).entry.description, 'Unread');
      expect(events, hasLength(3));
    });

    testWidgets('moves the entry when the client changes', (tester) async {
      final other = _MockCopilotKitBloc();
      await tester.pumpWidget(build(1));

      await tester.pumpWidget(build(1, withClient: other));

      final events = eventsOf(client);
      final added = events.first as ContextAdded;
      expect(events, [added, ContextRemoved(added.entry.id)]);
      final moved = eventsOf(other).single as ContextAdded;
      expect(moved.entry.description, 'Current user');
      expect(moved.entry.value, 1);
    });

    testWidgets('removes the entry on dispose', (tester) async {
      await tester.pumpWidget(build(1));

      await tester.pumpWidget(
        CopilotKit.value(client: client, child: const SizedBox()),
      );

      final events = eventsOf(client);
      final added = events.first as ContextAdded;
      expect(events, [added, ContextRemoved(added.entry.id)]);
    });
  });
}
