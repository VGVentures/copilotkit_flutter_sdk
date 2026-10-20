import 'dart:collection';

import 'package:copilotkit/src/json/models/json_encodable.dart';
import 'package:copilotkit/src/json/models/json_object.dart';
import 'package:equatable/equatable.dart';

/// The state an agent shares with the app: a JSON object.
///
/// Read it as a model with [decode]; set it from an app model with
/// [SharedState.of].
class const SharedState(final Map<String, Object?> _fields)
    extends Equatable
    implements JsonEncodable {
  /// Creates shared state holding the JSON object [_fields].
  this;

  /// Creates shared state from [value], an app model with `toJson`.
  ///
  /// Throws a [FormatException] when its JSON isn't an object: AG-UI only
  /// sends an object as the state of a run.
  factory of(JsonEncodable value) => SharedState.fromJson(value.toJson());

  /// Wraps [json], which must be a JSON object.
  ///
  /// Throws a [FormatException] when it isn't.
  factory fromJson(Object? json) =>
      SharedState(JsonObject.fromJson(json).toJson());

  /// Decodes the state with [decoder].
  ///
  /// Throws what [decoder] throws.
  T decode<T>(JsonDecoder<T> decoder) => decoder(toJson());

  /// The state as a read-only JSON object.
  @override
  Map<String, Object?> toJson() => UnmodifiableMapView(_fields);

  @override
  List<Object?> get props => [_fields];
}
