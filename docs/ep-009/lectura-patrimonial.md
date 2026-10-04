# MA-TSK-075 · Lectura patrimonial mensual

Ticket consultado el 2026-10-04 en `GET http://localhost:4310/api/data`,
tablero **My autofinance**. Se aplican EP-001 §4 y caso D, las consultas de
MA-TSK-039, la composición de MA-TSK-071 y la entrega aprobada de EP-002.

## Contrato público

`features/wealth/wealth.dart` exporta `WealthReading` y `WealthTotals`.
`WealthManagement.readMonth` y `WealthController.readMonth` entregan la lectura
del mes; `readYear` entrega doce lecturas independientes e inmutables. Se
reutilizan `WealthRepository.read/readYear`, sin una segunda consulta de fichas:
los valores y pendientes ya contienen vigencia y liquidez efectiva del mes en
una lectura consistente. El controlador resuelve la sesión en cada consulta,
igual que las lecturas anteriores de fotos, que conservan su API.

```dart
final reading = await controller.readMonth(Month(2026, 2));
final status = reading.status;
final pending = reading.pending;
final totals = reading.totals; // null = sin dato; no suma parcial
final liquid = reading.liquidAssetsCents; // null o céntimos, incluido cero
```

La lectura conserva foto, mes, valores individuales y fichas pendientes.
Ausente e incompleta conservan sus estados diferenciados y `totals == null`,
para presentar los motivos «Sin dato: falta foto patrimonial» y «Sin dato: foto
patrimonial incompleta» ya utilizados por la ruta existente. Una cabecera vacía
o un mes sin fichas ni valores es ausente, no un total cero. Cero registrado sí
completa una ficha. No se añaden subtotales parciales.

Solo la foto completa suma cuentas y carteras por liquidez en
`liquidAssetsCents`, `mediumAssetsCents` e `illiquidAssetsCents`. `assetsCents`
suma esos tres grupos; `debtsCents` conserva la magnitud positiva de las deudas;
`netWorthCents = assetsCents - debtsCents` admite resultado negativo. Las
magnitudes no negativas proceden del contrato de escritura existente, sin
convertir el signo de una deuda ni aplicar valor absoluto. Todos los cálculos
usan céntimos enteros y no dependen de movimientos.

`liquidAssetsCents` queda disponible como entrada para indicadores futuros:
exige la foto completa y no descuenta deudas. También puede construirse la
lectura desde una foto pública mediante `WealthReading.fromSnapshot`. No se
implementa ningún indicador ni se añade dependencia a presupuesto. Una foto
completa con activo sin clasificación mensual incumple el puerto y se rechaza,
en lugar de omitirlo de los activos.

No hay suma anual, arrastre de valoraciones ni uso de la clasificación actual
para fotos pasadas. El esquema, repositorios, lockfile y mockup no cambian.
La vista financiera completa y sus formularios siguen en sus tickets de EP-009;
este ticket entrega el modelo de lectura que consumirán.

## Verificación

`test/wealth/wealth_reading_test.dart` añade siete pruebas con SQLite real y
datos sintéticos: caso D completo; corrección de febrero con enero intacto;
liquidez efectiva y corrección histórica; altas y bajas inclusivas; cero y
cabecera vacía; las tres liquideces con precisión de céntimos y neto negativo;
doce meses independientes, revisión intacta, calendario hasta diciembre de
9999 y controlador que vuelve a resolver la sesión reemplazada.

Caso D comprobado: enero líquidos 9.000, medios 10.000, activos 19.000, deudas
5.000 y neto 14.000 EUR. Febrero parcial conserva ahorro y cartera pendientes
sin totales; completo con ahorro cero produce activos 16.700 y neto 11.900 EUR;
corregir cuenta a 6.300 produce neto 12.000 EUR sin cambiar enero.

No se requieren builds: el cambio es de dominio y consultas Dart, sin cambios
nativos o de pantallas. No se acredita recorrido visual en dispositivos.

Resultado local del 2026-10-04: `scripts/check-quality.ps1` correcto con Flutter
3.47.0/Dart 3.13.0; resolución con `--enforce-lockfile`, formato, análisis sin
incidencias, 871 pruebas y las cuatro variantes adicionales de `APP_ENV`.
`pubspec.lock` y `toolchain.json` permanecen intactos. La comprobación completa
se ejecutó fuera del aislamiento para permitir acceso a pub.dev y los bloqueos
SQLite de las pruebas existentes. `git diff --check` correcto.

Entrega limitada a los seis archivos de este ticket en la rama configurada
`ticket/ma-tsk-071`; los cambios concurrentes de otros tickets quedan fuera.
La consulta administrativa de Epic Board no modifica su estado ni cierra EP-009.
