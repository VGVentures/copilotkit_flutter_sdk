import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/threads/widgets/threads_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Lists the conversations of an agent. It pops with the id of the thread the
/// user picks, or of a new one.
class const ThreadsPage({
  /// The client whose runtime keeps the threads.
  required final CopilotKitClient client,

  /// The agent whose threads are listed.
  required final String agentId,

  /// The thread the chat is on now, marked in the list.
  required final String? currentThreadId,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        ThreadsBloc(client: client, agentId: agentId)
          ..add(const ThreadsRequested()),
    child: ThreadsView(currentThreadId: currentThreadId),
  );
}
