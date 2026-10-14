/// Pure Dart core of the CopilotKit SDK.
///
/// Connects to a Copilot Runtime over AG-UI and keeps agent state, frontend
/// tools and context in sync. Has no Flutter dependency.
library;

export 'package:ag_ui/ag_ui.dart'
    show
        AssistantMessage,
        BaseEvent,
        DeveloperMessage,
        EventType,
        Message,
        RunAgentInput,
        SystemMessage,
        ToolCall,
        ToolMessage,
        UserMessage;

export 'src/agent_snapshot.dart';
export 'src/agent_transport.dart';
export 'src/client.dart';
export 'src/context.dart';
export 'src/tools.dart';
