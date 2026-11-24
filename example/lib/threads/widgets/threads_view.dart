import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

/// The conversations list: a row per thread, with archive and delete when
/// the runtime allows them, and a button for a new conversation.
class const ThreadsView({
  /// The thread the chat is on now, marked in the list.
  required final String? currentThreadId,

  /// Generates the id of a new conversation.
  final Uuid _uuid = const Uuid(),
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<ThreadsBloc>().state;
    return BlocListener<ThreadsBloc, ThreadsState>(
      // A failed change while the list is showing: the bloc puts a deleted
      // row back, so say why it came back.
      listenWhen: (previous, current) =>
          current.error != null &&
          current.error != previous.error &&
          current.threads.isNotEmpty,
      listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not change that conversation. Try again.'),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Conversations'),
          actions: [
            IconButton(
              key: const Key('new_thread'),
              tooltip: 'New conversation',
              icon: const Icon(Icons.add),
              onPressed: () => Navigator.of(context).pop(_uuid.v4()),
            ),
          ],
        ),
        body: SafeArea(child: _body(context, state)),
      ),
    );
  }

  Widget _body(BuildContext context, ThreadsState state) {
    if (state.isLoading && state.threads.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.isAvailable) {
      return const Center(
        key: Key('threads_unavailable'),
        child: Text('This runtime does not keep conversations.'),
      );
    }
    if (state.error != null && state.threads.isEmpty) {
      return Center(
        key: const Key('threads_error'),
        child: TextButton(
          onPressed: () =>
              context.read<ThreadsBloc>().add(const ThreadsRequested()),
          child: const Text('Could not load. Try again.'),
        ),
      );
    }
    if (state.threads.isEmpty) {
      return const Center(child: Text('No conversations yet.'));
    }
    return ListView(
      children: [
        for (final thread in state.threads)
          ListTile(
            key: Key('thread_${thread.id}'),
            selected: thread.id == currentThreadId,
            title: Text(thread.name ?? 'New conversation'),
            subtitle: Text(thread.updatedAt.toLocal().toString()),
            onTap: () => Navigator.of(context).pop(thread.id),
            // The chat is on the current thread: deleting or archiving it
            // would leave the chat and the saved id on a thread that is gone.
            trailing: state.canMutate && thread.id != currentThreadId
                ? PopupMenuButton<VoidCallback>(
                    key: Key('thread_menu_${thread.id}'),
                    onSelected: (action) => action(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: () => context.read<ThreadsBloc>().add(
                          ThreadArchived(thread.id),
                        ),
                        child: const Text('Archive'),
                      ),
                      PopupMenuItem(
                        value: () => context.read<ThreadsBloc>().add(
                          ThreadDeleted(thread.id),
                        ),
                        child: const Text('Delete'),
                      ),
                    ],
                  )
                : null,
          ),
      ],
    );
  }
}
