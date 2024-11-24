import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:production_planning/shared/functions/functions.dart';
import 'package:production_planning/shared/widgets/hour_field.dart';
import 'package:production_planning/shared/widgets/input_field_custom.dart';

class AddMachineDialog extends StatelessWidget{
  final String machineTypeName;
  final TextEditingController capacityController;
  final TextEditingController preparationController;
  final TextEditingController restTimeController;
  final TextEditingController continueController;
  final TextEditingController nameController;
  final void Function() addMachineHandle;

  const AddMachineDialog(
    this.machineTypeName,
    {
      super.key,
      required this.nameController,
      required this.capacityController,
      required this.preparationController,
      required this.restTimeController,
      required this.continueController,
      required this.addMachineHandle,
    }
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(20),
        height: 540, // MediaQuery.of(context).size.height - 200, //media query so that the size is proportional to the screen size
        width:  800,//MediaQuery.of(context).size.width - 900,  //wORK TO MAKE IT MORE RELATIVE TO THE SIZE, NOT COMPLETELY LINEAL, BUT CHECK SIZES
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: ()=>printInfo(context, 
                    title: 'Agregar maquina especifica', 
                    content: 'Agrega una maquina especifica de $machineTypeName, una maquina especifica es una maquina fisica de la categoria de $machineTypeName\n\nLos atributos estan ligados con esta maquina fisica, por ejemplo, el tiempo de procesamiento se refiere a :\n1 hora generica en $machineTypeName es equivalente a cuantas horas en esta maquina fisica?, en donde 1 hora seria el promedio, mas de 1 hora implicaria que esta maquina es mas lenta, y menos de 1 hora implicaria que es mas rapida'
                  ), 
                  icon: Icon(Icons.info)
                )
              ],
            ),
            const SizedBox(height: 10,),
            Text('Nueva maquina de $machineTypeName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),),
            const SizedBox(height: 20,),
            InputFieldCustom(
              sizedBoxWidth: 50, 
              maxLines: 1, 
              title: 'Nombre maquina', 
              hintText: 'Nombre', 
              controller: nameController
            ),
            const SizedBox(height: 20,),
            HourField(text: '1 hora de trabajo promedio de $machineTypeName para esta maquina equivale a: ', controller: capacityController,),
            const SizedBox(height: 30,),
            HourField(text: 'Tiempo de preparacion de la maquina: ', controller: preparationController),
            const SizedBox(height: 30,),
            HourField(text: 'Tiempo de descanso necesario: ', controller: restTimeController),
            const SizedBox(height: 30,),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 430,
                  child: Text('Numero de procesamientos continuos (sin descanso): ', maxLines: 2,)
                ),
                SizedBox(
                  width: 180,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    controller: continueController,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration:const  InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.all(10),
                      border: OutlineInputBorder()
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(height: 40,),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: ()=>Navigator.of(context).pop(),   
                  style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(EdgeInsets.all(20)),
                   // backgroundColor: WidgetStatePropertyAll(Colors.red),
                  ),
                  child: const Text("Cancelar"),
                ),
                const SizedBox(width: 50,),
                TextButton(
                  onPressed: addMachineHandle,
                  style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(EdgeInsets.all(20)),
                   // backgroundColor: WidgetStatePropertyAll(const Color.fromARGB(255, 177, 218, 179)),
                  ),
                  child: const Text("Agregar"),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}