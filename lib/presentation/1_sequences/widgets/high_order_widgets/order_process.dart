import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_bloc.dart';

class OrderProcess extends StatelessWidget {
  final SequenceEntity process;
  final ScrollController _scrollController = ScrollController();

  OrderProcess({super.key, required this.process});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final machineCount = process.tasks!.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: const BoxConstraints(maxHeight: 500),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(2, 3),
                ),
              ],
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                _scrollController
                    .jumpTo(_scrollController.offset - details.delta.dx);
              },
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                itemCount: machineCount > 0 ? machineCount * 2 - 1 : 0,
                itemBuilder: (context, index) {
                  if (index % 2 == 1) {
                    return const Center(
                      child: Icon(
                        Icons.arrow_forward,
                        size: 30,
                        color: Colors.grey,
                      ),
                    );
                  }

                  final machineIndex = index ~/ 2;
                  if (machineIndex >= process.tasks!.length) {
                    return Container();
                  }

                  final duration = process.tasks![machineIndex].processingUnits;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Container(
                      width: 220,
                      margin: const EdgeInsets.symmetric(vertical: 20),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(1, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          /*
                          Text(
                            'Tarea ${process.tasks![machineIndex].execOrder}',
                            style: TextStyle(
                              fontSize: 18,
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          */
                          const SizedBox(height: 8),
                          Text(
                            process.tasks![machineIndex].machineName!,
                            style: TextStyle(
                              fontSize: 16,
                              color: colorScheme.onPrimaryContainer
                                  .withOpacity(0.8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Duración: ${duration.inHours.toString().padLeft(2, '0')}:${(duration.inMinutes - duration.inHours * 60).toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onPrimaryContainer,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (dialogContext) {
                      return AlertDialog(
                        title: const Text("¿Estás seguro de eliminar?"),
                        content: Row(
                          children: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text("Cancelar"),
                            ),
                            TextButton(
                              onPressed: () {
                                BlocProvider.of<SeeProcessBloc>(context)
                                    .deleteSequence(process.id!);
                                Navigator.of(dialogContext).pop();
                              },
                              child: const Text("Eliminar"),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                label: Text(
                  "Eliminar",
                  style: TextStyle(color: colorScheme.onError, fontSize: 16),
                ),
                icon: Icon(
                  Icons.delete,
                  color: colorScheme.onError,
                ),
                style: TextButton.styleFrom(
                  backgroundColor: colorScheme.errorContainer,
                  minimumSize: const Size(140, 50),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
