import 'dart:convert';

/// Parses a streamed, possibly incomplete JSON object into a best-effort map.
///
/// Open strings, arrays and objects are closed; a key without a value is
/// dropped; a number keeps its valid digits; a literal cut mid-way (`tr`,
/// `nu`) is completed. Complete JSON gives the same result as [jsonDecode].
/// Never throws: input that isn't a JSON object prefix gives an empty map.
Map<String, Object?> parsePartialJson(String input) {
  try {
    final decoded = jsonDecode(input);
    return decoded is Map<String, Object?> ? decoded : {};
  } on FormatException {
    // Incomplete or invalid; fall through to the tolerant parser.
  }
  try {
    final parser = _PartialJsonParser(input).._skipWhitespace();
    if (parser._atEnd || parser._peek != '{') return {};
    return parser._object();
  } on _Garbage {
    return {};
  }
}

class _Garbage implements Exception;

final _numberPattern = RegExp(r'-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?');

/// A fraction or exponent cut off at the end of the input, e.g. `1.`.
final _danglingNumberTail = RegExp(r'(?:\.|[eE][+-]?)$');

/// Marks a value cut off before any usable content, e.g. `-` or `"\u00`.
const Object _incomplete = Object();

class _PartialJsonParser(final String _input) {
  int _index = 0;

  bool get _atEnd => _index >= _input.length;

  String get _peek => _input[_index];

  void _skipWhitespace() {
    while (!_atEnd && ' \t\n\r'.contains(_peek)) {
      _index++;
    }
  }

  Object? _value() {
    _skipWhitespace();
    if (_atEnd) return _incomplete;
    return switch (_peek) {
      '{' => _object(),
      '[' => _array(),
      '"' => _string(),
      't' => _literal('true', true),
      'f' => _literal('false', false),
      'n' => _literal('null', null),
      _ => _number(),
    };
  }

  Map<String, Object?> _object() {
    _index++; // {
    final result = <String, Object?>{};
    while (true) {
      _skipWhitespace();
      if (_atEnd) return result;
      if (_peek == '}') {
        _index++;
        return result;
      }
      if (_peek != '"') throw _Garbage();
      final key = _string();
      _skipWhitespace();
      if (_atEnd) return result;
      if (_peek != ':') throw _Garbage();
      _index++;
      final value = _value();
      if (identical(value, _incomplete)) return result;
      result[key] = value;
      if (!_separator('}')) return result;
    }
  }

  List<Object?> _array() {
    _index++; // [
    final result = <Object?>[];
    while (true) {
      _skipWhitespace();
      if (_atEnd) return result;
      if (_peek == ']') {
        _index++;
        return result;
      }
      final value = _value();
      if (identical(value, _incomplete)) return result;
      result.add(value);
      if (!_separator(']')) return result;
    }
  }

  /// Consumes a `,` or the [closing] bracket after a value. Returns `false`
  /// when the container is finished (closed or cut off).
  bool _separator(String closing) {
    _skipWhitespace();
    if (_atEnd) return false;
    if (_peek == ',') {
      _index++;
      return true;
    }
    if (_peek == closing) {
      _index++;
      return false;
    }
    throw _Garbage();
  }

  String _string() {
    _index++; // "
    final buffer = StringBuffer();
    while (!_atEnd) {
      final char = _input[_index++];
      if (char == '"') return buffer.toString();
      if (char != r'\') {
        buffer.write(char);
        continue;
      }
      if (_atEnd) break;
      final escape = _input[_index++];
      switch (escape) {
        case '"' || r'\' || '/':
          buffer.write(escape);
        case 'b':
          buffer.write('\b');
        case 'f':
          buffer.write('\f');
        case 'n':
          buffer.write('\n');
        case 'r':
          buffer.write('\r');
        case 't':
          buffer.write('\t');
        case 'u':
          if (_index + 4 > _input.length) {
            _index = _input.length;
            break;
          }
          final code = int.tryParse(
            _input.substring(_index, _index + 4),
            radix: 16,
          );
          if (code == null) throw _Garbage();
          buffer.writeCharCode(code);
          _index += 4;
        default:
          throw _Garbage();
      }
    }
    return buffer.toString();
  }

  Object? _literal(String word, Object? value) {
    for (var i = 0; i < word.length && !_atEnd; i++, _index++) {
      if (_peek != word[i]) throw _Garbage();
    }
    return value;
  }

  Object _number() {
    final match = _numberPattern.matchAsPrefix(_input, _index);
    if (match == null) {
      if (_peek == '-' && _index + 1 == _input.length) {
        _index++;
        return _incomplete;
      }
      throw _Garbage();
    }
    _index = match.end;
    // Skip a dangling fraction or exponent cut off at the end, e.g. `1.`.
    final tail = _danglingNumberTail.matchAsPrefix(_input, _index);
    if (tail != null) _index = tail.end;
    return num.parse(match[0]!);
  }
}
