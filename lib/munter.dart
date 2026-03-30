/// munter.dart
/// Modèle de vitesse Munter adaptatif pour GhostTime.
///
/// Munter classique (à pied, conditions normales) :
///   UM = dist_km / vitesse_kmh + d_plus / 300 + d_minus / 500
///
/// Ici on l'inverse : on calcule le TEMPS (en heures) pour un segment
/// donné (distance horizontale + dénivelé), et on calibre les
/// dénominateurs selon le profil utilisateur + le rythme mesuré.

// ─── Profil utilisateur ───────────────────────────────────────────────────────

enum ActivityType { hiking, skiTouring, trail }
enum FitnessLevel { beginner, trained, warrior }
enum TerrainCondition { normal, difficultTerrain, heavySnow }

class UserProfile {
  final ActivityType activity;
  final FitnessLevel fitness;
  final TerrainCondition terrain;

  const UserProfile({
    required this.activity,
    required this.fitness,
    required this.terrain,
  });

  static const UserProfile defaultProfile = UserProfile(
    activity: ActivityType.hiking,
    fitness: FitnessLevel.trained,
    terrain: TerrainCondition.normal,
  );
}

// ─── Paramètres Munter ────────────────────────────────────────────────────────

/// Paramètres du modèle Munter.
/// [horizontalSpeed]  vitesse horizontale de base en km/h
/// [ascentRate]       dénivelé positif / heure (m/h) → dénominateur Munter D+
/// [descentRate]      dénivelé négatif / heure (m/h) → dénominateur Munter D-
class MunterParams {
  final double horizontalSpeed; // km/h
  final double ascentRate;      // m/h
  final double descentRate;     // m/h

  const MunterParams({
    required this.horizontalSpeed,
    required this.ascentRate,
    required this.descentRate,
  });

  /// Fusion pondérée avec des paramètres mesurés.
  /// [weight] ∈ [0, 1] : 0 = 100% baseline, 1 = 100% mesuré.
  MunterParams blend(MunterParams measured, double weight) {
    final w = weight.clamp(0.0, 1.0);
    return MunterParams(
      horizontalSpeed: horizontalSpeed * (1 - w) + measured.horizontalSpeed * w,
      ascentRate:      ascentRate      * (1 - w) + measured.ascentRate      * w,
      descentRate:     descentRate     * (1 - w) + measured.descentRate     * w,
    );
  }

  @override
  String toString() =>
      'MunterParams(h=${horizontalSpeed.toStringAsFixed(1)} km/h, '
      'D+=${ascentRate.toStringAsFixed(0)} m/h, '
      'D-=${descentRate.toStringAsFixed(0)} m/h)';
}

// ─── Table de référence Munter ────────────────────────────────────────────────

/// Valeurs de référence par combinaison profil/terrain.
/// Sources : méthode Munter, ajustements ski de rando (CAF), trail.
const Map<ActivityType, Map<FitnessLevel, MunterParams>> _baseTable = {
  ActivityType.hiking: {
    FitnessLevel.beginner: MunterParams(horizontalSpeed: 3.0, ascentRate: 250, descentRate: 400),
    FitnessLevel.trained:  MunterParams(horizontalSpeed: 4.0, ascentRate: 350, descentRate: 500),
    FitnessLevel.warrior:  MunterParams(horizontalSpeed: 5.0, ascentRate: 500, descentRate: 700),
  },
  ActivityType.skiTouring: {
    FitnessLevel.beginner: MunterParams(horizontalSpeed: 3.5, ascentRate: 300, descentRate: 600),
    FitnessLevel.trained:  MunterParams(horizontalSpeed: 4.5, ascentRate: 450, descentRate: 900),
    FitnessLevel.warrior:  MunterParams(horizontalSpeed: 5.5, ascentRate: 600, descentRate: 1200),
  },
  ActivityType.trail: {
    FitnessLevel.beginner: MunterParams(horizontalSpeed: 5.0, ascentRate: 400, descentRate: 600),
    FitnessLevel.trained:  MunterParams(horizontalSpeed: 7.0, ascentRate: 600, descentRate: 900),
    FitnessLevel.warrior:  MunterParams(horizontalSpeed: 9.0, ascentRate: 900, descentRate: 1200),
  },
};

/// Facteur multiplicatif appliqué au temps estimé selon terrain.
const Map<TerrainCondition, double> _terrainFactor = {
  TerrainCondition.normal:          1.0,
  TerrainCondition.difficultTerrain: 1.30,
  TerrainCondition.heavySnow:       1.45,
};

// ─── Moteur de calcul ─────────────────────────────────────────────────────────

class MunterEngine {
  final UserProfile profile;

  /// Paramètres courants (fusionnés baseline + calibration).
  MunterParams _params;

  /// Historique des mesures GPS pour la calibration.
  final List<_GpsMeasurement> _measurements = [];

  /// Poids de calibration courant ∈ [0, 1].
  double _calibrationWeight = 0.0;

  MunterEngine(this.profile)
      : _params = _resolveBaseParams(profile);

  MunterParams get currentParams => _params;
  double get calibrationWeight => _calibrationWeight;
  bool get isCalibrated => _calibrationWeight >= 0.5;

  // ── Calcul de temps ──────────────────────────────────────────────────────

