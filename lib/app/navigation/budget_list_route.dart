import 'package:flutter/material.dart';

import '../../features/budget/presentation/budget_source.dart';
import '../../features/budget/presentation/budget_list_screen.dart';
import 'budget_links.dart';
import 'budget_editor_origin.dart';
import 'monthly_status_origin.dart';

class BudgetListRoute extends StatelessWidget {
  const BudgetListRoute({
    super.key,
    required this.settings,
    required this.load,
  });
  final RouteSettings settings;
  final BudgetLoader load;
  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    MonthlyStatusOrigin? origin;
    void back() {
      if (navigator.canPop()) {
        navigator.pop();
      } else if (origin != null) {
        navigator.pushReplacementNamed(origin.route, arguments: origin.context);
      } else {
        navigator.pushReplacementNamed('/estado');
      }
    }

    try {
      final query = BudgetLinks.parse(settings.name!);
      origin = BudgetLinks.origin(settings.name!);
      Future<void> open(String? id) async {
        await navigator.pushNamed(
          id == null
              ? BudgetLinks.create(query, origin: origin?.route)
              : BudgetLinks.detail(id, query, origin: origin?.route),
          arguments: BudgetEditorOrigin(
            query.month,
            query.categoryId,
            listRoute: settings.name,
          ),
        );
      }

      return BudgetListScreen(
        load: load,
        query: query,
        onReturn: back,
        onCreate: () => open(null),
        onOpen: open,
      );
    } catch (_) {
      return Scaffold(
        appBar: AppBar(title: const Text('No se pudo abrir este detalle')),
        body: TextButton(
          onPressed: back,
          child: const Text('Volver al origen'),
        ),
      );
    }
  }
}
