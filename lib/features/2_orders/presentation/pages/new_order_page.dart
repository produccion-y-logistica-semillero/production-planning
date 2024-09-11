import 'package:flutter/material.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

class NewOrderPage extends StatelessWidget{

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: getAppBar(),
      body: Text("TO DO NUEVA ORDEN"),
    );
  }
}