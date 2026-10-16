# MA-TSK-193 · Conciliación de cifras y registros de origen

Fixtures sintéticos y resultados esperados para contrastar aperturas de Estado,
Presupuesto anual y Real anual. Los importes son EUR firmados, en céntimos,
siguiendo EP-001. Este artefacto fija conjuntos de origen antes del filtro; no
implementa una consulta ni establece reglas nuevas.

## Fixture base

Categorías (UUID simbólicos estables para facilitar la lectura): `ING` raíz de
ingresos; `HOG` raíz con `ALQ` hija; `ALI` raíz, `SUP` hija y `COMP` nieta;
`OCIO` raíz. `OLD` es una categoría archivada que antes era hija de `ALI` y
ahora cuelga de `HOG`. `DUP-A` y `DUP-B` son categorías distintas con el mismo
nombre visible «Otros». Los filtros y la conciliación usan UUID, no nombre ni
ruta. Cuentas: `C1` Cuenta principal, `C2` Cuenta ahorro.

| UUID | Tipo | Mes | Categoría | Cuenta | Importe | Significado |
|---|---|---|---|---|---:|---|
| P01 | presupuesto | 2026-01 | ING | — | +300000 | salario |
| P02 | presupuesto | 2026-01 | HOG | — | -100000 | partida padre, no repartida |
| P03 | presupuesto | 2026-01 | COMP | — | -40000 | compra semanal |
| P04 | presupuesto | 2026-01 | ALQ | — | -100000 | enero de EP-001 en fixture alternativo; usar solo aislado |
| P05 | presupuesto | 2026-02 | ING | — | +300000 | salario |
| P06 | presupuesto | 2026-02 | COMP | — | -40000 | compra semanal |
| P07 | presupuesto | 2026-01 | OLD | — | -700 | archivada / reparentada |
| R01 | real | 2026-01 | ING | C1 | +310000 | salario |
| R02 | real | 2026-01 | ALQ | C1 | -100000 | alquiler |
| R03 | real | 2026-01 | COMP | C1 | -35025 | compra semanal |
| R04 | real | 2026-01 | OCIO | C2 | -1000 | Café · registro A |
| R05 | real | 2026-01 | OCIO | C2 | -1000 | Café · registro B, legítimamente idéntico |
| R06 | real | 2026-01 | — | C1 | -500 | Sin clasificar |
| R07 | real | 2026-02 | ING | C2 | +302000 | salario |
| R08 | real | 2026-02 | ALQ | C1 | -100000 | alquiler |
| R09 | real | 2026-02 | COMP | C1 | -42010 | compra semanal |
| R10 | real | 2026-02 | OCIO | C2 | 0 | cero con registro de origen |
| R11 | real | 2025-12 | OLD | C1 | -700 | categoría archivada, ruta actual reparentada |
| R12 | real | 2026-01 | DUP-A | C1 | +500 | nombre no identifica rama |
| R13 | real | 2026-01 | DUP-B | C2 | -500 | mismo nombre, otro UUID |

`P04` no se mezcla con `P02`: serían presupuesto padre y descendiente en el
mismo mes, combinación prohibida por EP-001. P04 existe solamente como
fixture alternativo para reproducir el importe mensual de Alquiler; elegir uno
de los dos al cargar. El conjunto histórico original EP-001 conserva sus dos
filas «Café» separadas y los totales de sus casos B, C, E y F.

## Matriz de cifras y origen

`S{...}` denota el conjunto exacto de UUID y `Σ` su suma firmada. Las filas
agregadas incluyen descendientes una sola vez; «directo» incluye solo el UUID
de categoría indicado. Raíces y total general nunca suman padre más hijos.

| Informe / ámbito | Celda | Origen esperado antes de filtros | Σ EUR |
|---|---|---|---:|
| Estado real ene-2026 | ING agregado | S{R01} | +3.100,00 |
| Estado real ene-2026 | ALI agregado | S{R03} | -350,25 |
| Estado real ene-2026 | COMP directo | S{R03} | -350,25 |
| Estado real ene-2026 | OCIO agregado | S{R04,R05} | -20,00 |
| Estado real ene-2026 | Sin clasificar | S{R06} | -5,00 |
| Estado real ene-2026 | HOG previsto (P02 activo) | S{P02} | -1.000,00 |
| Estado real ene-2026 | ALI previsto | S{P03} | -400,00 |
| Estado real ene-2026 | ALQ directo real | S{R02} | -1.000,00 |
| Estado real ene-2026 | ALQ diferencia (alternativa P04) | S{R02,P04} | 0,00 |
| Presupuesto anual 2026 | ING enero / año | S{P01}; S{P01,P05} | +3.000,00 / +6.000,00 |
| Presupuesto anual 2026 | HOG enero (padre) | S{P02} | -1.000,00 |
| Presupuesto anual 2026 | ALI enero agregado | S{P03} | -400,00 |
| Presupuesto anual 2026 | febrero COMP | S{P06} | -400,00 |
| Presupuesto anual 2026 | marzo COMP / año sin partidas | S{} | 0,00 / sin presupuesto |
| Real anual 2026 | ING enero / año | S{R01}; S{R01,R07} | +3.100,00 / +6.120,00 |
| Real anual 2026 | ALI enero / febrero / año | S{R03}; S{R09}; S{R03,R09} | -350,25 / -420,10 / -770,35 |
| Real anual 2026 | OCIO enero / febrero | S{R04,R05}; S{R10} | -20,00 / 0,00 |
| Real anual 2026 | Sin clasificar enero | S{R06} | -5,00 |
| Real anual 2026 | DUP-A / DUP-B | S{R12}; S{R13} | +5,00 / -5,00 |

