# MA-TSK-108 · Revisión e historial de importación · v1

Fecha: 2026-10-07. **Pendiente de aprobación humana explícita.**

Artefacto autónomo retenido: [mockup-importacion.html](mockup-importacion.html).
En Epic Board: <http://localhost:4310/mockups/autofinance-ma-tsk-108-v1.html>.
El servidor local de Epic Board debe estar activo. Recargar restablece la simulación.

Se consultaron MA-EPIC-106 y sus tickets mediante `GET /api/data` en el tablero
**My autofinance**, con workspace coincidente. MA-TSK-107 está entregado;
MA-TSK-108 estaba en curso. Este artefacto no registra aprobación ni completa
el ticket. No implementa MA-TSK-109/110/111/112/113/114 ni lectores EP-013/014.

## Fuentes y propuesta

Amplía [entrega aprobada EP-002](../ep-002/entrega-flutter.md),
[sistema visual](../ep-002/sistema-visual.md) y
[flujos críticos](../ep-002/flujos-criticos.md), aplicando
[EP-001](../ep-001/especificacion.md),
[contrato CSV](../ep-001/contrato-csv.md),
[casos de referencia](../ep-001/casos-referencia.md) y
[contrato común v1](contrato-importacion.md). No modifica esos contratos,
los servicios Flutter, SQLite ni el adaptador sintético integrado de MA-TSK-113.

Conserva paleta, fuentes del sistema, cinco destinos y Gestión como acceso
secundario. En PC hay tabla compacta; por debajo de 840 px o en el selector
Android hay tarjetas etiquetadas. Controles móviles de al menos 48 px, foco
visible, diálogos con título accesible y mensajes que no dependen del color.
Texto al 200 % cambia a tarjetas para conservar rutas, importes y mensajes.
La propuesta no añade un sexto destino principal.

Cada fila muestra ordinal, REAL/PRESUPUESTO, fecha de valor o mes, concepto,
importe original, representación textual e importe interno, ruta, cuenta,
estado y originales. Conteos y totales se separan por tipo; los presupuestos
históricos invierten el signo una vez y el cero sigue siendo partida explícita.
La fila inválida se identifica en el bloque de errores, sin fingir que está
interpretada ni omitirla silenciosamente. Un error de fila, referencia pendiente,
lote vacío o conflicto jerárquico bloquea la confirmación completa.

Las cuentas REAL son obligatorias. Se vinculan referencias a todas sus filas;
los presupuestos no tienen cuenta. REAL admite Sin clasificar, que no crea nodo;
presupuesto requiere categoría. La referencia ambigua muestra rutas e identidades.
La creación de cuenta/categoría queda preparada en la sesión: se crea junto al lote,
nunca al abrir o cerrar el selector. Una raíz nueva exige elegir Ingreso/No ingreso;
un hijo hereda la marca. El selector sintético representa solo padres de primer
nivel; el selector completo de hasta tres niveles corresponde a la implementación.
Cambiar una vinculación elimina su alta preparada anterior e invalida revisiones.

Cada solapamiento compara cuenta, fecha de valor, importe y concepto normalizado
con un registro de otro archivo. Exige revisión expresa por ordinal y conserva
ambos registros. No hay eliminación automática. Cambiar de cuenta recalcula los
avisos: otra cuenta no coincide. Las filas Café 2 y 3 permanecen separadas.

La confirmación requiere lote válido y un consentimiento final independiente
de las marcas de solapamiento. La fase Confirmando bloquea dobles envíos y salidas
hasta resultado seguro. Error de escritura no deja altas; cambio de base exige
cuenta vigente y nueva revisión, manteniendo la sesión. Cancelar el diálogo final
vuelve a revisión; cancelar la sesión descarta sus decisiones y conserva todos los
datos confirmados. No se ofrece deshacer una importación confirmada.

