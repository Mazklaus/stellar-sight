# Stellar Sigth : prototype de galaxie

Premier prototype du 4X spatial Stellar Sigth, pour **Godot 4.7**. Il couvre l'étape 1 de la première version (galaxie spirale de 150 systèmes, routes de saut, caméra, sélection, temps réel pausable) et le noyau de simulation : état de partie, ticks déterministes, ordres des joueurs, sauvegarde et chargement.

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
| Renommer le système sélectionné | Champ « Nouveau nom » de la fiche, puis Entrée |
| Sauvegarde rapide | F5 |
| Chargement rapide | F9 |
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
    game_state.gd         État complet d'une partie (ce qu'on sauvegarde et compare)
    simulation.gd         Noyau : avance l'état tick par tick, applique les ordres
    sim_commands.gd       Ordres des joueurs : validation et application
    save_game.gd          Sauvegarde / chargement JSON avec empreinte de contrôle
    game_calendar.gd      Tick -> date de jeu
    systems/              Systèmes de simulation exécutés à chaque tick
      chronicle_system.gd Petits événements racontés par le chroniqueur
    game_clock.gd         Horloge (autoload GameClock) : pilote la simulation en temps réel, pause, 5 vitesses
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

## Noyau de simulation

![Aperçu du noyau](docs/apercu-noyau.png)

- **Un seul état, `GameState`.** Tout ce qui change en cours de partie y vit. La partie fixe de la galaxie (positions, routes) n'est pas sauvegardée : elle se régénère depuis la graine.
- **Déterministe.** Même état de départ + mêmes ordres aux mêmes ticks = même partie, à l'octet près. L'aléatoire de la simulation passe uniquement par `state.rng`, jamais par `randi()` global. `state.checksum()` donne une empreinte SHA-256 de l'état : en multijoueur, comparer les empreintes au même tick détectera les désynchronisations.
- **Les joueurs agissent par ordres.** Un ordre est un dictionnaire (`SimCommands.rename_system(...)`), soumis avec `Simulation.submit()`, revalidé puis appliqué à une frontière de tick. Pendant la pause, les ordres s'appliquent tout de suite sans faire passer le temps. Le journal `command_log` permet de rejouer une partie (`Simulation.replay`), base des rediffusions et de la reconnexion en multijoueur.
- **Le temps réel est à part.** `GameClock` transforme les secondes réelles en ticks et appelle `Simulation.step()`. Pause et vitesse sont des réglages locaux, pas de l'état de partie. En multijoueur, seul l'hôte pilotera l'horloge.
- **Sauvegarde JSON lisible** (`user://saves/quicksave.json`) avec version de format et empreinte vérifiée au chargement : un fichier abîmé ou modifié est refusé proprement. Écriture via un fichier temporaire pour ne jamais perdre la sauvegarde précédente.
- **Ajouter un système de jeu** (économie, flottes…) : un script dans `scripts/sim/systems/` avec une fonction `process(state)`, appelée dans `Simulation.step()` dans un ordre fixe.

## Tests

Un test de fumée vérifie la génération (plusieurs graines : 150 systèmes, galaxie connectée, noms uniques, déterminisme), le noyau de simulation (`tests/sim_tests.gd` : déterminisme sur 1000 ticks, ordres valides et refusés, ordres en pause, rediffusion, sauvegarde/chargement à l'identique, reprise après chargement identique à une partie jamais interrompue, fichiers abîmés refusés, performance), l'horloge et la scène principale avec des entrées simulées (pause, vitesse, clic, renommage, F5/F9, Échap, R) :

```
godot --headless --path . -s res://tests/smoke_test.gd
```

Il affiche `OK : N vérifications passées.` et renvoie le code 0 si tout passe, 1 sinon.

## Limites connues

- Pas encore de gameplay : la prochaine étape est l'économie et la colonisation (ressources, planètes, population).
- Un seul emplacement de sauvegarde (rapide) pour l'instant, pas encore de menu.
- Le multijoueur lui-même (réseau) n'est pas fait : le noyau est prêt pour un hôte qui fait autorité, mais rien n'est encore envoyé sur le réseau.
