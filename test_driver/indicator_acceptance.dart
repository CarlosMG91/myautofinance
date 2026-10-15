import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data?['ticket'] != 'MA-TSK-188' ||
        !['windows', 'android'].contains(data?['platform']) ||
        data?['appEnvironment'] != 'test' ||
        data?['syntheticDataOnly'] != true ||
        jsonEncode(data?['completed']) !=
            '["sqlite-contract-and-extension","source-return-import-restore-reopen"]') {
      throw StateError('El runner no acredita los dos recorridos completos.');
    }
    final directory = await Directory('docs/ep-023/evidencias-ma-tsk-188')
        .create(recursive: true);
    await File('${directory.path}/${data!['platform']}.json')
        .writeAsString('${const JsonEncoder.withIndent('  ').convert(data)}\n');
  },
);
