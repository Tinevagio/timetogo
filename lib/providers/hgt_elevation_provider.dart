// lib/providers/hgt_elevation_provider.dart
//
// Provider d'altitude depuis fichiers HGT SRTM1 (30m de résolution).
// Source : AWS Terrain Tiles (Skadi) — 3601×3601 points par degré.

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../isochrone.dart';

class HgtElevationProvider implements ElevationProvider {
  // SRTM1 : 3601×3601 points par degré (1 arc-seconde ≈ 30m)
  static const int _gridSize = 3601;
  static const int _nodata   = -32768;

  // Cache : clé présente avec données = tuile chargée
  //         clé présente avec null    = tuile connue absente (évite retenter le disque)
  //         clé absente               = tuile jamais vérifiée
  static final Map<String, Int16List?> _cache = {};

  @override
  Future<double> getElevation(double lat, double lng) async {
    final data = await _loadTile(lat, lng);
    if (data == null) return 1500.0;

    final latFloor = lat.floor();
    final lngFloor = lng.floor();
    final row = (_gridSize - 1) * (1.0 - (lat - latFloor));
    final col = (_gridSize - 1) * (lng - lngFloor);

    return _bilinear(data, row, col);
  }

  @override
  Future<void> prefetch(LatLng sw, LatLng ne) async {
    for (int lat = sw.lat.floor(); lat <= ne.lat.floor(); lat++) {
      for (int lng = sw.lng.floor(); lng <= ne.lng.floor(); lng++) {
        await _loadTile(lat.toDouble(), lng.toDouble());
      }
    }
  }

  static Future<Int16List?> _loadTile(double lat, double lng) async {
    final key = _tileKey(lat, lng);

    // Cache hit (données ou absence connue)
    if (_cache.containsKey(key)) return _cache[key];

    final file = await _hgtFile(key);
    if (!await file.exists()) {
      _cache[key] = null; // mémoriser l'absence — plus de spam disque
      debugPrint('HGT: $key manquant (mis en cache)');
      return null;
    }

    final bytes    = await file.readAsBytes();
    final expected = _gridSize * _gridSize * 2;
    if (bytes.length != expected) {
      _cache[key] = null; // fichier corrompu → traiter comme absent
      debugPrint('HGT: $key taille incorrecte (${bytes.length} vs $expected)');
      return null;
    }

    final buf  = bytes.buffer.asByteData();
    final data = Int16List(_gridSize * _gridSize);
    for (int i = 0; i < data.length; i++) {
      data[i] = buf.getInt16(i * 2, Endian.big);
    }

    _cache[key] = data;
    debugPrint('HGT: $key chargé — SRTM1 30m ✓');
    return data;
  }

  static double _bilinear(Int16List data, double row, double col) {
    final r0 = row.floor().clamp(0, _gridSize - 2);
    final c0 = col.floor().clamp(0, _gridSize - 2);
    final fr = row - r0;
    final fc = col - c0;

    final q00 = _val(data, r0,   c0);
    final q01 = _val(data, r0,   c0+1);
    final q10 = _val(data, r0+1, c0);
    final q11 = _val(data, r0+1, c0+1);

    return q00*(1-fr)*(1-fc) + q01*(1-fr)*fc
         + q10*fr*(1-fc)     + q11*fr*fc;
  }

  static double _val(Int16List data, int row, int col) {
    final v = data[row * _gridSize + col];
    return v == _nodata ? 0.0 : v.toDouble();
  }

  static String _tileKey(double lat, double lng) {
    final la = lat.floor();
    final lo = lng.floor();
    final latStr = la >= 0 ? 'N${la.abs().toString().padLeft(2,'0')}' : 'S${la.abs().toString().padLeft(2,'0')}';
    final lngStr = lo >= 0 ? 'E${lo.abs().toString().padLeft(3,'0')}' : 'W${lo.abs().toString().padLeft(3,'0')}';
    return '$latStr$lngStr';
  }

  static Future<File> _hgtFile(String key) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/hgt/$key.hgt');
  }

  static Future<bool> isAvailable(double lat, double lng) async {
    final file = await _hgtFile(_tileKey(lat, lng));
    return file.exists();
  }

  static Future<List<String>> installedTiles() async {
    final dir    = await getApplicationDocumentsDirectory();
    final hgtDir = Directory('${dir.path}/hgt');
    if (!await hgtDir.exists()) return [];
    return hgtDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.hgt'))
        .map((f) => f.uri.pathSegments.last.replaceAll('.hgt', ''))
        .toList();
  }

  static Future<void> deleteTile(String key) async {
    _cache.remove(key); // supprime données ET entrée null
    final file = await _hgtFile(key);
    if (await file.exists()) await file.delete();
  }

  /// À appeler après un téléchargement réussi pour invalider le cache null.
  static void invalidateCache(String key) {
    _cache.remove(key);
  }
}
