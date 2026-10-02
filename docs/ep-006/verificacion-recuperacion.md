# MA-TSK-059 · Recorrido completo y fallos de recuperación

## Alcance y evidencia

Consulta de `GET http://localhost:4310/api/data` el 2026-10-02: tablero
**My autofinance**, MA-TSK-059 en ejecución y MA-TSK-058 completado. El alcance
coincide con el ticket facilitado. Se mantienen el contrato EP-001, esquema v6,
la primitiva consistente de MA-TSK-038 y el diseño aprobado; no hay cambios de
producto, SDK, lockfile, importador ni acceso a Drive.

`test/synchronization/local_recovery_journey_test.dart` añade ocho pruebas con
SQLite y ficheros temporales reales. `test/support/recovery_reference.dart`
prepara, mediante repositorios, los casos sintéticos A–G ya normalizados:
48 presupuestos, 10 reales, enero +1.229,75 EUR, real anual +2.329,65 EUR,
presupuesto anual +13.200,00 EUR, líquidos de enero 9.000,00 EUR, colchón 3,00
meses y febrero sin foto. Es una preparación de prueba, no un importador CSV.
El comprobador del CSV original se ejecuta por separado.

Cada verificación compara **todas las tablas persistentes**, incluidos IDs,
categorías, cuentas, vigencias, fotos, lotes, trazabilidad, dataset y revisión,
y ejecuta `PRAGMA integrity_check` y `PRAGMA foreign_key_check`. Los reinicios
cierran el propietario y crean un store nuevo antes de leer; no se reutiliza
la conexión anterior como evidencia de persistencia.

| Escenario | Comprobación automatizada |
|---|---|
| Guardar M1 → modificar → guardar M2 → reiniciar | M2 contiene el estado modificado; las dos manuales conservan IDs propios |
| Restaurar M1 → reiniciar | Igualdad íntegra con el estado original; respaldo automático del estado modificado y contraste requerido |
| Restaurar el respaldo anterior → reiniciar | Recupera exactamente el estado modificado; nuevo epoch |
| Restauraciones sucesivas | Tres automáticas y las dos manuales; M2 continúa restaurable después de la poda |
| Disco falla tras instalar la candidata | Error sintético de I/O en publicación del diario, rollback, datos íntegros después del reinicio, respaldo conservado y sin contraste nuevo; reintento correcto |
| Cuarta restauración fallida | Conserva las cuatro automáticas; el siguiente éxito conserva exactamente las tres de mayor orden, incluida la del fallo |
| SQLite truncado a 512 bytes | Rechazo por tamaño antes del intercambio, bytes de copia y activa conservados tras reiniciar |
| SQLite v7 con hash y metadatos coherentes | Rechazo específico por esquema futuro, sin downgrade; original y activa conservados |
| Proceso terminado tras aislamiento (diario 002) | Reinicio recupera la anterior, sin contraste nuevo |
| Proceso terminado tras instalación (diario 003) | Reinicio recupera la anterior, sin contraste nuevo |
| Proceso terminado tras validación (diario 004) | Reinicio finaliza la candidata y exige contraste |

Las tres interrupciones usan `test/support/restore_crash_worker.dart`, ejecutado
en otro proceso Flutter con un build temporal privado para no competir por la
DLL SQLite del runner padre en Windows. Tras el movimiento duradero indicado,
el worker anuncia el punto y llama a `exit(73)`: no ejecuta el rollback ni los
`finally` del servicio. El padre exige salida no satisfactoria **y** el anuncio;
un error de compilación del worker no cuenta como interrupción probada. Después
abre los mismos ficheros, verifica un segundo reinicio y restaura el respaldo
anterior. Esa operación comprueba también la liberación del bloqueo nativo del
proceso terminado. No se usan snapshots artificiales para estos tres casos.

Las suites existentes de creación, catálogo, candidatas, restauración, sesión y
pantalla se mantienen en la verificación completa. Cubren otros puntos de I/O,
WAL, carreras, enlaces, corrupción integral, migraciones, reconstrucción del
catálogo, rollback imposible y nuevas interrupciones durante la recuperación.
Las pruebas de widgets comprueban los avisos visibles de contraste, rollback y
recuperación pendiente; la suite nueva comprueba la señal local duradera.

## Reproducción

