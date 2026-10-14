import 'dart:async';

/// Handles a frontend tool call on the device.
///
/// Receives the decoded tool [args] and a [signal] that is cancelled when the
/// run is stopped. Returns the result string sent back to the agent.
typedef FrontendToolHandler = Future<String> Function(
  Map<String, Object?> args, {
  required CancellationSignal signal,
});

/// {@template frontend_tool}
/// A tool the agent can call that runs in the app.
///
/// Register it with `CopilotKitClient.registerTool`. When the agent calls it,
/// [handler] runs, its result is appended as a tool message, and the agent
/// continues in the same turn.
/// {@endtemplate}
class FrontendTool {
  /// {@macro frontend_tool}
  const new({
    required this.name,
    required this.description,
    required this.parameters,
    required this.handler,
  });

  /// Unique tool name the agent calls the tool by.
  final String name;

  /// Tells the agent what the tool does and when to call it.
  final String description;

  /// JSON Schema of the arguments the agent must send.
  final JsonSchema parameters;

  /// Runs the tool when the agent calls it.
  final FrontendToolHandler handler;
}

/// {@template json_schema}
/// A JSON Schema describing tool parameters.
///
/// Build one with the named constructors, or wrap an existing schema map with
/// [JsonSchema.raw].
/// {@endtemplate}
class JsonSchema {
  /// {@macro json_schema}
  ///
  /// Wraps an existing JSON Schema [schema] map as is.
  const new raw(Map<String, Object?> schema) : _schema = schema;

  /// A string value.
  new string({String? description})
    : this._typed('string', description: description);

  /// A floating point or integer number.
  new number({String? description})
    : this._typed('number', description: description);

  /// An integer number.
  new integer({String? description})
    : this._typed('integer', description: description);

  /// A `true` or `false` value.
  new boolean({String? description})
    : this._typed('boolean', description: description);

  /// A list whose elements all match [items].
  new array(JsonSchema items, {String? description})
    : this._typed(
        'array',
        description: description,
        extra: {'items': items.toJson()},
      );

  /// An object with the given [properties].
  ///
  /// Names in [required] must be keys of [properties].
  new object(
    Map<String, JsonSchema> properties, {
    List<String> required = const [],
    String? description,
  }) : this._typed(
         'object',
         description: description,
         extra: {
           'properties': {
             for (final entry in properties.entries)
               entry.key: entry.value.toJson(),
           },
           if (required.isNotEmpty) 'required': required,
         },
       );

  new _typed(
    String type, {
    String? description,
    Map<String, Object?> extra = const {},
  }) : _schema = {'type': type, 'description': ?description, ...extra};

  final Map<String, Object?> _schema;

  /// The schema as a JSON-encodable map.
  Map<String, Object?> toJson() => _schema;
}

/// Lifecycle of a tool call as seen by the UI.
enum ToolCallStatus {
  /// The agent is still streaming the arguments; `ToolCallView.args` is
  /// partial.
  inProgress,

  /// The arguments are complete and the handler is running.
  executing,

  /// The handler finished; `ToolCallView.result` is set.
  complete,
}

/// {@template tool_call_view}
/// A tool call made by the agent, shaped for rendering.
/// {@endtemplate}
class ToolCallView {
  /// {@macro tool_call_view}
  const new({
    required this.id,
    required this.name,
    required this.status,
    this.args = const {},
    this.result,
  });

  /// Tool call id; stable for the whole call, use it as a widget key.
  final String id;

  /// Name of the tool being called.
  final String name;

  /// Where the call is in its lifecycle.
  final ToolCallStatus status;

  /// Arguments sent by the agent; partial while [status] is
  /// [ToolCallStatus.inProgress].
  final Map<String, Object?> args;

  /// Result string; set once [status] is [ToolCallStatus.complete].
  final String? result;
}

/// {@template cancellation_signal}
/// Tells a tool handler that its run was stopped.
///
/// The client creates one per tool call and cancels it when the run stops.
/// Handlers check [isCancelled] or await [whenCancelled] to stop early.
/// {@endtemplate}
class CancellationSignal {
  /// {@macro cancellation_signal}
  new();

  final _cancelled = Completer<void>();

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _cancelled.future;

  /// Cancels the signal. Calling it again has no effect.
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}
