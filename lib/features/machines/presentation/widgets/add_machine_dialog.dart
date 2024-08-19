import 'package:flutter/material.dart';
import 'package:production_planning/features/machines/presentation/widgets/new_machine_input_field.dart';

class AddMachineDialog extends StatelessWidget{

  final TextEditingController _nameController;
  final TextEditingController _descController;
  final void Function() addMachine;

  const AddMachineDialog({required TextEditingController nameController, required TextEditingController descController, required this.addMachine, super.key}): 
    _nameController = nameController,
    _descController = descController;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        height: 350, // MediaQuery.of(context).size.height - 200, //media query so that the size is proportional to the screen size
        width:  MediaQuery.of(context).size.width - 900,  //wORK TO MAKE IT MORE RELATIVE TO THE SIZE, NOT COMPLETELY LINEAL, BUT CHECK SIZES
        child: Column(
          children: [
            const SizedBox(height: 15,),
            const Text("Agregar tipo de maquina"),
            const SizedBox(height: 30,),
            NewMachineInputField(
              sizedBoxWidth: 30,
              title: "Nombre : ",
              hintText: "Nueva maquina",
              maxLines: 1,
              controller: _nameController,
            ),
            const SizedBox(height: 30,),
            NewMachineInputField(
              sizedBoxWidth: 10,
              title: "Descripcion : ",
              hintText: "Descripcion maquina",
              maxLines: 5,
              controller: _descController,
            ),
            const SizedBox(height: 40,),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: (){
                      Navigator.of(context).pop();
                    }, 
                    child: const Text("Cancelar"),
                  ),
                  const SizedBox(width: 15,),
                  TextButton(
                    onPressed: addMachine, 
                    child: const Text("Agregar")
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}