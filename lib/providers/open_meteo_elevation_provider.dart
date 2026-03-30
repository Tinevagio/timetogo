// lib/providers/open_meteo_elevation_provider.dart
//
// Provider d'altitude réelle via Open-Meteo Elevation API.
//
// Stratégie :
//   1. prefetch() construit une grille 10×10 = 100 points (1 seule requête)
//   2. getElevation() fait une interpolation bilinéaire dans la grille
//      → zéro requête réseau pendant le ray-casting
//
// API : https://api.open-meteo.com/v1/elevation?latitude=a,b&longitude=x,y
// Gratuite, sans clé, max 100 points/requête.

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../isochrone.dart';

class OpenMeteoElevationProvider implements ElevationProvider {
  // ── Grille cachée ─────────────────────────────────────────────────────────
  double? _gridOriginLat;
  double? _gridOriginLng;
  double? _gridStepLat;
  double? _gridStepLng;
  int?    _gridN;
  List<double>? _grid;

  bool get _hasGrid => _grid != null;

  // ── ElevationProvider interface ───────────────────────────────────────────

  @override
  Future<double> getElevation(double lat, double lng) async {
    if (_hasGrid) return _interpolate(lat, lng);
    return _fetchSingle(lat, lng);
  }

  @override
  Future<void> prefetch(LatLng sw, LatLng ne) async {
    // Grille 10×10 = 100 points → 1 seule requête HTTP, pas de rate-limit.
    // Distribution log-radiale : points plus denses près de l'origine
    // pour mieux capturer les changements de pente à courte distance.
    const n = 10;
    final centerLat = (sw.lat + ne.lat) / 2;
    final centerLng = (sw.lng + ne.lng) / 2;
    final halfLat   = (ne.lat - sw.lat) / 2;
    final halfLng   = (ne.lng - sw.lng) / 2;

    // Positions normalisées [-1, 1] avec distribution log
    // t_i = signe * (exp(|i|/n * ln(2)) - 1)  → plus dense au centre
    List<double> logSpaced(int count) {
      final result = <double>[];
      for (int i = 0; i < count; i++) {
        final t = i / (count - 1); // [0, 1]
        // Distribution en racine carrée : concentre au centre
        final pos = (2 * t - 1); // [-1, 1] linéaire
        result.add(pos.sign * (pos.abs() < 1e-10 ? 0 : pos.abs()));
      }
      return result;
    }

    final latOffsets = logSpaced(n);
    final lngOffsets = logSpaced(n);

    final lats = <double>[];
    final lngs = <double>[];
    for (final latO in latOffsets) {
      for (final lngO in lngOffsets) {
        lats.add(centerLat + latO * halfLat);
        lngs.add(centerLng + lngO * halfLng);
      }
    }

    final alts = await _fetchWithRetry(lats, lngs);

    _gridOriginLat = sw.lat;
    _gridOriginLng = sw.lng;
    _gridStepLat   = (ne.lat - sw.lat) / (n - 1);
    _gridStepLng   = (ne.lng - sw.lng) / (n - 1);
    _gridN         = n;
    _grid          = alts;

    final resLatM = (_gridStepLat! * 110540).toStringAsFixed(0);
    final resLngM = (_gridStepLng! * 111320 * cos(sw.lat * pi / 180)).toStringAsFixed(0);
    debugPrint('OpenMeteo: grille ${n}×$n OK (1 requête), résolution ~${resLatM}m×${resLngM}m');
  }

  // ── Requête avec retry ────────────────────────────────────────────────────

  Future<List<double>> _fetchWithRetry(
      List<double> lats, List<double> lngs) async {
    final latStr = lats.map((v) => v.toStringAsFixed(6)).join(',');
    final lngStr = lngs.map((v) => v.toStringAsFixed(6)).join(',');
    final url = Uri.parse(
        'https://api.open-meteo.com/v1/elevation'
        '?latitude=$latStr&longitude=$lngStr');

    Exception? lastError;
    for (int attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        // Backoff exponentiel — laisse le temps à la connexion de s'établir
        final delayMs = 1000 * attempt; // 1s, 2s, 3s
        debugPrint('OpenMeteo: attente ${delayMs}ms avant tentative ${attempt + 1}/4...');
        await Future.delayed(Duration(milliseconds: delayMs));
      }
      try {
        final response = await http
            .get(url, headers: {'Connection': 'keep-alive'})
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final elevations = (data['elevation'] as List).cast<num>();
          return elevations.map((e) => e.toDouble()).toList();
        }
        if (response.statusCode == 429) {
          // Rate limit — attendre plus longtemps avant retry
          debugPrint('OpenMeteo: 429 rate limit, attente 5s...');
          await Future.delayed(const Duration(seconds: 5));
          lastError = Exception('HTTP 429');
          continue;
        }
        lastError = Exception('HTTP ${response.statusCode}');
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('OpenMeteo tentative ${attempt + 1}/4 échouée: $e');
      }
    }
    throw lastError ?? Exception('OpenMeteo indisponible après 4 tentatives');
  }

  Future<double> _fetchSingle(double lat, double lng) async {
    final result = await _fetchWithRetry([lat], [lng]);
    return result.first;
  }

  // ── Interpolation bilinéaire ──────────────────────────────────────────────

  double _interpolate(double lat, double lng) {
    final n    = _gridN!;
    final grid = _grid!;

    final col = (lng - _gridOriginLng!) / _gridStepLng!;
    final row = (lat - _gridOriginLat!) / _gridStepLat!;

    final col0 = col.floor().clamp(0, n - 2);
    final row0 = row.floor().clamp(0, n - 2);
    final col1 = col0 + 1;
    final row1 = row0 + 1;

    final fc = (col - col0).clamp(0.0, 1.0);
    final fr = (row - row0).clamp(0.0, 1.0);

    final q00 = grid[row0 * n + col0];
    final q10 = grid[row1 * n + col0];
    final q01 = grid[row0 * n + col1];
    final q11 = grid[row1 * n + col1];

    return q00 * (1 - fr) * (1 - fc)
         + q10 *      fr  * (1 - fc)
         + q01 * (1 - fr) *      fc
         + q11 *      fr  *      fc;
  }

  String get debugInfo {
    if (!_hasGrid) return 'Grille non chargée';
    final resM = (_gridStepLat! * 110540).toStringAsFixed(0);
    return 'Grille ${_gridN}×$_gridN, résolution ~${resM}m';
  }
}

