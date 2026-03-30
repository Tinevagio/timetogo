// lib/providers/demo_elevation_provider.dart
//
// DEM de démonstration : génère un terrain synthétique
// avec des collines sinusoïdales pour tester les isochrones
// sans fichiers HGT ni connexion réseau.

import 'dart:math';
import '../isochrone.dart';

class DemoElevationProvider implements ElevationProvider {
  final double originLat;
  final double originLng;
  final double baseAltitude;

  const DemoElevationProvider({
    required this.originLat,
    required this.originLng,
    this.baseAltitude = 1200.0,
  });

  @override
  Future<double> getElevation(double lat, double lng) async {
    // Distance en mètres depuis l'origine
    final dx = (lng - originLng) * 111320 * cos(originLat * pi / 180);
    final dy = (lat - originLat) * 110540;

    // Terrain synthétique : superposition de plusieurs fréquences
    // pour un résultat plus naturel qu'une simple sinus.
    //
    // Colline principale au nord-est (direction ~45°)
    final hill1 = 400 * sin(dy / 1500 + 0.5) * sin(dx / 1800 + 0.3);
    // Vallée à l'ouest
    final valley = -200 * exp(-pow((dx + 1200) / 800, 2).toDouble()) *
                         exp(-pow(dy / 1500, 2).toDouble());
    // Relief de fond ondulé
    final noise = 80 * sin(dx / 600) * cos(dy / 700 + 1.2)
                + 40 * cos(dx / 300 + 0.8) * sin(dy / 350);
    // Légère pente générale vers le nord (montagne au fond)
    final trend = dy / 20;

    return baseAltitude + hill1 + valley + noise + trend;
  }

  @override
  Future<void> prefetch(LatLng sw, LatLng ne) async {
    // Pas de cache nécessaire — calcul instantané.
  }
}
