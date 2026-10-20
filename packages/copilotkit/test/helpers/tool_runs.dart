import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';

/// The tools, and the runs that call them, the client tests share.
class const ToolRuns() {
  /// Creates the tool runs.
  this;

  /// A `showWeather` tool with a required `city` and optional `days`, whose
  /// handler gets the arguments as a [JsonObject].
  FrontendTool<JsonObject> weatherTool(
    FrontendToolHandler<JsonObject> handler,
  ) {
    return FrontendTool(
      name: 'showWeather',
      description: 'Show the weather for a city',
      parameters: Ack.object({
        'city': Ack.string().describe('City name'),
        'days': Ack.integer().optional(),
      }),
      decode: JsonObject.new,
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

  /// A `confirmAction` human-in-the-loop tool with a required `action`.
  HumanInTheLoopTool<JsonObject> approvalTool({bool followUp = true}) {
    return HumanInTheLoopTool(
      name: 'confirmAction',
      description: 'Ask the user to confirm an action',
      parameters: Ack.object({'action': Ack.string()}),
      decode: JsonObject.new,
      followUp: followUp,
    );
  }

  /// The events that start the `confirmAction` call [id] with [args], without
  /// ending the run.
  List<BaseEvent> approvalCall(
    String id, {
    String args = '{"action": "delete"}',
    String parentMessageId = 'a1',
  }) {
    return [
      ToolCallStartEvent(
        toolCallId: id,
        toolCallName: 'confirmAction',
        parentMessageId: parentMessageId,
      ),
      ToolCallArgsEvent(toolCallId: id, delta: args),
      ToolCallEndEvent(toolCallId: id),
    ];
  }

  /// A run that calls `confirmAction` once per id in [ids], in one message.
  List<BaseEvent> approvalRun(
    String threadId, {
    List<String> ids = const ['c1'],
    String args = '{"action": "delete"}',
  }) {
    return [
      RunStartedEvent(threadId: threadId, runId: 'r1'),
      for (final id in ids) ...approvalCall(id, args: args),
      RunFinishedEvent(threadId: threadId, runId: 'r1'),
    ];
  }
}
