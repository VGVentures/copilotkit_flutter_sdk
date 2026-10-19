// Headless use of the CopilotKit core without Flutter.
// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:copilotkit/copilotkit.dart';

Future<void> main() async {
  final client = CopilotKitClient(
    runtimeUrl: Uri.parse('http://localhost:8200/api/copilotkit'),
    headers: () async => {'Authorization': 'Bearer <token>'},
    properties: {'userId': '42'},
    onError: (error, stackTrace) => print('CopilotKit error: $error'),
  );

  // A frontend tool. In Flutter, `CopilotTool` registers it for the
  // lifetime of a widget and renders `ToolCallView`s with a builder.
  final showWeather = FrontendTool(
    name: 'showWeather',
    description: 'Show the weather for a city',
    parameters: Ack.object({'city': Ack.string()}),
    handler: (args, {required signal}) async =>
        jsonEncode({'city': args['city'], 'forecast': 'sunny'}),
  );

  // App data the agent can answer from. In Flutter, `CopilotContext`.
  final user = AgentContextEntry(
    description: 'Current user',
    value: const {'name': 'Ada'},
  );

  client
    ..add(ToolRegistered(showWeather))
    ..add(ContextAdded(user))
    ..add(const AgentOpened('default'));
  final agent = await client.stream
      .map((state) => state.agents['default'])
      .firstWhere((agent) => agent != null);
  final subscription = agent!.stream.listen((state) {
    for (final call in state.toolCalls) {
      final view = switch (call.status) {
        ToolCallStatus.inProgress => 'loading…',
        ToolCallStatus.executing => 'weather for ${call.args['city']}',
        ToolCallStatus.complete => call.result!,
      };
      print('${call.name}: $view');
    }
    print(
      'running: ${state.isRunning}, '
      'messages: ${state.messages.length}',
    );
  });

  await agent.addMessage(
    UserMessage(id: 'user-1', content: "What's the weather in Lima?"),
  );
  agent.run();
  await agent.stream.firstWhere((state) => !state.isRunning);

  await subscription.cancel();
  client
    ..add(ContextRemoved(user.id))
    ..add(ToolUnregistered(showWeather));
  await client.close();
}
