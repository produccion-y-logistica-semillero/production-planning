import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/features/2_orders/domain/entities/metrics.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_machine_entity.dart';
import 'package:intl/intl.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/high_order/metrics_page.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/low_order/task_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/low_order/task_dialog.dart'; // For formatting dates

class GanttChart extends StatefulWidget {
  final List<PlanningMachineEntity> machines;
  final Metrics metrics;
  final int? selectedRule;
  final List<DropdownMenuItem<int>> items;
  final int number;

  const GanttChart(
      {super.key,
      required this.machines,
      required this.selectedRule,
      required this.items,
      required this.metrics,
      required this.number});

  @override
  State<GanttChart> createState() => _GanttChartState(
        selectedRule: selectedRule,
        items: items,
      );
}

class _GanttChartState extends State<GanttChart> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _vertical2ScrollController = ScrollController();
  double _currentHorizontalValue = 1;
  double _currentVerticalValue = 1;
  double hourWidth = 0;
  Map<int, Color> jobColor = {};

  DateTime startDate;
  DateTime endDate;
  int totalDays;

  int? selectedRule;
  List<DropdownMenuItem<int>> items;

  _GanttChartState({
    required this.selectedRule,
    required this.items,
  })  : startDate = DateTime.now(),
        endDate = DateTime.now().add(const Duration(hours: 10)),
        totalDays = 1;

  @override
  void initState() {
    super.initState();
    endDate = widget.machines[0].tasks[0].endDate;
    startDate = widget.machines[0].tasks[0].startDate;
    for (final machine in widget.machines) {
      for (final task in machine.tasks) {
        if (task.startDate.isBefore(startDate)) startDate = task.startDate;
        if (task.endDate.isAfter(endDate)) endDate = task.endDate;
      }
    }
    startDate = DateTime(startDate.year, startDate.month, startDate.day);
    totalDays = endDate.difference(startDate).inDays;
    if (totalDays == 0) {
      endDate = DateTime(endDate.year, endDate.month, endDate.day + 1, endDate.hour, endDate.minute);
      totalDays++;
    }
  }

  double _calculatePosition(DateTime date, double totalWidth) {
    int totalMinutes = totalDays * 24 * 60; // Total minutes of the chart
    int dayOffset = date.difference(startDate).inMinutes; // Position in minutes of the passed date
    return ((dayOffset / totalMinutes) * totalWidth) +
        (hourWidth / 2); // Adjust the minutes to the width size, also take into account hour width
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: startDate, end: endDate),
      firstDate: DateTime(2020), // Earliest possible date
      lastDate: DateTime(2030), // Latest possible date
    );

    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
        totalDays = endDate.difference(startDate).inDays;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    double staticChartWidth = (((MediaQuery.of(context).size.width - 500) * 0.85)) / widget.number;
    double staticChartHeight = (MediaQuery.of(context).size.height - 220) * 0.85;
    double chartWidth = ((MediaQuery.of(context).size.width * 0.88) * _currentHorizontalValue) /
        widget.number; // The width depends on the user's selected zoom level
    hourWidth = (chartWidth / totalDays) / 24;
    double chartHeight = ((widget.machines.length + 1) * (45.0 * _currentVerticalValue));
    return Column(
      children: [
        // Date range selector
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DropdownButton<int>(
              value: selectedRule,
              hint: const Text('Selecciona una opción'),
              icon: const Icon(Icons.arrow_downward),
              iconSize: 24,
              elevation: 16,
              style: const TextStyle(color: Colors.deepPurple),
              underline: Container(
                height: 2,
                color: Colors.deepPurpleAccent,
              ),
              onChanged: (int? id) {
                if (id != null) BlocProvider.of<GanttBloc>(context).selectRule(id);
              },
              items: items,
            ),
            Text('Inicio: ${DateFormat('yyyy-MM-dd').format(startDate)}'),
            const SizedBox(width: 16),
            Text('Final: ${DateFormat('yyyy-MM-dd').format(endDate)}'),
            const SizedBox(width: 16),
            Text('Numero de dias: $totalDays'),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: () => _selectDateRange(context),
              child: const Text('Seleccione rango'),
            ),
            const SizedBox(
              width: 15,
            ),
            TextButton(onPressed: () => showMetrics(widget.metrics, context), child: const Text("Metricas")),
          ],
        ),

        // Slider to select the horizontal zoom
        Slider(
          value: _currentHorizontalValue,
          min: 1,
          max: 10,
          divisions: 40,
          label: _currentHorizontalValue.toStringAsFixed(1),
          onChanged: (val) {
            setState(() {
              _currentHorizontalValue = val;
            });
          },
        ),
        Row(
          children: [
            SizedBox(
              height: staticChartHeight + 8.0,
              child: RotatedBox(
                quarterTurns: 1,
                child: Slider(
                    value: _currentVerticalValue,
                    min: 1,
                    max: 10,
                    divisions: 40,
                    label: _currentVerticalValue.toStringAsFixed(1),
                    onChanged: (val) {
                      setState(() {
                        _currentVerticalValue = val;
                      });
                    }),
              ),
            ),
            // Gesture detector for horizontal drag and scroll
            Container(
              height: staticChartHeight,
              width: 140,
              margin: const EdgeInsets.only(top: 70),
              child: SingleChildScrollView(
                  controller: _vertical2ScrollController,
                  physics: const NeverScrollableScrollPhysics(),
                  scrollDirection: Axis.vertical,
                  child: SizedBox(
                    height: chartHeight,
                    width: 100,
                    child: Stack(
                      children: getMachines(widget.machines, context),
                    ),
                  )),
            ),
            Container(
              width: staticChartWidth,
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(width: 4)),
              child: GestureDetector(
                onPanUpdate: (details) {
                  _horizontalScrollController.jumpTo(_horizontalScrollController.offset - details.delta.dx);
                  _verticalScrollController.jumpTo(_verticalScrollController.offset - details.delta.dy);
                  _vertical2ScrollController.jumpTo(_vertical2ScrollController.offset - details.delta.dy);
                },
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: Container(
                    width: chartWidth + 50,
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Days and hours headers
                        _buildChartHeaders(chartWidth),
                        const SizedBox(height: 1.0),

                        // Gantt chart
                        SizedBox(
                          height: staticChartHeight,
                          child: SingleChildScrollView(
                            controller: _verticalScrollController,
                            physics: const NeverScrollableScrollPhysics(),
                            scrollDirection: Axis.vertical,
                            child: SizedBox(
                              height: chartHeight,
                              width: chartWidth,
                              child: Stack(
                                children: getTasks(widget.machines, chartWidth),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        )
      ],
    );
  }

  void showMetrics(Metrics metrics, BuildContext context) {
    showDialog(
        context: context,
        builder: (subContext) {
          return MetricsPage(metrics: metrics);
        });
  }

  List<Widget> getMachines(List<PlanningMachineEntity> machines, BuildContext context) {
    List<Widget> machineWidgets = [];

    for (int index = 0; index < machines.length; index++) {
      machineWidgets.add(Positioned(
          left: 5,
          top: (index * (40.0 * _currentVerticalValue)) + (5 * index),
          child: Container(
            height: 40.0 * _currentVerticalValue,
            width: 140,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              machines[index].machineName,
              style: const TextStyle(color: Colors.white),
            ),
          )));
    }
    return machineWidgets;
  }

  List<Widget> getTasks(List<PlanningMachineEntity> machines, double chartWidth) {
    List<Widget> ganttItems = [];

    for (int index = 0; index < machines.length; index++) {
      for (final task in machines[index].tasks) {
        double taskStartPosition = _calculatePosition(task.startDate, chartWidth);
        double taskEndPosition = _calculatePosition(task.endDate, chartWidth);
        if (taskEndPosition > chartWidth) {
          taskEndPosition = chartWidth;
        }

        if (!jobColor.containsKey(task.jobId)) {
          final random = Random();
          jobColor[task.jobId] = Color.fromARGB(
            255,
            random.nextInt(256),
            random.nextInt(256),
            random.nextInt(256),
          );
        }
        final Color taskColor = jobColor[task.jobId]!;
        // Task bar on the Gantt chart
        final item = Positioned(
          top: (index * (40.0 * _currentVerticalValue)) + (5 * index),
          left: taskStartPosition,
          child: GestureDetector(
            onDoubleTap: () {
              showDialog(
                  context: context,
                  builder: (c) {
                    return BlocProvider<TaskBloc>(
                      create: (context) => GetIt.instance.get<TaskBloc>(),
                      child: TaskDialog(task: task),
                    );
                  });
            },
            child: Container(
              width: taskEndPosition - taskStartPosition,
              height: 40.0 * _currentVerticalValue,
              decoration: BoxDecoration(
                color: taskColor,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Center(
                child: Text(
                  '${task.sequenceName}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        );
        ganttItems.add(item);
      }
    }
    return ganttItems;
  }

  Widget _buildChartHeaders(double totalWidth) {
    List<SizedBox> days = [];
    int totalDays = endDate.difference(startDate).inDays;
    double dayWidth = totalWidth / totalDays;

    // Iterate over the days in range
    for (int i = 0; i < totalDays; i++) {
      DateTime currentDate = startDate.add(Duration(days: i));

      final dayRow = Center(
        child: Text(
          '${currentDate.day}/${currentDate.month}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );

      List<SizedBox> hoursRow = [];
      // Display hours only if the day width is large enough
      int numberHours = (i < (totalDays - 1)) ? 23 : 24;
      for (int i = 0; i <= numberHours; i++) {
        List<Widget> column = [];
        double height = dayWidth > 800 ? 10 : 15;
        if (i == 0) height = 30;
        column.add(SizedBox(height: height, child: VerticalDivider(thickness: i == 0 ? 4 : 1, width: 2)));
        if (dayWidth > 800) {
          if (i != 0) {
            column.add(
              Text(
                '$i:00',
                style: const TextStyle(fontSize: 12),
              ),
            );
          }
        }
        hoursRow.add(
          SizedBox(
            width: hourWidth,
            child: Column(
              children: column,
            ),
          ),
        );
      }

      // Add the day and hour rows to the list of columns
      days.add(
        SizedBox(
          width: dayWidth,
          child: SizedBox(
            height: 70,
            child: Column(
              children: [
                dayRow,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: hoursRow,
                ),
                const Divider(),
              ],
            ),
          ),
        ),
      );
    }

    return Row(children: days);
  }
}
