import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:production_planning/shared/functions/functions.dart';
import 'package:intl/intl.dart';

class AddMachineDialog extends StatelessWidget{
  final String machineTypeName;
  final TextEditingController capacityController;
  final TextEditingController preparationController;
  final TextEditingController restTimeController;
  final TextEditingController continueController;
  final TextEditingController nameController;
  final TextEditingController availabilityDateTimeController;  // Nuevo controlador
  final TextEditingController quantityController; 

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
      required this.availabilityDateTimeController,  
      required this.addMachineHandle,
      required this.quantityController,
    }
  );

  @override
  Widget build(BuildContext context) {
    Widget buildLabeledField({
      required String label,
      required Widget field,
      EdgeInsetsGeometry margin = EdgeInsets.zero,
    }) {
      return Container(
        margin: margin,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 8),
            field,
          ],
        ),
      );
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => printInfo(
                      context,
                      title: 'Agregar maquina especifica',
                      content:
                          'Agrega una maquina especifica de $machineTypeName. Utilice porcentajes para configurar los tiempos: 100% representa el tiempo estándar, valores mayores a 100% indican que la máquina es más lenta y valores menores a 100% indican que es más rápida.',
                    ),
                    icon: const Icon(Icons.info),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Nueva maquina de $machineTypeName',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 24),
              buildLabeledField(
                label: 'Nombre maquina',
                margin: const EdgeInsets.only(bottom: 20),
                field: TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    hintText: 'Nombre',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                ),
              ),
              buildLabeledField(
                label:
                    'En comparación con el tiempo estándar esta máquina trabaja en qué %',
                margin: const EdgeInsets.only(bottom: 20),
                field: TextField(
                  controller: capacityController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: InputDecoration(
                    hintText: 'Porcentaje',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                ),
              ),
              buildLabeledField(
                label:
                    'En comparación con el tiempo estándar el tiempo de preparación de esta máquina varía en qué %',
                margin: const EdgeInsets.only(bottom: 20),
                field: TextField(
                  controller: preparationController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: InputDecoration(
                    hintText: 'Porcentaje',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                ),
              ),
              buildLabeledField(
                label:
                    'En comparación con el tiempo estándar esta máquina varía su tiempo de descanso necesario en qué %',
                margin: const EdgeInsets.only(bottom: 20),
                field: TextField(
                  controller: restTimeController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: InputDecoration(
                    hintText: 'Porcentaje',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                ),
              ),
              buildLabeledField(
                label: 'Número de procesamientos continuos (sin descanso)',
                margin: const EdgeInsets.only(bottom: 20),
                field: TextField(
                  controller: continueController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: InputDecoration(
                    hintText: 'Cantidad',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                ),
              ),
              buildLabeledField(
                label: 'Disponibilidad desde Y',
                margin: const EdgeInsets.only(bottom: 20),
                field: TextField(
                  readOnly: true,
                  controller: availabilityDateTimeController,
                  decoration: InputDecoration(
                    hintText: 'Selecciona fecha y hora',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime(2100),
                      initialDate: DateTime.now(),
                    );
                    if (date == null) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time == null) return;
                    final fullDateTime = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                    availabilityDateTimeController.text =
                        DateFormat('yyyy-MM-dd HH:mm').format(fullDateTime);
                  },
                ),
              ),
              buildLabeledField(
                label: 'Cantidad de máquinas a crear',
                margin: const EdgeInsets.only(bottom: 32),
                field: TextField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: InputDecoration(
                    hintText: 'Cantidad',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: const ButtonStyle(
                      padding: MaterialStatePropertyAll(EdgeInsets.all(20)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 50),
                  TextButton(
                    onPressed: addMachineHandle,
                    style: const ButtonStyle(
                      padding: MaterialStatePropertyAll(EdgeInsets.all(20)),
                    ),
                    child: const Text('Agregar'),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
