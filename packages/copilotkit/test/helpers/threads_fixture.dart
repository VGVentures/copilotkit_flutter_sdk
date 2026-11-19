import 'fixtures.dart';

/// The recorded exchange of [step] in `threads_rest.jsonl`.
Map<String, Object?> threadsExchange(String step) =>
    loadFixture('threads_rest').rawEvents
        .firstWhere((row) => row['step'] == step);

/// The recorded response body of [step] in `threads_rest.jsonl`.
Object? threadsBody(String step) => threadsExchange(step)['body'];
