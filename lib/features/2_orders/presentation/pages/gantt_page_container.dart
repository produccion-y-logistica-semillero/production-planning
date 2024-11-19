import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/pages/gantt_page.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

class GanttPageContainer extends StatefulWidget {
  final int orderId;

  GanttPageContainer({super.key, required this.orderId});

  @override
  State<GanttPageContainer> createState() => _GanttPageContainerState();
}

class _GanttPageContainerState extends State<GanttPageContainer> {
  int number = 1;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: getAppBar(),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                  onPressed: () => {
                        setState(() {
                          number++;
                        })
                      },
                  child: Icon(Icons.add),
                  style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.green)),
              ),
              ElevatedButton(
                  onPressed: () => {
                        if (number > 1)
                          setState(() {
                            number--;
                          })
                      },
                  child: Icon(Icons.remove),
                  style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.red)),
              ),
            ],
          ),
          Row(children: [
            for (int i = 0; i < number; i++)
              BlocProvider<GanttBloc>(
                create: (context) => GetIt.instance.get<GanttBloc>(),
                child: Expanded(
                  child: GanttPage(orderId: widget.orderId, number: number),
                ),
              )
          ])
        ],
      ),
    );
  }
}
