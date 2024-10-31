import 'package:dartz/dartz.dart' as dartz;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_event.dart';

class AddJobWidget extends StatefulWidget {
  DateTime? availableDate;
  DateTime? dueDate;
  final TextEditingController? priorityController;
  final TextEditingController? quantityController;
  final List<dartz.Tuple2<int, String>> sequences;
  final int index;
  int? selectedSequence;

  AddJobWidget({
    super.key,
    required this.availableDate,
    required this.dueDate,
    required this.priorityController,
    required this.quantityController,
    required this.index,
    required this.sequences,
  });

  @override
  AddJobState createState() => AddJobState();
}

class AddJobState extends State<AddJobWidget> {
  int? selectedSequenceValue;
  DateTime? availableDate;
  DateTime? dueDate;

  @override
  void initState() {
    super.initState();
    availableDate = widget.availableDate;
    dueDate = widget.dueDate;
  }

  Future<void> _selectDate(BuildContext context, String label) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        if (label == 'Seleccione fecha de disponibilidad') {
          widget.availableDate = picked;
          availableDate = picked;
        } else {
          widget.dueDate = picked;
          dueDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            IconButton(
              onPressed: () {
                BlocProvider.of<NewOrderBloc>(context).add(OnRemoveJob(widget.index));
              },
              icon: Icon(Icons.delete, color: Colors.red),
            ),
            TextFormField(
              controller: widget.quantityController,
              decoration: InputDecoration(labelText: 'Cantidad'),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
            SizedBox(height: 8),
            TextFormField(
              controller: widget.priorityController,
              decoration: InputDecoration(labelText: 'Prioridad'),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: selectDate('Seleccione fecha de disponibilidad', availableDate),
                ),
                Expanded(flex: 2, child: SizedBox()),
                Expanded(
                  flex: 3,
                  child: selectDate('Seleccione fecha de finalizacion', dueDate),
                ),
              ],
            ),
            SizedBox(height: 8),
            DropdownButton<int>(
              value: selectedSequenceValue,
              hint: Text('Seleccionar secuencia'),
              onChanged: (int? newValue) {
                setState(() {
                  selectedSequenceValue = newValue;
                  widget.selectedSequence = newValue;
                });
              },
              items: widget.sequences
                  .map(
                    (sequence) => DropdownMenuItem<int>(
                      value: sequence.value1,
                      child: Text(sequence.value2),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget selectDate(String label, DateTime? date) {
    return Row(
      children: [
        Text(
          date == null ? label : DateFormat('dd/MM/yyyy').format(date),
        ),
        Spacer(),
        IconButton(
          icon: Icon(Icons.calendar_today),
          onPressed: () {
            _selectDate(context, label);
          },
        ),
      ],
    );
  }
}
