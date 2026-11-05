import 'package:ack/ack.dart';
import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/copilotkit.dart';

/// A `showWeather` tool with a required `city` and optional `days`, whose
/// handler gets the arguments as a map.
FrontendTool<Map<String, Object?>> weatherTool(
  FrontendToolHandler<Map<String, Object?>> handler,
) {
  return FrontendTool(
    name: 'showWeather',
    description: 'Show the weather for a city',
    parameters: Ack.object({
      'city': Ack.string().describe('City name'),
      'days': Ack.integer().optional(),
    }),
    decode: Map<String, Object?>.of,
    handler: handler,
  );
}

/// A `showWeather` tool without a handler, like a render-only component.
FrontendTool<Map<String, Object?>> componentTool({bool followUp = true}) {
  return FrontendTool(
    name: 'showWeather',
    description: 'Show the weather for a city',
    parameters: Ack.object({
      'city': Ack.string().describe('City name'),
      'days': Ack.integer().optional(),
    }),
    decode: Map<String, Object?>.of,
    followUp: followUp,
  );
}

/// A run that calls the [name] tool with `{"city": "Lima"}` as call `c1`.
List<ag_ui.BaseEvent> toolCallRun(
  String threadId, {
  String name = 'showWeather',
}) {
  return [
    ag_ui.RunStartedEvent(threadId: threadId, runId: 'r1'),
    ag_ui.ToolCallStartEvent(
      toolCallId: 'c1',
      toolCallName: name,
      parentMessageId: 'a1',
    ),
    const ag_ui.ToolCallArgsEvent(toolCallId: 'c1', delta: '{"city": "Lima"}'),
    const ag_ui.ToolCallEndEvent(toolCallId: 'c1'),
    ag_ui.RunFinishedEvent(threadId: threadId, runId: 'r1'),
  ];
}

/// A run that replies `Sunny in Lima`.
List<ag_ui.BaseEvent> replyRun(String threadId) {
  return [
    ag_ui.RunStartedEvent(threadId: threadId, runId: 'r2'),
    const ag_ui.TextMessageStartEvent(messageId: 'a2'),
    const ag_ui.TextMessageContentEvent(
      messageId: 'a2',
      delta: 'Sunny in Lima',
    ),
    ag_ui.RunFinishedEvent(threadId: threadId, runId: 'r2'),
  ];
}

/// A `confirmAction` human-in-the-loop tool with a required `action`.
HumanInTheLoopTool<Map<String, Object?>> approvalTool({bool followUp = true}) {
  return HumanInTheLoopTool(
    name: 'confirmAction',
    description: 'Ask the user to confirm an action',
    parameters: Ack.object({'action': Ack.string()}),
    decode: Map<String, Object?>.of,
    followUp: followUp,
  );
}

/// The events that start the `confirmAction` call [id] with [args], without
/// ending the run.
List<ag_ui.BaseEvent> approvalCall(
  String id, {
  String args = '{"action": "delete"}',
  String parentMessageId = 'a1',
}) {
  return [
    ag_ui.ToolCallStartEvent(
      toolCallId: id,
      toolCallName: 'confirmAction',
      parentMessageId: parentMessageId,
    ),
    ag_ui.ToolCallArgsEvent(toolCallId: id, delta: args),
    ag_ui.ToolCallEndEvent(toolCallId: id),
  ];
}

/// A run that calls `confirmAction` once per id in [ids], in one message.
List<ag_ui.BaseEvent> approvalRun(
  String threadId, {
  List<String> ids = const ['c1'],
  String args = '{"action": "delete"}',
}) {
  return [
    ag_ui.RunStartedEvent(threadId: threadId, runId: 'r1'),
    for (final id in ids) ...approvalCall(id, args: args),
    ag_ui.RunFinishedEvent(threadId: threadId, runId: 'r1'),
  ];
}
