import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

final accountRef = ImportAccountReference.named('Cuenta');
final rootRef = ImportCategoryReference(['Gastos']);
final childRef = ImportCategoryReference(['Gastos', 'Compra']);

InterpretedMovement real({
  int ordinal = 2,
  String concept = ' Café ',
  ImportAccountReference? account,
  ImportCategoryReference? category,
  int month = 1,
  int amount = -1250,
}) => InterpretedMovement(
  sourceOrdinal: ordinal,
  originalFields: const [ImportOriginalField('concepto', ' Café ')],
  concept: concept,
  amount: ImportAmount.economic(amount),
  valueDate: ValueDate(2026, month, 5),
  account: account ?? accountRef,
  category: category,
  discretion: 'Necesario',
);

InterpretedBudget budget({
  int ordinal = 3,
  ImportCategoryReference? category,
  int month = 1,
  int amount = 1000,
}) => InterpretedBudget(
  sourceOrdinal: ordinal,
  originalFields: const [],
  concept: 'Presupuesto',
  amount: ImportAmount.historicalBudget(amount),
  month: BudgetMonth(2026, month),
  category: category ?? rootRef,
);

ImportSession draft(
  List<InterpretedImportRow> rows, {
  List<ImportIssue> issues = const [],
  List<int> bytes = const [1],
  String name = 'sintetico.csv',
}) => ImportSession(
  file: ImportFile.fromBytes(
    bytes: bytes,
    fingerprint: const Sha256ImportFingerprint(),
    source: ImportSource.historicalCsv,
    originalName: name,
  ),
  interpretation: ImportInterpretation(
    formatVersion: 'synthetic-1',
    rows: rows,
    issues: issues,
  ),
);

AccountRecord account({
  String id = 'a',
  String name = ' Cuenta ',
  AccountKind kind = AccountKind.account,
  int from = 1,
  int? through,
}) => AccountRecord(
  id: id,
  name: name,
  kind: kind,
  activeFrom: Month(2026, from),
  activeThrough: through == null ? null : Month(2026, through),
);

CategoryNode node(
  String id, {
  String? parent,
  String name = 'Gastos',
  int depth = 1,
  bool archived = false,
}) => CategoryNode(
  id: id,
  parentId: parent,
  name: name,
  isIncome: false,
  archived: archived,
  depth: depth,
);

ImportPreviewSnapshot snapshot({
  List<AccountRecord>? accounts,
  List<CategoryNode>? categories,
  List<MovementRecord> movements = const [],
  List<BudgetRecord> budgets = const [],
  String? sameFileBatchId,
}) => ImportPreviewSnapshot(
  accounts: accounts ?? [account()],
  categories:
      categories ??
      [node('g'), node('c', parent: 'g', name: 'Compra', depth: 2)],
  movements: movements,
  budgets: budgets,
  sameFileBatchId: sameFileBatchId,
);

final class FixtureSource implements ImportPreviewSource {
  FixtureSource(this.data);
  final ImportPreviewSnapshot data;
  @override
  Future<ImportPreviewSnapshot> read(ImportSession session) async => data;
}

final class FailingSource implements ImportPreviewSource {
  @override
  Future<ImportPreviewSnapshot> read(ImportSession session) async =>
      throw StateError('lectura');
}

Future<ImportReview> preview(
  List<InterpretedImportRow> rows, {
  ImportPreviewSnapshot? data,
  ImportReferenceBindings? bindings,
}) =>
    ValidatingImportPreviewer(FixtureSource(data ?? snapshot()))
        .preview(draft(rows), bindings: bindings);

void blocked(ImportReview review) {
  expect(review.canRequestConfirmation, isFalse);
  expect(() => ImportConfirmationRequest(review: review), throwsStateError);
}

