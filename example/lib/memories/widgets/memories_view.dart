import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/memories/widgets/text_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The memories screen: a field to remember something, a search over what is
/// remembered, the results, and every memory with a button to forget it.
class const MemoriesView({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<MemoriesBloc>().state;
    return Scaffold(
      appBar: AppBar(title: const Text('Memories')),
      body: SafeArea(child: _body(context, state)),
    );
  }

  Widget _body(BuildContext context, MemoriesState state) {
    if (!state.isAvailable) {
      return const Center(
        key: Key('memories_unavailable'),
        child: Text('This runtime does not keep memories.'),
      );
    }
    final bloc = context.read<MemoriesBloc>();
    return ListView(
      children: [
        TextEntry(
          hint: 'Remember something',
          icon: Icons.add,
          tooltip: 'Remember',
          onSubmit: (text) => bloc.add(
            MemorySaved(NewMemory(content: text, kind: MemoryKind.topical)),
          ),
        ),
        TextEntry(
          hint: 'Search memories',
          icon: Icons.search,
          tooltip: 'Search',
          onSubmit: (text) => bloc.add(MemoriesRecalled(text)),
        ),
        if (state.lastOutcome?.isAbsorbed ?? false)
          const Padding(
            key: Key('memories_absorbed'),
            padding: EdgeInsets.all(16),
            child: Text('Already remembered, so it was not added again.'),
          ),
        if (state.error != null)
          Padding(
            key: const Key('memories_error'),
            padding: const EdgeInsets.all(16),
            child: Text(
              'Something went wrong. Try again.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (state.recalled.isNotEmpty) ...[
          const _Heading('Search results'),
          for (final memory in state.recalled) _MemoryTile(memory),
        ],
        const _Heading('Everything remembered'),
        if (state.isLoading && state.memories.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (state.memories.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nothing remembered yet.'),
          )
        else
          for (final memory in state.memories) _MemoryTile(memory),
      ],
    );
  }
}

class const _Heading(final String text) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class const _MemoryTile(final Memory memory) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListTile(
    key: Key('memory_${memory.id}'),
    title: Text(memory.content),
    subtitle: Text('${memory.kind.name} · ${memory.scope.name}'),
    trailing: IconButton(
      key: Key('forget_${memory.id}'),
      tooltip: 'Forget',
      icon: const Icon(Icons.delete_outline),
      onPressed: () =>
          context.read<MemoriesBloc>().add(MemoryRetired(memory.id)),
    ),
  );
}
