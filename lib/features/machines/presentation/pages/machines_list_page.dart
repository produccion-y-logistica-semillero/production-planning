
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:ui';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_bloc.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_event.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_state.dart';
import 'package:production_planning/features/machines/presentation/widgets/add_machine_dialog.dart';
import 'package:production_planning/features/machines/presentation/widgets/machines_list_view.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

class MachinesListPage extends StatelessWidget{

  final _nameController = TextEditingController();
  final _descController = TextEditingController();

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
              Widget widget =  switch(state){
                (MachineInitial _) => SizedBox(),
                (MachineRetrieving _) => Text("Loading"),
                (MachineRetrievingSuccess _) => MachinesListView(
                    machineTypes: state.machineTypes!,
                    deleteMachineType: (id)=>_deleteMachineType(context, id),
                  ),
                (MachineAddingSuccess _) => MachinesListView(
                    machineTypes: state.machineTypes!,
                     deleteMachineType: (id)=>_deleteMachineType(context, id),
                  ),
                (MachineAddingError _) => MachinesListView(
                    machineTypes: state.machineTypes!,
                     deleteMachineType: (id)=>_deleteMachineType(context, id),
                  ),
                (MachineRetrievingError _) => Text("Error fetching"),
              };
              return Expanded(
                child: Container(
                  padding: EdgeInsets.all(30),
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
      builder: (context){
        return AddMachineDialog(
          nameController: _nameController, 
          descController: _descController, 
          addMachine: (){
            BlocProvider.of<MachineBloc>(context).add(OnAddNewMachineType(_nameController.text, _descController.text));
            Navigator.of(context).pop();
            _nameController.clear();
            _descController.clear();
          },);
      }
    );
  }

  void _deleteMachineType(BuildContext context, int machineId) async{
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: const Icon(Icons.dangerous, color: Colors.red,),
          title: const Text("¿Estas seguro?"),
          content: const Text("Si eliminas este tipo de maquina, todas las maquinas asociadas seran eliminadas, ¿deseas continuar?"),
          actions: [
            TextButton(
              onPressed: ()=>Navigator.of(context).pop(), 
              child: const Text("Cancelar")
            ),
            TextButton(
              onPressed: (){
                BlocProvider.of<MachineBloc>(context).add(OnDeleteMachineType(machineId));
                Navigator.of(context).pop();
              }, 
              child: const Text("Eliminar")
            )
          ],
        );
      }
    );
  }
}