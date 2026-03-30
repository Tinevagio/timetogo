// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'screens/map_screen.dart';
import 'widgets/profile_sheet.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => GhostTimeState(),
      child:  const GhostTimeApp(),
    ),
  );
}

class GhostTimeApp extends StatelessWidget {
  const GhostTimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:        'TimeToGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0), // bleu montagne
        useMaterial3:    true,
        brightness:      Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        useMaterial3:    true,
        brightness:      Brightness.dark,
      ),
      home: const _Launcher(),
    );
  }
}

/// Affiche le profil sheet au premier lancement avant d'ouvrir la carte.
class _Launcher extends StatefulWidget {
  const _Launcher();
  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  @override
  void initState() {
    super.initState();
    // Ouvre le profil dès que le premier frame est rendu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ProfileSheet.show(context);
    });
  }

  @override
  Widget build(BuildContext context) => const MapScreen();
}
