# MA-TSK-243 · Ensayo nativo N → N+1

El runner `scripts/android-upgrade.mjs` prepara dos APK **release** mediante el
generador T05, con `APP_ENV=test`, paquete invariable y el mismo certificado
efímero. Es una prueba de actualización del almacenamiento y los componentes
reales de la aplicación. Su entrada Flutter muestra un rótulo de ensayo; no
acredita el recorrido visual completo ni una autorización Google real.

## Ejecución

Preparar un AVD nuevo y desechable con una imagen ya instalada. No usar el
teléfono ni el emulador habitual. El runner exige que su nombre coincida con
`--avd`, que haya terminado el arranque y que Autofinance no esté instalada.
Si existe cualquier instalación, se detiene antes de generar claves o APK.
No contiene operaciones de desinstalación, borrado de datos o downgrade forzado.

```powershell
flutter --version
./scripts/check-toolchain.ps1
node --test scripts/tests/android-upgrade.test.mjs
node scripts/android-upgrade.mjs --serial emulator-5580 --avd Autofinance243 --sdk $sdk --jdk $jdk
```

Usar Flutter/Dart/JDK y paquetes fijados en `toolchain.json`. En Windows,
`ANDROID_USER_HOME` puede señalar un directorio de ensayo dentro de `.tools`.
El runner no descarga imágenes ni actualiza SDK, dependencias o lockfile.
Para repetir el recorrido desde cero, preparar otro AVD vacío: se conserva la
instalación anterior con sus datos y sus evidencias.

## Aislamiento y artefactos

Clona el commit local en `.tools/243-native-*/checkout`; excluye cambios sin
confirmar y conserva el commit exacto en `evidence.json`. Sobre esa copia:

- Sustituye exclusivamente la entrada `lib/main.dart` por la fixture versionada.
- Añade un canal nativo de inspección de versión instalada, páginas y Keystore.
- Habilita HTTP en la fixture para el proveedor de control en loopback, con
  puerto aleatorio y autorización efímera por ejecución mediante `adb reverse`.
  No consulta Google ni transmite datos a un servicio externo.
- Aparta Windows dentro del directorio privado del ensayo para que Flutter no
  intente regenerar enlaces de plugins de escritorio al resolver Android.
- Cambia solo en esa copia `pubspec.yaml`: `0.1.0+24301` y `0.1.1+24302`.

Los dos APK N/N+1 pasan los controles T05 de manifiesto, firma, payload, ZIP/ELF de 16 KB
y estabilidad de fuentes. Se conservan sus manifiestos, hashes, certificados
y logs en el directorio privado ignorado. La clave PKCS12 se crea en un
directorio temporal **fuera del repositorio**, sus contraseñas se pasan por
entorno y se elimina en `finally`. Otra clave efímera prepara el rechazo de
firma. No se usa ni modifica el material T02.

Las fuentes de producción no reciben el canal de inspección, la entrada de
ensayo ni la excepción HTTP. Ningún APK, clave o registro de sesión se añade
al repositorio público. El ensayo conserva `completeDelivery=false`.

## Oráculo y recorrido

Importa el CSV sintético EP-001 por su lector/adaptador, previsualización y
confirmador reales: 10 movimientos y 48 partidas. Repite el contenido para
comprobar idempotencia; edita un movimiento importado y crea otro sin categoría
con Discrecionalidad. Registra fotos con valor y cero explícito, un cambio de
liquidez histórica, una copia manual y una restauración completa con su diario
y epoch. Guarda versión remota sintética y una subida pendiente mediante el
estado de sincronización real. Es metadata de un proveedor controlado, sin login.

La sesión/carpeta sintética se escribe una vez mediante el canal Keystore real.
Las verificaciones posteriores solo la leen. Se exige igual alias, fecha de
creación de clave y SHA-256 del **mismo ciphertext**; descifrarlo correctamente
acredita la misma clave, sin reescribir el registro.

