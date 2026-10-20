// Headless use of the CopilotKit core without Flutter.
// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:copilotkit/copilotkit.dart';

Future<void> main() async {
  final client = CopilotKitClient(
    runtimeUrl: Uri.parse('http://localhost:8200/api/copilotkit'),
    headers: () async => {'Authorization': 'Bearer <token>'},
    properties: const JsonObject({'userId': '42'}),
    onError: (error, stackTrace) => print('CopilotKit error: $error'),
  );

  // A frontend tool. In Flutter, `CopilotKitTool` registers it for the
  // lifetime of a widget and renders `ToolCallView`s with a builder.
  final showWeather = FrontendTool(
    name: 'showWeather',
    description: 'Show the weather for a city',
    parameters: Ack.object({'city': Ack.string()}),
    decode: _WeatherArgs.fromJson,
    handler: (args, {required signal}) async =>
        jsonEncode({'city': args.city, 'forecast': 'sunny'}),
  );

  // App data the agent can answer from. In Flutter, `CopilotKitContext`.
  final user = AgentContextEntry(
    description: 'Current user',
    value: const _User('Ada'),
  );

  client
    ..registerTool(showWeather)
    ..addContext(user);
  final agent = client.agent('default');
  final subscription = agent.stream.listen((state) {
    for (final call in state.toolCalls) {
      final view = switch (call.status) {
        ToolCallStatus.inProgress => 'loading…',
        ToolCallStatus.executing =>
          'weather for ${call.args.tryDecode(_WeatherArgs.fromJson)?.city}',
        ToolCallStatus.complete => call.result!,
      };
      print('${call.name}: $view');
    }
    print(
      'running: ${state.isRunning}, '
      'messages: ${state.messages.length}',
    );
  });

  // Shared state is sent with every run.
  agent
    ..setSharedState(const SharedState({'theme': 'dark'}))
    ..patchSharedState(const [JsonPatchAdd(path: '/units', value: 'metric')]);

  // Completes once the whole turn ends, tool calls included.
  await client.runAgent(
    'default',
    message: UserMessage(id: 'user-1', content: "What's the weather in Lima?"),
  );

  await subscription.cancel();
  client
    ..removeContext(user.id)
    ..unregisterTool(showWeather);
  await client.close();
}

/// The arguments of the `showWeather` tool.
class const _WeatherArgs(final String city) {
  factory fromJson(Map<String, Object?> json) =>
      _WeatherArgs(json['city']! as String);
}

/// The current user, shared with the agent as context.
class const _User(final String name) implements JsonEncodable {
  @override
  Map<String, Object?> toJson() => {'name': name};
}
