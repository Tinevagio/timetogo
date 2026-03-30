<p align="center">
  <img src="timetogo.png" width="160" alt="TimeToGo logo"/>
</p>

<h1 align="center">TimeToGo</h1>

<p align="center">
  <strong>Estimation de temps en montagne — ski de rando, randonnée alpine, trail</strong><br/>
  Application Flutter · Open source · Licence MIT
</p>

---

## L'idée

En montagne, la question qui compte vraiment n'est pas *« suis-je plus rapide que les autres ? »* mais :

> **À partir d'où je suis maintenant, combien de temps vais-je mettre pour atteindre ce col ou ce sommet ?**

TimeToGo répond à cette question en temps réel, depuis ta position GPS, en tenant compte du relief réel et de ton propre rythme.

Pas de comparaison, pas de leaderboard, pas de réseau social. Juste toi, le terrain, et ton rythme réel.

---

## Fonctionnalités

### Isochrones adaptées au relief
Superposition visuelle de zones accessibles en **15, 30, 45 et 60 minutes** depuis ta position. Les contours se déforment intelligemment selon la topographie réelle : resserrés en montée, étirés dans la vallée et en descente.

### Position GPS réelle
L'app détecte automatiquement ta localisation. Un **mode épingle** permet de simuler les isochrones depuis n'importe quel point de la carte — idéal pour préparer un itinéraire ou calibrer les seuils Munter sur des courses que tu connais.

### Estimation ponctuelle
Un simple tap sur la carte donne immédiatement le temps estimé vers ce point, avec la distance et le dénivelé.

### Algorithme Munter adaptatif
Basé sur la méthode Munter — référence en ski de rando et alpinisme — avec trois améliorations :
- **Différenciation montée / descente** : D+ et D- s'accumulent sur le même pas, pas d'annulation artificielle
- **Contrainte dominante** : `max(t_horizontal, t_D+ + t_D-)` pour chaque segment
- **Calibration automatique** : après 20–40 min de sortie, l'app mesure ton rythme réel (m D+/h, km/h) et affine ses prédictions en continu

### Profil personnalisé
Au lancement, tu renseignes en quelques secondes :
- **Activité** : randonnée · ski de rando · trail
- **Niveau** : débutant · entraîné · warrior
- **Conditions** : normal · terrain difficile · neige lourde

### Topographie haute résolution
- **Mode HGT SRTM1 (30m)** : téléchargement par massif (~12MB compressé), fonctionne entièrement hors-ligne. Résolution 12× supérieure au mode en ligne.
- **Mode Open-Meteo** : grille dense sans téléchargement préalable, résolution ~400m, connexion nécessaire.
- **Fallback synthétique** : terrain généré localement si aucune connexion disponible.

### Fond de carte topographique
OpenTopoMap avec courbes de niveau et relief visible — la carte de référence pour la montagne, avec cache local automatique des tuiles.

---

## Zones topographiques disponibles

| Massif | Fichier | Zones couvertes |
|---|---|---|
| Mont-Blanc / Chamonix | N45E006 | Chamonix, Argentière, Contamines |
| Belledonne / Chartreuse | N45E005 | Grenoble, Chamrousse, Prabert |
| Écrins / Oisans | N44E005 | Alpe d'Huez, La Grave, Briançon |
| Vanoise Est | N45E006 | Tignes, Val-d'Isère, Bonneval |
| Gran Paradiso / Aoste | N45E007 | Haute-Maurienne, Val d'Aoste |
| Mercantour | N43E006 | Alpes-Maritimes, Vésubie |
| Pyrénées Centrales | N42E000 | Gavarnie, Vignemale, Cauterets |
| Pyrénées Orientales | N42E001 | Canigou, Font-Romeu, Carlit |
| Jura / Vosges | N47E006 | Crêt de la Neige, Ballon d'Alsace |
| Massif Central N | N45E002 | Puy de Dôme, Cantal |

