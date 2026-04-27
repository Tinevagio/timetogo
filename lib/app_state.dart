// lib/app_state.dart

import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, ChangeNotifier;
import 'package:geolocator/geolocator.dart';
import 'isochrone.dart';
import 'munter.dart' as munter_lib;
import 'gps_calibrator.dart';
import 'providers/hgt_elevation_provider.dart';
import 'providers/open_meteo_elevation_provider.dart';
import 'providers/demo_elevation_provider.dart';
import 'package:flutter/widgets.dart';

// ─── Mode de positionnement ───────────────────────────────────────────────────

enum PositionMode {
  gps,   // position réelle du téléphone
  pin,   // épingle posée manuellement sur la carte
}

// ─── État principal ───────────────────────────────────────────────────────────

class GhostTimeState extends ChangeNotifier with WidgetsBindingObserver {

  // ── Profil ────────────────────────────────────────────────────────────────
  munter_lib.ActivityType     _activity = munter_lib.ActivityType.hiking;
  munter_lib.FitnessLevel     _fitness  = munter_lib.FitnessLevel.trained;
  munter_lib.TerrainCondition _terrain  = munter_lib.TerrainCondition.normal;

  munter_lib.ActivityType     get activity => _activity;
  munter_lib.FitnessLevel     get fitness  => _fitness;
  munter_lib.TerrainCondition get terrain  => _terrain;

  // ── Position & mode ───────────────────────────────────────────────────────
  PositionMode _positionMode = PositionMode.gps;
  PositionMode get positionMode => _positionMode;

  LatLng _position = const LatLng(45.9237, 6.8694); // Chamonix par défaut
  LatLng get position => _position;

  // Position GPS brute (peut différer de _position si mode pin)
  LatLng? _gpsPosition;
  LatLng? get gpsPosition => _gpsPosition;

  bool _gpsAvailable = false;
  bool get gpsAvailable => _gpsAvailable;

  String _gpsStatus = 'Localisation…';
  String get gpsStatus => _gpsStatus;

  bool _gpsPaused = false;
  bool get gpsPaused => _gpsPaused;

  StreamSubscription<Position>? _gpsSub;

  // ── Isochrones ────────────────────────────────────────────────────────────
  Map<int, List<LatLng>> _contours = {};
  Map<int, List<LatLng>> get contours => _contours;

  bool      _computing         = false;
  Duration? _lastComputeDuration;

  bool      get computing           => _computing;
  Duration? get lastComputeDuration => _lastComputeDuration;

  // ── Munter ────────────────────────────────────────────────────────────────
  late munter_lib.MunterEngine _munter;
  late GpsCalibrator _calibrator;

  Map<String, dynamic> get calibrationReport => _munter.calibrationReport();
  Map<String, String>  get calibratorReport  => _calibrator.report;
  bool                 get isCalibrated      => _munter.isCalibrated;

  // ── DEM cache ─────────────────────────────────────────────────────────────
  String             _demSource       = '';
  String             get demSource    => _demSource;
  ElevationProvider? _cachedDem;
  LatLng?            _cachedDemCenter;

  // ── Estimation ponctuelle ─────────────────────────────────────────────────
  String? _pointEstimate;
  LatLng? _targetPoint;
  String? get pointEstimate => _pointEstimate;
  LatLng? get targetPoint   => _targetPoint;

  // ── Init ──────────────────────────────────────────────────────────────────

  GhostTimeState() {
    _rebuildEngine();
    _initGps();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gpsSub?.cancel();
    super.dispose();
  }

