import 'package:copilotkit/copilotkit.dart';
import 'package:flutter/widgets.dart';

/// Builds the widget for a tool call.
typedef ToolCallWidgetBuilder = Widget Function(
  BuildContext context,
  ToolCallView call,
);
