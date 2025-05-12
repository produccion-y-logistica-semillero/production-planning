import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_state.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/order_process.dart';

class OrderList extends StatelessWidget {
  const OrderList({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocBuilder<SeeProcessBloc, SeeProcessState>(
      builder: (context, state) {
        Widget dropdown = const SizedBox();
        if (state is SeeProcessInitialState) {
          BlocProvider.of<SeeProcessBloc>(context).retrieveSequences();
        }
        if (state.sequences != null) {
          dropdown = DropdownButton<int>(
            borderRadius: BorderRadius.circular(12),
            value: state.selectedProcess,
            hint: Text(
              'Vea sus rutas de proceso registradas',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            items: state.sequences!.map((process) {
              return DropdownMenuItem<int>(
                value: process.id,
                child: Text(
                  process.name,
                  style: TextStyle(color: colorScheme.onSurface),
                ),
              );
            }).toList(),
            onChanged: (value) {
              BlocProvider.of<SeeProcessBloc>(context).selectSequence(value!);
            },
            isExpanded: true,
            underline: Container(
              height: 0, // Removed underline for a cleaner look
              color: Colors.transparent,
            ),
            icon: Icon(Icons.arrow_drop_down, color: colorScheme.primary),
            dropdownColor: colorScheme.surface,
          );
        }
        return Column(
          children: [
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              margin: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(2, 3),
                  ),
                ],
                border: Border.all(
                  color: colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
              child: Center(child: dropdown),
            ),
            if (state.selectedProcess != null)
              OrderProcess(process: state.process!),
            if (state.selectedProcess == null)
              Container(
                constraints: const BoxConstraints(
                  maxHeight: 400,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: Text(
                      'Ninguna orden seleccionada',
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
