# Guía cotidiana de Autofinance

Preparada el 2026-10-21. La entrega final sigue bloqueada según el
[expediente](expediente-entrega.md). Esta guía describe el recorrido existente;
no acredita que se haya realizado en los paquetes finales.

## Instalar o actualizar conservando datos

Recibe los paquetes y manifiestos por el canal privado de entrega. Comprueba
versión, SHA-256, plataforma y entorno production contra el manifiesto común.
Conserva la entrega anterior y una copia recuperable antes de actualizar.

- **Windows:** sigue la [guía del instalador](../ep-028/guia-usuario-windows.md).
  Cierra la app y ejecuta Setup con el usuario habitual; actualizar conserva
  datos, copias y estado. Una versión inferior se rechaza. Si se ofrece transferir
  sesión, revisa y confirma el origen exacto según esa guía.
- **Android:** sigue [instalación y actualización privada](../ep-029/guia-entrega-privada.md).
  Actualiza sobre la misma aplicación, con firma estable y versión superior,
  sin desinstalar ni borrar almacenamiento. Conserva el APK previo y sus datos.
  La [custodia de firma](../ep-029/firma-distribucion.md) corresponde al responsable
  de entrega; no compartas claves o contraseñas.

Si los hashes o la firma no coinciden, conserva la instalación y solicita el
paquete correcto por ese canal. Una copia de datos no garantiza que pueda
abrirse con una versión antigua de la aplicación.

## Importar, categorizar y consultar

Desde Inicio entra en Gestión para importar el histórico CSV. El
[contrato CSV](../ep-001/contrato-csv.md) explica columnas y signos. Revisa
cuentas, categorías, errores y posibles duplicados antes de confirmar. Cancelar
no debe escribir; los errores impiden altas parciales. Repetir los mismos bytes,
aunque cambie el nombre, no añade datos; dos filas iguales del mismo archivo
pueden ser dos movimientos legítimos. Openbank requiere la entrega caracterizada
de EP-014; actualmente la entrada sigue deshabilitada.

En Movimientos/Pendientes revisa fechas de valor, cuenta, importe y categoría.
Asigna categoría individualmente o selecciona los visibles para aplicar un lote;
revisa antes de guardar. La Discrecionalidad es texto conservado. Consulta el
[recorrido de categorización](../ep-015/verificacion-categorizacion.md).

En Presupuesto elige mes/año y guarda las partidas expresamente. Cero es un
valor; ausencia significa que no hay partida. No presupuestes a la vez un padre
y un descendiente del mismo mes. Revisa el resumen anual y la propuesta del
siguiente año antes de aceptarla; cancelar la propuesta no debe guardarla.
Véanse [presupuesto mensual](../ep-011/verificacion-presupuesto-mensual.md) y
[propuesta anual](../ep-018/verificacion-integral.md).

Registra en Patrimonio los valores manuales del día 1 de todas las fichas
vigentes. Los movimientos no calculan estos saldos. Una foto incompleta o ausente
produce «sin dato». Desde Inicio consulta Estado, Presupuesto anual, Real anual,
Patrimonio e Indicadores, eligiendo periodo y abriendo sus desgloses. El colchón
divide activos líquidos por ingresos anuales presupuestados/12; requiere foto
completa e ingresos registrados en los doce meses. Consulta los
[casos de referencia](../ep-001/casos-referencia.md) y el
[diagnóstico](../ep-025/interfaz-diagnostico.md) si falta un resultado.

## Copias y cambio de dispositivo

En Gestión → Copia en Drive revisa cuenta, carpeta, versión conocida y cambios
locales. La conexión usa el consentimiento configurado por la entrega. Solo
**Subir copia** y **Descargar última copia** acceden a Drive; abrir o editar no
sincroniza. Trabaja en un dispositivo cada vez: sube al terminar y descarga en
el otro antes de editar. La fecha/versión visible puede ser la última conocida.

Antes de descargar, abre Copias locales y pulsa **Crear copia** si quieres
conservar tus cambios; comprueba que la copia aparece validada en el catálogo.
Revisa fecha y versión; descargar sustituye la base completa tras validación y
respaldo previo. Puedes cancelar sin aplicar. No hay fusión. Si aparece
divergencia, conserva ambas versiones y decide expresamente qué base utilizar;
no fuerces una subida. Ante fallo o resultado incierto, conserva el mensaje y
los datos, y vuelve a pulsar el botón para contrastar antes de reintentar.
Una carrera simultánea puede dejar activa la última escritura; el historial de
Google no promete conservar todas las revisiones indefinidamente.

Para volver a una copia local usa el flujo existente de Copias locales:
selecciona, valida, revisa y confirma. La restauración conserva un respaldo de
la base sustituida y puede requerir nuevo contraste con Drive. No borres diarios
o marcadores ni copies la SQLite activa con sus sidecars. Si la app no puede
recuperar, conserva el perfil y el diagnóstico y consulta soporte. Detalles:
[Drive manual](../ep-007/interfaz-drive.md),
[divergencia e incertidumbre](../ep-007/divergencia-subida-incierta.md),
[restauración segura](../ep-006/restauracion-segura.md) y
[recuperación interrumpida](../ep-006/recuperacion-interrumpida.md).

## Exportar y consultar sin la aplicación

En Gestión abre Exportación y portabilidad: **Exportar datos** prepara los CSV
y **Exportar copia completa** prepara la SQLite portable. Selecciona el rango cuando corresponda,
y guarda mediante el destino del sistema. CSV sirve para consultar datos;
la copia SQLite portable conserva la base completa. Los presupuestos CSV
exportados tienen signo interno: no los reimportes como histórico de signo
inverso. Conserva el ZIP original y su hash. Para consultar la copia sin Flutter,
transfiérela como documento normal y sigue la
[guía independiente SQLite](../ep-027/recuperacion-sqlite.md) en una carpeta
nueva, sin sustituir ninguna instalación. Véanse
[CSV](../ep-027/exportacion-csv.md) y
[copia portable](../ep-027/copia-sqlite-portable.md).
