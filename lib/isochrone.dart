/// isochrone.dart
/// Calcul des isochrones pour GhostTime.
///
/// Algorithme : ray-casting adaptatif.
/// Pour chaque rayon (angle), on avance pas à pas depuis la position
/// de départ. À chaque pas on consulte le DEM, on calcule la pente,
/// on estime le temps via Munter. Quand le budget temps est atteint
/// on enregistre le dernier point valide → on relie les points
/// → isochrone.

import 'dart:math';
import 'munter.dart';

// ─── Types géographiques légers ───────────────────────────────────────────────

class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);

  @override
  String toString() => 'LatLng(${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)})';
}

class LatLngWithAlt {
  final double lat;
  final double lng;
  final double altM; // altitude en mètres
  const LatLngWithAlt(this.lat, this.lng, this.altM);
}

// ─── Interface DEM ────────────────────────────────────────────────────────────

/// Contrat que doit implémenter le fournisseur d'altitude.
/// En pratique : HgtElevationProvider (offline) ou OpenMeteoProvider (online).
abstract class ElevationProvider {
  /// Retourne l'altitude en mètres pour un point donné.
  /// Peut être async (lecture fichier HGT ou appel API).
  Future<double> getElevation(double lat, double lng);

  /// Précharge une zone rectangulaire (optimisation batch).
  /// Optionnel — l'implémentation peut être un no-op.
  Future<void> prefetch(LatLng sw, LatLng ne) async {}
}

// ─── Paramètres de calcul ─────────────────────────────────────────────────────

class IsochroneConfig {
  /// Intervalles de temps en minutes (ex: [15, 30, 45, 60]).
  final List<int> timeBudgetsMinutes;

  /// Nombre de rayons (résolution angulaire).
  /// 72 → résolution 5°, bon compromis qualité/perf.
  final int rayCount;

  /// Pas de base en mètres. Affiné dynamiquement selon la pente.
  final double baseStepM;

  /// Pas minimum en mètres (zones très pentues).
  final double minStepM;

  /// Pas maximum en mètres (terrain plat).
  final double maxStepM;

  /// Distance maximale d'un rayon (mètres).
  /// Garde-fou pour ne pas partir à l'infini.
  final double maxRayDistanceM;

  const IsochroneConfig({
    this.timeBudgetsMinutes = const [15, 30, 45, 60],
    this.rayCount            = 72,
    this.baseStepM           = 50.0,
    this.minStepM            = 15.0,
    this.maxStepM            = 200.0,
    this.maxRayDistanceM     = 8000.0,
  });
}

// ─── Résultat ─────────────────────────────────────────────────────────────────

class IsochroneResult {
  /// Clé = budget en minutes, valeur = liste de points formant le contour.
  final Map<int, List<LatLng>> contours;

  /// Durée de calcul (debug / UI).
  final Duration computeDuration;

  const IsochroneResult({
    required this.contours,
    required this.computeDuration,
  });
}

// ─── Moteur principal ─────────────────────────────────────────────────────────

class IsochroneEngine {
  final MunterEngine munter;
  final ElevationProvider dem;
  final IsochroneConfig config;

  IsochroneEngine({
    required this.munter,
    required this.dem,
    IsochroneConfig? config,
  }) : config = config ?? const IsochroneConfig();

  /// Point d'entrée principal.
  Future<IsochroneResult> compute(LatLng origin) async {
    final sw = Stopwatch()..start();

    // Altitude du point de départ
    final originAlt = await dem.getElevation(origin.lat, origin.lng);
    final originFull = LatLngWithAlt(origin.lat, origin.lng, originAlt);

    // Note : le prefetch DEM est géré par l'appelant (app_state.dart)
    // qui a déjà chargé la grille avant de lancer le calcul.

    // Tri des budgets croissants (pour partager les rayons entre niveaux)
    final budgets = List<int>.from(config.timeBudgetsMinutes)..sort();

    // Pour chaque angle, on calcule TOUS les niveaux en un seul rayon
    // → économie de N_budgets × appels DEM
    final Map<int, List<LatLng>> contours = {for (final b in budgets) b: []};

    final angleStep = 2 * pi / config.rayCount;

    for (int i = 0; i < config.rayCount; i++) {
      final angle = i * angleStep;
      final rayPoints = await _traceRay(originFull, angle, budgets);

      for (final b in budgets) {
        final pt = rayPoints[b];
        if (pt != null) contours[b]!.add(pt);
      }
    }

    sw.stop();
    return IsochroneResult(contours: contours, computeDuration: sw.elapsed);
  }

  // ─── Ray tracing ────────────────────────────────────────────────────────────

