import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/orders_bloc/orders_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/orders_bloc/orders_event.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/orders_bloc/orders_state.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/pages/gantt_page_container.dart';
import 'package:production_planning/features/2_orders/presentation/pages/new_order_page.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: getAppBar(),
      body: BlocProvider(
        create: (context) => GetIt.instance.get<OrderBloc>()..add(FetchOrdersEvent()),
        child: Column(
          children: [
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => BlocProvider<NewOrderBloc>(
                        create: (context) => GetIt.instance.get<NewOrderBloc>(),
                        child: const NewOrderPage(),
                      ),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text("Nueva orden"),
              ),
            ),
            Expanded(
              child: BlocBuilder<OrderBloc, OrdersState>(
                builder: (context, state) {
                  if (state is OrdersLoadingState) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (state is OrdersLoadedState) {
                    return ListView.builder(
                      itemCount: state.orders.length,
                      itemBuilder: (context, index) {
                        final order = state.orders[index];
                        return Card(
                          margin: const EdgeInsets.all(8.0),
                          color: colorScheme.surfaceContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
                          ),
                          shadowColor: colorScheme.shadow.withOpacity(0.1),
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Fecha: ${order.regDate.toLocal()}',
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
                                      onPressed: () => planificate(context, state.orders[index].orderId!),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        backgroundColor: colorScheme.secondary,
                                        foregroundColor: colorScheme.onSecondary,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: const Text("Programar"),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete, color: colorScheme.error),
                                      onPressed: () => BlocProvider.of<OrderBloc>(context).add(DeleteOrder(state.orders[index].orderId!)),
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
                      "No orders available",
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
}
