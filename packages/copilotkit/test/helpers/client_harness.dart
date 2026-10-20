import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';

import 'mock_agent_transport.dart';

/// A [CopilotKitClient] on a mocked transport.
///
/// Each run streams the next entry of [runs]; stops always succeed.
class ClientHarness {
  /// Creates a harness with no queued runs.
  new() {
    transport
      ..stubRun(() => runs.removeAt(0))
      ..stubStop();
    when(transport.close).thenAnswer((_) async {});
  }

  /// The mocked transport behind [client].
  final MockAgentTransport transport = MockAgentTransport();

  /// Errors reported through the client's `onError`.
  final List<Object> errors = [];

  /// Event streams for the next runs, consumed in order.
  final List<Stream<ag_ui.BaseEvent>> runs = [];

  /// The client under test.
  late final CopilotKitClient client = CopilotKitClient(
    runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
    onError: (error, _) => errors.add(error),
    transport: transport,
  );

  /// The default agent of [client].
  late final CopilotAgent agent = client.agent('default');
}
