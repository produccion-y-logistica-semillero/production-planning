
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_bloc.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_event.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_state.dart';
import 'package:production_planning/features/machines/presentation/widgets/add_machine_dialog.dart';
import 'package:production_planning/features/machines/presentation/widgets/machines_list_view.dart';
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
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
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
          BlocBuilder<MachineBloc, MachineState>(
            builder: (context, state){
              //this is pending for customize, because right now is not showing success or error
              //messages, it simply shows again the list, we need to add success or error dialogs
              Widget widget =  switch(state){
                (MachineInitial _) => const SizedBox(),
                (MachineTypesRetrieving _) => const Text("Loading"),
                (MachineTypesRetrievingError _) => const Text("Error fetching"),
                (MachineTypesRetrievingSuccess _) => MachinesListView(
                    machineTypes: state.machineTypes!,
                    deleteMachineType: (id, index)=>_deleteMachineType(context, id, index),
                  ),
                (MachineTypesAddingSuccess _) => MachinesListView(
                    machineTypes: state.machineTypes!,
                     deleteMachineType: (id, index)=>_deleteMachineType(context, id, index),
                  ),
                (MachineTypesAddingError _) => MachinesListView(
                    machineTypes: state.machineTypes!,
                     deleteMachineType: (id, index)=>_deleteMachineType(context, id, index),
                  ),
                (MachineTypeDeletionError _) => MachinesListView(
                    machineTypes: state.machineTypes!,
                    deleteMachineType: (id, index)=>_deleteMachineType(context, id, index),
                  ),
                (MachineTypeDeletionSuccess _) => MachinesListView(
                    machineTypes: state.machineTypes!,
                    deleteMachineType: (id, index)=>_deleteMachineType(context, id, index),
                  ),
              };
              //IF WE ARE IN THE INITIAL STATE, WE TRIGGER THE FETCHING OF THE MACHINES
              if(state is MachineInitial) BlocProvider.of<MachineBloc>(context).add(OnMachineTypeRetrieving());

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
        return AddMachineDialog(
          nameController: _nameController, 
          descController: _descController, 
          addMachine: (){
            //IMPORTANT, notice how we operate over the external context, because thats the one with the bloc provider
            //but we pop over the dialog widget, since that's the one where the dialog is displaying
            BlocProvider.of<MachineBloc>(context).add(OnAddNewMachineType(_nameController.text, _descController.text));
            Navigator.of(dialogContext).pop();
            _nameController.clear();
            _descController.clear();
          },);
      }
    );
  }

  void _deleteMachineType(BuildContext context, int machineId, int index) async{
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.dangerous, color: Colors.red,),
          title: const Text("¿Estas seguro?"),
          content: const Text("Si eliminas este tipo de maquina, todas las maquinas asociadas seran eliminadas, ¿deseas continuar?"),
          actions: [
            TextButton(
              onPressed: ()=>Navigator.of(dialogContext).pop(), 
              child: const Text("Cancelar")
            ),
            TextButton(
              onPressed: (){
                BlocProvider.of<MachineBloc>(context).add(OnDeleteMachineType(machineId, index));
                Navigator.of(dialogContext).pop();
              }, 
              child: const Text("Eliminar")
            )
          ],
        );
      }
    );
  }
}