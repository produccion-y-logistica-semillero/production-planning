import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/1_sequences/domain/entities/sequence_entity.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/see_processes_bloc/see_process_event.dart';

class OrderProcess extends StatelessWidget {
  final SequenceEntity process;
  final ScrollController _scrollController = ScrollController();

  OrderProcess({super.key, required this.process});

  @override
  Widget build(BuildContext context) {
    Color onSecondaryColor = Theme.of(context).colorScheme.onSecondaryContainer;
    Color primaryColor = Theme.of(context).colorScheme.primaryContainer;
    final machineCount = process.tasks!.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: const BoxConstraints(
              maxHeight: 500,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2), 
                      spreadRadius: 2,  // how much the shadow spreads
                      blurRadius: 7,   // the blur effect
                      offset: Offset(0, 3),  // the position of the shadow (x, y)
                    ),
                  ],
            ),
            child: GestureDetector(
              onHorizontalDragUpdate: (details){
                    _scrollController.jumpTo(_scrollController.offset - details.delta.dx);
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
                      width: 200,
                      margin: const EdgeInsets.symmetric(vertical: 80),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Tarea ${process.tasks![machineIndex].execOrder}',
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            process.tasks![machineIndex].machineName!,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Duración: ${duration.inHours.toString().padLeft(2, '0')}:${(duration.inMinutes - duration.inHours*60).toString().padLeft(2, '0')}', // Mostrar la duración tal cual
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white,
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
                    builder: (dialogContext){
                      return AlertDialog(
                        title: Text("Estas seguro de eliminar?"),
                        content: Row(
                          children: [
                            TextButton(
                              onPressed: ()=> Navigator.of(dialogContext).pop(), 
                              child: Text("Cancelar"),
                            ),
                            TextButton(
                              onPressed: (){
                                BlocProvider.of<SeeProcessBloc>(context).add(OnDeleteSequence(process.id!));
                                Navigator.of(dialogContext).pop();
                              }, 
                              child: Text("Eliminar"),
                            ),
                          ],
                        )
                      );
                    }
                  );
                },
                label: const Text(
                  "Eliminar",
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                icon: Icon(
                  Icons.save,
                  color: onSecondaryColor,
                ),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(
                    Colors.red,
                  ),
                  minimumSize: WidgetStateProperty.all(const Size(120, 50)),
                  shape: WidgetStateProperty.all(RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  )),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
