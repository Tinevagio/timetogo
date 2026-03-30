// lib/gps_calibrator.dart
//
// Accumule les segments de marche GPS et alimente MunterEngine.addGpsMeasurement().
//
// Stratégie :
//   - On groupe les positions GPS en segments de ~2-5 min
//   - Chaque segment est validé avant d'être envoyé à Munter
//   - Les pauses, remontées mécaniques, et points GPS imprécis sont filtrés

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'munter.dart' as munter_lib;
import 'providers/hgt_elevation_provider.dart';
import 'providers/open_meteo_elevation_provider.dart';
import 'isochrone.dart' show LatLng, ElevationProvider;

// ── Seuils de filtrage ────────────────────────────────────────────────────────

const _minSegmentDurationS  = 60.0;   // durée min d'un segment (s)
const _minSegmentDistanceM  = 50.0;   // distance min d'un segment (m)
const _maxSpeedKmh          = 15.0;   // vitesse max réaliste à pied/ski
const _minSpeedKmh          = 0.3;    // vitesse min (pause détectée en dessous)
const _maxGpsAccuracyM      = 30.0;   // précision GPS max acceptée (m)
const _maxAscentRateM_h     = 1500.0; // taux de montée max réaliste (m/h)
const _maxSlopePct          = 80.0;   // pente max — au-delà = erreur DEM probable

// ── Segment GPS accumulé ──────────────────────────────────────────────────────

class _GpsPoint {
  final double lat;
  final double lng;
  final double alt;       // altitude GPS (moins fiable que DEM, utilisée en fallback)
  final double accuracy;  // précision horizontale en mètres
  final DateTime time;

  const _GpsPoint({
    required this.lat,
    required this.lng,
    required this.alt,
    required this.accuracy,
    required this.time,
  });
}

// ── Calibrateur ───────────────────────────────────────────────────────────────

class GpsCalibrator {
  final munter_lib.MunterEngine munter;
  ElevationProvider? _dem; // DEM partagé depuis app_state

  _GpsPoint? _segmentStart;  // début du segment en cours
  _GpsPoint? _lastPoint;     // dernier point reçu

  // Stats pour l'UI
  int    _segmentsAccepted = 0;
  int    _segmentsRejected = 0;
  String _lastRejectReason = '';

  int    get segmentsAccepted  => _segmentsAccepted;
  int    get segmentsRejected  => _segmentsRejected;
  String get lastRejectReason  => _lastRejectReason;

  GpsCalibrator({required this.munter, ElevationProvider? dem}) : _dem = dem;

  void updateDem(ElevationProvider dem) => _dem = dem;

  // ── Point d'entrée principal ──────────────────────────────────────────────

  /// Appelé à chaque nouvelle position GPS.
  Future<void> onPosition(Position pos) async {
    // Filtrer les points imprécis
    if (pos.accuracy > _maxGpsAccuracyM) {
      debugPrint('Calibration: GPS imprécis (±${pos.accuracy.toStringAsFixed(0)}m) → ignoré');
      return;
    }

    final point = _GpsPoint(
      lat:      pos.latitude,
      lng:      pos.longitude,
      alt:      pos.altitude,
      accuracy: pos.accuracy,
      time:     DateTime.now(),
    );

    if (_segmentStart == null) {
      // Premier point valide → démarre le segment
      _segmentStart = point;
      _lastPoint    = point;
      return;
    }

    _lastPoint = point;

    // Vérifier si le segment est assez long pour être analysé
    final durationS = point.time.difference(_segmentStart!.time).inMilliseconds / 1000.0;
    final distM     = Geolocator.distanceBetween(
      _segmentStart!.lat, _segmentStart!.lng,
      point.lat, point.lng,
    );

    if (durationS < _minSegmentDurationS || distM < _minSegmentDistanceM) {
      return; // Segment trop court, on continue d'accumuler
    }

    // Segment assez long → l'évaluer
    await _evaluateSegment(_segmentStart!, point, distM, durationS);

    // Démarrer un nouveau segment depuis ce point
    _segmentStart = point;
  }

  // ── Évaluation d'un segment ───────────────────────────────────────────────

