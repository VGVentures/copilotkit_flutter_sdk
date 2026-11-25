import 'package:example/app/app.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = ThreadIdStore(
    preferences: await SharedPreferences.getInstance(),
  );
  final threadId = await store();
  runApp(
    App(
      runtimeUrl: const String.fromEnvironment('RUNTIME_URL'),
      threadId: threadId,
      threadIdStore: store,
      // Set with --dart-define=LEARNING=true; false otherwise.
      // ignore: avoid_redundant_argument_values
      learning: const bool.fromEnvironment('LEARNING'),
    ),
  );
}
