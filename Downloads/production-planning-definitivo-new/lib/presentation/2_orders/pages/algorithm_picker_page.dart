import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_state.dart';

class AlgorithmPickerPage extends StatefulWidget {
  final int orderId;
  const AlgorithmPickerPage({Key? key, required this.orderId}) : super(key: key);


  @override
  State<AlgorithmPickerPage> createState() => _AlgorithmPickerPageState();
}

class _AlgorithmPickerPageState extends State<AlgorithmPickerPage> {
  late final GanttBloc _ganttBloc;
  final List<int> _selectedIndexes = [];
  bool _selectAll = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _ganttBloc = GetIt.instance<GanttBloc>();
    _ganttBloc.assignOrderId(widget.orderId);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

        ),
      );
      return;
    }

    // Retornar los índices seleccionados
    Navigator.pop(context, List<int>.from(_selectedIndexes));
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

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

            return Column(
              children: [
                // Header con información del ambiente
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.3),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                    ],
                  ),
                ),

                // Select All Checkbox
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
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
                    onChanged: (v) => _toggleSelectAll(v, rules.length),
                    activeColor: colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Lista de algoritmos
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: rules.length,
                    itemBuilder: (context, index) {
                      final rule = rules[index];
                      final isSelected = _selectedIndexes.contains(index);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primaryContainer.withOpacity(0.3)
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? colorScheme.primary.withOpacity(0.5)
                                : colorScheme.outlineVariant.withOpacity(0.5),
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
                            'Índice: $index',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          value: isSelected,
                          onChanged: (v) => _toggleSingle(index, v, rules.length),

                          activeColor: colorScheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    },
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
                  child: Row(
                    children: [
                      // Información de selección
                      Expanded(
                        child: Column(
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
                              Text(
                                'Algoritmos: ${_selectedIndexes.map((i) => i + 1).join(', ')}',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Botones
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
                        onPressed: _selectedIndexes.isEmpty ? null : _onCalculate,

                        icon: const Icon(Icons.calculate),
                        label: const Text('Calcular'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          backgroundColor: _selectedIndexes.isEmpty
                              ? colorScheme.surfaceVariant

                              : colorScheme.primary,
                          foregroundColor: _selectedIndexes.isEmpty
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

