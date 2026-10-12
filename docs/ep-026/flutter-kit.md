# MA-TSK-208 · Kit Flutter compartido

Entrada pública: `package:myautofinance/ui/autofinance_ui.dart`. Tema claro
aplicado en `AutofinanceApp`; es-ES y EUR mantienen la configuración existente.
No se modifican pantallas, consultas, motores, rutas ni servicios de otros
tickets. El shell entregado es composición visual; T06 conecta navegación,
guards, sesión, Back, recuperación, foco y restauración del scroll.

La integración conserva el rol de etiqueta 14 para menús y navegación
heredados, y botones de icono de 48×48, evitando que el nuevo tema reduzca
el espacio útil en los recorridos existentes al 200 %. La fixture que ejecuta
recuperación en un proyecto temporal copia también los assets del pubspec;
no se modifica su comportamiento financiero ni la lógica de recuperación.

## Fuente visual y autorización de esta entrega

Se han leído identidad/tokens-visuales.json, identidad-visual.md, contrato del
shell/contexto, traspaso y prototipo v1, y observado sus capturas renderizadas.
La instrucción de implementación facilitada por el usuario declara MA-TSK-207
**completado** como requisito de MA-TSK-208 y autoriza expresamente implementar
este ticket. Se usa esa instrucción vigente. Los registros locales de T04
todavía dicen «pendiente»; esta entrega no inventa una revisión humana del
HTML, no cambia su hash/versión ni declara aprobado otro alcance. El registro
del tablero y la evidencia local de T04 deben reconciliarse por su propietario.
No hay herramienta Epic Board disponible en esta sesión: se consultó el ticket
completo aportado en el mensaje; no se cambia el estado del tablero.

## API para T06 y consumidores

| API | Contrato |
| --- | --- |
| AfTokens / AfTheme.light | Tokens normativos, Roboto local 400/500/700, foco, controles ≥48 dp, variante de alto contraste. ThemeMode.light, sin tema oscuro. |
| AfAmount / AfChartValue | EUR entero en céntimos; meses finitos; ausencia con motivo. Signo tipográfico, cero sin signo, céntimos visibles; no conversión de presupuesto CSV. |
| AfCard / AfSummaryCard / AfMoneyText | Normal, real petróleo, presupuesto violeta; etiqueta, cifra, contexto y callback de detalle. AfComparisonState lo entrega el propietario, no se deduce desde el signo. |
| AfValueRow / AfNumericText | Cifras tabulares alineadas a derecha en PC; texto y valores refluyen en Android y con texto ampliado. Slots para conceptos, categorías, fichas y acciones. |
| AfAction / AfFormField / AfStatus | Acciones rotuladas, motivo de deshabilitado, etiqueta/ayuda persistentes, validator/controlador/foco inyectados, error y borrador del formulario propietario. Carga, vacío, ausencia, pendiente, éxito, divergencia y fallo diferenciados. |
| AfPeriodSelector | Lista de opciones y selección controlada por ID; callback del consumidor. El kit no avanza meses ni altera consultas. |
| AfPageHeader / AfPageLayout / AfResponsiveGrid | Encabezado/contexto/acciones, contenido máximo 1200 y reflujo a una columna. |
| AfNavItem / AfPageSlots / AfShell | Firmas normativas de T02. Selección y retorno delegados; espera el callback antes de admitir otra selección, sin cambiar el destino por su cuenta. Periodo y utilidades visibles. |
| AfDetailTable / AfDetailRow | Caption/columnas/celdas aportados, cabecera y concepto persistentes, scroll interno, expansión independiente y tres niveles. No agrega totales ni carga descendientes. |
| AfIcons / AfIcon | Contornos originales CustomPainter. IconData se usa como identificador; **renderizar con AfIcon**, no con Icon. No hay fuente de iconos externa. Iconos decorativos excluidos de semántica; acciones llevan texto/tooltip. |

El kit depende exclusivamente de Dart/Flutter y de sí mismo. `core` sigue siendo
Dart puro. Las funcionalidades solo pueden importar la entrada pública del kit
desde `presentation`; ni `domain` ni `data` pueden hacerlo. La prueba de
arquitectura verifica estas fronteras y el grafo acíclico.

`AfShell` posee el scroll de página. `AfPageSlots.body` debe tener altura natural;
no colocar ListView/Expanded sin límite en ese slot. Usar contenido no
desplazable o un viewport acotado como AfDetailTable. Los controladores,
validadores, loaders y callbacks se inyectan por constructor y se liberan en
su propietario. Para formularios reales, el propietario valida y enfoca el
campo inválido mediante el FocusNode, conserva el borrador y protege la salida.
El kit no intercepta Back ni promete restauración automática.

AfDetailTable recibe una celda por columna y profundidad 0–2. Sus celdas se
componen con AfMoneyText/AfAction (o widgets de altura compatible); el
consumidor aporta nombres accesibles completos, incluidos columna, periodo,
concepto y origen para los enlaces. Su scroll horizontal es la única excepción
a la lectura sin desplazamiento lateral. Los IDs de registros/categorías nunca
se deducen desde etiquetas.

## Gráficos sin cálculo financiero

