import 'package:flutter/material.dart';

void main() {
  runApp(const AutofinanceApp());
}

class AutofinanceApp extends StatelessWidget {
  const AutofinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Autofinance',
      home: Scaffold(
        body: SafeArea(
          child: Center(child: Text('Autofinance · Base técnica')),
        ),
      ),
    );
  }
}
