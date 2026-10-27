// Placeholder demo content: a todo list kept in the agent's shared state, so
// both directions (the app edits it, the agent edits it) can be checked on a
// device.
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/todo_list.dart';
import 'package:flutter/material.dart';

/// Placeholder demo: shows the todo list of the agent's shared state and
/// lets the user add, tick and remove items.
///
/// Reads the agent of the nearest `CopilotAgentScope`. Edits go through
/// `CopilotAgent.setSharedState`, so the next run sends them, and the agent's
/// own edits arrive as state snapshots and deltas.
class const TodoPanel({super.key}) extends StatefulWidget {
  @override
  State<TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends State<TodoPanel> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _edit(TodoList list) {
    CopilotAgentScope.of(context).setSharedState(SharedState(list.toJson()));
  }

  void _add(TodoList list) {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    _edit(list.added(title));
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return AgentStateBuilder<SharedState?>(
      selector: (state) => state.sharedState,
      builder: (context, shared) {
        final list = _decode(shared);
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shared todos',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (list.todos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Nothing yet. Add one, or ask the agent to.'),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final (index, todo) in list.todos.indexed)
                          CheckboxListTile(
                            key: ValueKey('todo_$index'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: todo.done,
                            onChanged: (_) => _edit(list.toggled(index)),
                            title: Text(
                              todo.title,
                              style: todo.done
                                  ? const TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                    )
                                  : null,
                            ),
                            secondary: IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.close),
                              onPressed: () => _edit(list.removed(index)),
                            ),
                          ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _add(list),
                        decoration: const InputDecoration(
                          hintText: 'Add a todo',
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Add',
                      icon: const Icon(Icons.add),
                      onPressed: () => _add(list),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The list in [shared], or an empty one when there is none or the agent
  /// wrote something that isn't a todo list.
  static TodoList _decode(SharedState? shared) {
    try {
      return shared?.decode(TodoList.fromJson) ?? const TodoList();
    } on Object {
      return const TodoList();
    }
  }
}
