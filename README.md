# Stellar Sigth : prototype de galaxie

Premier prototype du 4X spatial Stellar Sigth, pour **Godot 4.7**. Il couvre l'étape 1 de la première version : génération d'une galaxie spirale de 150 systèmes, routes de saut, caméra, sélection d'un système et horloge en temps réel pausable.

![Aperçu de la galaxie](docs/apercu-galaxie.png)

## Lancer le prototype

1. Copier le dossier `stellar-sigth` sur ton PC.
2. Ouvrir Godot 4.7, cliquer sur **Importer**, choisir le fichier `project.godot`.
3. Appuyer sur **F5** (ou le bouton Lecture).

## Commandes

| Action | Commande |
| --- | --- |
| Pause / reprise | Espace |
| Vitesse 1 à 5 | Touches 1 à 5 (rangée du haut ou pavé numérique) |
| Sélectionner un système | Clic gauche |
| Désélectionner | Échap |
| Se déplacer | Clic droit glissé, molette enfoncée, ZQSD ou flèches |
| Zoomer | Molette (vers le curseur) |
| Nouvelle galaxie | R |

Le jeu démarre en pause, le 01/01/2400. Les noms des systèmes apparaissent quand on zoome.

## Organisation du code

La simulation et l'affichage sont séparés dès maintenant, pour pouvoir ajouter le multijoueur et passer en 2,5D sans tout réécrire.

```
scripts/
  sim/                    Simulation pure (aucun affichage)
    star_system.gd        Un système : nom, position 2D, type d'étoile, voisins
    galaxy.gd             Systèmes + routes de saut, recherche du système le plus proche
    galaxy_generator.gd   Génération procédurale à partir d'une graine
    game_clock.gd         Horloge (autoload GameClock) : jours de jeu, pause, 5 vitesses
  view/                   Affichage 2D (sera remplacé par la 2,5D)
    galaxy_view.gd        Dessin des étoiles, routes, sélection, noms
    galaxy_camera.gd      Zoom et déplacement
  ui/
    hud.gd                Barre du haut, fiche du système, aide
  main.gd                 Assemble le tout et gère les entrées
```

Principes :

- **Même graine, même galaxie.** La graine est affichée en haut ; elle servira aux sauvegardes et au multijoueur.
- **Un jour de jeu = un tick de simulation**, à pas fixe, indépendant de la cadence d'affichage.
- **La vue ne modifie jamais la simulation**, elle la lit seulement.

## Tests

Un test de fumée vérifie la génération (plusieurs graines : 150 systèmes, galaxie connectée, noms uniques, déterminisme), l'horloge et la scène principale avec des entrées simulées (pause, vitesse, clic, Échap, R) :

```
godot --headless --path . -s res://tests/smoke_test.gd
```

Il affiche `OK : N vérifications passées.` et renvoie le code 0 si tout passe, 1 sinon.

## Limites connues

- Pas encore de gameplay : c'est l'étape 2 (empires, brouillard de guerre, colonisation).
