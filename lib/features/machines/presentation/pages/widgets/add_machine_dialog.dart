import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class AddMachineDialog extends StatelessWidget{

  final TextEditingController _nameController;
  final TextEditingController _descController;

  AddMachineDialog({required TextEditingController nameController, required TextEditingController descController, super.key}): 
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
            SizedBox(height: 15,),
            Text("Agregar tipo de maquina"),
            SizedBox(height: 30,),
            Container(
              margin: EdgeInsets.symmetric(horizontal: 50),
              child: Row(
                children: [
                  Text("Nombre : "),
                  SizedBox(width: 30,),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      maxLines: 1,
                      decoration: InputDecoration(
                        hintText: "Nueva maquina",
                        contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        )
                      ),
                    ),
                  )
                ],
              ),
            ),
            SizedBox(height: 30,),
            Container(
              margin: EdgeInsets.symmetric(horizontal: 50),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Descripcion : "),
                  SizedBox(width: 10,),
                  Expanded(
                    child: TextField(
                      controller: _descController,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: "Descripcion maquina",
                        contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        )
                      ),
                    ),
                  )
                ],
              ),
            ),
            SizedBox(height: 40,),
            Container(
              margin: EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: (){
                      Navigator.of(context).pop();
                    }, 
                    child: Text("Cancelar"),
                  ),
                  SizedBox(width: 15,),
                  TextButton(
                    onPressed: (){}, 
                    child: Text("Agregar")
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