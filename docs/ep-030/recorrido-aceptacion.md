# T10 · Recorrido único propuesto para revisión humana

Propuesta preparada en T09 el 2026-10-21. **No ejecutada ni aprobada.**
MA-TSK-256 y EP-030 quedan pendientes. El
[expediente](expediente-entrega.md) contiene los bloqueos que impiden todavía
presentar una entrega final. La revisión se realiza sobre los mismos hashes
del [manifiesto común](manifiesto-entrega.json), con datos sintéticos T02 y
entornos aislados; conserva paquetes previos y copias recuperables.

## Una sola sesión revisable

| Paso | Acción que revisamos juntos | Evidencia / resultado esperado |
|---|---|---|
| 0 | Identificar Setup/EXE/APK, manifiestos, versiones, commit, production, PC/perfil y teléfono físico; mostrar resumen de matriz y calidad | Hashes recalculados y coincidentes; ningún obligatorio pendiente. Revisar instalación/actualización acreditadas por 235/245 |
| 1 | En Windows importar BASE-T02, revisar y confirmar. Importar Openbank caracterizado según EP-014 en su variante separada | [T04](verificacion-windows.md), [T02](datos-sinteticos.md): BASE 48 partidas/10 reales, dos Café distintos; repetición sin altas y fotos intactas. No sustituir Openbank por CSV |
| 2 | Categorizar los dos pendientes V01 individualmente y en lote, cancelar una vez; editar alquiler enero −1010 y revisar propuesta 2027 cancelándola | [T06 S02](verificacion-drive-real.md): B1 con 12 reales/48 partidas, presupuesto enero +1090 y anual +13190; sin partidas 2027 nuevas |
| 3 | Registrar/revisar foto completa enero y febrero sin foto; consultar Inicio, cinco vistas, desgloses, periodos y diagnóstico; cerrar/reabrir | B1: real enero +1233,75, anual +2333,65; líquidos 9000, neto 14000 y colchón 3,00 meses; febrero sin dato. Diagnóstico no escribe |
| 4 | Revisar expresamente UI EP-026 en ambos dispositivos, resumen/detalle, teclado/Back/tacto, escala y accesibilidad según 217 | Registrar decisión visual humana **específica de 217**, capturas actuales con origen y hash; aprobación del HTML 207 no basta |
| 5 | Windows sube B1; Android revisa descarga, cancela, luego confirma; cambia alquiler a −1020 y sube B2 | [T06 S03–S05](verificacion-drive-real.md): Google real, mismo archivo, respaldo y tablas/UUID/revisión iguales tras descarga; sin acciones automáticas |
| 6 | Windows obsoleto edita a −1030; subida bloqueada por divergencia; cancela descarga, luego instala B2. Edita otra vez y sube B3; Android descarga | [T06 S06–S09](verificacion-drive-real.md): conservar imagen local obsoleta y ambas versiones; B2 presupuesto enero +1080, B3 +1070; mismas cifras reales/fotos |
| 7 | Revisar fallos reales y recuperación acreditados; demostrar cancelación y restauración de una copia anterior y vuelta a la elegida en clones de ensayo | [T07](verificacion-fallos-recuperacion.md): datos/copias conservados y sin falso éxito, nuevo contraste Drive. Respetar carrera aceptada sin exigir CAS |
| 8 | Exportar CSV completo/enero/vacío y copia SQLite desde ambos paquetes; transferir documento Android a Windows y consultar en carpetas nuevas | [T08](verificacion-portabilidad.md) y guía SQL: hashes, integridad, 12 tablas y filas/identidad/revisión de la imagen exportada; no aplicar oráculo BASE a B3 |
| 9 | Revisar guía cotidiana, conservación de versiones/copias, limitaciones y matriz final; recoger decisión | Fecha, participantes y acciones ejecutadas por usuario/agente; versiones/hashes y alcance aprobado o cambios solicitados |

El tramo Openbank y las variantes/fallos se ejecutan en clones independientes,
sin acumularlos en B1–B3. Las precondiciones y observaciones detalladas son las
de T04–T08; este guion no reemplaza sus matrices ni permite omitir casos.
Las capturas distinguen HTML, golden, host, runner, emulador, production y físico.
No capturar correos, IDs externos, consentimientos, tokens o datos personales.

## Registro de decisión pendiente

- Fecha UTC y persona que decide: **pendientes**.
- Versiones/hashes exactos de ambas plataformas y expediente revisado: **pendientes**.
- Acciones físicas del usuario y acciones del agente: **pendientes**.
- Aceptación visual EP-026/217 y su evidencia: **pendiente**.
- Decisión sobre entrega (aprobada / cambios solicitados / sin decisión): **sin decisión**.
- Alcance, limitaciones aceptadas y referencia a la respuesta humana: **pendientes**.

Una respuesta de planificación anterior o un resultado automático no completan
estos campos. Si hay cambios, T09 regenera y repite las comprobaciones afectadas
antes de presentar de nuevo el candidato. Sin respuesta o con obligatorios
bloqueados, T10 y la épica no se cierran.
