import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/json/partial_json_parser.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';

const _args =
    '{"city": "San José", "days": 3, "units": {"temp": "C", "wind": null}, '
    r'"alerts": [true, false, -1.5e2], "note": "say \"hi\"\n\u00e9"}';

void main() {
  group(PartialJsonParser, () {
    const parser = PartialJsonParser();

    test('complete JSON matches jsonDecode', () {
      expect(parser.parse(_args), jsonDecode(_args));
    });

    test('every prefix parses without throwing', () {
      for (var i = 0; i <= _args.length; i++) {
        expect(
          () => parser.parse(_args.substring(0, i)),
          returnsNormally,
          reason: 'prefix of length $i',
        );
      }
    });

    test('every prefix yields a map that only grows towards the result', () {
      final complete = jsonDecode(_args) as Map<String, Object?>;
      for (var i = 0; i <= _args.length; i++) {
        final partial = parser.parse(_args.substring(0, i));
        for (final key in partial.keys) {
          expect(complete, contains(key), reason: 'prefix of length $i');
        }
      }
    });

    test('empty, whitespace and lone brace give an empty map', () {
      expect(parser.parse(''), isEmpty);
      expect(parser.parse('  '), isEmpty);
      expect(parser.parse('{'), isEmpty);
      expect(parser.parse('{ '), isEmpty);
    });

    test('keeps a string cut mid-value', () {
      expect(parser.parse('{"city": "San J'), {'city': 'San J'});
    });

    test('drops a key cut before its value', () {
      expect(parser.parse('{"a": 1, "ci'), {'a': 1});
      expect(parser.parse('{"a": 1, "city"'), {'a': 1});
      expect(parser.parse('{"a": 1, "city":'), {'a': 1});
      expect(parser.parse('{"a": 1, "city": '), {'a': 1});
    });

    test('keeps the digits of a number cut mid-way', () {
      expect(parser.parse('{"n": 12'), {'n': 12});
      expect(parser.parse('{"n": -1.5'), {'n': -1.5});
      expect(parser.parse('{"n": 1.'), {'n': 1});
      expect(parser.parse('{"n": 1e'), {'n': 1});
      expect(parser.parse('{"n": 2E+'), {'n': 2});
      expect(parser.parse('{"n": -'), isEmpty);
    });

    test('completes a literal cut mid-way', () {
      expect(parser.parse('{"a": t'), {'a': true});
      expect(parser.parse('{"a": fal'), {'a': false});
      expect(parser.parse('{"a": nu'), {'a': null});
    });

    test('closes nested objects and arrays', () {
      expect(parser.parse('{"u": {"t": "C", "w": [1, {"x": "y'), {
        'u': {
          't': 'C',
          'w': [
            1,
            {'x': 'y'},
          ],
        },
      });
      expect(parser.parse('{"a": ['), {'a': <Object?>[]});
      expect(parser.parse('{"a": {}, "b": [], "c'), {
        'a': <String, Object?>{},
        'b': <Object?>[],
      });
      expect(parser.parse('{"a": [1,'), {
        'a': [1],
      });
    });

    test('handles escaped quotes and a cut escape', () {
      expect(parser.parse(r'{"q": "say \"hi\"'), {'q': 'say "hi"'});
      expect(parser.parse(r'{"q": "a\'), {'q': 'a'});
      expect(parser.parse(r'{"q": "a\u00'), {'q': 'a'});
      expect(parser.parse(r'{"q": "\b\f\n\r\t\/\\'), {'q': '\b\f\n\r\t/\\'});
    });

    test('garbage gives an empty map', () {
      expect(parser.parse('not json'), isEmpty);
      expect(parser.parse('{"a": 1 "b": 2}'), isEmpty);
      expect(parser.parse('{"a": @}'), isEmpty);
      expect(parser.parse('{1: 2}'), isEmpty);
      expect(parser.parse(r'{"a": "\x"}'), isEmpty);
      expect(parser.parse(r'{"a": "\uZZZZ'), isEmpty);
      expect(parser.parse('{"a": [1 2]}'), isEmpty);
      expect(parser.parse('{"a": tx'), isEmpty);
    });

    test('a complete non-object gives an empty map', () {
      expect(parser.parse('[1, 2]'), isEmpty);
      expect(parser.parse('"text"'), isEmpty);
    });

    test('ignores anything after the closing brace', () {
      expect(parser.parse('{"a": 1} trailing'), {'a': 1});
    });

    test('every prefix of recorded tool args parses', () {
      final delta = loadFixture('frontend_tool_call').events
          .whereType<ToolCallArgsEvent>()
          .map((event) => event.delta)
          .join();

      for (var i = 0; i < delta.length; i++) {
        expect(
          () => parser.parse(delta.substring(0, i)),
          returnsNormally,
          reason: 'prefix of length $i',
        );
      }
      expect(parser.parse(delta), {'city': 'Lima'});
    });
  });
}
