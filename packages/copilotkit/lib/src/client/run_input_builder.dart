import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/context/context.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:uuid/uuid.dart';

/// Builds the input of a run from an agent and what the app registered.
class const RunInputBuilder({
  /// Generates the id of each run.
  final Uuid _uuid = const Uuid(),

  /// Encodes the parameters of each tool as JSON Schema.
  final JsonSchemaEncoder _schemaEncoder = const JsonSchemaEncoder(),
}) {
  /// Creates a builder.
  this;

  /// Returns the input for a new run of [agent], with the client [tools], the
  /// [context] entries (each value JSON-encoded) and the forwarded
  /// [properties], if any.
  ///
  /// Throws a [FormatException] when the JSON of [properties] isn't an
  /// object: AG-UI only sends an object as the forwarded properties.
  RunAgentInput build({
    required CopilotKitAgentState agent,
    required Iterable<ClientTool<Object?>> tools,
    required Iterable<AgentContextEntry> context,
    JsonEncodable? properties,
  }) => RunAgentInput(
    threadId: agent.threadId,
    runId: _uuid.v4(),
    state: agent.sharedState?.toJson(),
    messages: agent.messages,
    tools: [
      for (final tool in tools)
        Tool(
          name: tool.name,
          description: tool.description,
          parameters: _schemaEncoder.encode(tool.parameters),
        ),
    ],
    context: [
      for (final entry in context)
        Context(description: entry.description, value: jsonEncode(entry.value)),
    ],
    forwardedProps: properties == null
        ? null
        : JsonObject.fromJson(properties.toJson()).toJson(),
  );
}
