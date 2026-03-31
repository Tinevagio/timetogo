// lib/screens/map_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../isochrone.dart';
import '../widgets/isochrone_layer.dart';
import '../widgets/profile_sheet.dart';
import '../widgets/hgt_coverage_layer.dart';
import 'zones_screen.dart';
import '../widgets/profile_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final MapController _mapController;
  bool _showDemoInfo    = true;
  bool _centeredOnce    = false;
  bool _showCoverage    = false; // toggle couverture HGT

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  Widget build(BuildContext context) {
    final state  = context.watch<GhostTimeState>();
    final scheme = Theme.of(context).colorScheme;

    // Centrage automatique au premier fix GPS
    if (!_centeredOnce && state.gpsPosition != null) {
      _centeredOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(
          ll.LatLng(state.position.lat, state.position.lng),
          13.0,
        );
      });
    }

    return Scaffold(
      body: Stack(children: [

        // ── Carte ──────────────────────────────────────────────────────────
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: ll.LatLng(state.position.lat, state.position.lng),
            initialZoom:   13.0,
            // Carte figée au nord — pas de rotation par geste
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onTap:       (_, latlng) => _onTap(latlng),
            onLongPress: (_, latlng) => _onLongPress(latlng),
          ),
          children: [
            TileLayer(
              urlTemplate:          'https://tile.opentopomap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.ghosttime.app',
              maxNativeZoom:        17,
            ),
            IsochroneLayer(
              contours:    state.contours,
              targetPoint: state.targetPoint,
            ),
            // Couverture HGT (optionnel)
            HgtCoverageLayer(
              position: state.position,
              visible:  _showCoverage,
            ),
            // Marqueur position de départ
            MarkerLayer(markers: [
              Marker(
                point:  ll.LatLng(state.position.lat, state.position.lng),
                width:  48, height: 48,
                child: _OriginMarker(
                  mode:      state.positionMode,
                  computing: state.computing,
                ),
              ),
            ]),
          ],
        ),

        // ── Bandeau mode démo / GPS status ─────────────────────────────────
        Positioned(
          top:  MediaQuery.of(context).padding.top + 8,
          left: 16, right: 16,
          child: _StatusBanner(
            state:    state,
            onClose:  () => setState(() => _showDemoInfo = false),
            visible:  _showDemoInfo,
          ),
        ),

        // ── Indicateur calibration ──────────────────────────────────────────
        if (state.positionMode == PositionMode.gps && !state.isCalibrated)
          Positioned(
            top: MediaQuery.of(context).padding.top + (_showDemoInfo ? 72 : 8),
            left: 16,
            child: _CalibrationBadge(state: state),
          ),
          Positioned(
            top:   MediaQuery.of(context).padding.top + (_showDemoInfo ? 72 : 8),
            right: 16,
            child: IsochroneLegend(budgets: state.contours.keys.toList()),
          ),

        // ── Estimation ponctuelle ───────────────────────────────────────────
        if (state.pointEstimate != null)
          Positioned(
            bottom: 120, left: 16, right: 16,
            child: _PointEstimateCard(
              text:    state.pointEstimate!,
              onClose: () => context.read<GhostTimeState>().clearTarget(),
            ),
          ),

        // ── Info calcul ─────────────────────────────────────────────────────
        if (state.lastComputeDuration != null && state.contours.isNotEmpty)
          Positioned(
            bottom: 100, left: 0, right: 0,
            child: Center(child: _ComputeInfo(
              state.lastComputeDuration!, state.demSource,
            )),
          ),

        // ── Hint long press (si pas encore d'épingle) ──────────────────────
        if (state.contours.isEmpty && !state.computing)
          Positioned(
            bottom: 90, left: 0, right: 0,
            child: Center(child: _HintBadge(
              state.positionMode == PositionMode.gps
                ? 'Appui long sur la carte pour poser une épingle'
                : 'Appui long pour déplacer l\'épingle',
            )),
          ),

        // ── Barre d'actions ─────────────────────────────────────────────────
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 16,
          left: 16, right: 16,
          child: _ActionBar(
            mapController:  _mapController,
            showCoverage:   _showCoverage,
            onToggleCoverage: () => setState(() => _showCoverage = !_showCoverage),
          ),
        ),

      ]),
    );
  }

  // ── Interactions carte ────────────────────────────────────────────────────

  void _onTap(ll.LatLng latlng) {
    // Tap court → estimation ponctuelle vers ce point
    context.read<GhostTimeState>().estimateToPoint(
      LatLng(latlng.latitude, latlng.longitude),
    );
  }

  void _onLongPress(ll.LatLng latlng) {
    // Long press → pose une épingle comme nouveau point de départ
    final pin = LatLng(latlng.latitude, latlng.longitude);
    context.read<GhostTimeState>().setPin(pin);
    // Feedback visuel
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(children: [
          Icon(Icons.push_pin, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Flexible(child: Text('Épingle posée — calcule les isochrones depuis ce point',
              overflow: TextOverflow.ellipsis)),
        ]),
        duration:        const Duration(seconds: 3),
        backgroundColor: Colors.deepOrange.shade700,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// ── Marqueur origine ──────────────────────────────────────────────────────────

class _CalibrationBadge extends StatelessWidget {
  final GhostTimeState state;
  const _CalibrationBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final report = state.calibratorReport;
    final poids  = int.tryParse(report['poids']?.replaceAll('%','') ?? '0') ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(
            value:       poids / 80.0, // plafond 80%
            strokeWidth: 2,
            color:       Colors.amber,
            backgroundColor: Colors.white24,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          poids == 0 ? 'Calibration en attente…' : 'Calibration $poids%',
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ]),
    );
  }
}

