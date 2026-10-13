# MA-TSK-212 · Patrimonio y fotos mensuales

Patrimonio abre con el neto de la foto manual del día 1, activos, deudas y
activos líquidos. La distribución usa únicamente una foto completa y separa
las deudas del denominador. Una foto ausente o parcial conserva «Sin dato»
en todas las magnitudes; no publica sumas parciales ni arrastra otro mes.

Ver detalle muestra tarjetas por ficha agrupadas por su liquidez efectiva,
con enlaces al detalle existente y a la edición de la foto. El histórico
mantiene las doce consultas originales, sus huecos y una matriz completa
con valores, pendientes, liquidez de cada mes y fichas fuera de vigencia.
No existe suma anual de patrimonio. Escape y Back vuelven al resumen;
al regresar de una ficha se conserva detalle, periodo, scroll y foco.

La captura ofrece tabla en PC y tarjetas en Android o con texto ampliado.
Identifica la fecha fija y el estado guardado, y distingue vacío pendiente,
cero válido y valor manual. Conserva validación, borrador, confirmación de
descarte, errores y escritura del controlador existente. No cambia SQLite,
cálculos, indicadores ni el catálogo, cuyo rediseño pertenece a T12.

## Fuentes y alcance

Se consultó `GET http://localhost:4310/api/data`, tablero My autofinance:
MA-TSK-212 en curso, MA-TSK-207 y MA-TSK-208 completados. El borrador previo
de este ticket y su salida de ejecución permiten continuar su implementación.
El usuario autoriza implementar MA-TSK-212 y declara T05 completado. Los
registros locales de aprobación de T04 siguen desactualizados: no se modifica
la aprobación ni se afirma una revisión humana nueva de su artefacto.

La presentación sigue el prototipo integral, el contrato de shell/contexto
y la API pública del kit T05. EP-001 conserva sus reglas y casos de referencia.
`WealthOverview` y `WealthHistory` reciben lecturas existentes; no implementan
un segundo motor financiero. Solo presentation importa el kit visual.

Los cambios de README, catálogos, kit de catálogo, Drive, copias y otros
prototipos que ya estaban en el checkout se excluyen del commit. Se incluyen
las adaptaciones de las pruebas históricas y de los recorridos patrimoniales
que dependían de las etiquetas anteriores del resumen.

La comprobación en una copia de HEAD detectó referencias previas a
`drive_upload.dart`, `drive_upload_factory.dart` y cambios de contratos Drive
todavía sin versionar. Por ello la app base aislada no compila. Para verificar
patrimonio sin los rediseños concurrentes se aportan esos contratos/adaptadores
solo a la copia de prueba, manteniendo las pantallas y el kit originales de
catálogos y Drive. Ninguno de esos archivos de soporte entra en este commit;
su entrega sigue correspondiendo al propietario de Drive.

## Comprobaciones reproducibles

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub test/wealth test/historical_views_test.dart test/architecture_test.dart
./scripts/check-quality.ps1
node docs/ep-001/verificar-casos.mjs
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
$env:WEALTH_REDESIGN_CAPTURE='1'
flutter test --no-pub test/wealth/wealth_redesign_test.dart
```

Los builds Android usan Temurin JDK 17.0.20.1 con configuración local aislada,
sin cambiar las preferencias globales ni SDK/lockfile. Las pruebas SQLite en
archivo requieren acceso a sus directorios temporales. La ejecución inicial
en sandbox bloqueó las aperturas; se repitió fuera del sandbox. Calidad y
otras pruebas deben ejecutarse sin solaparse: Flutter reemplaza la misma DLL
nativa de SQLite y falla si otro proceso la mantiene abierta.

## Evidencia visual

`patrimonio-capturas/` conserva imágenes del motor Flutter obtenidas mediante
`flutter test` con datos sintéticos, no capturas de una aplicación instalada.
Se inspeccionan resumen, distribución, foto parcial, formulario, fichas,
histórico y matriz en PC; resumen, detalle y formulario Android a 320 dp y
texto 200 %. El recorrido también prueba 840 y 1440 dp al 200 %.

El caso D comprueba enero 19.000/5.000/14.000 €, líquidos 9.000 € y medios
10.000 €. Febrero ausente/parcial no entrega subtotales. Registrar ahorro 0
y completar febrero da neto 11.900 €; corregir 6.200 a 6.300 da 12.000 €,
con los mismos UUID y enero intacto. Se comprueban activos cero, vigencia,
liquidez histórica, doce celdas por fila, Back/Escape y descarte de borrador.

Los recorridos nativos integrados, capturas de aplicaciones instaladas y
TalkBack/Narrador quedan para T14. Esta evidencia de widgets no los sustituye.

## Resultado · 2026-10-13

- Toolchain Flutter 3.47.0 / Dart 3.13.0 correcto; dependencias fijadas
  resueltas sin cambios del lockfile.
- 94 pruebas del módulo, navegación histórica y arquitectura correctas,
  incluidos los recorridos con SQLite en archivo Windows/Android simulado.
- 60 comprobaciones adicionales correctas en la copia sin rediseños de
  catálogos/Drive, con el soporte backend pendiente descrito arriba.
- Los siete casos específicos del rediseño pasan, también al generar PNG.
- Casos financieros EP-001 correctos. Windows release y Android debug con
  APP_ENV=test compilados correctamente; Android verificado con JDK 17.
- Calidad completa: formato correcto (400 archivos), análisis sin incidencias;
  la suite global termina con 1.688 pruebas correctas y 28 fallos. Incluye
  23 fallos de catálogos/selector y su integración con Estado, cuatro de
  recuperación local y una espera insuficiente de la prueba de retorno de
  foto bajo la carga de la suite. Esa prueba ahora espera la relectura del
  resumen; la repetición final de formulario y rediseño pasa sus 22 casos.
- Los cuatro arranques adicionales development/test/production/invalid-synthetic
  son correctos. No se repite toda la suite tras el ajuste de espera: siguen
  pendientes sus incidencias externas de catálogos y recuperación.
- Dos fallos de recuperación se reproducen también en la copia de prueba;
  los archivos de persistencia y reglas patrimoniales no se han cambiado.
  Las incidencias globales de catálogos/recuperación no se resuelven ni se
  incorporan incidentalmente a MA-TSK-212.
