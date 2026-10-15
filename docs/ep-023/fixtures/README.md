# MA-TSK-187 · Casos sintéticos del colchón

`ma-tsk-187-colchon.json` recoge variantes aisladas del caso G y la foto de
febrero del caso D. Todos los importes son céntimos enteros sintéticos; las
sumas y razones grandes se guardan como cadenas decimales para no perder
precisión al leer JSON.

Desde la raíz del repositorio, ejecutar:

```powershell
node docs/ep-023/fixtures/verificar-ma-tsk-187.mjs
```

El comprobador verifica los resultados exactos y su presentación a dos
decimales, motivos y precedencia, presencia explícita por mes, suma según la
marca de la raíz, signos, categorías archivadas/reparentadas, independencia
de fotos por mes y el límite del catálogo de producción en la prueba de
extensibilidad. No importa servicios de la aplicación ni modifica las reglas
ni el contrato EP-001.

| Escenario | Resultado esperado |
|---|---|
| Enero: líquidos 9.000 EUR; ingresos del año 36.000 EUR | `3/1`, mostrado `3,00` meses. |
| Febrero ausente / parcial | `foto_ausente` / `foto_incompleta`; parcial deja pendientes Ahorro y Cartera. |
| Febrero completo: 6.200 EUR; corrección: 6.300 EUR | `31/15` → `2,07`; `21/10` → `2,10`. Enero conserva 9.000 EUR. |
| Doce meses con cero explícito / un mes sin partida | `ingresos_nulos` / `ingresos_incompletos` (mes 3 pendiente). |
| Ingreso anual firmado negativo / liquidez cero | `ingresos_negativos` / razón válida `0/1`, mostrada `0,00`. |
| Foto ausente más ingresos incompletos y negativos | Prevalece `foto_ausente`; los casos encadenados cubren el resto del orden. |
| Una partida de 1 céntimo / importes superiores a 2^53 | Razón exacta sin división previa; formato final con dos decimales. |
| Varias partidas en enero | Solo enero queda completo; febrero–diciembre siguen pendientes. |

La extensión se expresa como criterio de prueba: una definición sintética
puede añadirse al motor durante pruebas, mientras el catálogo de producción
contiene únicamente `colchon_emergencia`.