La suma de ramas de la plantilla EP-001, sin estos registros adicionales, debe
seguir siendo: Estado enero real +1.229,75, presupuesto +1.100,00, diferencia
+129,75; febrero +1.099,90, +1.100,00 y -0,10; Presupuesto anual +13.200,00;
Real anual +2.329,65. Las diez filas reales y 48 partidas de EP-001 son la
fuente para esa conciliación; los UUID de la fixture ampliada no se suman a
ella.

## Variantes de filtro y mutación

| Operación | UUID resultado | Conteo | Subtotal EUR | Comprobación |
|---|---|---:|---:|---|
| Abrir COMP desde Estado enero, directo | R03 | 1 | -350,25 | hereda enero/categoría/directo; coincide con cifra de origen |
| Cambiar a rama ALI en enero | R03 | 1 | -350,25 | el cambio es local, la etiqueta de origen se conserva |
| Real anual 2026 + cuenta C2 | R04,R05,R07,R10,R13 | 5 | +2.995,00 | cuenta solo real; dos Cafés no se colapsan |
| Real anual 2026 + Sin clasificar | R06 | 1 | -5,00 | no es filtro ni registro de presupuesto |
| Partidas enero + rama ALI (estado actual) | P03,P07 | 2 | -407,00 | categoría archivada se identifica por UUID y árbol actual |
| Presupuesto enero + cuenta/Sin clasificar | error de filtro | — | — | la UI no ofrece cuenta ni Sin clasificar |
| Cambiar Real anual 2026 a enero 2026 | R01-R06,R12,R13 | 8 | +1.724,75 | recalcular universo mensual; no incluir R07-R10 |
| Restablecer filtros del informe | ámbito inicial | según origen | según origen | repone filtros heredados; no restaura datos históricos |
| Paginar Real enero en páginas de 3 | primera 3 / resto 5 | 8 total | +1.724,75 total | contador/subtotal abarcan todas las páginas |
| Cero neto: R12 + R13 | R12,R13 | 2 | 0,00 | no convertir en ausencia ni eliminar identidades |
| Sin registros para categoría inexistente/mes sin datos | vacío | 0 | 0,00 | distinto de cero neto con registros |
| Editar R03 importe a -360,00 | R03 actualizado al releer | 1 | -360,00 | detalle conserva contexto; subtotal de origen ya puede diferir |
| Recategorizar R03 de COMP a SUP | R03 en SUP/rama ALI | 1 | -350,25 | UUID y suma se concilian con destino nuevo |
| Borrar R03 | vacío al releer COMP | 0 | 0,00 | sin snapshot fijo; retorno vuelve a leer |
| Reemplazar base durante lectura | no usar resultado atravesado | — | — | invalidar origen/lista anterior y conservar ámbito para reintentar |

Los filtros multimes se comprueban con extremos inclusivos: rango 2025-12 a
2026-02 para `OLD` produce {P07} en partidas y {R11} en reales por
separado; categoría UUID `OLD` sigue siendo la misma tras archivo/reparentado.
Una categoría homónima no añade registros: elegir `DUP-A` devuelve solo R12,
y `DUP-B` solo R13. La edición/categorización/borrado prueba retorno a detalle
y de lista con filtros, scroll y foco; volver al informe conserva periodo,
ramas y contexto originales.

## Relación con EP-001 y alcance

El CSV y los resultados aprobados siguen siendo la referencia de importes
financieros: `docs/ep-001/historico-ejemplo.csv` y
`docs/ep-001/casos-referencia.md` (casos B, C, E, F y matriz conjunta). Esta
fixture añade UUID sintéticos para comparar conjuntos de origen, identidad,
filtros y relectura; no modifica fórmulas, filtros EP-010 ni las consultas
propietarias de EP-019/021/022. Al conectar las aperturas, cada vista debe
entregar su enlace y su prueba final según dependencia. No afirma aceptación de
vistas que aún no estén disponibles.

## Verificación

Ejecutar `node docs/ep-001/verificar-casos.mjs` para las cifras obligatorias
del contrato. Esta matriz es un resultado esperado revisable y sintético; no
pretende reemplazar pruebas de integración SQLite de las aperturas. En los
casos con estado mutado, releer el resultado común antes de comparar. Las
sumas se expresan en centavos exactos; formato EUR se aplica solo al mostrar.
