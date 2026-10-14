// Dev-only probe for the Copilot Runtime v2 contract (task A1).
//
// Usage:
//   fvm dart run tool/round_trip.dart \
//     --url http://localhost:8200/api/copilotkit \
//     [--agent default] [--message "Hello"] [--via-client true]
//
// Prints the runtime info document, then every AG-UI event of one run
// from RUN_STARTED to RUN_FINISHED (or RUN_ERROR). With --via-client, runs
// through CopilotKitClient instead and prints the streamed reply.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> arguments) async {
  final options = _parse(arguments);
  final url = options['url'];
  if (url == null) {
    stderr.writeln(
      'usage: round_trip.dart --url <runtimeUrl> '
      '[--agent <id>] [--message <text>]',
    );
    exit(64);
  }
  final agent = options['agent'] ?? 'default';
  final message = options['message'] ?? 'Say hello in five words.';
  if (options['via-client'] == 'true') {
    return await _viaClient(Uri.parse(url), agent, message);
  }

  final httpClient = http.Client();
  try {
    final info = await httpClient.get(Uri.parse('$url/info'));
    print('GET $url/info -> ${info.statusCode}');
    print(info.body);

    final client = AgUiClient(
      config: AgUiClientConfig(baseUrl: url),
      httpClient: httpClient,
    );
    final input = SimpleRunAgentInput(
      threadId: 'thread-${DateTime.now().millisecondsSinceEpoch}',
      runId: 'run-${DateTime.now().millisecondsSinceEpoch}',
      messages: [UserMessage(id: 'user-1', content: message)],
    );

    print('POST $url/agent/$agent/run');
    await for (final event in client.runAgent('agent/$agent/run', input)) {
      print(jsonEncode(event.toJson()));
    }
  } finally {
    httpClient.close();
  }
}

Future<void> _viaClient(Uri url, String agentId, String message) async {
  final client = CopilotKitClient(
    runtimeUrl: url,
    onError: (error, stackTrace) => print('onError: $error'),
  );
  final agent = client.agent(agentId);
  final subscription = agent.changes.listen((snapshot) {
    final last = snapshot.messages.lastOrNull;
    print(
      'running: ${snapshot.isRunning} | ${last?.role.value}: '
      '${last?.content}',
    );
  });
  await agent.addMessage(UserMessage(id: 'user-1', content: message));
  await agent.run();
  await subscription.cancel();
  await client.dispose();
}

Map<String, String> _parse(List<String> arguments) {
  final options = <String, String>{};
  for (var i = 0; i + 1 < arguments.length; i += 2) {
    options[arguments[i].replaceFirst('--', '')] = arguments[i + 1];
  }
  return options;
}
