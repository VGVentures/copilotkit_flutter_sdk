import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Keeps the id of the conversation thread across launches.
///
/// The SDK doesn't store anything: it opens an agent on the thread id the app
/// gives it. The app keeps that id, so a conversation stays on the same
/// thread after a restart, and a runtime with Intelligence keeps its threads
/// together instead of starting a new one on every launch.
class const ThreadIdStore({
  /// Where the id is kept.
  required final SharedPreferences _preferences,

  /// Generates the id of a new thread.
  final Uuid _uuid = const Uuid(),
}) {
  /// Creates a store that keeps the id in [_preferences].
  this;

  /// The preferences key the thread id is kept under.
  static const key = 'copilotkit.threadId';

  /// Returns the saved thread id. On the first launch there is none, so it
  /// creates one, saves it and returns it.
  Future<String> call() async {
    if (_preferences.getString(key) case final saved?) return saved;
    final created = _uuid.v4();
    await _preferences.setString(key, created);
    return created;
  }
}
