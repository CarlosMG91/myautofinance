# MA-TSK-125 · Lector Openbank pendiente de caracterización

**Estado: bloqueado; lector no implementado.** Comprobación del 2026-10-08.

## Evidencia del requisito previo

Se ha leído `http://localhost:4310/api/data`, tablero **My autofinance**,
épica MA-EPIC-123 y tickets MA-TSK-124/125. El tablero marca MA-TSK-124
como `done`, pero su resultado declara que está bloqueado por falta de muestra
verificable y ruta privada. La
[caracterización versionada](caracterizacion-openbank.md) confirma que no se
han leído bytes de un extracto ni observado formato físico, hojas, columnas,
fechas, signos o resultados esperados. El estado del tablero no sustituye
esa evidencia.

Las listas de adjuntos de la épica y de ambos tickets están vacías. La petición
de MA-TSK-125 tampoco proporciona una ruta privada concreta. La consulta
`git ls-files --cached --others --exclude-standard` de nombres Openbank y
extensiones XLS/XLSX solo encuentra el documento de caracterización.
Esto no demuestra que no exista una muestra fuera del checkout o en archivos
ignorados. Se ha solicitado la ruta local al usuario; no se afirma haber leído
ningún extracto.

## Condición para retomar la implementación

Se necesita la muestra original anonimizada aportada por el usuario en una
ruta accesible, con su contenedor y estructura conservados, y completar la
caracterización de MA-TSK-124. Si ya existe una caracterización externa,
debe estar disponible junto con la evidencia verificable que la sustenta.
La muestra personal permanece fuera de Git.

Solo entonces se puede elegir y verificar el lector, documentar las variantes
aceptadas y preparar fixtures sintéticos fieles. La extensión `.xls` no
identifica el contenedor ni justifica elegir una biblioteca. No se inventan
hojas, cabeceras, formatos de fecha, columnas monetarias ni reglas de signo.

El lector puro pertenecerá a `features/importing/data`, conforme a la
[guía de lectores de EP-012](../ep-012/guia-lectores.md) y al
[contrato común](../ep-012/contrato-importacion.md). Su verificación deberá
cubrir rechazo íntegro del lote, diagnóstico por hoja/fila/campo, fechas
civiles, céntimos exactos, originales y ordinales estables, incluidos reales
legítimamente idénticos. La adaptación al núcleo corresponde a MA-TSK-126;
el lector no escribe SQLite ni fotos patrimoniales.

## Verificación de esta entrega

- Flutter 3.47.0 y Dart 3.13.0 comprobados mediante `flutter --version` y
  `scripts/check-toolchain.ps1`; no se cambia SDK, dependencias ni lockfile.
- Contraste de adjuntos, resultado del requisito previo, caracterización,
  contratos EP-012 y fronteras de arquitectura de EP-003.
- Esta entrega solo registra el bloqueo. No acredita lectura de Openbank,
  resultados de fixtures ni compatibilidad del lector Windows/Android.
  No hay cambios de código que analizar o probar ni builds que verifiquen
  un lector inexistente.

MA-TSK-125 sigue pendiente hasta disponer de la evidencia anterior y cumplir
sus criterios. No se modifica el estado de los tickets en Epic Board.
