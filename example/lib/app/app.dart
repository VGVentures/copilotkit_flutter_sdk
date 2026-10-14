import 'dart:developer';

import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/chat/chat_screen.dart';
import 'package:example/demo/weather_demo.dart';
import 'package:flutter/material.dart';

class const App({
  /// Copilot Runtime URL from `--dart-define=RUNTIME_URL=...`.
  required final String runtimeUrl,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(runtimeUrl);
    final isValid = uri != null && uri.hasScheme && uri.host.isNotEmpty;
    final app = MaterialApp(
      title: 'CopilotKit',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF6766FC)),
      home: isValid
          ? const WeatherDemo(child: ChatPage())
          : const _MissingRuntimeScreen(),
    );
    if (!isValid) return app;
    return CopilotKit(
      runtimeUrl: uri,
      onError: (error, stackTrace) =>
          log('CopilotKit error', error: error, stackTrace: stackTrace),
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
