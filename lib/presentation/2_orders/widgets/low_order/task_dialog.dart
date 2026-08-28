import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';
import 'package:production_planning/presentation/2_orders/widgets/low_order/task_bloc.dart';
import 'package:production_planning/presentation/2_orders/widgets/low_order/task_states.dart';
import 'package:production_planning/shared/functions/functions.dart';

class TaskDialog extends StatelessWidget {
  final PlanningTaskEntity task;

  const TaskDialog({
    super.key,
    required this.task,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: BlocBuilder<TaskBloc, TaskState>(
          builder: (context, state) {
            if (state is TaskInitialState) {
              BlocProvider.of<TaskBloc>(context).getTaskInfo(task.orderId);
            }
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.4,
              ),
              child: _buildStateContent(state),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStateContent(TaskState state) {
    return switch (state) {
      TaskRetrievingState() => const Center(
          child: CircularProgressIndicator(),
        ),
      TaskErrorState() => const Center(
          child: Text(
            "Hubo un error",
            style: TextStyle(fontSize: 16, color: Colors.red),
          ),
        ),
      TaskRetrievedState(order: final order) => _buildOrderInfo(order),
      _ => const SizedBox(),
    };
  }

  Widget _buildOrderInfo(OrderEntity order) {
    final job = order.orderJobs!.firstWhere((j) => j.jobId! == task.jobId);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow("Order ID", order.orderId.toString()),
          _buildInfoRow(
            "La orden está compuesta por",

            order.orderJobs!
                .map((j) => j.sequence!.name)
                .join(", "),
          ),
          _buildInfoRow("Nombre de Job", job.jobName ?? "Job ${job.jobId}"),
          _buildInfoRow("Secuencia", task.sequenceName),
          _buildInfoRow("ID tarea", task.taskId.toString()),
          _buildInfoRow(
            "Tiempo procesamiento",
            _formatProcessingDuration(_actualProcessingDuration(task)),
          ),
         /* _buildInfoRow(
            "Número ejecución",
            "${taskInfo.execOrder} de ${job.sequence!.tasks!.length}",
          ),*/
          _buildInfoRow(
            "Fechas",
            "${getDateFormat(task.startDate)} - ${getDateFormat(task.endDate)}",
          ),
          if (task.segments.length > 1)
            _buildInfoRow(
              "Procesado en ${task.segments.length} tramos",
              task.segments
                  .map((s) =>
                      '${getDateFormat(s.start)} – ${getDateFormat(s.end)}')
                  .join('\n'),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              "$label:",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// The duration actually spent processing this specific task instance —
  /// the sum of its segments, excluding any preemption pauses. This is what
  /// was truly scheduled for this job, as opposed to the sequence's generic
  /// per-task template duration (which can differ once per-job/per-machine
  /// overrides or machine processing percentages are applied).
  Duration _actualProcessingDuration(PlanningTaskEntity task) {
    return task.segments.fold(
      Duration.zero,
      (sum, segment) => sum + segment.duration,
    );
  }

  String _formatProcessingDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes =
        (duration.inMinutes - duration.inHours * 60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }
}
