import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';
import 'package:production_planning/features/2_orders/domain/repositories/order_repository.dart';
import 'package:production_planning/features/2_orders/domain/request_models/new_order_request_model.dart';
import 'package:production_planning/features/2_orders/domain/entities/job_entity.dart';
import 'package:production_planning/features/1_sequences/domain/entities/sequence_entity.dart';

class AddOrderUseCase
    implements UseCase<bool, List<NewOrderRequestModel>> {
  late final OrderRepository repository;

  AddOrderUseCase(this.repository);

  @override
  Future<Either<Failure, bool>> call({required List<NewOrderRequestModel> p}) async {
    // new order list become job entity list
    final List<JobEntity> jobs = p
        .map((jobModel) => JobEntity(
            null,
            SequenceEntity(jobModel.sequenceId, null, ""),
            jobModel.amount,
            jobModel.dueDate,
            jobModel.priority,
            jobModel.availableDate)
          )
        .toList();

    // order entity.
    final OrderEntity newOrder = OrderEntity(null, DateTime.now(), jobs);

    // call repository to create order.
    return await repository.createOrder(newOrder);
  }
}
