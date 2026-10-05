import 'package:flutter/foundation.dart';

import '../../features/movements/movements.dart';

/// Contexto del selector y del alta, compartido sin depender del router.
class CategoryNavigationContext {
  const CategoryNavigationContext({required this.returnLabel, this.onCreated});
  final String returnLabel;
  final ValueChanged<CategoryDetails>? onCreated;
}
