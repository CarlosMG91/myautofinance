import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/csv_import_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/data/native_local_csv_selector.dart';
import 'package:myautofinance/features/importing/historical_csv.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/importing/presentation/import_controller.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import 'csv_test_bundle.dart';

const csvHeader =
    'fecha;concepto;importe_eur;tipo;categoria;subcategoria;subsubcategoria;cuenta_origen;discrecionalidad';

/// Misma batería en VM y runners Windows/Android. El diálogo/proveedor nativo
/// se sustituye en un canal exclusivo de prueba; los bytes se leen de archivos
/// físicos. SHA/lector, controlador, revisión y persistencia son productivos.
final class CsvImportJourney {
  CsvImportJourney(this.directory)
    : store = LocalDatabaseStore(supportDirectory: () async => directory);
  final Directory directory;
  final LocalDatabaseStore store;
  late LocalDatabase db;
  late ImportController controller;
  bool _controllerCreated = false;
  final selections = <Object?>[];
  static const channel = MethodChannel('autofinance/csv-fixture-122');

  ImportServices get services => createImportServices(db);

  Future<void> open() async {
    for (final entry in csvTestBundle.entries) {
      await File('${directory.path}/${entry.key}')
          .writeAsBytes(base64Decode(entry.value));
    }
    db = await store.open();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'select');
          expect(call.arguments, isNull);
          final next = selections.removeAt(0);
          if (next is PlatformException) throw next;
          if (next == null) return null;
          final file = next as File;
          try {
            return {
              'name': file.uri.pathSegments.last,
              'bytes': await file.readAsBytes(),
            };
          } on FileSystemException {
            throw PlatformException(code: 'unavailable');
          }
        });
    controller = createCsvImportController(
      () async => createImportServices(await store.open()),
      selector: NativeLocalCsvSelector(channel: channel),
    );
    _controllerCreated = true;
  }

  Future<void> close() async {
    if (_controllerCreated) controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await store.close();
  }

  Future<File> write(String name, String text) =>
      File('${directory.path}/$name').writeAsString(text, encoding: utf8);

  Future<void> select(String name, {bool replace = true}) async {
    selections.add(File('${directory.path}/$name'));
    await controller.selectCsv(approveReplacement: () async => replace);
  }

  Future<Map<String, Object?>> image() async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();
    return {
      for (final table in tables)
        table.read<String>(
          'name',
        ): (await db
                .customSelect(
                  'SELECT * FROM "${table.read<String>('name')}" ORDER BY rowid',
                )
                .get())
            .map((r) => r.data)
            .toList(),
    };
  }

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT count(*) AS n FROM $table').getSingle())
          .read<int>('n');

  /// Aprobación expresa del arnés: sólo Ingresos es raíz de ingreso.
  /// Nunca deduce la marca del importe; reutiliza los UUID existentes.
  Future<void> approveMissingReferences() async {
    final session = controller.session!;
    final snapshot = controller.snapshot!;
    final bindings = controller.review!.bindings;
    final accountPlans = Map<ImportAccountReference, ImportNewAccount>.of(
      bindings.newAccounts,
    );
    final categoryPlans = Map<ImportCategoryReference, ImportNewCategory>.of(
      bindings.newCategories,
    );
    final categories = Map<ImportCategoryReference, String>.of(
      bindings.categories,
    );
    for (final row in session.interpretation.rows) {
      if (row is InterpretedMovement &&
          !bindings.accounts.containsKey(row.account)) {
        accountPlans[row.account] = ImportNewAccount(
          name: row.account.name!,
          activeFrom: Month(2026, 1),
          liquidity: Liquidity.liquid,
        );
      }
      final reference = switch (row) {
        InterpretedMovement() => row.category,
        InterpretedBudget() => row.category,
      };
      if (reference == null) continue;
      String? parentId;
      ImportCategoryReference? parentRef;
      for (var depth = 1; depth <= reference.path.length; depth++) {
        final prefix = ImportCategoryReference(
          reference.path.take(depth).toList(),
        );
        final matches = snapshot.categories
            .where(
              (node) =>
                  node.parentId == parentId &&
                  node.name.toLowerCase() == prefix.path.last.toLowerCase() &&
                  (depth == 1 || parentId != null),
            )
            .toList();
        if (matches.length == 1) {
          parentId = matches.single.id;
          categories[prefix] = parentId;
        } else {
          expect(
            matches,
            isEmpty,
            reason: 'Ambigüedades requieren elección de UUID.',
          );
          categoryPlans[prefix] = ImportNewCategory(
            name: prefix.path.last,
            isIncome: depth == 1 ? prefix.path.first == 'Ingresos' : null,
            parent: depth == 1
                ? null
                : parentId != null
                ? ImportCategoryTarget.existing(parentId)
                : ImportCategoryTarget.proposed(parentRef!),
          );
          parentId = null;
        }
        parentRef = prefix;
      }
    }
    await controller.refresh(
      bindings: ImportReferenceBindings(
        accounts: bindings.accounts,
        categories: categories,
        newAccounts: accountPlans,
        newCategories: categoryPlans,
      ),
    );
  }

  Future<ImportBatch> confirm() async {
    expect(controller.canConfirm, isTrue);
    await controller.confirm();
    expect(
      controller.result,
      isA<ImportConfirmed>(),
      reason: '${controller.failures.map((i) => i.reason)}',
    );
    return (controller.result as ImportConfirmed).batch;
  }

  Future<void> reference() async {
    final empty = await image();
    final initialRevision = (await db.readState()).revision;
    await select('historico-ejemplo.csv');
    expect(controller.canConfirm, isFalse);
    final review = controller.review!;
    expect(review.movementCount, 10);
    expect(review.budgetCount, 48);
    expect(
      review.totalCents(budgets: false, original: true),
      BigInt.from(232965),
    );
    expect(
      review.totalCents(budgets: false, original: false),
      BigInt.from(232965),
    );
    expect(
      review.totalCents(budgets: true, original: true),
      BigInt.from(-1320000),
    );
    expect(
      review.totalCents(budgets: true, original: false),
      BigInt.from(1320000),
    );
    await approveMissingReferences();
    expect(await image(), empty);
    final file = controller.session!.file;
    final batch = await confirm();
    expect(batch.movementCount, 10);
    expect(batch.budgetCount, 48);
    expect((await db.readState()).revision, initialRevision + 1);
    final committed = await image();
    await store.close();
    db = await store.open();
    final reopened = await image();
    // Estado temporal por conexión; todas las tablas duraderas se comparan.
    expect(
      Map.of(reopened)..remove('local_mutation'),
      Map.of(committed)..remove('local_mutation'),
    );
    final metadata = (await services.history.getBatch(batch.id))!;
    expect(metadata.sha256, file.sha256);
    expect(metadata.originalName, 'historico-ejemplo.csv');
    expect(metadata.source, ImportSource.historicalCsv);
    expect(metadata.contractVersion, importContractVersion);
    expect(metadata.formatVersion, historicalCsvVersion);
    expect(DateTime.tryParse(metadata.importedAt), isNotNull);
    expect(metadata.importedAt, batch.importedAt);
    final rows = (await services.history.listRows(batch.id)).items;
    expect(rows.map((r) => r.sourceOrdinal), List.generate(58, (i) => i + 2));
    for (final row in rows) {
      expect(row.original!.originalFields, hasLength(9));
      expect(
        row.currentMovement?.importRowId ?? row.currentBudget?.importRowId,
        row.id,
      );
      expect((await services.history.getRow(row.id))!.batchId, batch.id);
      expect(
        row.original!.amount.internalCents,
        row.currentMovement?.data.amountCents ??
            row.currentBudget!.data.amountCents,
      );
    }
    final movements = SqliteMovementRepository(db);
    expect(
      (await movements.readMonth(
        2026,
        1,
      )).fold<int>(0, (n, r) => n + r.data.amountCents),
      122975,
    );
    expect(
      (await movements.readMonth(
        2026,
        2,
      )).fold<int>(0, (n, r) => n + r.data.amountCents),
      109990,
    );
    expect(
      (await movements.readYear(2026))
          .fold<int>(0, (n, r) => n + r.data.amountCents),
      232965,
    );
    final cafes = rows.where((r) => r.original!.concept == 'Café').toList();
    expect(cafes, hasLength(2));
    expect(cafes[0].id, isNot(cafes[1].id));
    expect(
      cafes.every((r) => r.original!.discretion == 'Discrecional'),
      isTrue,
    );
    var annual = 0;
    for (var month = 1; month <= 12; month++) {
      final budgets = await SqliteBudgetRepository(db)
          .list(BudgetMonth(2026, month));
      expect(budgets, hasLength(4));
      final sum = budgets.fold<int>(0, (n, r) => n + r.data.amountCents);
      expect(sum, 110000);
      annual += sum;
    }
    expect(annual, 1320000);
    final nodes = await SqliteCategoryRepository(db).list();
    expect(nodes.where((n) => n.isIncome).map((n) => n.name).toSet(), {
      'Ingresos',
      'Salario',
    });
    expect(await count('wealth_snapshots'), 0);
    final beforeRepeat = await image();
    await File('${directory.path}/renombrado.csv').writeAsBytes(file.bytes);
    await select('renombrado.csv');
    expect(controller.result, isA<ImportAlreadyImported>());
    expect((controller.result as ImportAlreadyImported).batch.id, batch.id);
    expect(controller.canConfirm, isFalse);
    await controller.confirm();
    expect(await image(), beforeRepeat);
    // Los bytes físicos nuevos obligan a validar de nuevo los presupuestos.
    for (final content in [
      '\uFEFF${utf8.decode(file.bytes).replaceAll('\r\n', '\n')}',
      utf8.decode(file.bytes).replaceAll('\r\n', '\n').replaceAll('\n', '\r\n'),
    ]) {
      await write('otra-codificacion.csv', content);
      await select('otra-codificacion.csv');
      expect(controller.session!.file.sha256, isNot(file.sha256));
      expect(controller.result, isNull);
      expect(
        controller.review!.issues.any(
          (i) => i.code == ImportIssueCode.budgetConflict,
        ),
        isTrue,
      );
      await controller.confirm();
      expect(await image(), beforeRepeat);
    }
  }

  Future<void> fixtures() async {
    const valid = {
      'valido-lf.csv': (3, 2),
      'valido-crlf-bom.csv': (3, 2),
      'valido-comillas-multilinea.csv': (1, 1),
      'tipo-minusculas-y-espacios.csv': (1, 0),
      'referencias-renombradas.csv': (3, 2),
      'dos-reales-iguales.csv': (2, 0),
      'bytes-distintos-contenido-similar.csv': (2, 0),
      'referencia-ambigua.csv': (1, 0),
      'presupuesto-cero-admitido.csv': (0, 1),
    };
    const conflicts = {
      'conflicto-padre-descendiente.csv',
      'conflicto-mes-y-nodo.csv',
    };
    final empty = await image();
    for (final name in csvTestBundle.keys.where(
      (n) => n != 'historico-ejemplo.csv',
    )) {
      await select(name);
      if (valid.containsKey(name)) {
        expect(controller.session!.issues, isEmpty, reason: name);
        await approveMissingReferences();
        expect(controller.canConfirm, isTrue, reason: name);
        expect((
          controller.review!.movementCount,
          controller.review!.budgetCount,
        ), valid[name]);
        if (name == 'valido-lf.csv') {
          expect(
            controller.review!.totalCents(budgets: false, original: false),
            BigInt.from(-5525),
          );
          expect(
            controller.review!.totalCents(budgets: true, original: true),
            BigInt.from(40000),
          );
          expect(
            controller.review!.totalCents(budgets: true, original: false),
            BigInt.from(-40000),
          );
        }
      } else if (conflicts.contains(name)) {
        await approveMissingReferences();
        expect(
          controller.review!.issues.any(
            (i) =>
                i.code == ImportIssueCode.budgetConflict &&
                i.sourceOrdinal != null &&
                i.field != null,
          ),
          isTrue,
          reason: name,
        );
        await controller.confirm();
      } else {
        expect(controller.session!.interpretation.rows, isEmpty, reason: name);
        expect(controller.review!.issues, isNotEmpty, reason: name);
        expect(controller.canConfirm, isFalse, reason: name);
        await controller.confirm();
      }
      expect(await image(), empty, reason: name);
    }
    expect(
      csvTestBundle['referencias-renombradas.csv'],
      csvTestBundle['valido-lf.csv'],
    );
  }

  Future<void> physicalLines() async {
    await select('valido-comillas-multilinea.csv');
    expect(
      controller.session!.interpretation.rows.map((r) => r.sourceOrdinal),
      [2, 3],
    );
    await approveMissingReferences();
    final batch = await confirm();
    final rows = (await services.history.listRows(batch.id)).items;
    expect(rows.map((r) => r.sourceOrdinal), [2, 3]);
    expect(
      rows.first.original!.concept,
      'Compra "especial"; con detalle\ny nota',
    );
    final before = await image();
    final text = utf8.decode(
      base64Decode(csvTestBundle['valido-comillas-multilinea.csv']!),
    );
    await write(
      'multilinea-invalido.csv',
      text.replaceFirst('2026-01-01', '2026-02-30'),
    );
    await select('multilinea-invalido.csv');
    final issue = controller.review!.issues.firstWhere(
      (i) => i.field == 'fecha',
    );
    expect(issue.sourceOrdinal, 3);
    expect(issue.reason, contains('línea física 4'));
    expect(controller.canConfirm, isFalse);
    await controller.confirm();
    expect(await image(), before);
  }

  Future<void> repeatsAndHistory() async {
    await select('dos-reales-iguales.csv');
    await approveMissingReferences();
    final batch = await confirm();
    final original = (await services.history.listRows(batch.id)).items;
    expect(original.map((r) => r.sourceOrdinal), [2, 3]);
    expect(
      original[0].currentMovement!.id,
      isNot(original[1].currentMovement!.id),
    );
    final lf = controller.session!.file;
    final text = utf8.decode(lf.bytes);
    for (final variant in ['\uFEFF$text', text.replaceAll('\n', '\r\n')]) {
      await write('variante.csv', variant);
      await select('variante.csv');
      expect(controller.session!.file.sha256, isNot(lf.sha256));
      expect(
        controller.review!.overlaps,
        hasLength(2 * await count('movements')),
      );
      expect(controller.canConfirm, isFalse);
      final before = await image();
      await controller.confirm();
      expect(await image(), before);
      for (final overlap in controller.review!.overlaps) {
        controller.markOverlap(overlap.key, true);
      }
      await confirm();
    }
    final movement = original.first.currentMovement!;
    await SqliteMovementRepository(db).edit(
      movement.id,
      MovementInput(
        accountId: movement.data.accountId,
        categoryId: movement.data.categoryId,
        valueDate: movement.data.valueDate,
        concept: 'Corregido',
        amountCents: -500,
        discretion: movement.data.discretion,
      ),
    );
    await SqliteMovementRepository(db)
        .delete(original.last.currentMovement!.id);
    final beforeRepeat = await image();
    await File('${directory.path}/copia-renombrada.csv').writeAsBytes(lf.bytes);
    await select('copia-renombrada.csv');
    expect((controller.result as ImportAlreadyImported).batch.id, batch.id);
    expect(await image(), beforeRepeat);
    await store.close();
    db = await store.open();
    final rows = (await services.history.listRows(batch.id)).items;
    expect(rows.first.original!.concept, 'Café');
    expect(rows.first.original!.amount.internalCents, -1000);
    expect(rows.first.currentMovement!.data.concept, 'Corregido');
    expect(rows.last.isDeleted, isTrue);
    expect(rows.last.original!.sourceOrdinal, 3);
    expect((await services.history.getBatch(batch.id))!.movementCount, 2);
    expect(await count('movements'), 5);
  }

  Future<void> selection() async {
    final empty = await image();
    await select('valido-lf.csv');
    await approveMissingReferences();
    final session = controller.session;
    final bindings = controller.review!.bindings;
    for (final value in [
      null,
      PlatformException(code: 'accessDenied'),
      PlatformException(code: 'readFailed'),
      File('${directory.path}/ausente.csv'),
    ]) {
      selections.add(value);
      await controller.selectCsv(approveReplacement: () async => true);
      expect(controller.session, same(session));
      expect(controller.review!.bindings, same(bindings));
      expect(controller.selectionMessage, isNotNull);
    }
    await select('dos-reales-iguales.csv', replace: false);
    expect(controller.session, same(session));
    // El archivo externo cambia después de leerlo: sesión conserva bytes.
    await write('valido-lf.csv', 'archivo ahora inválido');
    expect(
      controller.session!.file.bytes,
      base64Decode(csvTestBundle['valido-lf.csv']!),
    );
    expect(await image(), empty);
    await confirm();
    expect(await count('movements'), 3);
    expect(await count('budgets'), 2);
    final committed = await image();
    await select('valido-lf.csv');
    expect(controller.session, isNot(same(session)));
    expect(controller.review!.bindings.newCategories, isEmpty);
    expect(controller.canConfirm, isFalse);
    expect(await image(), committed);
  }

  Future<void> rollback() async {
    final empty = await image();
    await select('historico-ejemplo.csv');
    await approveMissingReferences();
    // Metadatos se escriben al final: obliga a revertir referencias y 58 filas.
    await db.customStatement(
      "CREATE TEMP TRIGGER fail_122 BEFORE INSERT ON import_batch_metadata BEGIN SELECT RAISE(ABORT,'synthetic-122'); END",
    );
    await controller.confirm();
    expect(
      controller.failures.any((i) => i.code == ImportIssueCode.persistence),
      isTrue,
    );
    expect(await image(), empty);
    await db.customStatement('DROP TRIGGER fail_122');
    await Future.wait([controller.confirm(), controller.confirm()]);
    expect(controller.result, isA<ImportConfirmed>());
    expect(await count('import_batches'), 1);
    expect(await count('movements'), 10);
    expect(await count('budgets'), 48);
  }

  Future<void> budgetHistoryAndReferences() async {
    await select('valido-lf.csv');
    await approveMissingReferences();
    final batch = await confirm();
    final rows = (await services.history.listRows(batch.id)).items;
    final budgets = rows.where((r) => r.currentBudget != null).toList();
    final first = budgets.first.currentBudget!;
    await SqliteBudgetRepository(db).edit(
      first.id,
      BudgetInput(
        month: first.data.month,
        categoryId: first.data.categoryId,
        concept: 'Partida corregida',
        amountCents: -41000,
      ),
    );
    await SqliteBudgetRepository(db).delete(budgets.last.currentBudget!.id);
    final edited = await image();
    await select('referencias-renombradas.csv');
    expect((controller.result as ImportAlreadyImported).batch.id, batch.id);
    expect(await image(), edited);
    expect(
      (await services.history.getRow(budgets.first.id))!
          .original!
          .amount
          .originalCents,
      40000,
    );
    expect(
      (await services.history.getRow(budgets.first.id))!
          .currentBudget!
          .data
          .amountCents,
      -41000,
    );
    expect((await services.history.getRow(budgets.last.id))!.isDeleted, isTrue);
    expect((await services.history.getBatch(batch.id))!.budgetCount, 2);
    // La referencia elegida pierde elegibilidad después de previsualizar.
    await write(
      'referencia-cambiada.csv',
      '$csvHeader\n2026-05-03;Compra nueva;-1.00;REAL;Vivienda;Alquiler;;Cuenta nueva;\n',
    );
    await select('referencia-cambiada.csv');
    await approveMissingReferences();
    expect(controller.canConfirm, isTrue);
    final writer = LocalDatabase(
      NativeDatabase(File(store.databasePath!), setup: configureConnection),
    );
    try {
      await SqliteCategoryRepository(writer)
          .setArchived(first.data.categoryId, archived: true);
    } finally {
      await writer.close();
    }
    final changed = await image();
    await controller.confirm();
    expect(controller.result, isNull);
    expect(controller.failures, isNotEmpty);
    expect(await image(), changed);
    expect(await count('accounts'), 1);
  }

  Future<void> ambiguousReference() async {
    final repo = SqliteCategoryRepository(db);
    final first = await repo.create(name: 'Alimentación', isIncome: false);
    final second = await repo.create(name: 'Alimentación', isIncome: true);
    await repo.create(name: 'Supermercado', parentId: second.id);
    final leaf = await repo.create(name: 'Supermercado', parentId: first.id);
    final before = await image();
    await select('referencia-ambigua.csv');
    expect(controller.canConfirm, isFalse);
    expect(
      controller.review!.pendingReferences.any(
        (p) => p.candidateIds.length == 2,
      ),
      isTrue,
    );
    await controller.bindCategory(
      ImportCategoryReference(['Alimentación', 'Supermercado']),
      id: leaf.id,
    );
    await controller.bindAccount(
      ImportAccountReference.named('Cuenta principal'),
      plan: ImportNewAccount(
        name: 'Cuenta principal',
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      ),
    );
    expect(await image(), before);
    final batch = await confirm();
    final real = (await services.history.listRows(batch.id))
        .items
        .single
        .currentMovement!;
    expect(real.data.categoryId, leaf.id);
    expect((await repo.get(leaf.id))!.isIncome, isFalse);
  }

  Future<void> concurrency() async {
    await select('valido-lf.csv');
    await approveMissingReferences();
    final batch = await confirm();
    final row = (await services.history.listRows(batch.id)).items.first;
    expect(row.currentMovement, isNotNull);
    await write(
      'concurrente.csv',
      '$csvHeader\n2026-03-03;Concurrente;-2.00;REAL;Nueva;;;Cuenta principal;\n',
    );
    await select('concurrente.csv');
    await approveMissingReferences();
    expect(controller.canConfirm, isTrue);
    final second = LocalDatabase(
      NativeDatabase(File(store.databasePath!), setup: configureConnection),
    );
    try {
      final other = await write(
        'otro-escritor.csv',
        '$csvHeader\n2026-03-03; Concurrente ;-2.00;REAL;;;;Cuenta principal;\n',
      );
      final file = await prepareHistoricalCsvFile(
        LocalCsvSelected(
          name: 'otro-escritor.csv',
          bytes: await other.readAsBytes(),
        ),
      );
      final session = ImportSession(
        file: file,
        interpretation: await const BackgroundHistoricalCsvAdapter().interpret(
          file,
        ),
      );
      final otherServices = createImportServices(second);
      final review = await otherServices.previewer.preview(session);
      expect(
        await otherServices.confirmer.confirm(
          ImportConfirmationRequest(review: review),
        ),
        isA<ImportConfirmed>(),
      );
    } finally {
      await second.close();
    }
    final concurrent = await image();
    await controller.confirm();
    expect(controller.result, isNull);
    expect(controller.failures, isNotEmpty);
    expect(controller.review!.overlaps, hasLength(1));
    expect(controller.canConfirm, isFalse);
    expect(await image(), concurrent);
    controller.markOverlap(controller.review!.overlaps.single.key, true);
    await confirm();
    expect(await count('movements'), 5);
    // Un presupuesto concurrente bloquea aunque se haya aprobado crear cuenta.
    await write(
      'presupuesto-concurrente.csv',
      '$csvHeader\n2026-04-03;Nuevo;-1.00;REAL;;;;Cuenta nueva;\n2026-04-01;Previsto;20.00;PRESUPUESTO;Vivienda;Alquiler;;;\n',
    );
    await select('presupuesto-concurrente.csv');
    await approveMissingReferences();
    expect(controller.canConfirm, isTrue);
    final categoryId = controller
        .review!
        .bindings
        .categories[ImportCategoryReference(['Vivienda', 'Alquiler'])]!;
    final writer = LocalDatabase(
      NativeDatabase(File(store.databasePath!), setup: configureConnection),
    );
    try {
      await SqliteBudgetRepository(writer).create(
        BudgetInput(
          month: BudgetMonth(2026, 4),
          categoryId: categoryId,
          concept: 'Otro escritor',
          amountCents: -3000,
        ),
      );
    } finally {
      await writer.close();
    }
    final beforeConflict = await image();
    await controller.confirm();
    expect(
      controller.failures.any((i) => i.code == ImportIssueCode.budgetConflict),
      isTrue,
    );
    expect(await image(), beforeConflict);
    expect(await count('accounts'), 1);
  }
}

final csvJourneyCases = <String, Future<void> Function(CsvImportJourney)>{
  'plantilla anual, totales, reapertura y huellas': (j) => j.reference(),
  '24 fixtures: formato, semántica y conflictos sin escrituras': (j) =>
      j.fixtures(),
  'multilínea: ordinal, línea física y procedencia': (j) => j.physicalLines(),
  'reales idénticos, avisos, corrección, borrado y repetición': (j) =>
      j.repeatsAndHistory(),
  'cancelación, fallos, reemplazo y snapshot de bytes': (j) => j.selection(),
  'fallo tardío, rollback completo y doble confirmación': (j) => j.rollback(),
  'partidas corregidas/borradas y referencia archivada concurrentemente': (j) =>
      j.budgetHistoryAndReferences(),
  'referencia ambigua resuelta por UUID y marca heredada': (j) =>
      j.ambiguousReference(),
  'dos conexiones: solapamiento y presupuesto después de revisar': (j) =>
      j.concurrency(),
};
