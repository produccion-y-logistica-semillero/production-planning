import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_task_entity.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/low_order/task_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/low_order/task_states.dart';

class TaskDialog extends StatelessWidget {
  final PlanningTaskEntity task;

  const TaskDialog({
    Key? key,
    required this.task,
  }) : super(key: key);

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
    final taskInfo = job.sequence!.tasks!.firstWhere((t) => t.id == task.taskId);

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
          _buildInfoRow("ID Job", job.jobId.toString()),
          _buildInfoRow("Secuencia", task.sequenceName),
          _buildInfoRow("ID tarea", task.taskId.toString()),
          _buildInfoRow("Tarea", taskInfo.description),
          _buildInfoRow(
            "Número ejecución",
            "${taskInfo.execOrder} de ${job.sequence!.tasks!.length}",
          ),
          _buildInfoRow("Cantidad", job.amount.toString()),
          _buildInfoRow(
            "Fechas",
            "${_getDateFormat(task.startDate)} - ${_getDateFormat(task.endDate)}",
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

  String _getDateFormat(DateTime date) {
    return DateFormat("dd/MM/yyyy HH:mm").format(date);
  }
}
