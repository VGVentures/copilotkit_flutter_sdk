import 'package:equatable/equatable.dart';

/// The answer to a batch of trajectory events: how many the service kept.
class const TrajectoryReceipt({
  /// How many events of the batch were stored.
  required final int accepted,

  /// How many events of the batch were refused.
  required final int rejected,

  /// The highest `seq` stored so far, or `null` when none was.
  final int? highestSeq,
}) extends Equatable {
  /// Creates a receipt.
  this;

  /// Decodes the reply to a batch of [batchSize] events, or returns `null`
  /// when it isn't a receipt for that batch: counts that aren't
  /// non-negative integers or don't add up to [batchSize], or no
  /// `highestSeq` although events were stored.
  static TrajectoryReceipt? tryParse(Object? reply, int batchSize) {
    if (reply
        case {'accepted': final int accepted, 'rejected': final int rejected}
        when accepted >= 0 &&
            rejected >= 0 &&
            accepted + rejected == batchSize) {
      final highestSeq = reply['highestSeq'];
      if (highestSeq != null && (highestSeq is! int || highestSeq < 0)) {
        return null;
      }
      if (accepted > 0 && highestSeq == null) return null;
      return TrajectoryReceipt(
        accepted: accepted,
        rejected: rejected,
        highestSeq: highestSeq as int?,
      );
    }
    return null;
  }

  @override
  List<Object?> get props => [accepted, rejected, highestSeq];
}
