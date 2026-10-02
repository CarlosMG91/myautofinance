# MA-TSK-051 · Casos de aceptación del contrato local

Fuente normativa: [contrato v1](contrato-copias-locales.md). Todos los IDs,
fechas, bytes y bases de futuros fixtures son sintéticos. Estas son obligaciones
para los tickets de implementación; la revisión documental no acredita haber
ejecutado restauraciones ni interrupciones reales de EP-006.

## Trazabilidad de los criterios

| Criterio de MA-TSK-051 | Definición en contrato | Verificación posterior |
|---|---|---|
| Formato, nombres, rutas, metadatos y estados | Artefacto y ubicación; Serialización; Catálogo | MA-TSK-052/053/054 |
| Manual frente a automática, local frente a Drive | `origin`, `restoreOperationId`; Retención; tabla de versiones | MA-TSK-053/056 |
| Leer sin abrir activa | Catálogo independiente; reconstrucción desde manifiestos | MA-TSK-053/058 |
| Detectar incompletos y recuperar escritura | Publicación; dos slots, sobres, intenciones y bajas | MA-TSK-052/053/056 |
| Nunca podar manual ni única válida | Retención, superviviente revalidada y baja duradera | MA-TSK-053/059 |
| Reutilizar MA-TSK-038 | Una llamada a `LocalBackupSource` por captura | MA-TSK-052/059 |

## Captura, lectura y validación

| Caso | Preparación y acción | Resultado exigido |
|---|---|---|
| C01 · WAL y carrera | Capturar revisión 12 con WAL pendiente; confirmar edición 13 después | La imagen conserva datos/revisión 12 coherentes y manifiesto propio; activa 13. Una llamada a la primitiva, sin copiar archivo vivo |
| C02 · Activa ilegible | Catálogo válido y activa corrupta; listar | Fecha, origen, tamaño y última validación disponibles sin `open()` ni creación de otra activa |
| C03 · Manuales iguales | Crear dos manuales con idéntico hash | Dos IDs conservados; no deduplicación ni retención |
| C04 · Truncado o cambio | Cortar SQLite o alterar bytes manteniendo longitud | `sizeMismatch` o `hashMismatch`; no disponible para restaurar, activa intacta |
| C05 · Metadatos falsos | Hash de sobre correcto pero ID/ruta/revisión no coinciden con copia | Rechazo por metadatos/estructura; no modificar activa |
| C06 · Validación integral | Hash correcto, pero FK o regla financiera rota; producto ajeno | `foreignKeyFailure`, `financialRuleFailure` o `foreignFormat`; hash no basta |
| C07 · Versiones | Candidata v5 soportada, v7 futura, v0 sintética o formato JSON futuro | v5 migra solo trabajo y vuelve a validar; originales intactos. Las demás se conservan incompatibles, sin downgrade |
| C08 · Rutas | Descriptor con ruta absoluta/`..`, enlace o UUID distinto del directorio | No se sigue ni borra fuera de la raíz privada |
| C09 · I/O | Denegar lectura del catálogo o la copia | `unavailable`, nunca `empty`/corrupción supuesta ni creación de base nueva |
| C10 · Precisión | Revisión `9007199254740993`; orden `10` frente a `9` | Cadena decimal sin redondeo; comparación entera, no lexicográfica |
| C11 · Registro antiguo | Estado `valid` persistido, bytes modificados después | Mostrar fecha de comprobación; revalidación rechaza antes de restaurar/podar |

## Interrupciones de publicación y catálogo

En cada punto reiniciar con un propietario nuevo, no solo capturar una excepción.
No se abre la activa para reconstruir el catálogo. Conservar bytes anteriores;
el servicio no anuncia éxito antes de registro duradero.

| Punto de interrupción | Resultado exigido al reiniciar |
|---|---|
| P01 · Intent confirmado, snapshot no terminado | Intención/incompleto conservado, origen conocido; ninguna copia disponible nueva |
| P02 · Snapshot terminado antes de receipt | Huérfano protegido de origen desconocido; no inferir que es automático |
| P03 · `.part` o manifiesto incompleto | Incidencia incompleta; no promoción por nombre, extensión o tamaño |
| P04 · Directorio final completo antes del catálogo | Reconciliar manifiesto verificado sin baja y registrar `pending`; validar antes del uso |
| P05 · `.next` truncado, antes de reemplazar slot antiguo | Catálogo confirmado anterior intacto; no adoptar `.next` |
| P06 · Slot nuevo válido, antes de limpiar temporales | Elegir generación mayor; una entrada por ID; limpieza posterior solo de temporales propios identificados |
| P07 · Un slot corrupto | Usar el válido, reconciliar y reparar con nueva generación, sin borrar copias |
| P08 · Ambos slots corruptos | Reconstruir manifiestos y bajas, entradas `pending`, epoch nuevo y contraste requerido; no fingir vacío |
| P09 · Igual generación, contenido distinto | Conflicto y reconstrucción; no elegir por reloj ni autorizar poda |
| P10 · Slot futuro o inaccesible | Preservar, informar incompatibilidad/I/O; no sobrescribir desde el slot viejo |
| P11 · Baja durable antes de borrar SQLite | `deletionPending`; no resucitar la copia al leer un slot viejo o escanear |
| P12 · Baja corrupta o fallo de borrado | Cuarentena/aviso y conservación; no autorizar nuevos borrados |
| P13 · Dos procesos | Un propietario; segundo obtiene operación en curso; tras muerte se libera exclusión nativa |

