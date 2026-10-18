# MA-TSK-238 · Firma estable y custodia

Release usa `signingConfigs.distribution`, PKCS#12 y una clave estable propia.
No hay fallback debug. Debug sigue con la firma independiente de Android;
los tests y la configuración Gradle no necesitan la clave de distribución.
No cambia paquete, versiones, SDK, permisos, OAuth ni dependencias.

## Identidad pública

Paquete invariable: `com.carlosmg91.myautofinance`.
El [certificado público PEM](../../packaging/android/distribution-certificate.pem)
fija la identidad independiente del APK y no contiene clave privada ni alias.

| Huella del certificado X.509 DER | Valor |
| --- | --- |
| SHA-1, para alta Android Google T03 | `6a1557043d8b3f9fce356a2532aae09f81cd93f3` |
| SHA-256, identidad de actualización | `d6e624f1402fcc0df84cda5373a0b2a89321bd62cb2340a8d69a4a3e663b1951` |

Estas huellas son del certificado, **no del archivo APK ni del PEM**. Cada APK
tiene su propio hash SHA-256. Véase la [evidencia del APK técnico](verificacion-firma.md).
RSA 4096 / SHA256withRSA, vigencia de 36.500 días desde su creación. La identidad
no se cambia para resolver fallos de instalación o acceso a la clave.

## Custodia local de Windows

Ubicaciones predeterminadas, todas fuera del repositorio:

| Ubicación privada | Contenido y protección |
| --- | --- |
| `%LOCALAPPDATA%\MyAutofinance\android-signing\` | `distribution.p12` cifrado con contraseña aleatoria; `credentials.dpapi` cifra contraseña, alias y huella con DPAPI CurrentUser |
| `%USERPROFILE%\MyAutofinance-private-backup\android-signing\android.signing-backup` | Respaldo portátil completo cifrado AES-256-CBC y autenticado HMAC-SHA256, formato v1; incluye PKCS#12 y credenciales dentro del cifrado |
| `%USERPROFILE%\MyAutofinance-private-recovery\android-signing-recovery.key` | Llave aleatoria de recuperación de 64 bytes; permite descifrar el respaldo sin depender del DPAPI original |

Las carpetas se crean con ACL exclusiva del usuario Windows actual, sin
herencia de permisos generales. No se imprimen alias, contraseñas, contenido
DPAPI, respaldo o llave. La llave de recuperación es un secreto de máximo
valor: quien posea llave y respaldo puede firmar actualizaciones. No enviarlos
por chat, correo, Git, CI o incidencias; no ponerlos en dart-defines ni assets.

La copia preparada está en otra carpeta del mismo equipo: **no protege frente
a pérdida del disco/equipo**. Conservar el respaldo cifrado en soporte privado
propio independiente y la llave separada, por ejemplo en otro soporte protegido
o gestor privado ya utilizado. No se ha contratado ni configurado un proveedor
nuevo. Mantener también una copia del certificado público y de estos scripts.
La recuperación comprobada aquí es local en un temporal, no en otro equipo.

`Create` es una operación inicial explícita, nunca parte de un build. Rechaza
material completo/parcial existente, certificado ya fijado y `android/key.properties`;
no regenera ni sobrescribe. Si existe una clave previa de distribución en otra
ruta, detener la creación y provisionarla de forma privada conservando su
certificado; no sustituirla por una nueva ni por debug. La entrega actual ya
tiene identidad: ejecutar `Check`, no `Create`.

```powershell
# $jdk apunta al JDK 17 fijado en toolchain.json.
./scripts/manage-android-signing.ps1 -Action Check -Jdk $jdk
```

`Check` descifra el material mediante DPAPI, comprueba el certificado y restaura
el respaldo en un temporal nuevo de ACL privada. Abre el PKCS#12 recuperado y
genera una petición de certificado firmada con su clave privada; exige la misma
huella que el original y el PEM público. Elimina ese temporal al terminar.
Ni una copia de archivos ni la lectura de un certificado por sí solas acreditan
la recuperación de una clave utilizable.

## Recuperación sin regenerar

Si falla DPAPI o se pierde el equipo, disponer del respaldo cifrado y de su
llave separada. Copiarlos por un canal privado a una carpeta propia. Comparar
con el PEM público obtenido de una fuente confiable independiente. Usar
`Recover` en una **carpeta nueva**; nunca reemplaza el material original:

```powershell
# Solo rutas: no contraseñas ni alias en argumentos o historial.
./scripts/manage-android-signing.ps1 -Action Recover -Jdk $jdk `
  -MaterialDirectory $destinoNuevoPrivado `
  -BackupDirectory $carpetaRespaldoPrivado `
  -RecoveryKeyFile $archivoLlavePrivado
./scripts/manage-android-signing.ps1 -Action Check -Jdk $jdk `
  -MaterialDirectory $destinoNuevoPrivado `
  -BackupDirectory $carpetaRespaldoPrivado `
  -RecoveryKeyFile $archivoLlavePrivado