  Future<void> _evaluateSegment(
    _GpsPoint start,
    _GpsPoint end,
    double distM,
    double durationS,
  ) async {
    // Vitesse horizontale
    final speedKmh = (distM / 1000.0) / (durationS / 3600.0);

    if (speedKmh > _maxSpeedKmh) {
      _reject('vitesse ${speedKmh.toStringAsFixed(1)} km/h > $_maxSpeedKmh (remontée méca ?)');
      return;
    }
    if (speedKmh < _minSpeedKmh) {
      _reject('vitesse ${speedKmh.toStringAsFixed(1)} km/h < $_minSpeedKmh (pause)');
      return;
    }

    // Dénivelé via DEM si disponible, sinon altitude GPS
    double elevGain = 0, elevLoss = 0;
    try {
      final dem = _dem;
      if (dem != null) {
        final altStart = await dem.getElevation(start.lat, start.lng);
        final altEnd   = await dem.getElevation(end.lat, end.lng);
        final diff     = altEnd - altStart;
        elevGain = diff > 0 ? diff : 0;
        elevLoss = diff < 0 ? -diff : 0;
      } else {
        // Fallback : altitude GPS (moins précise, ±10-30m)
        final diff = end.alt - start.alt;
        elevGain = diff > 0 ? diff : 0;
        elevLoss = diff < 0 ? -diff : 0;
      }
    } catch (e) {
      debugPrint('Calibration: erreur DEM → altitude GPS utilisée');
      final diff = end.alt - start.alt;
      elevGain = diff > 0 ? diff : 0;
      elevLoss = diff < 0 ? -diff : 0;
    }

    // Pente
    final elevTotal = elevGain + elevLoss;
    final slopePct  = distM > 0 ? elevTotal / distM * 100 : 0;
    if (slopePct > _maxSlopePct) {
      _reject('pente ${slopePct.toStringAsFixed(0)}% > $_maxSlopePct (erreur DEM ?)');
      return;
    }

    // Taux de montée
    if (elevGain > 0) {
      final ascentRate = elevGain / (durationS / 3600.0);
      if (ascentRate > _maxAscentRateM_h) {
        _reject('D+ ${ascentRate.toStringAsFixed(0)} m/h > $_maxAscentRateM_h (irréaliste)');
        return;
      }
    }

    // Segment valide → alimenter Munter
    munter.addGpsMeasurement(
      distanceM:     distM,
      elevGain:      elevGain,
      elevLoss:      elevLoss,
      actualSeconds: durationS,
    );
    _segmentsAccepted++;

    debugPrint('Calibration ✓ segment #$_segmentsAccepted : '
        '${distM.round()}m en ${durationS.round()}s '
        '(${speedKmh.toStringAsFixed(1)} km/h, '
        'D+${elevGain.round()}m D-${elevLoss.round()}m) '
        '→ poids=${(munter.calibrationWeight*100).toStringAsFixed(0)}%');
  }

  void _reject(String reason) {
    _segmentsRejected++;
    _lastRejectReason = reason;
    debugPrint('Calibration ✗ segment rejeté : $reason');
    // On repart du dernier point pour éviter de perdre de la continuité
    _segmentStart = _lastPoint;
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  void reset() {
    _segmentStart    = null;
    _lastPoint       = null;
    _segmentsAccepted = 0;
    _segmentsRejected = 0;
    _lastRejectReason = '';
  }

  // ── Rapport pour l'UI ─────────────────────────────────────────────────────

  Map<String, String> get report => {
    'segments':  '$_segmentsAccepted acceptés, $_segmentsRejected rejetés',
    'poids':     '${(munter.calibrationWeight * 100).toStringAsFixed(0)}%',
    'calibré':   munter.isCalibrated ? 'Oui' : 'Non (${_segmentsAccepted < 3 ? "pas assez de données" : "en cours…"})',
    'hSpeed':    '${munter.currentParams.horizontalSpeed.toStringAsFixed(2)} km/h',
    'ascentRate':'${munter.currentParams.ascentRate.toStringAsFixed(0)} m/h',
    'descentRate':'${munter.currentParams.descentRate.toStringAsFixed(0)} m/h',
  };
}
