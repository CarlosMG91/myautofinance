# MA-TSK-169 · Tarjetas anuales Android

Ticket y dependencias consultados el 2026-10-11 en Epic Board, tablero
**My autofinance**. MA-TSK-166/167/170 figuran completados; MA-TSK-167 registra
la aprobación explícita de la persona usuaria del mockup v1. La indicación
pendiente en el suplemento local es anterior a esa aprobación.

## Presentación y reutilización

Android muestra tarjetas también en tabletas anchas. Windows mantiene la
matriz y reutiliza las tarjetas como alternativa estrecha. `AnnualBudgetCards`
es una composición sin acceso a persistencia: recibe las filas de
`AnnualBudgetQuery` y los constructores de celdas/categorías/totales compartidos.
No se incorporan servicios, reglas financieras ni una propuesta nueva.

Las raíces empiezan contraídas y permiten desplegar los tres niveles. Cada
tarjeta identifica su ruta, total anual de solo lectura, mes enfocado EP-016
y **Los doce meses**, de enero a diciembre. Las cifras distinguen partida
propia, subtotal, ausencia y cero registrado; un agregado neto cero conserva
sus partidas. Los totales mensuales siguen sumando únicamente raíces.

Partida propia y ausencia abren el formulario EP-011 con mes/categoría/UUID
según corresponda. El detalle existente ofrece **Editar** y conserva importe
y metadatos históricos. Subtotales y totales abren el desglose EP-019 mediante
los callbacks MA-TSK-170. Vaciar nunca borra; **Eliminar partida** exige la
confirmación existente. Un conflicto padre/descendiente conserva el borrador
y rechaza la escritura. Las partidas archivadas pueden corregirse; sus
ausencias no ofrecen alta y las nuevas asignaciones usan categorías activas.

## Estado y retorno

El contexto conserva año, mes enfocado, ramas, posición y foco. Se añade el
filtro opcional `meses` a `BudgetOrigin`: UUID separados por coma de las
categorías con **Los doce meses** abierto. Usa la misma validación UUID que
`abiertas`, sin trasladar listas arbitrarias al token de foco acotado a 256
caracteres. Se admite en las rutas de presupuesto; los orígenes de Estado
mantienen su contrato. No cambia cálculos ni repositorios.

Las tarjetas restauran los despliegues después de relecturas y reconstrucciones
sin pila. Volver de formulario/desglose relee cifras y restaura el foco del
control que abrió el destino. Las lecturas conservan la generación de petición
compartida: carga/error ocultan cifras y una respuesta tardía del año anterior
no sustituye el año actual. Atrás usa la protección de borradores EP-011.

## Verificación

`test/budget/annual_budget_android_test.dart` añade **11 pruebas** con SQLite
de archivo y datos sintéticos. Comprueban Android a 320/840/1440 px con texto
200 %, tres niveles/ruta/doce meses ordenados, formularios, cero/vacío,
borrado confirmado/cancelado, neto cero, archivo, conflictos, fallo de escritura
y reintento, mes enfocado octubre, Atrás con descarte/cancelación, conservación
de scroll/foco, reconstrucción sin pila y lectura tardía/error/reintento.
La prueba de matriz declara Windows explícitamente para separar las plataformas.

Capturas opcionales: establecer `ANNUAL_ANDROID_VISUAL_QA=1` y ejecutar
`flutter test --no-pub --concurrency=1 test/budget/annual_budget_android_test.dart`.
Se cargan fuentes locales solo en el comprobador y se guardan imágenes
ignoradas en `.tools/ma-tsk-169-*-200.png`. Se revisaron las tarjetas y el
formulario a 320 px/texto 200 %; no presentan desbordamientos Flutter.

La evidencia de calidad y compilaciones queda en `.tools/ma-tsk-169-*`,
con el SDK y lockfile fijados. No se acredita un recorrido E2E en dispositivo
Android ni uso de lector de pantalla; Atrás se comprueba por el mecanismo de
navegación del binding Flutter. No había dispositivo Android conectado.

La primera batería completa registró 1.615 aprobadas y tres fallos ajenos al
módulo anual: timeout de 30 s en recuperación, fallo consecutivo de su conexión
y lectura de pendientes de una foto patrimonial. Coincidió con compilaciones
simultáneas. Se repitió el script completo sin builds simultáneos, con un wrapper
local de Flutter que limita la concurrencia a cuatro y fija el timeout por
defecto a dos minutos; no modifica aserciones, tests ajenos ni el script.
La compilación Android definitiva usa la configuración Flutter aislada en
`.tools/ma-tsk-169-flutter-config` y JDK Temurin 17 confirmado con doctor,
mediante `APPDATA`/`JAVA_HOME` solo del proceso. Windows release y APK debug
usan `--no-pub --dart-define=APP_ENV=test`.

Formato de 368 archivos y análisis sin incidencias pasan. La repetición completa
termina con **1.617 aprobadas y un fallo** en `account_screens_test.dart`
(aviso «Ficha guardada» ausente); los tres casos de la primera ejecución pasan.
El archivo de fichas, que no usa la pantalla anual, pasa sus **cuatro pruebas**
en ejecución aislada con concurrencia uno. Se conservan ambos resultados:
el script global no se declara exitoso. Los logs son
`ma-tsk-169-quality-final.log` y `ma-tsk-169-account-isolated.log`.
Las cuatro variantes development/test/production/invalid-synthetic pasan por
separado después de esa repetición. Las 11 pruebas Android y las 18 de matriz
Windows pasan; las capturas finales de 320 y 840 px fueron revisadas.
Windows release y APK debug con JDK 17 pasan, con evidencia en
`ma-tsk-169-build-windows.log` y `ma-tsk-169-build-android-jdk17.log`.

La entrega usa la rama configurada `ticket/ma-tsk-113` y `origin`, únicamente
archivos propios. README, sincronización y prototipos de otras épicas ya estaban
modificados y se excluyen. La calidad del checkout incluye dependencias de
Drive ajenas aún sin confirmar; no acredita una clonación limpia hasta que su
ticket las publique. Este ticket no cierra EP-021 ni la verificación E2E MA-TSK-172.
