# Stellar Sigth : prototype de galaxie

Premier prototype du 4X spatial Stellar Sigth, pour **Godot 4.7**. Il couvre l'étape 1 de la première version (galaxie spirale de 150 systèmes, routes de saut, caméra, sélection, temps réel pausable) le noyau de simulation (état de partie, ticks déterministes, ordres des joueurs, sauvegarde et chargement) et l'économie avec la colonisation : planètes, 5 ressources, population, colonies, avant-postes et premiers bâtiments, pour les 4 factions de la première version, puis les flottes : construction de vaisseaux, déplacement en temps réel le long des routes de saut, brouillard de guerre et colonisation par vaisseau colon.

![Aperçu de la galaxie](docs/apercu-galaxie.png)

## Lancer le prototype

1. Copier le dossier `stellar-sigth` sur ton PC.
2. Ouvrir Godot 4.7, cliquer sur **Importer**, choisir le fichier `project.godot`.
3. Appuyer sur **F5** (ou le bouton Lecture). Le menu principal s'ouvre : **Nouvelle partie**, choisir son peuple, puis **Lancer la partie**.

## Commandes

| Action | Commande |
| --- | --- |
| Pause / reprise | Espace, ou le centre du cadran du temps (en bas à droite) |
| Vitesse 1 à 5 | Touches 1 à 5 (rangée du haut ou pavé numérique), ou les crans du cadran |
| Sélectionner un système | Clic gauche (le survol l'affiche dans la fiche en bas à gauche) |
| Lentille économique | L, ou l'onglet « Lentille économique » en haut |
| Ouvrir la vue système | Double-clic sur le système, Entrée, ou bouton « Entrer dans le système » |
| Système suivant / précédent de l'empire | Tab / Maj+Tab sur la carte ; Page préc. / Page suiv. ou les flèches à l'écran dans la vue système |
| Revenir à la capitale | H |
| Planète précédente / suivante (vue système) | Flèches gauche / droite, clic sur la planète ou sa carte en bas |
| Basculer vue orbitale / gestion du système | Tab, ou les onglets en haut au centre |
| Économie, Colonies, Recherche, Diplomatie | F1 à F4, ou les pictogrammes du panneau d'empire |
| Revenir en arrière | Échap : ferme le menu d'empire, puis la vue système, puis désélectionne, puis ouvre le menu du jeu. L'onglet « Vue galaxie » ramène aussi à la carte |
| Se déplacer | Clic droit glissé, molette enfoncée, ZQSD ou flèches |
| Zoomer | Molette (vers le curseur) |
| Sélectionner une flotte | Clic gauche sur son chevron, ou F / Maj+F (flotte suivante / précédente) |
| Envoyer la flotte sélectionnée | Clic droit sur un système (sans glisser) |
| Arrêter, rassembler, détacher, coloniser | Boutons de la fiche de flotte, en bas à gauche |
| Construire un vaisseau | « Chantier spatial » dans les ordres d'une colonie, dans la vue système |
| Coloniser, poser un avant-poste, construire | Section « Ordres » de la fiche de la planète, dans la vue système |
| Renommer un système | Bouton « Renommer » à côté de son nom, dans la vue système, puis Entrée |
| Sauvegarde / chargement rapide | F5 / F9, ou le menu du jeu |
| Plein écran | F11, ou Options |

## Interface et menus

![Interface de la carte](docs/apercu-interface.png)

La disposition reprend celle d'Endless Space 2, sans rien lui emprunter (dessins, polices et pictogrammes sont les nôtres) : panneaux plats et translucides aux angles droits, filets fins, police libre Exo 2 en graisses fines, capitales espacées, un seul accent cyan pour la sélection et les actions.

- **Panneau d'empire** en haut à gauche : les pictogrammes des menus d'empire, le nom et l'emblème de votre peuple (son trait en infobulle), les cinq ressources avec leur stock et leur bilan mensuel (détail production, entretien, bonus de faction et délai avant épuisement en infobulle), et une ligne d'état (chantiers, fondations, population, alertes).
- **Onglets de vue** en haut au centre : Vue galaxie, Lentille économique (la carte s'assombrit et seuls vos systèmes restent, avec leur bilan par ressource), et Gestion du système (×) quand un système est ouvert.
- **Fiche de sélection** en bas à gauche : une vignette de l'étoile, le nom, le propriétaire, une pastille par planète (cerclée de la couleur du propriétaire), une ligne d'ambiance et le bouton pour entrer dans le système. Elle montre le système survolé, sinon le système choisi.
- **Cadran du temps** en bas à droite, à la place du bouton de fin de tour : le centre met en pause, la date est dessous, les cinq crans de l'arc règlent la vitesse.
- **Étiquettes de systèmes** sur la carte : un cartouche sombre souligné de la couleur du propriétaire, et les pastilles des planètes pour vos systèmes et la sélection.
- **Écrans d'empire** en plein écran, comme dans Endless Space 2 : la carte s'efface derrière un voile, le panneau d'empire et le cadran restent, un onglet en haut au centre nomme l'écran et le ferme, une colonne à gauche résume, et le contenu se range en blocs titrés.
  - **Économie** : bilan des ressources (stock, production, entretien, bilan, tendance), anneau de répartition de la production, production par système (un clic ouvre le système), alertes. La colonne montre votre peuple et ses chiffres clés.
  - **Colonies** : liste filtrable (toutes, colonies, avant-postes, fondations), fiche de la colonie choisie avec son illustration et un bouton pour ouvrir sa vue système (ou double-clic sur la ligne). La colonne fait le compte dans un anneau.
  - **Recherche** et **Diplomatie** : écrans en place, en attente de leurs systèmes (arbre des technologies par ères, empires de la galaxie, emplacements de traités verrouillés).
- **Navigation fluide** : la caméra glisse vers le système choisi (Tab, H), la vue système s'ouvre en fondu, et les flèches de son en-tête passent d'un système de l'empire à l'autre.
- **Chronique galactique** en haut à droite (les six dernières entrées en infobulle). Les notifications (sauvegarde, ordre refusé) apparaissent sous les onglets et s'effacent seules.
- **Menu principal**, sur le modèle de celui d'Endless Space 2 : une grande planète à gauche, les entrées (Continuer ou Reprendre, Nouvelle partie, Options, Quitter) posées le long de son orbite avec un pictogramme rond et une bulle d'aide au survol, l'emblème-titre dans un anneau à droite, sur la galaxie qui dérive.
- **Nouvelle partie**, sur le modèle du choix de faction d'Endless Space 2 : une rangée de portraits (les 4 peuples et « Au hasard »), la grande illustration du peuple choisi à droite, puis ses affinités et traits, son histoire et les réglages de la galaxie (graine facultative : un nombre ou un mot). Boutons ronds Retour et Commencer.
- **Menu du jeu** (Échap) : le temps s'arrête et reprend comme avant à la fermeture. Reprendre, Sauvegarder, Charger, Raccourcis (rangés par thème), Options, Menu principal, Quitter (page de confirmation Annuler / Quitter).
- **Options**, en pleine page comme dans Endless Space 2 : titre centré, onglets (Affichage, Partie, Commandes), une ligne par réglage avec sa valeur dans une case sombre, boutons ronds Retour et Valeurs par défaut dans les coins. Réglages : plein écran, échelle de l'interface (100, 125 ou 150 %), pause automatique dans les écrans d'empire ; l'onglet Commandes liste les raccourcis. Ce sont des réglages du poste (`user://settings.cfg`), jamais enregistrés dans la partie.

![Lentille économique](docs/apercu-lentille-economique.png)
![Menu principal](docs/apercu-menu-principal.png)
![Options](docs/apercu-options.png)
![Nouvelle partie](docs/apercu-nouvelle-partie.png)
![Écran Économie](docs/apercu-ecran-economie.png)
![Écran Colonies](docs/apercu-menus-empire.png)

L'interface ne fait que lire la partie et émettre des demandes : les bilans des menus d'empire viennent de `EmpireReport` (côté simulation, en lecture seule, avec les mêmes règles qu'`Economy`), et tout changement passe toujours par un ordre.

### Emplacements d'illustrations

Les portraits de peuples, les bandeaux des écrans d'empire, la planète de la colonie choisie, le bandeau de la galaxie et le fond du menu principal sont des emplacements (`Widgets.ArtSlot`). Tant qu'il n'y a pas d'image, un motif dessiné tient la place dans la bonne teinte. Pour habiller le jeu, il suffira de déposer une image nommée d'après l'emplacement dans `assets/art/` (liste dans [assets/art/LISEZMOI.md](assets/art/LISEZMOI.md)) : aucun code à changer.

Sources d'inspiration étudiées : captures d'Endless Space 2 de la galerie [HUDS+GUIS](https://www.hudsandguis.com/home/2017/7/6/endless-space-2) (écran du Sénat, quêtes, nouvelle partie, choix de faction, choix du gouvernement) ainsi que celles d'[interfaceingame.com](https://interfaceingame.com/games/endless-space-2/) (menu principal, options, menu du jeu, confirmation), et le [guide de l'interface de Gamepressure](https://www.gamepressure.com/endless-space-2/interface-summary/z49c44). Seules la disposition et l'ergonomie s'en inspirent.

## Vue système

![Vue orbitale](docs/apercu-vue-systeme.png)

Chaque système a son écran, avec deux vues (onglets en haut au centre, ou Tab) :

- **Vue orbitale** : l'étoile au centre (couronne, faisceaux d'une étoile à neutrons ou disque d'un trou noir), les planètes qui tournent sur leurs orbites, éclairées du côté de l'étoile, et les ceintures d'astéroïdes. Chaque planète porte une fiche accrochée (nom, type et taille, disponibilité : colonisable, avant-poste possible, hors de portée…) ; la planète survolée ou choisie montre aussi son potentiel par ressource. Une colonie est entourée d'un arc de population à la couleur de son empire, un losange marque une capitale. Les fiches de vos planètes établies affichent aussi leur bilan du mois.
- **Gestion** : les planètes alignées en grand pour les comparer d'un coup d'œil, avec leurs rendements par mois (ou leur potentiel si elles ne sont pas à vous), la jauge de population, la disponibilité et l'ordre principal.

![Vue de gestion](docs/apercu-vue-gestion.png)

À gauche, sous le panneau d'empire, la colonne du système : son nom (renommable), puis la fiche de la planète choisie : habitabilité pour votre espèce, potentiel, gisements, colonie, bâtiments, production et ordres. Le mouvement des orbites est décoratif et n'influence pas la partie.

Inspiration : les deux niveaux de lecture (vue orbitale avec fiches accrochées, puis vue de gestion avec les planètes côte à côte) viennent de l'étude de captures d'Endless Space 2 ([galerie HUDS+GUIS](https://www.hudsandguis.com/home/2017/7/6/endless-space-2)) ; le rendu et la mise en page restent les nôtres.

La partie démarre en pause, le 01/01/2400, centrée sur le système d'origine du peuple choisi. Les noms des systèmes apparaissent quand on zoome. Un bouton grisé explique pourquoi en survol (ressources, portée…).

## Flottes, déplacements et exploration

![Flottes et brouillard](docs/apercu-flottes.png)

- **Deux classes de vaisseaux pour commencer** (`data/ships.json`) : l'éclaireur (40 Mat, 20 j, rapide, voit à 2 sauts) et le vaisseau colon (100 Mat + 20 Nour, 40 j, lent). Chaque empire démarre avec un de chaque, comme dans Endless Space 2 où l'on commence avec un vaisseau colon. Les vaisseaux de guerre arriveront avec le combat.
- **Chantier spatial** : chaque colonie peuplée construit un vaisseau à la fois, indépendamment de son chantier de bâtiments. Le vaisseau terminé apparaît en orbite dans sa propre flotte (« Éclaireur 2 »). Chaque vaisseau coûte 1 Én d'entretien par mois.
- **Déplacement en temps réel le long des routes de saut** : clic droit sur un système, la flotte prend le plus court chemin connu et avance chaque jour de sa vitesse (celle de son vaisseau le plus lent). Le trajet et le délai s'affichent en pointillés ; le chevron glisse en continu entre deux jours. Une flotte en route peut recevoir un contre-ordre : elle finit sa route ou fait demi-tour, selon ce qui est le plus court (comme dans Stellaris). « Arrêter » la pose au système le plus proche.
- **Flottes** : « Rassembler » réunit les flottes à l'arrêt dans un même système, « Détacher » en sépare un vaisseau.
- **Brouillard de guerre** : on ne voit que ce qu'observent ses revendications (1 saut autour) et ses flottes (selon leur vision). Un système vu une fois reste exploré (comme la « terra incognita » d'Endless Space 2 que les vaisseaux dissipent pour de bon) ; hors de vue, il est assombri et les flottes étrangères y sont invisibles. Les systèmes reliés à un système exploré apparaissent comme de simples lueurs, sans nom ni planètes : on peut y envoyer une flotte, pas les ouvrir. Le reste de la galaxie et ses routes sont cachés.
- **Colonisation par vaisseau colon** : pour s'installer dans un nouveau système, il faut y amener un vaisseau colon, qui se démonte pour fonder l'avant-poste ou la colonie (il ne reste à payer que l'influence). Une fois une revendication établie dans un système, ses autres planètes se revendiquent sans vaisseau, comme avant. La règle provisoire « système voisin » disparaît.
- **Premier contact** : quand un empire aperçoit un système ou une flotte d'un autre, la chronique raconte la rencontre et les deux empires la retiennent (base de la future diplomatie).
- **Tout passe par des ordres** (`build_ship`, `move_fleet`, `stop_fleet`, `merge_fleets`, `split_fleet`), en nombres entiers et sans aléatoire. Sauvegarde en version 3 (flottes, systèmes explorés, contacts, chantiers spatiaux).

![Fiche de flotte et système inexploré](docs/apercu-flottes-fiche.png)
![Coloniser avec un vaisseau colon](docs/apercu-vaisseau-colon.png)

Références consultées pour ces mécaniques : Endless Space 2 reste le modèle principal ([déplacements et routes](https://gamepressure.com/endless-space-2/systems-and-ways-of-travelling/z29c4b), [colonisation par vaisseau colon et avant-poste](https://www.gamepressure.com/endless-space-2/colonization-migration-and-evacuation/z69c4f)), complété par d'autres 4X en temps réel : Stellaris pour les contre-ordres en plein trajet et l'exploration par vaisseaux scientifiques, Sins of a Solar Empire pour garder des trajets courts (ses joueurs se plaignent d'attendre plusieurs minutes une flotte, [discussion Steam](https://steamcommunity.com/app/1575940/discussions/1/651441204180820081)).

## Organisation du code

La simulation et l'affichage sont séparés dès maintenant, pour pouvoir ajouter le multijoueur et passer en 2,5D sans tout réécrire.

```
scripts/
  sim/                    Simulation pure (aucun affichage)
    star_system.gd        Un système : nom, position 2D, type d'étoile, voisins, planètes
    planet.gd             Une planète : type, taille, gisements
    galaxy.gd             Systèmes + routes de saut, recherche du système le plus proche
    galaxy_generator.gd   Génération procédurale à partir d'une graine
    game_state.gd         État complet d'une partie (ce qu'on sauvegarde et compare)
    simulation.gd         Noyau : avance l'état tick par tick, applique les ordres
    sim_commands.gd       Ordres des joueurs : validation et application
    save_game.gd          Sauvegarde / chargement JSON avec empreinte de contrôle
    game_calendar.gd      Tick -> date de jeu
    game_data.gd          Lecture des données de jeu (data/*.json)
    empire.gd             Un empire : faction, stocks de ressources, capitale
    colony.gd             Une colonie ou un avant-poste : population, bâtiments, chantier
    economy.gd            Règles de l'économie (calculs purs, partagés par la simulation et l'interface)
    fleet.gd              Une flotte : vaisseaux, position, trajet
    fleets.gd             Règles des flottes : chemins, délais, vision et brouillard, vérification des ordres
    empire_report.gd      Bilans d'un empire pour les menus (lecture seule) et parcours de ses systèmes
    systems/              Systèmes de simulation exécutés à chaque tick
      economy_system.gd   Fondations, chantiers, croissance chaque jour ; bilan chaque mois
      fleet_system.gd     Chantiers spatiaux, déplacements, exploration et premiers contacts
      chronicle_system.gd Petits événements racontés par le chroniqueur
    game_clock.gd         Horloge (autoload GameClock) : pilote la simulation en temps réel, pause, 5 vitesses
  view/                   Affichage 2D (sera remplacé par la 2,5D)
    galaxy_view.gd        Dessin des étoiles, routes, sélection, noms
    galaxy_camera.gd      Zoom et déplacement
    system_view.gd        Vue système : étoile, orbites, planètes animées, annotations, clic sur une planète
  ui/
    ui_theme.gd           Thème visuel : palette, polices, panneaux plats, styles nommés
    hud.gd                Interface en jeu : onglets de vue, fiche de sélection, notifications, chronique, cadran
    empire_bar.gd         Panneau d'empire (menus, ressources, ligne d'état)
    time_dial.gd          Cadran du temps (pause, date, vitesse)
    empire_screens.gd     Écrans d'empire plein écran : Économie, Colonies, Recherche, Diplomatie
    main_menu.gd          Menu principal et choix de la faction
    pause_menu.gd         Menu du jeu et liste des raccourcis
    options_panel.gd      Page Options (partagée)
    ui_settings.gd        Réglages du poste (plein écran, pause automatique)
    widgets.gd            Petits contrôles : bouton à pictogramme, infobulle enrichie, emblème, pastille, vignette d'étoile
    resource_icon.gd      Icônes vectorielles des ressources
    system_screen.gd      Écran de la vue système : colonne (en-tête, fiche et ordres), bandeau des planètes
    system_manage_panel.gd Vue de gestion : planètes alignées, rendements, jauge, disponibilité, ordre principal
    planet_info.gd        Textes sur une planète partagés par les deux écrans
assets/fonts/             Police Exo 2 (licence SIL OFL, fichier de licence à côté)
assets/art/               Illustrations d'habillage (vide pour l'instant, voir assets/art/LISEZMOI.md)
shaders/                  Rendu de la vue système (planète éclairée, étoile, fond étoilé)
tools/
  capture_system_view.gd  Captures d'écran de la vue système (rendu réel, voir l'en-tête du fichier)
  capture_ui.gd           Captures des menus et de l'interface
  capture_fleets.gd       Captures des flottes et du brouillard de guerre
  main.gd                 Assemble le tout et gère les entrées
data/                     Données de jeu en JSON : tout l'équilibrage se règle ici
  rules.json              Ressources, coûts de colonisation, croissance, gisements, monde d'origine
  factions.json           Les 4 factions de la V1 : couleur, planètes préférées, bonus
  planet_types.json       Types de planètes : habitabilité, rendements, fréquence selon l'étoile
  buildings.json          Bâtiments : coût, durée, rendement, entretien
  ships.json              Classes de vaisseaux : coût, durée, entretien, vitesse, vision
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

## Économie et colonisation

![Aperçu de l'économie](docs/apercu-economie.png)

- **5 ressources** (périmètre V1 du GDD) : énergie, matériaux, nourriture, influence et cristaux de saut. Les stocks sont dans la barre du haut avec le solde du mois. Le bilan tombe tous les 30 jours.
- **Planètes générées depuis la graine** : 8 types (continentale, océanique, désertique, glaciaire, toxique, géante gazeuse, stérile, astéroïdes), une taille de 1 à 5 et parfois un gisement (filons riches, sols fertiles, géothermie, cristaux de saut, plus fréquents près des étoiles à neutrons et des trous noirs). Leur génération utilise son propre flux aléatoire : les galaxies existantes ne changent pas.
- **4 empires au départ**, un par faction, placés loin les uns des autres sur un monde d'origine à leur goût (8 pop, capitale, fermes, mine). Le joueur est l'empire 0 ; les trois autres vivent de leur économie en attendant l'IA.
- **Habitabilité selon l'espèce** : 100 % sur le type d'origine, 80 % sur le second préféré, sinon la valeur du type (une planète toxique n'accueille que l'Essaim Kh'thari). Population max = taille × 4 × habitabilité.
- **Colonie ou avant-poste** : une colonie (150 Mat, 40 Inf, 100 jours) accueille une population ; un avant-poste (60 Mat, 20 Inf, 45 jours) revendique le système et exploite n'importe quelle planète, et peut devenir une colonie plus tard. Il faut un vaisseau colon dans le système, ou une revendication déjà établie dans ce système (voir Flottes), au plus 2 fondations à la fois, et on ne s'installe pas dans le système d'un autre empire.
- **Population** : chaque pop produit selon le type de planète et mange 1 nourriture par mois. La croissance ralentit à mesure que la colonie grandit. En famine, la plus grosse colonie perd une pop et la croissance s'arrête ; en pénurie d'énergie, les chantiers s'arrêtent.
- **6 bâtiments** : fermes hydroponiques, centrale à fusion, complexe minier, forum impérial, raffinerie de cristaux (sur gisement, même sur un avant-poste) et habitats orbitaux (+4 pop max). Un chantier à la fois par planète, autant d'emplacements que sa taille.
- **Traits de faction** : Ossarane +50 % de cristaux (gisement garanti chez soi), Chœur Éternel +25 % de matériaux mais croissance -20 %, Vael +50 % d'influence et +10 % d'énergie, Kh'thari croissance ×2 mais +50 % de nourriture consommée et influence ÷2. Les mécaniques signatures (fiefs, ferveur, héros, biomasse) viendront avec l'étape des factions jouables.
- **Tout passe par des ordres** (`SimCommands.colonize`, `SimCommands.build`) et tout est calculé en nombres entiers, sans aléatoire : déterminisme, rediffusion et sauvegarde fonctionnent comme pour le reste du noyau. Le format de sauvegarde passe en version 2 ; les sauvegardes de la version 1 sont refusées avec un message clair.

## Tests

Un test de fumée vérifie la génération (plusieurs graines : 150 systèmes, galaxie connectée, noms uniques, déterminisme), le noyau de simulation (`tests/sim_tests.gd` : déterminisme sur 1000 ticks, ordres valides et refusés, ordres en pause, rediffusion, sauvegarde/chargement à l'identique, reprise après chargement identique à une partie jamais interrompue, fichiers abîmés refusés, performance), l'économie (`tests/economy_tests.gd` : données, planètes déterministes, départ des 4 empires, bilan mensuel exact, traits de faction, colonisation et chacun de ses refus, avant-poste transformé en colonie, chantiers et emplacements, croissance plafonnée, famine, pénurie d'énergie, déterminisme, rediffusion et sauvegarde avec colonies, 10 ans sans stock négatif), les flottes (`tests/fleet_tests.gd` : flottes et vision de départ, chemins le long des routes, arrivée au jour annoncé, refus, demi-tour et arrêt en route, chantier spatial, colonisation par vaisseau colon, rassembler et détacher, entretien, premier contact, sauvegarde en plein trajet, rediffusion, expéditions d'exploration), l'horloge et la scène principale avec des entrées simulées (pause, vitesse, clic, ouverture et fermeture de la vue système, bascule vers la vue de gestion, construction et colonisation depuis la fiche de la planète, renommage, F5/F9, Échap, brouillard, sélection de flotte, clic droit pour l'envoyer, fiche de flotte, F, chantier spatial), les bilans d'empire, l'interface (thème, barre d'empire, écrans Économie, Colonies, Recherche et Diplomatie (filtres, colonie choisie, anneau), pause automatique, Tab, H, flèches, fiche de sélection, lentille économique, cadran du temps, menu pause, menu principal et nouvelle partie avec faction et graine choisies) ainsi que la géométrie de la vue système (planètes dans la scène et cliquables) :

```
godot --headless --path . -s res://tests/smoke_test.gd
```

Il affiche `OK : N vérifications passées.` et renvoie le code 0 si tout passe, 1 sinon.

## Limites connues

- Les trois autres empires ne prennent encore aucune décision (leurs flottes restent chez eux) : l'IA basique est la prochaine étape, avec le combat.
- Pas encore de combat ni de vaisseaux de guerre : les flottes se croisent sans se battre.
- Hors de vue, les systèmes explorés montrent leur propriétaire actuel, pas la dernière information connue.
- Pas encore de mécaniques signatures des factions : prochaine étape, les factions jouables.
- Les matériaux servent maintenant aux vaisseaux ; la recherche viendra aussi les consommer.
- Un seul emplacement de sauvegarde (rapide) pour l'instant ; l'écran de sauvegardes multiples viendra plus tard.
- Pas encore de sons d'interface ni de raccourcis personnalisables.
- Le multijoueur lui-même (réseau) n'est pas fait : le noyau est prêt pour un hôte qui fait autorité, mais rien n'est encore envoyé sur le réseau.
