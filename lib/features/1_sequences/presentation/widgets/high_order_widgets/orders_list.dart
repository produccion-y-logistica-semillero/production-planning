import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/see_processes_bloc/see_process_event.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/see_processes_bloc/see_process_state.dart';
import 'package:production_planning/features/1_sequences/presentation/widgets/high_order_widgets/order_process.dart';

class OrderList extends StatelessWidget {

  const OrderList({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SeeProcessBloc, SeeProcessState>(
      builder: (context, state) {
        Widget dropdown = const SizedBox();
        if(state is SeeProcessInitialState) BlocProvider.of<SeeProcessBloc>(context).add(OnRetrieveSequencesEvent());
        if(state.sequences != null){
          dropdown = DropdownButton<int>(
            borderRadius: BorderRadius.circular(20),
            value: state.selectedProcess,
            hint: const Text(
              'Seleccione una orden',
              style: TextStyle(color: Colors.black),
            ),
            items: state.sequences!.map((process) {
              return DropdownMenuItem<int>(
                value: process.id,
                child: Text(
                  process.name,
                  style: const TextStyle(color: Colors.black),
                ),
              );
            }).toList(),
            onChanged: (value) {
              BlocProvider.of<SeeProcessBloc>(context).add(OnSequenceSelected(value!));
            },
            isExpanded: true,
            underline: Container(
              height: 2,
              color: Colors.transparent,
            ),
          );
        }
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
              child: dropdown
            ),
            if (state.selectedProcess != null)
              OrderProcess(process: state.process!),
            if (state.selectedProcess == null)
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
    );
  }
}
