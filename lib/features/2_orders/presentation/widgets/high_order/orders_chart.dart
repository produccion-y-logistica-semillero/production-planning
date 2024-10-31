import 'package:flutter/material.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';

class OrdersScreen extends StatelessWidget {
  final List<OrderEntity> orders;

  const OrdersScreen({required this.orders});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: Colors.blue, // Fondo del AppBar azul
      ),
      body: Container(
        color: Colors.white, // Fondo blanco
        padding: const EdgeInsets.all(16.0),
        child: ListView.builder(
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return Card(
              color: Colors.grey[200], // Color de tarjeta gris claro
              margin: const EdgeInsets.symmetric(vertical: 10.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order Date: ${order.regDate.toLocal()}',
                      style: const TextStyle(
                        fontSize: 18.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue, // Texto del título en azul
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Jobs: ${order.orderJobs?.map((job) => job.sequence?.name ?? 'Sin nombre').join(', ') ?? 'No jobs'}',
                      style: const TextStyle(fontSize: 16.0),
                    ),

                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        // Acción del botón
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue, // Botón azul
                      ),
                      child: const Text('View Details'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
