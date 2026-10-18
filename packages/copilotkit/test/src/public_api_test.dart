import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group('public API', () {
    test('exports what a user needs to work with the ag_ui types', () {
      // Only checks that the names resolve through copilotkit.dart.
      final types = <Type>[
        ActivityMessage,
        ReasoningMessage,
        TextContent,
        MultimodalContent,
        TransportError,
        AGUITimeoutError,
        AgUiError,
        RunStartedEvent,
        TextMessageStartEvent,
        Tool,
        Context,
        AgUiTransport,
      ];

      expect(types, everyElement(isNotNull));
    });

    test('AgUiTransport takes a custom http client factory', () {
      final transport = AgUiTransport(
        runtimeUrl: Uri.parse('https://runtime.test/api'),
        httpClientFactory: () => throw UnimplementedError(),
      );

      expect(transport, isA<AgentTransport>());
    });
  });
}
