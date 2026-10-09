# MA-TSK-074 · Capturar y corregir fotos patrimoniales

La carencia de verificación Android de esta entrega se revisa el 2026-10-09
en [MA-TSK-148 · Verificación nativa](../ep-017/verificacion-android.md), con
APK, recorrido SQLite en emulador, Back real y evidencia sintética.

Ticket consultado el 2026-10-04 en `GET http://localhost:4310/api/data`, tablero
**My autofinance**. Se aplican EP-001 §4 y caso D, el flujo F0–F4 de EP-002,
la aprobación MA-TSK-019 registrada en `entrega-flutter.md` y el formulario de
`mockup-final.html`. Se reutilizan la composición de MA-TSK-071, las fichas de
MA-TSK-072, las operaciones de fotos de EP-004 y la lectura de MA-TSK-075.

## Formulario y navegación

`/patrimonio/foto?a&m` abre `WealthPhotoScreen` con el mes validado por
`WealthRoute`. La referencia es siempre el día 1 del mes seleccionado, aunque
la captura o corrección sea posterior. El formulario lee exclusivamente ese
mes y muestra nombre, tipo y liquidez efectiva de sus fichas vigentes. Usa
tabla desde 840 px y tarjetas por debajo de ese ancho. Las deudas no tienen
liquidez. No se copian importes de otro mes ni se consultan movimientos.

Vacío deja pendiente; cero es registrado. Se acepta coma o punto decimal, sin
separadores de miles y con hasta dos decimales. `parseWealthAmount` convierte
mediante `BigInt`, valida el límite INTEGER de SQLite y entrega céntimos
enteros; `wealthAmountText` conserva la precisión al reabrir. No se usa double
ni se redondean fracciones de céntimo. El primer campo inválido recibe foco y
su error se muestra junto al campo y se anuncia. Cada campo conserva un nombre
accesible con la ficha, aunque su etiqueta visible sea breve.

Guardar vuelve al origen conservando la pila, los argumentos y el periodo.
Patrimonio relee el mes y muestra el aviso de guardado solo tras confirmación.
Una foto parcial lista pendientes y sigue sin dato; el formulario también
distingue el estado persistido y los campos del borrador. Reabrir permite
completar o corregir. Vaciar un valor registrado lo retira y vuelve a dejar
esa ficha pendiente. Sin valores registrados, el contrato existente devuelve
foto ausente, nunca un patrimonio cero.

Volver, Cancelar, Escape, Atrás y cambiar a cualquiera de los cinco destinos
ofrecen **Seguir editando** o **Descartar cambios** si hay borrador. Escape o
cerrar el diálogo conserva los campos y restaura el foco. El cambio de destino
conserva año/mes. Durante la escritura se bloquean edición y salida. Un error
de lectura ofrece Reintentar; uno de escritura conserva todos los campos y
muestra «No se guardó la foto. Inténtalo de nuevo.». Al volver a editar se
retira el aviso previo para que no cubra las acciones del formulario.

## Guardado y persistencia

`WealthController.savePhoto` resuelve la sesión actual y delega en
`WealthManagement.savePhoto(month, draft)`. El borrador contiene todas las
identidades vigentes; `null` representa ausencia. Si la lista de fichas cambió
desde la lectura, se rechaza el borrador sin escribir. Se copian sus entradas
antes de abrir la unidad de trabajo.

Lectura previa, validación, altas/correcciones, retiradas y lectura del resultado
se ejecutan en una sola unidad de trabajo sobre la conexión compartida. Se
reutilizan `read`, `setValue` y `deleteValue`, sin añadir esquema, migraciones
ni otro repositorio. Corregir conserva identidad y cabecera; repetir los mismos
valores no escribe. Un fallo de cualquier escritura o de la lectura final
revierte toda la operación, incluida la revisión de datos. Una operación con
varios cambios confirmados incrementa la revisión una sola vez.

## Verificación

Datos exclusivamente sintéticos. Las pruebas de `wealth_photo_management_test`
comprueban precisión hasta el límite de SQLite, entradas inválidas, caso D,
ausencia pese a un movimiento posterior al día 1, parcial con pendientes, cero,
corrección con identidad estable, ausencia de arrastre, eliminación a pendiente,
revisión única, repetición sin cambios y persistencia tras cerrar y reabrir la
base en archivo. Fallos inyectados en la última escritura y en la lectura final
conservan valores, identidades y revisión. También se comprueban vigencia
inclusiva, liquidez mensual y rechazo de un catálogo cambiado.

Las pruebas de `wealth_photo_screen_test` verifican carga/reintento, validación
con foco, escritura pendiente sin éxito ni salida, error con borrador y
reintento sin duplicados, Escape y descarte/cancelación, cambio de destino,
Atrás protegido, retorno a febrero, reapertura y completar con cero. Comprueban
320, 360, 412, 839, 840, 1024, 1199, 1200 y 1440 px con texto al 200 %.
Las capturas de widgets a 320 y 1440 px con fuentes legibles se revisaron; no
son una prueba de lector de pantalla ni de dispositivo Android.

Flutter 3.47.0/Dart 3.13.0 comprobados; `toolchain.json` y `pubspec.lock` intactos.
`scripts/check-quality.ps1` completo: formato correcto, análisis sin
incidencias, 898 pruebas y las cuatro variantes adicionales de `APP_ENV`
correctas. Las 47 pruebas del módulo Patrimonio también pasan por separado.
Casos de referencia EP-001/EP-008 correctos y `git diff --check` correcto.
El build Windows release con `APP_ENV=test` se verifica fuera del aislamiento
para permitir acceso a MSBuild. El build Android debug se intenta y queda
bloqueado por ausencia del Android SDK. No se acredita recorrido nativo ni
lector de pantalla. La suite SQLite en archivo requiere ejecución fuera del
aislamiento para abrir los bloqueos de recuperación.

La entrega se limita a los nueve archivos propios de MA-TSK-074 sobre la rama
existente `ticket/ma-tsk-071`, sin incluir los cambios concurrentes de
sincronización, README o prototipos. No se modifica el estado del tablero ni
se cierra EP-009 desde esta entrega.
