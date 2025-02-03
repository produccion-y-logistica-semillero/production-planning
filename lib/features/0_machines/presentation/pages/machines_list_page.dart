

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/0_machines/presentation/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/features/0_machines/presentation/bloc/machine_types_bloc/machine_types_state.dart';
import 'package:production_planning/features/0_machines/presentation/widgets/low_order_widgets/add_machine_type_dialog.dart';
import 'package:production_planning/features/0_machines/presentation/widgets/high_order_widgets/machines_list_view.dart';
import 'package:production_planning/shared/functions/functions.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

class MachinesListPage extends StatelessWidget{

  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  MachinesListPage({super.key});

  @override
  Widget build(BuildContext context) {
    Color onSecondaryContainer = Theme.of(context).colorScheme.onSecondaryContainer;
    return Scaffold(
      appBar: getAppBar(),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(onPressed: ()=>printInfo(
                context,
                title: "Manejo de tipos de maquinas",
                content: "Aca puedes manejar los tipos de maquinas que tienes, un tipo de maquina es un tipo generico no asociado a una maquina fisica, sino a la categoria de la misma, asi como Horno, Microondas, Nevera.\n\nCada tipo de maquina tendra sus maquinas fisicas especificas con sus capacidades, asi como Hornos de hasta 200 grados, hornos que calientan en 1 minuto, mientras otros en 10 minutos"
              ), icon: Icon(Icons.info)),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 60, vertical: 10),
                child: TextButton.icon(
                  label: Text("Agregar maquina", style: TextStyle(color:onSecondaryContainer ),),
                  icon: Icon(Icons.upload, color: onSecondaryContainer,),
                  onPressed: () => _clickNewMachineType(context), 
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(Theme.of(context).colorScheme.secondaryContainer),
                    minimumSize:   const WidgetStatePropertyAll(Size(120, 50)),
                    shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ),
              )
            ],
          ),
          BlocBuilder<MachineTypesBloc, MachineTypeState>(
            builder: (context, state){
              //this is pending for customize, because right now is not showing success or error
              //messages, it simply shows again the list, we need to add success or error dialogs
              Widget widget =  switch(state){
                (MachineTypeInitial _) => const SizedBox(),
                (MachineTypesRetrieving _) => const Text("Loading"),
                (MachineTypesRetrievingError _) => const Text("Error fetching"),
                (MachineTypesRetrievingSuccess _) => MachinesListView(machineTypes: state.machineTypes!,),
                (MachineTypesAddingSuccess _) => MachinesListView(machineTypes: state.machineTypes!,),
                (MachineTypesAddingError _) => MachinesListView(machineTypes: state.machineTypes!,),
                (MachineTypeDeletionError _) => MachinesListView(machineTypes: state.machineTypes!,),
                (MachineTypeDeletionSuccess _) => MachinesListView(machineTypes: state.machineTypes!,),
              };
              //IF WE ARE IN THE INITIAL STATE, WE TRIGGER THE FETCHING OF THE MACHINES
              if(state is MachineTypeInitial) BlocProvider.of<MachineTypesBloc>(context).retrieveMachineTypes();

              return Expanded(
                child: Container(
                  padding: const EdgeInsets.all(30),
                  child: widget,
                ),
              );
            }
          )
        ],
      ),
    );
  }

  void _clickNewMachineType(BuildContext context) async {
    await showDialog(
      context: context, 
      builder: (dialogContext){
        return AddMachineTypeDialog(
          nameController: _nameController, 
          descController: _descController, 
          addMachine: (){
            //IMPORTANT, notice how we operate over the external context, because thats the one with the bloc provider
            //but we pop over the dialog widget, since that's the one where the dialog is displaying
            BlocProvider.of<MachineTypesBloc>(context).addNewMachineType(_nameController.text, _descController.text);
            Navigator.of(dialogContext).pop();
            _nameController.clear();
            _descController.clear();
          },);
      }
    );
  }
}
