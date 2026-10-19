import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';

/// A `showWeather` tool with a required `city` and optional `days`.
FrontendTool weatherTool(FrontendToolHandler handler) {
  return FrontendTool(
    name: 'showWeather',
    description: 'Show the weather for a city',
    parameters: Ack.object({
      'city': Ack.string().describe('City name'),
      'days': Ack.integer().optional(),
    }),
    handler: handler,
  );
}

/// A run that calls the [name] tool with `{"city": "Lima"}` as call `c1`.
List<BaseEvent> toolCallRun(String threadId, {String name = 'showWeather'}) {
  return [
    RunStartedEvent(threadId: threadId, runId: 'r1'),
    ToolCallStartEvent(
      toolCallId: 'c1',
      toolCallName: name,
      parentMessageId: 'a1',
    ),
    const ToolCallArgsEvent(toolCallId: 'c1', delta: '{"city": "Lima"}'),
    const ToolCallEndEvent(toolCallId: 'c1'),
    RunFinishedEvent(threadId: threadId, runId: 'r1'),
  ];
}

/// A run that replies `Sunny in Lima`.
List<BaseEvent> replyRun(String threadId) {
  return [
    RunStartedEvent(threadId: threadId, runId: 'r2'),
    const TextMessageStartEvent(messageId: 'a2'),
    const TextMessageContentEvent(messageId: 'a2', delta: 'Sunny in Lima'),
    RunFinishedEvent(threadId: threadId, runId: 'r2'),
  ];
}
