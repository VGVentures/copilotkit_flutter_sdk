import 'package:example/app/thread_id_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  group(ThreadIdStore, () {
    Future<SharedPreferences> preferencesWith(Map<String, Object> values) {
      SharedPreferences.setMockInitialValues(values);
      return SharedPreferences.getInstance();
    }

    test('returns the thread id it saved', () async {
      final preferences = await preferencesWith({
        ThreadIdStore.key: 'thread-1',
      });

      expect(await ThreadIdStore(preferences: preferences)(), 'thread-1');
    });

    test('creates and saves a thread id on the first launch', () async {
      final preferences = await preferencesWith({});

      final created = await ThreadIdStore(preferences: preferences)();

      expect(Uuid.isValidUUID(fromString: created), isTrue);
      expect(preferences.getString(ThreadIdStore.key), created);
    });

    test('returns the same thread id on the next launch', () async {
      final preferences = await preferencesWith({});

      final first = await ThreadIdStore(preferences: preferences)();
      final second = await ThreadIdStore(preferences: preferences)();

      expect(second, first);
    });
  });
}
