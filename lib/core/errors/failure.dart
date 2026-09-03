abstract class Failure{}

class LocalStorageFailure implements Failure{}

class EnviromentNotCorrectFailure implements Failure{}

/// The order cannot be scheduled at all with the machines' current calendar
/// (empty shift, maintenance covering every working hour, or work that can
/// never fit). Carries a user-facing explanation because "no se pudo
/// planificar" alone leaves the user with nothing to fix.
class UnschedulableOrderFailure implements Failure{
  final String reason;

  UnschedulableOrderFailure(this.reason);
}
