# MA-TSK-255 · Expediente de entrega privada

Revisión: **2026-10-21**. **T09 bloqueado; candidato final no consolidado.**
Este expediente prepara una revisión reproducible. No acredita entrega efectiva,
aceptación visual, uso físico ni Google real. T10/MA-TSK-256 y EP-030 permanecen
pendientes de decisión humana sobre paquetes identificados y criterios cumplidos.

## Identidad y documentos de revisión

Fuente de partida: `8c0c8981fbe1369954085ecd8973727f88635de8` (véase
[evidencia-entrega.json](evidencia-entrega.json)), rama configurada
`ticket/ma-tsk-193`, seguimiento `origin/ticket/ma-tsk-193`. Versión fuente
`0.1.0+1`; Flutter 3.47.0, Dart 3.13.0; SQLite application_id `0x41464e43`,
esquema 8. Estas identidades de fuente **no identifican un EXE/APK instalado**.

Consultado Epic Board por `GET http://localhost:4310/api/data`, tablero
**My autofinance**, workspace coincidente: leídos EP-030, T09 y sus criterios,
T10, requisitos y entregas propietarias. 247/250–254 y 202/217/226/235/245
figuran `done`; T09 `in-progress`, T10 `ready`. La evidencia efectiva siguiente
prevalece sobre esos estados. No se modifican tickets ni se registra aprobación.
No hay adjuntos ni ruta privada alternativa en el ticket.

Orden de revisión:

