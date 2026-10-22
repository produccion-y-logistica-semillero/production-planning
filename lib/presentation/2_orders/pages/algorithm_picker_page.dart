import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:dartz/dartz.dart' as dartz;

import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/route_draft.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/tabu_params.dart';
import 'package:production_planning/presentation/2_orders/widgets/low_order/tabu_params_dialog.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/graph_editor.dart';
import 'package:production_planning/services/sequences_service.dart';
import 'package:production_planning/services/orders_service.dart';
import 'package:production_planning/shared/dispatch_rule_info.dart';

import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_state.dart';

class AlgorithmPickerPage extends StatefulWidget {
  final int orderId;
  const AlgorithmPickerPage({super.key, required this.orderId});

  @override
  State<AlgorithmPickerPage> createState() => _AlgorithmPickerPageState();
}

class _AlgorithmPickerPageState extends State<AlgorithmPickerPage> {
  late final GanttBloc _ganttBloc;
  final List<int> _selectedIndexes = [];
  TabuParams? _tabuParams;
  bool _selectAll = false;
  bool _isLoading = true;

  /// The program being scheduled, to show its routes and jobs.
  OrderEntity? _order;

  @override
  void initState() {
    super.initState();
    _ganttBloc = GetIt.instance<GanttBloc>();
    _ganttBloc.assignOrderId(widget.orderId);
    GetIt.instance<OrdersService>().getFullOrder(widget.orderId).then((r) {
      if (!mounted) return;
      r.fold((_) {}, (order) => setState(() => _order = order));
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _labelForRule(dynamic rule, int index) {
    try {
      final v = rule?.value2;
      if (v != null && v.toString().isNotEmpty) {
        return v.toString();
      }
    } catch (_) {
      // Si no tiene value2, usar el fallback
    }
    return 'Algoritmo ${index + 1}';
  }

  String _ruleSummary(String code) =>
      dispatchRuleInfo(code)?.summary ?? 'Sin descripción disponible.';

  void _showRuleHelp(BuildContext context, String code) {
    final info = dispatchRuleInfo(code);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(info == null ? code : '${info.code} · ${info.title}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: info == null
              ? const Text('No hay una descripción para esta regla.')
              : _RuleHelpBody(info: info),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showAllRulesHelp(BuildContext context, List<String> codes) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guía de reglas de este ambiente'),
        content: SizedBox(
          width: 600,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final code in codes.toSet())
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    dispatchRuleInfo(code) == null
                        ? code
                        : '$code · ${dispatchRuleInfo(code)!.title}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(_ruleSummary(code)),
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  children: [
                    if (dispatchRuleInfo(code) != null)
                      _RuleHelpBody(info: dispatchRuleInfo(code)!),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _toggleSelectAll(bool? value, int rulesLength) {
    setState(() {
      _selectAll = value ?? false;
      _selectedIndexes.clear();
      if (_selectAll) {
        _selectedIndexes.addAll(List<int>.generate(rulesLength, (i) => i));
      }
    });
  }

  void _toggleSingle(int index, bool? value, int rulesLength) {
    setState(() {
      if (value == true) {
        if (!_selectedIndexes.contains(index)) {
          _selectedIndexes.add(index);
        }
      } else {
        _selectedIndexes.remove(index);
      }
      _selectAll = _selectedIndexes.length == rulesLength && rulesLength > 0;
    });
  }

  Future<void> _configureTabu() async {
    final params = await showDialog<TabuParams>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TabuParamsDialog(
        initial: _tabuParams ?? const TabuParams(),
      ),
    );
    if (params == null) return; // canceló
    setState(() => _tabuParams = params);
  }

  void _onCalculate() {
    if (_selectedIndexes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.white),
              SizedBox(width: 12),
              Text('Debe seleccionar al menos un algoritmo'),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    // Retornar los índices seleccionados
    Navigator.pop(
      context,
      dartz.Tuple2<List<int>, TabuParams?>(
        List<int>.from(_selectedIndexes),
        _tabuParams,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Seleccionar Algoritmos',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: BlocListener<GanttBloc, GanttState>(
        bloc: _ganttBloc,
        listener: (context, state) {
          if (state is GanttOrderRetrieved ||
              state is GanttPlanningSuccess ||
              state is GanttPlanningError ||
              state is GanttPlanningLoading) {
            if (_isLoading) {
              setState(() {
                _isLoading = false;
              });
            }
          } else if (state is GanttOrderRetrieveError) {
            if (_isLoading) {
              setState(() {
                _isLoading = false;
              });
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Error al cargar los algoritmos'),
                backgroundColor: colorScheme.error,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        },
        child: BlocBuilder<GanttBloc, GanttState>(
          bloc: _ganttBloc,
          builder: (context, state) {
            if (_isLoading) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Cargando algoritmos...',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              );
            }

            final env = state.enviroment;
            if (env != null) {
              // Log rules for debugging
              try {
                print(
                    'DEBUG: AlgorithmPickerPage env.rules.length=${env.rules.length}');
              } catch (_) {}
            }
            if (env == null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No se pudo cargar el entorno',
                      style: TextStyle(
                        color: colorScheme.error,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _ganttBloc.assignOrderId(widget.orderId),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              );
            }
            final List<dynamic> rules = (env.rules ?? []) as List<dynamic>;

            if (rules.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'No hay algoritmos disponibles',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }

            // Mantener consistencia en las selecciones
            _selectedIndexes.removeWhere((i) => i < 0 || i >= rules.length);
            if (_selectedIndexes.length != rules.length) {
              _selectAll = false;
            }

            // Everything above the action bar scrolls as ONE list: the header,
            // the program summary (which can be expanded) and the rules. It
            // used to be a fixed column with only the rules list flexible,
            // so on a short window (tablet, phone) or with the summary open
            // the fixed parts alone were taller than the screen and the page
            // overflowed at the bottom.
            return Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          children: [
                            // Header con información del ambiente
                            Container(
                              margin: const EdgeInsets.all(16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer
                                    .withOpacity(0.3),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colorScheme.primaryContainer,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Orden ID: ${widget.orderId}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                        Text(
                                          'Ambiente: ${env.name}',
                                          style: TextStyle(
                                            color: colorScheme.onSurfaceVariant,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _showAllRulesHelp(
                                        context, [
                                      for (int i = 0; i < rules.length; i++)
                                        _labelForRule(rules[i], i)
                                    ]),
                                    icon: const Icon(Icons.menu_book_outlined),
                                    label: const Text('Guía de reglas'),
                                  ),
                                ],
                              ),
                            ),

                            // Rutas y jobs del programa
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: _ProgramSummary(order: _order),
                            ),

                            // Select All Checkbox
                            Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                              child: CheckboxListTile(
                                title: Text(
                                  'Seleccionar todos',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                subtitle: Text(
                                  '${rules.length} algoritmos disponibles',
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                                value: _selectAll,
                                onChanged: (v) =>
                                    _toggleSelectAll(v, rules.length),
                                activeColor: colorScheme.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),
                          ],
                        ),
                      ),

                      // Lista de algoritmos
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList.builder(
                          itemCount: rules.length,
                          itemBuilder: (context, index) {
                            final rule = rules[index];
                            final isSelected = _selectedIndexes.contains(index);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? colorScheme.primaryContainer
                                        .withOpacity(0.3)
                                    : colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? colorScheme.primary.withOpacity(0.5)
                                      : colorScheme.outlineVariant
                                          .withOpacity(0.5),
                                ),
                              ),
                              child: CheckboxListTile(
                                title: Text(
                                  _labelForRule(rule, index),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: isSelected
                                        ? colorScheme.primary
                                        : colorScheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  _ruleSummary(_labelForRule(rule, index)),
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                                secondary: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_labelForRule(rule, index)
                                                .toUpperCase() ==
                                            'TABU' &&
                                        env.name.toUpperCase() ==
                                            'PARALLEL MACHINES')
                                      IconButton(
                                        icon: Icon(
                                          Icons.tune,
                                          color: _tabuParams == null
                                              ? colorScheme.onSurfaceVariant
                                              : colorScheme.primary,
                                        ),
                                        tooltip: _tabuParams == null
                                            ? 'Configurar parametros (usando valores por defecto)'
                                            : 'Parametros personalizados activos',
                                        onPressed: _configureTabu,
                                      ),
                                    IconButton(
                                      tooltip: '¿Cómo funciona esta regla?',
                                      icon: Icon(Icons.help_outline,
                                          color: colorScheme.primary),
                                      onPressed: () => _showRuleHelp(
                                          context, _labelForRule(rule, index)),
                                    ),
                                  ],
                                ),
                                value: isSelected,
                                onChanged: (v) =>
                                    _toggleSingle(index, v, rules.length),
                                activeColor: colorScheme.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Botones de acción
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  // Narrow window: the selection summary on top and the
                  // buttons below, instead of squeezing all three into one
                  // line.
                  child: LayoutBuilder(builder: (context, c) {
                    final narrow = c.maxWidth < 520;
                    // Información de selección
                    final info = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Seleccionados: ${_selectedIndexes.length}/${rules.length}',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_selectedIndexes.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          // Rule names (EDD, LPT, WSPT...), in list order,
                          // instead of their position numbers.
                          Builder(builder: (context) {
                            final names = ([..._selectedIndexes]..sort())
                                .map((i) => _labelForRule(rules[i], i))
                                .join(', ');
                            return Tooltip(
                              message: names,
                              child: Text(
                                'Algoritmos: $names',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    );
                    // Botones
                    final buttons = <Widget>[
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed:
                            _selectedIndexes.isEmpty ? null : _onCalculate,
                        icon: const Icon(Icons.calculate),
                        label: const Text('Calcular'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          backgroundColor: _selectedIndexes.isEmpty
                              ? colorScheme.surfaceContainerHighest
                              : colorScheme.primary,
                          foregroundColor: _selectedIndexes.isEmpty
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ];
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          info,
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: buttons,
                          ),
                        ],
                      );
                    }
                    return Row(children: [
                      Expanded(child: info),
                      const SizedBox(width: 16),
                      ...buttons,
                    ]);
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Explanation of one rule: what it does, how it decides, when to use it.
class _RuleHelpBody extends StatelessWidget {
  final DispatchRuleInfo info;
  const _RuleHelpBody({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String label, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 2),
              Text(text),
            ],
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Chip(label: Text(info.kind), visualDensity: VisualDensity.compact),
        const SizedBox(height: 8),
        section('Qué hace', info.summary),
        section('Cómo decide', info.howItWorks),
        section('Útil para', info.goodFor),
      ],
    );
  }
}

/// The routes and jobs of the program being scheduled.
class _ProgramSummary extends StatelessWidget {
  final OrderEntity? order;
  const _ProgramSummary({required this.order});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final jobs = order?.orderJobs ?? const [];
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

    // Route -> number of jobs that use it, and the route's id (for the
    // preview).
    final routes = <String, int>{};
    final routeIds = <String, int?>{};
    for (final job in jobs) {
      final name = job.sequence?.name ?? 'Ruta sin nombre';
      routes[name] = (routes[name] ?? 0) + 1;
      routeIds[name] ??= job.sequence?.id;
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.list_alt, color: colorScheme.primary),
        title: const Text('Contenido del programa',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(order == null
            ? 'Cargando…'
            : '${jobs.length} ${jobs.length == 1 ? 'job' : 'jobs'} · '
                '${routes.length} ${routes.length == 1 ? 'ruta' : 'rutas'} '
                'de proceso'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rutas de proceso',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: colorScheme.primary)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final e in routes.entries)
                Tooltip(
                  message: 'Ver ruta',
                  child: ActionChip(
                    avatar: Icon(Icons.account_tree_outlined,
                        size: 16, color: colorScheme.primary),
                    label: Text(
                        '${e.key} (${e.value} ${e.value == 1 ? 'job' : 'jobs'})'),
                    onPressed: routeIds[e.key] == null
                        ? null
                        : () => showDialog<void>(
                              context: context,
                              builder: (_) => _RoutePreviewDialog(
                                sequenceId: routeIds[e.key]!,
                                name: e.key,
                              ),
                            ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Jobs',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: colorScheme.primary)),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 32,
                  dataRowMinHeight: 28,
                  dataRowMaxHeight: 32,
                  columns: const [
                    DataColumn(label: Text('Job')),
                    DataColumn(label: Text('Ruta')),
                    DataColumn(label: Text('Prioridad'), numeric: true),
                    DataColumn(label: Text('Disponible')),
                    DataColumn(label: Text('Entrega')),
                  ],
                  rows: [
                    for (final job in jobs)
                      DataRow(cells: [
                        DataCell(Text(job.jobName ?? 'Job ${job.jobId}')),
                        DataCell(Text(job.sequence?.name ?? '—')),
                        DataCell(Text('${job.priority}')),
                        DataCell(Text(dateFmt.format(job.availableDate))),
                        DataCell(Text(dateFmt.format(job.dueDate))),
                      ]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only view of a process route: its graph, which can be panned and
/// zoomed but not edited.
class _RoutePreviewDialog extends StatelessWidget {
  final int sequenceId;
  final String name;
  const _RoutePreviewDialog({required this.sequenceId, required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FutureBuilder(
            // The route's own record: it carries the station names, which the
            // copy inside each job does not always have.
            future:
                GetIt.instance<SequencesService>().getFullSequence(sequenceId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final SequenceEntity? route =
                  snapshot.data!.fold((_) => null, (r) => r);
              final draft =
                  route == null ? null : RouteDraft.fromSequence(route);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_tree_outlined,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            if (draft != null)
                              Text(
                                '${draft.nodes.length} estaciones · '
                                '${draft.arrows.length} precedencias · '
                                'solo lectura',
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: draft == null
                        ? const Center(
                            child: Text('No se pudo cargar la ruta.'))
                        : NodeEditor(readOnly: true, initialDraft: draft),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
