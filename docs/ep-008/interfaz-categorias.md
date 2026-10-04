# MA-TSK-083 · Gestión de categorías en Flutter

## Aprobación y alcance

Se consultó `GET http://localhost:4310/api/data`, tablero **My autofinance**,
el 2026-10-04. MA-TSK-081 y MA-TSK-082 constan `done`. MA-TSK-082 registra
`approvedAt: 2026-10-04T05:03:18.681Z` y la discusión de «Tú»:
«Propuesta visual aceptada: http://localhost:4310/mockups/autofinance-ma-tsk-082-v1.html».
La propuesta local aún describe su estado anterior a esa aceptación; esta
evidencia del tablero satisface la puerta de implementación del ticket.

Se reutilizan [EP-002](../ep-002/entrega-flutter.md),
[el mockup](mockup-categorias.html), [las reglas](arbol-categorias.md),
[la reorganización atómica](reorganizacion-atomica.md) y
[los casos de uso](operaciones-gestion.md). No se implementan pantallas
financieras, Fichas ni otras funciones de EP-009. Los cinco destinos existentes
mantienen sus marcadores y permiten entrar desde Gestión → Categorías.

## Composición y navegación

`LocalBackupSession.categories()` resuelve la conexión actual del store y
compone `CategoryManagement` mediante la fábrica de MA-TSK-081. Las lecturas y
escrituras resuelven este servicio de nuevo: no conservan un repositorio unido
a una conexión cerrada después de restaurar o reabrir. Se respetan el bloqueo
de recuperación y la misma base SQLite privada de la instalación.

Rutas: `/categorias`, `/categorias/nueva`, `/categorias/:id`. La lista y el
editor son rutas secundarias. El origen permanece en la pila, incluidos sus
parámetros, filtros, scroll, selección y foco. El árbol mantiene filtro de
archivadas, expansión y desplazamiento al volver del editor; abre los
ancestros del destino guardado y devuelve el foco a la categoría editada.

`CategoryNavigationContext(returnLabel: ..., onCreated: ...)` permite al
selector propietario recibir únicamente el `CategoryDetails` del alta
confirmada y volver directamente al selector. Cancelar no llama ese callback;
el selector conserva la selección anterior y su borrador. También se admite
entrada directa al alta. No se guarda ningún movimiento desde estas rutas.

## Árbol, formulario y operaciones

Tabla desde 840 px; tarjetas por debajo de ese ancho. Nombre, ruta completa,
nivel, tipo efectivo/heredado y estado visibles, con expansión anunciada y
acciones etiquetadas con la ruta. Se puede mostrar el catálogo archivado.
Carga, vacío, error de lectura y reintento tienen mensajes propios.

Campos: Nombre, Padre con ruta y UUID (también desambigua rutas idénticas),
Tipo. El nombre admite duplicados. El tipo es solo lectura en descendientes
y en promociones. `canChangeRootType` consulta `CategoryRepository.hasReferences`
para bloquear el campo en raíces con datos en cualquier mes y descendiente,
incluidos archivados y partidas de cero. Esta lectura no incrementa revisión.
La validación transaccional existente vuelve a comprobarlo al guardar.

Crear y editar usan `CategoryManagement.create/edit`; archivar/reactivar usan
sus casos de uso de rama completa. El cambio de padre exige revisión con
ruta/tipo antes y después, número de categorías y efecto sobre el histórico,
sin invertir importes. Promover conserva el tipo anterior. Archivo y
reactivación requieren confirmación; archivar no borra referencias.

La UI señala nombre vacío, ciclos, padre archivado y profundidad del subárbol.
SQLite revalida las reglas y los solapamientos en todos los meses de forma
atómica. Un conflicto muestra mes en español, ambas rutas propuestas y UUID;
conserva el formulario y no ofrece fusión, borrado ni ajuste de partidas.
Errores técnicos se traducen mediante la composición de MA-TSK-081.

Guardar bloquea campos y acciones hasta recibir respuesta y salir de la ruta,
evitando dobles escrituras. Un error conserva los campos y devuelve el foco
después de habilitarlos. Cancelar, Volver, Escape y Android Back preguntan
«Hay cambios sin guardar» si hay borrador; «Seguir editando» es la primera
opción. Durante escritura no se abandona la ruta. Los diálogos contienen el
recorrido de Tab, enfocan su título y devuelven el foco tras cerrarse. Errores
y estados tienen regiones semánticas de anuncio.

