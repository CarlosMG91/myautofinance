# MA-TSK-061 · Control de versiones de Drive

Fecha: 2026-10-02. **Entrega parcial; ensayo real bloqueado por OAuth.**
Se consultó el ticket suministrado por el usuario y la copia local de Epic Board
`.tools/board-059.json` (MA-EPIC-060, MA-TSK-061 y dependencias). Es una captura,
no una consulta del estado actual; no se cambió el tablero. El checkout comenzó
limpio en `main`, con `origin` configurado para este proyecto.

## Evidencia y decisión técnica

La referencia oficial de [files.update](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/update)
describe PATCH binario con `media`, `multipart` y `resumable`, sin parámetro de
precondición por versión. [File](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
define `version` como contador de solo lectura y `headRevisionId` como ID de
revisión del contenido binario. Ninguno es por sí mismo una condición de escritura.
La ausencia de un parámetro documentado **no prueba** que el endpoint ignore
una cabecera HTTP `If-Match`. No se extrapola el comportamiento de Drive v2,
de documentos Google ni de PATCH de solo metadatos.

Decisión provisional: no atribuir atomicidad a una lectura seguida de PATCH.
Usar obligatoriamente una condición de servidor si el ensayo real demuestra
que protege el **commit binario** de la modalidad elegida. Hasta entonces la
capacidad está indeterminada, no acreditada como viable ni como imposible.
La excepción aprobada en EP-001 permite el archivo único sin prometer exclusión
atómica; no autoriza saltarse divergencias ya detectables antes de publicar.

El historial nativo no equivale a un respaldo permanente: Google explica su
purga en [gestión de revisiones](https://developers.google.com/workspace/drive/api/guides/manage-revisions).
Este ensayo no fija `keepRevisionForever` ni crea un sistema paralelo de versiones.

## Ejecutor reproducible y preparación

`scripts/probe-drive-conditional-write.mjs` usa Node **22.20.0** y `node:sqlite`
(experimental en esa versión), sin paquetes externos. Genera tres SQLite válidas
y diferentes: base, escritor A y escritor B; comprueba `PRAGMA integrity_check`
antes de usarlas y elimina sus temporales locales. Son fixtures técnicos,
no bases de Autofinance compatibles con su esquema ni datos financieros.

Preparar dos autorizaciones independientes de ensayo del mismo proyecto OAuth,
misma cuenta tester y scope `drive.file`, siguiendo EP-005. Ambas deben tener
acceso a una carpeta normal **dedicada al ensayo**, creada/abierta por ese proyecto.
No usar la carpeta ni el archivo de una instalación financiera real. No ampliar
scopes para eludir problemas de acceso. Los clientes A/B son dos contextos HTTP
con tokens diferentes; no acreditan ejecución nativa Windows/Android.

Provisionar en privado estas variables de entorno del proceso:
`AUTOFINANCE_PROBE_TOKEN_A`, `AUTOFINANCE_PROBE_TOKEN_B` y
`AUTOFINANCE_PROBE_FOLDER_ID`. No pegar secretos en chats, comandos versionados
ni dart-defines. Ejecutar explícitamente:

```powershell
node scripts/probe-drive-conditional-write.mjs --live
```

El ejecutor no recibe ID de archivo existente. Crea cuatro archivos nuevos de
ensayo con nombres `autofinance-probe-<modalidad>-<uuid>.sqlite` y marca privada
`conditionalWriteProbeV1`, distinta de la marca de producción `databaseCopyV1`.
Solo actualiza esos IDs recién creados. Los conserva en la carpeta de ensayo
para inspeccionar su historial; su limpieza manual es posterior y no está
automatizada. Esta multiplicidad de fixtures no cambia el contrato de un único
archivo activo de la aplicación.

## Peticiones y carrera controlada

Todos los endpoints pertenecen a `https://www.googleapis.com`. No se siguen
redirects; las URLs de sesión deben conservar ese origen y la ruta upload de Drive.
Se limita cada petición/lectura a 30 segundos. No hay reintentos automáticos.
Campos consultados: `id,version,modifiedTime,headRevisionId,md5Checksum`.

| Fase | Petición |
|---|---|
| Crear fixture | `POST /upload/drive/v3/files?uploadType=multipart&fields=...`; metadatos con padre de ensayo y bytes SQLite base |
| Leer base A/B | Dos `GET /drive/v3/files/F?fields=...`; exigir misma versión, checksum base y mismo ETag si existe |
| Media | `PATCH /upload/drive/v3/files/F?uploadType=media&fields=...`; bytes SQLite, `Content-Type: application/vnd.sqlite3`, `If-Match: E0` si GET entregó ETag |
| Multipart | Mismo PATCH con `uploadType=multipart`, metadatos vacíos y bytes, `multipart/related`, misma condición |
| Reanudable | PATCH con `uploadType=resumable`, `{}`, `X-Upload-Content-Type/Length` y `If-Match: E0`; PUT a Location con bytes, Content-Range completo y la misma condición |
| Verificar | GET de metadatos y GET `?alt=media`, comparar MD5 de bytes completos con metadatos y fixture esperado |
| Historial | GET `/drive/v3/files/F/revisions?fields=nextPageToken,revisions(id,md5Checksum)&pageSize=1000` |

A y B terminan sus lecturas sobre V0 **antes** de escribir. A publica primero;
B intenta publicar con el validador obsoleto, sin volver a consultar. Es una
intercalación determinista de dos operaciones que partieron de la misma base,
no un ensayo aleatorio de simultaneidad de paquetes. Prueba precisamente el
intervalo que una consulta previa no puede proteger.

En la cuarta variante, ambos abren sus sesiones reanudables sobre V0 **antes**
del PUT de A; B hace su PUT después de A. Esto distingue una condición aplicada
solo al inicio de sesión de una condición aplicada al commit final. No basta
con que el PATCH inicial rechace un validador obsoleto. Una modalidad distinta
en producción requiere acreditar también su commit; no extrapolar el resultado.

## Respuestas, interpretación y cierre pendiente

El informe JSONL registra escritor, fase, método, HTTP, versión decimal,
checksum sintético y alias de ETag/revisión. No imprime Bearer, ID de carpeta,
ID de archivo, URL de sesión, cuerpo externo ni mensajes Google. Las peticiones
concretas se reconstruyen con la tabla; E0/F son alias, no valores para reenviar.

| Resultado del ejecutor | Evidencia exigida / consecuencia |
|---|---|
| `condition_observed` | A HTTP 200, B HTTP 412, validador disponible y contenido final exactamente A. Candidata viable para esa modalidad; repetir ensayo real y exigirla en producción |
| `stale_condition_not_enforced` | A y B HTTP 200, validador obsoleto enviado y contenido final B. Esa condición no bloquea la carrera de esa modalidad; última escritura activa |
| `unconditional_last_writer` | Sin ETag utilizable del GET, ambas HTTP 200 y contenido final B. Demuestra carrera sin condición, **no** demuestra que toda condición de Drive sea imposible |
| `inconclusive` | Error HTTP/red, permisos, contenido inesperado, etc. No acredita ni soporte ni ausencia |

Si falta validador o hay un resultado indeterminado, salida 2. Si una condición
se observa o se prueba ignorada en todas las variantes, salida 0; **0 no significa
que exista protección**. Leer los cuatro resultados. La presencia de A en el
historial se registra por checksum, sin prometer lista exhaustiva ni retención
futura. No se usa `version` como ETag inventado ni como campo de comparación
del servidor. Si no hay ETag, investigar otro validador documentado antes de
concluir definitivamente que Drive no ofrece ninguna condición.

Para cierre: registrar commit probado, fecha, proyecto/clientes mediante alias,
cuatro resultados reales, códigos HTTP y verificación binaria saneada; repetir
con A/B invertidos. Elegir la modalidad acreditada para MA-TSK-063/064. Si ninguna
condición protege el commit, aplicar la excepción de carrera aceptada: última
escritura activa, anterior sujeta al historial. MA-TSK-066 debe seguir deteniendo
divergencia secuencial y resolviendo acuses inciertos; MA-TSK-069 añade el recorrido
real Windows/Android. No añadir fusión automática.

## Verificación de esta entrega

- Inventario OAuth `config/google-oauth.public.json`: `blocked_external`, clientes
  ausentes; no hay variables `AUTOFINANCE_PROBE_*` provisionadas en la sesión.
- Ensayo `--live`: salida **2**, detenido por falta de sesiones/carpeta antes de
  ninguna petición. **No existen peticiones/respuestas ni carrera reales contra
  Google para registrar. MA-TSK-061 no cumple aún su criterio empírico de cierre.**
- `node --test scripts/tests/drive-conditional-write.test.mjs`: **7 pruebas**
  correctas; clasifican rechazo real del falso, condición ignorada, validación
  solo en inicio reanudable, ausencia de ETag, SQLite sintética y omisión de
  secretos. Los resultados de servidores falsos no son resultados de Drive.
- EP-001 §7.1 y decisiones corregidos; caso I revisado: la divergencia secuencial
  sigue deteniéndose. Reglas financieras, descarga y recuperación intactas.

- `flutter --version` y `scripts/check-toolchain.ps1`: Flutter 3.47.0/Dart
  3.13.0 correctos; sin actualizar SDK ni lockfile. `check-quality.ps1` completo:
  **110 archivos Dart** sin cambios de formato, análisis sin incidencias,
  **627 pruebas** correctas y cuatro variantes adicionales de arranque correctas.
  El primer intento falló por acceso a pub.dev en el sandbox; el segundo terminó
  con permiso de ejecución ampliado. No se cambió código Flutter/plataformas;
  no se ejecutaron builds Windows/Android ni pruebas en dispositivos.
- `node docs/ep-001/verificar-casos.mjs`: OK, 48 presupuestos, 10 reales,
  enero +1.229,75 EUR, real anual +2.329,65 EUR, presupuesto +13.200,00 EUR.
- `node scripts/check-google-oauth.mjs --require-configured`: salida 1,
  bloqueo esperado por proyecto/clientes ausentes; no es evidencia OAuth.
- Sintaxis Node y `git diff --check`: correctos. Solo cambios propios del ticket,
  sin credenciales ni bases versionadas. La publicación Git se comunica después
  de comprobar el push; no equivale al cierre empírico de MA-TSK-061.
