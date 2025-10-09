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


class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  late OrderBloc _orderBloc;

  @override
  void initState() {
    super.initState();
    _orderBloc = GetIt.instance.get<OrderBloc>();
    _orderBloc.fetchOrders();
  }

  @override
  void dispose() {
    _orderBloc.close();
    super.dispose();
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () async {
                          print("DEBUG: Navegando a NewOrderPage");
                          final result = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => BlocProvider<NewOrderBloc>(
                                create: (context) =>
                                    GetIt.instance.get<NewOrderBloc>(),
                                child: const NewOrderPage(),
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
                        child: const Text("Nuevo Programa de Producción"),
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
                    print("DEBUG: Órdenes cargadas: ${state.orders.length}");
                    return ListView.builder(
                      itemCount: state.orders.length,
                      itemBuilder: (context, index) {
                        final order = state.orders[index];
                        return Card(
                          margin: const EdgeInsets.all(8.0),
                          color: colorScheme.surfaceContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: colorScheme.outlineVariant.withOpacity(0.5)),
                          ),
                          shadowColor: colorScheme.shadow.withOpacity(0.1),
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Fecha: ${getDateFormat(order.regDate)}',
                                  style: TextStyle(
                                    fontSize: 18.0,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 8.0),
                                Text(
                                  'Jobs: ${order.orderJobs?.map((job) => job.sequence?.name ?? "No sequence").join(", ") ?? "No jobs"}',
                                  style: TextStyle(
                                    fontSize: 16.0,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8.0),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          getMetrics(context, state.orders[index].orderId!),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        backgroundColor: colorScheme.tertiary,
                                        foregroundColor: colorScheme.onTertiary,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: const Text("programar"),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete,
                                        color: colorScheme.error,
                                      ),
                                      onPressed: () =>
                                          _orderBloc.deleteOrderById(state.orders[index].orderId!),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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

}
