# MA-TSK-240 · Recorrido privado Android · v1

Propuesta del 2026-10-18, **pendiente de aprobación humana explícita**.
No hay `approvedAt` en el ticket consultado en Epic Board. No se aprueba ni
se completa el ticket automáticamente y no se implementan tickets posteriores.
La aprobación de este guion habilita la guía T08; no acredita pruebas nativas
ni la entrega final, ni condiciona técnicamente firma/build/OAuth independientes.

- Artefacto conservado: [mockup-instalacion-v1.html](mockup-instalacion-v1.html).
- Ruta revisable: [/mockups/autofinance-ma-tsk-240-v1.html](http://localhost:4310/mockups/autofinance-ma-tsk-240-v1.html).
- SHA-256 HTML: `9f1fe56c6a8668c6f831216e6f69bf0e461bd45706203aea66a00ca814efdefb`.
- Contexto consultado: API de Epic Board, **My autofinance / MA-EPIC-236 /
  MA-TSK-240**, contrato MA-TSK-237, evidencia OAuth MA-TSK-239 y EP-026 v1.
  El bloqueo externo de Google no se disimula como una conexión real.

## Guion para revisar

1. Archivo privado: nombre, versión, código, paquete y ficha de entrega. Los
   ejemplos `0.1.0+1` → `0.1.1+2` no son entregas production acreditadas.
2. Salida al instalador oficial: permiso por fuente cuando corresponde,
   decisión del usuario, retorno y cancelación. No hay instalador propio.
3. Apertura en Inicio y acceso por Más → Gestión, según EP-026.
4. Google Drive: conectar, cancelar autorización, volver, subir manualmente y
   revisar/cancelar descarga sin transferencias reales ni sincronización automática.
5. CSV y Openbank XLS: selector oficial, cancelar sin importar, volver a la
   revisión del importador y a Gestión/Inicio. No se duplica lector ni motor.
6. Actualización compatible: contraste con origen realmente instalado, mismo
   paquete/certificado y versionCode mayor; instalación sobre la anterior y
   conservación esperada de datos/copias/estado Drive/sesión Keystore.

El selector de estados añade firma distinta/debug, instalación cancelada,
sin Google Play Services y versión no superior. Una firma distinta o identidad
no verificada detiene el cambio: exige copia externa validada y recuperación
demostrada con firma destino antes de tocar origen. No se ofrece desinstalar,
borrar datos ni forzar downgrade. La copia en soporte privado no basta.
Sin Play Services se conserva el uso local; no se presenta Drive deshabilitado
como entrega final completa. Una sesión conservada puede necesitar reconexión
por caducidad o revocación de Google.

## Fuentes y política vigente

Consulta oficial realizada el **18/10/2026** para entrega directa privada en
España. El guion enlaza estas fuentes dentro del propio artefacto:

- [Distribución alternativa Android](https://developer.android.com/distribute/marketing-tools/alternative-distribution):
  canales fuera de Play y permiso por fuente en API 26+. Para API 24/25, si
  el dispositivo exige habilitar fuentes globalmente, el guion detiene y pide
  una vía compatible; no prescribe cambiar esa protección global.
- [Verificación Android](https://developer.android.com/developer-verification)
  y [FAQ oficial](https://developer.android.com/developer-verification/guides/faq):
  la fase inicial de septiembre de 2026 se limita a tiendas participantes en
  Brasil, Indonesia, Singapur y Tailandia sobre Android certificado 7+; la FAQ
  distingue la instalación directa de esa fase. La expansión de 2027 requiere
  revisar de nuevo las condiciones. No se impone Play Store, pago o verificación
  global como requisito actual de este caso en España.

No se indica desactivar Play Protect, root o permisos amplios de almacenamiento.
No se promete texto exacto ni control de políticas OEM. La política EP-029 de
backup/traslado automático es explícita y conserva la copia manual, sin prometer
restauración de secretos de otro dispositivo ni control universal de fabricantes.
No se cambia hosting ni visibilidad; solo se publica HTML sintético en el
servidor de mockups existente. Ningún APK, clave, token o dato real se publica.

## Verificación y límites

Verificador reproducible: [verificar-mockup.mjs](verificar-mockup.mjs).
Usa un módulo Playwright ya disponible y Chrome instalado, sin instalar SDK,
actualizar dependencias ni cambiar el lockfile:

```powershell
$env:PLAYWRIGHT_MODULE='<ruta al módulo playwright existente>'
$env:CHROME_PATH='C:/Program Files/Google/Chrome/Application/chrome.exe'
node docs/ep-029/verificar-mockup.mjs
```

Comprobados HTTP 200, instalación/cancelación, conexión/cancelación de Google,
subida simulada, revisión/cancelación de descarga, ambos selectores y retorno,
actualización ilustrada, bloqueo de firma, falta de servicios Google, Atrás
propio y Atrás del navegador. 150 combinaciones de cinco anchos
(320/360/412/840/1440), texto 100/200 %, pasos y estados, sin desbordamiento
horizontal; cero errores JavaScript. Foco visible, controles nativos y foco
en el título al navegar.

Capturas **del HTML en Chrome**, revisadas visualmente; no son capturas de
Flutter, goldens ni del teléfono:

- [Escritorio](mockup-escritorio.png).
- [320 px, actualización](mockup-320.png).
- [320 px y texto 200 %, firma incompatible](mockup-320-200.png).

No se ha instalado ni actualizado un APK ni probado TalkBack, gestos Android,
permisos/diálogos OEM, almacenamiento nativo, conexión Google, recuperación,
lector Openbank real o conservación efectiva. Estas comprobaciones pertenecen
a sus entregas y a T07/T09; el ejemplo preservado en memoria no las acredita.
La lectura real de Openbank sigue requiriendo MA-TSK-131 antes de T09. No se
generan builds de distribución porque el ticket solo añade documentación y
HTML de revisión.

### Calidad general del checkout

`flutter --version` y `check-toolchain.ps1`: Flutter 3.47.0 / Dart 3.13.0
correctos. Se ejecutó `scripts/check-quality.ps1`: la primera resolución se
detuvo por restricción de red con pub.dev; se repitió con acceso autorizado.
Lockfile conservado, 505 archivos de formato sin cambios y análisis sin
incidencias. La suite general detectó fallos en `pending_lifecycle_test.dart`
(EP-015, Windows tabla y Android tarjetas): `Bad state: No element`, en
`pending_lifecycle_journey.dart:82/144`. Estos archivos no son cambios de
MA-TSK-240 y no se modifican; no se afirma que la calidad global esté verde.
El script no llega a la matriz posterior de variantes APP_ENV si falla la suite.
Log local ignorado: `.tools/ma-tsk-240-quality.log`. La comprobación general
se realiza en el checkout compartido con cambios concurrentes excluidos del
commit propio; las pruebas específicas del HTML sí pasan.
