import 'package:phoenix_channels_client/phoenix_channels_client.dart';
import 'package:test/test.dart';

void main() {
  group(PhoenixReplyException, () {
    const exception = PhoenixReplyException(
      status: 'error',
      response: {'reason': 'denied'},
    );

    test('compare by value', () {
      expect(
        exception,
        const PhoenixReplyException(
          status: 'error',
          response: {'reason': 'denied'},
        ),
      );
    });

    test('say the status and the response', () {
      expect(
        exception.toString(),
        'PhoenixReplyException(error): {reason: denied}',
      );
    });
  });
}
