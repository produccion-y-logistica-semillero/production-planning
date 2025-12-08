import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_state.dart';
import 'package:production_planning/presentation/2_orders/widgets/high_order/add_job.dart';
import 'package:production_planning/shared/functions/functions.dart';

class NewOrderPage extends StatelessWidget {
  const NewOrderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear Nuevo Programa de Produccion'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: BlocListener<NewOrderBloc, NewOrderState>(
          listener: (context, state) {
            if (state is NewOrdersState) {
              if (state.justSaved != null) {
                showDialog(
                  context: context,
                  barrierDismissible: false, // Evitar cerrar accidentalmente
                  builder: (subcontext) {
                    return AlertDialog(
                      title: Text(
                        state.justSaved! ? "Guardado!!" : "Error",
                        style: TextStyle(
                            color: state.justSaved!
                                ? colorScheme.primary
                                : colorScheme.error),
                      ),
                      content: Text(
                        state.justSaved!
                            ? "La orden ha sido guardada exitosamente"
                            : "Hubo un error guardando la orden",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(subcontext).pop(); // cierra el diálogo
                            // Siempre regresar con el resultado del guardado

                            Navigator.of(context).pop(state.justSaved);
                          },
                          child: const Text("OK"),
                        ),
                      ],
                    );
                  },
                );
              }
            }
          },
          child: BlocBuilder<NewOrderBloc, NewOrderState>(
            builder: (context, state) {
              final provider = BlocProvider.of<NewOrderBloc>(context);
              List<AddJobWidget> widgets = [];
              if (state is NewOrdersInitialState) {
                provider.retrieveSequences();
                return const Center(child: CircularProgressIndicator());
              }
              if (state is NewOrdersState) {
                widgets = state.jobs;
              }

              return Center(
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                            onPressed: () => printInfo(context,
                                title: 'Crear orden',
                                content:
                                    'La creacion de una orden implica seleccionar los productos que deben ser fabricados, la prioridad que se tiene para fabricarlos, desde cuando se tiene la disponibilidad para fabricarlos (por ejemplo, por insumos), y cual es la fecha limite.\n\nUn producto esta relacionado con una secuencia, pues una secuencia es la secuencia de produccion para producir un producto por ejemplo, una orden puede contener:\n\n100(cantidad) empanadas, se tendran los insumos dentro de 3 dias (fecha de disponibilidad), y la fecha de entrega es dentro de 8 dias (fehca de finalizacion), la prioridad que se tiene de cumplir con esto es de 5(osea, 5 veces mas importante que una de 1), y la secuencia sobre la cual se basa esto es la secuencia de "produccion empanadas"'),
                            icon: const Icon(Icons.info))
                      ],
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(children: widgets),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        provider.addJob();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Agregar Job'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        bool isValid = _validateForm(state);

                        if (!isValid) {
                          _showValidationDialog(context, colorScheme);
                        } else {
                          provider.saveOrder();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.secondary,
                        foregroundColor: colorScheme.onSecondary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Crear programa de produccion'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  bool _validateForm(NewOrderState state) {
    if (state is NewOrdersState && state.jobs.isNotEmpty) {
      for (final job in state.jobs) {
        if (job.priorityController?.text.isEmpty ?? true) return false;
        if (job.quantityController?.text.isEmpty ?? true) return false;
        if (job.availableDate == null) return false;
        if (job.dueDate == null) return false;
        if (job.selectedSequence == null) return false;
      }
      return true;
    }
    return false;
  }

  void _showValidationDialog(BuildContext context, ColorScheme colorScheme) {
    showDialog(
      context: context,
      builder: (subcontext) {
        return AlertDialog(
          title: Text(
            "Campos Incompletos",
            style: TextStyle(color: colorScheme.error),
          ),
          content: const Text(
              "Asegúrese de llenar todos los campos de todos los jobs antes de crear el programa de producción."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(subcontext).pop(),
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }
}
