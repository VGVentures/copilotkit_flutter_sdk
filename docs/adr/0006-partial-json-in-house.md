# 0006. Partial JSON parsing stays in-house

**Status:** Accepted

## Context

AG-UI streams tool-call arguments as text deltas (`TOOL_CALL_ARGS`). To
render a tool widget while the arguments stream in, the reducer parses the
buffer after every delta into a best-effort map. `partial_json.dart` does
that with a small tolerant parser. Before refactoring it into a class, three
packages were evaluated as replacements.

## Decision

Keep the in-house parser. It becomes `PartialJsonParser` in
`partial_json_parser.dart` with no top-level declarations, and its tests
stay unchanged.

## Alternatives

### `llm_json_stream` 1.0.0

Push-based: the caller subscribes to one stream per property path and gets
a stream of chunks for that property. The reducer needs the opposite, a pull
from a buffer to a map, which the package offers through the root map
property's `stream`. That snapshot is wrong mid-stream. Reproduction, feeding
a 60-character payload in 6-character chunks and printing the latest root
snapshot after each chunk:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:llm_json_stream/llm_json_stream.dart';

Future<void> main() async {
  const json = '{"city":"Lima","days":3,"metric":true,"tags":["sun","wind"]}';
  final controller = StreamController<String>();
  final parser = JsonStreamParser(controller.stream);
  final root = parser.getMapProperty('');
  final snapshots = <Map<String, Object?>>[];
  root.stream.listen((map) => snapshots.add(Map.of(map)));
  for (var i = 0; i < json.length; i += 6) {
    final end = i + 6 > json.length ? json.length : i + 6;
    final chunk = json.substring(i, end);
    controller.add(chunk);
    await Future<void>.delayed(Duration.zero);
    print('chunk ${jsonEncode(chunk)} -> ${jsonEncode(snapshots.lastOrNull)}');
  }
  await controller.close();
  print('future -> ${jsonEncode(await root.future)}');
  await parser.dispose();
}
```

Output:

<!-- cspell:disable -->

```
chunk "{\"city" -> {}
chunk "\":\"Lim" -> {"city":"Lim"}
chunk "a\",\"da" -> {"city":"Lima"}
chunk "ys\":3," -> {"city":"Lima","days":null}
chunk "\"metri" -> {"city":"Lima","days":null}
chunk "c\":tru" -> {"city":"Lima","days":null,"metric":null}
chunk "e,\"tag" -> {"city":"Lima","days":null,"metric":null}
chunk "s\":[\"s" -> {"city":"Lima","days":null,"metric":null,"tags":[null]}
chunk "un\",\"w" -> {"city":"Lima","days":null,"metric":null,"tags":["s","w"]}
chunk "ind\"]}" -> {"city":"Lima","days":null,"metric":null,"tags":["sun","wind"]}
future -> {"city":"Lima","days":3,"metric":true,"tags":["sun","wind"]}
```

Numbers and booleans are `null` in every snapshot, including the last one
after the root closed; `days` is complete from the fourth chunk on and still
reads `null`. A list item is `null` until its first characters arrive. Only
`future`, which completes after the stream closes, returns the right map. A
tool widget reading `days` would render `null` for the whole stream.

The same chunks through the in-house parser:

```
chunk "{\"city" -> {}
chunk "\":\"Lim" -> {"city":"Lim"}
chunk "a\",\"da" -> {"city":"Lima"}
chunk "ys\":3," -> {"city":"Lima","days":3}
chunk "\"metri" -> {"city":"Lima","days":3}
chunk "c\":tru" -> {"city":"Lima","days":3,"metric":true}
chunk "e,\"tag" -> {"city":"Lima","days":3,"metric":true}
chunk "s\":[\"s" -> {"city":"Lima","days":3,"metric":true,"tags":["s"]}
chunk "un\",\"w" -> {"city":"Lima","days":3,"metric":true,"tags":["sun","w"]}
chunk "ind\"]}" -> {"city":"Lima","days":3,"metric":true,"tags":["sun","wind"]}
```

<!-- cspell:enable -->

### `jsonrepair_dart`

A port of the JavaScript `jsonrepair`. It repairs a string rather than
parsing it, so the result still goes through `jsonDecode`, and it has almost
no users or activity on pub.dev. Not worth a dependency for the same amount
of code we already own.

### Flutter-only packages

The remaining candidates depend on Flutter and can't go in the pure Dart
core.

## Consequences

- The parser's edge cases (dangling number tails, cut literals, open
  strings) stay our responsibility and stay covered by
  `partial_json_parser_test.dart`.
- The refactor in Task 18 is mechanical: static regexes, a static `parse`
  entry point and a typed result instead of the `_incomplete` sentinel.