No se añade una dependencia gráfica. CustomPainter representa valores ya
calculados, con escala común normalizada antes de restar, cero explícito y
datos equivalentes **siempre visibles**. Los lienzos decorativos se excluyen de
semántica para evitar anuncios duplicados. Las filas accionables admiten tacto,
Tab/Enter y foco; también funcionan sin hover. A 200 % o sin ancho suficiente
se muestran los datos en texto sin perder ninguna cifra. No hay animaciones
de cifras ni gráficos; las transiciones de acciones usan duración cero cuando
el sistema solicita reducción de movimiento o navegación accesible.

- AfBarChart: barras negativas a izquierda y positivas a derecha; un cero es
  un punto en el origen, una ausencia no produce barra. AfChartValue.unbudgeted
  presenta «Sin presupuesto», distinto de cero y de una foto ausente.
- AfTimeChart: índices mensuales absolutos, únicos, ordenados. Unir únicamente
  muestras presentes en meses consecutivos. Ausencia explícita y meses omitidos
  interrumpen la línea. Real continuo y presupuesto discontinuo; ninguna
  interpolación, arrastre de fotos o relleno. EUR y meses no comparten eje.
- AfDistributionChart: recibe foto completa/ausente/inválida, activos y total
  de su propietario. Valida solo coherencia estructural (magnitudes, IDs y suma
  contra total entregado) antes de dibujar. No calcula ni publica otro total.
  Deuda se presenta separada y nunca se resta del denominador. Total cero
  conserva todas las cifras y explica que la distribución no es representable.
  Foto incompleta no expone subtotales parciales.

## Ejemplo ejecutable y verificación visual

`flutter run -t examples/ui_kit.dart --dart-define=APP_ENV=test`

Galería sintética sin SQLite ni red: cifras de EP-001, tarjetas/filas/estados,
selección, expansión, formulario y los tres gráficos. Las interacciones están
rotuladas como demostración; seleccionar otro periodo no pretende recalcular
fixtures fijos. Es un ejemplo del kit, no una pantalla de producto ni servicios
copiados desde JavaScript del prototipo.

Las imágenes `test/ui/goldens/` proceden del motor de renderizado Flutter y se
han inspeccionado visualmente contra las capturas HTML: Windows, Android,
texto 200 %, gráficos firmados/con huecos y ceros/ausencia. Son goldens de
widgets, **no capturas de una app instalada**. No acreditan TalkBack/Narrador,
Back nativo, SQLite, Drive ni integración de las cinco pantallas. Las capturas
nativas y recorridos integrados de la épica pertenecen a T14.

Comandos reproducibles:

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub test/ui test/architecture_test.dart
./scripts/check-quality.ps1
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

Actualizar goldens solo después de revisar el resultado: `flutter test --no-pub
--update-goldens test/ui/goldens_test.dart`. SDK y lockfile permanecen fijados;
no se han añadido paquetes. Fuentes y licencia se verifican byte a byte con
la entrega de identidad. Resultados finales de la ejecución se registran al
final de este documento.

## Resultado · 2026-10-12

- Flutter 3.47.0 / Dart 3.13.0: verificador de toolchain correcto. Resolución
  con `--enforce-lockfile` correcta; también se comprobó offline tras la
  restricción de red inicial. Sin cambios en SDK, paquetes o lockfile.
- `./scripts/check-quality.ps1`: correcto, formato sin cambios, análisis sin
  incidencias, **1.663 pruebas** y cuatro ejecuciones adicionales del arranque
  con development/test/production/invalid-synthetic.
- Kit/goldens/arquitectura: **25 comprobaciones** correctas. Cinco imágenes
  inspeccionadas, sin glifos ausentes ni overflow de la galería entre 320–1440
  y texto 100/200 %. Contraste de todos los pares normativos, cifras, semántica,
  foco, teclado, objetivos 48 dp, selector, borrador/error y matriz comprobados.
- Regresiones de presupuesto anual, Estado, Drive y procesos de recuperación:
  **50 casos** correctos después de ajustar roles de etiqueta/padding y el
  bundle de la fixture temporal. No se redujo texto del sistema para pasar.
- `node docs/ep-001/verificar-casos.mjs`: OK; signos y referencias financieras
  permanecen vigentes.
- Build Windows release y APK debug de la entrada principal con APP_ENV=test:
  correctos. Android usa **Temurin JDK 17.0.20.1** en configuración local aislada,
  sin cambiar la configuración global. Galería `examples/ui_kit.dart` compilada
  además en Windows release, incluidos todos los componentes/iconos en AOT.
  El host tiene Visual Studio 2026 Insiders preinstalado; no se afirma haber
  compilado localmente con Visual Studio 2022 ni haber actualizado el toolchain.
- Las primeras compilaciones en sandbox fallaron por acceso MSBuild/caché
  Gradle; la ejecución autorizada fuera del sandbox completó las compilaciones.
  No queda un bloqueo de build. No se ejecutaron lectores de pantalla nativos
  ni recorridos en una app Android instalada: permanecen para integración T14.

Entrega limitada a archivos propios de MA-TSK-208 en la rama configurada
`ticket/ma-tsk-113`; README, backend Drive y prototipos concurrentes se excluyen.
Los artefactos de build y logs locales no forman parte del repositorio.
