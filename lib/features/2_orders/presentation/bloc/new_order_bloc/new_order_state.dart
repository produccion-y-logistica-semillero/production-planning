import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';


sealed class NewOrdersState{
    final List<OrderEntity>? orders;
    NewOrdersState(this.orders);
}

class NewOrdersInitialState extends NewOrdersState{
    NewOrdersInitialState(super.orders);
}

class NewOrdersRetrievievingSuccess extends NewOrdersState{
    NewOrdersRetrievievingSuccess(super.orders);
}

class NewOrdersError extends NewOrdersState{
    NewOrdersError(super.orders);
}

