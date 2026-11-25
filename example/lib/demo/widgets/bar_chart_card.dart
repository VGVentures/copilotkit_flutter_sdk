import 'dart:math' as math;

import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/bar_chart_args.dart';
import 'package:example/demo/models/chart_bar.dart';
import 'package:flutter/material.dart';

/// Generative UI for `showBarChart` calls: a horizontal bar per value,
/// filled in as the agent streams the arguments.
class const BarChartCard({
  /// The call to show.
  required final ToolCallView call,

  /// The arguments of [call], or `null` while they can't be decoded yet.
  final BarChartArgs? args,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bars = [
      for (final bar in args?.bars ?? const <ChartBar>[])
        if (bar.label != null && bar.value != null) (bar.label!, bar.value!),
    ];
    final largest = bars.fold<double>(0, (max, bar) => math.max(max, bar.$2));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(args?.title ?? 'Chart', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (bars.isEmpty && call.status == ToolCallStatus.inProgress)
              const LinearProgressIndicator(),
            for (final (label, value) in bars)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 96, child: Text(label)),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: largest <= 0 ? 0 : value / largest,
                        minHeight: 16,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_format(value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _format(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';
}
