# Pictogrammes du jeu

Les icônes des technologies, bâtiments, hauts faits, reliques, préceptes et natures de foi, fouilles et
ressources sont dessinées ici, en code, puis réunies sur une seule planche que le jeu lit
(`assets/icons/atlas.png` et `assets/icons/atlas.json`, classe `GameIcon`).

Le style suit l'écran de recherche d'Endless Space 2 : un pictogramme blanc plein, les détails découpés
dans la forme, posé par le jeu dans un cadre sombre à filet coloré (disque pour une technologie, carré
pour un bâtiment, losange pour un haut fait, hexagone pour une relique, ogive pour la foi).

| Fichier | Rôle |
| --- | --- |
| `formes.py` | Outils de dessin (boîte de 64 sur 64) |
| `motifs_a.py` à `motifs_d.py` | Les motifs, un par nom |
| `table.py` | Quel motif pour quelle entrée du jeu |
| `composer.py` | Motif seul, motif et insigne, crans de rang |
| `verifier.py` | Chaque entrée a son pictogramme, sans doublon dans une famille |
| `atlas.py` | Fabrique la planche du jeu |
| `planche.py` | Fabrique une page de relecture de toutes les icônes |
| `rendu.py` | Rendu SVG et planche de contrôle des motifs |

## Ajouter une entrée

1. Ajouter une ligne à `table.py`, dans la famille voulue : `identifiant=motif`, `identifiant=motif+insigne`
   (petit motif en bas à droite) ou `identifiant=motif*2` (deux crans de rang).
2. Si aucun motif ne convient, en dessiner un dans un fichier `motifs_*.py` : une liste de couches, `+` pour
   ajouter de la matière et `-` pour en retirer.
3. Lancer `python3 tools/icons/atlas.py`. Il faut Node avec Playwright et Chromium.
4. `tools/run_tests.sh game_icon_tests` vérifie que rien ne manque.
