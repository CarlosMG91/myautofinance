import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/core/persistence/unit_of_work.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/movements/movements.dart';

const root = '91000000-0000-4000-8000-000000000001';
const child = '91000000-0000-4000-8000-000000000002';
const sibling = '91000000-0000-4000-8000-000000000003';
const leaf = '91000000-0000-4000-8000-000000000004';
const archived = '91000000-0000-4000-8000-000000000005';
const income = '91000000-0000-4000-8000-000000000006';
const incomeChild = '91000000-0000-4000-8000-000000000007';

CategoryDetails category(
  String id,
  String? parent,
  int depth,
  String path, {
  bool isIncome = false,
  bool isArchived = false,
}) => CategoryDetails(
  node: CategoryNode(
    id: id,
    parentId: parent,
    name: path.split(' / ').last,
    isIncome: isIncome,
    archived: isArchived,
    depth: depth,
  ),
  path: path,
);

BudgetProposalDraft initial({int source = -35025}) {
  final categories = [
    category(root, null, 1, 'Alimentación'),
    category(child, root, 2, 'Alimentación / Compra'),
    category(sibling, root, 2, 'Alimentación / Compra'),
    category(leaf, child, 3, 'Alimentación / Compra / Mercado'),
    category(archived, root, 2, 'Alimentación / Antigua', isArchived: true),
    category(income, null, 1, 'Ingresos', isIncome: true),
    // Deliberadamente contrario a la raíz: los avisos deben usar la raíz.
    category(incomeChild, income, 2, 'Ingresos / Nómina'),
  ];
  final rows = [
    for (final r in categories.where((c) => c.node.parentId == null))
      for (var month = 1; month <= 12; month++)
        BudgetProposalRow(
          root: r,
          sourceMonth: BudgetMonth(2026, month),
          targetMonth: BudgetMonth(2027, month),
          sourceAmountCents: r.node.id == root && month == 1 ? source : 0,
          proposedAmountCents: r.node.id == root && month == 1
              ? (source > 0 ? 36000 : -36000)
              : 0,
          sourceMovementCount: r.node.id == root && month == 1 ? 1 : 0,
        ),
  ];
  return BudgetProposalDraft(
    sourceYear: 2026,
    targetYear: 2027,
    sourceRows: rows,
    allocations: rows.map(
      (r) => BudgetInput(
        month: r.targetMonth,
        categoryId: r.categoryId,
        amountCents: r.proposedAmountCents,
      ),
    ),
    includedScopes: rows.map(
      (r) => BudgetProposalScope(rootId: r.categoryId, month: r.targetMonth),
    ),
    excludedReals: [
      const BudgetProposalExcludedReal(
        real: BudgetProposalSourceReal(
          id: '92000000-0000-4000-8000-000000000001',
          valueDate: '2026-01-08',
          categoryId: null,
          amountCents: 700,
        ),
        reason: BudgetProposalExclusionReason.unclassified,
        categoryPath: null,
      ),
    ],
    basis: BudgetProposalBasis(
      sourceYear: 2026,
      datasetState: const DatasetState(
        datasetId: 'synthetic-dataset',
        revision: 7,
      ),
      categories: categories,
      sourceReals: [],
      targetBudgets: [],
    ),
  );
}

BudgetProposalDraft withAllocations(
  BudgetProposalDraft draft,
  List<BudgetInput> allocations,
) => BudgetProposalDraft(
  sourceYear: draft.sourceYear,
  targetYear: draft.targetYear,
  sourceRows: draft.sourceRows,
  allocations: allocations,
  includedScopes: draft.includedScopes,
  excludedReals: draft.excludedReals,
  basis: draft.basis,
);

BudgetProposalSplitAllocation splitRow(String id, int cents) =>
    BudgetProposalSplitAllocation(categoryId: id, amountCents: cents);

