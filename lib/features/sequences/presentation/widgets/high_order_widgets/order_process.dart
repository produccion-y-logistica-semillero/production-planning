import 'package:flutter/material.dart';
import 'package:production_planning/features/sequences/domain/entities/process_entity.dart';

class OrderProcess extends StatelessWidget {
  final ProcessEntity process;

  const OrderProcess({super.key, required this.process});

  @override
  Widget build(BuildContext context) {
    Color onSecondaryColor = Theme.of(context).colorScheme.onSecondaryContainer;
    Color primaryColor = Theme.of(context).colorScheme.primaryContainer;
    final machineCount =
        process.machines.isNotEmpty ? process.machines.length : 0;

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
            ),
            child: ListView.builder(
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
                if (machineIndex >= process.machines.length) {
                  return Container();
                }

                final machine = process.machines[machineIndex];
                final duration = process.durations[machineIndex];
                final taskNumber = machineIndex + 1;

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
                          'Tarea $taskNumber',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          machine.name,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Duración: ${duration.toString().split(".").first}', // Mostrar la duración tal cual
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
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () {},
                label: const Text(
                  "Editar",
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                icon: Icon(
                  Icons.save,
                  color: onSecondaryColor,
                ),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(
                    Theme.of(context).colorScheme.primaryContainer,
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
