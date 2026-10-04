# MA-TSK-088 · Búsqueda y paginación SQLite

`MovementRepository.readPage` devuelve `MovementPage`: registros visibles,
`subtotalCents` firmado de todos los resultados y `nextCursor` (NULL al terminar).
Comparte los predicados con `list`, `readMonth` y `readYear`; no introduce tablas,
migraciones, otra conexión ni cambios de revisión al leer.

## Uso del puerto

```dart
final first = await movements.readPage(
  from: ValueDate(2026, 3, 1),
  until: ValueDate(2026, 4, 1),
  accountId: accountId,
  categoryId: categoryId,
  categoryScope: MovementCategoryScope.branch,
  concept: 'CAFE',
  limit: 100,
);
// Continuar solo si first.nextCursor != null, manteniendo los mismos filtros.
```

- Periodo civil obligatorio `[from, until)`, por fecha de valor. `until: null`
  sigue reservado a periodos que comienzan en 9999.
- Cuenta opcional por UUID; sin ella se incluyen todas, también las cerradas
  con movimientos históricos. Los nombres duplicados no afectan al filtro.
- `categoryId` con alcance `direct` (predeterminado) o `branch` (nodo y todos
  sus descendientes actuales). Las categorías archivadas siguen siendo legibles.
  Reubicar una rama cambia la pertenencia histórica por el mismo UUID.
- `unclassifiedOnly: true` selecciona únicamente categoría NULL. Combinarlo
  con `categoryId` falla con `MovementFailure` antes de ejecutar consultas.
  Sin ambos filtros se incluyen clasificados y no clasificados.
- `concept` aplica subcadena literal solo al concepto. Se recortan extremos;
  vacío tras trim equivale a ausencia. Se conservan puntuación y espacios
  internos: `%`, `_`, comillas y barras no son comodines ni SQL.
- Orden de `list` y `readPage`: fecha descendente, UUID ascendente. Cursor
  exclusivo: fecha menor, o misma fecha y UUID mayor. Tamaño 100 por defecto,
  válido entre 1 y 500; se lee una fila extra para detectar continuación.
- `readMonth` y `readYear` conservan firmas, rama completa, orden ascendente
  previo y ausencia de límite. Los consumidores de informes no deben sustituir
  sus lecturas completas por una página.

Página y subtotal se obtienen en una misma transacción de lectura. Entre
llamadas no se retiene un snapshot: la garantía de ausencia de repetidos y
omisiones requiere una base y filtros estables. Tras una escritura,
reorganización de categorías o restauración, reiniciar desde la primera página.
Un cursor terminado devuelve página vacía y conserva el subtotal global.

## Implementación y portabilidad

Los valores de filtros, cursor y límite son parámetros SQLite. La rama utiliza
una CTE recursiva y pertenencia `IN`, sin unir cada antecesor con movimientos ni
duplicar resultados. Se reutilizan los índices existentes de fecha/cuenta/categoría.

`configureConnection` registra dos funciones de aplicación sobre `sqlite3`,
tanto en conexiones directas como en el isolate nativo usado por la app:

- `movement_search_key`: NFD, eliminación de marcas y case-fold de Unicode
  15.0.0. La tabla Dart se genera con Python 3.12 mediante
  `scripts/generate-concept-search-key.py`; Hangul se descompone algorítmicamente.
  La [licencia Unicode](unicode-license.txt) acompaña a los datos. No se cambia
  el lockfile ni se depende de ICU instalado en Windows/Android.
- `movement_subtotal`: acumula céntimos con `BigInt` y comprueba el resultado
  final int64. Sin resultados devuelve cero. Overflow positivo o negativo
  produce `MovementFailure`; compensaciones intermedias y cantidades mayores
  que la precisión de double mantienen su valor exacto.

Los movimientos no se cargan completos en Dart para filtrar o sumar: la página
se limita en SQL y el agregado mantiene solo el acumulador. La búsqueda por
subcadena necesita evaluar conceptos dentro del conjunto filtrado; no se añade
un índice de texto ni un caché persistente que pueda quedar desactualizado.
Conexiones de prueba creadas a mano deben usar `setup: configureConnection`,
igual que las conexiones de producción. Las funciones no son objetos del
esquema compartido ni alteran sus copias y validaciones.

## Evidencia

`test/persistence/movement_search_test.dart` convierte la fixture de MA-TSK-087
en pruebas SQLite sintéticas: filtros combinados, tres niveles, cuentas y
categorías con nombres duplicados, acentos compuestos/descompuestos,
case-fold (`Straße`, sigma griega), texto literal, espacios internos, duplicados
legítimos, cursores y subtotales en todas las páginas, categorías archivadas,
histórico reubicado, procedencia tras reapertura, límites y overflow.
Incluye 520 movimientos para comprobar páginas de 100/500 y lecturas de informes
completas, así como conexiones directas y en isolate.

Comprobaciones realizadas el 2026-10-04 con Flutter 3.47.0 / Dart 3.13.0:

- `check-toolchain.ps1` y `flutter pub get --enforce-lockfile`: correctos,
  sin cambiar SDK, toolchain ni lockfile.
- Suite dirigida de búsqueda, movimientos, consumidores de categorías e
  informes: 21 pruebas correctas, incluyendo reapertura de SQLite real.
- `./scripts/check-quality.ps1`: correcto; formato sin cambios, análisis sin
  incidencias, 932 pruebas correctas y cuatro variantes de `APP_ENV` verificadas.
- `git diff --check`: sin errores de espacios.
- `flutter build windows --release --no-pub --dart-define=APP_ENV=test`:
  correcto, salida `build/windows/x64/runner/Release/myautofinance.exe`.
- `flutter build apk --debug --no-pub --dart-define=APP_ENV=test`: intentado,
  bloqueado por ausencia de Android SDK (`No Android SDK found`). No se afirma
  compilación ni ejecución Android; las pruebas de conexión/isolate se ejecutan
  en el host Windows.

Las pruebas con temporales y la resolución de paquetes requieren el permiso
de ejecución fuera del sandbox de esta sesión. La ejecución final usa ese
permiso; el primer intento restringido no pudo abrir los temporales de SQLite.
Los widgets y recorridos nativos de Movimientos quedan para los tickets de
interfaz de EP-010.
