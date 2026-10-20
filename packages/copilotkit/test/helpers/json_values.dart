import 'package:copilotkit/copilotkit.dart';
import 'package:equatable/equatable.dart';

/// A number shared with the agent, for tests.
class const Count(final int value) extends Equatable implements JsonEncodable {
  /// Creates a count of [value].
  this;

  @override
  int toJson() => value;

  @override
  List<Object?> get props => [value];
}

/// A text shared with the agent, for tests.
class const Label(final String value)
    extends Equatable
    implements JsonEncodable {
  /// Creates a label with [value].
  this;

  @override
  String toJson() => value;

  @override
  List<Object?> get props => [value];
}

/// A JSON object shared with the agent, for tests.
class const Fields(final Map<String, Object?> value)
    extends Equatable
    implements JsonEncodable {
  /// Creates an object with the fields [value].
  this;

  @override
  Map<String, Object?> toJson() => value;

  @override
  List<Object?> get props => [value];
}

/// A value whose JSON isn't encodable, for tests.
class const NonJsonValue() implements JsonEncodable {
  /// Creates the value.
  this;

  @override
  Object? toJson() => DateTime(2026);
}
