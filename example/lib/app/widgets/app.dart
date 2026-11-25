import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/app/error_logger.dart';
import 'package:example/app/thread_id_store.dart';
import 'package:example/chat/chat.dart';
import 'package:example/demo/demo.dart';
import 'package:flutter/material.dart';

class const App({
  /// Copilot Runtime URL from `--dart-define=RUNTIME_URL=...`.
  required final String runtimeUrl,

  /// The conversation's thread, kept across launches (see `ThreadIdStore`).
  required final String threadId,

  /// Keeps the thread the user switches to, so the next launch opens it.
  /// `null` for none.
  final ThreadIdStore? _threadIdStore,

  /// Whether to capture a trajectory for Automatic Learning, from
  /// `--dart-define=LEARNING=true`.
  final bool learning = false,

  /// Receives the SDK's errors.
  final ErrorLogger _logger = const ErrorLogger(),
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(runtimeUrl);
    final isValid = uri != null && uri.hasScheme && uri.host.isNotEmpty;
    final app = MaterialApp(
      title: 'CopilotKit',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF6766FC)),
      navigatorObservers: [CopilotNavigatorObserver()],
      home: isValid
          ? WeatherDemo(
              child: BarChartDemo(
                child: CopilotAgentScope(
                  agentId: ChatPage.agentId,
                  threadId: threadId,
                  child: ChatPage(
                    header: const TodoPanel(),
                    onThreadSelected: _threadIdStore?.save,
                  ),
                ),
              ),
            )
          : const _MissingRuntimeScreen(),
    );
    if (!isValid) return app;
    return CopilotKit(
      runtimeUrl: uri,
      onError: _logger.call,
      learning: learning ? const CopilotLearning() : null,
      child: app,
    );
  }
}

class const _MissingRuntimeScreen() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Runtime URL missing', style: textTheme.headlineSmall),
              const SizedBox(height: 12),
              const Text(
                'Start the local runtime (see example/README.md) and run the '
                'app with its URL:',
              ),
              const SizedBox(height: 12),
              const SelectableText(
                'flutter run --dart-define=RUNTIME_URL=http://<lan-ip>:8200/api/copilotkit',
                style: TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
