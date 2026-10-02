# MA-TSK-057 · Propuesta visual de recuperación local · v1

Propuesta del 2026-10-02, **pendiente de aprobación humana explícita en Epic Board**.
No cierra el ticket ni autoriza MA-TSK-058 o tickets posteriores.

Mockup retenido: [mockup-recuperacion-local.html](mockup-recuperacion-local.html).
Revisión desde Epic Board: <http://localhost:4310/mockups/autofinance-ma-tsk-057-v1.html>.
El HTML es autónomo, sin fuentes, dependencias ni servicios externos. Todas las
fechas, identificadores y tamaños son sintéticos. Las acciones solo modifican
memoria del prototipo; recargar restablece los ejemplos.

## Fuentes y alcance

Se consultaron MA-EPIC-050 y sus tickets en `GET /api/data`, tablero
**My autofinance**, con workspace coincidente. MA-TSK-019 y MA-TSK-020 están
`done`; la discusión de MA-TSK-019 registra la aceptación humana de su mockup.
Se reutilizan [entrega Flutter](../ep-002/entrega-flutter.md) y
[sistema visual](../ep-002/sistema-visual.md), junto con los contratos de
[catálogo](catalogo-retencion.md), [validación](validacion-candidatas.md),
[restauración](restauracion-segura.md) y [reinicio](recuperacion-interrumpida.md).

La nueva entrada **Copias locales** se propone en Gestión, antes de Copia en
Drive. Mantiene los cinco destinos principales de EP-002. El catálogo y el
detalle son rutas secundarias (`/copias-locales` y `/copias-locales/:id`), con
retorno a destino y periodo de origen; el ejemplo usa Estado, octubre de 2026.
El acceso de recuperación de arranque no depende de abrir SQLite activa.
Las rutas son propuesta para la futura integración, no cambios en Flutter.

## Recorrido y estados

1. Gestión → Copias locales: tabla compacta Windows; tarjetas Android, fechas
   en hora local con zona indicada, origen manual/previa a restauración,
   tamaño, última comprobación y detalle. La última comprobación nunca promete
   validez actual; se revalida antes del intercambio.
2. Crear copia: confirmación del almacenamiento local, progreso y éxito solo
   después de captura, comprobación y registro. Sin copias ofrece primera copia.
3. Detalle: fecha/origen, conservación, comprobación y consecuencias para todos
   los datos. Una copia incompleta conserva su ficha pero no permite restaurar.
4. Confirmación: Cancelar primero y con foco inicial, aceptación de consecuencias,
   Restaurar habilitado solo tras marcarla. Cancelar/Esc devuelve el foco sin
   crear respaldo. La pantalla de progreso bloquea nuevas operaciones.
5. Éxito: reapertura y comprobación confirmadas, acceso a copia automática anterior
   y aviso de contraste remoto pendiente sin conexión. Con base dañada conserva
   originales aislados, sin presentarlos como una copia restaurable.
6. Fallos: validación rechazada con motivo concreto, falta de espacio, catálogo
   inaccesible (distinto de vacío), restauración revertida e interrupción resuelta
   antes de abrir datos. La validación fallida simulada muestra huella alterada.
7. Eliminación expresa: confirmación por copia; se explica que requiere otra
   copia comprobada. La simulación no reproduce la revalidación de disco.

Retención visible: manuales indefinidas hasta eliminación expresa, tres
automáticas tras restauración satisfactoria; fallos o limpieza insegura pueden
conservar más. Los originales dañados no participan en la poda. Se advierte que
una copia local no protege frente a pérdida del dispositivo o datos de la app.
No se propone selector de archivo externo, transferencia o fusión.

## Revisión humana

El selector superior permite abrir todos los escenarios directamente. Revisar
catálogo, crear, detalle, cancelar y confirmar restauración; repetir con base
dañada, validación fallida, falta de espacio, catálogo inaccesible e interrupción.
La opción Android limita el shell a 412 px; el modo adaptable responde al ancho
real y cambia a tarjetas por debajo de 840 px.

Comprobar en navegador Windows 1024/1440 y Android 360/412, también a 320 y
texto ampliado al 200 %. Revisar Tab, Intro/Espacio, Esc y retorno de foco,
lectura de estados, orden Cancelar/Restaurar y objetivos táctiles de 48 px.
El diálogo nativo contiene el foco. En PC el lateral tiene 200/216 px; se usan
los colores, fuentes del sistema, espaciado, radios y mensajes de EP-002.

La aceptación debe registrarse por la persona usuaria en Epic Board sobre
**MA-TSK-057 v1**. Si solicita cambios, se retendrá una nueva revisión y se
presentará otra vez antes de implementar las pantallas.

## Verificación y límites

- Sintaxis JavaScript comprobada con Node y `git diff --check` sin incidencias.
- Flutter 3.47.0 / Dart 3.13.0 comprobados y `scripts/check-quality.ps1`
  completo correcto: 102 archivos sin cambios de formato, análisis sin
  incidencias, 598 pruebas y cuatro variantes adicionales de arranque `APP_ENV`.
  El primer intento quedó bloqueado en pub.dev por la red del sandbox; el
  segundo, con permisos revisados, resolvió con `--enforce-lockfile` sin
  modificar paquetes ni lockfile.
- Ejecución lógica con DOM simulado: tabla/tarjetas, detalle, diálogo, cancelación,
  éxito, ocho escenarios, rechazo por huella/espacio sin cambiar catálogo y
  restauración de base dañada sin inventar copia anterior válida.
- Publicación local comprobada por HTTP 200 y comparación SHA-256 con el HTML
  retenido. El enlace funciona mientras Epic Board esté disponible en esta máquina.
- No hay navegadores conectados al entorno de Computer Use: no se pudo comprobar
  el renderizado, teclado real, lector de pantalla ni Android físico. La revisión
  visual y accesible sigue pendiente; las simulaciones no prueban SQLite o disco.
- No se cambian widgets, plataformas, SDK, paquetes ni contratos financieros.
  Los builds Windows/Android no corresponden a este suplemento HTML.
