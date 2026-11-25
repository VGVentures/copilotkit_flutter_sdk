import 'fixtures.dart';

/// The row of [step] in `trajectory_connect.jsonl` (recorded) or, failing
/// that, `trajectory_batches.jsonl` (synthetic).
Map<String, Object?> trajectoryRow(String step) => [
  ...loadFixture('trajectory_connect').rawEvents,
  ...loadFixture('trajectory_batches').rawEvents,
].firstWhere((row) => row['step'] == step || row['kind'] == step);