El oráculo compara todas las filas de todas las tablas, con UUID, revisión,
procedencia, ordinales, lotes, partidas, fotos y periodos de liquidez. Comprueba
integridad SQLite y claves foráneas. Compara además hashes de los archivos de
copias/catálogos/diarios y `drive-sync`, omitiendo únicamente archivos `.lock`.
Una verificación rechaza una base ausente antes de abrir el store y no siembra
datos: una base nueva, vacía o una revisión reiniciada falla.

Después de N, fuerza parada/reapertura y deja una escritura dentro de la unidad
de trabajo sin confirmar. Mata ese proceso, instala N+1 con `adb install -r`
y exige el estado anterior exacto. Comprueba `versionName/versionCode` desde
PackageManager dentro de la app y conserva `dumpsys package`. Intenta instalar
N y un APK con otra firma, exige el rechazo concreto de Android y vuelve a
comparar el estado completo. Reinicia el dispositivo y verifica otra vez.

Los rechazos SDK/ABI utilizan dos candidatos deliberadamente incompatibles,
fuera de la entrega T05: uno exige API 99 y el otro contiene únicamente una
ABI real del payload que el dispositivo no anuncia. Se construyen con aapt2,
la biblioteca SQLite ya compilada y las herramientas fijadas, con el mismo
paquete/certificado y código 24303. El SDK o ABI debe ser el motivo efectivo
del rechazo, sin quedar oculto por otra firma o por downgrade. No se lanzan.

Finalmente interrumpe el servicio real de restauración justo después del
intercambio de la imagen, antes de confirmar su diario. La siguiente apertura
debe recuperar el estado financiero previo sin tablas parciales ni falso cero.
Solo en ese paso se permite que el catálogo y los diarios evolucionen; deben
conservarse las imágenes existentes, el estado Drive y el registro cifrado.
Una segunda reapertura debe ser estable.

El oráculo de recuperación conserva también cada diario y archivo de soporte
anterior: únicamente `sqlite/local-backups/catalog-a.json` y `catalog-b.json`
pueden cambiar. La desaparición o sustitución de un diario falla el ensayo.

## Matriz y límites

El informe de ejecución debe identificar API, ABI, páginas, versiones y hashes
efectivos. Un build universal y la alineación ZIP/ELF no prueban ejecución en
API 24, 16 KB o teléfono ARM64. El runner declara esos gates pendientes y nunca
etiqueta una entrega completa. Los rechazos ABI/SDK del inspector T01 se
conservan en sus pruebas; los candidatos incompatibles del runner solo se
acreditan si llegan a ejecutarse y Android devuelve el rechazo esperado.

El runner registra por ADB API, versión del sistema, fingerprint, ABI y tamaño
de página **antes** de compilar o abrir SQLite. Conserva el paso en curso,
el hash del runner, PackageManager de N y la salida de cada rechazo. Tras un
recorrido completo solo acredita las API y páginas medidas en esa ejecución;
la ABI traducida de un emulador nunca elimina el requisito de teléfono ARM64.
El CSV servido procede del checkout del commit registrado, no de cambios
concurrentes del directorio principal.

La matriz CI prepara API 24/4 KB, API 36/4 KB y API 36/16 KB mediante la
imagen `google_apis_ps16k`. Pasa `--expected-api` y `--expected-pages` al
runner: una imagen que arranque con otra API o tamaño de página falla antes
de generar claves o APK. Los logs muestran hardware, versiones, hashes y
certificados sintéticos, sin subir APK, claves ni snapshots de sesión.
La definición de esta matriz no acredita su ejecución.

Google real, APK production definitivo y Openbank real corresponden a T09 y
a la entrega EP-014/MA-TSK-131. El proveedor de control no sustituye ninguna de
esas pruebas. La [verificación de ejecución](verificacion-actualizacion.md)
recoge los resultados y las limitaciones del entorno disponible.
