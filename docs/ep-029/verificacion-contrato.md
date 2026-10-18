# MA-TSK-237 · Verificación e inventario real

Revisión del 2026-10-18 sobre `d45f944`, rama configurada `ticket/ma-tsk-193`,
remoto `origin` del proyecto. [Contrato v1](contrato-apk-privado.md).
Se consulta `GET http://localhost:4310/api/data`, tablero **My autofinance**,
workspace coincidente, MA-EPIC-236, MA-TSK-237 y T02–T09. Sin requisitos ni
adjuntos adicionales en T01. No se modifica el estado del tablero desde código.

El checkout ya contenía cambios de README y sincronización (transferencia,
estado, subida y factoría), documentos/fixtures EP-007/008/013/014/015 e imágenes
sin seguimiento. No pertenecen a esta entrega ni se confirman/suben con ella.
Las comprobaciones Flutter usan el árbol compartido; no acreditan por sí solas
que todas sus dependencias concurrentes estén publicadas.

## Producción frente a debug: valores comprobados

| Elemento | Observación, no promesa de entrega final |
| --- | --- |
| Flutter / Dart | `flutter --version` y `check-toolchain.ps1`: 3.47.0 / 3.13.0, revisión `4cf2416426`; informa canal `[user-branch]`, conservado |
| JDK y Android | JDK local Temurin 17.0.20.1+1; Platform 36, Build-Tools 36.0.0 y NDK 28.2.13676358 disponibles; `FlutterExtension.kt` delegada fija min 24, compile/target 36 y ese NDK |
| Gradle release | `signingConfigs.getByName("debug")`: carencia real T02, aunque el modo se llame release |
| Versión fuente | `pubspec.yaml`: `0.1.0+1`; Gradle delega nombre/código a Flutter |
| APK inspeccionado | Salida debug preexistente `build/app/outputs/flutter-apk/app-debug.apk`; no se recompila ni distribuye como producción en T01 |
| APK efectivo: aapt2 | Paquete `com.carlosmg91.myautofinance`, nombre `0.1.0`, código `1`, min 24, compile/target 36, `debuggable=true` |
| ABI efectivas | `arm64-v8a`, `armeabi-v7a`, `x86_64`; no se ha ejecutado este artefacto en un teléfono ARM64 |
| Firma efectiva | apksigner verifica esquema v2; certificado `Android Debug`, no firma propia estable de distribución |
| OAuth | `config/google-oauth.public.json`: `blocked_external`, proyecto nulo, API desactivada, tester no acreditado, clientes Android vacíos y serverClientId nulo |
| Cableado real | `lib/app/drive_ui_factory.dart` lee `GOOGLE_ANDROID_SERVER_CLIENT_ID`; si falta, muestra «Drive no está configurado» y no compone subida/descarga |
| Backup Android | Manifiesto actual sin `allowBackup`, `fullBackupContent` ni `dataExtractionRules` explícitos; corrección corresponde a T06 según contrato |
| Dispositivo observado | Solo emulador `sdk_gphone64_x86_64`, API 37, ABI anunciadas `x86_64,arm64-v8a`; no equivale a teléfono ARM64 ni ensayo API 24/36 |

Huellas **públicas** del artefacto debug inspeccionado, no claves:

```text
SHA-256 archivo APK:
1494b550d6d851b69ebc4835774683ca891c573fb4ed20a3efc45cad251dd13c
SHA-256 certificado:
ddee29550a697d3fcde71c81f6fd077c17913e79acd91c4fde7b1d3d1b4a113c
SHA-1 certificado:
5b437e4801e7b0fd7fe0e054b38d2fc46f33e064
```

La ruta de build es reutilizable: una compilación posterior puede sustituir sus
bytes. Solo el hash identifica esta inspección. No se atribuye al APK un entorno
APP_ENV deducido del nombre, ni se declara APK final/reproducible/preservación.
El NDK se contrasta en SDK/configuración, no en el manifiesto binario.

La consulta de solo lectura `dumpsys package`/`pm path` en el emulador observado
no devuelve instalación del paquete. No hay APK instalado que inventariar allí
ni se han leído bases financieras. No se conoce el estado de un teléfono del
usuario: **cualquier transición debug con datos sigue bloqueada hasta demostrar
copia externa y recuperación segura**. No se instala, desinstala, borra ni
sustituye ninguna aplicación en esta tarea.

