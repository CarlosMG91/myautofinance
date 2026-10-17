# Verificación de MA-TSK-228

2026-10-17 · Solo contrato de instalación (T01). Ticket y épica consultados en
`GET http://localhost:4310/api/data`, tablero My autofinance. Rama configurada
`ticket/ma-tsk-193`, upstream `origin/ticket/ma-tsk-193`. Se conservan cambios
concurrentes de sincronización/README y prototipos ajenos fuera del commit.

## Comprobaciones propias

- `flutter --version`: Flutter 3.47.0 / Dart 3.13.0. Coinciden con
  `toolchain.json`; `scripts/check-toolchain.ps1` correcto. No se cambia SDK,
  pubspec ni lockfile.
- `scripts/check-windows-installation-contract.ps1`: contrato JSON legible,
  AppId válido, metadata fuente y BINARY_NAME actuales, path_provider_windows
  2.3.0 en lockfile, versión `0.1.0+1` y tupla PE `0.1.0.1` correctos.
- Con `-ExecutablePath build/windows/x64/runner/Release/myautofinance.exe`:
  comprobación correcta de recursos string, FILEVERSION/PRODUCTVERSION
  numéricas y cabecera PE AMD64. Es una salida local **preexistente**; no se
  ejecuta y no se presenta como payload de producción ni instalador verificado.
- La misma comprobación resuelve RoamingAppData mediante `SHGetKnownFolderPath`
  y lo combina con CompanyName/ProductName leídos del PE. Resultado coherente:
  `%RoamingAppData%\com.carlosmg91\Autofinance`. La raíz efectiva del perfil se
  oculta en la salida incluso si está redirigida. No crea/enumera directorios,
  no abre SQLite ni lee registro o Credential Manager.
- Control negativo: pasar el PE del host PowerShell provoca rechazo por
  metadata/versiones ajenas al contrato, como se esperaba.
- Código de path_provider_windows 2.3.0 inspeccionado en el paquete local
  resuelto por `.dart_tool/package_config.json`: Known Folder RoamingAppData,
  subcarpeta desde recursos, fallbacks y saneamiento. La ruta anterior es una
  verificación por derivación API+PE, **no** una llamada a path_provider dentro
  del runner instalado. Esa prueba antes/después corresponde a T03/T08.
- `git check-ignore` confirma ignorados EXE, `manifest.json` y licencias bajo
  `dist-private/windows/`. No se genera ni incorpora ningún instalador real.
- `git diff --check`: correcto.

## Calidad general ejecutada

`scripts/check-quality.ps1`: resolución con `--enforce-lockfile` correcta,
formato de **505 archivos sin cambios**, análisis Flutter sin incidencias.
La primera resolución en sandbox no pudo consultar `pub.dev`; se repitió el
control con acceso de red autorizado, sin actualizar dependencias.

La suite completa terminó en **2.009 pruebas superadas y cuatro fallos**:

- `test/movements/pending_lifecycle_test.dart`, Windows y Android: `No element`
  al buscar el control en `pending_lifecycle_journey.dart:144`.
- `test/synchronization/local_recovery_journey_test.dart`, dos copias manuales
  y recuperación: timeout de 30 s y base bloqueada por recuperación en teardown.
- En el mismo archivo, fallo de disco tras instalar: rollback con canal de
  isolate cerrado (`CouldNotRollBackException`).

Son los mismos casos que ya constaban fallidos en la
[validación anterior](prototipo/README.md), aunque el caso de las dos copias
ahora termina por timeout. No se establece su causa ni se modifican/reintentan
esos módulos en T01. El checkout conserva cambios concurrentes. **El control
general no pasa** y se detiene antes de su bloque posterior de pruebas por
`APP_ENV`, que no se ejecutó. Log completo local ignorado:
`.tools/ma-tsk-228-quality.log`. La verificación específica de este contrato sí
es correcta; no se usa para declarar corregidos los fallos generales.

## Cobertura y límites

| Criterio del ticket | Evidencia / traspaso |
| --- | --- |
| Identidad estable, soporte Roaming y persistencia separada | Contrato JSON, comprobador fuente/PE y tabla de artefactos en contrato |
| GUID/target y adopción inicial | Derivación nativa inspeccionada; invariantes y puertos para T03; sin leer secretos |
| Actualización/reparación/downgrade/cierre/cancelación | Reglas de versión y coordinación en contrato; implementación T03/T05 |
| Migración y respaldo sin SQL en instalador | Referencias a LocalDatabaseStore/EP-004/006, límites de propiedad explícitos |
| Uninstall conserva finanzas y limpia solo identidad propia | Secuencia/idempotencia de cleanupOwnSession; T03/T05 verifican con identidades sintéticas |
| Manifiesto, licencias, firma y canal privado | Campos obligatorios y política local ignorada; generación T02/T06 |
| Equivalencia patrimonio y dependencias | Cruces EP-009/017/026 documentados; sin dependencia EP-020 ficticia |

No se modifican código Dart/nativo, esquemas financieros ni interfaces del
producto. No procede recompilar plataformas por este cambio de contrato.
No se instalan/desinstalan paquetes ni se ensaya OAuth o Credential Manager
personal. Offline limpio, adopción/interrupción, actualización/conservación y
desinstalación efectiva requieren implementación y E2E T03/T05/T08. No se
infiere aprobación visual desde esta validación.
