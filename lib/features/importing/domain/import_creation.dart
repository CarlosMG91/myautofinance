import '../../wealth/wealth.dart';
import 'interpreted_import.dart';

/// Plan en memoria; no representa un UUID ni una cuenta ya creada.
final class ImportNewAccount {
  const ImportNewAccount({
    required this.name,
    required this.activeFrom,
    required this.liquidity,
    this.activeThrough,
  });
  final String name;
  final Month activeFrom;
  final Month? activeThrough;
  final Liquidity liquidity;
}

/// Identidad existente o referencia a un plan. Nunca usa UUID ficticios.
final class ImportCategoryTarget {
  const ImportCategoryTarget.existing(String id)
    : existingId = id,
      proposedReference = null;
  const ImportCategoryTarget.proposed(ImportCategoryReference reference)
    : existingId = null,
      proposedReference = reference;
  final String? existingId;
  final ImportCategoryReference? proposedReference;

  @override
  bool operator ==(Object other) =>
      other is ImportCategoryTarget &&
      existingId == other.existingId &&
      proposedReference == other.proposedReference;
  @override
  int get hashCode => Object.hash(existingId, proposedReference);
}

/// La raíz exige isIncome explícito; un hijo lo hereda y debe dejarlo null.
final class ImportNewCategory {
  const ImportNewCategory({required this.name, this.parent, this.isIncome});
  final String name;
  final ImportCategoryTarget? parent;
  final bool? isIncome;
}
