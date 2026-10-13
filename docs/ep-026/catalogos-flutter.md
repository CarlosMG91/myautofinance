# MA-TSK-215 · Catálogos con el kit compartido

Categorías, selector, fichas de cuentas/carteras/deudas y editores de liquidez
usan el tema claro y la superficie `AfCatalogPage`. El encabezado, contexto,
acciones, estados y tarjetas se componen desde la entrada pública del kit.
La página tiene un único scroll y un grupo de recorrido de foco; las pantallas
conservan sus loaders, validadores, borradores, confirmaciones y navegación.

## Contrato conservado

- El árbol conserva expansión, archivadas, scroll y foco al volver del editor.
  Muestra ruta, nivel, tipo efectivo y estado. PC usa tabla; Android y texto
  ampliado usan tarjetas. No cambia la marca heredada ni el archivado de rama.
- El selector conserva UUID, rutas y nombres duplicados. La selección es un
  borrador hasta pulsar «Seleccionar»; cancelar y Back no aplican cambios.
  Una referencia archivada previa puede conservarse, pero no reasignarse.
  Invalidaciones y errores siguen impidiendo confirmar datos obsoletos.
- El editor mantiene validación de ciclos, padre archivado y altura de toda la
  rama antes del guardado: no admite un cuarto nivel. Traslado, promoción,
  cambio de tipo y conflictos históricos siguen en `CategoryManagement`.
- Las fichas incluyen cuentas, carteras y deudas cerradas. Consulta y edición
  se distinguen: los campos aparecen al editar; el detalle muestra vigencia y
  periodos de liquidez. Los controles desplegables refluyen sin altura fija.
- El catálogo conserva las filas durante una relectura para mantener scroll y
  foco en la ficha de origen, y bloquea aperturas duplicadas. Los fallos no se
  anuncian como guardados ni sustituyen la información por importes inventados.
- Alta/baja inclusivas, fin exclusivo de liquidez, correcciones históricas y
  confirmaciones conservan sus servicios. Errores de fecha/vigencia se muestran
  junto al campo y lo enfocan; un fallo conserva el borrador.

No cambia ningún modelo, repositorio, migración, importe, foto, cálculo,
clasificación persistida, icono/color de categoría ni comportamiento de Drive.

## Coordinación de consumidores

`app/category_selector_navigation.dart` sigue abriendo **el mismo**
`CategorySelector` desde movimientos y presupuesto; no hay otro selector ni
un servicio nuevo. La alta vuelve por la API existente con el UUID creado.
Las pruebas de presupuesto buscan la opción en el scroll compartido, sin
depender de la antigua implementación `ListView`.

Patrimonio/fotos y Gestión conservan `AccountCatalogScreen`,
`AccountFormScreen` y sus rutas/contextos de origen. La elegibilidad de cuenta
de un movimiento y la vigencia de las filas de foto permanecen en sus
propietarios: el catálogo no inventa saldos ni añade otro filtro financiero.

## Procedencia y autorización

Se consultó el ticket facilitado y el API local de Epic Board, tablero
**My autofinance**: MA-TSK-215 en ejecución; MA-TSK-207 y MA-TSK-208 terminados.
La instrucción vigente autoriza implementar y declara T05 completado. Los
registros locales del prototipo todavía contienen texto de aprobación
pendiente; este ticket no fabrica evidencia textual de aprobación ni cambia
el artefacto conservado. Su propietario debe reconciliar ese registro.

Los cambios iniciales de categorías/fichas y `AfCatalogPage` se identificaron
como trabajo previo de este ticket mediante los scripts locales `edit-215`,
`tree-215` y `account-215`. Se completan aquí. README, importaciones, copias y
backend Drive concurrentes quedan fuera del commit.

