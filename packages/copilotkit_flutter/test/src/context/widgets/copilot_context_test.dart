import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/recording_client.dart';

void main() {
  group(CopilotContext, () {
    late RecordingClient client;

    setUp(() => client = RecordingClient());

    Widget build(
      JsonEncodable value, {
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
      await tester.pumpWidget(build(const JsonObject({'name': 'Ada'})));

      final added = client.addedEntries.single;
      expect(added.description, 'Current user');
      expect(added.value, const JsonObject({'name': 'Ada'}));
      expect(client.calls, hasLength(1));
    });

    testWidgets('updates the entry when the value changes', (tester) async {
      await tester.pumpWidget(build(const JsonObject({'name': 'Ada'})));

      await tester.pumpWidget(build(const JsonObject({'name': 'Grace'})));

      final added = client.addedEntries.single;
      expect(client.calls, [
        ClientCall('addContext', [added]),
        ClientCall('updateContext', [
          added.id,
          const JsonObject({'name': 'Grace'}),
        ]),
      ]);
    });

    testWidgets('replaces the entry when the description changes', (
      tester,
    ) async {
      await tester.pumpWidget(build(const JsonObject({'unread': 1})));

      await tester.pumpWidget(
        build(const JsonObject({'unread': 1}), description: 'Unread'),
      );

      final [added, replacement] = client.addedEntries;
      expect(client.calls, [
        ClientCall('addContext', [added]),
        ClientCall('removeContext', [added.id]),
        ClientCall('addContext', [replacement]),
      ]);
      expect(replacement.description, 'Unread');
    });

    testWidgets('moves the entry when the client changes', (tester) async {
      final other = RecordingClient();
      await tester.pumpWidget(build(const JsonObject({'unread': 1})));

      await tester.pumpWidget(
        build(const JsonObject({'unread': 1}), withClient: other),
      );

      final added = client.addedEntries.single;
      expect(client.calls, [
        ClientCall('addContext', [added]),
        ClientCall('removeContext', [added.id]),
      ]);
      final moved = other.addedEntries.single;
      expect(moved.description, 'Current user');
      expect(moved.value, const JsonObject({'unread': 1}));
    });

    testWidgets('removes the entry on dispose', (tester) async {
      await tester.pumpWidget(build(const JsonObject({'unread': 1})));

      await tester.pumpWidget(
        CopilotKit.value(client: client, child: const SizedBox()),
      );

      final added = client.addedEntries.single;
      expect(client.calls, [
        ClientCall('addContext', [added]),
        ClientCall('removeContext', [added.id]),
      ]);
    });
  });
}