  // Gestion du cycle de vie de l'app
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // App revenue au premier plan — redémarrer le GPS si pas en pause manuelle
        if (!_gpsPaused && _gpsAvailable && _gpsSub == null) {
          debugPrint('GPS: app resumed → restart stream');
          _startGpsStream();
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // App en arrière-plan — le foreground service maintient le GPS
        // On ne touche pas au stream, le service continue
        debugPrint('GPS: app en arrière-plan (foreground service actif)');
        break;
      default:
        break;
    }
  }

  // ── GPS ───────────────────────────────────────────────────────────────────

  Future<void> _initGps() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _gpsStatus = 'GPS désactivé';
        notifyListeners();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        _gpsStatus = 'Permission GPS refusée';
        notifyListeners();
        return;
      }

      _gpsAvailable = true;
      _gpsStatus    = 'GPS actif';

      // Position immédiate
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        _onGpsPosition(pos);
      } catch (_) {}

      _startGpsStream();

    } catch (e) {
      _gpsStatus = 'Erreur GPS';
      debugPrint('GPS init error: $e');
      notifyListeners();
    }
  }

  /// Démarre (ou redémarre) le stream GPS.
  /// Annule toujours l'éventuel stream existant avant d'en créer un nouveau
  /// pour éviter les doublons.
  void _startGpsStream() {
    _gpsSub?.cancel();
    _gpsSub = null;
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy:             LocationAccuracy.high,
        distanceFilter:       20,
        forceLocationManager: false,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText:  'TimeToGo suit votre position pour la calibration',
          notificationTitle: 'TimeToGo — GPS actif',
          enableWakeLock:    false,
          notificationIcon:  AndroidResource(
            name:    'ic_notification',
            defType: 'drawable',
          ),
        ),
      ),
    ).listen(
      _onGpsPosition,
      onError: (e) {
        debugPrint('GPS ERROR: $e');
        Future.delayed(const Duration(seconds: 5), () {
          if (!_gpsPaused && _gpsAvailable) _startGpsStream();
        });
      },
      onDone: () {
        debugPrint('GPS: stream terminé (onDone)');
        if (!_gpsPaused && _gpsAvailable) {
          Future.delayed(const Duration(seconds: 2), _startGpsStream);
        }
      },
    );
    debugPrint('GPS: stream démarré (distanceFilter=20m)');
  }

  // ── Pause / reprise manuelle ──────────────────────────────────────────────

  void pauseGps() {
    if (_gpsPaused || !_gpsAvailable) return;
    _gpsSub?.cancel();
    _gpsSub    = null;
    _gpsPaused = true;
    _gpsStatus = 'GPS en pause';
    debugPrint('GPS: pause manuelle');
    notifyListeners();
  }

  void resumeGps() {
    if (!_gpsAvailable) return;
    _gpsPaused = false;
    _gpsStatus = 'GPS reprise…';
    notifyListeners();
    _startGpsStream();
  }

  void _onGpsPosition(Position pos) {
    final newGps = LatLng(pos.latitude, pos.longitude);
    _gpsPosition = newGps;
    _gpsStatus   = 'GPS ±${pos.accuracy.toStringAsFixed(0)}m';

    if (_positionMode == PositionMode.gps) {
      _updatePosition(newGps);
    }

    if (_positionMode == PositionMode.gps) {
      _calibrator.onPosition(pos).then((_) {
        if (_munter.isCalibrated) notifyListeners();
      });
    }

    notifyListeners();
  }

  // ── Mode de positionnement ────────────────────────────────────────────────

  void switchToGps() {
    _positionMode = PositionMode.gps;
    if (_gpsPosition != null) {
      _updatePosition(_gpsPosition!);
    }
    notifyListeners();
  }

  void setPin(LatLng pos) {
    _positionMode = PositionMode.pin;
    _updatePosition(pos);
    notifyListeners();
  }

  void _updatePosition(LatLng pos) {
    // Invalider le cache DEM si on s'est beaucoup déplacé (>500m)
    if (_cachedDemCenter != null) {
      final dx = (pos.lat - _cachedDemCenter!.lat).abs() * 111000;
      final dy = (pos.lng - _cachedDemCenter!.lng).abs() * 111000;
      if (dx > 500 || dy > 500) {
        _cachedDem       = null;
        _cachedDemCenter = null;
      }
    }
    _position      = pos;
    _contours      = {};
    _pointEstimate = null;
    _targetPoint   = null;
  }

  // ── Setters profil ────────────────────────────────────────────────────────

  void setActivity(munter_lib.ActivityType v)    { _activity = v; _rebuildEngine(); }
  void setFitness(munter_lib.FitnessLevel v)     { _fitness  = v; _rebuildEngine(); }
  void setTerrain(munter_lib.TerrainCondition v) { _terrain  = v; _rebuildEngine(); }

  void _rebuildEngine() {
    _munter = munter_lib.MunterEngine(munter_lib.UserProfile(
      activity: _activity,
      fitness:  _fitness,
      terrain:  _terrain,
    ));
    // Nouveau calibrateur lié au nouveau moteur
    _calibrator = GpsCalibrator(munter: _munter, dem: _cachedDem);
    if (!_computing) {
      _contours      = {};
      _pointEstimate = null;
      _targetPoint   = null;
    }
    notifyListeners();
  }

  // ── Calcul isochrones ─────────────────────────────────────────────────────

  Future<void> computeIsochrones() async {
    if (_computing) return;
    _computing = true;
    _contours  = {};
    notifyListeners();

    try {
      final munter = munter_lib.MunterEngine(munter_lib.UserProfile(
        activity: _activity,
        fitness:  _fitness,
        terrain:  _terrain,
      ));

      // Grille 2km de rayon → résolution 10×10 = ~444m (vs 1100m avant)
      const gridRadiusM = 2000.0;
      final approxRadiusDeg = gridRadiusM / 111000;
      final sw = LatLng(_position.lat - approxRadiusDeg, _position.lng - approxRadiusDeg);
      final ne = LatLng(_position.lat + approxRadiusDeg, _position.lng + approxRadiusDeg);

      // Pour le HGT, on précharge aussi les tuiles couvrant le rayon MAX des isochrones
      // (pas seulement la grille Open-Meteo de 2km) — évite la coupure aux frontières de tuiles
      final maxRayM = munter.maxHorizontalDistance(60 * 60.0)
          .clamp(3000.0, 12000.0) * 1.5;
      final maxRayDeg = maxRayM / 111000;
      final swFull = LatLng(_position.lat - maxRayDeg, _position.lng - maxRayDeg);
      final neFull = LatLng(_position.lat + maxRayDeg, _position.lng + maxRayDeg);

      // ── Sélection DEM : HGT > Open-Meteo > Synthétique ────────────────
      ElevationProvider dem;

      // 1. HGT local disponible ?
      final hgtAvailable = await HgtElevationProvider.isAvailable(
          _position.lat, _position.lng);

      if (hgtAvailable) {
        final hgtDem = HgtElevationProvider();
        await hgtDem.prefetch(swFull, neFull); // précharge toutes les tuiles dans le rayon max
        dem              = hgtDem;
        _cachedDem       = hgtDem;
        _cachedDemCenter = _position;
        _demSource       = '🗻 HGT SRTM1 (30m)';
        _calibrator.updateDem(hgtDem);
        debugPrint('DEM: HGT local OK');

      } else {
        final samePos = _cachedDemCenter != null &&
            (_cachedDemCenter!.lat - _position.lat).abs() < 0.005 &&
            (_cachedDemCenter!.lng - _position.lng).abs() < 0.005 &&
            _cachedDem != null;

        if (samePos) {
          dem = _cachedDem!;
          debugPrint('DEM: cache réutilisé');
        } else {
          try {
            final omDem = OpenMeteoElevationProvider();
            await omDem.prefetch(sw, ne);
            dem              = omDem;
            _cachedDem       = omDem;
            _cachedDemCenter = _position;
            _demSource       = '🛰 Open-Meteo (±400m)';
            _calibrator.updateDem(omDem);
            debugPrint('DEM: Open-Meteo OK — ${omDem.debugInfo}');
          } catch (e) {
            debugPrint('DEM: fallback synthétique ($e)');
            final d = DemoElevationProvider(
                originLat: _position.lat, originLng: _position.lng);
            dem              = d;
            _cachedDem       = d;
            _cachedDemCenter = _position;
            _demSource       = '⚠ Terrain synthétique';
            _calibrator.updateDem(d);
          }
        }
      }

      final engine = IsochroneEngine(
        munter: munter,
        dem:    dem,
        config: IsochroneConfig(
          timeBudgetsMinutes: [15, 30, 45, 60],
          rayCount:           72,
          baseStepM:          40,   // 40m au lieu de 60m
          minStepM:           10,   // 10m au lieu de 15m
          maxStepM:           80,   // 80m au lieu de 250m — clé du fix terrain plat
          maxRayDistanceM:    maxRayM,
        ),
      );

      final result = await engine.compute(LatLng(_position.lat, _position.lng));

      _contours = result.contours.map(
        (k, v) => MapEntry(k, chaikinSmooth(v, iterations: 2)),
      );
      _lastComputeDuration = result.computeDuration;
    } catch (e) {
      debugPrint('Erreur calcul isochrones: $e');
    } finally {
      _computing = false;
      notifyListeners();
    }
  }

  // ── Estimation ponctuelle ─────────────────────────────────────────────────

  Future<void> estimateToPoint(LatLng target) async {
    _targetPoint   = target;
    _pointEstimate = 'Calcul…';
    notifyListeners();

    final dem = _cachedDem;
    double originAlt, targetAlt;

    if (dem != null) {
      originAlt = await dem.getElevation(_position.lat, _position.lng);
      targetAlt = await dem.getElevation(target.lat, target.lng);
    } else {
      try {
        final omDem = OpenMeteoElevationProvider();
        originAlt = await omDem.getElevation(_position.lat, _position.lng);
        targetAlt = await omDem.getElevation(target.lat, target.lng);
      } catch (_) {
        _pointEstimate = 'Altitude indisponible';
        notifyListeners();
        return;
      }
    }

    final elevDiff = targetAlt - originAlt;
    final distM    = _haversineM(_position.lat, _position.lng, target.lat, target.lng);
    final secs     = _munter.estimateSeconds(
      distanceM: distM,
      elevGain:  elevDiff > 0 ? elevDiff : 0,
      elevLoss:  elevDiff < 0 ? -elevDiff : 0,
    );

    final totalMin = (secs / 60).round();
    final h   = totalMin ~/ 60;
    final min = totalMin % 60;
    final timeStr = h > 0 ? '${h}h${min.toString().padLeft(2,'0')}' : '$min min';
    final elevStr = elevDiff >= 0
        ? '+${elevDiff.round()} m D+'
        : '${elevDiff.round()} m D-';

    _pointEstimate = '$timeStr  ·  ${distM.round()} m  ·  $elevStr';
    notifyListeners();
  }

  void clearTarget() {
    _targetPoint   = null;
    _pointEstimate = null;
    notifyListeners();
  }

  // ── Haversine ─────────────────────────────────────────────────────────────

  static double _haversineM(double lat1, double lng1, double lat2, double lng2) {
    const r  = 6371000.0;
    final dLat = (lat2 - lat1) * 3.141592653589793 / 180;
    final dLng = (lng2 - lng1) * 3.141592653589793 / 180;
    final a = _sin(dLat/2)*_sin(dLat/2) +
        _cos(lat1*3.141592653589793/180)*_cos(lat2*3.141592653589793/180)*
        _sin(dLng/2)*_sin(dLng/2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1-a));
    return r * c;
  }

  static double _sin(double x) {
    const pi = 3.141592653589793;
    x = x % (2*pi);
    if (x > pi) x -= 2*pi;
    if (x < -pi) x += 2*pi;
    final x2 = x*x;
    return x*(1 - x2/6*(1 - x2/20*(1 - x2/42)));
  }
  static double _cos(double x) => _sin(x + 3.141592653589793/2);
  static double _sqrt(double v) {
    if (v <= 0) return 0;
    double x = v > 1 ? v/2 : v+0.5;
    for (int i = 0; i < 30; i++) x = (x+v/x)/2;
    return x;
  }
  static double _atan2(double y, double x) {
    if (x > 0) return _atan(y/x);
    if (x < 0 && y >= 0) return _atan(y/x) + 3.141592653589793;
    if (x < 0 && y < 0)  return _atan(y/x) - 3.141592653589793;
    return y > 0 ? 1.5707963267948966 : -1.5707963267948966;
  }
  static double _atan(double x) {
    if (x.abs() > 1) return (x>0?1:-1)*1.5707963267948966 - _atan(1/x);
    final x2 = x*x;
    return x*(1 - x2/3*(1 - x2/5*(1 - x2/7*(1 - x2/9))));
  }
}
