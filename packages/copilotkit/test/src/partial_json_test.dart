import 'dart:convert';

import 'package:copilotkit/src/partial_json.dart';
import 'package:test/test.dart';

const _args =
    '{"city": "San José", "days": 3, "units": {"temp": "C", "wind": null}, '
    r'"alerts": [true, false, -1.5e2], "note": "say \"hi\"\n\u00e9"}';

void main() {
  group('parsePartialJson', () {
    test('complete JSON matches jsonDecode', () {
      expect(parsePartialJson(_args), jsonDecode(_args));
    });

    test('every prefix parses without throwing', () {
      for (var i = 0; i <= _args.length; i++) {
        expect(
          () => parsePartialJson(_args.substring(0, i)),
          returnsNormally,
          reason: 'prefix of length $i',
        );
      }
    });

    test('every prefix yields a map that only grows towards the result', () {
      final complete = jsonDecode(_args) as Map<String, Object?>;
      for (var i = 0; i <= _args.length; i++) {
        final partial = parsePartialJson(_args.substring(0, i));
        for (final key in partial.keys) {
          expect(complete, contains(key), reason: 'prefix of length $i');
        }
      }
    });

    test('empty, whitespace and lone brace give an empty map', () {
      expect(parsePartialJson(''), isEmpty);
      expect(parsePartialJson('  '), isEmpty);
      expect(parsePartialJson('{'), isEmpty);
      expect(parsePartialJson('{ '), isEmpty);
    });

    test('keeps a string cut mid-value', () {
      expect(parsePartialJson('{"city": "San J'), {'city': 'San J'});
    });

    test('drops a key cut before its value', () {
      expect(parsePartialJson('{"a": 1, "ci'), {'a': 1});
      expect(parsePartialJson('{"a": 1, "city"'), {'a': 1});
      expect(parsePartialJson('{"a": 1, "city":'), {'a': 1});
      expect(parsePartialJson('{"a": 1, "city": '), {'a': 1});
    });

    test('keeps the digits of a number cut mid-way', () {
      expect(parsePartialJson('{"n": 12'), {'n': 12});
      expect(parsePartialJson('{"n": -1.5'), {'n': -1.5});
      expect(parsePartialJson('{"n": 1.'), {'n': 1});
      expect(parsePartialJson('{"n": 1e'), {'n': 1});
      expect(parsePartialJson('{"n": 2E+'), {'n': 2});
      expect(parsePartialJson('{"n": -'), isEmpty);
    });

    test('completes a literal cut mid-way', () {
      expect(parsePartialJson('{"a": t'), {'a': true});
      expect(parsePartialJson('{"a": fal'), {'a': false});
      expect(parsePartialJson('{"a": nu'), {'a': null});
    });

    test('closes nested objects and arrays', () {
      expect(parsePartialJson('{"u": {"t": "C", "w": [1, {"x": "y'), {
        'u': {
          't': 'C',
          'w': [
            1,
            {'x': 'y'},
          ],
        },
      });
      expect(parsePartialJson('{"a": ['), {'a': <Object?>[]});
      expect(parsePartialJson('{"a": {}, "b": [], "c'), {
        'a': <String, Object?>{},
        'b': <Object?>[],
      });
      expect(parsePartialJson('{"a": [1,'), {
        'a': [1],
      });
    });

    test('handles escaped quotes and a cut escape', () {
      expect(parsePartialJson(r'{"q": "say \"hi\"'), {'q': 'say "hi"'});
      expect(parsePartialJson(r'{"q": "a\'), {'q': 'a'});
      expect(parsePartialJson(r'{"q": "a\u00'), {'q': 'a'});
      expect(parsePartialJson(r'{"q": "\b\f\n\r\t\/\\'), {
        'q': '\b\f\n\r\t/\\',
      });
    });

    test('garbage gives an empty map', () {
      expect(parsePartialJson('not json'), isEmpty);
      expect(parsePartialJson('{"a": 1 "b": 2}'), isEmpty);
      expect(parsePartialJson('{"a": @}'), isEmpty);
      expect(parsePartialJson('{1: 2}'), isEmpty);
      expect(parsePartialJson(r'{"a": "\x"}'), isEmpty);
      expect(parsePartialJson(r'{"a": "\uZZZZ'), isEmpty);
      expect(parsePartialJson('{"a": [1 2]}'), isEmpty);
      expect(parsePartialJson('{"a": tx'), isEmpty);
    });

    test('a complete non-object gives an empty map', () {
      expect(parsePartialJson('[1, 2]'), isEmpty);
      expect(parsePartialJson('"text"'), isEmpty);
    });

    test('ignores anything after the closing brace', () {
      expect(parsePartialJson('{"a": 1} trailing'), {'a': 1});
    });
  });
}
