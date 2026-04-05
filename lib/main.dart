// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'app_state.dart';
import 'screens/map_screen.dart';
import 'widgets/profile_sheet.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cache persistant des tuiles OpenTopoMap
  await FMTCObjectBoxBackend().initialise();
  await FMTCStore('opentopomap').manage.create();

  runApp(
    ChangeNotifierProvider(
      create: (_) => GhostTimeState(),
      child:  const TimeToGoApp(),
    ),
  );
}

class TimeToGoApp extends StatelessWidget {
  const TimeToGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:        'TimeToGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
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

class _Launcher extends StatefulWidget {
  const _Launcher();
  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ProfileSheet.show(context);
    });
  }

  @override
  Widget build(BuildContext context) => const MapScreen();
}
