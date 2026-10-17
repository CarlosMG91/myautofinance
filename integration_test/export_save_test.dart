import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myautofinance/features/synchronization/data/data_export_zip.dart';
import 'package:myautofinance/features/synchronization/data/native_export_saver.dart';
import 'package:myautofinance/features/synchronization/domain/data_export.dart';
import 'package:myautofinance/features/synchronization/export_saving.dart';
import 'package:path_provider/path_provider.dart';

// Recorrido interactivo: cancelar, guardar, repetir nombre y perder el origen.
// Solo ZIP genérico sintético; no abre SQLite, finanzas, Drive ni app de producto.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Selector nativo y ZIP sintético', (tester) async {
    final temp = await (await getTemporaryDirectory()).createTemp(
      'export-save-test-',
    );
    final payload = File('${temp.path}/prueba.md');
    final output = await payload.open(mode: FileMode.write);
    for (var i = 0; i < 64; i++) {
      await output.writeFrom(Uint8List(65536)..fillRange(0, 65536, i));
    }
    await output.close();
    final zip = File('${temp.path}/prepared.zip');
    final cancellation = DataExportCancellation();
    await createAndVerifyExportZip(
      stage: temp,
      zip: zip,
      files: [
        await describeExportFile(payload, 'prueba.md', cancellation, null),
      ],
      cancellation: cancellation,
      maxBytes: 8 * 1024 * 1024,
    );
    final hash = (await sha256.bind(zip.openRead()).first).toString();
    final zipSize = await zip.length();
    final saver = NativeExportSaver();
    final name =
        'autofinance-prueba-${DateTime.now().toUtc().millisecondsSinceEpoch}.zip';
    ExportSaveRequest request(String path) =>
        ExportSaveRequest(zipPath: path, suggestedName: name);
    final invalid = await saver.save(request('${temp.path}/missing.zip'));
    expect(
      (invalid as ExportSaveFailed).code,
      ExportSaveFailureCode.invalidSource,
    );
    Future<ExportSaveResult> stage(
      String label, {
      bool loseSource = false,
    }) async {
      // ignore: avoid_print
      print(label);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Text(label))));
      await tester.pump();
      // El runAsync permite mensajes nativos y temporizadores reales.
      return (await tester.runAsync(() async {
        final timer = loseSource
            ? Timer(const Duration(seconds: 3), () {
                if (zip.existsSync()) zip.deleteSync();
              })
            : null;
        try {
          return await saver.save(
            loseSource
                ? ExportSaveRequest(
                    zipPath: zip.path,
                    suggestedName: name.replaceFirst('.zip', '-3.zip'),
                  )
                : request(zip.path),
          );
        } finally {
          timer?.cancel();
        }
      }))!;
    }

    try {
      expect(
        await stage('MA-TSK-222: CANCELAR selector'),
        isA<ExportSaveCancelled>(),
      );
      expect(await zip.exists(), isTrue);
      final saved =
          await stage('MA-TSK-222: GUARDAR ZIP sintético') as ExportSaved;
      expect(saved.location, isNotNull);
      if (Platform.isWindows) {
        expect(
          (await sha256.bind(File(saved.location!).openRead()).first)
              .toString(),
          hash,
        );
      } else {
        expect(Uri.parse(saved.location!).scheme, 'content');
      }
      final repeated = await stage(
        'MA-TSK-222: GUARDAR de nuevo con el mismo nombre',
      );
      String? secondLocation;
      if (Platform.isWindows) {
        expect(
          (repeated as ExportSaveFailed).code,
          ExportSaveFailureCode.conflict,
        );
        expect(
          (await sha256.bind(File(saved.location!).openRead()).first)
              .toString(),
          hash,
        );
      } else {
        secondLocation = (repeated as ExportSaved).location;
        expect(secondLocation, isNotNull);
        expect(secondLocation, isNot(saved.location));
      }
      final failed = await stage(
        'MA-TSK-222: esperar 3 segundos y GUARDAR con origen perdido',
        loseSource: true,
      );
      expect(failed, isA<ExportSaveFailed>());
      binding.reportData = {
        'platform': Platform.operatingSystem,
        'syntheticDataOnly': true,
        'savedLocation': saved.location,
        'secondLocation': secondLocation,
        'repeatedNameProtected': true,
        'zipSha256': hash,
        'zipSize': zipSize,
        'cancelled': true,
        'invalidSource': true,
        'sourceLost': (failed as ExportSaveFailed).code.name,
        'incompleteMayRemain': failed.incompleteMayRemain,
      };
    } finally {
      await temp.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}
