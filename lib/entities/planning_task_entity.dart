import 'package:production_planning/services/scheduling/preemption_engine.dart';

class PlanningTaskEntity {
  final int sequenceId;
  final String sequenceName;
  final String displayName;
  final int taskId;
  final int numberProcess; //this is for instance, if in the order we put 2 items of sequence x, then there would be x1 and x2
  final DateTime startDate;
  final bool retarded; //if the termination is after due date
  final DateTime endDate;
  final int jobId;
  final int orderId;

  /// Name of the machine this task ran on. Needed to label its setup-time
  /// bar in the Gantt ("Alistamiento — [machineName]") even in "Por Job"
  /// view, where the row is no longer the machine.
  final String machineName;

  /// The actual processing segments (start/end pairs) that make up this
  /// task's execution. A task that isn't preempted has exactly one segment
  /// equal to (startDate, endDate). A task that was paused by a work-shift
  /// boundary, a scheduled maintenance window, or the continuous-use rest
  /// cap has 2+ segments with gaps between them — startDate/endDate still
  /// span the whole thing (first segment's start to last segment's end) for
  /// consumers that only need the overall window.
  final List<ProcessingSegment> segments;

  /// Sequence-dependent setup/changeover segments that ran immediately
  /// before [segments] on the same machine, if any. Empty when this task
  /// had no setup cost.
  final List<ProcessingSegment> setupSegments;

  PlanningTaskEntity({
    required this.sequenceId,
    required this.sequenceName,
    required this.displayName,
    required this.taskId,
    required this.numberProcess,
    required this.startDate,
    required this.endDate,
    required this.retarded,
    required this.orderId,
    required this.jobId,
    required this.machineName,
    List<ProcessingSegment>? segments,
    this.setupSegments = const [],
  }) : segments = segments ?? [ProcessingSegment(startDate, endDate)];
}
