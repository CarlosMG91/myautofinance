# MA-TSK-235 · Protocolo de aceptación del EXE real

Este protocolo prepara T08; no es evidencia de ejecución. El resultado actual
está en [verificacion-e2e.md](verificacion-e2e.md). Se usan la generación
[T06](generacion-privada.md), la [guía T07](guia-usuario-windows.md), el
[contrato T01](contrato-instalacion.md) y los [casos EP-001](../ep-001/casos-referencia.md).
No cerrar T08 ni EP-028 mientras falte alguna comprobación obligatoria.

## Entradas y entornos

Preparar dos entregas completas T06 desde dos commits limpios, con versiones
numéricas diferentes en sus respectivos `pubspec.yaml`, N < N+1. No renombrar
EXE ni editar manifiestos/recursos para simular una actualización. No cambiar
la versión de la rama compartida solo para producir el ensayo. Cada entrega
debe pasar su calidad y conservar su `delivery-manifest.json`, manifiestos de
payload/build/calidad y licencias. No sustituirla por el fixture CI.

En el equipo constructor, antes de transferir las carpetas privadas completas:

```powershell
node scripts/check-windows-e2e-inputs.mjs 'dist-private/windows/<N>/delivery' 'dist-private/windows/<N+1>/delivery'
```

El control solo lee archivos. Reutiliza la integridad T06, contrasta versiones,
AppId, commits, calidad y hashes entre manifiestos. Rechaza igualdad/downgrade,
metadatos incoherentes y archivos alterados/extra. Devuelve `inputsConsistent`
y **`e2e=notExecuted`**; los manifiestos son declaraciones, no prueban que un
binario sea el producto real, su procedencia o su ejecución. SHA256 no acredita
autoría, confianza ni SmartScreen. Verificar también recursos PE y firma real
en Windows; conservar el hash del manifiesto por el canal privado acordado.

| Entorno obligatorio | Identificación que se debe registrar | Estado actual |
| --- | --- | --- |
| Windows 10 x64 cliente | Edición, versión, build/revisión, imagen y checkpoint | No disponible / no ejecutado |
| Windows 11 x64 cliente | Edición, versión, build/revisión, imagen y checkpoint | No disponible / no ejecutado |
| CI Windows Server T06 | Job, commit y alcance de fixture | Antecedente; no sustituye las filas cliente |

En cada cliente usar una VM desechable y un usuario estándar nuevo, sin datos
personales, SDK Flutter/Dart, Visual Studio ni runtime VC++ v14 global. Un perfil
nuevo en un host con CRT global no acredita el arranque sin ese runtime. Registrar
inventario de herramientas/paquetes globales, pertenencia a grupos y rutas de
DLL efectivamente cargadas; no inferir ausencia por `PATH`. No desinstalar
componentes del equipo personal para crear estas condiciones. No cambiar
protecciones Windows. Incluir ruta de perfil con espacios/acentos.

Transferir entradas antes de desconectar la NIC virtual. Ejecutar primero la
instalación y el arranque offline, sin elevar Setup, registrando ausencia de UAC,
descargas y dependencias faltantes. La sonda del proveedor controlado se ejecuta
en una fase posterior diferenciada, mediante loopback en la VM; no implica
conexión con Google. La VM sin SDK ejecuta binarios preparados, no compila tests.

## Datos y comparación

Importar por Gestión el CSV sintético EP-001, resolver sus referencias y crear
la foto manual del 2026-01-01 según los casos A–G. Son 48 partidas y 10 reales,
incluidos dos Café. No inyectar una base personal. Registrar versión y origen
del runner en cada captura; no usar HTML/goldens como capturas nativas.

