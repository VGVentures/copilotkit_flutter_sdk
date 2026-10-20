import 'package:equatable/equatable.dart';

/// The state an agent shares with the app: a JSON object.
///
/// Read it as a model with [decode], e.g. `state.decode(Counter.fromJson)`.
class const SharedState(final Map<String, Object?> _value) extends Equatable {
  /// Creates shared state holding the JSON object [_value].
  this;

  /// Decodes the state with [decoder], e.g. a model's `fromJson`. Throws
  /// what [decoder] throws.
  T decode<T>(T Function(Map<String, Object?> json) decoder) => decoder(_value);

  /// Returns the JSON object the state holds.
  Map<String, Object?> toJson() => _value;

  @override
  List<Object?> get props => [_value];
}
