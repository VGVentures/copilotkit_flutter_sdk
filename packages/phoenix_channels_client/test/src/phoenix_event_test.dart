import 'package:phoenix_channels_client/phoenix_channels_client.dart';
import 'package:test/test.dart';

void main() {
  group(PhoenixEvent, () {
    test('compare by value', () {
      expect(
        const PhoenixEvent(topic: 't', event: 'e', payload: {'a': 1}),
        const PhoenixEvent(topic: 't', event: 'e', payload: {'a': 1}),
      );
      expect(
        const PhoenixEvent(topic: 't', event: 'e', payload: {'a': 1}),
        isNot(const PhoenixEvent(topic: 't', event: 'e', payload: {'a': 2})),
      );
    });
  });
}
