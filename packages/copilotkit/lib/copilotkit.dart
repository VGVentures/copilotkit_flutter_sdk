/// Pure Dart core of the CopilotKit SDK.
///
/// Connects to a Copilot Runtime over AG-UI and keeps agent state, frontend
/// tools and context in sync. Has no Flutter dependency.
library;

export 'package:ack/ack.dart' show Ack, AckSchema, ObjectSchema;
export 'package:ag_ui/ag_ui.dart'
    show
        // Errors reported to `CopilotKitClient.onError` and `AgentState.error`.
        AGUIError,
        AGUITimeoutError,
        ActivityDeltaEvent,
        ActivityMessage,
        ActivitySnapshotEvent,
        AgUiError,
        AssistantMessage,
        BaseEvent,
        // The conversation: messages, their content and the tool types of
        // `RunAgentInput`.
        CancellationError,
        Context,
        CustomEvent,
        DataSource,
        DecodingError,
        DeveloperMessage,
        EventType,
        FunctionCall,
        InputContent,
        InputContentSource,
        Message,
        MessageRole,
        MessagesSnapshotEvent,
        MultimodalContent,
        ProtocolViolationError,
        RawEvent,
        ReasoningEncryptedValueEvent,
        ReasoningEndEvent,
        ReasoningMessage,
        ReasoningMessageChunkEvent,
        ReasoningMessageContentEvent,
        // The events of a run, for implementing an `AgentTransport` and for
        // reading `AgentState.error`.
        ReasoningMessageEndEvent,
        ReasoningMessageStartEvent,
        ReasoningStartEvent,
        RunAgentInput,
        RunErrorEvent,
        RunFinishedEvent,
        RunStartedEvent,
        ServerError,
        StateDeltaEvent,
        StateSnapshotEvent,
        StepFinishedEvent,
        StepStartedEvent,
        SystemMessage,
        TextContent,
        TextMessageChunkEvent,
        TextMessageContentEvent,
        TextMessageEndEvent,
        TextMessageRole,
        TextMessageStartEvent,
        Tool,
        ToolCall,
        ToolCallArgsEvent,
        ToolCallChunkEvent,
        ToolCallEndEvent,
        ToolCallResultEvent,
        ToolCallStartEvent,
        ToolMessage,
        TransportError,
        UrlSource,
        UserMessage,
        UserMessageContent;

export 'src/agent/copilot_agent.dart';
export 'src/agent/models/agent_state.dart';
export 'src/client/copilot_error_handler.dart';
export 'src/client/copilot_kit_client.dart';
export 'src/client/copilot_kit_event.dart';
export 'src/client/headers_builder.dart';
export 'src/client/models/copilot_kit_state.dart';
export 'src/context/agent_context_entry.dart';
export 'src/tools/cancellation_controller.dart';
export 'src/tools/cancellation_signal.dart';
export 'src/tools/frontend_tool.dart';
export 'src/tools/frontend_tool_handler.dart';
export 'src/tools/models/tool_call_status.dart';
export 'src/tools/models/tool_call_view.dart';
export 'src/transport/ag_ui_transport.dart';
export 'src/transport/agent_transport.dart';
