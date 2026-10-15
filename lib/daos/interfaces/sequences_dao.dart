import 'package:production_planning/repositories/models/sequence_model.dart';

abstract class SequencesDao{
  Future<int> createSequence(SequenceModel sequence);
  Future<List<SequenceModel>> getSequences();
  Future<SequenceModel?> getSequenceById(int id);
  Future<bool> deleteSequence(int id);
  Future<void> renameSequence(int id, String name);

  /// How many jobs of saved production programs use this route.
  Future<int> countJobsUsing(int id);
}
