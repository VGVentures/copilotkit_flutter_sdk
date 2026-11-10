import 'dart:io';

/// The body in `test/fixtures/memories/<name>.json`.
///
/// These are synthetic: written from the `@copilotkit/core` and
/// `@copilotkit/runtime` 1.79.1 bundles, not recorded from a runtime.
String memoryFixture(String name) =>
    File('test/fixtures/memories/$name.json').readAsStringSync();
