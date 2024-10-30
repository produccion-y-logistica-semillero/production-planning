import 'package:flutter/material.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/high_order/add_order.dart';
class NewOrderPage extends StatelessWidget{


  List<TextEditingController>? priorityControllers;
  List<TextEditingController>? quantityControllers;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: getAppBar(),
      body: 
        AddOrder(priorityControllers: [], quantityControllers: [],)
    );
  }
}