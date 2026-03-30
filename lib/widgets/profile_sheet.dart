// lib/widgets/profile_sheet.dart
//
// Bottom sheet de configuration du profil utilisateur.
// S'affiche au premier lancement et via le bouton settings.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../munter.dart';

class ProfileSheet extends StatelessWidget {
  const ProfileSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ProfileSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state  = context.watch<GhostTimeState>();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color:        scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24,
          24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Mon profil', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),

          // Activité
          _SectionLabel('Activité'),
          const SizedBox(height: 8),
          _SegmentedRow<ActivityType>(
            values:   ActivityType.values,
            selected: state.activity,
            label:    _activityLabel,
            icon:     _activityIcon,
            onTap:    context.read<GhostTimeState>().setActivity,
          ),
          const SizedBox(height: 20),

          // Niveau
          _SectionLabel('Niveau'),
          const SizedBox(height: 8),
          _SegmentedRow<FitnessLevel>(
            values:   FitnessLevel.values,
            selected: state.fitness,
            label:    _fitnessLabel,
            icon:     _fitnessIcon,
            onTap:    context.read<GhostTimeState>().setFitness,
          ),
          const SizedBox(height: 20),

          // Terrain
          _SectionLabel('Conditions'),
          const SizedBox(height: 8),
          _SegmentedRow<TerrainCondition>(
            values:   TerrainCondition.values,
            selected: state.terrain,
            label:    _terrainLabel,
            icon:     _terrainIcon,
            onTap:    context.read<GhostTimeState>().setTerrain,
          ),
          const SizedBox(height: 28),

          // Résumé Munter
          _MunterSummary(),
          const SizedBox(height: 20),

          // Bouton lancer
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context);
                // L'utilisateur clique "Calculer" explicitement — pas d'auto-trigger
              },
              child: const Text('Valider le profil'),
            ),
          ),
        ],
      ),
    );
  }

  static String _activityLabel(ActivityType v) => switch (v) {
    ActivityType.hiking    => 'Randonnée',
    ActivityType.skiTouring => 'Ski de rando',
    ActivityType.trail     => 'Trail',
  };
  static IconData _activityIcon(ActivityType v) => switch (v) {
    ActivityType.hiking    => Icons.hiking,
    ActivityType.skiTouring => Icons.downhill_skiing,
    ActivityType.trail     => Icons.directions_run,
  };

  static String _fitnessLabel(FitnessLevel v) => switch (v) {
    FitnessLevel.beginner => 'Débutant',
    FitnessLevel.trained  => 'Entraîné',
    FitnessLevel.warrior  => 'Warrior',
  };
  static IconData _fitnessIcon(FitnessLevel v) => switch (v) {
    FitnessLevel.beginner => Icons.sentiment_satisfied,
    FitnessLevel.trained  => Icons.sentiment_very_satisfied,
    FitnessLevel.warrior  => Icons.local_fire_department,
  };

  static String _terrainLabel(TerrainCondition v) => switch (v) {
    TerrainCondition.normal           => 'Normal',
    TerrainCondition.difficultTerrain => 'Difficile',
    TerrainCondition.heavySnow        => 'Neige lourde',
  };
  static IconData _terrainIcon(TerrainCondition v) => switch (v) {
    TerrainCondition.normal           => Icons.check_circle_outline,
    TerrainCondition.difficultTerrain => Icons.terrain,
    TerrainCondition.heavySnow        => Icons.ac_unit,
  };
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    ),
  );
}

class _SegmentedRow<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final IconData Function(T) icon;
  final void Function(T) onTap;

  const _SegmentedRow({
    required this.values,
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: values.map((v) {
        final active = v == selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => onTap(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(
                color:        active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border:       active ? Border.all(color: scheme.primary, width: 1.5) : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon(v),
                    color: active ? scheme.primary : scheme.onSurfaceVariant,
                    size: 22,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label(v),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                      color:     active ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MunterSummary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state  = context.watch<GhostTimeState>();
    final report = state.calibratorReport;
    final scheme = Theme.of(context).colorScheme;
    final isCalibrated = state.isCalibrated;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.speed, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('Paramètres Munter',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
            const Spacer(),
            // Badge calibration
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isCalibrated ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: isCalibrated ? null : Border.all(color: scheme.outline, width: 0.5),
              ),
              child: Text(
                isCalibrated
                    ? '✓ Calibré ${report['poids']}'
                    : report['calibré'] ?? 'Baseline',
                style: TextStyle(
                  fontSize: 11,
                  color: isCalibrated ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: isCalibrated ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _StatRow('Vitesse horiz.', '${report['hSpeed']} km/h'),
          _StatRow('D+ / heure',     '${report['ascentRate']} m/h'),
          _StatRow('D- / heure',     '${report['descentRate']} m/h'),
          if (report['segments'] != null && report['segments'] != '0 acceptés, 0 rejetés') ...[
            const SizedBox(height: 4),
            Text(report['segments']!,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const Spacer(),
        Text(value,  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: scheme.onSurface)),
      ]),
    );
  }
}
