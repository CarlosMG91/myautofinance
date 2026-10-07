import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';

const fingerprint = Sha256ImportFingerprint();

ImportFile file({
  List<int>? bytes,
  String name = 'sintetico.csv',
  ImportSource source = ImportSource.historicalCsv,
}) => ImportFile.fromBytes(
  bytes: bytes ?? utf8.encode('abc'),
  fingerprint: fingerprint,
  source: source,
  originalName: name,
);

InterpretedMovement movement({
  int ordinal = 2,
  int cents = -1250,
  ImportCategoryReference? category,
  List<ImportOriginalField> originals = const [],
}) => InterpretedMovement(
  sourceOrdinal: ordinal,
  originalFields: originals,
  concept: 'Café',
  amount: ImportAmount.economic(cents),
  valueDate: ValueDate(2026, 1, 3),
  account: ImportAccountReference.named('Cuenta sintética'),
  category: category,
  discretion: 'Opcional',
);

InterpretedBudget budget({int ordinal = 3, int cents = 1000}) =>
    InterpretedBudget(
      sourceOrdinal: ordinal,
      originalFields: const [ImportOriginalField('importe_eur', '10.00')],
      concept: 'Presupuesto',
      amount: ImportAmount.historicalBudget(cents),
      month: BudgetMonth(2026, 1),
      category: ImportCategoryReference(['Alimentación']),
    );

ImportSession session(
  List<InterpretedImportRow> rows, {
  List<ImportIssue> issues = const [],
  ImportFile? sourceFile,
  String contractVersion = importContractVersion,
}) => ImportSession(
  file: sourceFile ?? file(),
  interpretation: ImportInterpretation(
    formatVersion: 'synthetic-1',
    contractVersion: contractVersion,
    rows: rows,
    issues: issues,
  ),
);

// Ejemplo mínimo compilable de implementación. Solo existe bajo test/;
// no es un lector CSV/XLS ni el adaptador integrado de MA-TSK-113.
final class ExampleImportAdapter implements ImportAdapter {
  @override
  ImportSource get source => ImportSource.historicalCsv;
  @override
  Future<ImportInterpretation> interpret(ImportFile file) async {
    if (file.source != source) {
      return ImportInterpretation(
        formatVersion: 'synthetic-1',
        issues: const [
          ImportIssue(
            code: ImportIssueCode.invalidFile,
            reason: 'Origen ajeno.',
          ),
        ],
      );
    }
    return ImportInterpretation(
      formatVersion: 'synthetic-1',
      rows: [movement(), budget()],
    );
  }
}

final class ExamplePreviewer implements ImportPreviewer {
  ExamplePreviewer(this.readOnlyCatalog);
  final Future<bool> Function() readOnlyCatalog;

  @override
  Future<ImportReview> preview(
    ImportSession session, {
    ImportReferenceBindings? bindings,
  }) async {
    await readOnlyCatalog();
    return ImportReview(
      session: session,
      bindings: bindings,
      pendingReferences: [
        ImportPendingReference(
          reference: PendingImportAccount(
            (session.interpretation.rows.first as InterpretedMovement).account,
          ),
          sourceOrdinals: [2],
          reason: 'Elegir cuenta explícitamente.',
        ),
      ],
    );
  }
}

