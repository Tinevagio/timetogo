// lib/widgets/isochrone_layer.dart
//
// Layer flutter_map qui dessine les contours isochrones
// et la cible pointée par l'utilisateur.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../isochrone.dart';

// Couleurs des isochrones (du plus proche au plus loin)
const _isoColors = [
  Color(0xFF4CAF50), // 15 min — vert
  Color(0xFF2196F3), // 30 min — bleu
  Color(0xFFFF9800), // 45 min — orange
  Color(0xFFF44336), // 60 min — rouge
];

// Épaisseur de trait décroissante : la 15min est la plus visible
const _isoStrokeWidths = [3.0, 2.2, 1.8, 1.5];

class IsochroneLayer extends StatelessWidget {
  final Map<int, List<LatLng>> contours;
  final LatLng? targetPoint;

  const IsochroneLayer({
    super.key,
    required this.contours,
    this.targetPoint,
  });

  @override
  Widget build(BuildContext context) {
    final budgets = contours.keys.toList()..sort();

    final polygons = <Polygon>[];
    final polylines = <Polyline>[];

    // On dessine du plus grand au plus petit pour l'effet de remplissage
    for (int i = budgets.length - 1; i >= 0; i--) {
      final budget = budgets[i];
      final pts    = contours[budget]!;
      if (pts.isEmpty) continue;

      final color = _isoColors[i % _isoColors.length];
      final llPts = pts.map((p) => ll.LatLng(p.lat, p.lng)).toList();

      // Remplissage semi-transparent
      polygons.add(Polygon(
        points:          llPts,
        color:           color.withOpacity(0.08),
        borderColor:     Colors.transparent,
        borderStrokeWidth: 0,
      ));

      // Contour lissé — plus épais pour les isochrones courtes
      polylines.add(Polyline(
        points:      llPts + [llPts.first],
        color:       color.withOpacity(0.9),
        strokeWidth: _isoStrokeWidths[i % _isoStrokeWidths.length],
      ));
    }

    return Stack(children: [
      PolygonLayer(polygons: polygons),
      PolylineLayer(polylines: polylines),

      // Marqueur cible
      if (targetPoint != null)
        MarkerLayer(markers: [
          Marker(
            point:  ll.LatLng(targetPoint!.lat, targetPoint!.lng),
            width:  32,
            height: 32,
            child: const _TargetMarker(),
          ),
        ]),
    ]);
  }
}

class _TargetMarker extends StatelessWidget {
  const _TargetMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:  Colors.white,
        shape:  BoxShape.circle,
        border: Border.all(color: Colors.black87, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
      ),
      child: const Icon(Icons.flag, size: 18, color: Colors.black87),
    );
  }
}

// Légende des isochrones
class IsochroneLegend extends StatelessWidget {
  final List<int> budgets;

  const IsochroneLegend({super.key, required this.budgets});

  @override
  Widget build(BuildContext context) {
    final sorted = List<int>.from(budgets)..sort();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color:        Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow:    const [BoxShadow(blurRadius: 6, color: Colors.black12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sorted.asMap().entries.map((e) {
          final color = _isoColors[e.key % _isoColors.length];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 20, height: 3,
                decoration: BoxDecoration(
                  color:        color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text('${e.value} min',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            ]),
          );
        }).toList(),
      ),
    );
  }
}
