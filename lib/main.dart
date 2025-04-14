import 'package:flutter/material.dart';
import 'package:zamio/RadioSniffer.dart';

void main() {
  runApp(const RadioSnifferApp());
}

class RadioSnifferApp extends StatelessWidget {
  const RadioSnifferApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radio Sniffer',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: const RecordingPage(),
    );
  }
}