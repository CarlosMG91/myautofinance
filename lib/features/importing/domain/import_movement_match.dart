/// Criterio EP-012 compartido por previsualización y diagnóstico retrospectivo.
/// La igualdad solo acredita coincidencia, nunca autoriza borrar registros.
typedef ImportMovementMatch = (String, String, int, String);

ImportMovementMatch importMovementMatch({
  required String accountId,
  required String valueDate,
  required int amountCents,
  required String concept,
}) => (accountId, valueDate, amountCents, concept.trim().toLowerCase());
