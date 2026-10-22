// Every rule the database can offer has a plain-language explanation for
// the "¿Cómo funciona esta regla?" help, so none shows up blank.
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/shared/dispatch_rule_info.dart';

void main() {
  // Names seeded in dispatch_rules (sqllite_database_provider.dart).
  const seeded = [
    'EDD', 'SPT', 'LPT', 'FIFO', 'WSPT',
    'EDD_ADAPTADO', 'SPT_ADAPTADO', 'LPT_ADAPTADO', 'FIFO_ADAPTADO',
    'WSPT_ADAPTADO', 'MINSLACK', 'CR', 'ATCS', 'MS', 'JOHNSON', 'GENETICS',
    'TABU', 'LWR', 'MWR',
  ];

  test('every seeded rule is explained', () {
    for (final code in seeded) {
      final info = dispatchRuleInfo(code);
      expect(info, isNotNull, reason: code);
      expect(info!.summary, isNotEmpty, reason: code);
      expect(info.howItWorks, isNotEmpty, reason: code);
    }
  });

  test('MS is the same rule as MINSLACK', () {
    expect(dispatchRuleInfo('ms')!.code, 'MINSLACK');
  });
}
