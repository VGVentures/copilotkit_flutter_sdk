import 'package:copilotkit/src/agent/models/shared_state.dart';
import 'package:copilotkit/src/json/json.dart';

/// Applies RFC 6902 JSON Patches to a [SharedState].
class const SharedStatePatcher({
  /// Applies the operations to the state's JSON.
  final JsonPatcher _patcher = const JsonPatcher(),
}) {
  /// Creates a patcher.
  this;

  /// Returns [state] with [operations] applied. A missing state is patched
  /// as an empty object.
  ///
  /// Throws a [FormatException] when an operation doesn't apply (a missing
  /// path, a failed test) or the result isn't a JSON object.
  SharedState apply(SharedState? state, List<JsonPatchOperation> operations) =>
      SharedState.fromJson(
        _patcher.apply(
          state?.toJson() ?? const <String, Object?>{},
          operations,
        ),
      );
}
