# MA-TSK-223 · Exportación y portabilidad · propuesta v1

Fecha: 2026-10-17. **Pendiente de aprobación humana explícita** en Epic Board.
La aprobación de EP-026 v1 no aprueba este suplemento ni habilita MA-TSK-224.
No se han implementado pantallas Flutter ni tickets posteriores.

Artefacto autónomo: [exportacion-v1.html](exportacion-v1.html).
Publicación: `/mockups/autofinance-exportacion-v1.html` en Epic Board.
SHA-256 del HTML: `f97a9e92897898ecf32c5fd15f6c2c757c54aa7e4133f95e274f73f2c580db12`.
El estado de aprobación lo determina la decisión humana del tablero; este
documento conserva el estado de entrega de la propuesta.

## Referencias consultadas

- `GET http://localhost:4310/api/data`, My autofinance, MA-EPIC-218 y MA-TSK-223.
  T01–T04 entregados; UI MA-TSK-224 pendiente de esta aprobación y servicios.
- `lib/ui/autofinance_ui.dart`, `lib/ui/src/tokens.dart`, prototipo EP-026 v1,
  su aprobación y tokens visuales. Se reutilizan colores, Roboto local,
  radios, espaciado, formularios, tarjetas y controles del prototipo vigente.
- EP-001, signos, entidades separadas y fotos manuales; contrato EP-027 v1 y
  guardado nativo MA-TSK-222. No se cambia ninguno de estos contratos.

## Recorrido de revisión

1. Desde Gestión, abrir **Exportar datos**. Elegir todo o rango de meses.
   Probar inicio posterior al final y después un único mes válido. El resumen
   sigue la selección. Revisar signos, diferencia con CSV histórico, siete CSV,
   diccionario, metadatos y contexto completo incluso fuera del periodo.
2. **Guardar ZIP** inicia captura, generación y verificación. Abrir el panel
   superior del prototipo para elegir resultado Windows/Android. Avanzar las
   fases con el control de muestra. No hay porcentajes ni esperas inventadas.
3. Revisar el selector cancelado, nombre existente, generación fallida,
   escritura fallida y documento incompleto. Se conserva la selección para
   reintentar. Un nombre existente exige elegir otro nombre/destino.
4. Cancelar antes del guardado; durante escritura solicitar salir y esperar.
   El resultado sigue al sistema, puede terminar guardado. Solo el resultado
   de guardado confirmado muestra la vista de éxito. Android contempla que
   el proveedor no facilite ubicación, sin inventar una ruta del dispositivo.
5. Cambiar un periodo y pulsar Volver, Escape o Back del navegador: continuar
   o descartar borrador. Nada elimina archivos guardados. Si el selector está
   abierto, Escape/Back cancela el selector. Los diálogos mantienen el foco.
6. Abrir **Exportar copia completa**. Periodo deshabilitado/no aplicable;
   siempre incluye todo el histórico, aunque antes se eligiera rango CSV.
7. Abrir guía y volver al origen. Recuperación significa verificar y extraer
   a carpeta nueva Windows, después consultar SQLite estándar en solo lectura,
   también para ZIP Android. No sustituye la instalación ni reconstruye CSV.
8. Revisar 320 px, texto 200 %, teclado y lector de pantalla. Los controles
   de revisión quedan en un panel aparte y no son ajustes del producto.

## Qué representa el artefacto

HTML de interacción con información sintética; no contiene cuentas personales,
extractos, SQLite, ZIP, credenciales ni conexiones. No genera ni descarga archivos.
Selector y guardado son simulados y están identificados como tales, también
en la vista de éxito. La UI real solo podrá mostrar éxito tras `ExportSaved`.
Los resúmenes son contenido previsto, no conteos certificados de una captura.
No presentan totales patrimoniales ni convierten ausencias en ceros.

El mockup no llama al catálogo privado de copias ni a Drive. No constituye un
segundo motor financiero/snapshot. La guía es una vista previa de lectura;
MA-TSK-225 entregará los comandos reales y MA-TSK-226 acreditará su ejecución.

## Reproducir

```powershell
node docs/ep-027/prototipo/generar.mjs
node docs/ep-027/prototipo/generar.mjs --check
node --check docs/ep-027/prototipo/interacciones.js
# Playwright y Chromium/Chrome disponibles en el entorno:
$env:PLAYWRIGHT_MODULE = '<ruta al paquete playwright>'
$env:CHROME_PATH = '<ruta a chrome.exe>'
$env:MOCKUP_URL = 'http://localhost:4310/mockups/autofinance-exportacion-v1.html'
node docs/ep-027/prototipo/verificar.mjs
```

Sin `MOCKUP_URL` las pruebas abren el HTML local. El generador incluye tokens,
estilos y fuentes de EP-026 con su licencia en `docs/ep-026/identidad/assets`.
No necesita red para usar el artefacto.

## Verificación de entrega

- Generación reproducible, sintaxis JavaScript y recorridos Playwright: correctos.
  Valida ambos modos, meses inválidos/iguales, actualización del resumen,
  selección conservada, diálogos y foco, Back/Escape, cancelaciones, cinco
  resultados, guía y Android sin ruta ficticia. Sin errores JavaScript.
- Sin desbordamiento horizontal a 320/360/412/840/1440 px. A 320 px y texto
  200 %: formulario CSV/copia, guía, progreso, resultado y diálogo. Los diálogos
  largos permiten desplazamiento vertical y empiezan mostrando el título.
- Capturas inspeccionadas: [Windows](windows.png), [rango](windows-rango.png),
  [320 px](android-320.png), [resultado 200 %](android-320-texto200.png),
  [rango 200 %](android-320-rango-texto200.png),
  [decisión de salida 200 %](android-320-abandonar-texto200.png).
  **Todas son capturas del HTML en Chrome de escritorio con viewport adaptado**;
  no son capturas de Flutter ni de un dispositivo Android.
- HTTP 200 y contenido publicado idéntico al HTML conservado.
- Flutter 3.47.0 / Dart 3.13.0 comprobados. `flutter analyze --no-pub
  --fatal-infos --fatal-warnings`: sin incidencias. `flutter test --no-pub
  test/ui/kit_test.dart`: **18 pruebas correctas**.
- `scripts/check-quality.ps1` ejecutado: comprobó versiones, pero se detuvo
  en `flutter pub get --enforce-lockfile` al consultar
  `https://pub.dev/api/packages/http/advisories` (SocketException 10057).
  No se acredita batería completa ni se actualiza SDK/lockfile.
- Sin cambios de plataforma ni módulos Flutter: no se compilan builds para
  este HTML. Pendientes: evaluación humana visual y con lector de pantalla,
  Back nativo, texto del sistema y guardado real en Windows/Android. La prueba
  del navegador no sustituye MA-TSK-224/226 ni la aprobación explícita.

Los archivos concurrentes de otros tickets permanecen fuera de esta entrega.
