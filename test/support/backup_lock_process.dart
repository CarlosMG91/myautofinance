import 'dart:convert';
import 'dart:io';

import 'package:myautofinance/features/synchronization/data/native_backup_persistence.dart';

Future<void> main(List<String> args) async {
  await NativeBackupPersistence().exclusively(args.single, () async {
    stdout.writeln('locked');
    await stdin.transform(utf8.decoder).first;
  });
}