| Pantalla / caso | Resultado que debe repetirse tras cada operación |
| --- | --- |
| Estado enero 2026 | Real +1.229,75; previsto +1.100,00; diferencia +129,75 EUR |
| Patrimonio enero | Neto 14.000,00; líquidos 9.000,00 EUR |
| Presupuesto anual 2026 | +13.200,00 EUR, 48 partidas |
| Real anual 2026 | +2.329,65 EUR, 10 movimientos |
| Indicador enero | 3,00 meses, ingreso anual presupuestado 36.000,00 EUR |
| Febrero sin foto / foto parcial | «sin dato», sin arrastrar enero; pendientes identificados |
| Variante D, ahorro cero explícito | Foto completa: líquidos 6.200,00, neto 11.900,00; indicador 2,07 |
| Sin presupuesto / presupuesto cero | Ocio conserva sus reales; cero explícito no se confunde con ausencia |
| Foto completa con líquidos cero | Con ingreso presupuestado positivo y completo, indicador 0,00 meses |
| Ingreso incompleto / cero explícito | Un mes ausente impide el indicador; un mes con cero cuenta como registrado |
| Ingreso anual cero o negativo | «sin dato» por denominador no válido, sin división por cero ni valor inventado |

Las variantes se ensayan en checkpoints independientes para no contaminar las
cifras iniciales. Patrimonio corresponde a EP-009/017 y EP-026 MA-TSK-212;
no se inventa una dependencia EP-020. EP-025/027 no son requisitos de este ensayo.

Antes/después registrar `datasetId`, revisión, esquema, UUID/referencias y filas
de negocio ordenadas, catálogo/copias, diarios, estado Drive, ruta efectiva de
soporte obtenida por el runner/path_provider y GUID/target de instalación. Usar
instrumentación diagnóstica de prueba si hace falta, identificándola como tal;
no atribuir su resultado automáticamente al EXE production. La igualdad de
Known Folder/VERSIONINFO por sí sola no prueba la ruta devuelta por Flutter.

Con la app cerrada y sin handles vivos, obtener inventario y SHA256 de soporte
antes de Setup y después de Setup **antes de abrir la app**: SQLite, sidecars,
copias, diarios y estado Drive deben coincidir. No copiar ni hashear una BD viva
como evidencia de una foto consistente. Tras abrir, comparar datos lógicos por
los servicios EP-004; cambios de esquema solo por migración legítima con respaldo.
No exigir hash SQLite idéntico después de un arranque que migra o hace checkpoint.
El instalador nunca consulta SQL, copia bases vivas ni baja el esquema.

## Recorridos obligatorios en ambos clientes

Cada fila requiere fecha UTC, entorno/checkpoint, versiones/commits/SHA256 de
entradas, acción, resultado esperado/observado, código de salida y referencia a
evidencia privada. `pendiente`, `bloqueado` o fallo no equivalen a aprobado.

