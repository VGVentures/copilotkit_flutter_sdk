import 'package:copilotkit/src/tools/tools.dart';
import 'package:test/test.dart';

void main() {
  group(ToolSchema, () {
    group('builds each member', () {
      test('object', () {
        expect(
          const ToolSchema.object({'city': ToolSchema.string()}),
          const ObjectToolSchema({'city': StringToolSchema()}),
        );
      });

      test('string', () {
        expect(const ToolSchema.string(), const StringToolSchema());
      });

      test('integer', () {
        expect(const ToolSchema.integer(), const IntegerToolSchema());
      });

      test('number', () {
        expect(const ToolSchema.number(), const NumberToolSchema());
      });

      test('boolean', () {
        expect(const ToolSchema.boolean(), const BooleanToolSchema());
      });

      test('enumString', () {
        expect(
          const ToolSchema.enumString(['c', 'f']),
          const EnumToolSchema(['c', 'f']),
        );
      });

      test('list', () {
        expect(
          const ToolSchema.list(ToolSchema.string()),
          const ListToolSchema(StringToolSchema()),
        );
      });
    });

    test('is required and has no description by default', () {
      const schema = ToolSchema.string();

      expect(schema.description, isNull);
      expect(schema.optional, isFalse);
    });

    test('keeps description and optional', () {
      const schema = ToolSchema.integer(description: 'Days', optional: true);

      expect(schema.description, 'Days');
      expect(schema.optional, isTrue);
    });

    group('supports value equality', () {
      test('object', () {
        expect(
          const ToolSchema.object({'city': ToolSchema.string()}),
          ToolSchema.object(Map.of({'city': const ToolSchema.string()})),
        );
        expect(
          const ToolSchema.object({'city': ToolSchema.string()}),
          isNot(const ToolSchema.object({'city': ToolSchema.integer()})),
        );
        expect(
          const ToolSchema.object({}),
          isNot(const ToolSchema.object({}, optional: true)),
        );
      });

      test('string', () {
        expect(
          const ToolSchema.string(description: 'City'),
          ToolSchema.string(description: String.fromCharCodes('City'.runes)),
        );
        expect(
          const ToolSchema.string(),
          isNot(const ToolSchema.string(description: 'City')),
        );
      });

      test('integer', () {
        expect(
          const ToolSchema.integer(optional: true),
          ToolSchema.integer(optional: bool.parse('true')),
        );
        expect(
          const ToolSchema.integer(),
          isNot(const ToolSchema.integer(optional: true)),
        );
      });

      test('number', () {
        expect(
          const ToolSchema.number(description: 'Price'),
          ToolSchema.number(description: String.fromCharCodes('Price'.runes)),
        );
        expect(
          const ToolSchema.number(),
          isNot(const ToolSchema.number(description: 'Price')),
        );
      });

      test('boolean', () {
        expect(
          const ToolSchema.boolean(optional: true),
          ToolSchema.boolean(optional: bool.parse('true')),
        );
        expect(
          const ToolSchema.boolean(),
          isNot(const ToolSchema.boolean(optional: true)),
        );
      });

      test('enumString', () {
        expect(
          const ToolSchema.enumString(['c', 'f']),
          ToolSchema.enumString(List.of(['c', 'f'])),
        );
        expect(
          const ToolSchema.enumString(['c', 'f']),
          isNot(const ToolSchema.enumString(['c'])),
        );
      });

      test('list', () {
        expect(
          const ToolSchema.list(ToolSchema.object({'a': ToolSchema.string()})),
          ToolSchema.list(
            ToolSchema.object(Map.of({'a': const ToolSchema.string()})),
          ),
        );
        expect(
          const ToolSchema.list(ToolSchema.string()),
          isNot(const ToolSchema.list(ToolSchema.integer())),
        );
      });

      test('across members', () {
        expect(const ToolSchema.integer(), isNot(const ToolSchema.number()));
      });
    });
  });
}
