import 'package:production_planning/features/1_sequences/domain/entities/sequence_entity.dart';

abstract class SeeProcessState{
  final List<SequenceEntity>? sequences;
  final int? selectedProcess;
  final SequenceEntity? process;

  SeeProcessState(this.sequences, this.selectedProcess, this.process);
}

class SeeProcessInitialState extends SeeProcessState{
  SeeProcessInitialState(super.sequences, super.selectedProcess, super.process);
}

class SequencesRetrieved extends SeeProcessState{
  SequencesRetrieved(super.sequences, super.selectedProcess, super.process);
}

class SequencesRetrieveFailure extends SeeProcessState{
  SequencesRetrieveFailure(super.sequences, super.selectedProcess, super.process);
}

class SequenceRetrieveFailure extends SeeProcessState{
  SequenceRetrieveFailure(super.sequences, super.selectedProcess, super.process);
}

class SequenceRetrieveSuccess extends SeeProcessState{
  SequenceRetrieveSuccess(super.sequences, super.selectedProcess, super.process);
}

class SequenceDeletedFailure extends SeeProcessState{
  SequenceDeletedFailure(super.sequences, super.selectedProcess, super.process);
}

class SequenceDeletedSuccess extends SeeProcessState{
  SequenceDeletedSuccess(super.sequences, super.selectedProcess, super.process);
}