El resultado enlaza lote/origen y Estado, Presupuesto y Real de enero de 2026.
El fixture tiene un solo periodo y origen Real de enero; los destinos representan
el contexto de retorno, no sus pantallas funcionales. Visitar historial durante
la revisión conserva la sesión. Salir a un destino, cargar otro escenario o Atrás
desde la revisión exige decidir entre seguir revisando y descartar. Esc cancela
el diálogo; el foco retorna al control cuando sigue disponible o al título tras
un cambio de vista. Alt+Izquierda y Atrás del navegador recorren detalle/origen,
lote, historial y revisión. Durante confirmación Atrás no abandona la operación.
El cierre/recarga utiliza el aviso nativo de sesión sin guardar.

El historial muestra únicamente lotes confirmados: nombre, fecha, origen,
versiones, huella y conteos. El detalle pagina todas las filas (dos por página
en el fixture para hacer revisable el retorno) y conserva la página al volver
de un origen. El origen distingue campos originales de registro actual;
hay ejemplos de importe corregido y registro borrado. Repetir el archivo
renombrado da Ya importado, cero altas, sin recrear ni revertir esos registros.
No hay archivo completo, intentos cancelados/fallidos guardados ni deshacer.

## Guion de revisión humana

1. Revisar PC y Android, con texto normal y 200 %. Ver fila 4 Sin clasificar,
   presupuesto −400,00 € procedente de +400,00 € y partida cero.
2. Vincular Cuenta diaria y la categoría; abrir cada Comparar y marcar revisión.
   Confirmar lote completo, consentir Importar todo y consultar el lote nuevo.
3. Preparar una nueva referencia y cancelar: comprobar que el historial no cambia.
   Crear una raíz sin marca de ingreso: se exige elegirla expresamente.
4. Preparar fallo de confirmación: el lote y las altas no aparecen; reintentar.
   Preparar cambio de base: resolver otra vez cuenta y avisos antes de confirmar.
5. Cargar Error de fila, Conflicto padre/descendiente y Lote vacío: cada caso
   impide toda la carga. Cargar otro escenario requiere descartar la sesión.
6. Cargar Mismos bytes, otro nombre y confirmar: cero altas. Consultar LOT-001,
   fila 3 borrada y fila 5 corregida; conservar página al volver.
7. Probar cancelación del diálogo, salida a otro destino, historial y Atrás.
   Aprobar explícitamente MA-TSK-108 en Epic Board o solicitar cambios allí.

## Verificación y límites

- `node docs/ep-012/verificar-mockup.mjs`: correcto. Ejecuta el script autónomo
  con un DOM mínimo simulado y verifica asignaciones, marca de raíz, revisión por
  ordinal, totales/signos/cero, rechazos completos, fallo/reintento, base cambiada,
  repetición con corrección/borrado, cancelación, paginación y doble envío.
- `node docs/ep-001/verificar-casos.mjs`: correcto; reglas financieras conservadas.
- Enlace publicado con respuesta HTTP 200; contenido cotejado con el artefacto.
- No hay navegadores ni superficies nativas conectadas en esta ejecución.
  No se acredita inspección visual, layout real a 320 px/200 %, teclado real,
  lector de pantalla ni Atrás físico de Android. Esos puntos quedan para revisión.
- No se ejecutan análisis/pruebas Flutter ni builds: no se modifica módulo Dart,
  código de plataformas o dependencias. Las pruebas son del prototipo HTML.
- La persistencia y la revalidación se simulan en memoria, sin SQLite. Huellas,
  fecha de confirmación e identidades del fixture son ilustrativas; el mockup
  no calcula SHA-256 ni interpreta bytes. El núcleo real usará el contrato v1.
  Las pruebas no acreditan transacciones SQLite, concurrencia o lectores reales.

Conservar este suplemento junto al diseño aprobado. La entrega visual de
MA-TSK-108 solo se completa tras aprobación humana; la ejecución en lote y
la publicación o entrega Git no sustituyen esa aprobación.
