/// Pure Dart core of the CopilotKit SDK.
///
/// Connects to a Copilot Runtime over AG-UI and keeps agent state, frontend
/// tools and context in sync. Has no Flutter dependency.
library;

export 'package:ag_ui/ag_ui.dart' show BaseEvent, EventType, RunAgentInput;

export 'src/agent/agent.dart';
export 'src/client/client.dart'
    hide
        ActiveRun,
        AgentRunner,
        RunInputBuilder,
        RunResult,
        RunStreamer,
        ToolCallRunner,
        Turn;
export 'src/context/context.dart' hide AgentContextStore;
export 'src/messages/messages.dart';
export 'src/tools/tools.dart'
    hide
        FallbackToolResult,
        ToolCallExecutor,
        ToolCallOutcome,
        ToolRegistry,
        ToolResponses;
export 'src/transport/transport.dart' show AgentTransport;
