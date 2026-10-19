import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/context/context.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:uuid/uuid.dart';

/// Builds the input of a run from an agent and what the app registered.
class const RunInputBuilder({
  /// Generates the id of each run.
  final Uuid _uuid = const Uuid(),
}) {
  /// Creates a builder.
  this;

  /// The input for a new run of [agent], with the frontend [tools], the
  /// [context] entries (each value JSON-encoded) and the forwarded
  /// [properties].
  RunAgentInput build({
    required CopilotAgentState agent,
    required Iterable<FrontendTool> tools,
    required Iterable<AgentContextEntry> context,
    required Map<String, Object?> properties,
  }) => RunAgentInput(
    threadId: agent.threadId,
    runId: _uuid.v4(),
    state: agent.sharedState,
    messages: agent.messages,
    tools: [
      for (final tool in tools)
        Tool(
          name: tool.name,
          description: tool.description,
          parameters: ToolSchema(tool.parameters).toJson(),
        ),
    ],
    context: [
      for (final entry in context)
        Context(description: entry.description, value: jsonEncode(entry.value)),
    ],
    forwardedProps: properties,
  );
}
