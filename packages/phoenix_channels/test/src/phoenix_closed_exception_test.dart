import 'package:phoenix_channels/phoenix_channels.dart';
import 'package:test/test.dart';

void main() {
  group(PhoenixClosedException, () {
    test('compare by value', () {
      expect(
        const PhoenixClosedException(code: 1006, reason: 'gone'),
        const PhoenixClosedException(code: 1006, reason: 'gone'),
      );
      expect(
        const PhoenixClosedException(code: 1006),
        isNot(const PhoenixClosedException(code: 1000)),
      );
    });

    test('say the code and the reason', () {
      expect(
        const PhoenixClosedException(code: 1006, reason: 'gone').toString(),
        'PhoenixClosedException(code: 1006, reason: gone)',
      );
    });
  });
}