Source : [AWS Terrain Tiles (Skadi)](https://registry.opendata.aws/terrain-tiles/) — données publiques SRTM1, sans authentification requise.

---

## Architecture technique

```
lib/
├── main.dart                               # Point d'entrée
├── app_state.dart                          # État global (ChangeNotifier + GPS)
├── munter.dart                             # Algorithme Munter + calibration
├── isochrone.dart                          # Ray-casting adaptatif + Chaikin smooth
├── providers/
│   ├── hgt_elevation_provider.dart         # Lecture HGT SRTM1, interpolation bilinéaire
│   ├── hgt_downloader.dart                 # Téléchargement et décompression .hgt.gz
│   ├── open_meteo_elevation_provider.dart  # Grille Open-Meteo, fallback réseau
│   └── demo_elevation_provider.dart        # Terrain synthétique (offline complet)
├── screens/
│   ├── map_screen.dart                     # Écran carte principal
│   └── zones_screen.dart                  # Gestion des zones HGT
└── widgets/
    ├── isochrone_layer.dart                # Layer flutter_map pour les contours
    └── profile_sheet.dart                 # Bottom sheet profil utilisateur
```

### Stack

| Composant | Choix | Raison |
|---|---|---|
| Framework | Flutter | Cross-platform iOS/Android, performances natives |
| Carte | flutter_map + OpenTopoMap | Tuiles topo offline-friendly, pas de clé API |
| DEM offline | HGT SRTM1 via AWS Skadi | 30m de résolution, ~12MB/massif, sans auth |
| DEM en ligne | Open-Meteo Elevation API | Gratuit, sans clé, batch jusqu'à 100 points |
| GPS | geolocator | Stream de positions avec filtre distance (20m) |
| Calculs | Dart pur | Tout local, pas de backend, offline-first |

### Algorithme isochrone (ray-casting adaptatif)

Pour chaque rayon (72 directions), l'algo avance pas à pas depuis la position de départ :

1. **Sonde** : mesure la pente locale sur 15m pour choisir la taille du pas (15m à 250m)
2. **Pas** : calcule la nouvelle position et l'altitude via le DEM (interpolation bilinéaire)
3. **Munter** : estime le temps — `max(t_horizontal, t_D+ + t_D-)`
4. **Seuil** : interpolation linéaire quand le temps cumulé dépasse le budget
5. **Lissage** : algorithme de Chaikin (2 itérations) sur le contour final

La grille DEM est pré-chargée une seule fois avant le calcul et mise en cache — zéro requête réseau pendant le ray-casting.

---

## Lancer le projet

```bash
git clone https://github.com/votre-compte/timetogo.git
cd timetogo
flutter pub get
flutter run
```

Testé sur Android (Pixel 9a) avec Flutter 3.x, AGP 8.6, Kotlin 2.1.

Pour les **zones topographiques**, ouvre l'écran Zones (icône montagne dans la barre) et télécharge le massif de ta zone sur WiFi avant ta sortie.

---

## Roadmap

- [ ] Calibration GPS automatique en sortie (brancher `MunterEngine.addGpsMeasurement()` sur le stream de positions)
- [ ] Import GPX pour prévisualiser un itinéraire et estimer le temps total
- [ ] Calibration par type de neige (poudreuse / tassée / croûtée)
- [ ] Mode trail : prise en compte de la fatigue en altitude
- [ ] Isochrones en mode "retour" : combien de temps pour revenir au point de départ
- [ ] Widget iOS / Android pour accès rapide depuis l'écran verrouillé
- [ ] Intégration dictées audio de conditions neigeuses

---

## Contributions

Bienvenues, en particulier sur :
- Optimisation du ray-casting (parallélisation des rayons via isolates)
- Gestion offline avancée (pré-cache de tuiles carte par zone)
- Support d'autres massifs (Alpes suisses, autrichiennes, Dolomites, Scandinavie)
- Tests unitaires sur les calculs Munter et l'interpolation HGT
- Interface pensée pour les gants (boutons larges, contraste élevé)

---

## Licence

MIT — voir [LICENSE](LICENSE)

---

*Pas de publicité. Pas de tracking. Pas de compte requis.*  
*Les données de position restent sur l'appareil.*
