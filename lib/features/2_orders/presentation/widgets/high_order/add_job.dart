import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Para manejar fechas

class AddJob extends StatelessWidget {
  final DateTime? selectedDate;
  final TextEditingController? priorityController;
  final TextEditingController? quantityController;


  AddJob({
    super.key,
    this.selectedDate,
    required this.priorityController,
    required this.quantityController,
    });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextFormField(
              decoration: InputDecoration(labelText: 'Cantidad'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 8),
            TextFormField(
              decoration: InputDecoration(labelText: 'Prioridad'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Text(
                  selectedDate == null
                      ? 'Seleccionar fecha de entrega'
                      : DateFormat('dd/MM/yyyy').format(selectedDate!),
                ),
                Spacer(),
                IconButton(
                  icon: Icon(Icons.calendar_today),
                  onPressed: () {
                    // Aquí se implementará el DatePicker para seleccionar la fecha
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
