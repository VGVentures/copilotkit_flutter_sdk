import 'package:example/app/app.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final threadId = await ThreadIdStore(
    preferences: await SharedPreferences.getInstance(),
  )();
  runApp(
    App(
      runtimeUrl: const String.fromEnvironment('RUNTIME_URL'),
      threadId: threadId,
    ),
  );
}
