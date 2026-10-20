import 'package:copilotkit/src/json/models/json_encodable.dart';
import 'package:copilotkit/src/json/models/json_object.dart';
import 'package:equatable/equatable.dart';

/// The state an agent shares with the app: any JSON value it sent.
///
/// Read it as a model with [decode].
class const SharedState(final Object? _value)
    extends Equatable
    implements JsonEncodable {
  /// Creates shared state holding a JSON value.
  this;

  /// Decodes the state with [decoder].
  ///
  /// Throws a [FormatException] when the state isn't a JSON object, and
  /// what [decoder] throws.
  T decode<T>(JsonDecoder<T> decoder) =>
      JsonObject.fromJson(_value).decode(decoder);

  @override
  Object? toJson() => _value;

  @override
  List<Object?> get props => [_value];
}
