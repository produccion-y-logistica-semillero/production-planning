import 'package:flutter/material.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

class NewOrderPage extends StatelessWidget{
  const NewOrderPage({super.key});


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: getAppBar(),
      body: const Text("TO DO NUEVA ORDEN"),
    );
  }
}