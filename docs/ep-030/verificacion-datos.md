# MA-TSK-248 · Verificación de T02

Ejecución del 2026-10-20 en host Windows. Punto de partida
`79b118f808ac9edab920b1e13e5837a0d2b615e6`, rama configurada
`ticket/ma-tsk-193`. El checkout ya tenía modificaciones concurrentes de
sincronización y otros artefactos: se conservaron y quedan fuera del commit T02.
Las comprobaciones corresponden a ese working tree más los archivos propios;
no se presenta como validación de un paquete final limpio o instalado.

## Artefactos y reproducción

- [Preparación y reposición](datos-sinteticos.md): base, doce variantes,
  puntos de fallo existentes, comparación entre equipos y enlace Openbank.
- [Oráculos y hashes](oraculos.json): céntimos EUR y SHA-256 de cuatro CSV.
- `node docs/ep-030/preparar-datos.mjs --destino CARPETA_NUEVA`: empaqueta los
  archivos; nunca sobrescribe un destino existente ni abre una instalación.
- `test/support/integral_reference.dart`: soporte de pruebas que importa el
  CSV exacto con los servicios existentes y crea las fotos manuales sintéticas.
  Exige catálogos/datos vacíos y no localiza instalaciones por su cuenta.

## Comprobaciones efectivas

| Comprobación | Resultado |
|---|---|
| `flutter --version` y `scripts/check-toolchain.ps1` | Flutter 3.47.0 / Dart 3.13.0 correctos. |
| `flutter pub get --enforce-lockfile` | Correcto; lockfile y toolchain sin cambios. |
| `node docs/ep-001/verificar-casos.mjs` | OK: cifras y reglas de referencia existentes. |
| `node --check docs/ep-030/preparar-datos.mjs` y ejecución sin destino | OK: sintaxis, CSV original, copia Dart portable, conteos, duplicados y cuatro hashes. |
| Formato de `lib test integration_test` mediante `check-quality.ps1` | 508 archivos, cero cambios pendientes. |
| `flutter analyze --no-pub --fatal-infos --fatal-warnings` | Sin incidencias; repetido sobre la versión final. |
| `flutter test --no-pub test/integral_reference_test.dart` final | **9/9 correctos**; base persistente, todas las tablas de copia SQLite, UUID/revisión, fotos, propuesta, CSV variantes independientes y motivos del indicador. |
| `scripts/check-quality.ps1`, suite general | **2021 correctos / 2 fallidos**. El script termina con error por I01 de EP-015, detallado abajo. |
| Arranque `environment_bootstrap_test.dart` con development/test/production/invalid-synthetic | **4/4 correctos**, ejecutados secuencialmente después de la suite general. |
| `git diff --cached --check` | Sin errores de espacios en los archivos T02 preparados. |

La suite general incluye los soportes existentes de recuperación, Drive simulado
y exportación. El lector independiente `sqlite3` contrasta todas las tablas de
la copia consistente T02, además de identidad y revisión; la base reabierta
supera `integrity_check` y `foreign_key_check`. No se infiere igualdad financiera
por el hash del ZIP ni por metadatos de instalación.

Los dos fallos son `test/movements/pending_lifecycle_test.dart`, variantes
«Windows tabla» y «Android tarjetas»: `StateError: Bad state: No element` en
`pending_lifecycle_journey.dart:144` al buscar un widget. Coinciden con I01 de la
[auditoría T01](auditoria-cobertura.md). Propietario EP-015 MA-TSK-138; integración
EP-026/030 según esa matriz. T02 no modifica sus tests ni su implementación,
no oculta los fallos y no declara verde la calidad general.

Incidencias de ejecución: el primer `pub get` restringido no accedió a pub.dev;
la resolución autorizada posterior terminó correctamente. La primera apertura
SQLite de T02 en sandbox informó recuperación bloqueada; la ejecución autorizada
con carpetas temporales pasó. Un intento paralelo de suite dirigida no arrancó
por DLL nativa ocupada por la suite general; se dejó terminar esta y se verificó
T02 de nuevo secuencialmente. No se atribuyen esos errores al producto ni se
alteran permisos/configuración permanente para encubrirlos.

## Límites de entrega

No se ejecutaron builds por no haber cambios de producto/plataforma. No se
modificaron instalaciones personales, sesiones financieras ni archivos Drive.
La evidencia es de **host**, con SQLite real y proveedores simulados en las
suites existentes. No es runner nativo, emulador, paquete production, teléfono
físico ni Google real; esas ejecuciones siguen en los tickets de EP-030.

Openbank permanece pendiente de entrega efectiva de fixtures fieles MA-TSK-129.
El enlace y sus requisitos están preparados sin inventar estructura bancaria.
T02 queda preparado para ambos dispositivos; no se cierra ni se acepta la épica,
ni se da por cumplida su prueba Openbank final por documentar el bloqueo.
