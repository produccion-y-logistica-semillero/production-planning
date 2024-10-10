import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';


sealed class OrdersState{
    final List<OrderEntity>? orders;
    OrdersState(this.orders);
}

class OrdersInitialState extends OrdersState{
    OrdersInitialState(super.orders);
}

class OrdersRetrievievingSuccess extends OrdersState{
    OrdersRetrievievingSuccess(super.orders);
}

class OrdersError extends OrdersState{
    OrdersError(super.orders);
}