BudgetProposalDraft withCategories(
  BudgetProposalDraft draft,
  List<CategoryDetails> categories,
) => BudgetProposalDraft(
  sourceYear: draft.sourceYear,
  targetYear: draft.targetYear,
  sourceRows: draft.sourceRows,
  allocations: draft.allocations,
  includedScopes: draft.includedScopes,
  excludedReals: draft.excludedReals,
  basis: BudgetProposalBasis(
    sourceYear: draft.basis.sourceYear,
    datasetState: draft.basis.datasetState,
    categories: categories,
    sourceReals: draft.basis.sourceReals,
    targetBudgets: draft.basis.targetBudgets,
  ),
);

Matcher failure(BudgetProposalEditFailureCode code) =>
    isA<BudgetProposalEditFailure>().having((e) => e.code, 'código', code);

void main() {
  final january = BudgetMonth(2027, 1);
  final february = BudgetMonth(2027, 2);
  late BudgetProposalDraft start;
  late BudgetProposalEditor editor;
  setUp(() {
    start = initial();
    editor = BudgetProposalEditor(start);
  });

  BudgetInput allocation(String id, BudgetMonth month) => editor
      .draft
      .allocations
      .singleWhere((a) => a.categoryId == id && a.month.value == month.value);

  test('Edita céntimos firmados y cero sin redondear ni cambiar fuente', () {
    for (final value in [-35213, 0, 129, -9223372036854775808]) {
      editor.editAmount(month: january, categoryId: root, amountCents: value);
      expect(allocation(root, january).amountCents, value);
    }
    expect(start.allocations.first.amountCents, -36000);
    expect(editor.draft.sourceRows, start.sourceRows);
    expect(editor.draft.sourceRows.first.sourceAmountCents, -35025);
    expect(editor.draft.sourceRows.first.proposedAmountCents, -36000);
    expect(editor.draft.basis, same(start.basis));
    expect(editor.draft.includedScopes, start.includedScopes);
    expect(editor.draft.excludedReals, start.excludedReals);
    expect(allocation(root, february).amountCents, 0);
  });

  test('Los metadatos de una partida editada se conservan', () {
    final before = start.allocations.first;
    editor = BudgetProposalEditor(
      withAllocations(start, [
        BudgetInput(
          month: before.month,
          categoryId: before.categoryId,
          amountCents: before.amountCents,
          concept: 'Concepto sintético',
          discretion: 'Necesario',
        ),
        ...start.allocations.skip(1),
      ]),
    );
    editor.editAmount(month: january, categoryId: root, amountCents: 0);
    expect(allocation(root, january).concept, 'Concepto sintético');
    expect(allocation(root, january).discretion, 'Necesario');
  });

  test('Desglosa padre solo en enero, permite hermanos y niveles 2/3', () {
    editor.split(
      month: january,
      parentCategoryId: root,
      allocations: [splitRow(leaf, -20000), splitRow(sibling, -16000)],
    );
    expect(allocation(leaf, january).amountCents, -20000);
    expect(allocation(sibling, january).amountCents, -16000);
    expect(
      editor.draft.allocations.where(
        (a) => a.categoryId == root && a.month.value == january.value,
      ),
      isEmpty,
    );
    expect(allocation(root, february).amountCents, 0);
    expect(editor.draft.includedScopes, start.includedScopes);
    expect(editor.validatedDraft(), same(editor.draft));
    expect(editor.draft.sourceRows, start.sourceRows);
  });

  test('El desglose puede continuar hasta el tercer nivel', () {
    editor.split(
      month: january,
      parentCategoryId: root,
      allocations: [splitRow(child, -36000)],
    );
    editor.split(
      month: january,
      parentCategoryId: child,
      allocations: [splitRow(leaf, -36000)],
    );
    expect(allocation(leaf, january).amountCents, -36000);
    expect(
      editor.splitOptions(month: january, parentCategoryId: leaf),
      isEmpty,
    );
  });

  test('Suma distinta exige nuevo total explícito y coincidente', () {
    expect(
      () => editor.split(
        month: january,
        parentCategoryId: root,
        allocations: [splitRow(child, -30000)],
      ),
      throwsA(failure(BudgetProposalEditFailureCode.totalChangeRequiresEdit)),
    );
    expect(editor.draft, same(start));
    expect(
      () => editor.split(
        month: january,
        parentCategoryId: root,
        allocations: [splitRow(child, -30000)],
        explicitlyEditedTotalCents: -29999,
      ),
      throwsA(failure(BudgetProposalEditFailureCode.totalMismatch)),
    );
    expect(editor.draft, same(start));
    editor.split(
      month: january,
      parentCategoryId: root,
      allocations: [splitRow(child, -30000)],
      explicitlyEditedTotalCents: -30000,
    );
    expect(allocation(child, january).amountCents, -30000);
  });

  test('Se puede editar el total del padre antes de desglosar', () {
    editor.editAmount(month: january, categoryId: root, amountCents: 0);
    editor.split(
      month: january,
      parentCategoryId: root,
      allocations: [splitRow(child, -100), splitRow(sibling, 100)],
    );
    expect(allocation(child, january).amountCents, -100);
    expect(allocation(sibling, january).amountCents, 100);
    expect(editor.draft.requiresSignReview, isTrue);
  });

  test('Cero explícito en descendiente es válido y no se elimina', () {
    editor.split(
      month: february,
      parentCategoryId: root,
      allocations: [splitRow(child, 0), splitRow(sibling, 0)],
    );
    expect(allocation(child, february).amountCents, 0);
    expect(allocation(sibling, february).amountCents, 0);
    expect(editor.validatedDraft().requiresSignReview, isFalse);
  });

  test('UUID y ruta para nombres iguales; destinos activos', () {
    final options = editor.splitOptions(month: january, parentCategoryId: root);
    expect(options.map((c) => c.node.id), containsAll([child, sibling, leaf]));
    expect(options.map((c) => c.node.id), isNot(contains(archived)));
    expect(options.map((c) => c.node.id), isNot(contains(incomeChild)));
    expect(
      options.where((c) => c.path == 'Alimentación / Compra'),
      hasLength(2),
    );
    expect(() => options.clear(), throwsUnsupportedError);
    editor.split(
      month: january,
      parentCategoryId: root,
      allocations: [splitRow(child, -20000), splitRow(sibling, -16000)],
    );
    editor.editAmount(month: january, categoryId: sibling, amountCents: -15999);
    expect(allocation(child, january).amountCents, -20000);
    expect(allocation(sibling, january).amountCents, -15999);
  });

  test(
    'Rechaza vacíos, ajenos, padre, archivados y desconocidos sin mutar',
    () {
      final cases =
          <
            (List<BudgetProposalSplitAllocation>, BudgetProposalEditFailureCode)
          >[
            ([], BudgetProposalEditFailureCode.invalidSplit),
            (
              [splitRow(incomeChild, -36000)],
              BudgetProposalEditFailureCode.invalidSplit,
            ),
            (
              [splitRow(root, -36000)],
              BudgetProposalEditFailureCode.invalidSplit,
            ),
            (
              [splitRow(archived, -36000)],
              BudgetProposalEditFailureCode.categoryArchived,
            ),
            (
              [splitRow('missing', -36000)],
              BudgetProposalEditFailureCode.categoryNotFound,
            ),
          ];
      for (final entry in cases) {
        expect(
          () => editor.split(
            month: january,
            parentCategoryId: root,
            allocations: entry.$1,
          ),
          throwsA(failure(entry.$2)),
        );
        expect(editor.draft, same(start));
      }
    },
  );

  test('Rechaza duplicados y padre/descendiente aunque conserven suma', () {
    for (final entry in [
      (
        [splitRow(child, -18000), splitRow(child, -18000)],
        BudgetProposalEditFailureCode.duplicateCategoryMonth,
      ),
      (
        [splitRow(child, -18000), splitRow(leaf, -18000)],
        BudgetProposalEditFailureCode.ancestorDescendantConflict,
      ),
    ]) {
      expect(
        () => editor.split(
          month: january,
          parentCategoryId: root,
          allocations: entry.$1,
        ),
        throwsA(failure(entry.$2)),
      );
      expect(editor.draft, same(start));
    }
  });

  test('Suma exacta BigInt antes de validar int64; detecta overflow', () {
    editor.editAmount(month: january, categoryId: root, amountCents: -1);
    editor.split(
      month: january,
      parentCategoryId: root,
      allocations: [
        splitRow(child, -9223372036854775808),
        splitRow(sibling, 9223372036854775807),
      ],
    );
    expect(allocation(child, january).amountCents, -9223372036854775808);
    final before = editor.draft;
    expect(
      () => editor.split(
        month: february,
        parentCategoryId: root,
        allocations: [
          splitRow(child, 9223372036854775807),
          splitRow(sibling, 1),
        ],
        explicitlyEditedTotalCents: 0,
      ),
      throwsA(failure(BudgetProposalEditFailureCode.overflow)),
    );
    expect(editor.draft, same(before));
  });

  test(
    'Edición crea aviso firmado, exige revisión e invalida tras cambios',
    () {
      editor.editAmount(month: january, categoryId: root, amountCents: 123);
      final warning = editor.draft.signWarnings.single;
      expect(warning.origin, BudgetProposalSignOrigin.allocation);
      expect(warning.categoryId, root);
      expect(warning.categoryPath, 'Alimentación');
      expect(warning.month.value, january.value);
      expect(warning.amountCents, 123);
      expect(
        editor.validatedDraft,
        throwsA(failure(BudgetProposalEditFailureCode.signsNotReviewed)),
      );
      editor.setSignsReviewed(true);
      expect(editor.validatedDraft().signsReviewed, isTrue);
      final reviewed = editor.draft;
      editor.editAmount(month: january, categoryId: root, amountCents: 123);
      expect(editor.draft, same(reviewed));
      expect(
        () => editor.split(
          month: january,
          parentCategoryId: root,
          allocations: [splitRow(child, 1)],
        ),
        throwsA(failure(BudgetProposalEditFailureCode.totalChangeRequiresEdit)),
      );
      expect(editor.draft, same(reviewed));
      editor.editAmount(month: january, categoryId: root, amountCents: 124);
      expect(editor.draft.signsReviewed, isFalse);
      editor.setSignsReviewed(true);
      editor.setSignsReviewed(false);
      expect(
        editor.validatedDraft,
        throwsA(failure(BudgetProposalEditFailureCode.signsNotReviewed)),
      );
      editor.editAmount(month: january, categoryId: root, amountCents: 0);
      expect(editor.validatedDraft().requiresSignReview, isFalse);
    },
  );

  test('Desglose detecta signos individuales por raíz e invalida revisión', () {
    editor.editAmount(month: january, categoryId: income, amountCents: -100);
    editor.setSignsReviewed(true);
    editor.split(
      month: january,
      parentCategoryId: income,
      allocations: [splitRow(incomeChild, -100)],
    );
    expect(editor.draft.signsReviewed, isFalse);
    expect(editor.draft.signWarnings.single.categoryId, incomeChild);
    expect(
      editor.validatedDraft,
      throwsA(failure(BudgetProposalEditFailureCode.signsNotReviewed)),
    );
    editor.editAmount(
      month: january,
      categoryId: incomeChild,
      amountCents: 100,
    );
    expect(editor.draft.requiresSignReview, isFalse);
    editor.split(
      month: january,
      parentCategoryId: root,
      allocations: [splitRow(child, -36100), splitRow(sibling, 100)],
    );
    expect(editor.draft.signWarnings.single.categoryId, sibling);
    expect(
      editor.draft.signWarnings.single.categoryPath,
      'Alimentación / Compra',
    );
  });

  test('Aviso del real fuente permanece aunque se corrija la propuesta', () {
    editor = BudgetProposalEditor(initial(source: 35025));
    expect(editor.draft.signWarnings, hasLength(2));
    editor.setSignsReviewed(true);
    editor.editAmount(month: january, categoryId: root, amountCents: -36000);
    expect(editor.draft.signsReviewed, isFalse);
    final warning = editor.draft.signWarnings.single;
    expect(warning.origin, BudgetProposalSignOrigin.sourceReal);
    expect(warning.month.value, '2026-01-01');
    expect(warning.amountCents, 35025);
    editor.setSignsReviewed(true);
    expect(editor.validatedDraft().signsReviewed, isTrue);
  });

  test('Validador público rechaza borradores construidos fuera del editor', () {
    const validator = BudgetProposalDraftValidator();
    for (final entry in [
      (
        BudgetInput(month: january, categoryId: root, amountCents: 0),
        BudgetProposalEditFailureCode.duplicateCategoryMonth,
      ),
      (
        BudgetInput(month: january, categoryId: leaf, amountCents: 0),
        BudgetProposalEditFailureCode.ancestorDescendantConflict,
      ),
      (
        BudgetInput(month: january, categoryId: archived, amountCents: 0),
        BudgetProposalEditFailureCode.categoryArchived,
      ),
      (
        BudgetInput(
          month: BudgetMonth(2026, 1),
          categoryId: child,
          amountCents: 0,
        ),
        BudgetProposalEditFailureCode.invalidDraft,
      ),
    ]) {
      expect(
        () => validator.validate(
          withAllocations(start, [...start.allocations, entry.$1]),
        ),
        throwsA(failure(entry.$2)),
      );
    }
  });

  test('Mes/nodo inexistentes rechazan sin modificar el borrador', () {
    expect(
      () =>
          editor.editAmount(month: january, categoryId: child, amountCents: 0),
      throwsA(failure(BudgetProposalEditFailureCode.allocationNotFound)),
    );
    expect(
      () => editor.split(
        month: BudgetMonth(2028, 1),
        parentCategoryId: root,
        allocations: [splitRow(child, -36000)],
      ),
      throwsA(failure(BudgetProposalEditFailureCode.allocationNotFound)),
    );
    expect(editor.draft, same(start));
  });

  test('No admite cuarto nivel ni destinos con ancestro archivado', () {
    const fourth = '91000000-0000-4000-8000-000000000008';
    const inactiveChild = '91000000-0000-4000-8000-000000000009';
    editor = BudgetProposalEditor(
      withCategories(start, [
        ...start.basis.categories,
        category(fourth, leaf, 4, 'Alimentación / Compra / Mercado / Puesto'),
        category(inactiveChild, archived, 3, 'Alimentación / Antigua / Compra'),
      ]),
    );
    final before = editor.draft;
    for (final entry in [
      (fourth, BudgetProposalEditFailureCode.invalidDraft),
      (inactiveChild, BudgetProposalEditFailureCode.categoryArchived),
    ]) {
      expect(
        () => editor.split(
          month: january,
          parentCategoryId: root,
          allocations: [splitRow(entry.$1, -36000)],
        ),
        throwsA(failure(entry.$2)),
      );
      expect(editor.draft, same(before));
    }
  });

  test('Cambiar otra cifra también invalida la casilla global de revisión', () {
    editor.editAmount(month: january, categoryId: root, amountCents: 123);
    editor.setSignsReviewed(true);
    editor.editAmount(month: february, categoryId: root, amountCents: -1);
    expect(editor.draft.signWarnings.single.amountCents, 123);
    expect(editor.draft.signsReviewed, isFalse);
    expect(
      editor.validatedDraft,
      throwsA(failure(BudgetProposalEditFailureCode.signsNotReviewed)),
    );
  });

  test('Cancelar cierra sesión; otra instancia no recupera ediciones', () {
    editor.editAmount(month: january, categoryId: root, amountCents: 1);
    editor.setSignsReviewed(true);
    editor.cancel();
    editor.cancel();
    expect(editor.isClosed, isTrue);
    for (final action in <void Function()>[
      () => editor.draft,
      () => editor.validatedDraft(),
      () => editor.editAmount(month: january, categoryId: root, amountCents: 0),
      () => editor.splitOptions(month: january, parentCategoryId: root),
      () =>
          editor.split(month: january, parentCategoryId: root, allocations: []),
      () => editor.setSignsReviewed(true),
    ]) {
      expect(
        action,
        throwsA(failure(BudgetProposalEditFailureCode.sessionClosed)),
      );
    }
    final fresh = BudgetProposalEditor(start);
    expect(fresh.draft.allocations.first.amountCents, -36000);
    expect(fresh.draft.signsReviewed, isFalse);
    expect(fresh.validatedDraft().requiresSignReview, isFalse);
    expect(() => start.allocations.clear(), throwsUnsupportedError);
  });
}
