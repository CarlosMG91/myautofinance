# MA-TSK-210 · Inicio y comparación mensual

Inicio (`/` y `/inicio`) compone el resultado firmado de EP-019, el presupuesto
y la diferencia real menos previsto con tarjetas y barras del kit T05. Las
categorías comienzan contraídas y se despliegan independientemente hasta los
tres niveles. PC dispone las comparativas en dos columnas; Android y texto
ampliado refluyen a una columna. Las barras conservan el signo y el origen
cero; al 200 % se conservan los datos equivalentes en texto.

`/estado` continúa como Ver detalle: previsto agregado, real directo, real
agregado y diferencia, con todos los desgloses y enlaces de registros existentes.
No se reparte un presupuesto del padre ni se suman de nuevo sus descendientes.
Sin clasificar permanece fuera del árbol. La ausencia de presupuesto conserva
su etiqueta y aporta cero aritmético; una partida explícita de cero sigue presente.

## Composición y flujos

- `MonthlyStatusScreen` conserva lectura, invalidaciones, expansión, periodo,
  scroll y posición. `HomeSummary` presenta sus cifras sin agregar datos.
  La conexión se resuelve en cada lectura, también después de restaurar la base.
  Una respuesta recibida con la ruta cubierta se difiere hasta el retorno y no
  inicia entonces otra lectura de la foto. Los indicadores accesibles de carga
  representan las dos lecturas pendientes.
- App inyecta la lectura patrimonial mediante `HomeWealthSummary`, utilizando
  `WealthManagement.readMonth` y `WealthReading`. El módulo mensual no adquiere
  una dependencia de patrimonio. La fecha del día 1 aparece separada del flujo.
  Una foto ausente/incompleta muestra Sin dato y fichas pendientes; nunca expone
  subtotales parciales ni deduce un saldo desde los movimientos.
- Pendientes muestra el contador de movimientos sin categoría del mes consultado.
  Categorizar abre la bandeja existente, que abarca todos los meses: ese alcance
  está explicado junto al acceso. Importar CSV y Registrar/Corregir foto usan
  las rutas y formularios entregados. Volver solicita una lectura nueva.
- Los orígenes de desgloses aceptan Inicio con validación equivalente a Estado:
  periodo, UUID, ámbito, expansión, foco y posición. Partidas/reales conservan
  sus parsers, filtros y enlaces. Un origen inválido no publica contexto.
- Durante refrescos se ocultan las cifras de Inicio y se mantienen montados sus
  controles para conservar el foco al regresar de una fuente. Carga, error de
  comparación y error de foto se diferencian; la foto admite reintento propio.

No se cambian consultas financieras, repositorios, esquema, SDK ni lockfile.
No se añaden indicadores, umbrales, alertas, consultas remotas o automatismos.

## Fuentes y autorización

Se consultaron el ticket completo proporcionado, EP-001, el contrato del shell,
el kit Flutter, el prototipo v1 y sus capturas renderizadas de Inicio. También
se leyó Epic Board (`GET http://localhost:4310/api/data`, My autofinance):
MA-TSK-207, 208 y 209 figuran `done`; MA-TSK-210 figura `in-progress`.
La instrucción actual del usuario autoriza implementar T07 y declara T05
completado. Los archivos locales de aprobación T04 siguen diciendo pendiente;
no se modifican ni se inventa evidencia humana. Su reconciliación corresponde
al propietario de T04.

## Verificación

`test/monthly_status/home_screen_test.dart` utiliza SQLite desechable y el
dataset sintético EP-001 ya empleado en los recorridos existentes. Comprueba:

- Enero `+1.229,75 / +1.100,00 / +129,75` y febrero `+1.099,90 / −0,10`.
- Tres niveles, directos y agregados, ambas piernas de transferencia,
  Sin clasificar, presupuesto cero/ausente y total sin doble conteo.
- Foto completa/ausente/incompleta, cero manual, fecha, fuentes independientes
  y ausencia de mutaciones al visitar Inicio.
- Detalle, movimientos, partidas, retorno con expansión/periodo, invalidación,
  sustitución de conexión, carga/error/reintento y respuesta de un mes anterior.
- Accesos a importación y categorización, corrección de una foto mediante su
  formulario real y actualización del resumen al volver.
- Goldens Windows 1440×900, Android 412×915 y 360×800, 320 px/texto 200 %,
  incluyendo comparativas desplegadas y sin overflow.

Las seis imágenes de `test/monthly_status/home_goldens/` provienen del motor
Flutter y se revisaron visualmente contra el prototipo. Son pruebas de widgets,
no capturas de una aplicación instalada. TalkBack/Narrador y las capturas y
recorridos nativos integrales permanecen en T14. No se acredita una subida o
restauración Drive desde Inicio; esas operaciones siguen siendo manuales.

La espera de `category_screen_test.dart` se adapta al retorno a Inicio: permite
turnos de E/S real mientras aparecen indicadores indeterminados de carga, sin
alterar sus comprobaciones de datos, revisión, borrador ni foco.

Comandos reproducibles:

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub test/monthly_status/home_screen_test.dart
./scripts/check-quality.ps1
node docs/ep-001/verificar-casos.mjs
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

## Propiedad de la entrega

Los cambios previos de README, backend Drive, subida validada y prototipos de
otras épicas quedan fuera del commit. El checkout inicial ya contiene referencias
versionadas a archivos de Drive sin seguimiento; las comprobaciones usan ese
estado compartido, cuya entrega corresponde a su propietario. La rama configurada
es `ticket/ma-tsk-113`. Solo se confirman y suben los archivos propios de T07.

## Resultado · 2026-10-13

- Flutter 3.47.0 / Dart 3.13.0 y resolución `--enforce-lockfile`: correctos.
  SDK, dependencias y lockfile permanecen fijados.
- `./scripts/check-quality.ps1`: correcto. 392 archivos sin cambios de formato,
  análisis sin incidencias, **1.693 pruebas** y los cuatro arranques adicionales
  development/test/production/invalid-synthetic.
- Inicio: **12 pruebas** correctas, con seis goldens revisados. Categorías:
  **26 pruebas** correctas; los dos recorridos completos de importación también
  pasan con rollback y reapertura. La espera de E/S al retornar al Inicio nuevo
  conserva todas sus aserciones funcionales.
- `node docs/ep-001/verificar-casos.mjs`: correcto, con los resultados originales
  y los signos de salario/impuestos conservados.
- Windows release y APK debug de la entrada principal, `APP_ENV=test`: correctos.
  Android utiliza Temurin JDK 17.0.20.1 y los paquetes Android fijados. La
  configuración Flutter se aísla en `.tools/ma-tsk-210-flutter-config`, sin
  modificar la configuración global.
- No se realizaron capturas de aplicaciones instaladas ni pruebas de lectores
  de pantalla nativos; siguen perteneciendo a T14. Las verificaciones usan el
  checkout compartido descrito arriba.