## Verificación reproducible

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
./scripts/check-quality.ps1
flutter drive -d windows --profile --driver=test_driver/catalog_redesign.dart --target=integration_test/catalog_redesign_test.dart --dart-define=APP_ENV=test --no-pub
flutter drive -d emulator-5554 --profile --driver=test_driver/catalog_redesign.dart --target=integration_test/catalog_redesign_test.dart --dart-define=APP_ENV=test --no-pub
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

El recorrido nativo usa SQLite en memoria y solo datos sintéticos; no abre la
instalación personal ni conecta Drive. Recorre árbol con archivadas, formulario
con error, selector, fichas, detalle y liquidez al 100/200 %. El driver conserva
las capturas en `catalogos-capturas/` antes de retirar la app de prueba Android.
Son píxeles del motor Flutter en aplicaciones Windows/Android, capturados en
su superficie, sin marco del sistema ni barra de tareas. No son goldens ni
capturas HTML y no acreditan por sí solos TalkBack/Narrador.

La compilación Windows debug del host falla al enlazar el runtime C++ debug
(`_malloc_dbg`, LNK1120). El recorrido usa profile, sin cambiar la configuración
nativa del proyecto. Las compilaciones de entrega usan release Windows y debug
Android. Android usa la configuración local aislada con Temurin JDK 17.
No se actualizan SDK, lockfile ni paquetes.

## Resultado · 2026-10-13

- Flutter 3.47.0 / Dart 3.13.0, verificador de toolchain y resolución fijada:
  correctos. La primera resolución restringida se completó offline; la
  verificación general volvió a resolver con `--enforce-lockfile`. SDK,
  dependencias y lockfile permanecen sin cambios.
- Formato: 408 archivos sin cambios. Análisis final: sin incidencias. Las
  pruebas dirigidas de árbol/selector/fichas/liquidez/retorno pasan, incluidas
  alturas 320–1440 y texto 100/200 %, ciclos, cuarto nivel, archivadas,
  conflictos y borradores. La nueva prueba de foco tras renombrar y releer
  SQLite pasa.
- `check-quality.ps1` ejecutado: **1.728 pruebas correctas y un timeout** en
  `budget_lifecycle_test`, variante Android, durante las compilaciones.
  El caso completo se repitió sin builds concurrentes: **correcto, 21 s**,
  incluyendo histórico archivado, persistencia, rollback y reapertura.
  No se declara verde esa ejecución global ni se amplían timeouts o eliminan
  comprobaciones para ocultar el fallo. Todos sus casos han pasado entre la
  ejecución general y la repetición aislada.
- Arranque development/test/production/invalid-synthetic: las cuatro
  comprobaciones adicionales pasan, ejecutadas secuencialmente tras SQLite.
- Recorridos nativos Windows profile y Android profile: correctos, con **24
  capturas** del estado final entregadas por el driver. Revisión visual de
  árbol PC, ficha PC/Android, selección ampliada y errores junto al campo:
  tema/fuente coherentes, reflujo y scroll sin overflow. Android: emulador API
  37, viewport lógico 412×915; Windows: viewport nativo 1266×683.
- Builds de la aplicación principal: **Windows release y APK debug correctos**
  con APP_ENV=test. El recorrido Android y el APK usan Temurin JDK 17 en
  configuración local aislada. El fallo Windows debug del host no afecta
  a los dos builds requeridos ni al recorrido profile.

Las pruebas conservan verificaciones de persistencia, rollback, UUID,
conflictos, tipos, archivado y fotos. Las adaptaciones de regresiones externas
solo cambian búsqueda/scroll, Back y el importe textual cuya unidad puede
refluir en el kit; no cambian sus valores esperados ni reglas financieras.
Lectores nativos TalkBack/Narrador y revisión integrada de la épica completa
quedan para T14; no se declaran ejecutados por este ticket.

Entrega únicamente de archivos propios en la rama configurada
`ticket/ma-tsk-113`, sin force push ni cambios concurrentes. El remoto se
comprobó antes de confirmar; los artefactos/caches de build quedan fuera.
