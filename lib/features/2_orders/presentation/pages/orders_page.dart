import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/pages/new_order_page.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

class OrdersPage extends StatelessWidget{

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: getAppBar(),
      body: Column(
        children: [
          TextButton(
            onPressed: (){
              //navigating and providing bloc
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => 
                    BlocProvider<NewOrderBloc>(
                      create: (context) => GetIt.instance.get<NewOrderBloc>(),
                      child: NewOrderPage(),
                    )
                )
              );
            }, 
            child: const Text("Nueva orden")
          ),
        ],
      )
    );
  }
}