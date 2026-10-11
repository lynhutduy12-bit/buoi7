import 'package:flutter/material.dart';
import 'screens/map_screen.dart';

void main() {
  runApp(const MapNavigatorApp());
}

class MapNavigatorApp extends StatelessWidget {
  const MapNavigatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Map Navigator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const MapScreen(),
    );
  }
}
