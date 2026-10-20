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

export 'src/agent/agent.dart'
    show CopilotKitAgent, CopilotKitAgentState, SharedState;
export 'src/client/client.dart'
    show CopilotKitClient, CopilotKitErrorHandler, HeadersBuilder;
export 'src/context/context.dart' show AgentContextEntry;
export 'src/json/json.dart'
    show
        JsonDecoder,
        JsonEncodable,
        JsonObject,
        JsonPatchAdd,
        JsonPatchCopy,
        JsonPatchMove,
        JsonPatchOperation,
        JsonPatchRemove,
        JsonPatchReplace,
        JsonPatchTest;
export 'src/tools/tools.dart'
    show
        CancellationSignal,
        ClientTool,
        FrontendTool,
        FrontendToolHandler,
        HumanInTheLoopTool,
        ToolCallStatus,
        ToolCallView;
export 'src/transport/transport.dart'
    show AgUiTransport, AgentTransport, SkippedEventHandler;
