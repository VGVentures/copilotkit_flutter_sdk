import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

class _MockAgentContextEntry extends Mock implements AgentContextEntry;

void main() {
  group(CopilotContext, () {
    late _MockCopilotKitClient client;
    late List<_MockAgentContextEntry> entries;

    _MockCopilotKitClient mockClient() {
      final mock = _MockCopilotKitClient();
      when(() => mock.addContext(any(), any())).thenAnswer((_) {
        final entry = _MockAgentContextEntry();
        entries.add(entry);
        return entry;
      });
      return mock;
    }

    setUp(() {
      entries = [];
      client = mockClient();
    });

    Widget build(
      Object? value, {
      String description = 'Current user',
      CopilotKitClient? withClient,
    }) {
      return CopilotKit.value(
        client: withClient ?? client,
        child: CopilotContext(
          description: description,
          value: value,
          child: const SizedBox(),
        ),
      );
    }

    testWidgets('adds the entry on mount', (tester) async {
      await tester.pumpWidget(build({'name': 'Ada'}));

      verify(() => client.addContext('Current user', {'name': 'Ada'}))
          .called(1);
    });

    testWidgets('updates the entry when the value changes', (tester) async {
      await tester.pumpWidget(build({'name': 'Ada'}));

      await tester.pumpWidget(build({'name': 'Grace'}));

      verify(() => entries.single.update({'name': 'Grace'})).called(1);
      verify(() => client.addContext(any(), any())).called(1);
    });

    testWidgets('replaces the entry when the description changes', (
      tester,
    ) async {
      await tester.pumpWidget(build(1));

      await tester.pumpWidget(build(1, description: 'Unread'));

      verify(() => entries.first.remove()).called(1);
      verify(() => client.addContext('Unread', 1)).called(1);
    });

    testWidgets('moves the entry when the client changes', (tester) async {
      final other = mockClient();
      await tester.pumpWidget(build(1));

      await tester.pumpWidget(build(1, withClient: other));

      verify(() => entries.first.remove()).called(1);
      verify(() => other.addContext('Current user', 1)).called(1);
    });

    testWidgets('removes the entry on dispose', (tester) async {
      await tester.pumpWidget(build(1));

      await tester.pumpWidget(
        CopilotKit.value(client: client, child: const SizedBox()),
      );

      verify(() => entries.single.remove()).called(1);
    });
  });
}
