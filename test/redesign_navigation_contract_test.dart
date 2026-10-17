import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/core/modules/feature_module.dart';

void main() {
  final catalog = jsonDecode(
    File('docs/ep-026/catalogo-navegacion.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final destinations = (catalog['destinations'] as List)
      .cast<Map<String, dynamic>>();
  final byId = {
    for (final destination in destinations)
      destination['id'] as String: destination,
  };
  final navigation = catalog['navigation'] as Map<String, dynamic>;
  // EP-027 añade el suplemento aprobado sin reescribir el catálogo EP-026.
  final exportCatalog = jsonDecode(
    File('docs/ep-027/catalogo-navegacion.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final exportDestinations = (exportCatalog['destinations'] as List)
      .cast<Map<String, dynamic>>();

  test(
    'Suplemento EP-027 conserva Gestión, módulos y ámbito independiente',
    () {
      expect(exportCatalog['approvalTicket'], 'MA-TSK-223');
      expect(exportDestinations.map((d) => d['path']), [
        AppRoutes.exportData,
        AppRoutes.exportComplete,
      ]);
      expect(exportDestinations.map((d) => d['period']), [
        'independent-inclusive-months',
        'all-history',
      ]);
      for (final destination in exportDestinations) {
        expect(destination['parent'], 'management');
        expect(destination['module'], ModuleId.synchronization.name);
        expect(destination['owner'], 'MA-TSK-224');
        expect(destination['surfaces'], ['windows', 'android']);
      }
    },
  );

  Map<String, int> distances(String surface, {bool includeUtilities = true}) {
    final config = navigation[surface] as Map<String, dynamic>;
    final result = <String, int>{};
    final queue = <String>[
      ...(config['primary'] as List).cast<String>(),
      if (includeUtilities) ...(config['utilities'] as List).cast<String>(),
    ];
    for (final id in queue) {
      result[id] = 1;
    }
    for (var cursor = 0; cursor < queue.length; cursor++) {
      final id = queue[cursor];
      for (final child in (byId[id]!['children'] as List).cast<String>()) {
        if (!result.containsKey(child)) {
          result[child] = result[id]! + 1;
          queue.add(child);
        }
      }
    }
    return result;
  }

  test(
    'Catálogo íntegro, con propietarios y sin módulos financieros nuevos',
    () {
      expect(catalog['version'], 1);
      expect(catalog['status'], 'design-awaiting-MA-TSK-207');
      expect(byId.length, destinations.length);
      expect(
        destinations.map((d) => d['path']).toSet().length,
        destinations.length,
      );
      final modules = ModuleId.values.map((id) => id.name).toSet();
      for (final destination in destinations) {
        final uri = Uri.parse(destination['path'] as String);
        expect(uri.path, startsWith('/'));
        expect(uri.hasScheme || uri.hasAuthority || uri.hasQuery, isFalse);
        expect(uri.hasFragment, isFalse);
        expect(destination['label'], isNotEmpty);
        expect(destination['owner'], isNotEmpty);
        expect(
          destination['state'],
          isIn(['existing', 'marker', 'new', 'integrationPending', 'backlog']),
        );
        expect(
          destination['period'],
          isIn(['monthly', 'annual', 'range', 'context']),
        );
        if (destination['module'] != null) {
          expect(destination['module'], isIn(modules));
        } else {
          expect(
            destination['id'],
            isIn(['analysis', 'more', 'management', 'diagnostics']),
          );
        }
        for (final child in destination['children'] as List) {
          expect(byId, contains(child));
        }
      }
      expect(catalog['rules']['financialModulesAdded'], isEmpty);
      expect(byId['actual']!['state'], 'marker');
      expect(byId['indicators']!['state'], 'marker');
      expect(byId['importOpenbank']!['state'], 'integrationPending');
      expect(byId['diagnostics']!['state'], 'backlog');
    },
  );

  test('Cinco principales y acceso a todos los flujos; Real/Indicadores en dos acciones', () {
    expect(navigation['windows']['primary'], [
      'home',
      'budget',
      'movements',
      'wealth',
      'analysis',
    ]);
    expect(navigation['android']['primary'], [
      'home',
      'budget',
      'movements',
      'wealth',
      'more',
    ]);
    for (final surface in ['windows', 'android']) {
      final result = distances(surface);
      final fromPrimary = distances(surface, includeUtilities: false);
      for (final id in ['actual', 'indicators']) {
        expect(fromPrimary, contains(id));
        expect(fromPrimary[id], lessThanOrEqualTo(2), reason: '$surface → $id');
      }
      for (final id in [
        'home',
        'monthlyComparison',
        'budget',
        'movements',
        'wealth',
        'actual',
        'indicators',
        'pending',
        'wealthPhoto',
        'budgetProposal',
        'categories',
        'accounts',
        'importCsv',
        'importReview',
        'importHistory',
        'importBatch',
        'importRow',
        'drive',
        'backups',
        'backupDetail',
        'diagnostics',
      ]) {
        expect(result, contains(id), reason: '$surface → $id');
      }
      final surfaceDestinations = destinations.where(
        (d) =>
            d['surfaces'] == null || (d['surfaces'] as List).contains(surface),
      );
      expect(
        result.keys,
        containsAll(surfaceDestinations.map((d) => d['id'])),
        reason: surface,
      );
    }
  });

  test(
    'Selección adaptable de informes y agrupaciones sin cambiar su ruta',
    () {
      final selection = catalog['entrySelection'] as Map<String, dynamic>;
      for (final surface in ['windows', 'android']) {
        final config = navigation[surface] as Map<String, dynamic>;
        final visible = <String>{
          ...(config['primary'] as List).cast<String>(),
          ...(config['utilities'] as List).cast<String>(),
        };
        final entries = selection[surface] as Map<String, dynamic>;
        expect(
          entries.keys,
          containsAll({
            ...(config['primary'] as List).cast<String>(),
            ...AppRoutes.destinations.map(
              (old) =>
                  destinations.singleWhere((d) => d['path'] == old.path)['id'],
            ),
            'management',
          }),
        );
        for (final entry in entries.entries) {
          expect(byId, contains(entry.key));
          expect(
            visible,
            contains(entry.value),
            reason: '$surface → ${entry.key}',
          );
        }
        for (final id in ['actual', 'indicators', 'diagnostics']) {
          expect(entries[id], surface == 'windows' ? 'analysis' : 'more');
        }
        expect(entries['monthlyComparison'], 'home');
        expect(
          entries['management'],
          surface == 'windows' ? 'management' : 'more',
        );
      }
    },
  );

  test('Todas las rutas publicadas conservan destino o namespace, no alias destructivo', () {
    final source = File('lib/app/navigation/app_routes.dart')
        .readAsStringSync();
    final paths = RegExp(r"static const \w+ = '([^']+)';")
        .allMatches(source)
        .map((match) => match.group(1)!);
    final plannedPaths = [
      ...destinations,
      ...exportDestinations,
    ].map((d) => d['path'] as String).toSet();
    final systemPaths = (catalog['systemRoutes'] as List)
        .map((d) => d['path'] as String)
        .toSet();
    final aliases = (catalog['aliases'] as List).cast<Map<String, dynamic>>();
    for (final path in paths) {
      expect(
        plannedPaths.contains(path) ||
            plannedPaths.contains('$path/:id') ||
            systemPaths.contains(path) ||
            aliases.any((alias) => alias['path'] == path),
        isTrue,
        reason: 'Falta la ruta publicada $path',
      );
    }
    for (final old in AppRoutes.destinations) {
      final preserved = destinations.singleWhere((d) => d['path'] == old.path);
      expect(preserved['module'], old.module.name);
    }
    expect(aliases.length, 1);
    expect(aliases.single['path'], '/');
    expect(aliases.single['policy'], 'startup-only');
    expect(byId['monthlyComparison']!['path'], AppRoutes.monthlyStatus);
  });

  test('Cada resumen alcanza el detalle completo del mismo módulo', () {
    final summaries = catalog['summaries'] as Map<String, dynamic>;
    expect(
      summaries.keys,
      containsAll([
        'home',
        'budget',
        'movements',
        'wealth',
        'actual',
        'indicators',
      ]),
    );
    for (final entry in summaries.entries) {
      final summary = byId[entry.key]!;
      final detail = byId[entry.value]!;
      expect(summary['children'], contains(detail['id']));
      expect(detail['kind'], isIn(['detail', 'records']));
      expect(detail['module'], summary['module']);
      expect(detail['period'], summary['period']);
    }
    expect(byId['actual']!['period'], 'annual');
    expect(byId['indicators']!['period'], 'monthly');
  });

  test(
    'Tareas diarias tienen entrada contextual y recuperación no exige base',
    () {
      final actions = catalog['contextualActions'] as Map<String, dynamic>;
      expect(
        actions['home'],
        containsAll(['importCsv', 'pending', 'wealthPhoto']),
      );
      expect(actions['movements'], containsAll(['importCsv', 'pending']));
      expect(actions['wealth'], contains('wealthPhoto'));
      expect(actions['indicators'], containsAll(['wealthPhoto', 'budget']));
      for (final entry in actions.entries) {
        expect(byId[entry.key]!['children'], containsAll(entry.value as List));
      }
      expect(catalog['startup']['activeDatabase'], 'home');
      expect(catalog['startup']['unavailableDatabase'], 'backups');
      expect(catalog['startup']['requiresDatabase'], isFalse);
      expect(catalog['rules']['automaticDrive'], isFalse);
      expect(catalog['rules']['photoReference'], 'first-day');
    },
  );

  test('Puertos existentes conservan periodo y origen, y rechazan salida cancelada', () async {
    var clockReads = 0;
    final session = NavigationSession(
      clock: () {
        clockReads++;
        return DateTime.utc(2026, 10, 12);
      },
    );
    addTearDown(session.dispose);
    final origin = NavigationContext(
      destination: SessionDestination.status,
      period: NavigationPeriod(2024, 2),
      branchId: '80000000-0000-4000-8000-000000000003',
      filters: {'concepto': 'Retención', 'abiertas': 'rama'},
      scrollOffset: 240,
      focus: 'fila-impuestos',
    );
    await session.setContext(origin);
    final saved = session.openSecondary();
    for (final destination in SessionDestination.values) {
      await session.changeDestination(destination);
      expect(session.period, NavigationPeriod(2024, 2));
    }
    expect(clockReads, 1);
    await session.returnToOrigin(saved);
    expect(session.context, same(origin));
    expect(session.context.filters['concepto'], 'Retención');
    expect(session.context.scrollOffset, 240);
    expect(session.context.focus, 'fila-impuestos');
    final accepted = await session.selectPeriod(
      NavigationPeriod(2025, 8),
      guard: () async => false,
    );
    expect(accepted, isFalse);
    expect(session.context, same(origin));
    expect(
      await session.changeDestination(
        SessionDestination.budget,
        guard: () async => false,
      ),
      isFalse,
    );
    expect(session.context, same(origin));
    expect(clockReads, 1);
    final newPeriod = origin.withPeriod(NavigationPeriod(2025, 8));
    expect(newPeriod.branchId, origin.branchId);
    expect(newPeriod.filters, origin.filters);
    expect(newPeriod.scrollOffset, 0);
    expect(newPeriod.focus, isNull);
    final annual = AnnualNavigationPeriod(origin.period);
    expect(annual.year, 2024);
    expect(annual.focusedMonth, 2);
    expect(annual.firstDay.value, '2024-01-01');
    expect(annual.until!.value, '2025-01-01');
  });
}