class _OriginMarker extends StatelessWidget {
  final PositionMode mode;
  final bool computing;
  const _OriginMarker({required this.mode, required this.computing});

  @override
  Widget build(BuildContext context) {
    final isPin   = mode == PositionMode.pin;
    final color   = isPin
        ? Colors.deepOrange
        : Theme.of(context).colorScheme.primary;

    return Center(
      child: Stack(alignment: Alignment.center, children: [
        if (computing)
          SizedBox(
            width: 40, height: 40,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(
            color:  color,
            shape:  BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
          ),
          child: isPin
              ? const Icon(Icons.push_pin, size: 11, color: Colors.white)
              : null,
        ),
      ]),
    );
  }
}

// ── Bandeau status ────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final GhostTimeState state;
  final VoidCallback onClose;
  final bool visible;
  const _StatusBanner({required this.state, required this.onClose, required this.visible});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final isPin      = state.positionMode == PositionMode.pin;
    final isPaused   = state.gpsPaused;
    final isAutoSleep = state.gpsAutoSleep;

    Color bgColor;
    IconData icon;
    String text;

    if (isPin) {
      bgColor = Colors.deepOrange.shade800;
      icon    = Icons.push_pin;
      text    = 'Mode épingle — appui long pour déplacer';
    } else if (isPaused) {
      bgColor = isAutoSleep ? Colors.blueGrey.shade700 : Colors.indigo.shade700;
      icon    = Icons.pause_circle_outline;
      text    = isAutoSleep
          ? 'GPS en veille (immobile 10 min) — tap pour reprendre'
          : 'GPS en pause — tap pour reprendre';
    } else if (!state.gpsAvailable) {
      bgColor = Colors.orange.shade800;
      icon    = Icons.gps_off;
      text    = state.gpsStatus;
    } else {
      bgColor = Colors.black87;
      icon    = Icons.gps_fixed;
      text    = '${state.gpsStatus}  •  Appui long = épingle';
    }

    return GestureDetector(
      // Tap sur le bandeau → reprendre si en pause
      onTap: isPaused ? () => context.read<GhostTimeState>().resumeGps() : null,
      child: Material(
        borderRadius: BorderRadius.circular(12),
        color: bgColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(child: Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 12))),
            // Bouton pause/reprise
            if (!isPin && state.gpsAvailable)
              GestureDetector(
                onTap: isPaused
                    ? () => context.read<GhostTimeState>().resumeGps()
                    : () => context.read<GhostTimeState>().pauseGps(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(isPaused ? Icons.play_arrow : Icons.pause,
                        size: 14, color: Colors.white),
                    const SizedBox(width: 3),
                    Text(isPaused ? 'Reprendre' : 'Pause',
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ]),
                ),
              ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close, size: 16, color: Colors.white54),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Barre d'actions ───────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  final MapController mapController;
  final bool showCoverage;
  final VoidCallback onToggleCoverage;

  const _ActionBar({
    required this.mapController,
    required this.showCoverage,
    required this.onToggleCoverage,
  });

  @override
  Widget build(BuildContext context) {
    final state  = context.watch<GhostTimeState>();
    final scheme = Theme.of(context).colorScheme;
    final isPin  = state.positionMode == PositionMode.pin;

    return Row(children: [
      // Profil + Zones (stack)
      Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton(
          heroTag:   'profile',
          onPressed: () => ProfileSheet.show(context),
          tooltip:   'Profil',
          child:     const Icon(Icons.person_outline),
        ),
      ]),
      const SizedBox(width: 8),

      // Toggle GPS / Épingle
      FloatingActionButton(
        heroTag:         'gps_pin',
        onPressed:       () => _toggleMode(context, state),
        tooltip:         isPin ? 'Revenir au GPS' : 'Mode épingle',
        backgroundColor: isPin ? Colors.deepOrange.shade700 : scheme.secondaryContainer,
        child: Icon(
          isPin ? Icons.push_pin : Icons.my_location,
          color: isPin ? Colors.white : scheme.onSecondaryContainer,
        ),
      ),

      const Spacer(),

      // Zones HGT + Calcul (colonne)
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        // Bouton zones discret
        GestureDetector(
          onTap:       () => ZonesScreen.show(context),
          onLongPress: onToggleCoverage,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: showCoverage
                  ? Colors.green.shade100
                  : state.demSource.contains('HGT')
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: showCoverage
                  ? Border.all(color: Colors.green.shade600, width: 1)
                  : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.terrain, size: 13,
                color: showCoverage
                    ? Colors.green.shade700
                    : state.demSource.contains('HGT')
                        ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                showCoverage
                    ? 'Zones visibles'
                    : state.demSource.contains('HGT') ? 'HGT 30m' : 'Zones topo',
                style: TextStyle(fontSize: 11,
                  color: showCoverage
                      ? Colors.green.shade700
                      : state.demSource.contains('HGT')
                          ? scheme.primary : scheme.onSurfaceVariant),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        // Bouton calcul
        FloatingActionButton.extended(
          heroTag:   'compute',
          onPressed: state.computing
              ? null
              : () => context.read<GhostTimeState>().computeIsochrones(),
          icon: state.computing
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.radar),
          label: Text(state.computing ? 'Calcul…' : 'Isochrones'),
        ),
      ]),
    ]);
  }

  void _toggleMode(BuildContext context, GhostTimeState state) {
    if (state.positionMode == PositionMode.pin) {
      // Retour au GPS
      context.read<GhostTimeState>().switchToGps();
      mapController.move(
        ll.LatLng(state.position.lat, state.position.lng), 13,
      );
    } else {
      // Passer en mode épingle sur la position actuelle
      context.read<GhostTimeState>().setPin(state.position);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Mode épingle — appui long pour repositionner'),
          backgroundColor: Colors.deepOrange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }
}

// ── Widgets utilitaires ───────────────────────────────────────────────────────

class _PointEstimateCard extends StatelessWidget {
  final String text;
  final VoidCallback onClose;
  const _PointEstimateCard({required this.text, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      elevation: 6,
      shadowColor: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          const Icon(Icons.schedule, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          GestureDetector(
            onTap: onClose,
            child: const Icon(Icons.close, size: 18, color: Colors.black45),
          ),
        ]),
      ),
    );
  }
}

class _ComputeInfo extends StatelessWidget {
  final Duration d;
  final String demSource;
  const _ComputeInfo(this.d, this.demSource);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Calculé en ${d.inMilliseconds} ms  •  $demSource',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}

class _HintBadge extends StatelessWidget {
  final String text;
  const _HintBadge(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white70, fontSize: 11)),
    );
  }
}
