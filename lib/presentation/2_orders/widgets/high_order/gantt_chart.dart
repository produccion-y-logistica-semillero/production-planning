import 'dart:math';
import 'package:dartz/dartz.dart' as dartz;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/presentation/2_orders/widgets/high_order/metrics_page.dart';
import 'package:production_planning/presentation/2_orders/widgets/low_order/task_bloc.dart';
import 'package:production_planning/presentation/2_orders/widgets/low_order/task_dialog.dart';

enum GanttViewMode { byMachine, byJob }

class _GanttRow {
  final String name;
  final List<PlanningTaskEntity> tasks;

  const _GanttRow({
    required this.name,
    required this.tasks,
  });
}

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

  GanttViewMode _currentMode = GanttViewMode.byMachine;
  List<_GanttRow> _rows = [];

  double _horizontalZoom = 1.8;
  double _verticalZoom = 1.0;

  late DateTime _startDate;
  late DateTime _endDate;
  late int _totalDays;

  late int initialHour;
  late int endingHour;

  final Map<int, Color> _jobColor = {};

  int? _selectedRule;

  double _hourWidth = 0;

  bool _syncingMachineScroll = false;
  bool _syncingTasksScroll = false;

  @override
  void initState() {
    super.initState();

    _selectedRule = widget.selectedRule;
    if (_selectedRule == null && widget.items.isNotEmpty) {
      _selectedRule = widget.items.first.value;
    }

    initialHour = widget.schedule.value1.hour;
    endingHour = widget.schedule.value2.hour;

    if (endingHour <= initialHour) {
      endingHour = initialHour + 1;
    }

    _calculateChartDateRange();
    _updateRows();

    // Sincroniza el scroll vertical
    _verticalMachineScrollController.addListener(() {
      if (_syncingMachineScroll) return;

      if (_verticalTasksScrollController.hasClients) {
        _syncingTasksScroll = true;

        _verticalTasksScrollController.jumpTo(
          _verticalMachineScrollController.offset.clamp(
            _verticalTasksScrollController.position.minScrollExtent,
            _verticalTasksScrollController.position.maxScrollExtent,
          ),
        );

        _syncingTasksScroll = false;
      }
    });

    _verticalTasksScrollController.addListener(() {
      if (_syncingTasksScroll) return;

      if (_verticalMachineScrollController.hasClients) {
        _syncingMachineScroll = true;

        _verticalMachineScrollController.jumpTo(
          _verticalTasksScrollController.offset.clamp(
            _verticalMachineScrollController.position.minScrollExtent,
            _verticalMachineScrollController.position.maxScrollExtent,
          ),
        );

        _syncingMachineScroll = false;
      }
    });
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalMachineScrollController.dispose();
    _verticalTasksScrollController.dispose();
    super.dispose();
  }

  void _calculateChartDateRange() {
    DateTime? earliest;
    DateTime? latest;
    bool foundAnyTask = false;

    for (final machine in widget.machines) {
      for (final task in machine.tasks) {
        if (earliest == null) {
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

    if (earliest == null) {
      earliest = DateTime.now();
      latest = earliest.add(const Duration(days: 1));
    }

    if (!foundAnyTask) {
      _startDate = earliest;
      _endDate = latest!;
      _totalDays = 1;
      return;
    }

    _startDate = DateTime(
      earliest.year,
      earliest.month,
      earliest.day,
    );

    _endDate = latest!;
    _totalDays = _endDate.difference(_startDate).inDays + 1;

    if (_totalDays > 20) {
      _totalDays = 20;
      _endDate = _startDate.add(const Duration(days: 20));
    }

    if (_totalDays < 1) {
      _totalDays = 1;
      _endDate = _startDate.add(const Duration(days: 1));
    }
  }

  void _updateRows() {
    if (_currentMode == GanttViewMode.byMachine) {
      _rows = widget.machines.map((machine) {
        final machineTasks = List<PlanningTaskEntity>.from(machine.tasks)
          ..sort((a, b) => a.startDate.compareTo(b.startDate));

        return _GanttRow(
          name: machine.machineName,
          tasks: machineTasks,
        );
      }).toList();
    } else {
      final jobMap = <int, List<PlanningTaskEntity>>{};

      for (final machine in widget.machines) {
        for (final task in machine.tasks) {
          jobMap.putIfAbsent(task.jobId, () => []).add(task);
        }
      }

      _rows = jobMap.entries.map((entry) {
        final tasks = List<PlanningTaskEntity>.from(entry.value)
          ..sort((a, b) => a.startDate.compareTo(b.startDate));

        final label = _baseTaskName(tasks.first.displayName);

        return _GanttRow(
          name: 'Job ${entry.key} – $label',
          tasks: tasks,
        );
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    const double rowLabelWidth = 220.0;
    const double rowHeight = 40.0;
    const double rowSpacing = 5.0;
    const double rowHeaderHeight = 76.0;

    final double rowSlotHeight = rowHeight * _verticalZoom + rowSpacing;

    final double chartContainerWidth =
        max(screenWidth - rowLabelWidth - 72, 620).toDouble();

    final double chartTotalHeight =
        max(_rows.length * rowSlotHeight, 280.0).toDouble();

    final double chartRowsVisibleHeight =
        max(min(chartTotalHeight, screenHeight * 0.72).toDouble(), 320.0)
            .toDouble();

    final double chartTotalWidth =
        max(chartContainerWidth * _horizontalZoom, chartContainerWidth);

    final double dayWidth = chartTotalWidth / max(1, _totalDays);
    _hourWidth = dayWidth / max(1, endingHour - initialHour);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTopControls(),
        const SizedBox(height: 8),
        _buildZoomSliders(),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: rowLabelWidth,
              height: chartRowsVisibleHeight + rowHeaderHeight,
              child: _buildRowLabelPanel(
                chartTotalHeight,
                rowHeaderHeight,
                rowHeight,
                chartRowsVisibleHeight,
              ),
            ),
            Expanded(
              child: _buildChartArea(
                chartContainerWidth: chartContainerWidth,
                chartVisibleHeight: chartRowsVisibleHeight,
                chartTotalWidth: chartTotalWidth,
                chartTotalHeight: chartTotalHeight,
                headerHeight: rowHeaderHeight,
                rowHeight: rowHeight,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopControls() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          children: [
            const Text(
              'Algoritmo: ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _selectedRule,
              hint: const Text('Seleccionar algoritmo'),
              items: widget.items,
              onChanged: (int? id) {
                if (id != null) {
                  setState(() {
                    _selectedRule = id;
                  });

                  BlocProvider.of<GanttBloc>(context).selectRule(id);
                }
              },
            ),
            const SizedBox(width: 24),
            SegmentedButton<GanttViewMode>(
              segments: const [
                ButtonSegment(
                  value: GanttViewMode.byMachine,
                  label: Text('Por Máquina'),
                ),
                ButtonSegment(
                  value: GanttViewMode.byJob,
                  label: Text('Por Job'),
                ),
              ],
              selected: {_currentMode},
              onSelectionChanged: (newSelection) {
                setState(() {
                  _currentMode = newSelection.first;
                  _updateRows();
                });
              },
            ),
            const SizedBox(width: 24),
            Text(
              'Inicio: ${DateFormat('yyyy-MM-dd').format(_startDate)}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(width: 16),
            Text(
              'Final: ${DateFormat('yyyy-MM-dd').format(_endDate)}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(width: 16),
            Text(
              'Días: $_totalDays',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: () => _selectDateRange(context),
              child: const Text('Rango de fechas'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomSliders() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          const Text('Zoom Horizontal: ', style: TextStyle(fontSize: 12)),
          Expanded(
            child: Slider(
              value: _horizontalZoom,
              min: 0.8,
              max: 4.0,
              divisions: 32,
              label: _horizontalZoom.toStringAsFixed(1),
              onChanged: (val) {
                setState(() {
                  _horizontalZoom = val;
                });
              },
            ),
          ),
          const SizedBox(width: 24),
          const Text('Zoom Vertical: ', style: TextStyle(fontSize: 12)),
          SizedBox(
            width: 120,
            child: Slider(
              value: _verticalZoom,
              min: 0.8,
              max: 2.0,
              divisions: 12,
              label: _verticalZoom.toStringAsFixed(2),
              onChanged: (val) {
                setState(() {
                  _verticalZoom = val;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowLabelPanel(
    double chartTotalHeight,
    double headerHeight,
    double rowHeight,
    double visibleHeight,
  ) {
    final double rowSlotHeight = rowHeight * _verticalZoom + 5.0;

    return Column(
      children: [
        Container(
          height: headerHeight,
          color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
          alignment: Alignment.center,
          child: Text(
            _currentMode == GanttViewMode.byMachine ? 'MÁQUINAS' : 'JOBS',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _verticalMachineScrollController,
            scrollDirection: Axis.vertical,
            child: SizedBox(
              height: chartTotalHeight,
              child: Column(
                children: _rowNameWidgets(
                  rowHeight,
                  rowSlotHeight,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _rowNameWidgets(
    double rowHeight,
    double rowSlotHeight,
  ) {
    final List<Widget> widgets = [];

    for (int i = 0; i < _rows.length; i++) {
      widgets.add(
        SizedBox(
          height: rowSlotHeight,
          child: Center(
            child: Container(
              height: rowHeight * _verticalZoom,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: i.isEven
                    ? Theme.of(context)
                        .colorScheme
                        .surfaceVariant
                        .withOpacity(0.14)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color:
                      Theme.of(context).colorScheme.outline.withOpacity(0.12),
                  width: 1,
                ),
              ),
              child: Text(
                _rows[i].name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    required double chartVisibleHeight,
    required double chartTotalWidth,
    required double chartTotalHeight,
    required double headerHeight,
    required double rowHeight,
  }) {
    return GestureDetector(
      onPanUpdate: (details) {
        if (_horizontalScrollController.hasClients) {
          final newHorizontalOffset =
              _horizontalScrollController.offset - details.delta.dx;

          _horizontalScrollController.jumpTo(
            newHorizontalOffset.clamp(
              _horizontalScrollController.position.minScrollExtent,
              _horizontalScrollController.position.maxScrollExtent,
            ),
          );
        }

        if (_verticalTasksScrollController.hasClients) {
          final newVerticalOffset =
              _verticalTasksScrollController.offset - details.delta.dy;

          _verticalTasksScrollController.jumpTo(
            newVerticalOffset.clamp(
              _verticalTasksScrollController.position.minScrollExtent,
              _verticalTasksScrollController.position.maxScrollExtent,
            ),
          );
        }
      },
      child: Container(
        width: chartContainerWidth,
        height: chartVisibleHeight + headerHeight,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(width: 1),
        ),
        child: SingleChildScrollView(
          controller: _horizontalScrollController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: chartTotalWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildChartHeaders(
                  chartTotalWidth,
                  headerHeight,
                ),
                SizedBox(
                  height: chartVisibleHeight,
                  child: SingleChildScrollView(
                    controller: _verticalTasksScrollController,
                    scrollDirection: Axis.vertical,
                    child: SizedBox(
                      height: chartTotalHeight,
                      width: chartTotalWidth,
                      child: Stack(
                        children: [
                          ..._buildRowBackgrounds(
                            chartTotalWidth,
                            chartTotalHeight,
                            rowHeight,
                          ),
                          ..._buildTaskBars(
                            chartTotalWidth,
                            rowHeight,
                          ),
                        ],
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

  Widget _buildChartHeaders(
    double chartWidth,
    double headerHeight,
  ) {
    final int totalDays = max(1, _totalDays);
    final double dayWidth = chartWidth / totalDays;
    final int hoursPerDay = max(1, endingHour - initialHour);

    return Container(
      height: headerHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF1B2433),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(8),
        ),
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade700,
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: List.generate(totalDays, (dayIndex) {
          final currentDate = _startDate.add(
            Duration(days: dayIndex),
          );

          final double hourWidth = dayWidth / hoursPerDay;

          final int labelStep = hourWidth >= 58
              ? 1
              : hourWidth >= 34
                  ? 2
                  : 4;

          return SizedBox(
            width: dayWidth,
            height: headerHeight,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      '${currentDate.day}/${currentDate.month}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Divider(
                    height: 1,
                    color: Colors.white24,
                  ),
                ),

                ...List.generate(hoursPerDay + 1, (hourIndex) {
                  final int hour = initialHour + hourIndex;
                  final double left = hourWidth * hourIndex;

                  final bool isDayStart = hourIndex == 0;
                  final bool isDayEnd = hourIndex == hoursPerDay;

                  final bool showLabel =
                      isDayStart || isDayEnd || hourIndex % labelStep == 0;

                  return Positioned(
                    left: left,
                    bottom: 0,
                    child: SizedBox(
                      width: isDayEnd ? 1 : hourWidth,
                      height: 48,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0,
                            bottom: 0,
                            child: Container(
                              width: isDayStart ? 2 : 1,
                              height: isDayStart ? 38 : 28,
                              color: Colors.grey.shade400,
                            ),
                          ),

                          if (showLabel)
                            Positioned(
                              left: isDayStart ? 4 : -22,
                              bottom: 4,
                              child: SizedBox(
                                width: 54,
                                child: Text(
                                  '${hour.toString().padLeft(2, '0')}:00',
                                  textAlign: isDayStart
                                      ? TextAlign.left
                                      : TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.visible,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        }),
      ),
    );
  }

  List<Widget> _buildRowBackgrounds(
    double chartWidth,
    double chartHeight,
    double rowHeight,
  ) {
    final double rowSpacing = 5.0;
    final double rowSlotHeight = rowHeight * _verticalZoom + rowSpacing;
    final List<Widget> backgrounds = [];

    for (int i = 0; i < _rows.length; i++) {
      backgrounds.add(
        Positioned(
          top: i * rowSlotHeight,
          left: 0,
          child: Container(
            width: chartWidth,
            height: rowSlotHeight,
            decoration: BoxDecoration(
              color: i.isEven ? Colors.white : Colors.grey.shade50,
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.shade300.withOpacity(0.3),
                  width: 0.8,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return backgrounds;
  }

  List<Widget> _buildTaskBars(
    double chartWidth,
    double rowHeight,
  ) {
    final double rowSpacing = 5.0;
    final double rowSlotHeight = rowHeight * _verticalZoom + rowSpacing;
    final bars = <Widget>[];

    for (int i = 0; i < _rows.length; i++) {
      final row = _rows[i];

      for (final task in row.tasks) {
        final int rowIndex = i;

        if (!_jobColor.containsKey(task.jobId)) {
          final random = Random();

          _jobColor[task.jobId] = Color.fromARGB(
            255,
            random.nextInt(160) + 60,
            random.nextInt(160) + 60,
            random.nextInt(160) + 60,
          );
        }

        final color = _jobColor[task.jobId]!;

        final double top = (rowIndex * rowSlotHeight) + (rowSpacing / 2);
        final double left = _calculateTaskLeft(task.startDate, chartWidth);
        final double right = _calculateTaskLeft(task.endDate, chartWidth);
        final double width = (right - left).clamp(1, chartWidth).toDouble();

        bars.add(
          Positioned(
            top: top,
            left: left,
            child: GestureDetector(
              onDoubleTap: () => _openTaskDialog(task),
              child: Container(
                width: width,
                height: rowHeight * _verticalZoom,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(1, 1),
                    ),
                  ],
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    task.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
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

  double _calculateTaskLeft(
    DateTime date,
    double chartWidth,
  ) {
    final int hoursPerDay = max(1, endingHour - initialHour);
    final int totalDisplayedMinutes = _totalDays * hoursPerDay * 60;

    final int dayIndex = date.difference(_startDate).inDays;

    final int clampedDayIndex = dayIndex < 0
        ? 0
        : dayIndex >= _totalDays
            ? _totalDays - 1
            : dayIndex;

    final int hour = date.hour;

    final int clampedHour = hour < initialHour
        ? initialHour
        : hour >= endingHour
            ? endingHour
            : hour;

    int minutePart = date.minute;

    if (hour < initialHour || hour >= endingHour) {
      minutePart = 0;
    }

    final int displayedMinutesSoFar =
        (clampedDayIndex * hoursPerDay * 60) +
            ((clampedHour - initialHour) * 60) +
            minutePart;

    final double fraction =
        (displayedMinutesSoFar / totalDisplayedMinutes).clamp(0.0, 1.0);

    return (fraction * chartWidth).clamp(0.0, chartWidth);
  }

  String _baseTaskName(String displayName) {
    final index = displayName.indexOf(' · Unidad ');

    if (index >= 0) {
      return displayName.substring(0, index);
    }

    return displayName;
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final result = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: _startDate,
        end: _endDate,
      ),
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

        _totalDays = max(
          1,
          _endDate.difference(_startDate).inDays + 1,
        );
      });
    }
  }

  void _showMetrics(
    Metrics metrics,
    BuildContext context,
  ) {
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
