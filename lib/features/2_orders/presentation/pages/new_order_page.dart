import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_event.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_state.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/high_order/add_job.dart';

class NewOrderPage extends StatelessWidget {
  List<TextEditingController>? priorityControllers;
  List<TextEditingController>? quantityControllers;

  NewOrderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Crear Nueva Orden'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: BlocListener<NewOrderBloc, NewOrderState>(
          listener: (context, state) {
            if (state is NewOrdersState) {
                if (state.justSaved != null) {
                  if (state.justSaved!) {
                    showDialog(
                        context: context,
                        builder: (subcontext) {
                          return AlertDialog(
                            title: Text("Guardado!!"),
                            content: Text("La orden ha sido guardada"),
                          );
                        });
                  } else {
                    showDialog(
                        context: context,
                        builder: (subcontext) {
                          return AlertDialog(
                            title: Text("Error"),
                            content: Text("Hubo un error guardando la orden"),
                          );
                        });
                  }
                }
              }

          },
          child: BlocBuilder<NewOrderBloc, NewOrderState>(
            builder: (context, state) {
              final provider = BlocProvider.of<NewOrderBloc>(context);
              List<AddJobWidget> widgets = [];
              if (state is NewOrdersInitialState) {
                provider.add(OnRetrieveSequences());
                return Center(
                  child: CircularProgressIndicator(),
                );
              }
              if (state is NewOrdersState) {
                widgets = (state).jobs;
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
                      child: Text('Agregar Secuencia'),
                    ),
                    SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        bool dialog = false;
                        if (state is NewOrdersState && state.jobs.length > 0) {
                          for (final wid in state.jobs) {
                            if (dialog) break;
                            if (wid.priorityController?.text.isEmpty ?? true) {
                              print("prioridad vacia");
                              dialog = true;
                            } else if (wid.quantityController?.text.isEmpty ?? true) {
                              print("cantidad vacia");
                              dialog = true;
                            } else if (wid.availableDate == null) {
                              print("disponibildiad vacia");
                              dialog = true;
                            } else if (wid.dueDate == null) {
                              print("due date vacia");
                              dialog = true;
                            } else if (wid.selectedSequence == null) {
                              print("secuencia vacia");
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
                                  title: Text("Cuidado"),
                                  content: Text("Asegurese de llenar todos los jobs"),
                                );
                              });
                        } else {
                          provider.add(OnSaveOrder());
                        }
                      },
                      child: Text('Crear Orden'),
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
