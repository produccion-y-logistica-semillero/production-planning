import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_event.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_state.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/high_order/add_job.dart';

class NewOrderPage extends StatelessWidget {
  const NewOrderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear Nueva Orden'),
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
                  builder: (subcontext) {
                    return AlertDialog(
                      title: Text(
                        state.justSaved! ? "Guardado!!" : "Error",
                        style: TextStyle(color: state.justSaved! ? colorScheme.primary : colorScheme.error),
                      ),
                      content: Text(
                        state.justSaved!
                            ? "La orden ha sido guardada"
                            : "Hubo un error guardando la orden",
                      ),
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
          },
          child: BlocBuilder<NewOrderBloc, NewOrderState>(
            builder: (context, state) {
              final provider = BlocProvider.of<NewOrderBloc>(context);
              List<AddJobWidget> widgets = [];
              if (state is NewOrdersInitialState) {
                provider.add(OnRetrieveSequences());
                return const Center(child: CircularProgressIndicator());
              }
              if (state is NewOrdersState) {
                widgets = state.jobs;
              }

              return Center(
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(children: widgets),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        provider.add(OnAddJob());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Agregar Secuencia'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        bool dialog = false;
                        if (state is NewOrdersState && state.jobs.isNotEmpty) {
                          for (final wid in state.jobs) {
                            if (dialog) break;
                            if (wid.priorityController?.text.isEmpty ?? true) {
                              dialog = true;
                            } else if (wid.quantityController?.text.isEmpty ?? true) {
                              dialog = true;
                            } else if (wid.availableDate == null) {
                              dialog = true;
                            } else if (wid.dueDate == null) {
                              dialog = true;
                            } else if (wid.selectedSequence == null) {
                              dialog = true;
                            }
                          }
                        } else {
                          dialog = true;
                        }
                        if (dialog) {
                          showDialog(
                            context: context,
                            builder: (subcontext) {
                              return AlertDialog(
                                title: Text(
                                  "Cuidado",
                                  style: TextStyle(color: colorScheme.error),
                                ),
                                content: const Text("Asegúrese de llenar todos los jobs"),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(subcontext).pop(),
                                    child: const Text("OK"),
                                  ),
                                ],
                              );
                            },
                          );
                        } else {
                          provider.add(OnSaveOrder());
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.secondary,
                        foregroundColor: colorScheme.onSecondary,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Crear Orden'),
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
}
