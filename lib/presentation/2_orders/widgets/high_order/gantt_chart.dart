import 'dart:math';
import 'package:dartz/dartz.dart' as dartz;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/presentation/2_orders/widgets/high_order/metrics_page.dart';
import 'package:production_planning/presentation/2_orders/widgets/low_order/task_bloc.dart';
import 'package:production_planning/presentation/2_orders/widgets/low_order/task_dialog.dart';

class GanttChart extends StatefulWidget {
  final List<PlanningMachineEntity> machines;
  final Metrics metrics;
  final int? selectedRule;
  final List<DropdownMenuItem<int>> items;
  final int number;
  final dartz.Tuple2<TimeOfDay, TimeOfDay> schedule;

  const GanttChart({
    super.key,
    required this.machines,
    required this.selectedRule,
    required this.items,
    required this.metrics,
    required this.number,
    required this.schedule,
  });

  @override
  State<GanttChart> createState() => _GanttChartState();
}

class _GanttChartState extends State<GanttChart> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalMachineScrollController = ScrollController();
  final ScrollController _verticalTasksScrollController = ScrollController();

  //zoom factors
  double _horizontalZoom = 1.4;
  double _verticalZoom = 1.0;

  late DateTime _startDate;
  late DateTime _endDate;
  late int _totalDays;

  late int initialHour;
  late int endingHour;

  final Map<int, Color> _jobColor = {};

  int? _selectedRule;

  double _hourWidth = 0;

  @override
  void initState() {
    super.initState();
    _selectedRule = widget.selectedRule;
    _calculateChartDateRange();

    initialHour = widget.schedule.value1.hour;
    endingHour = widget.schedule.value2.hour;

    //keep the two vertical scrolls in sync (machine list & tasks)
    _verticalMachineScrollController.addListener(() {
      _verticalTasksScrollController.jumpTo(
        _verticalMachineScrollController.offset,
      );
    });
    _verticalTasksScrollController.addListener(() {
      _verticalMachineScrollController.jumpTo(
        _verticalTasksScrollController.offset,
      );
    });
  }

  void _calculateChartDateRange() {
    DateTime? earliest;
    DateTime? latest;
    bool foundAnyTask = false;

    for (final machine in widget.machines) {
      for (final task in machine.tasks) {
        if(earliest == null){
          earliest = task.startDate;
          latest = earliest.add(const Duration(days: 1));
        }
        foundAnyTask = true;
        if (task.startDate.isBefore(earliest)) {
          earliest = task.startDate;
        }
        if (task.endDate.isAfter(latest!)) {
          latest = task.endDate;
        }
      }
    }
    if(earliest == null){
      earliest = DateTime.now();
      latest = earliest.add(const Duration(days: 1));
    }
    if (!foundAnyTask) {
      _startDate = earliest;
      _endDate = latest!;
      _totalDays = 1;
      return;
    }

    _startDate = DateTime(earliest.year, earliest.month, earliest.day);
    _endDate = latest!;
    _totalDays = _endDate.difference(_startDate).inDays+1;
    if(_totalDays > 20){
      _totalDays = 20;
      _endDate = _startDate.add(const Duration(days: 20));
    }
    if (_totalDays < 1) {
      _totalDays = 1;
      _endDate = _startDate.add(const Duration(days: 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    const machineListWidth = 140.0;

    final chartContainerWidth = max((screenWidth - 220) * 0.8, 300);

    final chartContainerHeight = max((screenHeight - 300) * 0.9, 300);

    //total (virtual) width of the chart (with zoom)
    final chartTotalWidth = (chartContainerWidth * _horizontalZoom) / widget.number;

    //total (virtual) height for the tasks area
    final chartTotalHeight = (widget.machines.length * (40.0 * _verticalZoom))
        + (5 * (widget.machines.length - 1));


    final dayWidth = chartTotalWidth / _totalDays;
    _hourWidth = dayWidth / (endingHour-initialHour);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTopControls(),
        const SizedBox(height: 8),
        _buildHorizontalZoomSlider(),
        const SizedBox(height: 8),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVerticalZoomSlider(chartContainerHeight.toDouble()),

            SizedBox(
              width: machineListWidth,
              height: chartContainerHeight.toDouble(),
              child: _buildMachineListArea(chartTotalHeight),
            ),

            Expanded(
              child: _buildChartArea(
                chartContainerWidth: chartContainerWidth.toDouble(),
                chartContainerHeight: chartContainerHeight.toDouble(),
                chartTotalWidth: chartTotalWidth,
                chartTotalHeight: chartTotalHeight,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        DropdownButton<int>(
          value: _selectedRule,
          items: widget.items.where((item) => item.value == _selectedRule).toList(),
          onChanged: (int? id) {
            if (id != null) {
              setState(() {
                _selectedRule = id;
              });
              BlocProvider.of<GanttBloc>(context).selectRule(id);
            }
          },
        ),

        const SizedBox(width: 16),
        Text('Inicio: ${DateFormat('yyyy-MM-dd').format(_startDate)}'),
        const SizedBox(width: 16),
        Text('Final: ${DateFormat('yyyy-MM-dd').format(_endDate)}'),
        const SizedBox(width: 16),
        Text('Días: $_totalDays'),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () => _selectDateRange(context),
          child: const Text('Rango de fechas'),
        ),
        const SizedBox(width: 16),
        //TextButton(
        // onPressed: () => _showMetrics(widget.metrics, context),
        //  child: const Text('Métricas'),
        // ),
      ],
    );
  }

  Widget _buildHorizontalZoomSlider() {
    return Slider(
      value: _horizontalZoom,
      min: 1.4,
      max: 10,
      divisions: 40,
      label: _horizontalZoom.toStringAsFixed(1),
      onChanged: (val) {
        setState(() {
          _horizontalZoom = val;
        });
      },
    );
  }

  Widget _buildVerticalZoomSlider(double chartContainerHeight) {
    return SizedBox(
      height: chartContainerHeight,
      child: RotatedBox(
        quarterTurns: 1,
        child: Slider(
          value: _verticalZoom,
          min: 1,
          max: 10,
          divisions: 40,
          label: _verticalZoom.toStringAsFixed(1),
          onChanged: (val) {
            setState(() {
              _verticalZoom = val;
            });
          },
        ),
      ),
    );
  }

  Widget _buildMachineListArea(double chartTotalHeight) {
    return Container(
      margin: const EdgeInsets.only(top: 55), //this is impportant, because this margin aligns the machines with the tasks
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        controller: _verticalMachineScrollController,
        scrollDirection: Axis.vertical,
        child: SizedBox(
          height: chartTotalHeight,
          child: Stack(
            children: _machineNameWidgets(),
          ),
        ),
      ),
    );
  }

  List<Widget> _machineNameWidgets() {
    final List<Widget> widgets = [];
    for (int i = 0; i < widget.machines.length; i++) {
      final topPos = (i * (40.0 * _verticalZoom)) + (5 * i);
      widgets.add(
        Positioned(
          top: topPos,
          left: 5,
          child: Container(
            height: 40.0 * _verticalZoom,
            width: 130,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(5),
            ),
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                widget.machines[i].machineName,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildChartArea({
    required double chartContainerWidth,
    required double chartContainerHeight,
    required double chartTotalWidth,
    required double chartTotalHeight,
  }) {
    return GestureDetector(
      onPanUpdate: (details) {
        _horizontalScrollController.jumpTo(
          _horizontalScrollController.offset - details.delta.dx,
        );
        _verticalTasksScrollController.jumpTo(
          _verticalTasksScrollController.offset - details.delta.dy,
        );
      },
      child: Container(
        width: chartContainerWidth,
        height: chartContainerHeight,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(width: 1),
        ),
        child: SingleChildScrollView(
          controller: _horizontalScrollController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: chartTotalWidth + 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildChartHeaders(chartTotalWidth),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _verticalTasksScrollController,
                    scrollDirection: Axis.vertical,
                    child: SizedBox(
                      height: chartTotalHeight,
                      width: chartTotalWidth,
                      child: Stack(
                        children: _buildTaskBars(chartTotalWidth),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChartHeaders(double chartWidth) {
    final totalDays = max(1, _totalDays);
    final List<Widget> dayWidgets = [];
    final dayWidth = chartWidth / totalDays;

    for (int i = 0; i < totalDays; i++) {
      final currentDate = _startDate.add(Duration(days: i));
      final dayLabel = Text(
        '${currentDate.day}/${currentDate.month}',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      );

      final List<Widget> hourTicks = [];
      for (int hour = initialHour; hour < endingHour; hour++) {
        final children = <Widget>[
          SizedBox(
            height: (hour == initialHour) ? 30 : 10,
            child: VerticalDivider(
              thickness: (hour == initialHour) ? 2 : 1,
              width: 1,
              color: Colors.grey.shade700,
            ),
          ),
        ];

        if (dayWidth > 800 && hour > initialHour) {
          children.add(
            Text('$hour:00', style: const TextStyle(fontSize: 10)),
          );
        }

        hourTicks.add(
          SizedBox(
            width: _hourWidth,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: children,
            ),
          ),
        );
      }

      dayWidgets.add(
        SizedBox(
          width: dayWidth,
          child: Column(
            children: [
              dayLabel,
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: hourTicks,
              ),
              const Divider(height: 1),
            ],
          ),
        ),
      );
    }

    return Row(children: dayWidgets);
  }

  List<Widget> _buildTaskBars(double chartWidth) {
    final bars = <Widget>[];

    for (int i = 0; i < widget.machines.length; i++) {
      final machine = widget.machines[i];
      for (final task in machine.tasks) {
        if (!_jobColor.containsKey(task.jobId)) {
          final random = Random();
          _jobColor[task.jobId] = Color.fromARGB(
            255,
            random.nextInt(256),
            random.nextInt(256),
            random.nextInt(256),
          );
        }
        final color = _jobColor[task.jobId]!;

        final top = (i * (40.0 * _verticalZoom)) + (5 * i);
        final left = _calculateTaskLeft(task.startDate, chartWidth);
        final right = _calculateTaskLeft(task.endDate, chartWidth);
        final width = (right - left).clamp(1, chartWidth);

        bars.add(
          Positioned(
            top: top,
            left: left,
            child: GestureDetector(
              onDoubleTap: () => _openTaskDialog(task),
              child: Container(
                width: width.toDouble(),
                height: 40.0 * _verticalZoom,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(5),
                ),
                alignment: Alignment.center,
                child: FittedBox(
                  //Agregar id del job y el id de la secuencia
                  child: Text(
                    '${task.sequenceName} (Job: ${task.jobId})',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return bars;
  }

  double _calculateTaskLeft(DateTime date, double chartWidth) {
    final hoursPerDay = endingHour - initialHour;
    final totalDisplayedMinutes = _totalDays * hoursPerDay * 60;

    final dayIndex = date.difference(_startDate).inDays;
    final clampedDayIndex = dayIndex < 0 ? 0 : (dayIndex >= _totalDays ? _totalDays - 1 : dayIndex);

    final hour = date.hour;
    final clampedHour = (hour < initialHour)
        ? initialHour
        : (hour >= endingHour ? endingHour : hour);

    int minutePart = date.minute;
    if (hour < initialHour || hour >= endingHour) {
      minutePart = 0;
    }
    final displayedMinutesSoFar = (clampedDayIndex * hoursPerDay * 60)
        + ((clampedHour - initialHour) * 60)
        + minutePart;
    final fraction = (displayedMinutesSoFar / totalDisplayedMinutes).clamp(0.0, 1.0);
    return (fraction * chartWidth) + (_hourWidth/2);
  }



  Future<void> _selectDateRange(BuildContext context) async {
    final result = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (result != null) {
      setState(() {
        _startDate = DateTime(
          result.start.year,
          result.start.month,
          result.start.day,
        );
        _endDate = DateTime(
          result.end.year,
          result.end.month,
          result.end.day,
          23,
          59,
          59,
        );
        _totalDays = max(1, _endDate.difference(_startDate).inDays);
      });
    }
  }

  void _showMetrics(Metrics metrics, BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => MetricsPage(metrics: metrics),
    );
  }

  void _openTaskDialog(task) {
    showDialog(
      context: context,
      builder: (c) {
        return BlocProvider<TaskBloc>(
          create: (_) => GetIt.instance.get<TaskBloc>(),
          child: TaskDialog(task: task),
        );
      },
    );
  }
}
