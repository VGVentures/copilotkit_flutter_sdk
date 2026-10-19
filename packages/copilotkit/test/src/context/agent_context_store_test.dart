import 'package:copilotkit/src/context/context.dart';
import 'package:test/test.dart';

void main() {
  group(AgentContextStore, () {
    final user = AgentContextEntry(
      id: 'user',
      description: 'Current user',
      value: 'Ada',
    );
    final city = AgentContextEntry(
      id: 'city',
      description: 'Current city',
      value: 'Lima',
    );

    test('starts empty', () {
      expect(AgentContextStore().entries, isEmpty);
    });

    test('keeps entries in the order they were added', () {
      final store = AgentContextStore()
        ..add(user)
        ..add(city);

      expect(store.entries, [user, city]);
    });

    test('updates the value of an entry, keeping its place', () {
      final store = AgentContextStore()
        ..add(user)
        ..add(city)
        ..update('user', 'Grace');

      expect(store.entries, [user.copyWith(value: 'Grace'), city]);
    });

    test('ignores updates and removals of unknown entries', () {
      final store = AgentContextStore()
        ..add(user)
        ..update('missing', 'x')
        ..remove('missing');

      expect(store.entries, [user]);
    });

    test('removes an entry', () {
      final store = AgentContextStore()
        ..add(user)
        ..add(city)
        ..remove('user');

      expect(store.entries, [city]);
    });

    test('exposes a read-only copy', () {
      final store = AgentContextStore()..add(user);

      expect(() => store.entries.add(city), throwsUnsupportedError);
    });
  });
}