| ID | Acción y comprobación |
| --- | --- |
| E01 | Instalar N offline, usuario estándar, sin SDK/VS/CRT global. Abrir por Inicio y escritorio opcional. Comprobar carga de CRT app-local y pantallas/cifras de arriba. |
| E02 | Sembrar sesión sintética nativa exclusiva de destino, mediante una sonda aislada. Capturar GUID/target sin secreto; cerrar. Actualizar N→N+1. Mismo `%LOCALAPPDATA%/Programs/Autofinance`, mismo AppId/HKCU, una sola entrada de uninstall, recursos PE N+1, accesos funcionales, inventario completo y cifras/IDs/revisión conservados. |
| E03 | Reparar N+1, incluyendo binario propio alterado/ausente en checkpoint separado. Restituir inventario, sin limpiar sesión, datos ni archivos ajenos. Verificar GUID y refresco de E09. |
| E04 | Ejecutar N sobre N+1. Rechazo antes de escribir: payload, registro, accesos, soporte y credenciales iguales; N+1 sigue utilizable. |
| E05 | Desinstalar N+1 por la UI. Conservar datos/copias/diarios/estado Drive y sesión de directorio independiente. Eliminar solo credencial/marker propios; no llamar revocación remota. Reinstalar N+1: recuperar mismos datos y pedir conexión intencional nueva, sin resucitar credencial eliminada. |
| E06 | Adoptar desde EXE anterior exacto, identidad/soporte inequívocos, confirmación explícita. Origen y destino deben tener GUID propios; sesión transferida comprobada antes de retirar origen. Origen independiente intacto. Validar recursos/ruta efectiva antes de abrir store. |
| E07 | Repetir adopción con otra sesión en destino, origen inválido/ambiguo y sin consentimiento: bloquear sin sobrescribir ni escanear credenciales. Cancelar selección/asistente antes de reemplazo: ningún cambio de datos/sesiones/payload. |
| E08 | App abierta con borrador y con operación de copia; segunda instancia durante mantenimiento, tanto origen como destino. Setup bloquea o permite cierre cooperativo según guía; sin taskkill, sin reemplazar archivos en uso ni abrir BD desde nueva instancia. Registrar ventanas/códigos. |
| E09 | Forzar expiración de la sesión sintética y refrescar con proveedor controlado mediante el adaptador nativo. Comprobar lectura real de Credential Manager tras update/repair, persistencia del nuevo secreto y contador de refresco del proveedor. No basta una igualdad de GUID ni un mock en memoria. Ningún token en argumentos, entorno, archivos o logs. |
| E10 | Checkpoints separados: disco virtual sin espacio, ACL de destino sin escritura, archivo bloqueado y fallo de escritura. Registrar condición exacta/código. Sin pérdida ni éxito falso; después de restituir recursos, reparación/reintento según T07 deja app utilizable. No llenar ni cambiar ACL del host. |
| E11 | Interrumpir Setup/adopción antes y después de cada frontera durable relevante, en VM, nunca matar la app con BD abierta. Reiniciar misma versión o superior; reconciliación idempotente o bloqueo explícito ante conflicto, sin cambiar origen ni borrar diarios para forzar progreso. Incluir interrupción de Uninstall y reintento de limpieza propia. |
| E12 | Base sintética de esquema futuro por fixture del propietario EP-004; versión anterior rechazada por Setup o store sin reset/migración descendente. Copia de esquema antiguo compatible migra con respaldo EP-004. Recuperación de diarios/copias por EP-006 y T07; comparar datos originales. |

## Sesión sintética y evidencias

El ejecutable nativo de T03 se prepara en el equipo constructor y se ejecuta
**solo** en el perfil `AutofinanceTest_<sufijo>` de la VM con las tres copias y
opt-in descritos en [verificacion-sesion.md](verificacion-sesion.md). Sus
sentinelas prueban aislamiento/credenciales del adaptador, no cifras SQLite ni
refresco OAuth. Complementa E06/E07/E09; no los sustituye.

E09 requiere una sonda/proveedor controlado que conecte el flujo de refresco real
con el almacén nativo y pueda conservar exclusivamente un resultado booleano y
contador sin secretos. Esta sonda aún no se ha integrado con el EXE final en
esta sesión. Una compilación instrumentada debe consignar su diferencia respecto
de production y repetir los recorridos del paquete final que correspondan.
No afirmar OAuth Google real a partir de esa prueba. Una comprobación Google
opcional exige cuenta de pruebas y acciones explícitas; guardarla por separado.

Conservar localmente bajo `dist-private/windows/e2e/<entorno>/<ejecucion>/`:
ficha del entorno, hashes de entregas, tablas de comparación, capturas nativas
sanitizadas, códigos/resultados y logs sin secretos. No guardar dumps de Credential
Manager, blobs, cuentas, perfiles ni respuestas OAuth. No publicar archivos del
paquete ni datos en artifacts/Releases. En Git solo debe ir el informe resumido
sin rutas personales, identificadores de sesión ni secretos. Descartar las VM
al terminar, después de conservar la evidencia privada necesaria.

El cierre requiere E01–E12 aprobados en ambos entornos, calidad pertinente
aprobada, EXE production identificado por SHA256 y firma efectiva documentada,
y revisión humana de las ventanas conforme al mockup aprobado. Una compilación,
el preflight o CI Server no permiten inferir ese cierre.
