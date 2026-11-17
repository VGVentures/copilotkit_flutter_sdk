import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/context/context.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:json_utils/json_utils.dart';
import 'package:uuid/uuid.dart';

/// Builds the input of a run from an agent and what the app registered.
class const RunInputBuilder({
  /// Generates the id of each run.
  final Uuid _uuid = const Uuid(),

  /// Normalizes the JSON Schema of each tool's parameters.
  final JsonSchemaNormalizer _schemaNormalizer = const JsonSchemaNormalizer(),
}) {
  /// Creates a builder.
  this;

  /// The input for a new run of [agent], with the client [tools], the
  /// [context] entries (each value JSON-encoded) and the forwarded
  /// [properties], if any.
  RunAgentInput call({
    required CopilotAgentState agent,
    required Iterable<ClientTool<Object?>> tools,
    required Iterable<AgentContextEntry> context,
    Map<String, Object?>? properties,
  }) => RunAgentInput(
    threadId: agent.threadId,
    runId: _uuid.v4(),
    state: agent.sharedState?.toJson(),
    messages: [for (final message in agent.messages) message.toAgUi()],
    tools: [
      for (final tool in tools)
        Tool(
          name: tool.name,
          description: tool.description,
          // Ack omits `properties` on empty objects, which some providers
          // reject.
          parameters: _schemaNormalizer.normalize(
            tool.parameters.toJsonSchema(),
          ),
        ),
    ],
    context: [
      for (final entry in context)
        Context(description: entry.description, value: jsonEncode(entry.value)),
    ],
    forwardedProps: properties,
  );
}