## Verificación

Todas las pruebas y capturas emplean datos sintéticos. SDK fijado:
Flutter 3.47.0 / Dart 3.13.0. No se cambian SDK, lockfile ni esquema SQLite.

`test/movements/category_screen_test.dart` cubre navegación desde los cinco
destinos y periodo completo de retorno; alta desde selector y cancelación;
traslado/promoción/renombre; archivo/reactivación; bloqueo de tipo usado;
conflicto de enero de 2025 con rollback; errores de lectura y escritura;
doble guardado y Back durante escritura; teclado, foco y semántica; contexto
del árbol; sesión SQLite real y reapertura antes de guardar.

Pruebas de layout en 320, 360, 412, 839, 840, 1024 y 1440 px, con texto
100 % y 200 %, bajo configuración de plataforma Android/Windows. Capturas
de árbol, formulario y confirmación en 320/412/1440, con fuentes locales:

```powershell
$env:CATEGORY_CAPTURE = '1'
flutter test --no-pub test/movements/category_screen_test.dart
```

Se generan en `.tools/083-<ancho>-<estado>.png` (excluidas de Git).
Se inspeccionaron capturas del árbol PC y formulario/confirmación móvil;
los errores de overflow se comprueban en todos los tamaños de la matriz.
Esta evidencia de widgets no equivale a un lector de pantalla o Android físico.

Recorrido nativo reproducible sobre una base aislada dentro del soporte de
la app (nunca la base personal):

```powershell
flutter test integration_test/category_management_test.dart -d windows --no-pub --dart-define=APP_ENV=test
flutter test integration_test/category_management_test.dart -d <id-android> --no-pub --dart-define=APP_ENV=test
```

El recorrido usa Gestión, alta, cancelación sin escritura, traslado, archivo
y reapertura de SQLite. No necesita OAuth ni servicios remotos.

Las 26 pruebas de interfaz pasan sobre SQLite real, incluido el catálogo
semántico de expansión y la conservación de foco/scroll/filtro.
`./scripts/check-quality.ps1` completo: versiones y lockfile exigido, formato
sin cambios (148 archivos), análisis sin incidencias, **837 pruebas correctas**
y las cuatro variantes development/test/production/invalid-synthetic correctas.
La suite incluye trabajo concurrente de sincronización, excluido del commit.
`flutter build windows --release --no-pub --dart-define=APP_ENV=test` correcto
con el código final: bundle en `build/windows/x64/runner/Release/`.
El comprobador numérico `node docs/ep-001/verificar-casos.mjs` pasa, incluidos
L/M y la conservación de signos. `git diff --check` correcto.

Android: se intentó `flutter build apk --debug --no-pub --dart-define=APP_ENV=test`;
falla con «No Android SDK found». `flutter devices` no detecta dispositivo
Android. Por ello el APK y el recorrido nativo Android quedan sin verificar.

Windows: se intentó el recorrido de integración preparado. La compilación
debug llega al enlazador y falla con LNK2001/LNK2019/LNK1120 para símbolos
del runtime debug de C++ (`_CrtDbgReport`, `_malloc_dbg`, `_free_dbg`, etc.),
usando Visual Studio 18 Insiders y Windows SDK 10.0.26100.0 de esta máquina.
El test no llegó a ejecutarse: no se acredita recorrido UI nativo.
No se cambian bibliotecas ni reglas de plataformas de otras épicas para
sortear ese límite. TalkBack/Narrador y recorrido manual táctil sin verificar.

La primera compilación Windows alcanzó la instalación, pero una caché CMake
previa apuntaba a `C:/Program Files/myautofinance`. Se corrigió exclusivamente
la caché local ignorada a `$<TARGET_FILE_DIR:myautofinance>`; no se modificaron
archivos de plataforma ni se instaló en directorios del sistema.
El build release Windows posterior produjo el ejecutable y su bundle.

Los cambios de sincronización y del prototipo MA-TSK-082 presentes al empezar
permanecen fuera de la entrega de MA-TSK-083. No se actualiza el estado
administrativo del tablero ni se da por finalizada EP-008.
