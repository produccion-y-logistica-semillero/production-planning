import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';


sealed class NewOrderState{
    NewOrderState.NewOrderState();
}

class NewOrdersInitialState extends NewOrderState{
    NewOrdersInitialState() : super.NewOrderState();
}