## Capacidades reutilizables y carencias

| Requisito | Evidencia concreta existente | Límite para EP-029 |
| --- | --- | --- |
| EP-004/006 persistencia y recuperación | `LocalDatabaseStore`, copias consistentes, migraciones, catálogo/restauración; contratos `docs/ep-004/persistencia-local.md` y `docs/ep-006/contrato-copias-locales.md` | Reutilizar; falta prueba N→N+1 production T07/T09, no crear motor Android paralelo |
| EP-005/007 Drive | Proveedor Android, `DriveSessionStore.kt`, estado `drive-sync`, reconciliación/subida/descarga; `docs/ep-007/verificacion-sincronizacion.md` | Pruebas sintéticas/documentación no acreditan Google real; alta nula y cambios concurrentes de subida aún sin confirmar al inicio |
| EP-019 Estado | Consultas y tarjetas Android; `test/monthly_status/monthly_status_journey_test.dart`, `docs/ep-019/verificacion-integrada.md` | Evidencia funcional previa, no del APK final firmado |
| EP-021 Presupuesto anual | Consultas/formulario/tarjetas, `test/budget/annual_budget_lifecycle_test.dart`, `docs/ep-021/verificacion-integral.md` | Repetir integración en artefacto production exacto |
| EP-022 Real anual | Consultas/tabla/tarjetas y `test/actual_spending/annual_actual_lifecycle_test.dart`, `docs/ep-022/validacion-integral.md` | No sustituir por marcador o por motor nuevo |
| EP-023 Indicador | `indicator_engine.dart`, cálculo de colchón y proveedor; `test/indicators/indicator_acceptance_test.dart`, `docs/ep-023/validacion-integrada.md` | Solo indicador aprobado, repetir cifras/ausencias en APK final |
| Patrimonio equivalente EP-020 | EP-009/017/026, `test/wealth/wealth_lifecycle_test.dart`, `docs/ep-026/patrimonio-flutter.md` | Fotos manuales y liquidez histórica conservadas; EP-020 no existe como entrega independiente |
| EP-026 navegación/diseño | Referencia aprobada en `docs/ep-026/prototipo/aprobacion.md`; componentes Flutter reales | Aprobación HTML no equivale a aceptación visual final ni a prueba APK production |
| EP-014 Openbank | `docs/ep-014/verificacion-reapertura-131.md`: falta muestra, lector/adaptador e integración; ruta deshabilitada en `app_router.dart` | Bloqueo concreto MA-TSK-245. Un selector o guion sintético `bank_import_wealth` no lo resuelve |

Firma, generador y reglas Android pueden avanzar sin Openbank; el gate final
requiere la entrega efectiva MA-TSK-131 y repetir su recorrido en el artefacto
final. EP-025/027/028 no se usan como bloqueos artificiales ni se modifican.

## Comprobaciones de esta entrega

El inspector `scripts/check-android-apk-contract.mjs` usa aapt2 y apksigner
oficiales por procesos sin shell, sin imprimir stderr externo, rutas personales
o identidad de cuentas. Solo emite metadatos públicos y hashes. El resultado
siempre dice `completeDelivery=false`; no sustituye los gates de T05/T09.

- `node --test scripts/tests/android-apk-contract.test.mjs`: nueve pruebas
  correctas: lectura de SDK/ABI, evidencia incompleta, múltiples firmantes,
  debug incluso en release, certificado esperado, incremento numérico,
  paquete/firma incompatibles, API/ABI, rechazo de split incluso con ABI
  suficientes, override/rango de versión y contrato
  frente a Gradle/toolchain. Todas las huellas de fixtures son sintéticas.
- Inspección del APK existente con `--allow-debug`: salida cero y datos de la
  tabla. Sin esa opción: salida 1 esperada por debuggable, certificado debug y
  ausencia de huella de distribución esperada.
- Comparación del APK consigo mismo como `--previous-apk`, solo inspección de
  prueba: salida 1 esperada por versionCode no creciente. No se intenta instalar.
- `git check-ignore`: excluye `dist-private/android/test.apk`, APK/AAB fuera de
  build, JKS y `android/key.properties`. No se versiona ningún binario o secreto.
