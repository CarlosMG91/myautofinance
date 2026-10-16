# MA-TSK-199 · Diagnóstico de coherencia · Propuesta v1

Propuesta del 2026-10-16, **pendiente de aprobación humana explícita**.
Artefacto: [diagnostico-v1.html](diagnostico-v1.html).
URL de revisión: <http://localhost:4310/mockups/autofinance-ma-tsk-199-v1.html>.
El ticket no se considera terminado y no se implementan MA-TSK-201/202.

## Referencias y alcance

Ticket y épica consultados en `GET http://localhost:4310/api/data`, tablero
My autofinance; MA-TSK-199 sin adjuntos ni aprobación específica. Se conserva
la aprobación global MA-TSK-207 documentada en
[EP-026](../../ep-026/prototipo/aprobacion.md), sin modificar su HTML/hash.
Se reutilizan directamente sus tokens, fuentes Roboto y CSS de componentes,
shell lateral Windows, barra inferior Android y reflujo al 200 %.
Análisis/Más y Gestión son las entradas secundarias existentes.

El suplemento completa estados e interacciones específicos de EP-025 y
requiere aprobación propia. El contrato de
[MA-TSK-197](../contrato-diagnostico.md) fija severidades, nueve reglas,
ámbitos y destinos. EP-001 conserva fórmulas, entidades y excepciones.
Los destinos del HTML son representaciones revisables de pantallas propietarias,
no nuevas implementaciones ni parsers Flutter. La integración real y su
disponibilidad al navegar pertenecen a MA-TSK-201.

## Recorrido de revisión en Windows y Android

1. Abrir Análisis (Más en Android) o Gestión → Diagnóstico. Elegir mes/año.
   No se ejecuta automáticamente. La revisión estructural abarca toda la
   base; fotos/indicador se limitan al mes elegido y su año de ingresos.
2. Ejecutar diagnóstico. Ver progreso y cancelar: la cancelación no presenta
   conformidad ni recuentos finales. Repetir inicia una ejecución explícita.
3. Revisar el ejemplo mixto: dos errores, un aviso y tres pendientes.
   Filtrar por severidad mantiene recuentos globales. Ver detalle explica
   regla, evidencia, ámbito y registro/periodo que abrirá la acción.
4. Abrir el conflicto histórico: enero de 2026 se conserva aunque el periodo
   elegido sea octubre. Abrir el movimiento sin categoría conduce a bandeja,
   la foto a su mes y la referencia inexistente al catálogo, sin ruta al ID roto.
5. En el posible duplicado abrir ambos lotes con sus filas e identidades.
   La coincidencia es solo aviso. Las filas legítimas siguen conservadas.
6. En un destino editable, pulsar «Simular cambio guardado en el editor» y
   volver. Se mantiene el filtro y se muestra «Resultado obsoleto»; repetir
   es explícito. Cambiar de mes también invalida el resultado anterior.
7. Desplegar la franja de propuesta para cambiar la próxima ejecución:
   sin hallazgos, pendientes válidos, ingresos incompletos, posible duplicado,
   regla no ejecutada, lectura fallida y obsoleto. Seleccionar el escenario
   no ejecuta controles. «Sin hallazgos» solo acompaña nueve reglas ejecutadas;
   proveedor ausente muestra ocho de nueve y «Revisión incompleta».
8. La foto incompleta y su causa prioritaria del indicador tienen destinos
   hacia la misma foto; el ejemplo separado de ingresos abre marzo del año
   elegido. No se calcula ningún indicador en JavaScript.
9. Lectura fallida: no se muestran ceros ni revisión inventada, se informa
   de las reglas no ejecutadas y se abre Recuperación local. Recuperación
   se simula sin restaurar datos reales. Recargar elimina los resultados.

No hay acciones de reparar, borrar, fusionar, exportar o consultar historial
de diagnósticos. Los cambios de la demostración solo afectan su memoria.
Las tablas no son la entrada: resumen, grupos de tarjetas y detalle explícito.

## Evidencia y comprobaciones

Comandos desde la raíz:

```powershell
node docs/ep-025/prototipo/generar.mjs --check
node --check docs/ep-025/prototipo/diagnostico.js
node docs/ep-025/prototipo/verificar.mjs
```

El verificador usa Playwright ya disponible en `.tools/ma-tsk-141-browser` y
Chrome instalado; se pueden indicar `PLAYWRIGHT_MODULE`, `CHROME_PATH` y
`MOCKUP_URL`. No se incorporan dependencias, SDK ni lockfiles al repositorio.
Sirve el HTML en un puerto efímero y cierra navegador/servidor al terminar.

Resultado: recorridos en 1440×960 y 412×915, ocho escenarios, cancelación,
filtros/retorno, destinos y periodos, cambios y repetición, resultados no
persistidos; sin errores JavaScript ni solicitudes externas. Sin desbordamiento
horizontal a 320/360/412/839/840/1024/1440 y a 200 % en 360. Se conservan
20 capturas en [capturas](capturas), procedentes **del HTML en Chrome headless**,
no de Flutter Windows ni de un dispositivo Android.
Inspección visual de resultados Windows/Android y detalle al 200 % realizada.

| Criterio | Evidencia revisable |
| --- | --- |
| Acceso, mes, ejecución manual y progreso/cancelación | `*-inicio.png`, `*-progreso.png` y recorrido automatizado |
| Resumen, grupos, filtro y detalle con destino | `*-resultados.png`, `*-duplicado.png`, pruebas de filtro y retorno |
| Sin hallazgos y pendientes válidos | `*-sin-hallazgos.png`, `*-pendientes.png` |
| Regla no ejecutada distinta de conforme | `*-no-ejecutada.png`, ocho de nueve reglas |
| Lectura fallida y recuperación | `*-error-lectura.png`, recorrido de recuperación sin recuentos |
| Obsoleto, repetición y retorno desde corrección | `*-obsoleto.png`, prueba de cambio y periodo |
| Apariencia/navegación EP-026 y adaptación | CSS/tokens/fuentes reutilizados, 7 anchos, `android-*-200.png` |
| Artefacto conservado y aprobación explícita | HTML y fuentes conservados; **aprobación específica pendiente** |

No se han verificado SQLite, servicios financieros, restauración, rutas nativas,
lectores de pantalla, teclado/Back nativo ni dispositivo Android físico.
Son materia de implementación/integración posterior. No se ejecuta
`check-quality.ps1`, análisis o builds Flutter: este cambio solo contiene HTML,
JavaScript del prototipo, documentación y capturas; no cambia Dart/plataformas.

## Puerta de aprobación y versión

La aprobación global no acredita este suplemento. Antes de completar el
ticket registrar persona, fecha y referencia textual de la aprobación de
esta versión en Epic Board. No se registra ni se simula esa aprobación.
La petición explícita del usuario exige esperar antes de implementar los
tickets posteriores. El commit de la propuesta no equivale a su aceptación.

SHA-256 del HTML v1 publicado:
`2a1e89e05a40dc1ae6a216832ac703ad0003c90a78c349d916e7ae84b18f80c5`.
Publicación en la ruta pública de Epic Board; respuesta HTTP 200 y hash
contrastado con el artefacto retenido antes de la entrega.
