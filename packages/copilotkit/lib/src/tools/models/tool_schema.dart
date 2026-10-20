import 'package:equatable/equatable.dart';

/// Describes a value a tool takes: its type and, for objects and lists,
/// what they contain.
///
/// A tool's `ClientTool.parameters` is an [ObjectToolSchema]. It's sent to
/// the agent as JSON Schema, and each call's arguments are validated with it
/// before the tool runs. Every value is required unless [optional] is
/// `true`, and an object accepts no properties besides the ones it lists.
///
/// ```dart
/// const ToolSchema.object({
///   'city': ToolSchema.string(description: 'City name, e.g. Lima'),
///   'days': ToolSchema.integer(optional: true),
/// })
/// ```
///
/// Sealed: switch over it to handle every kind of value.
sealed class ToolSchema extends Equatable {
  const new({this.description, this.optional = false});

  /// An object with the given [properties]; see [ObjectToolSchema].
  const factory object(
    Map<String, ToolSchema> properties, {
    String? description,
    bool optional,
  }) = ObjectToolSchema;

  /// A string; see [StringToolSchema].
  const factory string({String? description, bool optional}) = StringToolSchema;

  /// An integer; see [IntegerToolSchema].
  const factory integer({String? description, bool optional}) =
      IntegerToolSchema;

  /// Any number; see [NumberToolSchema].
  const factory number({String? description, bool optional}) = NumberToolSchema;

  /// `true` or `false`; see [BooleanToolSchema].
  const factory boolean({String? description, bool optional}) =
      BooleanToolSchema;

  /// One of the given string [values]; see [EnumToolSchema].
  const factory enumString(
    List<String> values, {
    String? description,
    bool optional,
  }) = EnumToolSchema;

  /// A list whose elements match [items]; see [ListToolSchema].
  const factory list(ToolSchema items, {String? description, bool optional}) =
      ListToolSchema;

  /// Tells the agent what the value is, e.g. `City name, e.g. Lima`.
  final String? description;

  /// Whether the value may be left out. Values are required by default.
  final bool optional;

  @override
  List<Object?> get props => [description, optional];
}

/// An object with the given [properties] and no others.
final class const ObjectToolSchema(
  /// The schema of each property, by name.
  final Map<String, ToolSchema> properties, {
  super.description,
  super.optional,
}) extends ToolSchema {
  /// Creates a schema for an object with the given [properties].
  this;

  @override
  List<Object?> get props => [...super.props, properties];
}

/// A string.
final class const StringToolSchema({super.description, super.optional})
    extends ToolSchema {
  /// Creates a schema for a string.
  this;
}

/// An integer.
final class const IntegerToolSchema({super.description, super.optional})
    extends ToolSchema {
  /// Creates a schema for an integer.
  this;
}

/// Any number, integer or not.
final class const NumberToolSchema({super.description, super.optional})
    extends ToolSchema {
  /// Creates a schema for a number.
  this;
}

/// `true` or `false`.
final class const BooleanToolSchema({super.description, super.optional})
    extends ToolSchema {
  /// Creates a schema for a boolean.
  this;
}

/// One of the given string [values].
final class const EnumToolSchema(
  /// The strings the value may be.
  final List<String> values, {
  super.description,
  super.optional,
}) extends ToolSchema {
  /// Creates a schema for one of the given string [values].
  this;

  @override
  List<Object?> get props => [...super.props, values];
}

/// A list whose elements all match [items].
final class const ListToolSchema(
  /// The schema of each element.
  final ToolSchema items, {
  super.description,
  super.optional,
}) extends ToolSchema {
  /// Creates a schema for a list whose elements match [items].
  this;

  @override
  List<Object?> get props => [...super.props, items];
}
