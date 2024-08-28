import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:production_planning/features/machines/presentation/widgets/low_order_widgets/hour_text_input.dart';
import 'package:production_planning/features/machines/presentation/widgets/low_order_widgets/new_machine_hour_field.dart';

class AddMachineDialog extends StatelessWidget{
  final String machineTypeName;

  AddMachineDialog(this.machineTypeName);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(20),
        height: 450, // MediaQuery.of(context).size.height - 200, //media query so that the size is proportional to the screen size
        width:  800,//MediaQuery.of(context).size.width - 900,  //wORK TO MAKE IT MORE RELATIVE TO THE SIZE, NOT COMPLETELY LINEAL, BUT CHECK SIZES
        child: Column(
          children: [
            const SizedBox(height: 10,),
            Text('Nueva maquina de $machineTypeName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),),
            const SizedBox(height: 20,),
            NewMachineHourField(text: '1 hora de trabajo promedio de $machineTypeName para esta maquina equivale a: '),
            const SizedBox(height: 30,),
            NewMachineHourField(text: 'Tiempo de preparacion de la maquina: '),
            const SizedBox(height: 30,),
            NewMachineHourField(text: 'Tiempo de descanso necesario: '),
            const SizedBox(height: 30,),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 430,
                  child: Text('Numero de procesamientos continuos (sin descanso): ', maxLines: 2,)
                ),
                Container(
                  width: 180,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.all(10),
                      border: OutlineInputBorder()
                    ),
                  ),
                )
              ],
            ),
            SizedBox(height: 40,),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: ()=>Navigator.of(context).pop(), 
                  child: const Text("Cancelar"),
                  style: ButtonStyle(
                    padding: WidgetStatePropertyAll(EdgeInsets.all(20)),
                   // backgroundColor: WidgetStatePropertyAll(Colors.red),
                  ),
                ),
                SizedBox(width: 50,),
                TextButton(
                  onPressed: (){},
                  child: const Text("Agregar"),
                  style: ButtonStyle(
                    padding: WidgetStatePropertyAll(EdgeInsets.all(20)),
                   // backgroundColor: WidgetStatePropertyAll(const Color.fromARGB(255, 177, 218, 179)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}