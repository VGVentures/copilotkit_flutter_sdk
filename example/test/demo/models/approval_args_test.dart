import 'package:example/demo/models/approval_args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_annotation/json_annotation.dart';

void main() {
  group(ApprovalArgs, () {
    test('decodes the action', () {
      expect(
        ApprovalArgs.fromJson({'action': 'Delete 3 files'}).action,
        'Delete 3 files',
      );
    });

    test('allows a missing action', () {
      expect(ApprovalArgs.fromJson({}).action, isNull);
    });

    test('rejects an action that is not a string', () {
      expect(
        () => ApprovalArgs.fromJson({'action': 42}),
        throwsA(isA<CheckedFromJsonException>()),
      );
    });

    test('encodes to JSON', () {
      expect(const ApprovalArgs(action: 'Delete').toJson(), {
        'action': 'Delete',
      });
      expect(const ApprovalArgs().toJson(), isEmpty);
    });
  });
}
