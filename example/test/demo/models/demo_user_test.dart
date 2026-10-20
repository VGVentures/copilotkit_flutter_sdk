import 'package:example/demo/models/demo_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(DemoUser, () {
    test('encodes to JSON', () {
      expect(DemoUser.ada.toJson(), {'name': 'Ada', 'homeCity': 'Lima'});
    });

    test('supports value equality', () {
      // A separate instance, so equality isn't identity.
      expect(
        DemoUser.ada,
        DemoUser(name: ['A', 'da'].join(), homeCity: 'Lima'),
      );
      expect(
        DemoUser.ada,
        isNot(const DemoUser(name: 'Ada', homeCity: 'Quito')),
      );
    });
  });
}
