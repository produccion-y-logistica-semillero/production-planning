import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';
import 'package:production_planning/repositories/interfaces/order_repository.dart';
import 'package:production_planning/services/orders_service.dart';

class _FakeOrderRepository implements OrderRepository {
  _FakeOrderRepository(this.stored);

  final OrderEntity stored;
  OrderEntity? created;

  @override
  Future<Either<Failure, OrderEntity>> getFullOrder(int id) async =>
      Right(stored);

  @override
  Future<Either<Failure, bool>> createOrder(OrderEntity orderEntity) async {
    created = orderEntity;
    return const Right(true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMachineRepository implements MachineRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('duplicating a program keeps its setup matrix and initial states',
      () async {
    final original = OrderEntity(
      7,
      DateTime(2026, 10, 1),
      [],
      setupTimeMatrix: {
        'Horno 1': {
          'A': {'B': 30},
          'B': {'A': 45},
        },
      },
      machineInitialStates: {'Horno 1': 'A'},
    );
    final repo = _FakeOrderRepository(original);
    final service = OrdersService(repo, _FakeMachineRepository());

    final result = await service.duplicateOrder(7);

    expect(result.isRight(), isTrue);
    expect(repo.created, isNotNull);
    expect(repo.created!.orderId, isNull);
    expect(repo.created!.setupTimeMatrix, original.setupTimeMatrix);
    expect(repo.created!.machineInitialStates, {'Horno 1': 'A'});
  });
}
