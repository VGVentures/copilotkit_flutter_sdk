import 'package:ack/ack.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/bar_chart_args.dart';
import 'package:example/demo/widgets/bar_chart_card.dart';
import 'package:flutter/material.dart';

/// Lets the agent show a bar chart in the chat with [CopilotComponent], the
/// Flutter version of `useComponent`: ask it to "show a bar chart of …".
class const BarChartDemo({required final Widget child, super.key})
    extends StatelessWidget {
  // Keep in sync with BarChartArgs and ChartBar.
  static final ObjectSchema _parameters = Ack.object({
    'title': Ack.string().describe('Title of the chart'),
    'bars': Ack.list(
      Ack.object({
        'label': Ack.string().describe('Label of the bar'),
        'value': Ack.double().describe('Value of the bar'),
      }),
    ).describe('The bars, in the order to show them'),
  });

  @override
  Widget build(BuildContext context) => CopilotComponent<BarChartArgs>(
    name: 'showBarChart',
    description: 'Shows a horizontal bar chart of labelled values.',
    parameters: _parameters,
    decode: BarChartArgs.fromJson,
    builder: (context, call, args) => BarChartCard(call: call, args: args),
    child: child,
  );
}
