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

  /// Color shown as a dot next to this row's name — the machine's color in
  /// "Por Máquina" view, the job's color in "Por Job" view. Null only when
  /// the row somehow has no resolvable color.
  final Color? accentColor;

  const _GanttRow({
    required this.name,
    required this.tasks,
    this.accentColor,
  });
}

/// One task segment placed at its pixel position within a Gantt row, used to
/// figure out how much free space follows it before the next segment starts.
class _PositionedSegment {
  final PlanningTaskEntity task;
  final String label;
  final double left;
  final double right;

  /// True for a sequence-dependent setup/changeover block that runs right
  /// before the task's own processing — rendered with no fill and diagonal
  /// stripes in the job's own color, so it reads as "preparing the machine
  /// for this job" while never being mistaken for actual processing time.
  final bool isSetup;

  const _PositionedSegment({
    required this.task,
    required this.label,
    required this.left,
    required this.right,
    this.isSetup = false,
  });
}

/// Paints evenly-spaced diagonal stripes across the widget's bounds, used to
/// mark setup/changeover bars as visually distinct from the solid job
/// processing bars they share a color with.
class _DiagonalStripesPainter extends CustomPainter {
  final Color stripeColor;
  final double spacing;
  final double strokeWidth;

  const _DiagonalStripesPainter({
    required this.stripeColor,
    this.spacing = 8.0,
    this.strokeWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = stripeColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // Diagonal lines at 45°, spaced evenly, spanning wide enough that the
    // clip (applied by the caller) covers the whole bar regardless of its
    // width — walk an offset from -size.height to size.width.
    for (double x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DiagonalStripesPainter oldDelegate) =>
      oldDelegate.stripeColor != stripeColor ||
      oldDelegate.spacing != spacing ||
      oldDelegate.strokeWidth != strokeWidth;
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

  /// Job color, keyed by jobId. Seeded from the jobId itself (see
  /// [_assignJobColors]) so the same job keeps the same color across
  /// rebuilds and across the side-by-side charts in gantt_page_container.
  final Map<int, Color> _jobColor = {};

  /// Machine color, keyed by machineName — shown as a dot beside the row
  /// name so each machine has a stable visual identity. Assigned by the
  /// machine's position in [GanttChart.machines], not by a hash, so two
  /// charts compared side by side agree.
  final Map<String, Color> _machineColor = {};

  /// Fixed, mutually distinguishable colors handed out to machines in order.
  static const List<Color> _machinePalette = [
    Color(0xFF1E88E5), // azul
    Color(0xFFE65100), // naranja
    Color(0xFF2E7D32), // verde
    Color(0xFF6A1B9A), // morado
    Color(0xFFC62828), // rojo
    Color(0xFF00838F), // cian
    Color(0xFF8D6E63), // café
    Color(0xFFAD1457), // magenta
    Color(0xFF558B2F), // oliva
    Color(0xFF4527A0), // índigo
  ];

  int? _selectedRule;

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

    _assignMachineColors();
    _assignJobColors();

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

  /// Hands each machine a color from [_machinePalette] following the order
  /// they arrive in, so the assignment is deterministic: the same machine
  /// gets the same color on every rebuild and in every chart on screen.
  void _assignMachineColors() {
    for (int i = 0; i < widget.machines.length; i++) {
      _machineColor[widget.machines[i].machineName] =
          _machinePalette[i % _machinePalette.length];
    }
  }

  /// Precomputes every job's color up front, seeding the generator with the
  /// jobId itself. Doing it here rather than lazily while painting bars
  /// matters for two reasons: the row-name panel is built before the bars in
  /// the same frame and needs the color already resolved, and seeding keeps
  /// a job's color identical across the charts that gantt_page_container
  /// places side by side.
  void _assignJobColors() {
    for (final machine in widget.machines) {
      for (final task in machine.tasks) {
        _jobColor.putIfAbsent(task.jobId, () {
          final random = Random(task.jobId);

          return Color.fromARGB(
            255,
            random.nextInt(160) + 60,
            random.nextInt(160) + 60,
            random.nextInt(160) + 60,
          );
        });
      }
    }
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

        // startDate is the start of *processing*: a task's setup block runs
        // before it, so it can fall outside the range startDate/endDate
        // describe. Without this the earliest setup bar would be clamped
        // onto the first displayed day instead of drawn where it belongs.
        for (final setupSegment in task.setupSegments) {
          if (setupSegment.start.isBefore(earliest!)) {
            earliest = setupSegment.start;
          }
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
          accentColor: _machineColor[machine.machineName],
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
          name: label,
          tasks: tasks,
          accentColor: _jobColor[entry.key],
        );
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use the space this widget was actually given by its parent, not the
    // full app window — MediaQuery.size reports the whole window regardless
    // of how narrow the space allotted to this chart really is (e.g. when
    // gantt_page_container.dart places 2+ charts side by side via Expanded),
    // which previously caused this chart to lay out far wider than it fit
    // and overflow.
    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth;
        final double availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.of(context).size.height;

        const double rowLabelWidth = 220.0;
        const double rowHeight = 40.0;
        const double rowSpacing = 5.0;
        const double rowHeaderHeight = 76.0;

        final double rowSlotHeight = rowHeight * _verticalZoom + rowSpacing;

        final double chartContainerWidth =
            max(availableWidth - rowLabelWidth - 72, 620).toDouble();

        final double chartTotalHeight =
            max(_rows.length * rowSlotHeight, 280.0).toDouble();

        final double chartRowsVisibleHeight = max(
          min(chartTotalHeight, availableHeight * 0.72).toDouble(),
          320.0,
        ).toDouble();

        final double chartTotalWidth =
            max(chartContainerWidth * _horizontalZoom, chartContainerWidth);

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
      },
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          children: [
            const Text('Zoom Horizontal: ', style: TextStyle(fontSize: 12)),
            SizedBox(
              width: 220,
              child: Slider(
                value: _horizontalZoom,
                min: 0.8,
                max: 24.0,
                divisions: 72,
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
                        .surfaceContainerHighest
                        .withOpacity(0.14)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color:
                      Theme.of(context).colorScheme.outline.withOpacity(0.12),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  if (_rows[i].accentColor != null) ...[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _rows[i].accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  // Expanded so the name still gets a bounded width and its
                  // ellipsis overflow keeps working next to the dot.
                  Expanded(
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
                ],
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
        // +2 accounts for the 1px border on top and bottom: BoxDecoration
        // insets the child by the border width, so without this the inner
        // Column (sized to exactly chartVisibleHeight + headerHeight)
        // overflows by the border's total vertical width.
        height: chartVisibleHeight + headerHeight + 2,
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
    const double rowSpacing = 5.0;
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
    const double rowSpacing = 5.0;
    final double rowSlotHeight = rowHeight * _verticalZoom + rowSpacing;
    final bars = <Widget>[];

    // Font grows with horizontal zoom (base 12px at the default 1.8x zoom)
    // instead of staying fixed, so zooming in actually makes labels easier
    // to read rather than just making bars wider around static-size text.
    final double taskLabelFontSize =
        (12.0 * (_horizontalZoom / 1.8)).clamp(10.0, 28.0);

    // A short segment (e.g. a 5-minute job on a multi-day timeline) renders
    // too narrow for FittedBox to keep its label readable — FittedBox only
    // ever shrinks text to fit, it never lets the label be seen at a normal
    // size. Below this width we stop trying to cram the name inside the bar
    // and print it just to the right instead, at a fixed readable size.
    const double insideLabelMinWidth = 70.0;
    const double minBarWidth = 10.0;
    const double externalLabelGap = 4.0;

    for (int i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final int rowIndex = i;
      final double top = (rowIndex * rowSlotHeight) + (rowSpacing / 2);

      // Flatten every (task, segment) in this row — both processing and
      // setup/changeover segments — and sort by start position, so each
      // segment knows how much free space precedes the next one — needed
      // to size/clip an external label without overlapping it.
      final List<_PositionedSegment> rowSegments = [];
      for (final task in row.tasks) {
        for (final setupSegment in task.setupSegments) {
          final double left =
              _calculateTaskLeft(setupSegment.start, chartWidth);
          final double right = _calculateTaskLeft(setupSegment.end, chartWidth);
          rowSegments.add(_PositionedSegment(
            task: task,
            label: 'Alistamiento — ${task.machineName}',
            left: left,
            right: right,
            isSetup: true,
          ));
        }

        final bool isSegmented = task.segments.length > 1;
        for (int segIndex = 0; segIndex < task.segments.length; segIndex++) {
          final segment = task.segments[segIndex];
          final double left = _calculateTaskLeft(segment.start, chartWidth);
          final double right = _calculateTaskLeft(segment.end, chartWidth);
          rowSegments.add(_PositionedSegment(
            task: task,
            label: isSegmented
                ? '${task.displayName} (${segIndex + 1}/${task.segments.length})'
                : task.displayName,
            left: left,
            right: right,
          ));
        }
      }
      rowSegments.sort((a, b) => a.left.compareTo(b.left));

      for (int s = 0; s < rowSegments.length; s++) {
        final ps = rowSegments[s];
        final task = ps.task;

        // Colors are precomputed in _assignJobColors, but fall back to a
        // neutral grey rather than throwing if a task somehow wasn't seen
        // there (e.g. a machine list mutated after initState).
        final Color jobColor = _jobColor[task.jobId] ?? Colors.blueGrey;

        // A setup/changeover block is painted with no fill at all and only
        // diagonal stripes in its job's color: it stays tied to the job the
        // machine is being prepared for, while the empty background makes it
        // impossible to confuse with the solid bar of actual processing.
        final bool isSegmented = !ps.isSetup && task.segments.length > 1;

        final double width =
            (ps.right - ps.left).clamp(minBarWidth, chartWidth).toDouble();
        final double nextLeft =
            s + 1 < rowSegments.length ? rowSegments[s + 1].left : chartWidth;
        final double externalLabelWidth =
            (nextLeft - (ps.left + width) - externalLabelGap)
                .clamp(0.0, 240.0)
                .toDouble();
        final bool labelFitsInside = width >= insideLabelMinWidth;

        final Widget insideLabel = FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text(
            ps.label,
            style: TextStyle(
              // A setup bar has no fill, so white text on it would sit on
              // the light row background and disappear — use the job's own
              // color, which is dark enough to read there.
              color: ps.isSetup ? jobColor : Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: taskLabelFontSize,
            ),
          ),
        );

        // One bar per processing segment, so a task paused by a work-shift
        // boundary, scheduled maintenance, or the rest cap visibly shows the
        // gap instead of rendering as one continuous bar over the pause.
        bars.add(
          Positioned(
            top: top,
            left: ps.left,
            child: GestureDetector(
              onDoubleTap: () => _openTaskDialog(task),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: width,
                    height: rowHeight * _verticalZoom,
                    decoration: BoxDecoration(
                      color: ps.isSetup ? Colors.transparent : jobColor,
                      borderRadius: BorderRadius.circular(6),
                      border: ps.isSetup
                          ? Border.all(color: jobColor, width: 1.5)
                          : isSegmented
                              ? Border.all(color: Colors.white, width: 1)
                              : null,
                      // No shadow behind a setup bar: it would paint a solid
                      // block under the transparent fill and defeat the
                      // whole point of leaving the background showing.
                      boxShadow: ps.isSetup
                          ? null
                          : const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(1, 1),
                              ),
                            ],
                    ),
                    alignment: Alignment.centerLeft,
                    // Setup bars take no padding here: it would inset the
                    // ClipRRect below and leave the stripes short of the
                    // bar's ends — plainly visible now that there is no fill
                    // covering the gap. Their label is inset by its own
                    // Padding inside the stack instead.
                    padding: labelFitsInside && !ps.isSetup
                        ? const EdgeInsets.symmetric(horizontal: 10)
                        : EdgeInsets.zero,
                    child: ps.isSetup
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CustomPaint(
                                  painter: _DiagonalStripesPainter(
                                    stripeColor: jobColor,
                                    spacing: 7,
                                    strokeWidth: 1.5,
                                  ),
                                ),
                                if (labelFitsInside)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: insideLabel,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : (labelFitsInside ? insideLabel : null),
                  ),
                  if (!labelFitsInside && externalLabelWidth > 12)
                    Padding(
                      padding: const EdgeInsets.only(left: externalLabelGap),
                      child: SizedBox(
                        width: externalLabelWidth,
                        child: Text(
                          ps.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ps.isSetup ? jobColor : Colors.black87,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
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

    final int displayedMinutesSoFar = (clampedDayIndex * hoursPerDay * 60) +
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
