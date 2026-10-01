# MA-TSK-029 · Builds nativos y arranque

## Entrega

`build.yml` compila Windows release en windows-2022 y APK debug en
ubuntu-24.04. Ambos usan APP_ENV=test, Flutter/Dart fijados en toolchain.json
y dependencias con --enforce-lockfile. Android instala los paquetes fijados
mediante el sdkmanager del runner y usa Temurin 17. No requiere dispositivo,
credenciales ni firma de distribución. Windows conserva la carpeta Release
completa; Android conserva app-debug.apk. upload-artifact@v4 falla si no hay
salida y conserva los ZIP 14 días. La consulta pública acredita su existencia;
la descarga desde Actions requiere sesión y acceso GitHub.

README y AGENTS documentan preparación, arranque, calidad, builds, módulos,
rutas vacías y traspaso a diseño y épicas de datos. Se conservan las reglas
funcionales. No se implementan pantallas ni esquema SQLite/importación/Drive.
La entrega EP-002 registra la aprobación visual de MA-TSK-019; este ticket
no amplía su alcance a implementación funcional.

Se corrigió también la inicialización previa de Flutter en toolchain.yml para
que el primer arranque Windows no contamine su salida JSON. El primer intento
Android falló en setup-android antes del build; la descarga de logs públicos
respondió 403. Se sustituyó esa acción por el SDK ya instalado en Ubuntu y
la instalación explícita de paquetes, verificada en la siguiente ejecución.

## Verificación local · 2026-10-01

- actionlint 1.7.12: los tres workflows válidos.
- scripts/check-quality.ps1: Flutter 3.47.0/Dart 3.13.0 correctos, lockfile
  intacto, 22 archivos con formato correcto y análisis sin incidencias.
- 21 pruebas correctas y cuatro variantes adicionales de APP_ENV correctas.
- git diff --check: sin errores.
- No se ejecutaron builds locales por ausencia de SDK Android/Visual Studio;
  los builds nativos se verifican en CI. No se probó ejecución en dispositivo
  ni se descargaron los ZIP con autenticación. No se acredita distribución.

Se usó el ticket completo del usuario; Epic Board no ofrece herramienta en
esta sesión y no se ha modificado el estado del tablero. README y AGENTS
estaban sin seguimiento al comenzar y se incluyen porque completarlos forma
parte explícita de MA-TSK-029. No se incluyeron archivos ajenos.

## Fuentes de implementación

- [Artefactos y retención](https://github.com/actions/upload-artifact).
- [APK y builds Android](https://docs.flutter.dev/deployment/android).

## Ejecución remota acreditada

[Ejecución 36852436838](https://github.com/CarlosMG91/myautofinance/actions/runs/36852436838)
del commit `cfbdee261ff166f8d6feeef04f013b71a9fbcf41`: **success**, ambos
jobs Build windows y Build android completados correctamente el 2026-10-01.
La API confirma artefactos no caducados:

| Destino | Artefacto | Tamaño ZIP | ID |
|---|---|---:|---:|
| Windows | autofinance-windows-cfbdee261ff166f8d6feeef04f013b71a9fbcf41 | 11.149.434 bytes | 11156218369 |
| Android | autofinance-android-cfbdee261ff166f8d6feeef04f013b71a9fbcf41 | 71.552.175 bytes | 11156312671 |

[Calidad 36852437103](https://github.com/CarlosMG91/myautofinance/actions/runs/36852437103)
y [Entorno 36852436891](https://github.com/CarlosMG91/myautofinance/actions/runs/36852436891)
del mismo commit también terminaron con **success**. El commit posterior
solo añade este informe y el enlace README, sin modificar configuración ni código.
