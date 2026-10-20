import 'dart:convert';

import 'package:json_utils/json_utils.dart';
import 'package:test/test.dart';

const _args =
    '{"city": "San José", "days": 3, "units": {"temp": "C", "wind": null}, '
    r'"alerts": [true, false, -1.5e2], "note": "say \"hi\"\n\u00e9"}';

void main() {
  group(PartialJsonParser, () {
    const parser = PartialJsonParser();

    /// The fields [parser] reads from [input].
    Map<String, Object?> parse(String input) => parser.parse(input);

    test('complete JSON matches jsonDecode', () {
      expect(parse(_args), jsonDecode(_args));
    });

    test('every prefix parses without throwing', () {
      for (var i = 0; i <= _args.length; i++) {
        expect(
          () => parse(_args.substring(0, i)),
          returnsNormally,
          reason: 'prefix of length $i',
        );
      }
    });

    test('every prefix yields a map that only grows towards the result', () {
      final complete = jsonDecode(_args) as Map<String, Object?>;
      for (var i = 0; i <= _args.length; i++) {
        final partial = parse(_args.substring(0, i));
        for (final key in partial.keys) {
          expect(complete, contains(key), reason: 'prefix of length $i');
        }
      }
    });

    test('empty, whitespace and lone brace give an empty map', () {
      expect(parse(''), isEmpty);
      expect(parse('  '), isEmpty);
      expect(parse('{'), isEmpty);
      expect(parse('{ '), isEmpty);
    });

    test('keeps a string cut mid-value', () {
      expect(parse('{"city": "San J'), {'city': 'San J'});
    });

    test('drops a key cut before its value', () {
      expect(parse('{"a": 1, "ci'), {'a': 1});
      expect(parse('{"a": 1, "city"'), {'a': 1});
      expect(parse('{"a": 1, "city":'), {'a': 1});
      expect(parse('{"a": 1, "city": '), {'a': 1});
    });

    test('keeps the digits of a number cut mid-way', () {
      expect(parse('{"n": 12'), {'n': 12});
      expect(parse('{"n": -1.5'), {'n': -1.5});
      expect(parse('{"n": 1.'), {'n': 1});
      expect(parse('{"n": 1e'), {'n': 1});
      expect(parse('{"n": 2E+'), {'n': 2});
      expect(parse('{"n": -'), isEmpty);
    });

    test('completes a literal cut mid-way', () {
      expect(parse('{"a": t'), {'a': true});
      expect(parse('{"a": fal'), {'a': false});
      expect(parse('{"a": nu'), {'a': null});
    });

    test('closes nested objects and arrays', () {
      expect(parse('{"u": {"t": "C", "w": [1, {"x": "y'), {
        'u': {
          't': 'C',
          'w': [
            1,
            {'x': 'y'},
          ],
        },
      });
      expect(parse('{"a": ['), {'a': <Object?>[]});
      expect(parse('{"a": {}, "b": [], "c'), {
        'a': <String, Object?>{},
        'b': <Object?>[],
      });
      expect(parse('{"a": [1,'), {
        'a': [1],
      });
    });

    test('handles escaped quotes and a cut escape', () {
      expect(parse(r'{"q": "say \"hi\"'), {'q': 'say "hi"'});
      expect(parse(r'{"q": "a\'), {'q': 'a'});
      expect(parse(r'{"q": "a\u00'), {'q': 'a'});
      expect(parse(r'{"q": "\b\f\n\r\t\/\\'), {'q': '\b\f\n\r\t/\\'});
    });

    test('garbage gives an empty map', () {
      expect(parse('not json'), isEmpty);
      expect(parse('{"a": 1 "b": 2}'), isEmpty);
      expect(parse('{"a": @}'), isEmpty);
      expect(parse('{1: 2}'), isEmpty);
      expect(parse(r'{"a": "\x"}'), isEmpty);
      expect(parse(r'{"a": "\uZZZZ'), isEmpty);
      expect(parse('{"a": [1 2]}'), isEmpty);
      expect(parse('{"a": tx'), isEmpty);
    });

    test('a complete non-object gives an empty map', () {
      expect(parse('[1, 2]'), isEmpty);
      expect(parse('"text"'), isEmpty);
    });

    test('ignores anything after the closing brace', () {
      expect(parse('{"a": 1} trailing'), {'a': 1});
    });
  });
}