void main() {
  test('Normaliza cada nivel y aplica identidad a todas las filas; originales intactos', () async {
    final rows = [
      real(category: ImportCategoryReference([' GASTOS ', ' compra '])),
      real(
        ordinal: 4,
        category: childRef,
        account: ImportAccountReference.named(' CUENTA '),
      ),
      budget(ordinal: 5, category: childRef, amount: 0),
    ];
    final review = await preview(rows);
    expect(review.issues, isEmpty);
    expect(review.canRequestConfirmation, isTrue);
    expect(review.bindings.accounts.length, 1);
    expect(review.bindings.categories[childRef], 'c');
    expect(review.movementCount, 2);
    expect(review.budgetCount, 1);
    expect(
      review.totalCents(budgets: false, original: false),
      BigInt.from(-2500),
    );
    expect(review.session.interpretation.rows, rows);
    expect(rows.first.originalFields.single.value, ' Café ');
    expect(rows.first.discretion, 'Necesario');
  });

  test(
    'Cuenta obligatoria pendiente y REAL Sin clasificar no propone categorías',
    () async {
      final review = await preview([
        real(account: const ImportAccountReference.selectedAccount()),
      ]);
      blocked(review);
      expect(review.pendingReferences.single.sourceOrdinals, [2]);
      expect(review.bindings.newCategories, isEmpty);
      final ready = await preview(
        [real(account: const ImportAccountReference.selectedAccount())],
        bindings: ImportReferenceBindings(
          accounts: {const ImportAccountReference.selectedAccount(): 'a'},
        ),
      );
      expect(ready.canRequestConfirmation, isTrue);
      expect(ready.bindings.categories, isEmpty);
      expect(
        ready.session.interpretation.rows
            .whereType<InterpretedMovement>()
            .single
            .toMovementInput(accountId: 'a')
            .categoryId,
        isNull,
      );
    },
  );

  test(
    'Ambigüedad de cuentas y categorías exige UUID y agrupa ordinales',
    () async {
      final data = snapshot(
        accounts: [
          account(),
          account(id: 'b'),
        ],
        categories: [node('g'), node('g2')],
      );
      final rows = [
        real(category: rootRef),
        real(ordinal: 3, category: rootRef),
        budget(ordinal: 4),
      ];
      final review = await preview(rows, data: data);
      blocked(review);
      expect(review.pendingReferences.length, 2);
      expect(review.pendingReferences.first.sourceOrdinals, [2, 3]);
      expect(review.pendingReferences.last.sourceOrdinals, [2, 3, 4]);
      expect(review.pendingReferences.first.candidateIds, ['a', 'b']);
      final ready = await preview(
        rows,
        data: data,
        bindings: ImportReferenceBindings(
          accounts: {accountRef: 'b'},
          categories: {rootRef: 'g2'},
        ),
      );
      expect(ready.canRequestConfirmation, isTrue);
      expect(ready.bindings.categories[rootRef], 'g2');
    },
  );

  test(
    'Ruta completa distingue ramas iguales y hermanos con nombre duplicado',
    () async {
      final data = snapshot(
        categories: [
          node('g'),
          node('x', name: 'Otro'),
          node('c', parent: 'g', name: 'Compra', depth: 2),
          node('c2', parent: 'g', name: 'Compra', depth: 2),
          node('c3', parent: 'x', name: 'Compra', depth: 2),
        ],
      );
      final review = await preview([real(category: childRef)], data: data);
      blocked(review);
      expect(review.pendingReferences.single.candidateIds, ['c', 'c2']);
      final ready = await preview([
        real(category: ImportCategoryReference(['Otro', 'Compra'])),
      ], data: data);
      expect(ready.canRequestConfirmation, isTrue);
      expect(ready.bindings.categories.values.single, 'c3');
    },
  );

  test('No normaliza acentos, puntuación o espacios interiores', () async {
    for (final name in ['Cuénta', 'Cuen ta', 'Cuenta.']) {
      final review = await preview([
        real(account: ImportAccountReference.named(name)),
      ]);
      blocked(review);
      expect(review.pendingReferences.single.candidateIds, isEmpty);
    }
  });

  test(
    'Valida todas las filas y conserva errores del lector, conteos y signos',
    () async {
      final session = draft(
        [real(), budget()],
        issues: const [
          ImportIssue(
            code: ImportIssueCode.invalidField,
            sourceOrdinal: 8,
            field: 'fecha',
            reason: 'Fecha inválida',
          ),
        ],
      );
      final review = await ValidatingImportPreviewer(FixtureSource(snapshot()))
          .preview(session);
      blocked(review);
      expect(review.issues.single.sourceOrdinal, 8);
      expect(review.issues.single.field, 'fecha');
      expect(
        review.totalCents(budgets: true, original: true),
        BigInt.from(1000),
      );
      expect(
        review.totalCents(budgets: true, original: false),
        BigInt.from(-1000),
      );
      expect(review.bindings.categories[rootRef], 'g');
    },
  );

  test(
    'Rechaza referencias explícitas inexistentes/archivadas y tipo de cuenta',
    () async {
      final data = snapshot(
        accounts: [account(kind: AccountKind.portfolio)],
        categories: [node('g', archived: true)],
      );
      final review = await preview(
        [real(category: rootRef), budget()],
        data: data,
        bindings: ImportReferenceBindings(
          accounts: {accountRef: 'a'},
          categories: {rootRef: 'g'},
        ),
      );
      blocked(review);
      expect(review.issues.map((i) => i.sourceOrdinal), containsAll([2, 3]));
      final missing = await preview(
        [real(category: rootRef)],
        bindings: ImportReferenceBindings(
          accounts: {accountRef: 'missing'},
          categories: {rootRef: 'missing'},
        ),
      );
      blocked(missing);
      expect(missing.issues.length, 2);
      final archived = await preview([budget()], data: data);
      blocked(archived);
      expect(archived.pendingReferences.single.candidateIds, ['g']);
    },
  );

  test(
    'No elige otra identidad ignorando una coincidencia archivada',
    () async {
      final review = await preview([
        budget(),
      ], data: snapshot(categories: [node('g'), node('g2', archived: true)]));
      blocked(review);
      expect(review.pendingReferences.single.candidateIds.length, 2);
    },
  );

  test(
    'Vigencia mensual inclusiva para todas las filas y cuentas nuevas',
    () async {
      final rows = [
        real(month: 1),
        real(ordinal: 3, month: 2),
        real(ordinal: 4, month: 3),
        real(ordinal: 5, month: 4),
      ];
      final review = await preview(
        rows,
        data: snapshot(accounts: [account(from: 2, through: 3)]),
      );
      blocked(review);
      expect(review.issues.map((i) => i.sourceOrdinal), [2, 5]);
      final planned = await preview(
        rows,
        bindings: ImportReferenceBindings(
          newAccounts: {
            accountRef: ImportNewAccount(
              name: 'Nueva',
              activeFrom: Month(2026, 2),
              activeThrough: Month(2026, 3),
              liquidity: Liquidity.liquid,
            ),
          },
        ),
      );
      blocked(planned);
      expect(planned.issues.map((i) => i.sourceOrdinal), [2, 5]);
    },
  );

  test(
    'Raíces nuevas requieren elección explícita sin inferencia por signo',
    () async {
      final ref = ImportCategoryReference(['Nueva']);
      for (final amount in [-1000, 1000, 0]) {
        final rows = [budget(category: ref, amount: amount)];
        final review = await preview(
          rows,
          bindings: ImportReferenceBindings(
            newCategories: {ref: const ImportNewCategory(name: 'Nueva')},
          ),
        );
        blocked(review);
        expect(
          review.issues.any((i) => i.reason.contains('Ingreso/Salida')),
          isTrue,
        );
        for (final income in [false, true]) {
          final ready = await preview(
            rows,
            bindings: ImportReferenceBindings(
              newCategories: {
                ref: ImportNewCategory(name: 'Nueva', isIncome: income),
              },
            ),
          );
          expect(ready.canRequestConfirmation, isTrue);
          expect(ready.bindings.newCategories[ref]!.isIncome, income);
          expect(ready.bindings.categories, isEmpty);
        }
      }
    },
  );

  test('Planes con tres niveles se resuelven sin UUID ficticios', () async {
    final leaf = ImportCategoryReference(['Nueva', 'Hija', 'Hoja']);
    final parent = ImportCategoryReference(['Nueva', 'Hija']);
    final root = ImportCategoryReference(['Nueva']);
    final plans = {
      root: const ImportNewCategory(name: 'Nueva', isIncome: true),
      parent: ImportNewCategory(
        name: 'Hija',
        parent: ImportCategoryTarget.proposed(root),
      ),
      leaf: ImportNewCategory(
        name: 'Hoja',
        parent: ImportCategoryTarget.proposed(parent),
      ),
    };
    final ready = await preview([
      budget(category: leaf),
    ], bindings: ImportReferenceBindings(newCategories: plans));
    expect(ready.canRequestConfirmation, isTrue);
    expect(
      ready.bindings.categoryTarget(leaf),
      ImportCategoryTarget.proposed(leaf),
    );
    expect(ready.bindings.categories, isEmpty);
    expect(() => ready.bindings.newCategories.clear(), throwsUnsupportedError);
  });

  test('Un antecesor nuevo inválido informa cada ordinal afectado', () async {
    final root = ImportCategoryReference(['Nueva']);
    final child = ImportCategoryReference(['Nueva', 'Hija']);
    final review = await preview(
      [real(category: child), budget(ordinal: 9, category: child)],
      bindings: ImportReferenceBindings(
        newCategories: {
          root: const ImportNewCategory(name: 'Nueva'),
          child: ImportNewCategory(
            name: 'Hija',
            parent: ImportCategoryTarget.proposed(root),
          ),
        },
      ),
    );
    blocked(review);
    expect(
      review.issues
          .where((i) => i.sourceOrdinal != null)
          .map((i) => i.sourceOrdinal),
      containsAll([2, 9]),
    );
  });

  test(
    'Altas explícitas se aplican a referencias equivalentes sin inferir tipo',
    () async {
      final ref = ImportCategoryReference(['Nueva']);
      final alias = ImportCategoryReference([' NUEVA ']);
      final review = await preview(
        [
          real(category: ref, amount: -100),
          real(
            ordinal: 7,
            category: alias,
            account: ImportAccountReference.named(' CUENTA '),
            amount: 200,
          ),
          budget(ordinal: 8, category: alias, amount: 0),
        ],
        bindings: ImportReferenceBindings(
          newAccounts: {
            accountRef: ImportNewAccount(
              name: 'Cuenta elegida',
              activeFrom: Month(2026, 1),
              liquidity: Liquidity.medium,
            ),
          },
          newCategories: {
            ref: const ImportNewCategory(
              name: 'Nombre elegido',
              isIncome: true,
            ),
          },
        ),
      );
      expect(review.canRequestConfirmation, isTrue);
      expect(review.bindings.accounts, isEmpty);
      expect(review.bindings.categories, isEmpty);
      expect(review.bindings.newAccounts.length, 1);
      expect(review.bindings.newCategories.length, 1);
      expect(review.bindings.newCategories[alias]!.isIncome, isTrue);
      expect(
        review.totalCents(budgets: false, original: false),
        BigInt.from(100),
      );
    },
  );

  test(
    'Rechaza cuarto nivel, ciclo, padre ausente/archivado y tipo en hijo',
    () async {
      final ref = ImportCategoryReference(['Nueva']);
      final other = ImportCategoryReference(['Otra']);
      final data = snapshot(
        categories: [
          node('g'),
          node('c', parent: 'g', depth: 2),
          node('leaf', parent: 'c', depth: 3),
          node('arch', archived: true),
        ],
      );
      final invalid = [
        {
          ref: const ImportNewCategory(
            name: 'Nueva',
            parent: ImportCategoryTarget.existing('leaf'),
          ),
        },
        {
          ref: ImportNewCategory(
            name: 'Nueva',
            parent: ImportCategoryTarget.proposed(other),
          ),
          other: ImportNewCategory(
            name: 'Otra',
            parent: ImportCategoryTarget.proposed(ref),
          ),
        },
        {
          ref: ImportNewCategory(
            name: 'Nueva',
            parent: ImportCategoryTarget.proposed(other),
          ),
        },
        {
          ref: const ImportNewCategory(
            name: 'Nueva',
            parent: ImportCategoryTarget.existing('missing'),
          ),
        },
        {
          ref: const ImportNewCategory(
            name: 'Nueva',
            parent: ImportCategoryTarget.existing('arch'),
          ),
        },
        {
          ref: const ImportNewCategory(
            name: 'Nueva',
            parent: ImportCategoryTarget.existing('g'),
            isIncome: false,
          ),
        },
      ];
      for (final plans in invalid) {
        final review = await preview(
          [budget(category: ref)],
          data: data,
          bindings: ImportReferenceBindings(newCategories: plans),
        );
        blocked(review);
        expect(review.issues, isNotEmpty);
        expect(
          review.issues.any((i) => i.code == ImportIssueCode.persistence),
          isFalse,
        );
      }
    },
  );

  test('Rechaza alta y vinculación simultáneas, planes sobrantes y cuenta inválida', () async {
    final ref = ImportCategoryReference(['Otra']);
    final reviews = [
      await preview(
        [real()],
        bindings: ImportReferenceBindings(
          accounts: {accountRef: 'a'},
          newAccounts: {
            accountRef: ImportNewAccount(
              name: 'Otra',
              activeFrom: Month(2026, 1),
              liquidity: Liquidity.liquid,
            ),
          },
        ),
      ),
      await preview(
        [budget()],
        bindings: ImportReferenceBindings(
          categories: {rootRef: 'g'},
          newCategories: {
            rootRef: const ImportNewCategory(name: 'Gastos', isIncome: false),
          },
        ),
      ),
      await preview(
        [real()],
        bindings: ImportReferenceBindings(
          newCategories: {
            ref: const ImportNewCategory(name: 'Otra', isIncome: false),
          },
        ),
      ),
      await preview(
        [real()],
        bindings: ImportReferenceBindings(
          newAccounts: {
            accountRef: ImportNewAccount(
              name: ' ',
              activeFrom: Month(2026, 2),
              activeThrough: Month(2026, 1),
              liquidity: Liquidity.liquid,
            ),
          },
        ),
      ),
    ];
    for (final review in reviews) {
      blocked(review);
    }
  });

  test('Conflictos mismo nodo y padre/descendiente entre filas en ambas direcciones', () async {
    for (final refs in [
      [rootRef, rootRef],
      [rootRef, childRef],
      [childRef, rootRef],
    ]) {
      final review = await preview([
        budget(ordinal: 2, category: refs[0], amount: 0),
        budget(ordinal: 7, category: refs[1]),
      ]);
      blocked(review);
      expect(
        review.issues
            .where((i) => i.code == ImportIssueCode.budgetConflict)
            .map((i) => i.sourceOrdinal),
        [2, 7],
      );
    }
    final alias = ImportCategoryReference(['Alias']);
    blocked(
      await preview([
        budget(ordinal: 2),
        budget(category: alias),
      ], bindings: ImportReferenceBindings(categories: {alias: 'g'})),
    );
  });

  test('Conflictos con base incluyen cero y archivadas, mismo mes en ambas direcciones', () async {
    for (final category in ['g', 'c']) {
      final record = BudgetRecord(
        id: 'guardada',
        data: BudgetInput(
          month: BudgetMonth(2026, 1),
          categoryId: category,
          amountCents: 0,
        ),
      );
      for (final ref in [rootRef, childRef]) {
        final review = await preview([
          budget(category: ref),
        ], data: snapshot(budgets: [record]));
        blocked(review);
        expect(review.issues.single.reason, contains('guardada'));
        expect(review.issues.single.sourceOrdinal, 3);
      }
    }
    final data = snapshot(
      categories: [
        node('g'),
        node('c', parent: 'g', archived: true, depth: 2),
      ],
      budgets: [
        BudgetRecord(
          id: 'archivada',
          data: BudgetInput(
            month: BudgetMonth(2026, 1),
            categoryId: 'c',
            amountCents: 0,
          ),
        ),
      ],
    );
    blocked(await preview([budget()], data: data));
    expect(
      (await preview([budget(month: 2)], data: data)).canRequestConfirmation,
      isTrue,
    );
  });

  test('Hermanas y meses distintos válidos, planes nuevos participan en conflictos', () async {
    final sibling = ImportCategoryReference(['Gastos', 'Otra']);
    final bindings = ImportReferenceBindings(
      newCategories: {
        sibling: const ImportNewCategory(
          name: 'Otra',
          parent: ImportCategoryTarget.existing('g'),
        ),
      },
    );
    expect(
      (await preview([
        budget(category: childRef),
        budget(ordinal: 4, category: sibling),
        budget(ordinal: 5, month: 2),
      ], bindings: bindings)).canRequestConfirmation,
      isTrue,
    );
    blocked(
      await preview([
        budget(),
        budget(ordinal: 4, category: sibling),
      ], bindings: bindings),
    );
    final data = snapshot(
      budgets: [
        BudgetRecord(
          id: 'base',
          data: BudgetInput(
            month: BudgetMonth(2026, 1),
            categoryId: 'g',
            amountCents: -100,
          ),
        ),
      ],
    );
    blocked(
      await preview(
        [budget(category: sibling)],
        data: data,
        bindings: bindings,
      ),
    );
  });

  test('Solapamientos por cuatro campos exactos normalizados, cada ordinal se conserva', () async {
    MovementRecord existing(
      String id, {
      String accountId = 'a',
      int amount = -1250,
      int day = 5,
      String concept = 'cAFÉ',
      String? batch = 'otro',
    }) => MovementRecord(
      id: id,
      batchId: batch,
      data: MovementInput(
        accountId: accountId,
        valueDate: ValueDate(2026, 1, day),
        concept: concept,
        amountCents: amount,
      ),
    );
    final data = snapshot(
      movements: [
        existing('m'),
        existing('m2', concept: ' CAFÉ '),
        existing('cuenta', accountId: 'b'),
        existing('importe', amount: 1250),
        existing('fecha', day: 6),
        existing('interior', concept: 'Ca fé'),
        existing('acento', concept: 'Cafe'),
        existing('manual', batch: null),
      ],
    );
    final review = await preview([real(), real(ordinal: 3)], data: data);
    expect(review.movementCount, 2);
    expect(review.overlaps.map((o) => o.key), ['2:m', '2:m2', '3:m', '3:m2']);
    expect(review.canRequestConfirmation, isTrue);
    expect(() => ImportConfirmationRequest(review: review), throwsStateError);
    expect(
      () => ImportConfirmationRequest(
        review: review,
        reviewedOverlapKeys: {'2:m', '2:m2', '3:m'},
      ),
      throwsStateError,
    );
    final request = ImportConfirmationRequest(
      review: review,
      reviewedOverlapKeys: review.overlaps.map((o) => o.key).toSet(),
    );
    expect(request.review.movementCount, 2);
  });

  test(
    'Mismos bytes no se comparan con su propio lote y el nombre no participa',
    () async {
      final rows = [real(), budget()];
      final data = snapshot(
        sameFileBatchId: 'mismo',
        movements: [
          MovementRecord(
            id: 'm',
            batchId: 'mismo',
            data: (rows.first as InterpretedMovement).toMovementInput(
              accountId: 'a',
            ),
          ),
        ],
        budgets: [
          BudgetRecord(
            id: 'b',
            batchId: 'mismo',
            data: (rows.last as InterpretedBudget).toBudgetInput(
              categoryId: 'g',
            ),
          ),
        ],
      );
      final review = await ValidatingImportPreviewer(FixtureSource(data))
          .preview(draft(rows, name: 'renombrado.csv'));
      expect(review.issues, isEmpty);
      expect(review.overlaps, isEmpty);
      expect(review.canRequestConfirmation, isTrue);
    },
  );

  test(
    'Fallo de lectura, lote vacío y ordinales inválidos bloquean todo',
    () async {
      final failed = await ValidatingImportPreviewer(FailingSource())
          .preview(draft([real()]));
      blocked(failed);
      expect(failed.issues.single.code, ImportIssueCode.persistence);
      blocked(await preview([]));
      blocked(await preview([real(ordinal: 1), budget(ordinal: 1)]));
    },
  );
}