1. [Matriz T01 y actualización T09](auditoria-cobertura.md#actualización-t09--2026-10-21):
   25 criterios obligatorios, con resultado y límite actual.
2. [Manifiesto común](manifiesto-entrega.json): estado bloqueado, identidades
   finales nulas, compatibilidad fuente y referencias a generadores propietarios.
3. [Evidencia estructurada](evidencia-entrega.json): fecha, commit documental,
   SHA-256 de cada fuente leída y verificaciones nuevas, sin binarios ni secretos.
4. [Guía cotidiana](guia-cotidiana.md) y [único recorrido humano](recorrido-aceptacion.md).

## Contraste de entregas obligatorias

Las fechas son las de los informes originales; sus commits documentales y hashes
están en el JSON. No se asigna su versión fuente al candidato final ausente.

| Entrega / fecha | Evidencia efectiva reutilizable | Límite que conserva T09 |
|---|---|---|
| EP-025 / 202 · 2026-10-16 | [Diagnóstico](../ep-025/verificacion-recorrido.md): 93 dirigidas, siete hitos de runner Windows/Android emulador; lectura sin reparación | No paquete production físico ni calidad global aprobada; no aceptación visual |
| EP-026 / 217 · 2026-10-14 | [Validación](../ep-026/validacion-integral.md): 120 capturas de contenido Flutter runner con viewport forzado | Revisión parcial antigua; Real/Indicadores/diagnóstico ya existen. `approvedAt` y `discussion` de 217 nulos en consulta actual. Falta aceptación visual humana vigente y accesibilidad física; aprobación HTML 207 no la sustituye |
| EP-027 / 226 · 2026-10-17 | [Portabilidad](../ep-027/verificacion-portabilidad.md): exportación nativa runner Windows debug/emulador API 37, SQLite independiente. [T08](verificacion-portabilidad.md) relee 16 ZIP con hashes coincidentes | No exportación desde las dos instalaciones finales. Límite int64 de agregación extrema documentado; no convertir a REAL |
| EP-028 / 235 · 2026-10-18 | [E2E Windows](../ep-028/verificacion-e2e.md): preparación y límites de fixtures/CI | Sin instalador production ni recorrido cliente limpio, actualización y conservación efectivos |
| EP-029 / 245 · 2026-10-20 | [Final Android](../ep-029/verificacion-final-245.md): 17 casos de host y APK técnico de firma identificado | Sin APK final/teléfono/Google real; apertura de almacenamiento y actualización nativa pendientes. APK técnico no es candidato |
| EP-014 / 131 · 2026-10-18 | [Openbank](../ep-014/verificacion-reapertura-131.md): invariancia patrimonial del contrato sintético | Sin muestra caracterizada, lector/adaptador ni recorrido Openbank real. No se inventa fixture ni otro importador |

## Resultados conjuntos y bloqueos para continuar

| Salida | Resultado verificable | Pendiente obligatorio / propietario |
|---|---|---|
| [T02 datos](datos-sinteticos.md) | Oráculos y entradas sintéticas identificados; [verificación](verificacion-datos.md) y hashes | Fixture Openbank caracterizado: EP-014/131 |
| [T03 OAuth Windows](oauth-windows.md) | Scope `drive.file`; configuración pública comprobable | Proyecto/clientes/API/tester/sesión real: 249 y Android 239; mismo proyecto compatible |
| [T04 Windows](verificacion-windows.md) | I01 del guion corregida y dos variantes host pasan | Paquete production, perfil Windows aislado y recorrido físico: EP-028/235, después 250 |
| [T05 Android](verificacion-android.md) | APK técnico inspeccionado, pruebas de host delimitadas | APK final, teléfono y apertura/actualización: EP-029/243/245, después 251; antecedente de rutas enlazadas sin resolver |
| [T06 Drive](verificacion-drive-real.md) | 61 dirigidas host con proveedor simulado y 4 arranques | Todos S00–S10 reales pendientes: OAuth, paquetes/dispositivos y Openbank; 252 |
| [T07 fallos](verificacion-fallos-recuperacion.md) | 31 dirigidas y un runner Windows debug; seis casos nuevos conservan ambas imágenes sintéticas | Red/Google y recuperación con ambos paquetes finales pendientes: 253 |
| [T08 independiente](verificacion-portabilidad.md) | 57 dirigidas, 16 ZIP históricos releídos y guía SQL sobre ambas copias base | Nuevas exportaciones de paquetes finales y traslado normal desde teléfono: 254 |
| Fuentes concurrentes | HEAD consume fuentes Drive modificadas/no publicadas de EP-007/064 | Publicación por su propietario antes de generar. No incorporarlas en T09 |
| Calidad global | T06/T08: 2026 correctas / 3 fallidas; T07: 2027 / 2 | Recuperación EP-006/059 y foto EP-017, coordinación 253/026. Pasadas aisladas no borran fallos generales ni establecen causa |

En `dist-private/windows` se localizaron únicamente compiler-probe y fixtures
synthetic; en Android ci-fixture y signing-check. No se han recibido candidatos
alternativos. No se inspeccionan instalaciones ni sesiones personales. Los
antecedentes de dispositivo/emulador son los de T04–T08: T09 no repite inventarios
ni afirma uso físico nuevo. Se solicitaron rutas/entornos de ensayo al usuario;
la falta de respuesta no acredita disponibilidad ni aprobación.

## Congelar y renovar el candidato

Cuando los propietarios levanten los bloqueos, generar desde fuentes propias
confirmadas, publicadas y limpias con las automatizaciones de
[Windows](../ep-028/generacion-privada.md) y
[Android](../ep-029/generador-apk.md). No modificar SDK, lockfile o esquema para
sortear controles. Guardar instalador, payload/EXE, APK, manifiestos y versiones
anteriores por el canal privado, **fuera del repositorio**; las carpetas ignoradas
de ensayo no son un canal de entrega. Custodia de firma:
[EP-029](../ep-029/firma-distribucion.md).

Completar el manifiesto común desde los manifiestos propietarios verificados:
commit completo del código construido, versión por plataforma, production,
configuración pública, SHA-256/tamaño de Setup/EXE/APK y manifiestos, certificado
público Android, compatibilidad SQLite y referencia privada mediante alias.
Registrar por prueba UTC, plataforma/SO/modelo, paquete/hash, dataset/revisión,
proveedor, esperado/observado y capturas saneadas con hash/origen. Sesión,
credenciales, rutas y estado Drive son locales a cada instalación; no deben
coincidir ni se transportan. Tampoco se exigen binarios iguales entre plataformas.

Una corrección o configuración que cambie el artefacto exige regeneración por
su propietario, nuevos hashes y revisión de aplicabilidad fila por fila. Repetir
lo afectado y el tramo crítico importar → categorizar → presupuestar → consultar
→ Windows→Android→Windows → recuperar → exportar/SQLite. Reutilizar evidencia
solo cuando identifique ese mismo candidato y alcance. Cambios meramente
documentales no obligan a reconstruir; no reutilizar pruebas de un overlay como
prueba de un checkout limpio. Conservar fallos y resultados anteriores separados.

La divergencia observable debe bloquear la subida. Se conserva la excepción
aceptada de carrera sobre un único archivo: última escritura e historial sujeto
a purga, sin exigir comparación condicional atómica ni fusión automática.

## Comprobaciones T09

Resultados nuevos y hashes en [evidencia-entrega.json](evidencia-entrega.json).
Se ejecuta `scripts/check-quality.ps1` y los verificadores EP-001/T02/OAuth;
los controles OAuth bloqueados no cuentan como acceso real. Se comprueban JSON,
enlaces locales, 25 filas únicas, correspondencia de hashes y whitespace propio.
Sin cambios de producto, pruebas, UI, dependencias o configuración propios,
no se generan nuevos builds que pudieran confundirse con entregas finales.

El primer intento de calidad se detuvo en pub.dev con SocketException 10057,
antes de análisis/pruebas. El reintento autorizado resuelve estrictamente el
lockfile, comprueba formato de 508 archivos sin cambios y termina análisis sin
incidencias (124,5 s). Las pruebas usan el checkout con overlay concurrente y
SQLite temporal del host, sin identificar un candidato limpio ni físico.

En la suite general se reproducen dos casos de
`test/synchronization/local_recovery_journey_test.dart`: restauración EP-001
tras reinicios (timeout 30 s y cierre bloqueado por recuperación pendiente) y
fallo de disco (esperado `rolledBack`, observado `recoveryRequired`, además de
temporal ocupado errno 32 al limpiar). Son los mismos casos ya publicados por
T01/T06–T08, con detalles de error propios de esta ejecución. Las comparaciones
de referencia T01 y pasadas aisladas T07/T08 se conservan, sin atribuir causa
definitiva ni declarar corregida la incidencia. Corresponde contrastar y resolver
I02 con EP-006/059 y T07/253 antes de aprobar calidad/candidato. No se cambian
timeouts, validaciones o motores para sortearla. El resultado total final y
las variantes de arranque se detallan en la evidencia estructurada.

Resultado final de la batería T09: **2027 correctas / 2 fallidas, 17 min 24 s**;
calidad global **no aprobada**. El test de foto de T08 no falla en esta pasada;
no se considera corregido por ello. EP-001 y preparación T02 terminan con
salida 0; los dos controles OAuth específicos terminan con salida 1 por falta
de proyecto Google acreditado. Los arranques se ejecutan aparte porque calidad
se detiene antes de ellos: **4/4 correctos**, development/test/production e
invalid-synthetic. No se repite la batería ni las suites aisladas que
T07/T08 ya contrastaron sobre estas mismas fuentes sin una nueva hipótesis.

T09 no cierra hasta resolver todos los criterios obligatorios. T10 se propone
como una sola revisión mediante el recorrido enlazado, cuando estén disponibles
los paquetes y resultados. Su decisión explícita debe identificar fecha,
versiones/hashes y alcance; aún no existe ni se solicita aprobar esta preparación
como una entrega terminada.
