import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_state.dart';
import 'add_job.dart';

class AddOrder extends StatelessWidget {

  List<TextEditingController>? priorityControllers;
  List<TextEditingController>? quantityControllers;

  AddOrder({
    required this.priorityControllers,
    required this.quantityControllers
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Crear Nueva Orden'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(

          children: [
            Expanded(
              child: ListView(
                children: [
                  AddJob(
                    priorityController: null,
                    quantityController: null,    
                    ), 
                  SizedBox(height: 16),
                  AddJob(
                    priorityController: null,
                    quantityController: null,                    
                    ), 
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {
                },
              child: Text('Agregar Secuencia'),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // Aquí irá la lógica para crear la orden
              },
              child: Text('Crear Orden'),
            ),
          ],
        ),
      ),
    );
  }
}