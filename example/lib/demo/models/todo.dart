import 'package:json_annotation/json_annotation.dart';

part 'todo.g.dart';

/// One item of the shared todo list.
///
/// The agent writes these too, so [done] falls back to `false` when it
/// leaves it out.
@JsonSerializable()
class const Todo({required final String title, final bool done = false}) {
  factory fromJson(Map<String, Object?> json) => _$TodoFromJson(json);

  Map<String, Object?> toJson() => _$TodoToJson(this);

  /// Returns this todo with [done] flipped.
  Todo toggled() => Todo(title: title, done: !done);
}
