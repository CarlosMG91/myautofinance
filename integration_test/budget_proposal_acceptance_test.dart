import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/budget_proposal_acceptance_journey.dart';
import 'budget_proposal_test.dart' as ui;

void main() {
  // Reutilizar el recorrido visible de generación, edición, desglose,
  // cancelación, autorización y reapertura; añadir los fallos sobre SQLite.
  ui.main();
  testWidgets('EP-018 contrato completo sobre SQLite nativo', (tester) async {
    final support = await getApplicationSupportDirectory();
    final fixtures = await Directory(
      p.join(support.path, 'proposal-synthetic-tests'),
    ).create(recursive: true);
    final root = await fixtures.resolveSymbolicLinks();
    final temporary = await fixtures.createTemp('ma-tsk-156-');
    final directory = Directory(await temporary.resolveSymbolicLinks());
    if (!p.isWithin(root, directory.path)) {
      throw StateError(
        'La carpeta sintética queda fuera del ámbito de pruebas.',
      );
    }
    try {
      await tester.runAsync(() => budgetProposalAcceptanceJourney(directory));
    } finally {
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
