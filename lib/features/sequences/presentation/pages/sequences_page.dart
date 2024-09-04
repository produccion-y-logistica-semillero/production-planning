import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/sequences/presentation/widgets/high_order_widgets/orders_list.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';
import 'package:production_planning/features/sequences/presentation/widgets/high_order_widgets/machines_list.dart';
import 'package:production_planning/features/machines/presentation/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/features/machines/presentation/bloc/machine_types_bloc/machine_types_state.dart';
import 'package:production_planning/features/machines/presentation/bloc/machine_types_bloc/machine_types_event.dart';

class SequencesPage extends StatelessWidget {
  const SequencesPage({super.key});

  // final _nameOrder = TextEditingController();
  // final _weightOrder = TextEditingController();

  @override
  Widget build(BuildContext context) {
    Color onSecondaryContainer =
        Theme.of(context).colorScheme.onSecondaryContainer;
    Color primaryColor = Theme.of(context).colorScheme.primaryContainer;
    List<Map<String, String>> orders = [
      {'name': 'Job A', 'process': 'Process A'},
      {'name': 'Job B', 'process': 'Process B'},
      {'name': 'Job C', 'process': 'Process C'},
      {'name': 'Job D', 'process': 'Process D'},
    ];

    return Scaffold(
      appBar: getAppBar(),
      body: Row(
        children: [
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Expanded(
                  flex: 2,
                  child: BlocBuilder<MachineTypesBloc, MachineTypeState>(
                    builder: (context, state) {
                      Widget widget = switch (state) {
                        (MachineTypeInitial _) => const SizedBox(),
                        (MachineTypesRetrieving _) =>
                          const Center(child: CircularProgressIndicator()),
                        (MachineTypesRetrievingError _) =>
                          const Center(child: Text("Error fetching")),
                        (MachineTypesRetrievingSuccess _) =>
                          MachinesList(machineTypes: state.machineTypes!),
                        (MachineTypesAddingSuccess _) =>
                          MachinesList(machineTypes: state.machineTypes!),
                        (MachineTypesAddingError _) =>
                          MachinesList(machineTypes: state.machineTypes!),
                        (MachineTypeDeletionError _) =>
                          MachinesList(machineTypes: state.machineTypes!),
                        (MachineTypeDeletionSuccess _) =>
                          MachinesList(machineTypes: state.machineTypes!),
                      };

                      if (state is MachineTypeInitial) {
                        BlocProvider.of<MachineTypesBloc>(context)
                            .add(OnMachineTypeRetrieving());
                      }

                      return Container(
                        padding: const EdgeInsets.all(16.0),
                        child: widget,
                      );
                    },
                  ),
                ),
                Expanded(
                    flex: 1,
                    child: Center(
                      child: TextButton.icon(
                        onPressed: () {},
                        label: Text(
                          "Agregar trabajo",
                          style: TextStyle(color: primaryColor, fontSize: 18),
                        ),
                        icon: Icon(
                          Icons.upload,
                          color: onSecondaryContainer,
                        ),
                        style: ButtonStyle(
                          backgroundColor: WidgetStatePropertyAll(
                              Theme.of(context).colorScheme.secondaryContainer),
                          minimumSize:
                              WidgetStateProperty.all(const Size(200, 60)),
                          padding: WidgetStateProperty.all(
                              const EdgeInsets.symmetric(
                                  horizontal: 30, vertical: 20)),
                          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                        ),
                      ),
                    )),
              ],
            ),
          ),
          Expanded(
              flex: 2,
              child: OrderList(
                orders: orders,
              )),
        ],
      ),
    );
  }
}
