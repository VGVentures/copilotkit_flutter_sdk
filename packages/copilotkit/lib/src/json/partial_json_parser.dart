import 'dart:convert';

/// Parses a streamed, possibly incomplete JSON object into a best-effort map.
///
/// Open strings, arrays and objects are closed; a key without a value is
/// dropped; a number keeps its valid digits; a literal cut mid-way (`tr`,
/// `nu`) is completed. Complete JSON gives the same result as [jsonDecode].
/// Never throws: input that isn't a JSON object prefix gives an empty map.
class const PartialJsonParser() {
  /// Creates a parser.
  this;

  /// Parses [input] into the map it describes so far.
  Map<String, Object?> parse(String input) {
    try {
      final decoded = jsonDecode(input);
      return decoded is Map<String, Object?> ? decoded : {};
    } on FormatException {
      // Incomplete or invalid; fall through to the tolerant parser.
    }
    try {
      final cursor = _Cursor(input).._skipWhitespace();
      if (cursor._atEnd || cursor._peek != '{') return {};
      return cursor._object();
    } on _Garbage {
      return {};
    }
  }
}

/// Reads one input from left to right; one cursor per [PartialJsonParser.parse]
/// call.
class _Cursor(final String _input) {
  static final _numberPattern = RegExp(
    r'-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?',
  );

  /// A fraction or exponent cut off at the end of the input, e.g. `1.`.
  static final _danglingNumberTail = RegExp(r'(?:\.|[eE][+-]?)$');

  int _index = 0;

  bool get _atEnd => _index >= _input.length;

  String get _peek => _input[_index];

  void _skipWhitespace() {
    while (!_atEnd && ' \t\n\r'.contains(_peek)) {
      _index++;
    }
  }

  /// Parses the next value. Returns `null` when the value is cut off before
  /// any usable content, e.g. `-` or `"\u00`.
  _Parsed? _value() {
    _skipWhitespace();
    if (_atEnd) return null;
    return switch (_peek) {
      '{' => (value: _object()),
      '[' => (value: _array()),
      '"' => (value: _string()),
      't' => (value: _literal('true', true)),
      'f' => (value: _literal('false', false)),
      'n' => (value: _literal('null', null)),
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
      final key = _key();
      if (key == null) return result;
      final parsed = _value();
      if (parsed == null) return result;
      result[key] = parsed.value;
      if (!_separator('}')) return result;
    }
  }

  /// Consumes an object key and its `:`. Returns `null` when the input ends
  /// before the `:`.
  String? _key() {
    if (_peek != '"') throw _Garbage();
    final key = _string();
    _skipWhitespace();
    if (_atEnd) return null;
    if (_peek != ':') throw _Garbage();
    _index++;
    return key;
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
      final parsed = _value();
      if (parsed == null) return result;
      result.add(parsed.value);
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
      buffer.write(char == r'\' ? _escape() : char);
    }
    return buffer.toString();
  }

  /// Decodes the escape after a `\`. Returns `''` when the input ends inside
  /// it.
  String _escape() {
    if (_atEnd) return '';
    final escape = _input[_index++];
    return switch (escape) {
      '"' || r'\' || '/' => escape,
      'b' => '\b',
      'f' => '\f',
      'n' => '\n',
      'r' => '\r',
      't' => '\t',
      'u' => _unicodeEscape(),
      _ => throw _Garbage(),
    };
  }

  /// Decodes the four hex digits of a `\u` escape. Returns `''` when the
  /// input ends before all four.
  String _unicodeEscape() {
    if (_index + 4 > _input.length) {
      _index = _input.length;
      return '';
    }
    final code = int.tryParse(_input.substring(_index, _index + 4), radix: 16);
    if (code == null) throw _Garbage();
    _index += 4;
    return String.fromCharCode(code);
  }

  Object? _literal(String word, Object? value) {
    for (var i = 0; i < word.length && !_atEnd; i++, _index++) {
      if (_peek != word[i]) throw _Garbage();
    }
    return value;
  }

  _Parsed? _number() {
    final match = _numberPattern.matchAsPrefix(_input, _index);
    if (match == null) {
      if (_peek == '-' && _index + 1 == _input.length) {
        _index++;
        return null;
      }
      throw _Garbage();
    }
    _index = match.end;
    // Skip a dangling fraction or exponent cut off at the end, e.g. `1.`.
    final tail = _danglingNumberTail.matchAsPrefix(_input, _index);
    if (tail != null) _index = tail.end;
    return (value: num.parse(match[0]!));
  }
}

/// A value the parser could read; `null` in its place means it was cut off.
typedef _Parsed = ({Object? value});

class _Garbage implements Exception;