```

`Recover` autentica el respaldo antes de descifrarlo, comprueba la clave
recuperada y el certificado público y vuelve a proteger las credenciales con
DPAPI del usuario destino. No requiere contraseña en chat. Si faltan respaldo
o llave, o cambia la huella, detenerse; no crear otra identidad. Perder todas
las copias de la clave privada impide actualizar las instalaciones existentes.

## Compilación técnica y fallos

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
./scripts/build-android-signing-check.ps1 -Jdk $jdk -AndroidSdk $sdk
```

El script solo produce una comprobación de firma: APK universal release
`APP_ENV=production`, sin instalar ni publicar. Aísla la configuración Flutter,
selecciona JDK 17, desactiva daemon persistente y configuration-cache y restaura
el entorno del proceso al terminar. Las variables `AUTOFINANCE_SIGNING_*`
transportan material solo al proceso local; no son parámetros públicos de app.
No ejecutar con volcado de entorno, trazas sensibles o publicación de logs.

El contrato para T05 es `AUTOFINANCE_SIGNING_STORE_FILE`,
`AUTOFINANCE_SIGNING_STORE_PASSWORD`, `AUTOFINANCE_SIGNING_KEY_ALIAS` y
`AUTOFINANCE_SIGNING_KEY_PASSWORD`, todos obtenidos del material privado en
memoria. El PEM público fija el certificado esperado; no se acepta una huella
de distribución elegida por el llamante. La tarea Gradle
`:app:verifyDistributionSigning` permite comprobar ese canal sin generar APK.

Con Flutter 3.47, `--no-pub` omite regenerar los registrantes de plugins para
release. El script resuelve primero con `--enforce-lockfile`, genera tooling
con `flutter build apk --release --config-only` y comprueba que el hash del
lockfile permanezca idéntico; después compila con `--no-pub`. La preparación
se ejecuta sin las variables secretas y no edita el SDK ni el Java generado.

Gradle valida los grafos que firman/empaquetan release: ruta absoluta externa,
material utilizable, clave privada, vigencia y coincidencia con el PEM público.
Los errores `APK-SIGNING[MISSING_MATERIAL]`, `INVALID_LOCATION`,
`INVALID_MATERIAL`, `CERTIFICATE_MISMATCH`, `EXPIRED_CERTIFICATE`, `PRIVATE_ONLY`
y `CONFIGURATION_CACHE` explican por qué se detiene; nunca prueban otra firma.
No usar `signingReport` como evidencia pública: puede revelar rutas y alias.

Salida ignorada: `dist-private/android/signing-check/`, APK técnico y JSON de
inspección. `apksigner verify --verbose --print-certs` y aapt2 se ejecutan por
el inspector T01; se exige la huella independiente del certificado. El JSON
siempre declara `completeDelivery=false`. El verificador adicional
`check-android-signing-secrets.ps1 -Apk $apk` busca el material conocido y
archivos privados en todas las entradas descomprimidas del APK.

CI no recibe la clave estable ni genera/publica production. Conserva el build
debug de prueba y comprueba Gradle con una clave efímera independiente que se
elimina al terminar. El canal fixture exige `APP_ENV=test` explícito y una huella
distinta de distribución; no permite reutilizarlo con production. Para una
futura pareja de actualizaciones T07 se debe reutilizar **la misma** fixture
solo en esa pareja, con versiones crecientes, y destruirla después.

## Límites de la entrega

No se instala sobre debug ni se borra soporte privado. Una firma distinta
mantiene bloqueada la transición hasta probar copia externa y recuperación,
según T01/T07/T08. La firma entregada no acredita Google Drive real, OAuth T03,
Openbank, preservación entre versiones, teléfono ARM64 ni aceptación final.
El generador completo corresponde a T05 y debe conservar sus gates propios.

Fuentes oficiales consultadas el 2026-10-18:
[firma y conservación de claves Android](https://developer.android.com/studio/publish/app-signing),
[distribución Flutter](https://docs.flutter.dev/deployment/android) y
[verificación apksigner](https://developer.android.com/tools/apksigner).
