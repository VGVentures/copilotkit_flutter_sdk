import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../../helpers/memory_metadata_fixture.dart';

void main() {
  group(MemoryChannelCredentials, () {
    test('decodes the recorded credentials of both channels', () {
      final credentials = MemoryChannelCredentials.fromJson(
        memoryChannelBody('subscribe')! as Map<String, Object?>,
      );

      expect(credentials.joinToken, '<redacted>');
      expect(credentials.userTopic, 'user_meta:memories:<join-code>');
      expect(
        credentials.projectTopic,
        'project_meta:memories:<project-join-code>',
      );
    });

    test('accepts the project pair alone', () {
      final credentials = MemoryChannelCredentials.fromJson(const {
        'projectJoinToken': 'pt',
        'projectJoinCode': 'pc',
        'joinToken': '',
      });

      expect(credentials.userTopic, isNull);
      expect(credentials.projectTopic, 'project_meta:memories:pc');
    });

    test('rejects credentials without a complete pair', () {
      for (final json in [
        const <String, Object?>{},
        const {'joinToken': 't'},
        const {'projectJoinCode': 'c', 'joinCode': 7},
      ]) {
        expect(
          () => MemoryChannelCredentials.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });

    test('compares by value', () {
      const json = {'joinToken': 't', 'joinCode': 'c'};

      expect(
        MemoryChannelCredentials.fromJson(json),
        MemoryChannelCredentials.fromJson(json),
      );
      expect(
        MemoryChannelCredentials.fromJson(json),
        isNot(
          MemoryChannelCredentials.fromJson(const {
            'joinToken': 't',
            'joinCode': 'd',
          }),
        ),
      );
    });
  });
}
