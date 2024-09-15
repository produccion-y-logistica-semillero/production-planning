abstract class SeeProcessEvent{}

class OnRetrieveSequencesEvent implements SeeProcessEvent{

}

class OnSequenceSelected extends SeeProcessEvent{
  final int id;
  OnSequenceSelected(this.id);
}

class OnDeleteSequence extends SeeProcessEvent{
  final int id;
  OnDeleteSequence(this.id);
}