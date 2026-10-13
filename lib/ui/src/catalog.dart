import 'package:flutter/material.dart';

import 'components.dart';
import 'layout.dart';
import 'tokens.dart';

/// Catálogos y editores secundarios: un único scroll, encabezado y superficie.
/// El consumidor conserva navegación, foco, borrador y validación.
class AfCatalogPage extends StatelessWidget {
  const AfCatalogPage({
    super.key,
    required this.title,
    required this.child,
    this.contextTrail,
    this.actions = const [],
    this.scrollController,
    this.form = false,
  });

  final String title;
  final Widget child;
  final Widget? contextTrail;
  final List<Widget> actions;
  final ScrollController? scrollController;
  final bool form;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        controller: scrollController,
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: form ? 760 : AfTokens.contentMax,
            ),
            child: FocusTraversalGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 24,
                children: [
                  AfPageHeader(
                    title: title,
                    contextTrail: contextTrail,
                    actions: actions,
                  ),
                  AfCard(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
