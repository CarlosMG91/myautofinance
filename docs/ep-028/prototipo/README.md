# Propuesta del asistente privado de Windows · v1

MA-TSK-231 · EP-028 · 2026-10-17. **Pendiente de aprobación humana**.
No completa el ticket ni autoriza implementar MA-TSK-232 o tickets posteriores.

Artefacto conservado: [instalador-v1.html](instalador-v1.html).
Revisión en Epic Board: `/mockups/autofinance-instalador-privado-v1.html`.
También disponible mientras el board local esté activo:
`http://localhost:4310/mockups/autofinance-instalador-privado-v1.html`.

HTML autocontenido sin dependencias, recursos remotos ni persistencia. Los
botones representan estados; no instalan, abren o desinstalan programas ni
consultan archivos, credenciales o Drive. Versiones, nombres de perfil, rutas
y GUID son ficticios. No incluye EXE ni manifiesto de una entrega real.

## Identidad y alcance de la aprobación

Se han consultado el ticket y la épica en `GET /api/data` de Epic Board,
`docs/ep-026/prototipo/aprobacion.md`, los tokens visuales EP-026 y
`lib/ui/src/tokens.dart`. La propuesta usa verde `#14645f`, fondo `#f6f5f1`,
texto `#202e32` y colores de aviso/error de ese contrato. Segoe UI y los
controles comunes aproximan el asistente Inno de Windows. El monograma A
representa la identidad en el HTML; el instalador usará los recursos de
identidad existentes. La geometría exacta y los controles del asistente
nativo se verifican después de implementar, sin convertir este HTML en una
captura de Windows o Flutter.

La revisión solicitada abarca jerarquía visual, textos, secuencia, decisiones
y resultados. No afecta pantallas financieras ni añade autoactualización.
T01/T02/backend pueden avanzar de forma independiente según la épica. Esta
propuesta no fija una API de transferencia, AppId o formato de marcadores;
su implementación debe consumir los contratos de sus tickets propietarios.

## Cobertura revisable

| Criterio | Dónde revisarlo |
| --- | --- |
| Windows 10/11 x64, offline, por usuario, sin admin/SDK y C++ app-local | Primera instalación → bienvenida |
| Destino fijo `%LOCALAPPDATA%\\Programs\\Autofinance`, sin directorios por versión | Bienvenida y resumen; perfil ficticio `María López` |
| Inicio, escritorio opcional sin premarcar, sin autoarranque | Primera instalación → accesos → resumen |
| Versión, ruta, conservación y siguiente acción | Inicio/resumen/final de cada recorrido |
| Actualización manual anterior → nueva; mismo directorio y sesión/GUID | Actualizar 1.3 → 1.4 |
| Misma versión repara; no restaura BD ni baja esquema | Reparar 1.4 |
| Bloquear paquete antiguo | Rechazar versión anterior |
| App abierta: cerrar manualmente, reintentar o cancelar; sin kill | App abierta; botón de simulación de cierre separado del asistente real |
| Adopción: origen inequívoco y consentimiento no premarcado, sin cuentas/tokens | Adopción de Drive; ruta EXE completa + versión + GUID de origen |
| Sin compartir sesiones independientes ni sobrescribir destino | Destino con otra sesión; continuación conserva destino |
| Origen ausente/ambiguo no habilita transferencia | Origen ambiguo o ausente |
| Sin transferencia por defecto; sin subir/descargar automáticamente | Adopción → continuar sin casilla → resumen |
| Desinstalar conserva datos/copias/diarios/estado Drive y desconecta solo credencial/marcador propios, sin revocación ni purga | Desinstalar → final |
| Cancelación antes/después de cambios, sin falso éxito | Cancelar en bienvenida o progreso; modal permite volver |
| Fallo no promete rollback completo ni éxito; siguiente paso para reparar | Fallo de la operación |
| Reinicio pendiente distinto de completado, sin reinicio/arranque automático | Reinicio pendiente |
| Ejecutar tras terminar solo por elección | Finales de instalación/actualización/reparación; casilla desmarcada |
| Sin firma ni editor verificado; SHA-256 no atribuye confianza o autoría | Firma y entrega privada; sin hash inventado de EXE |

La pantalla de firma pertenece al catálogo de revisión y a la información de
entrega; no sustituye una advertencia del sistema ni representa SmartScreen.
El único hash registrado aquí identifica el **HTML**, no un instalador.

