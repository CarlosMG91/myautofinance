# Ejemplo sintético EP-027 v1

Exportación de datos: enero a marzo de 2026 inclusivos. Movimientos por fecha
de valor; presupuestos y fotos por mes. Catálogos completos: contienen contexto
anterior/posterior al filtro, cuentas cerradas y categorías archivadas.

Abrir con editor de texto o importar CSV indicando UTF-8, separador ; y
calificador de texto ". Desactivar fórmulas y detección de tipos y seleccionar
TODAS las columnas como Texto antes de cargar. No abrir con doble clic. Si la
herramienta no permite impedir evaluación, usar un lector que no evalúe fórmulas.
Las comillas CSV no impiden ejecución de fórmulas en hojas de cálculo. No se
añaden apóstrofos ni se alteran conceptos. No convertir importes a coma flotante.

Null es campo vacío sin comillas; cadena vacía es "". Una hoja que los colapse
no permite distinguir ausencia: usar lector CSV que conserve las comillas.
Los saltos CR/LF y Unicode interiores se conservan. Importes con signo interno,
incluidos presupuesto cero y deuda positiva. No hay subtotales patrimoniales.
Febrero conserva cabecera vacía absent; marzo foto incompleta; abril sin cabecera
no se exporta. Ningún valor o presupuesto ausente se rellena con cero.

Este ZIP no es CSV histórico EP-013 ni promete reimportación o reconstrucción.
No contiene extractos originales completos. Consulte diccionario.json.
