import 'package:copilotkit/src/json/models/json_encodable.dart';
import 'package:equatable/equatable.dart';

/// Decodes a JSON object into a model, e.g. a `fromJson` factory.
typedef JsonDecoder<T> = T Function(Map<String, Object?> json);

/// A JSON object, e.g. the arguments of a tool call or the properties sent
/// with every run.
///
/// Read it as a model with [decode] or [tryDecode].
class const JsonObject([final Map<String, Object?> _fields = const {}])
    extends Equatable
    implements JsonEncodable {
  /// Creates an object with the given fields.
  this;

  /// Wraps [json], which must be a JSON object.
  ///
  /// Throws a [FormatException] when it isn't.
  factory fromJson(Object? json) => switch (json) {
    final Map<String, Object?> fields => JsonObject(fields),
    _ => throw FormatException('Expected a JSON object, got $json'),
  };

  /// Decodes this object with [decoder].
  ///
  /// Throws what [decoder] throws.
  T decode<T>(JsonDecoder<T> decoder) => decoder(_fields);

  /// Decodes this object with [decoder], or returns `null` when [decoder]
  /// throws, e.g. for arguments that are still streaming in.
  T? tryDecode<T>(JsonDecoder<T> decoder) {
    try {
      return decoder(_fields);
      // Decoders throw anything, e.g. a TypeError from a hand-written one.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  @override
  Map<String, Object?> toJson() => _fields;

  @override
  List<Object?> get props => [_fields];
}