  /// Trace un rayon depuis [origin] dans la direction [angleRad].
  /// Retourne le dernier point valide pour chaque budget temps.
  Future<Map<int, LatLng?>> _traceRay(
    LatLngWithAlt origin,
    double angleRad,
    List<int> budgetsSorted,
  ) async {
    final result = <int, LatLng?>{for (final b in budgetsSorted) b: null};

    double accumulatedSeconds = 0.0;
    double currentLat = origin.lat;
    double currentLng = origin.lng;
    double currentAlt = origin.altM;
    double totalDist  = 0.0;

    int budgetIdx = 0;
    final maxBudgetS = budgetsSorted.last * 60.0;

    while (accumulatedSeconds < maxBudgetS &&
           totalDist < config.maxRayDistanceM) {

      // ── Calcul du pas adaptatif ──────────────────────────────────────────
      // On fait un premier petit pas pour mesurer la pente locale,
      // puis on ajuste la taille du pas suivant.
      final probeStep = config.minStepM;
      final probeLat  = _destinationLat(currentLat, currentLng, angleRad, probeStep);
      final probeLng  = _destinationLng(currentLat, currentLng, angleRad, probeStep);
      final probeAlt  = await dem.getElevation(probeLat, probeLng);

      final probeSlopePct = _slopePct(probeAlt - currentAlt, probeStep);
      final stepM = _adaptiveStep(probeSlopePct);

      // ── Déplacement réel ─────────────────────────────────────────────────
      final nextLat = _destinationLat(currentLat, currentLng, angleRad, stepM);
      final nextLng = _destinationLng(currentLat, currentLng, angleRad, stepM);
      final nextAlt = (stepM == probeStep)
          ? probeAlt // réutilise la mesure sonde
          : await dem.getElevation(nextLat, nextLng);

      final elevDiff = nextAlt - currentAlt;
      final elevGain = elevDiff > 0 ? elevDiff : 0.0;
      final elevLoss = elevDiff < 0 ? -elevDiff : 0.0;

      // ── Estimation du temps Munter ───────────────────────────────────────
      final stepSeconds = munter.estimateSeconds(
        distanceM: stepM,
        elevGain:  elevGain,
        elevLoss:  elevLoss,
      );

      accumulatedSeconds += stepSeconds;
      totalDist += stepM;

      // ── Enregistrement des seuils dépassés ───────────────────────────────
      while (budgetIdx < budgetsSorted.length &&
             accumulatedSeconds >= budgetsSorted[budgetIdx] * 60.0) {

        // Interpolation linéaire pour affiner la position du seuil
        final budgetS   = budgetsSorted[budgetIdx] * 60.0;
        final overshoot = accumulatedSeconds - budgetS;
        final ratio     = 1.0 - (overshoot / stepSeconds).clamp(0.0, 1.0);

        final interpLat = currentLat + (nextLat - currentLat) * ratio;
        final interpLng = currentLng + (nextLng - currentLng) * ratio;
        result[budgetsSorted[budgetIdx]] = LatLng(interpLat, interpLng);

        budgetIdx++;
      }

      if (budgetIdx >= budgetsSorted.length) break;

      currentLat = nextLat;
      currentLng = nextLng;
      currentAlt = nextAlt;
    }

    // Si le rayon a terminé sans atteindre un seuil (terrain trop pentu),
    // on utilise le dernier point connu pour les budgets restants.
    for (int b = budgetIdx; b < budgetsSorted.length; b++) {
      result[budgetsSorted[b]] ??= LatLng(currentLat, currentLng);
    }

    return result;
  }

  // ─── Pas adaptatif ──────────────────────────────────────────────────────────

  /// Réduit le pas sur terrain pentu, l'augmente sur terrain plat.
  /// [slopePct] = dénivelé / distance horizontale × 100
  double _adaptiveStep(double slopePct) {
    final abs = slopePct.abs();
    if (abs < 5)  return config.maxStepM;          // très plat → grands pas
    if (abs < 15) return config.baseStepM;          // pente modérée → pas standard
    if (abs < 30) return config.baseStepM * 0.6;   // pente forte
    return config.minStepM;                         // très pentu → petits pas
  }

  // ─── Géodésie ────────────────────────────────────────────────────────────────

  static const _earthRadiusM = 6371000.0;

  /// Pente en % à partir d'une différence d'altitude et d'une distance.
  static double _slopePct(double elevDiff, double distM) =>
      distM > 0 ? (elevDiff / distM) * 100.0 : 0.0;

  /// Nouvelle latitude après déplacement de [distM] dans la direction [bearingRad].
  static double _destinationLat(double lat, double lng, double bearingRad, double distM) {
    final latR  = _deg2rad(lat);
    final angDist = distM / _earthRadiusM;
    final newLat = asin(sin(latR) * cos(angDist) +
                        cos(latR) * sin(angDist) * cos(bearingRad));
    return _rad2deg(newLat);
  }

  /// Nouvelle longitude après déplacement de [distM] dans la direction [bearingRad].
  static double _destinationLng(double lat, double lng, double bearingRad, double distM) {
    final latR  = _deg2rad(lat);
    final lngR  = _deg2rad(lng);
    final angDist = distM / _earthRadiusM;
    final newLng = lngR + atan2(
      sin(bearingRad) * sin(angDist) * cos(latR),
      cos(angDist) - sin(latR) * sin(asin(sin(latR) * cos(angDist) +
                                          cos(latR) * sin(angDist) * cos(bearingRad))),
    );
    return _rad2deg(newLng);
  }

  static double _deg2rad(double d) => d * pi / 180.0;
  static double _rad2deg(double r) => r * 180.0 / pi;
}

// ─── Post-processing : lissage du contour ─────────────────────────────────────

/// Lissage de Chaikin sur le contour isochrone.
/// Réduit l'aspect "polygonal" lié à la discrétisation des rayons.
/// Appeler 2-3 fois pour un résultat fluide.
List<LatLng> chaikinSmooth(List<LatLng> pts, {int iterations = 2}) {
  if (pts.length < 3) return pts;
  var current = pts;
  for (int i = 0; i < iterations; i++) {
    current = _chaikinStep(current);
  }
  return current;
}

List<LatLng> _chaikinStep(List<LatLng> pts) {
  final result = <LatLng>[];
  final n = pts.length;
  for (int i = 0; i < n; i++) {
    final p0 = pts[i];
    final p1 = pts[(i + 1) % n];
    result.add(LatLng(
      0.75 * p0.lat + 0.25 * p1.lat,
      0.75 * p0.lng + 0.25 * p1.lng,
    ));
    result.add(LatLng(
      0.25 * p0.lat + 0.75 * p1.lat,
      0.25 * p0.lng + 0.75 * p1.lng,
    ));
  }
  return result;
}
