# MA-TSK-113 · Adaptador y casos sintéticos reproducibles

El adaptador de prueba `test/support/synthetic_import_adapter.dart` interpreta
bytes JSON deterministas en memoria mediante el contrato `ImportAdapter`. No
lee archivos de usuario, no importa CSV/XLS, no consulta catálogos, no guarda
datos y no se exporta desde `lib/`; por ello no puede componerse en producción.
Las pruebas crean `ImportFile` con bytes, SHA-256 y nombre explícito, luego
construyen la sesión real del contrato común.

Una fila de fixture usa `kind` (`REAL` o `PRESUPUESTO`), `ordinal`, `concept`,
`cents`, `fields` opcional (lista ordenada `{name,value}`), y los campos
específicos `date`, `account`, `category` o `month`. `cents` es el valor de
origen: REAL conserva el signo; PRESUPUESTO aplica una inversión exactamente
una vez. Omitir `category` en REAL representa Sin clasificar. Omitir `account`
solo es válido para origen bancario y expresa cuenta pendiente de selección.
Errores se devuelven como `ImportIssue`; la sesión rechaza el lote completo.

## Resultados de aceptación

| Escenario | Resultado esperado | Evidencia |
|---|---|---|
| REAL de entrada/salida y dos filas idénticas | Signos sin inferencias; ordinales distintos conservan ambas filas. | `synthetic_import_adapter_test.dart`; reglas de importación del [caso L](../ep-001/casos-referencia.md#caso-l-ingresos--salario--impuestos-y-signos) y [caso N](../ep-001/casos-referencia.md#caso-n--archivo-reactivación-duplicados-y-referencia-nula). |
| REAL sin categoría | Categoría nula, equivalente a Sin clasificar; nunca crea una categoría. | Prueba sintética y [caso J](../ep-001/casos-referencia.md#caso-j--agregación-y-clasificación-de-reales). |
| Cuenta bancaria pendiente | Referencia explícita de selección, no cuenta nula para confirmar. Un CSV sintético sin cuenta produce error de fila. | `synthetic_import_adapter_test.dart`; contrato EP-012 de importación. |
| PRESUPUESTO | Categoría requerida por el tipo; el signo original queda disponible y el interno se invierte una vez. Cero es una fila existente, no ausencia. | Prueba sintética; [casos E/H](../ep-001/casos-referencia.md#caso-e--presupuesto-anual-de-2026) y escenarios [L3/H3](../ep-011/escenarios-presupuesto-mensual.md). |
| Referencia nueva o ambigua; padre/descendiente en mismo mes | No se confirma sin plan/vinculación inequívocos; conflicto bloquea el lote completo. | `sqlite_import_preview_test.dart` (ambigüedades y conflicto con cero), `sqlite_import_confirmation_test.dart` (planes/conflictos). |
| Fecha inválida, tipo incompatible, lote vacío | Se conserva issue con ordinal cuando aplica; sesión inválida y sin confirmación parcial. | Prueba sintética; [rechazos CSV](../ep-001/contrato-csv.md#ejemplos-de-rechazo). |
| Mismos bytes renombrados, incluso tras edición/borrado | Mismo SHA; la confirmación informa ya importado y no recrea filas borradas. | `sqlite_import_confirmation_test.dart`: “Mismos bytes renombrados no son otro archivo; corrección/borrado no se recrean”. |
| Bytes distintos con coincidencia visible | SHA diferente; presenta aviso de solapamiento para revisión expresa, conserva las dos filas y no borra automáticamente. | `sqlite_import_preview_test.dart`: “Consulta meses completos, solapamientos fuera de página…”. |
| Base cambia después de previsualizar | Confirmar rechaza revisión obsoleta sin altas parciales. | `sqlite_import_confirmation_test.dart`: “Revalida base cambiada desde revisión…” y prueba con otra conexión. |

El conjunto financiero de referencia sigue siendo EP-001; estos fixtures
solo ejercitan su traspaso al contrato común. Los escenarios con catálogo,
transacción SQLite, edición/borrado posterior y cambio concurrente usan la
base SQLite y repositorios reales de prueba, no un simulador de persistencia.
