import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/orders_bloc/orders_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/orders_bloc/orders_event.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/orders_bloc/orders_state.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/pages/gantt_page.dart';
import 'package:production_planning/features/2_orders/presentation/pages/gantt_page_container.dart';
import 'package:production_planning/features/2_orders/presentation/pages/new_order_page.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
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
                child: const Text("nueva orden"),
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
                          color: Colors.grey[200],
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Fecha: ${order.regDate.toLocal()}',
                                  style: const TextStyle(
                                    fontSize: 18.0,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(height: 8.0),
                                Text(
                                  'Jobs: ${order.orderJobs?.map((job) => job.sequence?.name ?? "No sequence").join(", ") ?? "No jobs"}',
                                  style: const TextStyle(fontSize: 16.0),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    TextButton(
                                      onPressed: ()=> planificate(context, state.orders[index].orderId!), 
                                      child: const Text("Programar")
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red,),
                                      onPressed: ()=>BlocProvider.of<OrderBloc>(context).add(DeleteOrder(state.orders[index].orderId!)), 
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  } else if (state is OrdersErrorState) {
                    return Center(child: Text(state.message));
                  }
                  return const Center(child: Text("No orders available"));
                },
              ),
            )
    
          ],
        ),
      ),
    );
  }


  void planificate(BuildContext context, int id){
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GanttPageContainer(orderId: id),
      ),
    );
  }
}
