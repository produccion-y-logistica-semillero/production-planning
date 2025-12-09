import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_state.dart';

class GanttDataTablePage extends StatelessWidget {
  final int orderId;

  const GanttDataTablePage({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Detalle de Programación',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: BlocBuilder<GanttBloc, GanttState>(
          builder: (context, state) {
            if (state is GanttOrderRetrieveError) {
              return const _ErrorMessage(
                message:
                    'Ocurrió un error al recuperar la información de la orden.',
              );
            }

            if (state is GanttPlanningError) {
              return const _ErrorMessage(
                message:
                    'No fue posible obtener la planificación para la orden.',
              );
            }

            if (state is GanttPlanningLoading ||
                state.orderId == null ||
                state.selectedRule == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is! GanttPlanningSuccess) {
              return const _ErrorMessage(
                message:
                    'Selecciona un algoritmo para visualizar la información.',
              );
            }

            final rules = state.enviroment?.rules;
            final selectedRuleName = () {
              if (rules == null || rules.isEmpty) {
                return 'Algoritmo ${state.selectedRule ?? '-'}';
              }

              final matchingRule = rules.firstWhere(
                (rule) => rule.value1 == state.selectedRule,
                orElse: () => rules.first,
              );

              return matchingRule.value2?.toString() ??
                  'Algoritmo ${matchingRule.value1}';

            }();

            final taskRows = _buildTaskRows(state.planningMachines);
            if (taskRows.isEmpty) {
              return _EmptyMessage(
                  orderId: orderId, ruleName: selectedRuleName);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderInfo(
                  orderId: orderId,
                  ruleName: selectedRuleName,
                  machineCount: state.planningMachines.length,
                  taskCount: taskRows.length,
                ),
                const SizedBox(height: 16),
                Expanded(child: _TaskTable(rows: taskRows)),
              ],
            );
          },
        ),
      ),
    );
  }

  List<_TaskTableRowData> _buildTaskRows(List<PlanningMachineEntity> machines) {
    final List<_TaskTableRowData> rows = [];

    for (final machine in machines) {
      for (final task in machine.tasks) {
        rows.add(
          _TaskTableRowData(
            machineName: machine.machineName,
            task: task,
          ),
        );
      }
    }

    rows.sort((a, b) => a.task.startDate.compareTo(b.task.startDate));
    return rows;
  }
}

class _HeaderInfo extends StatelessWidget {
  final int orderId;
  final String ruleName;
  final int machineCount;
  final int taskCount;

  const _HeaderInfo({
    required this.orderId,
    required this.ruleName,
    required this.machineCount,
    required this.taskCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Orden $orderId',
            style: TextStyle(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Algoritmo: $ruleName',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.precision_manufacturing_outlined,
                label: '$machineCount máquinas',
              ),
              _InfoChip(
                icon: Icons.playlist_add_check_circle_outlined,
                label: '$taskCount operaciones',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskTable extends StatelessWidget {
  final List<_TaskTableRowData> rows;

  const _TaskTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFormatter = DateFormat('dd/MM/yyyy HH:mm');

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              colorScheme.primaryContainer.withOpacity(0.6),
            ),
            columnSpacing: 24,
            horizontalMargin: 16,
            dataRowMinHeight: 56,
            dataRowMaxHeight: 72,
            columns: const [
              DataColumn(label: Text('Máquina')),
              DataColumn(label: Text('Job')),
              DataColumn(label: Text('Operación')),
              DataColumn(label: Text('Inicio')),
              DataColumn(label: Text('Fin')),
              DataColumn(label: Text('Duración (min)')),
              DataColumn(label: Text('Estado')),
            ],
            rows: List<DataRow>.generate(rows.length, (index) {
              final row = rows[index];
              final task = row.task;
              final duration = task.endDate.difference(task.startDate);
              final durationMinutes = duration.inMinutes;

              return DataRow(
                color: WidgetStateProperty.all(
                  index.isEven
                      ? colorScheme.surface.withOpacity(0.6)
                      : Colors.transparent,
                ),
                cells: [
                  DataCell(Text(row.machineName)),
                  DataCell(Text('Job ${task.jobId}')),
                  DataCell(Text('${task.sequenceName} #${task.numberProcess}')),
                  DataCell(Text('${task.displayName}')),
                  DataCell(Text(dateFormatter.format(task.startDate))),
                  DataCell(Text(dateFormatter.format(task.endDate))),
                  DataCell(Text('$durationMinutes')),
                  DataCell(
                    Row(
                      children: [
                        Icon(
                          task.retarded
                              ? Icons.warning_amber_outlined
                              : Icons.check_circle_outline,
                          color: task.retarded
                              ? colorScheme.error
                              : colorScheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          task.retarded ? 'Fuera de plazo' : 'A tiempo',
                          style: TextStyle(
                            color: task.retarded
                                ? colorScheme.error
                                : colorScheme.onSurfaceVariant,
                            fontWeight: task.retarded
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _TaskTableRowData {
  final String machineName;
  final PlanningTaskEntity task;

  const _TaskTableRowData({required this.machineName, required this.task});
}

class _ErrorMessage extends StatelessWidget {
  final String message;

  const _ErrorMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            color: colorScheme.error,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  final int orderId;
  final String ruleName;

  const _EmptyMessage({required this.orderId, required this.ruleName});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            color: colorScheme.onSurfaceVariant,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'No hay operaciones programadas para la orden $orderId con el algoritmo "$ruleName".',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
