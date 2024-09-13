import 'package:flutter/material.dart';
import 'package:production_planning/features/1_sequences/domain/entities/process_entity.dart';
import 'package:production_planning/features/1_sequences/presentation/widgets/high_order_widgets/order_process.dart';

class OrderList extends StatefulWidget {
  final List<Map<String, dynamic>> orders;

  const OrderList({super.key, required this.orders});

  @override
  State<OrderList> createState() => _OrderListState();
}

class _OrderListState extends State<OrderList> {
  String? _selectedOrderName;
  ProcessEntity? _selectedOrderProcess;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          margin: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.7))]),
          child: DropdownButton<String>(
            borderRadius: BorderRadius.circular(20),
            value: _selectedOrderName,
            hint: const Text(
              'Seleccione una orden',
              style: TextStyle(color: Colors.black),
            ),
            items: widget.orders.map((order) {
              return DropdownMenuItem<String>(
                value: order["name"],
                child: Text(
                  order["name"]!,
                  style: const TextStyle(color: Colors.black),
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedOrderName = value;
                _selectedOrderProcess = widget.orders
                    .firstWhere((order) => order['name'] == value)['process'];
              });
            },
            isExpanded: true,
            underline: Container(
              height: 2,
              color: Colors.transparent,
            ),
          ),
        ),
        if (_selectedOrderProcess != null)
          OrderProcess(process: _selectedOrderProcess!),
        if (_selectedOrderProcess == null)
          Container(
            constraints: const BoxConstraints(
              maxHeight: 400,
            ),
            child: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'Ninguna orden seleccionada',
                  style: TextStyle(fontSize: 18, color: Colors.black),
                ),
              ),
            ),
          )
      ],
    );
  }
}
