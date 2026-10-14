# Autofinance — contexto para agentes

Este repositorio contiene una aplicación nueva de finanzas familiares, independiente de `MyFinance`. El producto previsto es una app Flutter completa para Windows y Android, con SQLite local y una copia manual en Google Drive. Hay una sola persona usuaria, importes solo en EUR e interfaz en español.

## Fuentes de verdad

- Para reglas financieras, leer la parte pertinente de `docs/ep-001/especificacion.md`. El usuario aprobó este contrato el 2026-10-01.
- Para importación histórica, usar `docs/ep-001/contrato-csv.md` y `docs/ep-001/historico-ejemplo.csv`.
- Para resultados comprobables, usar `docs/ep-001/casos-referencia.md`. El origen de las decisiones está en `docs/ep-001/decisiones.md`.
- El alcance, los criterios y las dependencias de cada tarea viven en Epic Board, tablero **My autofinance**. Consultar el ticket asignado antes de trabajar. No trasladar código ni decisiones pendientes del proyecto antiguo `MyFinance`.

## Reglas que no deben cambiarse de forma incidental

- Categorías de hasta tres niveles. La marca de ingreso pertenece a la raíz. Un movimiento real tiene cuenta, fecha de valor e importe firmado; ahorro y transferencias se suman según su signo.
- Presupuestos y movimientos reales son entidades distintas. El CSV histórico trae presupuestos con signo contrario al real equivalente; se normalizan al importar. Para una misma rama y mes se prohíbe presupuestar simultáneamente un padre y un descendiente.
- Los saldos de cuentas, deudas e inversiones son fotos manuales del día 1; nunca se calculan desde movimientos. Un mes sin foto completa se muestra «sin dato».
- El indicador inicial es `activos líquidos / (ingresos anuales presupuestados / 12)`. La estructura debe permitir añadir indicadores, pero la primera versión solo incluye este.
- La sincronización con Drive ocurre únicamente al pulsar «Subir copia» o «Descargar última copia». Debe proteger la base local y detectar divergencias; no hay fusión automática.

## Diseño y entrega

- EP-026 v1 es la referencia visual y de navegación vigente, aprobada explícitamente en MA-TSK-207; evidencia y hash en `docs/ep-026/prototipo/aprobacion.md`. Sustituye la apariencia de EP-002, conservando EP-001. Usar `lib/ui/autofinance_ui.dart`, resumen como entrada, detalle completo y adaptación Windows/Android. La aceptación visual final de MA-TSK-217 es independiente y no debe inferirse de tests o builds.
- Usar datos sintéticos en prototipos y pruebas. No añadir extractos bancarios reales, credenciales, tokens ni bases de datos personales al repositorio.
- Respetar el alcance y los archivos de otros tickets que estén ejecutándose en el mismo checkout. Antes de cambiar un contrato compartido, comprobar sus casos de referencia y las dependencias afectadas.
- Verificar el comportamiento cambiado con las pruebas pertinentes; cuando exista el proyecto Flutter, ejecutar también los análisis y pruebas del módulo afectado. Informar qué se comprobó y qué quedó sin verificar.
- La rama local inicial es `main` y `origin` apunta al repositorio de este proyecto. Confirmar y subir solo los cambios propios del ticket según la regla de Epic Board; no incluir cambios concurrentes de otros agentes ni forzar la subida. Si el remoto o permisos impiden subir, informar del bloqueo.

## Base Flutter y traspaso de EP-003

- `toolchain.json` fija Flutter/Dart/JDK y paquetes Android. Preparación y
  comandos completos en `README.md` y `docs/ep-003/entorno.md`. Inicializar
  con `flutter --version`, comprobar `scripts/check-toolchain.ps1` y resolver
  con `flutter pub get --enforce-lockfile`; no actualizar SDK ni lockfile
  incidentalmente.
- `lib/app` compone arranque, módulos y rutas; `lib/core` contiene contratos
  técnicos; las ocho funcionalidades están en `lib/features`. Respetar
  `docs/ep-003/arquitectura.md`: entradas públicas, grafo acíclico e inyección
  por constructor. Añadir domain/data/presentation solo cuando haya código.
- Ejecutar `./scripts/check-quality.ps1` (formato, análisis y pruebas).
  Compilar con `flutter build windows --release --no-pub --dart-define=APP_ENV=test`
  y `flutter build apk --debug --no-pub --dart-define=APP_ENV=test` cuando el
  cambio afecte plataformas. Windows necesita Visual Studio C++; Android SDK
  y JDK 17. Los builds CI usan estas mismas versiones y conservan artefactos
  durante 14 días; no añaden firma de distribución.
- `/` redirige a `/inicio`; Inicio, Estado, Presupuesto, Movimientos,
  Patrimonio y Gestión tienen implementación. Real anual, Indicadores y
  diagnóstico conservan propietarios EP-022/023/025; los filtros EP-024
  también requieren su entrega. No duplicar sus motores ni convertir un
  marcador en una funcionalidad simulada. La matriz de cobertura y la
  validación vigente están en `docs/ep-026/validacion-integral.md`.
- Reutilizar SQLite, migraciones, importadores, lógica financiera y copias
  existentes. Definir los puertos mínimos en su dominio propietario sin usar
  simulaciones del prototipo como servicios reales. Capturas del HTML,
  goldens y capturas del runner nativo deben identificarse por su origen.
- `APP_ENV` admite development/test/production y es público. No poner
  credenciales en dart-defines ni subir SDK, caches, builds o datos personales.
