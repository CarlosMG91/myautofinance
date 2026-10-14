# MA-TSK-175 · Real anual · suplemento v1

Propuesta del 2026-10-14, **pendiente de aprobación humana específica**.
No completa MA-TSK-175 ni inicia interfaces o tickets posteriores.

Artefacto autónomo: [mockup-real-anual.html](mockup-real-anual.html).
Publicación: `/mockups/autofinance-ma-tsk-175-v1.html` en Epic Board.
SHA-256: `26b63f59f8a03445e28c0608af7744c6453c2c21128c789d65c469556fa3d054`.

## Referencia y alcance

Consultados MA-TSK-175 y MA-TSK-207 mediante `GET http://localhost:4310/api/data`.
T04 figura completado, con `approvedAt=2026-10-12T14:56:25.247Z` y discusión
del usuario: «Propuesta visual aceptada: /mockups/autofinance-integral-v1.html».
El hash de su HTML conservado coincide con [su aprobación](../ep-026/prototipo/aprobacion.md).
Este suplemento deriva de ese HTML y reutiliza fuentes, tokens, shell, gráfico,
estados y formulario de movimientos. No cambia el artefacto aprobado ni el kit
Flutter. EP-001 §2/§5.4 y [consulta-anual.md](consulta-anual.md) conservan el
contrato financiero. Las funciones JS son simulaciones de presentación, nunca
servicios para producción.

La aprobación global cubre la referencia visual, pero no se extiende a estas
variantes sin revisión explícita: expansión independiente por nivel, persistencia
de los doce meses abiertos, foco y desplazamiento al volver, y la muestra conjunta
de histórico archivado, directos y transferencia con neto cero.

## Recorrido de revisión

1. Entrada Real anual: resultado **+2.716,65 €**, enero **+1.666,75 €**,
   febrero **+1.099,90 €**, diciembre **−50,00 €**. El gráfico y la lista mensual
   usan los mismos importes. Cambiar mes no reduce el informe al mes enfocado.
2. Ver detalle: raíces contraídas, doce meses y total anual; desplazar horizontal
   y verticalmente la región de tabla con cabecera/categoría persistentes.
3. Desplegar Alimentación y luego Supermercado: aparecen tres niveles. Enero
   contiene −12,00 € directos en Alimentación, +2,00 € directos en Supermercado
   y movimientos en Compra semanal. Los padres incluyen cada registro una vez.
   «Solo directos» y las cifras agregadas abren ámbitos distintos.
4. Abrir Ahorro enero **0,00 €**: dos piernas −500,00/+500,00 €, en cuentas
   distintas. Salud enero cero abre lista vacía. Sin clasificar enero **+4,00 €**
   abre sus dos registros de referencia nula. Transporte/Abono antiguo y Ocio
   muestran histórico archivado.
5. En Android, abrir los doce meses de cualquier tarjeta y una cifra. Volver
   conserva mes enfocado, ramas, meses abiertos y foco. En Windows conserva
   también desplazamiento de matriz. Expansionar no abre registros.
6. Añadir movimiento abre el formulario heredado EP-026/EP-010; guardar/editar
   simula datos en memoria y volver recupera el informe. Los borradores siguen
   el diálogo existente Seguir editando/Descartar.
7. Abrir la franja de revisión para carga/vacío/error, escenario de referencia
   EP-001 y texto 200 %. Tab/Enter, Escape, Alt+Izquierda y Volver permiten
   recorrer los destinos y regresar. No hay editor de celda, presupuesto,
   porcentajes nuevos ni filtro de cuenta en Real anual. La lista de origen
   conserva los controles existentes de Movimientos.

## Cobertura y evidencia

| Criterio | Evidencia del suplemento |
| --- | --- |
| Resumen y gráfica mensual firmada | Captura resumen Windows; mismo dataset y lista equivalente accesible |
| Matriz PC doce meses + anual | 14 columnas; región con scroll y cabecera/primera columna sticky |
| Tarjetas Android / mes enfocado | Total, doce meses desplegables en cada grupo, Sin clasificar y total general |
| Raíces contraídas / tres niveles | Expansión por nodo separada de sus cifras; pruebas de ambos niveles |
| Histórico / nulo / cero / EUR | Archivo en raíz y descendiente, raíz activa vacía, cero con dos registros |
| Celdas y totales → origen | Mes/rama, directos, año y total general; lista vacía también navegable |
| Añadir / estados / retorno / foco | Formulario existente, estados heredados; restauración probada en PC y tarjetas |
| Texto 200 % / 320 px / teclado | Cinco anchos sin desbordamiento de página; captura 320 px a 200 %; foco restaurado |
| Android Back | Recorrido representado por Volver/Escape/Alt+Izquierda; Back del sistema pendiente en app nativa |
| Aprobación explícita | Pendiente; no se infiere de T04 ni de verificaciones automáticas |

Capturas en [capturas](capturas/) de **HTML en Chrome headless**, no runner
Flutter, goldens ni app Android: resumen Windows, detalle Windows, Android
412 px y texto 200 % a 320 px. Inspección visual de las capturas realizada.

Comandos ejecutados correctamente:

```powershell
node docs/ep-022/generar-mockup.mjs
node docs/ep-022/generar-mockup.mjs --check
node docs/ep-022/verificar-mockup.mjs
git diff --check -- docs/ep-022
```

Verificador: referencia F (+1.229,75/+1.099,90/anual +2.329,65), muestra
completa, expansión de tres niveles, archivo/null, cero con datos y lista vacía,
18 registros en el origen anual, formulario, estados, retorno/foco/scroll,
320/360/412/1024/1440 px, 200 % y ausencia de errores JavaScript.
El generador comprueba reproducción exacta sin tocar fuentes globales.

No se modificó código Flutter, SDK o lockfile; análisis, pruebas Flutter y builds
no se ejecutaron para este suplemento HTML. TalkBack/Narrador, Back Android,
escalado y foco nativos, enlaces reales, SQLite y persistencia requieren las
interfaces e integración de sus tickets propietarios. La consulta MA-TSK-174
no se duplica ni espera la aprobación de este mockup.

Para aprobar, registrar aceptación explícita de **MA-TSK-175 · suplemento v1**
y su ruta pública. Hasta entonces el ticket conserva pendiente su aprobación.
