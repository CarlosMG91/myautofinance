import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/core/modules/feature_module.dart';

const _folders = <String, ModuleId>{
  'monthly_status': ModuleId.monthlyStatus,
  'wealth': ModuleId.wealth,
  'budget': ModuleId.budget,
  'actual_spending': ModuleId.actualSpending,
  'indicators': ModuleId.indicators,
  'movements': ModuleId.movements,
  'importing': ModuleId.importing,
  'synchronization': ModuleId.synchronization,
};

void _expectAcyclic<T>(Map<T, Iterable<T>> graph) {
  final visited = <T>{};
  final active = <T>{};
  void visit(T node) {
    expect(active, isNot(contains(node)), reason: 'Ciclo en $node');
    if (!visited.add(node)) return;
    active.add(node);
    for (final dependency in graph[node]!) {
      expect(graph, contains(dependency), reason: 'Dependencia ausente: $node');
      visit(dependency);
    }
    active.remove(node);
  }

  for (final node in graph.keys) {
    visit(node);
  }
}

void main() {
  test('El arranque registra cada módulo una vez y sin ciclos', () {
    final modules = AutofinanceApp.modules;
    expect(
      modules.map((module) => module.id),
      unorderedEquals(ModuleId.values),
    );
    _expectAcyclic({
      for (final module in modules) module.id: module.dependencies,
    });
  });

  test(
    'Las directivas Dart respetan fronteras, capas y ausencia de ciclos',
    () {
      final root = Directory('lib').absolute.uri;
      String relativePath(Uri uri) {
        expect(uri.path, startsWith(root.path), reason: 'Fuera de lib: $uri');
        return uri.path.substring(root.path.length);
      }

      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      final graph = <String, Set<String>>{};
      // Incluye import, export, part e imports/exports condicionales.
      final directive = RegExp(
        r'^\s*(?:import|export|part)\s+(?!of\b)([^;]+);',
        multiLine: true,
      );
      final quoted = RegExp("['\"]([^'\"]+)['\"]");
      for (final file in files) {
        final source = relativePath(file.absolute.uri);
        final dependencies = graph[source] = <String>{};
        final sourceParts = source.split('/');
        for (final match in directive.allMatches(file.readAsStringSync())) {
          for (final uriMatch in quoted.allMatches(match[1]!)) {
            final uri = uriMatch[1]!;
            final isLocalPackage = uri.startsWith('package:myautofinance/');
            final parsed = Uri.parse(uri);
            if (parsed.hasScheme && !isLocalPackage) {
              if (sourceParts.contains('domain') ||
                  sourceParts.first == 'core') {
                expect(uri, startsWith('dart:'), reason: '$source → $uri');
              }
              continue;
            }
            final targetUri = isLocalPackage
                ? root.resolve(uri.substring('package:myautofinance/'.length))
                : file.absolute.uri.resolve(uri);
            final target = relativePath(targetUri);
            dependencies.add(target);
            final targetParts = target.split('/');
            final reason = '$source → $target';
            if (sourceParts.first == 'core') {
              expect(targetParts.first, 'core', reason: reason);
            }
            if (sourceParts.first != 'features') continue;
            expect(
              targetParts.first,
              isIn(['core', 'features']),
              reason: reason,
            );
            if (targetParts.first == 'core') continue;
            if (sourceParts[1] != targetParts[1]) {
              expect(
                target,
                'features/${targetParts[1]}/${targetParts[1]}.dart',
                reason: 'Consumir solo la entrada pública: $reason',
              );
              final module = AutofinanceApp.modules.singleWhere(
                (module) => module.id == _folders[sourceParts[1]],
              );
              expect(
                module.dependencies,
                contains(_folders[targetParts[1]]),
                reason: 'Dependencia no declarada: $reason',
              );
            }
            if (sourceParts.contains('domain')) {
              expect(targetParts, isNot(contains('data')), reason: reason);
              expect(
                targetParts,
                isNot(contains('presentation')),
                reason: reason,
              );
            }
            if (sourceParts.contains('data')) {
              expect(
                targetParts,
                isNot(contains('presentation')),
                reason: reason,
              );
            }
            if (sourceParts.contains('presentation')) {
              expect(targetParts, isNot(contains('data')), reason: reason);
            }
          }
        }
      }
      _expectAcyclic(graph);
    },
  );
}
