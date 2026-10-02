import 'package:flutter/material.dart';

import 'app/bootstrap.dart';

export 'app/app.dart' show AutofinanceApp;

Future<void> main({LocalSessionInitializer? initializeLocal}) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StartupLoadingApp());
  runApp(await initializeApp(initializeLocal: initializeLocal));
}
