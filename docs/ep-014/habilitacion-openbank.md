# Habilitación Openbank · 2026-10-22

La solicitud directa del usuario habilita la implementación y el botón sobre
la muestra original privada aportada. Se entrega el lector de la variante
[caracterizada](formato-observado.md), su adaptador y la ruta productiva común;
no un lanzamiento con un lector sintético. MA-TSK-127/128 se conservan.

## Resultado comprobado

- Gestión muestra **Importar Openbank** habilitado con almacenamiento disponible.
  La opción abre la selección y revisión real; se ha comprobado en el runner
  Windows de producción, en el mismo ejecutable que utilizaba el usuario.
- El lector productivo ha interpretado las 48 filas de la muestra privada,
  comparando fila física, fecha de valor, concepto e importe con una extracción
  independiente. No se ha confirmado ni duplicado ese extracto en la base personal.
- SHA-256 del contenido de todas las tablas persistentes personales, antes de
  compilar y después de abrir la app actualizada: idéntico. Integridad y claves
  foráneas correctas; sin cambio de revisión, migración ni fotos patrimoniales.
- **51 pruebas dirigidas aprobadas** en una ejecución final nueva: lector,
  controlador/SQLite, pantallas 412/1440, regresión CSV, selector, arquitectura
  y contraste privado del archivo original. Log: `.tools/openbank-final-checks.log`.
- Las capturas widget `.tools/openbank-review-412.0.png` y
  `.tools/openbank-review-1440.0.png` se han revisado con la fuente de la app
  cargada. Son capturas de widgets sintéticos, no del runner nativo.
- Casos financieros EP-001: correctos, mediante `node docs/ep-001/verificar-casos.mjs`.

## Compilaciones y herramientas

Flutter 3.47.0 y Dart 3.13.0, verificador de versiones correcto. El lockfile
conserva las versiones previas; solo añade XML 6.6.1 y petitparser 7.1.0.

| Comprobación | Resultado | Evidencia local ignorada |
| --- | --- | --- |
| Windows release, `APP_ENV=test` | Correcto, 165,1 s | `.tools/openbank-build-windows-test.log` |
| Windows release, `APP_ENV=production` | Correcto, 160,5 s | `.tools/openbank-build-windows-production.log` |
| Android debug, `APP_ENV=test`, JDK 17 | Correcto, 145,3 s | `.tools/openbank-build-android.log` |
| Análisis general inicial | Sin incidencias, 110,7 s | `.tools/openbank-quality.log` |
| Análisis final de ocho entradas afectadas | Sin incidencias, 108,3 s | `.tools/openbank-analyze-final.log` |

El ejecutable de uso normal se ha generado en
`build/windows/x64/runner/Release/myautofinance.exe`; APK de comprobación en
`build/app/outputs/flutter-apk/app-debug.apk`. La configuración de compilación
usa APPDATA temporal para evitar modificar los ajustes Flutter del usuario.

## Límites

Solo se admite la variante XHTML ISO-8859-1 observada, aunque la extensión sea
XLS. No se acredita BIFF/OLE, XLSX ni otros bancos. No se ha importado mediante
un teléfono físico ni se ha instalado un APK de distribución; la compilación
Android y las pruebas widget no sustituyen esa comprobación.

No se cambia OAuth, sincronización, firma, empaquetado, esquema SQLite ni
reglas financieras. La aceptación visual final MA-TSK-217 sigue siendo una
revisión humana independiente. Esta entrega no afirma por sí sola que se
hayan ejecutado todas las pruebas nativas de MA-TSK-131/245 en Android.

## Control general

`scripts/check-quality.ps1` se ha ejecutado: dependencias con `--enforce-lockfile`,
formato de 515 archivos sin cambios y análisis correctos. La suite general
termina con **2.047 aprobadas y cuatro fallidas**; no se declara calidad global
completa. El control general se inició antes del último ajuste de estructura
XML y registró el caso Openbank «contenido fuera de tabla» como fallido. Ese
caso pasa en la ejecución final dirigida de 51 pruebas; no se ha vuelto a
ejecutar toda la suite después del ajuste.

Los otros tres fallos están en archivos no modificados por esta tarea:

- `local_recovery_journey_test.dart`: dos manuales, restauración y recuperación
  de la anterior tras reinicios.
- `local_recovery_journey_test.dart`: fallo de disco tras instalar.
- `wealth_lifecycle_test.dart`: Caso D completo en archivo SQLite, Windows.

Se conservan sus diagnósticos en `.tools/openbank-quality.log`. No se amplía
esta tarea para modificar recuperación o patrimonio. El script se detuvo
antes de los arranques; se comprueban separadamente y se registran abajo.

Los bytes del fixture se marcan binarios en `.gitattributes`: la huella esperada
coincide con el contenido preparado en Git, sin conversión de saltos de línea.

Los cuatro arranques `development`, `test`, `production` e `invalid-synthetic`
se han verificado separadamente y pasan. Evidencias:
`.tools/openbank-bootstrap-<entorno>.log`. Un primer intento encontró la DLL
SQLite en uso; la repetición usa un directorio nuevo de salida aislado y termina
correctamente, sin borrar archivos en uso ni cambiar datos de usuario.
