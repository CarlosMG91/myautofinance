# MA-TSK-105 · Verificación del presupuesto mensual

## Alcance y diseño

Se consultó `GET http://localhost:4310/api/data` de Epic Board, tablero
**My autofinance**, con workspace coincidente. MA-TSK-102, MA-TSK-103 y
MA-TSK-104 están completados. MA-TSK-099 figura completado con aprobación
explícita `2026-10-05T11:30:53.008Z` y el mockup
<http://localhost:4310/mockups/autofinance-ma-tsk-099-v1.html>.
La propuesta local conserva su estado anterior pendiente; la evidencia del
tablero es posterior. No se modifica el estado del tablero ni se cierra la épica.

La entrega añade verificación, sin cambiar pantallas, reglas, esquema,
dependencias ni toolchain. Usa los escenarios de
[MA-TSK-104](escenarios-presupuesto-mensual.md), las reglas de EP-001 y la
composición real `AutofinanceApp → LocalBackupSession → BudgetSource → SQLite`.

`test/support/budget_lifecycle_journey.dart` contiene el guion compartido;
`test/budget/budget_lifecycle_test.dart` lo ejecuta en el host con presentación
Windows de 1440 px y Android de 412 px. El runner
`integration_test/budget_management_test.dart` lo ejecuta en Windows/Android
nativos, usando `path_provider` para una carpeta sintética independiente de
la base personal. Los UUID se generan por fixture y se comparan por identidad,
incluidas dos categorías hermanas llamadas IMPUESTOS.
`test/support/budget_native_driver.dart` permite ejecutar el mismo test en
Windows profile cuando no está disponible el enlace del runtime C++ Debug.

Se reutilizan F1–F4 con tres niveles válidos: Alimentación es una raíz y
Supermercado/Compra semanal sus descendientes. La ruta de cuatro niveles que
aparece en F1 no se materializa. El caso L aporta NÓMINA `+3.000,00` e
IMPUESTOS `−600,00` por mes; el histórico F3 suma `−400,00` en enero:
total inicial `+2.000,00`. Febrero contiene Vivienda `−1.000,00` para probar
el conflicto inverso. La fixture no reproduce los totales de F2 completo.

## Evidencia por escenario

| Escenarios | Comprobación del recorrido compartido |
|---|---|
| L1–L4, W1, R2 | Árbol activo por UUID, nombres repetidos, signos y total; alta explícita cero; fallo INSERT conserva filas/revisión/borrador; reintento crea una fila y una revisión; cierre/reapertura conserva cero frente a ausencia. |
| R1, R6 | Edición por celda Windows y detalle Android; trigger UPDATE aborta; comparación completa del estado antes/después; borrador conservado; reintento manual guarda una vez; reapertura y edición sin cambios conservan también timestamps/revisión. |
| W2, W3, W6, R4 | Rechazo padre→descendiente y descendiente→padre con mes y ambas rutas; registros y borrador intactos; edición a destino conflictivo rechazada; corrección explícita a categoría/mes válidos y reintento. |
| W5, W7 | Seguir editando y descartar no escriben; detalle cambia mes, categoría e importe; vuelve al origen, ofrece Ver mes y muestra el destino; desaparece la asignación anterior. |
| H1, H3 | Preparación por repositorio de lote histórico, con normalización CSV una sola vez; guardar sin cambios no invierte el signo; categoría archivada fuera del selector activo; corrección manteniendo el archivo y todos los metadatos. |
| W8, R3, R5 | Cancelar borrado conserva todo; trigger DELETE aborta sin éxito ficticio; reintento exige otra confirmación; elimina únicamente la partida y conserva import_rows/lote; reapertura conserva el resultado. |

Los snapshots ordenados comparan presupuestos, dataset/revisión, categorías,
lotes/filas CSV, movimientos, cuentas/liquidez y fotos/valores patrimoniales.
La edición compara además todas las columnas de la partida, permitiendo
cambiar solo mes/categoría/importe/updated_at: conserva ID, created_at,
concepto, discrecionalidad e import_row_id. Lote y ordinal se preservan al
comparar import_rows/import_batches. Los fallos usan triggers TEMP de prueba;
se retiran antes del reintento, sin introducir fallos en producción.

La batería previa complementa el guion: hermanos coexistentes, conflicto con
cero, alta/cancelación desde selector, límites int64 y precisión, foco/Intro,
campo vacío, destino archivado rechazado, bloqueo tras sustituir la base,
fallo de lectura, doble toque, Atrás Android y preservación del borrador de
edición ante fallo de borrado. Los tests de MA-TSK-102/103 también comprueban
320 px, texto al 200 % y controles táctiles. No se atribuyen esas variantes
al runner nativo de este ticket.

La correspondencia funcional con el mockup se comprueba mediante tabla con
importe propio y subtotal separado, tarjetas/formulario en ancho compacto,
ausencia/cero, detalle de tres campos, metadatos de solo lectura, archivo
separado, conflictos sin sustitución y confirmaciones de descarte/borrado.
No se trata de una comparación píxel a píxel ni una auditoría de lector de
pantalla, contraste del sistema o teclado físico.