Usar Flutter/Dart fijados en `toolchain.json`, con su `bin` en PATH:

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub --reporter=expanded test/synchronization/local_recovery_journey_test.dart
./scripts/check-quality.ps1
node docs/ep-001/verificar-casos.mjs
git diff --check
```

En este entorno las pruebas de disco requieren ejecución fuera del sandbox por
la comprobación de antecesores de las rutas temporales Windows. Todos los datos
y builds de los workers son temporales sintéticos; no se incluyen bases en Git.

Resultados del 2026-10-02: Flutter 3.47.0 / Dart 3.13.0 comprobados;
`--enforce-lockfile` correcto sin cambios de dependencias. El verificador
`scripts/check-quality.ps1` terminó correctamente: formato sin cambios,
análisis sin incidencias, **627 pruebas correctas**, incluidas las ocho nuevas,
y las cuatro ejecuciones adicionales de arranque APP_ENV correctas.
`node docs/ep-001/verificar-casos.mjs` y `git diff --check` también correctos.
Las tres terminaciones de proceso pasaron tanto en la ejecución dirigida como
en la suite completa. Los logs locales quedan en `.tools/ma-tsk-059-*.log`,
fuera de Git; los resultados nativos bloqueados se detallan a continuación.

## Controles y recorrido manual pendiente

Se inspeccionaron de nuevo las capturas existentes de MA-TSK-058
[tabla Windows](verificacion-app/windows-catalogo.png) y
[tarjetas Android](verificacion-app/android-catalogo.png): controles de creación,
reintento, detalle, origen, comprobación y explicación de retención visibles.
Son imágenes del renderer de widgets, no ejecución nativa ni evidencia de
interacción manual en este ticket.

**La aceptación manual nativa de Windows y Android queda pendiente.**
`flutter doctor -v` confirma que no está instalado Visual Studio C++ ni Android
SDK. `flutter devices` detecta Windows y navegadores, sin teléfono ni emulador
Android. Se intentaron ambos builds fijados: Windows release falla por toolchain
Visual Studio ausente; APK debug falla por Android SDK ausente. No hay binarios
nativos de esta entrega con los que acreditar ese criterio.

Cuando estén disponibles los destinos, ejecutar el siguiente recorrido en una
instalación de prueba independiente con datos sintéticos. Los marcadores
financieros actuales no permiten editar/importar EP-001 desde la UI: preparar y
modificar el fixture mediante un harness de prueba que inyecte el directorio de
soporte, sin intervenir en la instalación personal.

1. Abrir Gestión → Copias locales en ambos destinos; comprobar teclado/foco en
   Windows y tacto/Atrás en Android, tabla/tarjetas y texto ampliado.
2. Crear M1 por el diálogo y comprobar fecha, origen y estado. Cancelar creación
   y restauración mediante los controles del sistema; confirmar que no hay
   copia automática nueva ni cambios de datos.
3. Con el harness cerrado, modificar el estado, abrir de nuevo y crear M2.
   Entrar en el detalle de M1, aceptar la sustitución y restaurar. Comprobar
   bloqueo de acciones durante la operación y éxito solo al terminar.
4. Reiniciar la app; verificar las cifras y tablas desde el harness. Comprobar
   «Contraste con Drive pendiente», pulsar «Ver copia anterior», restaurarla y
   verificar el estado modificado tras otro reinicio.
5. Repetir hasta superar tres automáticas; comprobar las tres más recientes y
   conservación de M1/M2. Provocar un fallo controlado en la instalación de
   prueba y comprobar aviso, reintento y ausencia de poda tras el fallo.
6. Probar copia truncada y futura, y cierre forzado nativo en fases del
   intercambio; reabrir y verificar que los datos corresponden al resultado
   recuperado y que sigue existiendo una versión anterior restaurable.

Registrar versión de OS/SDK, dispositivo, commit, acciones, resultados y capturas
sin datos personales. No marcar esta lista como ejecutada por pasar widgets.

## Límites reales

La inyección de disco usa una excepción sintética en el puerto de persistencia;
no llena el volumen del equipo ni acredita el comportamiento de todos los
drivers ante ENOSPC, permisos o avería física. `exit(73)` demuestra terminación
del proceso propietario y recuperación de sus ficheros, no corte eléctrico,
apagado del sistema ni cierre forzado en Android. El host probado es Windows;
la persistencia nativa Android y los controles del sistema siguen pendientes.
El contraste probado es local: no se contacta Drive ni se acredita sincronización
remota. La conservación indefinida manual se verifica mediante operaciones y
reinicios, no mediante una espera temporal infinita.