  /// Estime le temps en secondes pour un segment.
  /// [distanceM]  distance horizontale en mètres
  /// [elevGain]   dénivelé positif en mètres (≥ 0)
  /// [elevLoss]   dénivelé négatif en mètres (≥ 0, valeur absolue)
  ///
  /// Formule Munter correcte :
  ///   t = max(dist_km / v_horiz, D+ / ascentRate, D- / descentRate)
  ///
  /// La contrainte DOMINANTE dicte le temps — on ne les additionne pas.
  /// Sur un segment montée raide : la montée dicte, la distance horizontale
  /// est déjà "incluse" dans le dénivelé.
  /// Sur un segment plat : la vitesse horizontale dicte.
  double estimateSeconds({
    required double distanceM,
    required double elevGain,
    required double elevLoss,
  }) {
    final distKm = distanceM / 1000.0;

    // Temps horizontal
    final tHoriz = distKm / _params.horizontalSpeed;

    // D+ et D- s'ADDITIONNENT entre eux sur un même pas
    // (une montée puis une descente coûtent les deux, même si le net est nul)
    // mais on prend le MAX avec l'horizontal
    // (en terrain plat, c'est la vitesse horizontale qui dicte)
    final tVert = (elevGain / _params.ascentRate) + (elevLoss / _params.descentRate);

    final tBase = tHoriz > tVert ? tHoriz : tVert;

    final factor = _terrainFactor[profile.terrain]!;
    return tBase * factor * 3600;
  }

  /// Estime la distance maximale franchissable (horizontale, mètres)
  /// dans un budget temps [budgetSeconds], sur un terrain plat.
  double maxHorizontalDistance(double budgetSeconds) {
    final budgetH = budgetSeconds / 3600.0;
    final factor = _terrainFactor[profile.terrain]!;
    return (_params.horizontalSpeed * budgetH / factor) * 1000.0;
  }

  // ── Calibration ──────────────────────────────────────────────────────────

  /// Enregistre une observation GPS.
  /// Appelé toutes les ~30 secondes pendant la sortie.
  void addGpsMeasurement({
    required double distanceM,
    required double elevGain,
    required double elevLoss,
    required double actualSeconds,
  }) {
    if (distanceM < 10 || actualSeconds < 10) return; // filtre arrêts
    _measurements.add(_GpsMeasurement(
      distanceM:     distanceM,
      elevGain:      elevGain,
      elevLoss:      elevLoss,
      actualSeconds: actualSeconds,
    ));
    _recalibrate();
  }

  void _recalibrate() {
    if (_measurements.length < 3) return;

    // On travaille sur les 20 dernières mesures (fenêtre glissante)
    final window = _measurements.length > 20
        ? _measurements.sublist(_measurements.length - 20)
        : _measurements;

    double totalDist  = 0, totalGain = 0, totalLoss = 0, totalTime = 0;
    for (final m in window) {
      totalDist  += m.distanceM;
      totalGain  += m.elevGain;
      totalLoss  += m.elevLoss;
      totalTime  += m.actualSeconds;
    }

    if (totalDist < 50 || totalTime < 30) return;

    // Vitesse horizontale mesurée (km/h)
    final measuredHSpeed = (totalDist / 1000.0) / (totalTime / 3600.0);

    // Taux de montée mesuré (m/h) — uniquement sur les segments avec gain
    double gainTime = 0, gainDist = 0;
    for (final m in window) {
      if (m.elevGain > 2) {
        gainTime += m.actualSeconds;
        gainDist += m.elevGain;
      }
    }
    final measuredAscentRate = gainTime > 0
        ? gainDist / (gainTime / 3600.0)
        : _params.ascentRate; // pas assez de données D+

    // Taux de descente mesuré
    double lossTime = 0, lossDist = 0;
    for (final m in window) {
      if (m.elevLoss > 2) {
        lossTime += m.actualSeconds;
        lossDist += m.elevLoss;
      }
    }
    final measuredDescentRate = lossTime > 0
        ? lossDist / (lossTime / 3600.0)
        : _params.descentRate;

    // Validation : on ignore les valeurs aberrantes
    if (measuredHSpeed < 0.5 || measuredHSpeed > 20) return;
    if (measuredAscentRate < 50 || measuredAscentRate > 1500) return;

    final measured = MunterParams(
      horizontalSpeed: measuredHSpeed,
      ascentRate:      measuredAscentRate,
      descentRate:     measuredDescentRate,
    );

    // Poids de calibration : monte progressivement avec le temps de sortie
    // 0% à 0 min → 50% à 20 min → 80% à 40 min (plafond)
    final totalMinutes = totalTime / 60.0;
    _calibrationWeight = (totalMinutes / 50.0).clamp(0.0, 0.80);

    final baseline = _resolveBaseParams(profile);
    _params = baseline.blend(measured, _calibrationWeight);
  }

  // ── Utils ────────────────────────────────────────────────────────────────

  static MunterParams _resolveBaseParams(UserProfile profile) {
    return _baseTable[profile.activity]![profile.fitness]!;
  }

  /// Rapport de debugging / affichage dans l'UI de calibration.
  Map<String, dynamic> calibrationReport() => {
    'weight':           (_calibrationWeight * 100).toStringAsFixed(0) + '%',
    'isCalibrated':     isCalibrated,
    'measurements':     _measurements.length,
    'horizontalSpeed':  _params.horizontalSpeed.toStringAsFixed(2),
    'ascentRate':       _params.ascentRate.toStringAsFixed(0),
    'descentRate':      _params.descentRate.toStringAsFixed(0),
  };
}

// ─── Données internes ─────────────────────────────────────────────────────────

class _GpsMeasurement {
  final double distanceM;
  final double elevGain;
  final double elevLoss;
  final double actualSeconds;

  const _GpsMeasurement({
    required this.distanceM,
    required this.elevGain,
    required this.elevLoss,
    required this.actualSeconds,
  });
}
