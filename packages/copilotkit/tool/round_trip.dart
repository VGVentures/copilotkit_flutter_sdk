// Dev-only probe for the Copilot Runtime v2 contract (task A1).
//
// Usage:
//   fvm dart run tool/round_trip.dart \
//     --url http://localhost:8200/api/copilotkit \
//     [--agent default] [--message "Hello"] [--via-client true]
//     [--record test/fixtures/<name>.jsonl] [--tool true] [--state '{...}']
//
// Prints the runtime info document, then every AG-UI event of one run
// from RUN_STARTED to RUN_FINISHED (or RUN_ERROR). With --via-client, runs
// through CopilotKitClient instead and prints the streamed reply.
//
// With --record, writes the raw SSE data payloads of one run to a JSONL file
// (one event per line, after a `{"fixture": {...}}` header line), bypassing
// ag_ui's decoder so events it can't decode are kept. --tool sends the
// example's showWeather frontend tool; --state sends an initial state.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/tool_schema.dart';
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
  final record = options['record'];
  if (record != null) {
    return await _record(
      url: url,
      agentId: agent,
      message: message,
      file: File(record),
      withTool: options['tool'] == 'true',
      state: options['state'] == null ? null : jsonDecode(options['state']!),
    );
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
  print('done | running: ${agent.isRunning} | error: ${agent.snapshot.error}');
  await client.dispose();
}

/// Placeholder tool from `example/lib/demo/weather_demo.dart`.
final _showWeather = Tool(
  name: 'showWeather',
  description: 'Show the current weather for a city on the user screen.',
  parameters: toolParametersJson(
    Ack.object({'city': Ack.string().describe('City name, e.g. Lima')}),
  ),
);

Future<void> _record({
  required String url,
  required String agentId,
  required String message,
  required File file,
  required bool withTool,
  required Object? state,
}) async {
  final httpClient = http.Client();
  try {
    final info = jsonDecode(
      (await httpClient.get(Uri.parse('$url/info'))).body,
    ) as Map<String, Object?>;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final input = RunAgentInput(
      threadId: 'thread-$stamp',
      runId: 'run-$stamp',
      state: state,
      messages: [UserMessage(id: 'user-1', content: message)],
      tools: [if (withTool) _showWeather],
      context: const [],
    );
    final request = http.Request('POST', Uri.parse('$url/agent/$agentId/run'))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode(input.toJson());
    final response = await httpClient.send(request);
    if (response.statusCode >= 400) {
      stderr.writeln('run failed: HTTP ${response.statusCode}');
      exit(1);
    }

    final lines = <String>[
      jsonEncode({
        'fixture': {
          'source': 'recorded',
          'runtimeVersion': info['version'],
          'recordedOn': DateTime.now().toIso8601String().substring(0, 10),
          'message': message,
          'tools': [if (withTool) _showWeather.name],
          'state': ?state,
        },
      }),
    ];
    final data = <String>[];
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.startsWith('data:')) {
        data.add(line.substring(5).trimLeft());
      } else if (line.isEmpty && data.isNotEmpty) {
        lines.add(jsonEncode(jsonDecode(data.join('\n'))));
        print(lines.last);
        data.clear();
      }
    }
    await file.parent.create(recursive: true);
    await file.writeAsString('${lines.join('\n')}\n');
    print('wrote ${lines.length - 1} events to ${file.path}');
  } finally {
    httpClient.close();
  }
}

Map<String, String> _parse(List<String> arguments) {
  final options = <String, String>{};
  for (var i = 0; i + 1 < arguments.length; i += 2) {
    options[arguments[i].replaceFirst('--', '')] = arguments[i + 1];
  }
  return options;
}
