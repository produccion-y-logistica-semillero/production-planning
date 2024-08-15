import 'package:flutter/material.dart';
import 'package:production_planning/features/machines/presentation/pages/widgets/add_machine_dialog.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

class MachinesListPage extends StatelessWidget{

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
                  onPressed: () => _addMachine(context), 
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(Theme.of(context).colorScheme.secondaryContainer),
                    minimumSize: const  WidgetStatePropertyAll(Size(120, 50)),
                    shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  void _addMachine(BuildContext context) async {
    await showDialog(
      context: context, 
      builder: (context){
        return AddMachineDialog();
      }
    );
  }
}