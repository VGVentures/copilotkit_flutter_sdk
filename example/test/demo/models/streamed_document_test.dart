import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/streamed_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(StreamedDocument, () {
    test('reads the document of the shared state', () {
      final document = StreamedDocument.fromShared(
        const SharedState({'document': 'Dear Ada,'}),
      );

      expect(document.text, 'Dear Ada,');
    });

    test('is empty without a shared state', () {
      expect(StreamedDocument.fromShared(null).text, isEmpty);
    });

    test('is empty when the state has no document', () {
      final document = StreamedDocument.fromShared(
        const SharedState({'todos': <Object?>[]}),
      );

      expect(document.text, isEmpty);
    });

    test('is empty when the document is not a string', () {
      expect(
        StreamedDocument.fromShared(const SharedState({'document': 42})).text,
        isEmpty,
      );
      expect(
        StreamedDocument.fromShared(const SharedState({'document': null})).text,
        isEmpty,
      );
    });

    test('replaces the document and keeps the rest of the state', () {
      final shared = const StreamedDocument(text: 'New').toShared(
        const SharedState({
          'document': 'Old',
          'todos': [
            {'title': 'Buy milk', 'done': false},
          ],
        }),
      );

      expect(shared.toJson(), {
        'document': 'New',
        'todos': [
          {'title': 'Buy milk', 'done': false},
        ],
      });
    });

    test('shares just the document when there is no state yet', () {
      expect(const StreamedDocument(text: 'New').toShared(null).toJson(), {
        'document': 'New',
      });
    });

    test('supports value equality', () {
      // A separate instance, so equality isn't identity.
      expect(
        const StreamedDocument(text: 'Hi'),
        StreamedDocument(text: ['H', 'i'].join()),
      );
      expect(
        const StreamedDocument(text: 'Hi'),
        isNot(const StreamedDocument(text: 'Hello')),
      );
    });
  });
}
