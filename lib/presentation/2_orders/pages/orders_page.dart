import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/presentation/2_orders/bloc/orders_bloc/orders_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/orders_bloc/orders_state.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/presentation/2_orders/pages/gantt_page_container.dart';
import 'package:production_planning/presentation/2_orders/pages/new_order_page.dart';
import 'package:production_planning/presentation/2_orders/pages/order_metrics_page.dart';
import 'package:production_planning/shared/functions/functions.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';
import 'package:production_planning/presentation/2_orders/pages/algorithm_picker_page.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/presentation/2_orders/order_filter.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  late OrderBloc _orderBloc;

  // Search and filters
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _environment;
  String? _route;

  @override
  void initState() {
    super.initState();
    _orderBloc = GetIt.instance.get<OrderBloc>();
    _orderBloc.fetchOrders();
  }

  @override
  void dispose() {
    _orderBloc.close();
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasFilters =>
      _query.isNotEmpty || _environment != null || _route != null;

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _query = '';
      _environment = null;
      _route = null;
    });
  }

  /// Search box, environment and route filters, and how many programs show.
  Widget _buildFilterBar(
    ColorScheme colorScheme, {
    required List<String> environmentOptions,
    required List<String> routeOptions,
    required String? environment,
    required String? route,
    required int shown,
    required int total,
    required bool environmentsLoading,
  }) {
    InputDecoration box(String label, IconData icon) => InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
          isDense: true,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 340,
                child: TextField(
                  controller: _searchController,
                  decoration: box('Buscar por job, ruta o número', Icons.search)
                      .copyWith(
                    hintText: 'Ej.: Pan integral, Lote 3, #12',
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Borrar búsqueda',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() {
                              _searchController.clear();
                              _query = '';
                            }),
                          ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String?>(
                  value: environment,
                  isExpanded: true,
                  decoration: box(
                      environmentsLoading ? 'Ambiente (calculando…)' : 'Ambiente',
                      Icons.factory_outlined),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Todos los ambientes')),
                    for (final e in environmentOptions)
                      DropdownMenuItem<String?>(value: e, child: Text(e)),
                  ],
                  onChanged: (v) => setState(() => _environment = v),
                ),
              ),
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String?>(
                  value: route,
                  isExpanded: true,
                  decoration: box('Ruta de proceso', Icons.account_tree_outlined),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Todas las rutas')),
                    for (final r in routeOptions)
                      DropdownMenuItem<String?>(
                          value: r,
                          child: Text(r, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _route = v),
                ),
              ),
              if (_hasFilters)
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Limpiar filtros'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _hasFilters
                ? 'Mostrando $shown de $total programas'
                : '$total programas',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// One program: its jobs, date, environment and routes, and its actions.
  Widget _buildOrderCard(BuildContext context, ColorScheme colorScheme,
      OrderEntity order, String? environment) {
    final routes = routeNamesOf(order);
    return Card(
      margin: const EdgeInsets.all(8.0),
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      shadowColor: colorScheme.shadow.withValues(alpha: 0.1),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Jobs: ${order.orderJobs?.map((job) => job.jobName ?? "Job ${job.jobId}").join(", ") ?? "No jobs"}',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8.0),
            Text(
              'Programa #${order.orderId} · Fecha: ${getDateFormat(order.regDate)}',
              style: TextStyle(
                fontSize: 14.0,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (environment != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.factory_outlined, size: 16),
                    label: Text(environment),
                  ),
                for (final r in routes)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.account_tree_outlined, size: 16),
                    label: Text(r),
                  ),
              ],
            ),
            const SizedBox(height: 8.0),
            // Wrap, not Row: on a narrow screen the actions go to a second
            // line instead of overflowing.
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () => getMetrics(context, order.orderId!),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    backgroundColor: colorScheme.tertiary,
                    foregroundColor: colorScheme.onTertiary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text("programar"),
                ),
                IconButton(
                  icon: Icon(Icons.edit, color: colorScheme.secondary),
                  onPressed: () => _editOrder(context, order.orderId!),
                ),
                IconButton(
                  icon: Icon(Icons.copy, color: colorScheme.primary),
                  onPressed: () => _orderBloc.duplicateOrder(order.orderId!),
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: colorScheme.error),
                  onPressed: () => _orderBloc.deleteOrderById(order.orderId!),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: getAppBar(),
      body: BlocProvider.value(
        value: _orderBloc,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => printInfo(
                    context,
                    title: 'Ordenes',
                    content:
                    'Una orden es sobre lo que se realiza la planificación de producción... \n\nUna orden puede referirse a que se requiere producir 100 panes para dentro de 5 días...',

                  ),
                  icon: const Icon(Icons.info),
                ),
                Expanded(
                  flex: 1,
                  // Wrap (not Row) hands the button the available width, so
                  // on a phone its label breaks into two lines instead of
                  // overflowing.
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () async {
                          print("DEBUG: Navegando a NewOrderPage");

                          final result = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => BlocProvider<NewOrderBloc>(
                                create: (context) =>
                                    GetIt.instance.get<NewOrderBloc>(),
                                child: const NewOrderPage(editOrderId: null),
                              ),
                            ),
                          );
                          print("DEBUG: Regreso de NewOrderPage con resultado: $result");
                          print("DEBUG: Context mounted: ${context.mounted}");

                          if (result == true && context.mounted) {
                            _orderBloc.fetchOrders(); // <--- refrescar lista
                          } else {
                          }

                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text("Nuevo Programa de Producción",
                            textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Expanded(
              child: BlocBuilder<OrderBloc, OrdersState>(
                builder: (context, state) {
                  print("DEBUG: OrdersState actual: ${state.runtimeType}");
                  if (state is OrdersLoadingState) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (state is OrdersLoadedState) {
                    final environments = state.environments;
                    final environmentOptions = environments.values.toSet().toList()
                      ..sort();
                    final routeOptions = <String>{
                      for (final o in state.orders) ...routeNamesOf(o),
                    }.toList()
                      ..sort((a, b) => normalizeForSearch(a)
                          .compareTo(normalizeForSearch(b)));
                    // A filter whose value disappeared (e.g. its last order
                    // was deleted) no longer applies.
                    final String? environment =
                        environmentOptions.contains(_environment)
                            ? _environment
                            : null;
                    final String? route =
                        routeOptions.contains(_route) ? _route : null;
                    final filtered = filterOrders(
                      state.orders,
                      environments,
                      query: _query,
                      environment: environment,
                      route: route,
                    );

                    return Column(
                      children: [
                        _buildFilterBar(
                          colorScheme,
                          environmentOptions: environmentOptions,
                          routeOptions: routeOptions,
                          environment: environment,
                          route: route,
                          shown: filtered.length,
                          total: state.orders.length,
                          environmentsLoading: environments.isEmpty &&
                              state.orders.isNotEmpty,
                        ),
                        Expanded(
                          child: filtered.isEmpty
                              ? Center(
                                  child: Text(
                                    state.orders.isEmpty
                                        ? 'No hay programas de producción'
                                        : 'Ningún programa coincide con la búsqueda',
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 16,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) => _buildOrderCard(
                                    context,
                                    colorScheme,
                                    filtered[index],
                                    environments[filtered[index].orderId],
                                  ),
                                ),
                        ),
                      ],
                    );
                  } else if (state is OrdersErrorState) {
                    return Center(
                      child: Text(
                        state.message,
                        style: TextStyle(
                          color: colorScheme.error,
                          fontSize: 16,
                        ),
                      ),
                    );
                  }
                  return Center(
                    child: Text(
                      "No hay órdenes disponibles",
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void planificate(BuildContext context, int id) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GanttPageContainer(orderId: id),
      ),
    );
  }

  Future<void> getMetrics(BuildContext context, int id) async {
    final selected = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(
        builder: (_) => AlgorithmPickerPage(orderId: id),
      ),
    );

    if (selected != null && selected.isNotEmpty) {

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderMetrics(
            orderId: id,
            selectedRuleIndexes: selected,
          ),
        ),
      );
    }
  }

  Future<void> _editOrder(BuildContext context, int id) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BlocProvider<NewOrderBloc>(
          create: (context) => GetIt.instance.get<NewOrderBloc>(),
          child: NewOrderPage(editOrderId: id),
        ),
      ),
    );
    if (result == true && context.mounted) {
      _orderBloc.fetchOrders();
    }
  }
}
