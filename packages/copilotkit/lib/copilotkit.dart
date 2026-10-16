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

export 'src/agent/models/agent_snapshot.dart';
export 'src/agent_transport.dart';
export 'src/client/copilot_error_handler.dart';
export 'src/client/copilot_kit_client.dart';
export 'src/client/headers_builder.dart';
export 'src/context.dart';
export 'src/tools/cancellation_signal.dart';
export 'src/tools/frontend_tool.dart';
export 'src/tools/frontend_tool_handler.dart';
export 'src/tools/models/tool_call_status.dart';
export 'src/tools/models/tool_call_view.dart';
