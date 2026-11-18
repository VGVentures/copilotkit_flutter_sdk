import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/memories/widgets/memories_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Shows what the runtime remembers about the user, and lets them add,
/// search and forget memories.
class const MemoriesPage({
  /// The client whose runtime keeps the memories, e.g.
  /// `CopilotKitClient.memories`.
  required final MemoriesClient client,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => MemoriesBloc(client: client)..add(const MemoriesRequested()),
    child: const MemoriesView(),
  );
}
