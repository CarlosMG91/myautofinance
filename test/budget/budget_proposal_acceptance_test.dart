import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/budget_proposal_acceptance_journey.dart';
import '../support/budget_proposal_reference_csv.dart';

void main() {
  test('Fixture nativo idéntico al CSV sintético aprobado de EP-001', () {
    expect(
      budgetProposalReferenceCsv.replaceAll('\r\n', '\n'),
      File('docs/ep-001/historico-ejemplo.csv')
          .readAsStringSync()
          .replaceAll('\r\n', '\n'),
    );
  });
  test('EP-018 aceptación completa sobre SQLite de archivo', () async {
    final directory = await Directory.systemTemp.createTemp('proposal-156-');
    try {
      await budgetProposalAcceptanceJourney(directory);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