## Teclado, escalado y perfiles

Revisión estática: controles HTML nativos, etiquetas asociadas, foco visible,
orden DOM coherente, foco en el título al cambiar de paso y diálogo de
cancelación con acción de continuar enfocada. Tab/Mayús+Tab y Enter conservan
su comportamiento nativo; Escape solicita cancelar y el diálogo permite
volver al asistente. El progreso no captura todo el teclado. El panel lateral
es un catálogo del prototipo, no parte de Inno.

El control «Texto al 200 %» permite inspeccionar reflujo sin un ancho fijo del
asistente. Hay reglas para ventanas estrechas, alto contraste y rutas largas
con ajuste de línea. Las rutas ficticias incluyen espacios y acentos tanto en
usuario como en origen. No se han probado rutas reales ni creado perfiles.

**Pendiente de revisión visual en navegador y de validación nativa:**
distribución efectiva y desbordamientos al 100/125/150/200 % de escala Windows,
teclado real, foco del diálogo, lector de pantalla, tema de contraste y
perfiles desechables con espacios/acentos. El inventario de Computer Use
devolvió cero navegadores y cero apps; no se obtuvieron capturas. La revisión
estática y el botón de texto ampliado no acreditan escalado DPI nativo.
MA-TSK-232/235 deben comprobar el asistente real en Windows 10/11 aislado.

## Verificación y conservación

Ejecutar desde la raíz:

```powershell
node docs/ep-028/prototipo/verificar-mockup.mjs
```

Prueba ejecutada correctamente: cinco recorridos completos, consentimiento
desmarcado y revocable al volver atrás, sesiones independientes, origen no
verificable, app abierta y reintento, downgrade, cancelación previa/parcial,
fallo, reinicio y apertura voluntaria. Es una prueba de estados con DOM mínimo,
no una prueba de layout, navegador, Inno o preservación real de datos.

Publicación comprobada con HTTP 200 y `text/html; charset=utf-8`. Archivo
local y archivo servido desde la carpeta pública tienen el mismo SHA-256:

`bec3ff0a447ae41d65e65a676ecef4a492e57ce243323d714c302ab8e7561f47`.

No se crean servicios de hosting, releases o instaladores públicos. Solo se
copia este HTML sintético a la ruta de mockups del board existente.

No hay aprobación humana registrada en esta entrega. Debe quedar asociada a
esta versión/URL antes de completar el ticket o implementar el asistente.

### Calidad general del checkout

Se ejecutaron `flutter --version` y `scripts/check-quality.ps1` con la
toolchain fijada. El primer intento no pudo consultar `pub.dev` por la
restricción de red; se repitió con el acceso autorizado, sin actualizar SDK
ni `pubspec.lock`. Resolución de dependencias correcta, formato de 505 archivos
sin cambios y análisis sin incidencias.

La suite general finalizó con **2.008 pruebas superadas y cinco fallos**:

- `test/budget/budget_lifecycle_test.dart`, recorrido Android: timeout de 45 s.
- `test/movements/pending_lifecycle_test.dart`, Windows y Android: `No element`
  al buscar un control en `pending_lifecycle_journey.dart:144`.
- `test/synchronization/local_recovery_journey_test.dart`, fallo de disco tras
  instalar: canal de isolate cerrado durante rollback.
- Ese mismo archivo, dos copias manuales/restauración/recuperación: discrepancia
  en la comparación del estado esperado.

El recorrido de presupuesto Android pasó en la repetición aislada:
`flutter test --no-pub --concurrency=1 test/budget/budget_lifecycle_test.dart
--plain-name 'EP-011 recorrido SQLite de archivo: android'` (una prueba, 30 s).
Esto no convierte la ejecución general en correcta. No se modificaron esos
módulos ni se establece una causa para los fallos en este ticket; el checkout
contiene cambios concurrentes. No se repitieron los otros cuatro fallos.

El script se detuvo tras la suite fallida, por lo que no ejecutó su bloque
posterior de arranque por `APP_ENV`. No se realizaron builds Windows/Android:
esta entrega solo añade el prototipo HTML, su prueba de estados y este informe.
Logs locales ignorados: `.tools/ma-tsk-231-quality.log`,
`.tools/ma-tsk-231-quality-unrestricted.log` y
`.tools/ma-tsk-231-budget-retry.log`.
