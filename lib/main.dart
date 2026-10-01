import 'package:flutter/material.dart';

import 'app/bootstrap.dart';

export 'app/app.dart' show AutofinanceApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await initializeApp());
}
