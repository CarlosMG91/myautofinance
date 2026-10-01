# MA-TSK-024 · Módulos y contratos internos

## Estructura y composición

`lib/main.dart` inicia Flutter. `lib/app/app.dart` contiene la aplicación y
expone el catálogo de `lib/app/modules.dart`: es el punto de composición.
La pantalla técnica se conserva; este ticket no implementa vistas de producto,
rutas, localización, SQLite, importadores, OAuth ni operaciones de Drive.

Cada funcionalidad tiene una entrada pública importable en
`lib/features/<nombre>/<nombre>.dart`. Actualmente solo contiene su descriptor
constante `FeatureModule`. El contrato en `lib/core/modules/feature_module.dart`
declara una identidad técnica `ModuleId` y el conjunto de dependencias permitidas.
No es un repositorio ni un modelo de datos persistido. Importar el catálogo no
inicia servicios ni realiza operaciones. Los identificadores son internos Dart;
no se serializan ni establecen identificadores de base de datos.

| Módulo | Responsabilidad futura | Dependencias permitidas inicialmente |
|---|---|---|
| `monthly_status` | Estado del mes, comparación real/presupuesto | `movements`, `budget` |
| `wealth` | Fichas y fotos manuales de cuentas, deudas y carteras | Ninguna |
| `budget` | Partidas y presupuesto anual | Ninguna |
| `actual_spending` | Consulta de reales anuales, incluidos ingresos y transferencias | `movements` |
| `indicators` | Catálogo y resultados de indicadores | `wealth`, `budget` |
| `movements` | Registro y consulta de movimientos reales | Ninguna |
| `importing` | Previsualización y confirmación de cargas históricas | `movements`, `budget` |
| `synchronization` | Copias completas manuales y protección de la base local | Ninguna |

Estas dependencias son permisos para futuros contratos, no servicios ya
implementados. No se importa código de una funcionalidad solo para declarar
el permiso: se evita acoplar los módulos vacíos. El catálogo importa todas sus
entradas públicas, por lo que arranque y pruebas ya comprueban su compilación.

## Reglas de dependencias

- `app` compone módulos y adaptadores; ninguna funcionalidad importa `app` ni
  `main.dart`. `main.dart` reexporta `AutofinanceApp` para conservar el import
  de la prueba de arranque de MA-TSK-023.
- `core` solo depende de Dart y de sí mismo. Aloja contratos técnicos pequeños
  compartidos, no una colección de reglas financieras.
- Los módulos consumen otros módulos únicamente a través de su entrada pública
  y dentro del conjunto declarado. No se accede a archivos internos ajenos.
  El grafo debe seguir siendo acíclico; modificarlo exige revisar consumidores.
- Crear `domain/`, `presentation/` y `data/` dentro de un módulo únicamente
  cuando haya código que ubicar. No crear carpetas vacías ni archivos de relleno.
- Dominio depende de Dart, contratos comunes y contratos de dominio públicos;
  nunca de Flutter, presentación o datos. Datos implementa puertos de dominio
  y no importa presentación. Presentación consume dominio, sin importar datos.
  `app` conecta implementaciones concretas mediante inyección por constructor.
- Las entradas públicas exportarán únicamente contratos necesarios; nunca
  adaptadores de datos o detalles de widgets que inviertan estas reglas. La
  revisión debe comprobar también dependencias transitivas de esas exportaciones.

`test/architecture_test.dart` verifica el catálogo completo, unicidad,
dependencias resolubles y ciclos. Recorre además las directivas Dart de `lib`
(imports, exports, parts y alternativas condicionales), detecta ciclos reales,
fronteras infringidas y dependencias entre capas. La prueba no sustituye la
revisión semántica de los futuros contratos públicos.

## Decisiones para las siguientes épicas

1. Una sola aplicación y módulos por funcionalidad, sin paquetes separados,
   contenedor de servicios ni biblioteca de estado adicional. Las capas se
   incorporan cuando aportan implementación. Esta base no elige aún gestión
   de estado o estrategia de acceso SQLite.
2. Se separan movimientos reales y presupuesto conforme a EP-001 §§2–3.
   Patrimonio no consume movimientos: sus fotos son manuales (§4). Importación
   es un módulo separado que coordinará ambos tipos sin confundir sus signos
   (contrato CSV). No se adelantan DTO, métodos CRUD o transacciones.
3. Indicadores consume patrimonio y presupuesto; el contrato extensible de
   EP-001 §6.1 se concretará con el primer cálculo. No se crean fórmulas,
   resultados ficticios o un catálogo financiero vacío con valores inventados.
4. Sincronización no depende de cada módulo de negocio: intercambia la base
   completa (§7.1). Su futuro puerto de copias locales se definirá cuando exista
   infraestructura real y se conozcan integridad, compatibilidad y reemplazo.
   Nunca se inicia desde el catálogo o el arranque.
5. No se define ahora una interfaz de consulta financiera sin tipos reales.
   `FeatureModule` es el único contrato común necesario en esta entrega. Al
   implementar funciones, sus puertos mínimos vivirán en el dominio propietario
   y se exportarán desde la entrada pública. Por ejemplo, la propuesta de
   presupuesto basada en reales requerirá añadir `budget → movements`, revisar
   el grafo y sus pruebas, sin crear una dependencia inversa.

Las reglas funcionales no cambian. Las pruebas financieras futuras usarán
`docs/ep-001/casos-referencia.md` y datos sintéticos. La implementación visual
continúa sujeta a la aprobación explícita de MA-TSK-019.

## Verificación y entrega

Se utiliza el ticket completo facilitado por el usuario. No hay herramienta
Epic Board disponible en esta sesión; no se ha consultado ni cambiado el estado
del tablero. `AGENTS.md` y `README.md` estaban sin seguimiento al comenzar y no
pertenecen al commit de este ticket.

Comprobaciones locales del 2026-10-01, con el SDK fijado en `.tools/flutter`:

- `dart format lib test`: aplicado; verificación final sin cambios.
- `flutter analyze`: sin incidencias.
- `flutter test --no-pub`: tres pruebas correctas (arranque y dos de arquitectura).
- `git diff --check`: sin errores de espacios.

No se ejecutaron builds ni arranques nativos: este ticket cambia composición
Dart, no plataformas. MA-TSK-023 ya documenta la falta de Visual Studio y Android
SDK en esta máquina; la prueba de widgets no demuestra el arranque nativo.
No se verificaron operaciones financieras, persistencia ni Drive, que aún no
existen en estos módulos.