## Retención y restauración

`A1…A4` son automáticas válidas por orden de creación, `M1/M2` manuales.
Las copias de intentos fallidos permanecen hasta una restauración satisfactoria.

| Caso | Catálogo y evento | Resultado exigido |
|---|---|---|
| R01 · Cuarta restauración satisfactoria | A1, A2, A3, M1, M2; crear A4 y confirmar restauración | Conservar A2, A3, A4, M1, M2; baja durable únicamente A1 |
| R02 · Cuarta fallida | Mismo inicio; crear A4, fallo antes/después del intercambio | Conservar A1–A4, M1, M2; ninguna poda |
| R03 · Cancelación | Cancelar antes de confirmar restauración | Activa, archivos y catálogo intactos; no crear respaldo por cancelar |
| R04 · Exceso acumulado | A1–A5 tras fallos; A6 protege siguiente éxito | Conservar A4–A6 y todas las manuales, si las comprobaciones permiten podar |
| R05 · Única válida | A1 válida y tres automáticas dañadas | Conservar A1 y dañadas; no contar dañadas como supervivientes ni completar cuota borrando |
| R06 · Manual antigua | M1 más antigua que todas las automáticas | M1 nunca participa en poda automática, incluso con disco lleno |
| R07 · Datos ambiguos | Falta origen u orden, huérfano, formato futuro, error de lectura | Conservar; suspender poda hasta resolver, sin suponer automática |
| R08 · Reloj atrasado | A4 tiene fecha anterior a A3 pero orden mayor | Retención elige por orden; listado conserva su orden de presentación documentado |
| R09 · Baja expresa | Borrar M1 con otra copia válida o siendo la única válida | Primer caso: baja duradera de ese ID; segundo: bloqueo hasta disponer de otra verificada |
| R10 · Activa corrupta | Elegir candidata válida y confirmar | Aislar activa y sidecars originales; no inventar respaldo válido ni podar esos originales |
| R11 · Igual revisión | Restaurar otra copia con mismo linaje y revisión | Nuevo epoch y contraste pendiente; no presumir igualdad con Drive |
| R12 · Reinicio del intercambio | Interrumpir staging/cierre/intercambio/reapertura | MA-TSK-056 finaliza o revierte antes de abrir; respaldo protegido, señal coherente; no red |
| R13 · Espacio insuficiente | Falla creación, flush, cierre o persistencia del catálogo | Activa y copias anteriores conservadas; no éxito, no poda de manuales para continuar |

## Evidencia de MA-TSK-051 · 2026-10-02

- SDK local `.tools/flutter`: Flutter 3.47.0 y Dart 3.13.0 comprobados con
  `flutter --version` y `scripts/check-toolchain.ps1`, sin actualizar SDK.
- `flutter pub get --enforce-lockfile`: correcto, lockfile y dependencias sin
  cambios. El primer intento falló por bloqueo de red del sandbox a pub.dev;
  el verificador completo funcionó con permisos revisados.
- `scripts/check-quality.ps1`: 78 archivos sin cambios de formato, análisis sin
  incidencias, **448 pruebas correctas** y las cuatro variantes adicionales de
  arranque `APP_ENV` correctas. La advertencia previa de Drift sobre instancias
  múltiples aparece en la prueba integrada; no causó fallos ni se cambió ese módulo.
- Comprobación Node puntual: tres ejemplos JSON parseables, checksum exacto del
  sobre, campos del manifiesto, AFNC, UUID, fechas, contadores int64 y catálogo
  inicial; 34 enlaces locales existentes entre los dos documentos y README.
  Se comprobó la presencia de los 37 casos C/P/R y se revisó su trazabilidad;
  **no se ejecutaron como pruebas de un servicio de copias locales**.
- `node docs/ep-001/verificar-casos.mjs`: cifras y reglas de referencia intactas.
- `git diff --check`: sin errores. Solo README y los dos documentos de EP-006
  pertenecen a esta entrega; no se modifican puertos, esquema, plataformas o SDK.

Los casos C/P/R quedan para MA-TSK-052–059. No se ejecutan builds ni pruebas en
dispositivos porque este ticket entrega documentación de contrato, sin cambios
de plataforma. La resistencia a interrupciones y la persistencia del adaptador
Windows/Android deberán demostrarse en esos tickets. No se ha cambiado el estado
administrativo de Epic Board ni se ha contactado Drive.