- `git diff --check`: correcto para los cambios propios. Gradle, manifiesto,
  SDK, lockfile, configuración OAuth y motores financieros sin cambios propios.

No se requiere recompilar plataformas por cambios de contrato, inspector y
exclusiones Git: no se altera código Flutter, Gradle ni recursos nativos.

Logs locales ignorados del intento previo: `.tools/ma-tsk-237-board.json`,
`ma-tsk-237-apk-inspection.json`, `ma-tsk-237-debug-rejected.json`,
`ma-tsk-237-equal-version-rejected.json`, `ma-tsk-237-quality.log` y
`ma-tsk-237-quality-network.log` bajo `.tools/`. La instantánea del tablero no
se publica. APK y claves permanecen fuera de Git y de artifacts/releases públicos.

## Continuación y comprobación del contrato

En la continuación del 2026-10-18 se vuelven a consultar el ticket y T02–T09
en el tablero vivo, a comprobar Flutter/toolchain y a inspeccionar el mismo
APK debug: metadatos, certificado y hash coinciden con la tabla anterior.
Se completan los borradores específicos MA-TSK-237 del intento previo; siguen
fuera de esta entrega los cambios concurrentes de otras épicas.

El inspector añade rechazo explícito de un APK con atributo `split`, aunque
su manifiesto anuncie las ABI requeridas. Pasan las nueve pruebas Node y las
exclusiones Git para APK/AAB/JKS/key.properties. No se instala ningún APK.

La primera consulta ADB falla por permisos al crear su directorio de usuario.
El reintento autorizado de solo lectura confirma el emulador API 37 y las ABI
de la tabla. `pm path com.carlosmg91.myautofinance` no devuelve instalación
(salida 1). No aparece un teléfono real ni se conoce su instalación o sus
datos. Sigue bloqueada cualquier sustitución debug incompatible en él hasta
acreditar origen, copia externa y recuperación.

La ejecución de `check-quality.ps1` se detiene primero en la consulta de
avisos de pub.dev por restricción de red (SocketException, errno 10057).
Se reintenta con acceso autorizado y log local ignorado
`.tools/ma-tsk-237-resume-quality-network.log`; el primer intento está en
`.tools/ma-tsk-237-resume-quality.log`. No se cambia SDK ni lockfile.

El reintento resuelve las dependencias con `--enforce-lockfile`, comprueba el
formato de 505 archivos (cero cambios) y termina el análisis sin incidencias.
La suite completa finaliza en 11 min 4 s: **2.011 aprobadas y dos fallidas**.
Ambas son `test/movements/pending_lifecycle_test.dart`, casos «EP-015 completo
con SQLite: Windows tabla» y «Android tarjetas»: `Bad state: No element` en
`pendingLifecycleJourney.tap`, al buscar `PopupMenuButton<String>`.
Son los dos fallos ya reproducidos y registrados antes de T01 en
[MA-TSK-131](../ep-014/verificacion-reapertura-131.md); este ticket no modifica
sus archivos, los widgets ni los servicios Flutter. No se declara calidad
global correcta ni se cambian otras épicas para resolverlos.

El script se detiene al fallar la suite, antes de las cuatro variantes de
arranque. Se ejecutan aparte y pasan `development`, `test`, `production` e
`invalid-synthetic` (una prueba por variante, salida cero). No convierten en
correcta la suite global. Sus ejecuciones separadas quedan en
`.tools/ma-tsk-237-resume-bootstrap-<APP_ENV>.log` y el resumen local
`ma-tsk-237-resume-bootstrap-results.json`. No se recompilan plataformas ni se
genera un APK production: esta entrega cambia únicamente contrato, inspector,
pruebas Node y exclusiones Git.

## Traspaso

T01 entrega identidad/contrato, inventario y comprobador técnico. No acredita
firma de distribución T02, OAuth Google real T03, política nativa aplicada T06,
preservación production T07, guía aprobada T08 o APK completo T09. Las carencias
son entradas explícitas para sus propietarios, no una declaración de épica
completada. No hay vía de migración debug acreditada ni lector Openbank
disponible; se conservan intactos los datos y no se ocultan esos bloqueos.
