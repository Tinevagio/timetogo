// lib/screens/zones_screen.dart
//
// Écran de gestion des zones topographiques (HGT).
// Accessible depuis le menu ou automatiquement si aucun HGT n'est installé.

import 'package:flutter/material.dart';
import '../providers/hgt_elevation_provider.dart';
import '../providers/hgt_downloader.dart';

class ZonesScreen extends StatefulWidget {
  const ZonesScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.push(context,
      MaterialPageRoute(builder: (_) => const ZonesScreen()));
  }

  @override
  State<ZonesScreen> createState() => _ZonesScreenState();
}

class _ZonesScreenState extends State<ZonesScreen> {
  List<String> _installed = [];
  final Map<String, DownloadProgress> _progress = {};

  @override
  void initState() {
    super.initState();
    _loadInstalled();
  }

  Future<void> _loadInstalled() async {
    final tiles = await HgtElevationProvider.installedTiles();
    setState(() => _installed = tiles);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zones topographiques'),
        backgroundColor: scheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelp,
          ),
        ],
      ),
      body: Column(children: [
        // Bandeau info
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: scheme.primaryContainer,
          child: Row(children: [
            Icon(Icons.terrain, color: scheme.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Téléchargez les zones avant votre sortie pour des isochrones précises à 90m.',
              style: TextStyle(fontSize: 13, color: scheme.onPrimaryContainer),
            )),
          ]),
        ),

        // Liste des massifs
        Expanded(
          child: ListView.builder(
            itemCount: HgtMassif.alpinesMassifs.length,
            itemBuilder: (_, i) => _MassifTile(
              massif:    HgtMassif.alpinesMassifs[i],
              installed: _installed.contains(HgtMassif.alpinesMassifs[i].tile),
              progress:  _progress[HgtMassif.alpinesMassifs[i].tile],
              onDownload: () => _download(HgtMassif.alpinesMassifs[i]),
              onDelete:   () => _delete(HgtMassif.alpinesMassifs[i]),
            ),
          ),
        ),

        // Footer stockage
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${_installed.length} zone(s) installée(s)  •  ~${(_installed.length * 25).toStringAsFixed(0)}MB utilisés',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }

  Future<void> _download(HgtMassif massif) async {
    setState(() => _progress[massif.tile] = const DownloadProgress(
      status: DownloadStatus.downloading));

    await HgtDownloader.downloadTile(
      massif.tile,
      onProgress: (p) => setState(() => _progress[massif.tile] = p),
    );

    await _loadInstalled();
    setState(() => _progress.remove(massif.tile));
  }

  Future<void> _delete(HgtMassif massif) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Supprimer ${massif.name} ?'),
        content: const Text('Le fichier topographique sera supprimé du stockage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true),  child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirm == true) {
      await HgtElevationProvider.deleteTile(massif.tile);
      await _loadInstalled();
    }
  }

  void _showHelp() {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('À propos des zones'),
      content: const Text(
        'Les fichiers topographiques (HGT SRTM1) donnent l\'altitude avec une '
        'précision de 30m — bien meilleure que le mode en ligne (~400m).\n\n'
        'Chaque fichier couvre environ 100km × 100km et pèse ~25MB une fois installé (~12MB à télécharger).\n\n'
        'Téléchargez les zones de vos sorties habituelles sur WiFi '
        'avant de partir. Une fois installées, elles fonctionnent '
        'entièrement hors-ligne.',
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
      ],
    ));
  }
}

// ── Tuile massif ──────────────────────────────────────────────────────────────

class _MassifTile extends StatelessWidget {
  final HgtMassif massif;
  final bool installed;
  final DownloadProgress? progress;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _MassifTile({
    required this.massif,
    required this.installed,
    required this.progress,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme     = Theme.of(context).colorScheme;
    final isLoading  = progress != null && progress!.status != DownloadStatus.done
        && progress!.status != DownloadStatus.error;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Icône statut
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: installed
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                installed ? Icons.check_circle : Icons.download_outlined,
                size: 20,
                color: installed ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(massif.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Text(massif.description,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            )),
            // Badge taille
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('~12 MB', style: TextStyle(fontSize: 11)),
            ),
          ]),

          // Barre de progression
          if (isLoading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress!.progress),
            const SizedBox(height: 4),
            Text(
              progress!.status == DownloadStatus.extracting
                  ? 'Extraction…'
                  : 'Téléchargement… ${(progress!.progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],

          // Erreur
          if (progress?.status == DownloadStatus.error) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.error_outline, size: 14, color: scheme.error),
              const SizedBox(width: 4),
              Expanded(child: Text(progress!.error ?? 'Erreur',
                style: TextStyle(fontSize: 11, color: scheme.error))),
            ]),
          ],

          // Boutons
          if (!isLoading) ...[
            const SizedBox(height: 12),
            Row(children: [
              if (installed) ...[
                FilledButton.tonal(
                  onPressed: onDelete,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.errorContainer,
                    foregroundColor: scheme.onErrorContainer,
                  ),
                  child: const Text('Supprimer'),
                ),
                const SizedBox(width: 8),
                Text('Installé  ✓',
                  style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
              ] else
                FilledButton.icon(
                  // onPressed null désactive le bouton pendant le download
                  onPressed: progress != null ? null : onDownload,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Télécharger'),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}
