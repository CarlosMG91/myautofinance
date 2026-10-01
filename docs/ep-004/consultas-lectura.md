# MA-TSK-039 · Consultas de lectura

Los puertos públicos siguen en su dominio propietario, exportados por las
entradas de movimientos, presupuesto y patrimonio. App inyecta los adaptadores
SQLite con la misma LocalDatabase. No se añaden pantallas, fórmulas de informes,
parseadores ni dependencias entre funcionalidades.

| Entrada pública | Datos de origen |
|---|---|
| CategoryRepository.list() | Árbol completo, incluidos archivados, padre, profundidad y marca de ingreso heredada |
| MovementRepository.readMonth(year, month) / readYear(year) | Todos los movimientos según fecha de valor, ordenados por fecha/id, sin límite de paginación |
| Las mismas lecturas con categoryId | Nodo y descendientes; cada movimiento conserva su categoría directa y aparece una vez |
| BudgetRepository.list(month) / readYear(year) | Partidas explícitas originales por nodo, incluidos ceros y procedencia |
| BudgetRepository.readYear(year, incomeOnly: true) | Partidas de los doce meses bajo raíces de ingreso, independientemente de signo o archivo |
| AccountRepository.listForMonth(month) | Fichas vigentes, con liquidez efectiva; deudas sin liquidez |
| WealthRepository.read(month) / readYear(year) | Valores manuales y fichas pendientes; doce estados mensuales independientes en la lectura anual |

## Consumo

Estado mensual combina árbol, movimientos del mes y partidas del mes. Presupuesto
anual combina árbol y partidas del año; real anual combina árbol y movimientos
del año. El árbol permite reconstruir los agregados desde el nodo directo sin
consultar tablas. No se materializan filas para ancestros ni se reparte presupuesto
padre entre hijos. La ausencia de partida es una lista vacía, no un cero explícito.
Los movimientos sin categoría y las dos piernas manuales de una transferencia
permanecen en la lectura completa, con sus signos y cuentas.

Patrimonio consume únicamente sus fotos y fichas. Colchón consume la foto del mes
y las partidas anuales con incomeOnly: true. La presencia de alguna partida de
ingreso en cada mes permite distinguir ingresos incompletos de doce ceros
explícitos. El consumidor calcula sumas, denominador, motivos y presentación;
estas consultas no calculan el indicador ni toman decisiones por el signo.
La foto conserva absent/incomplete/complete, valores cero válidos y pendientes;
un mes no recibe valores de otro y el año no tiene un saldo aditivo.

Las lecturas completas no tienen la cota de 500 del listado paginado para edición.
Para detalles grandes se conserva MovementRepository.list con su cursor existente.
Los periodos civiles son [inicio, siguiente mes/año); diciembre de 9999 usa el
extremo abierto permitido por el calendario del esquema. Se usan rangos sobre
value_date y month, no funciones sobre esas columnas, aprovechando movements_date,
movements_category_date y la unicidad (month, category_id). El esquema físico
sigue en v6: no requiere migración ni cambios de índices.

Cada consulta SQL entrega una lectura consistente. La lectura anual patrimonial
agrupa los doce meses en una transacción. Para combinar varias lecturas públicas
en una misma revisión, app puede envolverlas en una transacción de la conexión
compartida. Las lecturas no incrementan la revisión financiera.

## Verificación

report_reads_test.dart usa SQLite real y datos sintéticos equivalentes a EP-001:
48 partidas, 10 movimientos con los dos cafés legítimos y foto inicial. Reconstruye
real anual 2.329,65 EUR, presupuesto anual 13.200,00 EUR, diferencias mensuales,
patrimonio 14.000,00 EUR y colchón 3 meses solo desde contratos públicos. Comprueba
ausencias, ceros, signos negativos en ingresos, tres niveles sin duplicación,
sin clasificar, archivo de categorías, liquidez histórica y vigencias de fichas.
Verifica además 501 movimientos en un mes, límites del calendario, procedencia,
revisión intacta e índices en los planes de consulta.

check-quality.ps1 completado con Flutter 3.47.0 / Dart 3.13.0 y lockfile
sin actualizar: formato correcto, análisis sin incidencias, 76 pruebas correctas
y las cuatro variantes de APP_ENV. git diff --check sin errores.

Se utiliza el ticket completo facilitado por el usuario: no hay herramienta
Epic Board disponible y no se cambia su estado administrativo. No se modifican
plataformas; la ejecución nativa Windows/Android queda sin verificar localmente.