## Comandos reproducibles

```powershell
flutter --version
./scripts/check-toolchain.ps1
./scripts/check-quality.ps1
flutter test --no-pub test/budget/budget_lifecycle_test.dart
flutter test --no-pub integration_test/budget_management_test.dart -d windows --dart-define=APP_ENV=test
# Alternativa nativa usada en esta máquina:
flutter drive --profile --no-pub --driver=test/support/budget_native_driver.dart --target=integration_test/budget_management_test.dart -d windows --dart-define=APP_ENV=test
# Sustituir el ID por un dispositivo autorizado disponible.
flutter test --no-pub integration_test/budget_management_test.dart -d emulator-5554 --dart-define=APP_ENV=test
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

Windows requiere permitir las herramientas nativas fuera del sandbox. Android
usa JDK 17, seleccionado temporalmente y restaurado al terminar. El runner
registra `testTextInput` para introducir valores reproducibles; no acredita
el teclado Android del sistema. Las carpetas de fixtures se eliminan al
terminar y los logs/builds locales no se incorporan al repositorio.

## Resultados de ejecución · 2026-10-05

- Flutter 3.47.0 / Dart 3.13.0; `check-toolchain.ps1` correcto y resolución
  `flutter pub get --enforce-lockfile` correcta. SDK, `toolchain.json` y
  `pubspec.lock` se conservan.
- `scripts/check-quality.ps1`: formato correcto, análisis sin incidencias,
  **1.038 pruebas generales correctas** y las cuatro variantes de arranque
  development/test/production/invalid-synthetic correctas. Incluye los dos
  recorridos nuevos en el host y la batería previa de presupuesto.
  La repetición final limita `flutter test` a `--concurrency=2` mediante una
  función PowerShell temporal; conserva el script y sus pasos. La ejecución
  inicial con paralelismo por defecto produjo fallos/timeouts en movimientos,
  presupuesto y sincronización y se detuvo. Se corrigieron esperas y
  desplazamiento del selector del nuevo runner antes de la repetición completa.
  No se eliminaron ni relajaron aserciones financieras.
- El driver profile, añadido después de la batería general, se verificó
  además con formato y análisis específicos, ambos correctos.
- Builds Windows release y Android debug con `--no-pub` y `APP_ENV=test`:
  correctos. Android usa Temurin 17.0.20.1; la selección
  anterior de Java se restaura mediante `finally`.
- El runner Windows Debug se intentó dos veces; el log detallado identifica
  LNK2001/LNK2019/LNK1120 con `_CrtDbgReport`, `_calloc_dbg`, `_free_dbg` y
  otros símbolos del runtime C++ Debug, con Visual Studio 18 Insiders.
  Ese modo queda bloqueado; no se cambian CMake, SDK ni bibliotecas para
  ocultarlo. Se usa el runner profile para la comprobación nativa.

- **Windows nativo profile: correcto**, compilación y recorrido completo con
  SQLite en archivo; `All tests passed!`, salida 0, 1 min 49 s de recorrido.
  Flutter Driver recoge el resultado por VMService. El aviso de que no se
  detecta el canal nativo de `integration_test` en Windows no impide esa
  recogida: se conserva el resultado del driver y su código de salida.
- **Android nativo debug: correcto**, emulador existente API 37,
  `All tests passed!`, salida 0, 3 min 30 s de recorrido. La imagen del
  emulador no cambia el SDK de compilación fijado por el proyecto. El AVD
  inicialmente permaneció offline; arrancó en frío con 2 GB y dos núcleos,
  sin modificar su configuración guardada ni instalar herramientas.
- El APK se vuelve a compilar desde `lib/main.dart` al terminar el recorrido
  Android, conservando `APP_ENV=test`.

Los cuatro recorridos (dos presentaciones en el host y dos destinos nativos)
comprueban las mismas aserciones de integración. Android físico, IME/teclado
del sistema, TalkBack, Narrador, alto contraste y comparación visual píxel a
píxel siguen **sin verificar**. Los modos Debug del host y del emulador
complementan las comprobaciones funcionales de Windows profile; no se afirma
haber ejecutado la aplicación Windows Debug.

Logs locales ignorados: `.tools/ma-tsk-105-quality-final.log`,
`.tools/ma-tsk-105-driver-analysis.log`,
`.tools/ma-tsk-105-native-windows-verbose.log`,
`.tools/ma-tsk-105-native-windows-profile.log`,
`.tools/ma-tsk-105-native-android.log`,
`.tools/ma-tsk-105-build-windows.log`, `.tools/ma-tsk-105-final-apk.log`.
Este documento conserva el resultado y los comandos sin incorporar logs,
binarios ni bases sintéticas al repositorio.

## Entrega Git

Solo se incluyen este informe, el guion de presupuesto, su prueba de host,
el runner nativo y el driver profile. README, sincronización y prototipos de
categorías ya modificados al comenzar quedan fuera del commit. Se entrega
en la rama configurada `ticket/ma-tsk-071`, sin forzar el push.
