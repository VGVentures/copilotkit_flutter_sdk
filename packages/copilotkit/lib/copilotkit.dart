/// Pure Dart core of the CopilotKit SDK.
///
/// Connects to a Copilot Runtime over AG-UI and keeps agent state, frontend
/// tools and context in sync. Has no Flutter dependency.
library;

export 'package:ack/ack.dart' show Ack, AckSchema, ObjectSchema;
export 'package:ag_ui/ag_ui.dart'
    show
        AssistantMessage,
        BaseEvent,
        DeveloperMessage,
        EventType,
        FunctionCall,
        Message,
        RunAgentInput,
        RunErrorEvent,
        SystemMessage,
        ToolCall,
        ToolMessage,
        UserMessage;

export 'src/agent/bloc/copilot_agent_bloc.dart'
    hide
        AgentEventReceived,
        AgentRunFailed,
        AgentSettleRequested,
        AgentTurnEnded,
        AgentTurnStarted;
export 'src/client/bloc/copilot_kit_bloc.dart';
export 'src/client/copilot_error_handler.dart';
export 'src/client/headers_builder.dart';
export 'src/context/agent_context_entry.dart';
export 'src/tools/cancellation_signal.dart';
export 'src/tools/frontend_tool.dart';
export 'src/tools/frontend_tool_handler.dart';
export 'src/tools/models/tool_call_status.dart';
export 'src/tools/models/tool_call_view.dart';
export 'src/transport/agent_transport.dart';
