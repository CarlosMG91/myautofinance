# MA-TSK-128 · Suplemento visual Openbank · v1

Fecha: 2026-10-08. **Pendiente de aprobación humana explícita.**

Artefacto autónomo: [mockup-openbank.html](mockup-openbank.html).
En Epic Board: <http://localhost:4310/mockups/autofinance-ma-tsk-128-v1.html>.
Requiere el servidor de Epic Board activo. Recargar restablece la simulación.
Los controles del prototipo no registran aprobación ni importan datos reales.

Se consultaron MA-TSK-128, MA-EPIC-123 y el núcleo MA-EPIC-106 mediante
`GET /api/data`, tablero **My autofinance**, con workspace coincidente.
EP-012 figura entregado; su historial, confirmación y navegación se reutilizan
como base del HTML. También se respeta [EP-002](../ep-002/sistema-visual.md),
[EP-001](../ep-001/especificacion.md), el
[contrato común](../ep-012/contrato-importacion.md), la
[adaptación Openbank](adaptacion-nucleo.md) y el
[selector compartido](selector-extractos.md).

La [caracterización](caracterizacion-openbank.md) registra falta de muestra.
El estado `done` de MA-TSK-124/125 en el tablero no acredita una muestra ni
desbloquea el lector: no se han leído extractos. El suplemento puede revisarse
sin caracterización porque solo usa campos del dominio común. No se inventan
columnas, hojas, filas físicas, reglas de conversión ni identidad bancaria.

## Experiencia propuesta

- Gestión desde Real mantiene origen y enero de 2026. Un archivo por carga,
  selección local orientada a XLS, sin aceptar el formato por la extensión.
  El diálogo de selección de este mockup es una lista de escenarios sintéticos.
  Cancelar conserva la sesión previa; entregar otro archivo exige descartar
  la revisión actual antes de leer el nuevo.
- Cuatro REAL: ordinales 2/3 Café de −10,00 € cada uno, ordinal 4 compra de
  −35,25 € y ordinal 5 abono de +1.000,00 €. Total firmado **+944,75 €**.
  Todos Sin clasificar, para categorizar después desde Real. Los ordinales
  son del contrato común, no números de fila física del banco.
- Cuenta EUR elegida y confirmada con una marca explícita en cada carga.
  No hay selección automática. Cambiar cuenta invalida las revisiones previas
  y recalcula los avisos; Cuenta ahorro no coincide con el lote anterior.
- Cada Café coincide con un movimiento de otro archivo en Cuenta diaria.
  Se abre la comparación y se marca cada aviso por separado. Ambas filas
  nuevas se conservan y mantienen ordinal distinto. No hay descarte automático.
- PC usa tabla compacta; Android y texto 200 % usan tarjetas etiquetadas.
  Se mantienen cinco destinos, foco visible, botones táctiles de 48 px,
  diálogos accesibles, salto al contenido, mensajes con texto además de color
  y soporte de colores forzados. No se añade un destino principal.
- Confirmación común de todo el lote con consentimiento final independiente
  de cuenta y avisos. Confirmando bloquea acciones y salida. Fallo deja cero
  altas y conserva sesión; cuenta desactualizada exige nueva asignación y
  revisión. Cancelar antes de confirmar descarta decisiones sin borrar lotes.
- Error de lectura/acceso/documento ausente, estructura desconocida, movimiento
  inválido y lote vacío rechazan todo. Conteo y total quedan «no disponibles»;
  la implementación mostrará hoja/fila/campo solo cuando el lector los conozca.
- Resultado confirmado, historial paginado, lote, procedencia y registro actual
  reutilizan EP-012. Se muestran ejemplos de registro corregido y borrado.
  Repetición exacta reconoce SHA-256 de bytes completos aunque cambie el nombre:
  cero altas, sin recrear borrados ni revertir correcciones. La huella del
  mockup es ilustrativa; no calcula SHA-256 ni conserva archivo binario.
- Visitar historial mantiene la sesión; Atrás vuelve de origen a lote, historial
  y revisión. Salir con sesión pide descartar o seguir revisando. Volver a Real
  conserva el periodo y solo representa la navegación de retorno.
- No se importan presupuestos ni se modifican fotos patrimoniales. No se muestra
  ningún saldo bancario como actualización de foto. Las sumas son flujos REAL.

## Guion de aprobación

1. Seleccionar lote válido, revisar PC y Android y activar Texto 200 %.
2. Elegir Cuenta diaria sin marcar confirmación: comprobar bloqueo. Confirmarla,
   revisar ambos Café y confirmar el lote completo mediante consentimiento final.
3. Abrir lote, originales no caracterizados y registro actual; volver al origen.
4. Seleccionar mismos bytes renombrados: cero altas. Consultar LOT-001 con
   registro corregido y borrado; ninguno se restablece.
5. Probar todos los diagnósticos del selector: rechazo completo, sin total ficticio.
6. Cambiar cuenta, cambiar archivo y cancelar selección o descarte. Consultar
   historial durante revisión y volver; verificar conservación de la sesión.
7. Probar fallo de confirmación y cambio de base con los controles de revisión.
   Reintentar con cuenta vigente; cancelar confirmación vuelve a la revisión.
8. Aprobar explícitamente MA-TSK-128 en Epic Board o solicitar cambios.

## Verificación y límites

- `node docs/ep-014/publicar-mockup.mjs`: genera el HTML autónomo desde EP-012
  y el suplemento, sin modificar la base.
- `node docs/ep-014/verificar-mockup.mjs`: correcto. DOM simulado verifica
  selección/cancelación y cambio, todos los diagnósticos, suma exacta,
  cuenta explícita por carga, bloqueo por avisos, invalidación por cuenta,
  consentimiento final, fallo sin altas, revalidación, repetición y procedencia.
- `node docs/ep-001/verificar-casos.mjs`: correcto; contratos financieros
  conservados. Publicación HTTP 200 y contenido idéntico al artefacto retenido.
- No hay navegador ni superficies conectadas: no se acredita inspección visual,
  layout real a 320 px/200 %, teclado real, lector de pantalla o Android físico.
  Esos aspectos forman parte de la revisión humana pendiente.
- No hay cambios Dart, plataforma, dependencias o lockfile. No se ejecutan
  calidad/builds Flutter: esta entrega contiene solo prototipo y documentación.
- No se acredita lector Openbank, SQLite, selector nativo o transacción real.
  Ningún escenario simulado caracteriza XLS. No se usa código de MyFinance.

MA-TSK-128 no se completa con esta entrega. Publicación, pruebas, commit y push
no sustituyen aprobación humana. No se implementan tickets posteriores;
la aprobación visual bloquea interfaz y la muestra sigue bloqueando el lector.
