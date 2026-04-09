import 'package:remotelens_app/services/connectivity_service.dart';
import 'package:remotelens_app/views/selection_landing_screen.dart';
import 'package:flutter/material.dart';

void main() {
  ConnectivityService().init();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1B1E),
      ),
      home: const SelectionLandingScreen(),
    );
  }
}