void main() {
  test('SHA-256 conocido de bytes completos, nombre independiente', () {
    expect(
      file().sha256,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(file(name: 'renombrado.csv').sha256, file().sha256);
    expect(file().matchesFingerprint(fingerprint), isTrue);
    expect(
      file(bytes: [239, 187, 191, ...utf8.encode('abc')]).sha256,
      isNot(file().sha256),
    );
    expect(
      file(bytes: utf8.encode('abc\r\n')).sha256,
      isNot(file(bytes: utf8.encode('abc\n')).sha256),
    );
  });

  test('Bytes copiados e inmutables y metadatos sin rutas', () {
    final bytes = <int>[1, 2, 3];
    final original = file(bytes: bytes);
    bytes[0] = 4;
    expect(original.bytes, [1, 2, 3]);
    expect(() => original.bytes[0] = 4, throwsUnsupportedError);
    expect(original.matchesFingerprint(fingerprint), isTrue);
    for (final name in [
      '',
      ' ',
      '../archivo.csv',
      r'C:\archivo.csv',
      '\u0000',
    ]) {
      expect(() => file(name: name), throwsArgumentError);
    }
    expect(() => file(bytes: [-1]), throwsArgumentError);
    expect(() => file(bytes: [256]), throwsArgumentError);
  });

  test('Referencias ignoran solo mayúsculas y espacios externos por nivel', () {
    final a = ImportAccountReference.named(' Cuenta ');
    final b = ImportAccountReference.named('CUENTA');
    expect(a, b);
    expect({a, b}.length, 1);
    expect(const ImportAccountReference.selectedAccount(), isNot(a));
    final first = ImportCategoryReference([' Alimentación ', 'compra']);
    final second = ImportCategoryReference(['ALIMENTACIÓN', 'COMPRA']);
    expect(first, second);
    expect({first, second}.length, 1);
    expect(first, isNot(ImportCategoryReference(['Alimentacion', 'compra'])));
    expect(
      ImportCategoryReference(['a/b']),
      isNot(ImportCategoryReference(['a', 'b'])),
    );
    for (final path in <List<String>>[
      [],
      [' '],
      ['a', '', 'b'],
      ['a', 'b', 'c', 'd'],
    ]) {
      expect(() => ImportCategoryReference(path), throwsArgumentError);
    }
    expect(() => ImportAccountReference.named(' '), throwsArgumentError);
  });

  test('Campos originales conservan espacios, columnas repetidas y orden', () {
    final originals = [
      const ImportOriginalField('concepto', ' Café '),
      const ImportOriginalField('extra', ' uno;dos\n"tres" '),
      const ImportOriginalField('extra', ''),
    ];
    final row = movement(originals: originals);
    originals.clear();
    expect(row.originalFields.map((f) => f.name), [
      'concepto',
      'extra',
      'extra',
    ]);
    expect(row.originalFields[1].value, ' uno;dos\n"tres" ');
    expect(() => row.originalFields.clear(), throwsUnsupportedError);
  });

  test(
    'REAL sin categoría mantiene signo, cuenta obligatoria y discreción',
    () {
      final row = movement();
      expect(row.category, isNull);
      final data = row.toMovementInput(accountId: 'cuenta-resuelta');
      expect(data.categoryId, isNull);
      expect(data.amountCents, -1250);
      expect(data.accountId, 'cuenta-resuelta');
      expect(data.valueDate.value, '2026-01-03');
      expect(data.discretion, 'Opcional');
      expect(() => row.toMovementInput(accountId: ''), throwsArgumentError);
      expect(() => movement(cents: 0), throwsArgumentError);
      expect(
        () =>
            movement(category: ImportCategoryReference(['Ocio']))
                .toMovementInput(accountId: 'cuenta'),
        throwsArgumentError,
      );
      final bank = InterpretedMovement(
        sourceOrdinal: 2,
        originalFields: const [],
        concept: 'Banco sintético',
        amount: const ImportAmount.economic(123),
        valueDate: ValueDate(2026, 1, 1),
        account: const ImportAccountReference.selectedAccount(),
      );
      expect(bank.account.name, isNull);
      expect(bank.toMovementInput(accountId: 'elegida').accountId, 'elegida');
      expect(
        () => InterpretedMovement(
          sourceOrdinal: 2,
          originalFields: const [],
          concept: 'x',
          amount: ImportAmount.historicalBudget(1),
          valueDate: ValueDate(2026, 1, 1),
          account: bank.account,
        ),
        throwsArgumentError,
      );
    },
  );

  test('PRESUPUESTO requiere categoría, admite cero e invierte una vez', () {
    for (final cents in [1000, -300000, 0, 9223372036854775807]) {
      final row = budget(cents: cents);
      expect(row.amount.originalCents, cents);
      expect(row.amount.internalCents, -cents);
      expect(row.toBudgetInput(categoryId: 'primera').amountCents, -cents);
      expect(row.toBudgetInput(categoryId: 'segunda').amountCents, -cents);
      expect(
        row.toBudgetInput(categoryId: 'segunda').month.value,
        '2026-01-01',
      );
    }
    expect(() => budget().toBudgetInput(categoryId: ''), throwsArgumentError);
    expect(
      () => ImportAmount.historicalBudget(-9223372036854775808),
      throwsA(
        isA<BudgetFailure>().having(
          (e) => e.code,
          'code',
          BudgetFailureCode.invalidAmount,
        ),
      ),
    );
    expect(
      ImportAmount.economic(-9223372036854775808).internalCents,
      -9223372036854775808,
    );
  });

  test('Lote vacío, versiones y ordinal transversal inválidos bloquean', () {
    expect(session([]).issues.single.code, ImportIssueCode.emptyBatch);
    expect(session([movement()], contractVersion: 'futura').isValid, isFalse);
    for (final rows in <List<InterpretedImportRow>>[
      [movement(ordinal: 1)],
      [movement(), movement()],
      [movement(), budget(ordinal: 2)],
    ]) {
      expect(session(rows).issues.last.code, ImportIssueCode.invalidOrdinal);
    }
    final duplicates = session([
      movement(),
      movement(ordinal: 3),
      budget(ordinal: 4),
    ]);
    expect(duplicates.isValid, isTrue);
    expect(duplicates.interpretation.rows.length, 3);
  });

  test('Origen bancario rechaza presupuesto y CSV exige signo normalizado', () {
    expect(
      session([
        budget(),
      ], sourceFile: file(source: ImportSource.bankXls)).isValid,
      isFalse,
    );
    final economicBudget = InterpretedBudget(
      sourceOrdinal: 2,
      originalFields: const [],
      concept: 'Previsto',
      amount: const ImportAmount.economic(-1000),
      month: BudgetMonth(2026, 1),
      category: ImportCategoryReference(['Ocio']),
    );
    expect(session([economicBudget]).isValid, isFalse);
  });

  test('Errores fila/campo/motivo no permiten una carga parcial', () {
    final issues = [
      const ImportIssue(
        code: ImportIssueCode.invalidField,
        sourceOrdinal: 3,
        field: 'fecha',
        reason: 'Fecha inexistente.',
      ),
    ];
    final draft = session([movement()], issues: issues);
    issues.clear();
    expect(draft.issues.single.sourceOrdinal, 3);
    expect(draft.issues.single.field, 'fecha');
    expect(draft.issues.single.reason, 'Fecha inexistente.');
    expect(() => draft.issues.clear(), throwsUnsupportedError);
    expect(
      () => ImportConfirmationRequest(review: ImportReview(session: draft)),
      throwsStateError,
    );
  });

  test('Conteos y totales separan tipos y originales sin overflow', () {
    final review = ImportReview(
      session: session([
        movement(cents: 9223372036854775807),
        movement(ordinal: 3, cents: 9223372036854775807),
        budget(ordinal: 4),
        budget(ordinal: 5, cents: 0),
      ]),
    );
    expect(review.movementCount, 2);
    expect(review.budgetCount, 2);
    expect(
      review.totalCents(budgets: false, original: false),
      BigInt.parse('18446744073709551614'),
    );
    expect(review.totalCents(budgets: true, original: true), BigInt.from(1000));
    expect(
      review.totalCents(budgets: true, original: false),
      BigInt.from(-1000),
    );
  });

  test(
    'Referencias pendientes y errores de revisión bloquean confirmación',
    () {
      final draft = session([movement()]);
      final pending = ImportPendingReference(
        reference: PendingImportCategory(ImportCategoryReference(['Ambigua'])),
        sourceOrdinals: [2],
        reason: 'Elegir UUID.',
      );
      for (final review in [
        ImportReview(session: draft, pendingReferences: [pending]),
        ImportReview(
          session: draft,
          issues: const [
            ImportIssue(
              code: ImportIssueCode.budgetConflict,
              reason: 'Conflicto con ancestro.',
            ),
          ],
        ),
        ImportReview(session: session([])),
      ]) {
        expect(review.canRequestConfirmation, isFalse);
        expect(
          () => ImportConfirmationRequest(review: review),
          throwsStateError,
        );
      }
    },
  );

  test('Solapamientos requieren revisión explícita y nunca eliminan filas', () {
    final overlaps = [
      const ImportOverlap(sourceOrdinal: 2, existingMovementId: 'anterior'),
    ];
    final review = ImportReview(
      session: session([movement(), movement(ordinal: 3)]),
      bindings: ImportReferenceBindings(
        accounts: {movement().account: 'cuenta'},
      ),
      overlaps: overlaps,
    );
    overlaps.clear();
    expect(() => ImportConfirmationRequest(review: review), throwsStateError);
    final ack = <String>{review.overlaps.single.key};
    final request = ImportConfirmationRequest(
      review: review,
      reviewedOverlapKeys: ack,
    );
    ack.clear();
    expect(request.reviewedOverlapKeys, {'2:anterior'});
    expect(request.review.movementCount, 2);
  });

  test('Ejemplos públicos de lector y previsualizador solo leen', () async {
    ImportAdapter adapter = ExampleImportAdapter();
    final source = file();
    final draft = ImportSession(
      file: source,
      interpretation: await adapter.interpret(source),
    );
    var reads = 0;
    ImportPreviewer previewer = ExamplePreviewer(() async {
      reads++;
      return true;
    });
    final review = await previewer.preview(draft);
    expect(reads, 1);
    expect(review.canRequestConfirmation, isFalse);
    expect(review.movementCount, 1);
    expect(review.budgetCount, 1);
  });

  test('Vinculación obligatoria aunque el resolutor omita pendientes', () {
    final draft = session([movement(), budget()]);
    expect(ImportReview(session: draft).canRequestConfirmation, isFalse);
    final accounts = {movement().account: 'cuenta'};
    final categories = {budget().category: 'categoria'};
    final bindings = ImportReferenceBindings(
      accounts: accounts,
      categories: categories,
    );
    accounts.clear();
    categories.clear();
    final review = ImportReview(session: draft, bindings: bindings);
    expect(review.canRequestConfirmation, isTrue);
    expect(ImportConfirmationRequest(review: review).review, same(review));
    expect(() => bindings.accounts.clear(), throwsUnsupportedError);
    expect(() => bindings.categories.clear(), throwsUnsupportedError);
    expect(
      ImportReview(
        session: draft,
        bindings: ImportReferenceBindings(
          accounts: {movement().account: ''},
          categories: bindings.categories,
        ),
      ).canRequestConfirmation,
      isFalse,
    );
  });

  test('Resultados distinguen éxito, repetición y rechazo estructurado', () {
    const batch = ImportBatch(
      id: 'lote',
      sha256: 'huella',
      source: ImportSource.historicalCsv,
      originalName: 'sintetico.csv',
      contractVersion: 'csv-1',
      importedAt: 'fecha',
    );
    final results = <ImportConfirmationResult>[
      const ImportConfirmed(batch: batch, movementCount: 2, budgetCount: 1),
      const ImportAlreadyImported(batch),
      ImportRejected(const [
        ImportIssue(
          code: ImportIssueCode.staleReview,
          reason: 'Base modificada.',
        ),
      ]),
    ];
    final labels = results.map(
      (result) => switch (result) {
        ImportConfirmed() => 'confirmado',
        ImportAlreadyImported() => 'ya importado',
        ImportRejected() => 'rechazado',
      },
    );
    expect(labels, ['confirmado', 'ya importado', 'rechazado']);
    expect(() => ImportRejected([]), throwsArgumentError);
  });
}
