import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/memories/widgets/text_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The memories screen: a field to remember something, a search over what is
/// remembered, the results, and every memory with a button to forget it.
class const MemoriesView({super.key}) extends StatefulWidget {
  @override
  State<MemoriesView> createState() => _MemoriesViewState();
}

class _MemoriesViewState extends State<MemoriesView> {
  final _remember = TextEditingController();
  final _search = TextEditingController();

  /// The last search submitted, or `null` before one: the bloc can't tell
  /// "never searched" from "searched and found nothing".
  String? _query;

  @override
  void dispose() {
    _remember.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MemoriesBloc>().state;
    return BlocListener<MemoriesBloc, MemoriesState>(
      // A save that worked: the text is remembered, so the field can empty. A
      // failed one leaves it, so nothing typed is lost.
      listenWhen: (previous, current) =>
          current.lastOutcome != null &&
          current.lastOutcome != previous.lastOutcome,
      listener: (context, state) => _remember.clear(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Memories')),
        body: SafeArea(child: _body(context, state)),
      ),
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
    final error = state.error;
    final loadFailed =
        error != null &&
        error is! MemoryValidationException &&
        state.memories.isEmpty &&
        !state.isLoading;
    return ListView(
      children: [
        TextEntry(
          controller: _remember,
          hint: 'Remember something',
          icon: Icons.add,
          tooltip: 'Remember',
          onSubmit: (text) => bloc.add(
            MemorySaved(NewMemory(content: text, kind: MemoryKind.topical)),
          ),
        ),
        TextEntry(
          controller: _search,
          hint: 'Search memories',
          icon: Icons.search,
          tooltip: 'Search',
          onSubmit: (text) {
            setState(() => _query = text);
            bloc.add(MemoriesRecalled(text));
          },
        ),
        if (state.lastOutcome?.isAbsorbed ?? false)
          const Padding(
            key: Key('memories_absorbed'),
            padding: EdgeInsets.all(16),
            child: Text('Already remembered, so it was not added again.'),
          ),
        if (error != null)
          Padding(
            key: const Key('memories_error'),
            padding: const EdgeInsets.all(16),
            child: Text(
              error is MemoryValidationException
                  ? 'That cannot be remembered: ${error.message}'
                  : 'Something went wrong. Try again.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (state.isRecalling) const LinearProgressIndicator(),
        if (state.recalled.isNotEmpty) ...[
          const _Heading('Search results'),
          for (final memory in state.recalled)
            _MemoryTile(memory, isMutating: state.isMutating),
        ] else if (_query != null && !state.isRecalling && error == null) ...[
          const _Heading('Search results'),
          Padding(
            key: const Key('memories_no_match'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('No memories match "$_query".'),
          ),
        ],
        const _Heading('Everything remembered'),
        if (state.isLoading && state.memories.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (loadFailed)
          Center(
            key: const Key('memories_load_failed'),
            child: TextButton(
              onPressed: () => bloc.add(const MemoriesRequested()),
              child: const Text('Could not load. Try again.'),
            ),
          )
        else if (state.memories.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nothing remembered yet.'),
          )
        else
          for (final memory in state.memories)
            _MemoryTile(memory, isMutating: state.isMutating),
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

class const _MemoryTile(final Memory memory, {required final bool isMutating})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListTile(
    key: Key('memory_${memory.id}'),
    title: Text(memory.content),
    subtitle: Text('${memory.kind.name} · ${memory.scope.name}'),
    trailing: IconButton(
      key: Key('forget_${memory.id}'),
      tooltip: 'Forget',
      icon: const Icon(Icons.delete_outline),
      // One change at a time: a second tap would retire it twice.
      onPressed: isMutating
          ? null
          : () => context.read<MemoriesBloc>().add(MemoryRetired(memory.id)),
    ),
  );
}
