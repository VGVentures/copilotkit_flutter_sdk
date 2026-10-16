/// Flutter widgets and blocs for the CopilotKit SDK.
///
/// Re-exports the `copilotkit` core, so apps only import this library.
library;

export 'package:copilotkit/copilotkit.dart';

export 'src/chat/bloc/copilot_chat_bloc.dart';
export 'src/chat/models/chat_row.dart';
export 'src/client/copilot_kit.dart';
export 'src/context/copilot_context.dart';
export 'src/tools/copilot_tool.dart';
export 'src/tools/tool_call_widget.dart';
export 'src/tools/tool_call_widget_builder.dart';
export 'src/tools/tool_renderer.dart';
