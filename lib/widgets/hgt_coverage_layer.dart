// lib/widgets/hgt_coverage_layer.dart
//
// Affiche sur la carte les zones HGT installées et manquantes.
// Tap sur une zone manquante → téléchargement direct.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../providers/hgt_elevation_provider.dart';
import '../providers/hgt_downloader.dart';
import '../isochrone.dart' show LatLng;

class HgtCoverageLayer extends StatefulWidget {
  final LatLng position;
  final bool visible;

  const HgtCoverageLayer({
    super.key,
    required this.position,
    required this.visible,
  });

  @override
  State<HgtCoverageLayer> createState() => _HgtCoverageLayerState();
}

class _HgtCoverageLayerState extends State<HgtCoverageLayer> {
  List<String> _installed = [];
  List<String> _needed    = [];
  final Map<String, DownloadProgress> _downloading = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(HgtCoverageLayer old) {
    super.didUpdateWidget(old);
    if (old.position.lat != widget.position.lat ||
        old.position.lng != widget.position.lng ||
        old.visible != widget.visible) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final installed = await HgtElevationProvider.installedTiles();
    final needed    = _tilesNeededAround(widget.position);
    if (mounted) {
      setState(() {
        _installed = installed;
        _needed    = needed.where((t) => !installed.contains(t)).toList();
      });
    }
  }

  Future<void> _download(String tile) async {
    if (_downloading.containsKey(tile)) return;
    setState(() => _downloading[tile] =
        const DownloadProgress(status: DownloadStatus.downloading, progress: 0));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Téléchargement $tile…'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.blueGrey.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    }

    await HgtDownloader.downloadTile(tile, onProgress: (p) {
      if (mounted) setState(() => _downloading[tile] = p);
    });

    final prog = _downloading[tile];
    if (prog?.status == DownloadStatus.done) {
      HgtElevationProvider.invalidateCache(tile);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(prog?.status == DownloadStatus.done
            ? '✓ $tile installé — recalcule les isochrones'
            : '✗ Échec téléchargement $tile'),
        backgroundColor: prog?.status == DownloadStatus.done
            ? Colors.green.shade700
            : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
      setState(() => _downloading.remove(tile));
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    final polygons  = <Polygon>[];
    final polylines = <Polyline>[];
    final markers   = <Marker>[];

    // Zones installées — contour vert
    for (final tile in _installed) {
      final bounds = _tileBounds(tile);
      if (bounds == null) continue;
      polygons.add(Polygon(
        points:            bounds,
        color:             Colors.green.withOpacity(0.06),
        borderColor:       Colors.green.withOpacity(0.6),
        borderStrokeWidth: 1.5,
      ));
      final m = _tileMarker(tile, installed: true, downloading: null);
      if (m != null) markers.add(m);
    }

    // Zones manquantes — contour orange + label cliquable
    for (final tile in _needed) {
      final bounds = _tileBounds(tile);
      if (bounds == null) continue;
      final isDownloading = _downloading.containsKey(tile);
      polylines.add(Polyline(
        points:      bounds + [bounds.first],
        color:       isDownloading
            ? Colors.blue.withOpacity(0.8)
            : Colors.orange.withOpacity(0.8),
        strokeWidth: isDownloading ? 2.5 : 1.5,
      ));
      final m = _tileMarker(tile,
          installed:   false,
          downloading: _downloading[tile]);
      if (m != null) markers.add(m);
    }

    return Stack(children: [
      PolygonLayer(polygons: polygons),
      PolylineLayer(polylines: polylines),
      MarkerLayer(markers: markers),
    ]);
  }

  Marker? _tileMarker(String tile, {
    required bool installed,
    required DownloadProgress? downloading,
  }) {
    final center = _tileCenter(tile);
    if (center == null) return null;

    final isDownloading = downloading != null &&
        downloading.status == DownloadStatus.downloading ||
        downloading?.status == DownloadStatus.extracting;

    return Marker(
      point:  center,
      width:  180,
      height: 52,
      child: GestureDetector(
        onTap: installed || isDownloading ? null : () => _download(tile),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: installed
                  ? Colors.green.shade600
                  : isDownloading
                      ? Colors.blue.shade600
                      : Colors.orange.shade700,
              width: 1.5,
            ),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black12)],
          ),
          child: isDownloading
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      value: downloading!.progress,
                      strokeWidth: 2,
                      color: Colors.blue.shade600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('$tile ${(downloading.progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 11, color: Colors.blue.shade700,
                        fontWeight: FontWeight.w600)),
                ])
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    installed ? Icons.check_circle : Icons.download,
                    size: 14,
                    color: installed ? Colors.green.shade700 : Colors.orange.shade800,
                  ),
                  const SizedBox(width: 5),
                  Flexible(child: Text(
                    installed ? '✓ $tile (30m)' : 'Tap → télécharger $tile',
                    style: TextStyle(
                      fontSize: 11,
                      color: installed ? Colors.green.shade700 : Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  )),
                ]),
        ),
      ),
    );
  }

  // ── Utilitaires ───────────────────────────────────────────────────────────

  static List<String> _tilesNeededAround(LatLng pos) {
    final la = pos.lat.floor();
    final lo = pos.lng.floor();
    final result = <String>[];
    for (int dLat = -1; dLat <= 1; dLat++) {
      for (int dLng = -1; dLng <= 1; dLng++) {
        result.add(_keyFromInts(la + dLat, lo + dLng));
      }
    }
    return result;
  }

  static String _keyFromInts(int la, int lo) {
    final latStr = la >= 0
        ? 'N${la.abs().toString().padLeft(2,'0')}'
        : 'S${la.abs().toString().padLeft(2,'0')}';
    final lngStr = lo >= 0
        ? 'E${lo.abs().toString().padLeft(3,'0')}'
        : 'W${lo.abs().toString().padLeft(3,'0')}';
    return '$latStr$lngStr';
  }

  static List<ll.LatLng>? _tileBounds(String tile) {
    try {
      final la = int.parse(tile.substring(1, 3)) * (tile[0] == 'S' ? -1 : 1);
      final lo = int.parse(tile.substring(4, 7)) * (tile[3] == 'W' ? -1 : 1);
      return [
        ll.LatLng(la.toDouble(),  lo.toDouble()),
        ll.LatLng(la.toDouble(),  lo + 1.0),
        ll.LatLng(la + 1.0,       lo + 1.0),
        ll.LatLng(la + 1.0,       lo.toDouble()),
      ];
    } catch (_) { return null; }
  }

  static ll.LatLng? _tileCenter(String tile) {
    try {
      final la = int.parse(tile.substring(1, 3)) * (tile[0] == 'S' ? -1 : 1);
      final lo = int.parse(tile.substring(4, 7)) * (tile[3] == 'W' ? -1 : 1);
      return ll.LatLng(la + 0.5, lo + 0.5);
    } catch (_) { return null; }
  }
}
