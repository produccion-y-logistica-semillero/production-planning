import 'package:production_planning/features/1_sequences/data/models/sequence_model.dart';

abstract class SequencesDao{
  Future<int> createSequence(SequenceModel sequence);
  Future<List<SequenceModel>> getSequences();
  Future<SequenceModel?> getSequenceById(int id);
}