import 'package:copilotkit/src/json/json.dart';
import 'package:test/test.dart';

/// A model decoded from a JSON object, for these tests.
class const _City(final String name) {
  factory fromJson(Map<String, Object?> json) => _City(json['name']! as String);
}

void main() {
  group(JsonObject, () {
    const lima = JsonObject({'name': 'Lima'});

    test('defaults to no fields', () {
      expect(const JsonObject().toJson(), isEmpty);
    });

    test('fromJson wraps a JSON object', () {
      expect(JsonObject.fromJson(const {'name': 'Lima'}), lima);
    });

    test('fromJson rejects other JSON values', () {
      expect(() => JsonObject.fromJson('Lima'), throwsFormatException);
      expect(() => JsonObject.fromJson(null), throwsFormatException);
    });

    test('decode decodes the fields', () {
      expect(lima.decode(_City.fromJson).name, 'Lima');
    });

    test('decode throws what the decoder throws', () {
      expect(
        () => const JsonObject().decode(_City.fromJson),
        throwsA(isA<TypeError>()),
      );
    });

    test('tryDecode returns null when the decoder throws', () {
      expect(lima.tryDecode(_City.fromJson)?.name, 'Lima');
      expect(const JsonObject().tryDecode(_City.fromJson), isNull);
    });

    test('encodes as its fields, read-only', () {
      final json = JsonObject(Map.of({'name': 'Lima'})).toJson();

      expect(json, {'name': 'Lima'});
      expect(() => json['name'] = 'Quito', throwsUnsupportedError);
    });

    test('supports value equality', () {
      // A separate instance, so equality isn't identity.
      expect(lima, JsonObject(Map.of({'name': 'Lima'})));
      expect(lima, isNot(const JsonObject({'name': 'Quito'})));
    });
  });
}
