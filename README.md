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
| Pause / reprise (tour par tour : fin de tour) | Espace, ou le centre du cadran du temps (en bas à droite) |
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
| Liste des flottes | Panneau à droite sous la chronique : clic = sélectionner et centrer, double-clic = ouvrir le système |
| Flotte inactive suivante | I / Maj+I, ou le bouton « N flottes inactives » au-dessus du cadran |
| Exploration automatique | E (flotte sélectionnée), ou le bouton de la fiche de flotte |
| Tactique de combat de la flotte | T (flotte sélectionnée), ou le bouton « Tactique » de la fiche de flotte |
| Envahir le système assiégé | Bouton « Envahir » de la fiche de flotte (quand les troupes dépassent la garnison) |
| Dernier rapport de bataille | B, ou le bouton « Rapport » de la fiche de flotte |
| Revoir la bataille (vue de replay) | R, ou « Revoir la bataille » dans le rapport ; Espace lecture/pause, Échap revient au rapport |
| Recherche : choisir, lancer, mettre en file, retirer | Écran Recherche (F3) : clic sur une technologie pour sa fiche, double-clic pour la lancer tout de suite ; boutons de la fiche ; croix de la file |
| Diplomatie : proposer un traité, répondre, rompre, déclarer la guerre | Écran Diplomatie (F4) : choisir l'empire sur la table, puis les boutons de la relation (la guerre en deux clics) |
| Construire un vaisseau | « Chantier spatial » dans les ordres d'une colonie, dans la vue système |
| Coloniser, poser un avant-poste, construire | Section « Ordres » de la fiche de la planète, dans la vue système |
| Renommer un système | Bouton « Renommer » à côté de son nom, dans la vue système, puis Entrée |
| Sauvegarde / chargement rapide | F5 / F9, ou le menu du jeu |
| Plein écran | F11, ou Options |
| Spectateur : suivre l'empire suivant / précédent | Tab / Maj+Tab, ou clic sur sa ligne du tableau des empires (double-clic : sa capitale) |
| Spectateur : vue d'ensemble ou yeux de l'empire suivi | V, ou les boutons du tableau des empires |

## Interface et menus

![Interface de la carte](docs/apercu-interface.png)

La disposition reprend celle d'Endless Space 2, sans rien lui emprunter (dessins, polices et pictogrammes sont les nôtres) : panneaux plats et translucides aux angles droits, filets fins, police libre Exo 2 en graisses fines, capitales espacées, un seul accent cyan pour la sélection et les actions.

- **Panneau d'empire** en haut à gauche : les pictogrammes des menus d'empire, le nom et l'emblème de votre peuple (son trait en infobulle), les cinq ressources avec leur stock et leur bilan mensuel (détail production, entretien, bonus de faction et délai avant épuisement en infobulle), et une ligne d'état (chantiers, fondations, population, alertes).
- **Onglets de vue** en haut au centre : Vue galaxie, Lentille économique (la carte s'assombrit et seuls vos systèmes restent, avec leur bilan par ressource), et Gestion du système (×) quand un système est ouvert.
- **Fiche de sélection** en bas à gauche : une vignette de l'étoile, le nom, le propriétaire, une pastille par planète (cerclée de la couleur du propriétaire), une ligne d'ambiance et le bouton pour entrer dans le système. Elle montre le système survolé, sinon le système choisi.
- **Cadran du temps** en bas à droite, à la place du bouton de fin de tour : le centre met en pause, la date est dessous, les cinq crans de l'arc règlent la vitesse.
- **Tour par tour au choix** (ligne « Temps » de la nouvelle partie : temps réel pausable, ou tours de 5, 10 ou 30 jours). Au tour par tour, le temps est arrêté pendant qu'on donne ses ordres ; le cadran devient un bouton « Fin de tour » (Espace) qui fait défiler les jours du tour en accéléré, avec la progression sur l'anneau, puis s'arrête au tour suivant. La simulation ne fait aucune différence entre les deux modes (un tour = N ticks ordinaires) : mêmes règles, même déterminisme, et le choix est rangé dans la sauvegarde. En multijoueur, le plan est celui des tours simultanés d'Endless Space 2 : l'hôte lance la fin de tour quand tous les joueurs ont terminé.
- **Étiquettes de systèmes** sur la carte : un cartouche sombre souligné de la couleur du propriétaire, et les pastilles des planètes pour vos systèmes et la sélection.
- **Écrans d'empire** en plein écran, comme dans Endless Space 2 : la carte s'efface derrière un voile, le panneau d'empire et le cadran restent, un onglet en haut au centre nomme l'écran et le ferme, une colonne à gauche résume, et le contenu se range en blocs titrés.
  - **Économie** : bilan des ressources (stock, production, entretien, bilan, tendance), anneau de répartition de la production, production par système (un clic ouvre le système), alertes. La colonne montre votre peuple et ses chiffres clés.
  - **Colonies** : liste filtrable (toutes, colonies, avant-postes, fondations), fiche de la colonie choisie avec son illustration et un bouton pour ouvrir sa vue système (ou double-clic sur la ligne). La colonne fait le compte dans un anneau.
  - **Recherche** : tout l'arbre du peuple (4 domaines × 5 ères), la recherche en cours, le Savoir, la file d'attente et la fiche de la technologie choisie (voir Recherche).
  - **Diplomatie** : la table des statuts, la relation avec l'empire choisi et les propositions reçues (voir Diplomatie).
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
- **Ergonomie des flottes** (d'après Endless Space 2) : liste permanente de toutes vos flottes à droite (état : en route, en exploration, attend des ordres, avec délais) ; bouton des flottes inactives au-dessus du cadran, comme celui au-dessus de la fin de tour d'ES2 ; avis à l'arrivée d'une flotte.
- **Exploration automatique** : ordre permanent d'une flotte (sauvegardé, rejouable). Elle vise le système inexploré le plus proche par les routes connues, change de cible dès que la sienne a été vue en chemin, évite celles déjà visées par un autre explorateur, et s'arrête (avec une ligne de chronique) quand il n'y a plus rien à atteindre. Un ordre manuel la coupe.

![Liste des flottes et exploration automatique](docs/apercu-flottes-liste.png)

- **Flottes** : « Rassembler » réunit les flottes à l'arrêt dans un même système, « Détacher » en sépare un vaisseau.
- **Brouillard de guerre** : on ne voit que ce qu'observent ses revendications (1 saut autour) et ses flottes (selon leur vision). Un système vu une fois reste exploré (comme la « terra incognita » d'Endless Space 2 que les vaisseaux dissipent pour de bon) ; hors de vue, il est assombri et les flottes étrangères y sont invisibles. Les systèmes reliés à un système exploré apparaissent comme de simples lueurs, sans nom ni planètes : on peut y envoyer une flotte, pas les ouvrir. Le reste de la galaxie et ses routes sont cachés.
- **Colonisation par vaisseau colon** : pour s'installer dans un nouveau système, il faut y amener un vaisseau colon, qui se démonte pour fonder l'avant-poste ou la colonie (il ne reste à payer que l'influence). Une fois une revendication établie dans un système, ses autres planètes se revendiquent sans vaisseau, comme avant. La règle provisoire « système voisin » disparaît.
- **Premier contact** : quand un empire aperçoit un système ou une flotte d'un autre, la chronique raconte la rencontre et les deux empires la retiennent (base de la future diplomatie).
- **Tout passe par des ordres** (`build_ship`, `move_fleet`, `stop_fleet`, `merge_fleets`, `split_fleet`), en nombres entiers et sans aléatoire. Sauvegarde en version 3 (flottes, systèmes explorés, contacts, chantiers spatiaux).

![Fiche de flotte et système inexploré](docs/apercu-flottes-fiche.png)
![Coloniser avec un vaisseau colon](docs/apercu-vaisseau-colon.png)

Références consultées pour ces mécaniques : Endless Space 2 reste le modèle principal ([déplacements et routes](https://gamepressure.com/endless-space-2/systems-and-ways-of-travelling/z29c4b), [colonisation par vaisseau colon et avant-poste](https://www.gamepressure.com/endless-space-2/colonization-migration-and-evacuation/z69c4f)), complété par d'autres 4X en temps réel : Stellaris pour les contre-ordres en plein trajet et l'exploration par vaisseaux scientifiques, Sins of a Solar Empire pour garder des trajets courts (ses joueurs se plaignent d'attendre plusieurs minutes une flotte, [discussion Steam](https://steamcommunity.com/app/1575940/discussions/1/651441204180820081)).

## Les 4 peuples et leurs traits

Chaque peuple de la première version a des traits qui changent vraiment la façon de jouer (économie, flottes, colonisation). Ils sont décrits en entier dans l'écran Nouvelle partie, rappelés en infobulle sur le nom du peuple, et chaque peuple a sa jauge dans le panneau d'empire. Tous les réglages sont dans `data/factions.json`.

| Peuple | Traits | Ce que ça change |
|---|---|---|
| **Lignées d'Ossarane** (médiéval spatial) | Navigateurs façonnés, Serment des fiefs, Fils de Saphène | Flottes 30 % plus rapides et monopole des cristaux. Chaque colonie hors du système capital est un fief qui verse +1 influence ; un fief à plus de 4 sauts coûte 1 cristal par mois, et sans cristaux les fiefs lointains entrent en dissidence (production divisée par deux). On s'étend vite, mais on doit tenir ses routes de cristaux. |
| **Hégémonie du Chœur Éternel** (grimdark) | Forges sacrées, Le dieu-machine a faim, Offrande, Pèlerins zélés | La ferveur (0 à 100) baisse de 5 par mois et monte de 1 par colonie. À 60 ou plus, Exaltation : +25 % de production ; à 0, le dieu se tait : -25 %. Ordre « Offrande » : -1 population, +20 ferveur. Les nouvelles colonies démarrent à 2 population. On s'étend pour nourrir le dieu, ou on sacrifie. |
| **Concorde de Vael** (space opera héroïque) | Assemblées ouvertes, Quarante peuples, Vote d'urgence, Ambassades | Toute planète habitable l'est au moins à 60 %. Ordre « Vote d'urgence » : achever tout de suite un bâtiment ou un vaisseau contre de l'influence (1 pour 2 jours restants). +2 influence par mois par empire rencontré. L'influence devient une monnaie. |
| **Essaim Kh'thari** (horreur biologique) | Croissance explosive, Essaimage, Biomasse | Pas de vaisseau colon : des vaisseaux-spores payés en population (2) et en nourriture. Coloniser ne coûte jamais d'influence. Une colonie pleine continue de grandir et digère chaque population en trop en 15 matériaux. On produit des colons, pas des diplomates. |

Nouveaux ordres : `sacrifice` (Chœur) et `rush` (Vael). Sauvegarde en version 4 (ferveur, dissidence, biomasse), puis 5 avec le niveau des IA, puis 6 avec le combat.

![Choix du peuple et ses traits](docs/apercu-factions.png)
![Offrande et jauge de ferveur](docs/apercu-offrande.png)

Références consultées pour ces mécaniques (les traits restent originaux) : les guides Gamepressure d'Endless Space 2 sur [le choix de la race](https://www.gamepressure.com/endless-space-2/what-race-should-i-choose/z09d03) (les Unfallen sacrifient leur population contre de l'approbation, les Cravers doublent leur croissance, les Lumeris n'ont pas de vaisseau colon) et sur [l'Empire Uni](https://www.gamepressure.com/endless-space-2/united-empire/za9ce9) (l'influence sert à accélérer les constructions), et les discussions des développeurs de Stellaris sur [l'essaim dévoreur](https://admin-forum.paradoxplaza.com/forum/developer-diary/stellaris-dev-diary-76-hive-mind-improvements-tradition-swapping.1034124) (une ruche privée de diplomatie).

## Empires IA et mode spectateur

Les trois autres peuples sont menés par l'ordinateur : ils explorent, colonisent, construisent et se servent des talents de leur peuple. Le niveau et le tempérament se choisissent dans la ligne « Rivaux » de la nouvelle partie (réglages dans `data/ai.json`).

| Niveau | Comment il joue | Bonus |
|---|---|---|
| **Recrue** | Réfléchit tous les 20 jours, oublie une décision sur trois, se sert très mal des talents de son peuple, une seule colonisation à la fois | aucun |
| **Normal** (par défaut) | Tous les 10 jours, quelques oublis, connaît les bases de son peuple | aucun |
| **Vétéran** | Tous les 5 jours, aucun oubli, exploite tout le registre de son peuple et lit son goulot (quand les matériaux s'entassent, il construit des forums pour l'influence) | aucun |
| **Expert** | Le jeu du Vétéran | +15 % de production, petite avance au départ |
| **Légende** | Le jeu du Vétéran, plus réactif encore | +30 % de production, vraie avance au départ |

Ce que chaque peuple fait de ses talents selon le niveau (bloc `"ai"` de `data/factions.json`) :

- **À la Recrue**, chaque peuple connaît ses talents mais les gâche : le Chœur attend que son dieu se taise et sacrifie dans sa plus petite colonie ; Vael vote l'urgence sur des chantiers presque finis, au prix plancher, sans garder d'influence pour coloniser ; Ossarane court après les cristaux sans compter ce que coûtent ses fiefs lointains ; l'Essaim lance ses spores depuis ses colonies les plus fragiles.

- **Ossarane** : garde ses premiers fiefs à portée de la capitale et ne pose de fief lointain que s'il produit les cristaux pour le payer (au Vétéran, le compte est exact) ; raffinerie sur chaque gisement de cristaux.
- **Chœur Éternel** : offrande quand le dieu va se taire (Normal) ; au Vétéran, entretient l'Exaltation (+25 %) en prenant le fidèle dans une colonie pleine, qui regrandit sans rien perdre.
- **Vael** : vote d'urgence sur les vaisseaux colons et les longs chantiers dès que l'influence déborde (au Vétéran, dès qu'il reste de quoi payer la prochaine revendication) ; un éclaireur de plus pour rencontrer les autres empires (ambassades).
- **Kh'thari** : vaisseaux-spores lancés depuis ses colonies les plus peuplées (pleines d'abord au Vétéran, la biomasse fait le reste), colonisation sans compter l'influence, fermes en priorité.

**Tempérament.** À côté du niveau, un second réglage règle l'attitude des IA envers les autres empires, sans jamais changer leurs ressources : Pacifique, Prudent, Normal, Agressif, Belliqueux (`data/ai.json`). Chaque peuple le décale d'un cran (bloc `"ai"."temperament"`) : Ossarane est fière (sans décalage), le Chœur zélé et l'Essaim vorace (un cran plus agressifs ; l'Essaim ne fera jamais la paix), Vael conciliante (un cran plus pacifique). Il oriente l'expansion : un empire agressif colonise au contact de ses rivaux et se jette sur les systèmes disputés, un empire pacifique garde ses distances (seules comptent les frontières qu'il a explorées). La même valeur (`AiLevels.aggression`) décide des guerres (voir Combat spatial) et décidera des traités. Inspiré de l'agressivité des IA de Stellaris ([Gameranx](https://gameranx.com/updates/id/55918/article/stellaris-beta-patch-1-10-adds-ai-aggressiveness-customized-titles-and-more/)), des traits de personnalité des IA d'Endless Space 2 et de la guerre éternelle des Cravers ([forum Amplitude](https://community.amplitude-studios.com/amplitude-studios/endless-space-2/ideas/227-faction-goals)), et des programmes des dirigeants de Civilization VI ([PCGamesN](https://www.pcgamesn.com/civilization-vi/leaders-agendas)).

Sur 3 galaxies et 5 ans entre IA (`tools/ai_bench.gd`), le score moyen monte bien avec le niveau pour chaque peuple, et une IA Légende finit devant les autres dans les parties mixtes.

**Comment c'est fait.** L'IA fait partie de la simulation (`AiSystem`, appelé à la fin de chaque tick, et le cerveau `AiPlayer`) : elle ne voit que ce que son empire a exploré et n'agit que par les ordres ordinaires (`SimCommands`), validés comme ceux d'un joueur. Ses « oublis » viennent d'un hachage de la graine et du jour, jamais de l'aléatoire global : elle joue exactement pareil en temps réel et au tour par tour, dans une rediffusion (le journal ne garde que les ordres des joueurs, les IA se rejouent seules) et sur toutes les machines d'une partie en réseau. Le module `_military` mène la guerre (voir Combat spatial) ; `_diplomacy` négocie (voir Diplomatie).

**Mode spectateur.** Ligne « Partie » de la nouvelle partie : « Spectateur ». Les 4 peuples sont des IA et personne ne donne d'ordre. La carte est entièrement visible, et le **tableau des empires** remplace la liste des flottes : classement au score, niveau, systèmes, colonies, population, flottes, jauge du peuple, ce que fait chaque IA en ce moment, et la courbe du score de chacun mois après mois. Clic sur une ligne (ou Tab) : suivre l'empire (panneau d'empire, H pour sa capitale) ; double-clic : sa capitale. V ou les deux boutons : vue d'ensemble, ou les **yeux de l'empire** suivi (son brouillard de guerre). La vue système reste consultable, en lecture seule. Une sauvegarde d'une partie sans joueur se recharge en spectateur. Ce même mode servira aux spectateurs d'une partie en réseau (un client sans empire).

![Mode spectateur : vue d'ensemble](docs/apercu-spectateur.png)
![Mode spectateur : les yeux du Chœur Éternel](docs/apercu-spectateur-yeux.png)

Recherche consultée (le reste vient de mémoire et est signalé comme tel dans la PR) :
- Endless Space 2 : [discussion Steam « What does upping the difficulty do to the AI? »](https://steamcommunity.com/app/392110/discussions/0/1291817837615803045/) (propos rapportés de l'équipe : l'IA reçoit des bonus à partir de Difficile ; en dessous, elle réagit moins aux menaces, poursuit ses objectifs plus lentement et négocie moins bien ; son seul avantage est un bonus de production) ; [fil sur les outils de débogage E.N.F.E.R.](https://community.amplitude-studios.com/amplitude-studios/endless-space-2/forums/65-general/threads/24821-enfer-ai-debug-tools?page=-7) (IA à base d'objectifs et de tâches dotés d'une « motivation » qui plafonne les ressources engagées ; outil désactivé en multijoueur parce qu'il montre les informations des adversaires) ; [fil Steam sur l'IA](https://steamcommunity.com/app/392110/discussions/0/3111396383970684094) (l'IA utilise les mêmes mécaniques que le joueur). Aucune trace d'un mode spectateur dans Endless Space 2 ; une [suggestion de joueurs pour le premier Endless Space](https://community.amplitude-studios.com/amplitude-studios/endless-space/forums/29-archives/threads/13521-composite-suggestion-timed-peace-and-replays-spectating?page=1) le réclamait déjà.
- Galactic Civilizations : [journal de développement « Organic Difficulty »](https://forums.sorcererking.com/537257/galciv-iv-dev-journal-106-organic-difficulty-in-galciv-iv) et [notes de la v3.3](https://forums.sinsofasolarempire2.com/541281/galactic-civilizations-iv-v3-3-now-available) (IA adaptative), [wiki](https://galciv.fandom.com/wiki/Difficulty_level) (difficulté réglable empire par empire).
- Stellaris : commande `observe` pour regarder la partie ([PCGamesN](https://www.pcgamesn.com/stellaris/cheats-console-commands)).
- Age of Empires II DE : spectateurs qui passent d'un joueur à l'autre avec un bandeau d'informations ([Wikipédia](https://en.wikipedia.org/wiki/Age_of_Empires_II:_Definitive_Edition)), et l'outil [CaptureAge](https://captureage.com/docs) (statistiques et événements pour les spectateurs).

## Combat spatial

Les flottes d'empires en guerre se battent quand elles se retrouvent dans le même système, les systèmes ennemis se prennent par le siège puis l'invasion, et l'IA s'en sert selon son niveau et son tempérament. Tout est réglé dans `data/combat.json`, `data/ships.json` (vaisseaux) et les blocs `"combat"` de `data/factions.json`.

![Une bataille en cours](docs/apercu-bataille.png)
![Rapport de bataille](docs/apercu-rapport-bataille.png)
![Siège et invasion](docs/apercu-siege.png)
![Vue de replay d'une bataille](docs/apercu-replay.png)

- **La guerre.** Les empires se déclarent la guerre depuis l'écran Diplomatie (F4), une fois rencontrés ; elle vaut dans les deux sens. L'Essaim Kh'thari est en guerre avec tout empire qu'il rencontre. La paix se négocie (voir Diplomatie).
- **Un catalogue de vaisseaux de guerre** (voir « Catalogue de vaisseaux » plus bas) : la **corvette** (rapide, canons cinétiques, mortelle au contact), la **frégate** (rayons à moyenne portée, boucliers), le **croiseur** (missiles à longue portée, blindage, 12 troupes pour les invasions), et neuf autres classes. Éclaireurs et vaisseaux colons ne sont pas armés : ils subissent.
- **La bataille** est automatique et dure six jours : deux à longue portée, deux à moyenne, deux à courte. Chaque famille d'armes a sa portée (missiles 90/70/40 %, rayons 50/90/70 %, canons 20/40/90 %), les boucliers réduisent les rayons, le blindage les canons et les missiles. Tous les vaisseaux tirent chaque jour sur une cible au hasard (tirée par la simulation, donc identique sur toutes les machines), les dégâts s'appliquent ensemble. Au bout des six jours, un rapport est rédigé (B) ; si les deux camps sont encore là, une nouvelle bataille commence. Les flottes qui arrivent en cours de route rejoignent la bataille.
- **La vue de replay** (facultative) : la simulation garde le journal de chaque bataille (qui tire sur qui, avec quelle arme, pour combien, et qui est détruit, jour par jour), et « Revoir la bataille » dans le rapport le rejoue en 2D stylisée : chaque camp rangé en écran, ligne et arrière, les tirs dessinés par famille d'armes (missiles en courbe, rayons, traçantes, torpilles, obus, essaims de chasseurs), les coques qui baissent, les vaisseaux qui sautent. Lecture, pause, vitesse ×1/×2/×4, jour par jour. Elle ne fait que relire ce qui s'est passé : la partie continue pendant ce temps (en multijoueur, chacun regarde quand il veut), comme les batailles qu'on peut regarder ou passer dans Endless Space 2. Une version plus cinématique viendra avec le passage en 2,5D.
- **La tactique** se choisit avant (T), comme les plans de bataille d'Endless Space 2 : Équilibre, Assaut (charge, pour les corvettes), Tir à distance (pour les missiles), Rempart (-20 % de dégâts reçus). On ne contrôle rien pendant la bataille, mais on peut **sonner la retraite** : l'ordre de déplacement s'applique avant la reprise du lendemain.
- **Le blocus.** Une flotte armée ennemie arrête toute flotte qui traverse son système.
- **Le siège.** Une flotte armée dans un système ennemi sans défenseur le met en siège : sa garnison fond chaque jour (corvette et frégate 1, croiseur 3), sa production tombe de moitié, ses chantiers spatiaux s'arrêtent. Le **bastion orbital** (nouveau bâtiment) ajoute 20 de garnison et tire chaque jour sur les assiégeants tant que la garnison tient. La garnison dépend de la population (5 par population, 6 par avant-poste, 30 pour la capitale) et remonte de 2 par jour une fois le siège levé.
- **L'invasion.** Quand les troupes embarquées dépassent la garnison, « Envahir » : toutes les revendications de l'empire dans le système changent de mains. Une capitale perdue est remplacée par la colonie la plus peuplée ; un empire sans revendication disparaît, avec ses flottes.
- **Réparations et troupes** : vite dans ses propres systèmes (5 % de la coque par jour), lentement ailleurs (1 %) ; les troupes se refont chez soi.
- **Temps réel et tour par tour** : la simulation ne fait aucune différence. Au tour par tour, le tour s'interrompt quand une bataille s'engage avec vos flottes, pour choisir la tactique ou se retirer ; « Fin de tour » joue le reste du tour.

**Les traits de peuple au combat** (en attente depuis les factions) :

| Peuple | Trait | Effet |
|---|---|---|
| Ossarane | Ban des vassaux | +15 % de dégâts dans ses propres systèmes, garnisons des fiefs +50 % |
| Chœur Éternel | Croisade | +2 ferveur par vaisseau ennemi détruit, +10 par système conquis |
| Vael | Au dernier moment | Une flotte qui rejoint une bataille déjà engagée inflige +30 % de dégâts |
| Kh'thari | Faim sans traité | En guerre avec tout empire rencontré ; colonies conquises digérées (il reste 1 population, le reste devient 15 matériaux par population) ; coques vivantes qui se réparent partout ; garnisons +50 % |

Les héros de Vael et la trahison d'héritier d'Ossarane attendront les personnages.

**L'IA au combat** (bloc `"military"` de chaque niveau et `"war"` de `data/ai.json`) :

- **Le tempérament décide de la guerre.** Passé un délai de grâce d'un an, une IA déclare la guerre à un voisin si elle se juge assez forte : il lui faut 3 fois la force estimée de l'autre au tempérament Normal, 1,5 fois en Agressif, autant que lui en Belliqueux, 0,8 fois au plus agressif ; un Pacifique ou un Prudent ne déclare jamais (il se défend et contre-attaque). Plus il est agressif, plus il va chercher loin, et seuls les plus belliqueux ouvrent un second front. Il arme aussi plus ou moins.
- **Le niveau décide du savoir-faire.** La Recrue arme, attaque et choisit sa tactique, mais mal : toujours à l'assaut (même avec des missiles), des vaisseaux au hasard, ses flottes envoyées une par une, jamais de retraite, et elle ne compte que les flottes qu'elle voit. Le Normal rassemble ses flottes, attend d'être plus fort que la cible, se retire quand il est dominé et fortifie le front (bastions). Le Vétéran et au-dessus adaptent la tactique aux armes de chaque flotte, construisent ce qui contre la flotte ennemie qu'ils voient et des croiseurs quand les troupes manquent.
- Toutes les IA défendent leurs systèmes assiégés, assiègent la cible la plus faible, envahissent dès que leurs troupes suffisent, et ne voient que ce que leur empire voit. Elles agissent toujours par les ordres ordinaires.

Sur 3 galaxies et 8 ans entre IA Normales (`tools/war_bench.gd`), il y a une centaine de batailles et de sièges par partie, et un empire disparaît souvent vers la troisième année ; au tempérament Pacifique, seul l'Essaim est en guerre.

**Recherche consultée** (la règle du projet : ce qui vient de sources est cité, le reste est signalé comme venant de mémoire) :
- Endless Space 2 : [guide Gamepressure des batailles spatiales](https://www.gamepressure.com/endless-space-2/space-battles/z39cd3) (blocus puis attaque, tactique choisie avant la bataille, aucun contrôle pendant), [GDD 4 « Battle overview » d'Amplitude](https://community.amplitude-studios.com/amplitude-studios/endless-space-2/forums/65-general/threads/18857-es2-gdd-4-battle-overview?page=1) (arrivée, trois phases, résolution ; plan de bataille choisi au début ; renforts ; même résultat en bataille automatique), [guide des armées et batailles au sol](https://www.gamepressure.com/endless-space-2/armies-and-ground-battles/z49cd4) (le siège réduit la garnison chaque tour, puis invasion), [GDD 14 « Ground battle »](https://community.amplitude-studios.com/amplitude-studios/endless-space-2/forums/65-general/threads/19715-es2-gdd-14-ground-battle?page=1) (blocus pour affaiblir le système avant l'invasion, conséquences économiques des guerres), [guide de la main-d'œuvre](https://www.gamepressure.com/endless-space-2/manpower/z99c49) (les équipages servent de troupes, réapprovisionnement coupé par le blocus) et [des discussions de joueurs sur le forum d'Endless Space 2](https://community.amplitude-studios.com/amplitude-studios/endless-space-2/forums/66-game-design/threads/28821-defence-mechanics-explanations-issues?page=2) (les boucliers absorbent surtout les armes à énergie, le blindage surtout les cinétiques et les missiles ; les chiffres varient selon les versions, je n'ai pas trouvé de source officielle).
- Endless Space (le premier) : [guide Gamepressure du combat](https://www.gamepressure.com/endless-space/battle/z33e65) (efficacité des armes par phase : missiles 90/70/40 %, rayons 50/90/70 %, cinétiques 20/40/90 %, reprise telle quelle).
- Stellaris : [journal de développement 99 sur les armées](https://admin-forum.paradoxplaza.com/forum/developer-diary/dev-diary-99-ground-combat-army-rework.1061707/page-17) et [guide de la conquête](https://gamerempire.net/stellaris-how-to-conquer-a-planet/) (bombardement qui use les défenses, forteresses) : pour le bastion qui tient tant que la garnison tient.
- De mémoire (non vérifié) : la durée de six jours, les chiffres des vaisseaux et des garnisons, les traits de combat des peuples et le comportement de l'IA sont des choix maison.

## Diplomatie

Les empires qui se rencontrent entrent en **guerre froide**, puis peuvent signer la paix, s'allier, commercer, échanger leurs cartes, se trahir ou se faire la guerre. Tout est réglé dans `data/diplomacy.json` ; les règles vivent dans `scripts/sim/diplomacy.gd`, le jugement et les initiatives de l'IA dans `scripts/sim/ai/ai_diplomacy.gd`.

![Diplomatie de Vael](docs/apercu-diplomatie.png)

**Statuts et traités** (repris d'Endless Space 2) :

| Statut ou traité | Effet |
|---|---|
| Guerre froide | Statut de départ après la rencontre : pas de combat, chacun peut déclarer la guerre |
| Guerre | Combats, sièges, invasions ; un score de guerre compte les vaisseaux détruits et les systèmes pris |
| Paix | Aucune attaque ; une **trêve d'un an** suit la signature (pas de guerre possible) ; ensuite on peut dénoncer la paix (retour à la guerre froide) ou attaquer quand même et passer pour **parjure** aux yeux de toute la galaxie. +1 influence par mois |
| Alliance | Après six mois de paix. Les alliés **partagent leurs guerres** (qui attaque l'un a l'autre sur le dos, et l'allié d'un agresseur le suit), sauf s'ils sont liés par la paix à l'autre camp, et leurs cartes chaque mois. La quitter ramène à la guerre froide. +2 influence par mois |
| Accord commercial | Avec la paix : +4 énergie et +1 influence par mois chacun |
| Échange de cartes | Chacun reçoit les systèmes explorés par l'autre ; pas en guerre, pas plus d'une fois tous les deux ans |

Une proposition faite à une IA reçoit sa réponse tout de suite ; une proposition faite à un joueur humain l'attend 30 jours dans son écran Diplomatie (et un avis s'affiche). Un refus impose un délai avant de reproposer.

**Opinion** (de -100 à 100, ce qu'un empire pense d'un autre ; l'infobulle donne chaque raison) :

- le **choc des tons** du document de game design : une dissonance entre registres de -3 à +3 (×5), par exemple grimdark face au space opera héroïque -15 ;
- les **credos** (même credo +10, foi contre raison -10…), les **gouvernements** (féodalité contre république -5…), l'archétype (une ruche inspire l'horreur, -10) et certains traits (les Quarante peuples de Vael aiment tout le monde, le fanatisme du Chœur déteste les autres credos) ;
- les **frontières communes** (-3 par système voisin, jusqu'à -15) ;
- le statut (guerre -40, paix +10, alliance +20, commerce +5), la **confiance** qui monte de 2 par mois sous traité jusqu'à +30 (Stellaris), l'**ennemi commun** (+15) ;
- l'**histoire commune** : des souvenirs qui s'effacent avec le temps (déclaration de guerre, traité rompu, parjure, conquêtes, paix signée, allié venu à l'aide, héritier soudoyé, arbitrage…), comme les griefs de Civilization VI.

Tout cela porte sur les couches d'espèce (registre, credo, gouvernement, archétype, traits), pas sur l'identifiant d'une faction : une espèce créée dans l'éditeur obtiendra les mêmes réactions.

**Les talents diplomatiques des peuples** (eux aussi liés aux couches d'espèce, bloc `"abilities"`) :

| Talent | Qui | Effet |
|---|---|---|
| Faim sans traité | ruche + credo survie (l'Essaim Kh'thari) | Ne signe rien, ne reçoit rien, n'achète personne ; reste en guerre avec tous ceux qu'il rencontre |
| L'héritier | toute féodalité (les Lignées d'Ossarane) | Loyauté de 0 à 100 : -6 par mois en dissidence des fiefs, -2 par guerre, + avec le temps et les traités. Les rivaux peuvent la **soudoyer** (30 influence, -15, et l'on s'en souvient) ; la dynastie offre un **banquet des lignées** (20 influence et 3 cristaux, +20). À 0, l'héritier **trahit** : il livre le fief le plus lointain à celui qui l'a acheté (ou à un ennemi), puis un nouvel héritier prend sa place |
| Les Veilleurs du Seuil | toute république (la Concorde de Vael) | **Arbitrer** la guerre entre deux empires connus : si elle dure depuis deux mois et que les deux camps respectent l'arbitre (opinion positive), la paix est imposée avec sa trêve (40 influence, une fois par an). Inspiré des trêves forcées des factions pacifistes d'Endless Space 2 |
| Pas de paix avec les hérétiques | théocratie + credo foi (le Chœur Éternel) | Déclarer la guerre à un autre credo : +10 ferveur ; chaque traité de paix avec un autre credo : -1 ferveur par mois |

**L'IA.** Elle juge chaque offre en additionnant des raisons lisibles, que le joueur voit avant de proposer (« Accepterait (+13) » et le détail en infobulle, comme la barre d'Endless Space 2 qui montre ce que l'autre pense de l'offre) : l'opinion, la lassitude et le cours de la guerre, le rapport de forces (la « pression » d'ES2), l'ennemi commun, les guerres d'un futur allié qui ne sont pas les siennes, et le **tempérament** (un belliqueux signe moins volontiers qu'un pacifique). Elle propose d'elle-même ce qu'elle accepterait avec une marge, au plus une proposition par réflexion, quitte une alliance qui ne lui plaît plus, et ne rompt un traité pour attaquer que si elle est belliqueuse et déteste sa cible. Par niveau : la Recrue juge à l'humeur du jour (un écart fixe pour le mois, déterministe), ignore le rapport de forces, offre son banquet trop tard, achète n'importe quel héritier et arbitre la première guerre venue ; le Normal compte les bases ; le Vétéran et au-dessus pèsent tout, soudoient les héritiers de leurs ennemis et arbitrent quand un ami perd. Sur des parties de 2000 jours entre IA, Vael et Ossarane finissent alliés, l'alliance entraîne Ossarane contre le Chœur, et au niveau Vétéran Vael finit par signer la paix avec le Chœur ; l'Essaim, lui, ne signe jamais.

**Interface.** L'écran Diplomatie (F4) reprend l'écran des statuts d'Endless Space 2 : votre empire au centre d'un anneau, les autres tout autour, un secteur coloré par statut (rouge la guerre, ambre la guerre froide, bleu la paix, cyan l'alliance) et des cordes pour les guerres et alliances entre les autres. À droite : les propositions reçues (accepter, refuser), puis la relation avec l'empire choisi (statut, trêve, score de guerre, opinions dans les deux sens, talents de son peuple, un bouton par traité avec le verdict de l'IA, rompre, déclarer la guerre, soudoyer l'héritier, arbitrer). À gauche : le bilan, les talents de votre peuple et, pour une dynastie, la loyauté de l'héritier et le banquet.

Nouveaux ordres : `propose_treaty`, `answer_proposal`, `cancel_treaty`, `bribe_heir`, `banquet`, `mediate`. Sauvegarde en version 7 (relations, souvenirs, propositions, héritier). Captures : `tools/capture_diplomacy.gd`.

Sources consultées :

- Endless Space 2 : [guide Gamepressure de la diplomatie](https://www.gamepressure.com/endless-space-2/diplomacy/z49cce) (guerre froide par défaut, paix sans aucune attaque, alliance, frontières, accord commercial, échange de cartes, écran de négociation qui montre ce que l'autre pense de l'offre), [mise à jour 1.1.0 « Galactic Statecraft »](https://community.amplitude-studios.com/amplitude-studios/endless-space-2/blogs/586-update-1-1-0-galactic-statecraft) (quitter une alliance ramène à la guerre froide), [billet sur la pression diplomatique](https://community.amplitude-studios.com/amplitude-studios/endless-space-2/blogs/584-galactic-statecraft-pressure-retake-constellation-control) (rapport de forces, friction de frontière), [wiki des statuts](https://endlessspace.fandom.com/wiki/Diplomatic_Status) et discussions de joueurs sur les trêves forcées des pacifistes et leurs délais ; la capture « Endless Space 2 - Diplomacy » de la [galerie hudsandguis](https://www.hudsandguis.com/home/2017/7/6/endless-space-2) pour la table des statuts.
- Stellaris : [notes de la mise à jour Asimov](https://forum.paradoxplaza.com/forum/threads/asimov-update-1-2-released-checksum-2352-not-for-problem-reports.953141/) et [journal 315](https://admin-forum.paradoxplaza.com/forum/developer-diary/stellaris-dev-diary-315-the-velvet-glove.1600119/) (la confiance qui monte avec les traités), discussions de moddeurs sur la friction de frontière et la menace commune.
- Civilization VI : [casus belli](https://civilization.fandom.com/wiki/Casus_Belli_(Civ6)) et discussions sur les griefs (les offenses qui pèsent puis s'effacent).
- Document de game design : opinion selon la dissonance des registres, les credos et l'histoire commune ; V1 = guerre, paix, alliance ; l'héritier qui trahit ; les Veilleurs du Seuil qui arbitrent ; l'Essaim sans diplomatie.
- De mémoire ou choix maison (non vérifié) : tous les chiffres (durées, valeurs d'opinion, revenus, coûts), la table de dissonance entre registres, le banquet et la bourse de l'héritier.

Pas encore fait : vassalisation, conseil galactique, contrats de mercenaires, exigences et menaces (la pression d'ES2 sert pour l'instant au jugement de l'IA), héros (ils viendront avec le système de personnages du GDD), vision partagée en temps réel entre alliés (les cartes s'échangent une fois par mois).

## Recherche

Une seule ressource de recherche, le **Savoir**, et un arbre entièrement visible de quatre domaines (Armement, Génie spatial, Économie, Société) sur cinq ères, comme dans Endless Space 2. Le premier lot a posé environ 65 technologies par peuple, surtout dans les ères 1 à 3 ; le deuxième (plus bas) ajoute les marques IV-V et les doctrines.

- **Savoir.** Chaque colonie en produit 1 pour 5 habitants, la capitale 8 de plus, et le bâtiment de recherche du peuple apporte le reste : Académie (et +10 % dans sa colonie), Scriptorium du Chœur (qui chante aussi : +1 ferveur par mois), Université des Quarante de Vael, Ganglion de mémoire de l'Essaim (nourri de nourriture). Il s'accumule ; chaque mois la technologie en tête de file en consomme jusqu'à deux fois le revenu (ou un douzième de la réserve si elle est grosse).
- **Coût.** Base de l'ère (30, 120, 320, 800, 1 900, ×3), +2,5 % par technologie déjà connue, +5 % par colonie au-delà de 5 : un grand empire paie sa recherche plus cher.
- **Ères.** Une ère s'ouvre dans un domaine quand on y connaît assez de technologies de l'ère précédente (2, 3, 3, 4). La file compte comme acquis ce qu'elle contient : on peut planifier une chaîne. Changer de recherche en cours met le travail entamé de côté, il est retrouvé quand on y revient.
- **Contenu derrière des technologies.** Transport, Croiseur, Torpilleur, Bombarde, Cuirassé, Porte-vaisseaux, Titan et Martyr, ainsi que la Raffinerie, les Habitats, le Bastion, l'Arsenal et le Chantier titanesque, demandent maintenant leurs technologies. Les alliances demandent les Chancelleries des deux côtés. Corvette, Frégate et Escorteur restent libres.
- **Effets.** Marques d'armes et de défenses (voir Arsenal), vitesse, coût et durée des vaisseaux, entretien, vision des colonies, production, croissance, fondations simultanées, emplacements, habitabilité (mondes toxiques, géantes gazeuses avec les cités flottantes), troupes et garnisons.
- **Technologies de peuple** (par couches d'espèce, comme les classes de vaisseaux : un peuple de l'éditeur qui partage la combinaison y a droit). Variantes qui remplacent une technologie commune (Scriptorium, Griffes, Routes des lignées, Serviteurs…), exclusives (Litanies, Charge sacrée, Duellistes, Ban des vassaux, Au dernier moment, Couvées…), hérétiques (Intelligences de bord et Génétique : 50 % plus chères et coûteuses en ferveur pour le registre Grimdark) et interdites (Automatisation pour le Chœur). Certaines ne valent que pendant l'Exaltation.
- **Talents de recherche des peuples.** Ossarane : technologies de saut 25 % moins chères. Chœur : Savoir -20 %, société +25 %, +5 ferveur par technologie d'armement, +4 Savoir par vaisseau ennemi détruit. Vael : +5 % de Savoir par empire en paix ou allié (20 % au plus). Kh'thari : Savoir divisé par deux, mais +2 Savoir par population digérée et +8 par vaisseau détruit.
- **IA.** Elle garde deux technologies en file, pèse l'intérêt de chaque domaine (tempérament, guerre en cours, penchant du peuple) contre le coût, construit un bâtiment de recherche pour cinq colonies, et évite les hérésies ; la Recrue choisit avec du bruit et ne voit pas l'hérésie.

### Arsenal : marques, doctrines, épaves, eurêkas

Le deuxième lot relie la recherche au combat et à ce qui se passe dans la partie. L'arbre compte 107 technologies.

- **Marques I à V.** Les 6 familles d'armes (cinétique, rayons, missiles, torpilles, artillerie, chasseurs) et les 3 défenses (blindage, boucliers, défense ponctuelle) montent chacune de la marque I à la marque V, +20 % par marque, comme les lignes d'armes de Galactic Civilizations. Dix technologies d'ères 4 et 5 complètent les marques IV et V.
- **Chaque vaisseau garde ses marques.** Un vaisseau sort du chantier avec les marques du moment et les garde. Une flotte à quai dans un système où l'empire a une colonie peut passer **au chantier** (bouton REMISE À NIVEAU) : 10 % du prix des vaisseaux en retard, 5 jours ; partir ou se battre interrompt les travaux. L'IA remet ses flottes à niveau quand elle est en paix.
- **Doctrines.** Trois paires exclusives en Armement (ères 2, 3, 4), comme les choix exclusifs d'Endless Space 2 : Rideau d'acier (l'écran encaisse 20 % de moins) ou Frappe en profondeur (25 % des tirs ignorent les rangs) ; Feu lointain (+15 % à longue portée, -10 % à courte) ou Abordage (+15 % à courte portée, +25 % de troupes) ; Guerre d'usure (réparations doublées, sièges +25 %) ou Guerre éclair (+20 % de vitesse, +10 % de dégâts le premier jour). Le choix est définitif : l'autre branche ne s'obtient plus que par les épaves.
- **Épaves** (Stellaris). Le vainqueur d'une bataille étudie les vaincus : 10 % de la marque suivante dans chaque famille où ils le dépassent, et 10 % de chacune de leurs doctrines. Reliques saintes du Chœur : deux fois plus ; Mémoire génétique de l'Essaim : trois fois plus. Une technologie entièrement payée ainsi est découverte aussitôt. Le rapport de bataille liste les épaves étudiées.
- **Eurêkas** (Civilization VI). 42 technologies ont un objectif en jeu qui paie 40 % de leur coût, une fois : rencontrer des empires, fonder des colonies, tenir des gisements, coloniser un type de monde, détruire ou perdre des vaisseaux, gagner des batailles, subir un siège, signer une paix ou un accord commercial, atteindre l'Exaltation... Vérifiés chaque trimestre. La fiche montre l'objectif et son avancement ; dans l'arbre, un point doré marque l'eurêka (plein une fois obtenu) et un trait doré le Savoir déjà acquis.
- **Pas encore là** : les technologies ultimes de l'ère 5 (Économie et Société n'ont pas encore d'ère 4), les modules et l'éditeur de vaisseaux, le commerce de technologies.

Sources (étude citée plus haut) : familles d'armes en marques de [Galactic Civilizations II](https://galciv.fandom.com/wiki/Technology), choix exclusifs d'[Endless Space 2](https://endless-space-2.fandom.com/wiki/Technology), analyse des épaves de [Stellaris](https://stellaris.paradoxwikis.com/Technology), eurêkas de [Civilization VI](https://civilization.fandom.com/wiki/Boost_(Civ6)) (40 % depuis Rise and Fall). Choix maison : les chiffres des doctrines, le prix et la durée de la remise à niveau, la liste des objectifs.

![Arbre du Chœur Éternel](docs/apercu-recherche.png)

**Rythme.** Calibré pour une partie d'environ 3 heures à la vitesse normale (0,5 seconde par jour) sur une vraie partie entre IA de niveau Normal : une dizaine de technologies au premier quart d'heure, l'ère 3 vers la demi-heure, une soixantaine de technologies à 3 heures pour un grand empire. À rejouer à la main.

Sources (consultées pour l'étude, voir le [document d'étude](https://claude.ai/artifact/VZPzNQD33eoKTu8FgYQAC1) et la [maquette de l'arbre du Chœur](https://claude.ai/artifact/4UzS2fXPdfBGcRaDS6w2Vt)) : le [wiki d'Endless Space 2 sur les technologies](https://endless-space-2.fandom.com/wiki/Technology) (arbre visible en domaines et ères à seuils, coût qui monte avec chaque technologie connue, technologies de peuple), le [wiki de Stellaris](https://stellaris.paradoxwikis.com/Technology) (coût qui grandit avec l'empire, choix pondérés de l'IA), le [wiki de Galactic Civilizations II](https://galciv.fandom.com/wiki/Technology) (familles d'armes en marques). De mémoire ou choix maison : tous les chiffres, les seuils et la dépense du Savoir stocké.

## Catalogue de vaisseaux

Le combat garde sa bataille automatique en trois phases ; le catalogue l'enrichit pour que chaque classe ait un usage et un contre. Tout est dans `data/ships.json` et `data/combat.json`. L'étude qui a mené à ces choix (dix jeux comparés, sources, décisions) : [Étude : systèmes de combat et types de vaisseaux](https://claude.ai/artifact/497ptZZyfqQfhcSajXLkTh).

![Bataille entre flottes mixtes et son rapport](docs/apercu-catalogue.png)

**Nouvelles règles de bataille**

- **Écran, ligne, arrière.** Chaque classe a un rang. Les tirs visent surtout l'écran (poids 3), puis la ligne (poids 2) ; l'arrière n'est visé que quand il ne reste plus ni écran ni ligne. Les chasseurs, eux, frappent partout. Inspiré des rôles et positions de départ de [Galactic Civilizations IV](https://wiki.galciv.com/index.php/GalCiv4:Spaceship_Battles) et des rôles d'[Endless Space 2](https://www.gamepressure.com/endless-space-2/roles-and-types-of-ships/z29cd2).
- **Défense ponctuelle.** Missiles, torpilles et chasseurs sont en partie abattus par la défense ponctuelle de la cible et par celle que les escorteurs prêtent à toute leur flotte (plafond 60 %). Inspiré de la flak et de la défense ponctuelle de Stellaris ([journal de développement 271](https://devtrackers.gg/stellaris/p/d228cc12-stellaris-dev-diary-271-ready-fight)).
- **Taille des coques.** Les torpilles frappent plus fort les grosses coques (40 % contre une petite, 250 % contre un titan) ; l'artillerie lourde écrase de loin mais ne tire plus à courte portée. Même source : bonus de taille des torpilles et portée minimale des grosses armes dans Stellaris.

**Les classes communes**

| Classe | Rang | Rôle | Particularité |
| --- | --- | --- | --- |
| Corvette | Écran | Chasse | Canons cinétiques, mortelle au contact |
| Escorteur | Écran | Antimissile | Défense ponctuelle 30 %, +15 % à toute sa flotte |
| Frégate | Ligne | Ligne | Rayons à moyenne portée, boucliers |
| Torpilleur | Ligne | Anti-gros | Torpilles, bonus contre les grandes coques et le titan |
| Croiseur | Ligne | Siège | Missiles, blindage, 12 troupes |
| Transport de troupes | Arrière | Invasion | 30 troupes, aucune arme |
| Bombarde | Arrière | Siège | Siège 8 : use la garnison bien plus vite |
| Cuirassé | Arrière | Artillerie | Artillerie lourde, rien à courte portée ; demande un **arsenal orbital** |
| Porte-vaisseaux | Arrière | Chasseurs | Chasseurs qui ignorent les rangs ; demande un arsenal orbital |
| Titan | Ligne | Méga-vaisseau | Premier échelon des méga-vaisseaux : un seul par empire, demande un **chantier titanesque** (qui demande un arsenal), annoncé à toute la galaxie |

**Les classes de peuple.** Une classe de peuple existe quand elle a du sens pour lui. Elle ne dépend pas de l'identifiant de la faction mais des **couches d'espèce** du GDD (registre, archétype, gouvernement, credo, traits ; bloc `"species"` de `data/factions.json`) : une espèce créée plus tard dans l'éditeur qui partage la combinaison y aura droit aussi. L'idée vient des armes du Colosse de Stellaris, qui dépendent des éthiques de l'empire ([guide](https://gamerempire.net/?p=55930)).

| Classe | Condition d'espèce | Peuple V1 | Effet |
| --- | --- | --- | --- |
| Coursier de saut | trait « navigateurs » | Ossarane | Remplace la corvette ; une flotte de coursiers traverse les blocus |
| Martyr | credo « foi » | Chœur Éternel | S'ajoute ; payé en population, il se sacrifie à courte portée (gros dégâts, +5 ferveur) |
| Frégate des Quarante | trait « pluriel » | Vael | Remplace la frégate ; ouvre la tactique **Adaptative** à sa flotte |
| Ruche-mère | archétype « ruche » | Kh'thari | Remplace le porte-vaisseaux ; payée en nourriture et en population plutôt qu'en métal |

**L'IA et le catalogue.** La Recrue pioche au hasard dans ce qu'elle peut construire. Le Normal ajoute un escorteur de temps en temps et des transports quand les troupes manquent. Le Vétéran et au-dessus gardent un tiers d'écran, prennent des escorteurs contre les missiles et chasseurs ennemis, des torpilleurs contre les grosses coques, des cuirassés ou porte-vaisseaux une fois l'arsenal bâti, une bombarde pour les sièges, et lancent leur titan dès que possible. Toutes utilisent la classe de leur peuple à la place du modèle commun, et la tactique Adaptative quand elles l'ont.

À venir, selon l'étude : les familles d'armes, modules et doctrines viendront avec la couche de technologies ; les échelons de méga-vaisseaux au-dessus du titan, plus tard (jeu de base ou extension, à décider par échelon).

### Éditeur de vaisseaux (lot 1 : le moteur)

Étude sourcée (Endless Space 2, Stellaris, Galactic Civilizations IV, Master of Orion II) : https://claude.ai/artifact/F51fEJz4ATWYVRL1Pk7ftb

- Un vaisseau = une **coque** (`data/designs.json`, `hulls`) + ses **modules intégrés** (coques de peuple, jamais retirables) + les **modules posés** dans ses emplacements typés : armes, lourds (artillerie, hangars), défense, soutien, titanesque. Les types d'emplacements sont des données (`slot_types`, champ `accepts`) : un échelon de méga-coque au-delà du titan ajoute le sien sans toucher au code.
- La valeur d'un module dépend de la taille de la coque (petite, moyenne, grande, titan), comme les tailles d'emplacements de Stellaris. Un emplacement vide ne coûte rien : le vaisseau est moins cher et sort plus vite.
- Les classes de combat de `data/ships.json` sont des **modèles d'origine** (`origin`) : leurs caractéristiques sont calculées depuis leur coque et leurs modules. Corvette, frégate, croiseur, cuirassé, porte-vaisseaux, titan, martyr et ruche-mère gardent exactement leurs chiffres ; escorteur, torpilleur, transport, bombarde, coursier et frégate des Quarante, devenus des modèles sur une coque commune ou de peuple, bougent un peu.
- Les modèles conçus en partie vivent dans `GameState.designs` (sauvegarde version 10 ; les parties version 9 se chargent encore) : nom, coque, modules, rang (écran, ligne, arrière), priorité de cible, version. Une nouvelle version garde la coque et retire l'ancienne de la liste de construction ; les vaisseaux déjà construits restent tels quels. `GameData.ship()` les lit comme des classes, donc combat, flottes et chantiers fonctionnent sans changement.
- Commandes : `SimCommands.save_design`, `SimCommands.retire_design`. Tests : `tests/design_tests.gd`.
- **Écran Chantier** (F6, lot 2) : modèles rangés par coque à gauche (« + Coque » ouvre un brouillon vierge), coque schématique au centre avec ses emplacements colorés par type (clic : choisir, clic droit : vider), modules de l'emplacement choisi à droite avec leur effet pour cette taille de coque, caractéristiques en bas comparées au modèle affiché (dégâts par phase, coque, défenses, vitesse, coût, durée). Enregistrer, nouvelle version, retirer ou remettre en service. Captures : `tools/capture_shipyard.gd`.

![Écran Chantier](docs/apercu-chantier.png)

- À venir : priorité de cible en bataille et seuils de miniaturisation (lot 4), conception automatique et IA qui conçoivent leurs modèles (lot 3), hangars à variantes et modules titanesques (lot 4).

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
    faction_traits.gd     Traits des peuples : fiefs, ferveur, vote d'urgence, vaisseaux-spores, biomasse
    research.gd           Recherche : arbre de chaque peuple, file, ères, coûts, avancée mensuelle, effets des technologies
    ai/                   Empires IA : niveaux de difficulté (ai_levels.gd), cerveau (ai_player.gd), diplomatie (ai_diplomacy.gd)
    fleet.gd              Une flotte : vaisseaux, position, trajet
    fleets.gd             Règles des flottes : chemins, délais, vision et brouillard, vérification des ordres
    combat.gd             Règles du combat : puissance, dégâts, tactiques, guerre, garnison, siège, invasion
    diplomacy.gd          Règles de la diplomatie : statuts, traités, opinion, souvenirs, héritier, arbitrage
    empire_report.gd      Bilans d'un empire pour les menus (lecture seule) et parcours de ses systèmes
    systems/              Systèmes de simulation exécutés à chaque tick
      economy_system.gd   Fondations, chantiers, croissance chaque jour ; bilan chaque mois
      fleet_system.gd     Chantiers spatiaux, déplacements, exploration et premiers contacts
      chronicle_system.gd Petits événements racontés par le chroniqueur
      combat_system.gd    Batailles, blocus, sièges, réparations et empires disparus
      diplomacy_system.gd Propositions qui expirent ; chaque mois confiance, cartes des alliés, souvenirs, héritier
      ai_system.gd        Empires IA : chacun réfléchit à son rythme et donne des ordres ordinaires
    game_clock.gd         Horloge (autoload GameClock) : pilote la simulation en temps réel (pause, 5 vitesses) ou au tour par tour
  view/                   Affichage 2D (sera remplacé par la 2,5D)
    galaxy_view.gd        Dessin des étoiles, routes, sélection, noms
    galaxy_camera.gd      Zoom et déplacement
    system_view.gd        Vue système : étoile, orbites, planètes animées, annotations, clic sur une planète
  ui/
    ui_theme.gd           Thème visuel : palette, polices, panneaux plats, styles nommés
    hud.gd                Interface en jeu : onglets de vue, fiche de sélection, notifications, chronique, cadran
    empire_bar.gd         Panneau d'empire (menus, ressources, ligne d'état)
    time_dial.gd          Cadran du temps (pause, date, vitesse ; fin de tour au tour par tour)
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
    battle_report_panel.gd Rapport de bataille (B)
    battle_replay_panel.gd Vue de replay : rejoue le journal d'une bataille (R)
    diplomacy_table.gd    Table des statuts diplomatiques (écran Diplomatie)
    research_tree.gd      Arbre des technologies (écran Recherche)
assets/fonts/             Police Exo 2 (licence SIL OFL, fichier de licence à côté)
assets/art/               Illustrations d'habillage (vide pour l'instant, voir assets/art/LISEZMOI.md)
shaders/                  Rendu de la vue système (planète éclairée, étoile, fond étoilé)
tools/
  capture_system_view.gd  Captures d'écran de la vue système (rendu réel, voir l'en-tête du fichier)
  capture_ui.gd           Captures des menus et de l'interface
  capture_fleets.gd       Captures des flottes et du brouillard de guerre
  capture_factions.gd     Captures des 4 peuples et de leurs ordres propres
  capture_combat.gd       Captures du combat (bataille, rapport, siège, diplomatie, spectateur en guerre)
  capture_diplomacy.gd    Captures de la diplomatie (Vael, arbitrage, héritier d'Ossarane, spectateur)
  capture_research.gd     Captures de l'écran Recherche (Chœur, Vael) et rythme d'une partie entre IA
  war_bench.gd            Banc d'essai de la guerre entre IA (batailles, sièges, invasions, disparitions)
  main.gd                 Assemble le tout et gère les entrées
data/                     Données de jeu en JSON : tout l'équilibrage se règle ici
  rules.json              Ressources, coûts de colonisation, croissance, gisements, monde d'origine
  factions.json           Les 4 factions de la V1 : couleur, planètes préférées, bonus
  planet_types.json       Types de planètes : habitabilité, rendements, fréquence selon l'étoile
  buildings.json          Bâtiments : coût, durée, rendement, entretien
  ships.json              Classes de vaisseaux : coût, durée, entretien, vitesse, vision, armes, défenses, troupes
  combat.json             Combat : phases, armes, tactiques, garnisons, siège, réparations
  diplomacy.json          Diplomatie : traités, opinion, souvenirs, talents des peuples, jugement de l'IA
  technologies.json       Recherche : domaines, ères, coûts, et toutes les technologies avec leurs effets
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

Un test de fumée vérifie la génération (plusieurs graines : 150 systèmes, galaxie connectée, noms uniques, déterminisme), le noyau de simulation (`tests/sim_tests.gd` : déterminisme sur 1000 ticks, ordres valides et refusés, ordres en pause, rediffusion, sauvegarde/chargement à l'identique, reprise après chargement identique à une partie jamais interrompue, fichiers abîmés refusés, performance), l'économie (`tests/economy_tests.gd` : données, planètes déterministes, départ des 4 empires, bilan mensuel exact, traits de faction, colonisation et chacun de ses refus, avant-poste transformé en colonie, chantiers et emplacements, croissance plafonnée, famine, pénurie d'énergie, déterminisme, rediffusion et sauvegarde avec colonies, 10 ans sans stock négatif), les empires IA (`tests/ai_tests.gd` : niveaux ordonnés, rivaux et spectateur, expansion en 2 ans sans famine, déterminisme et rediffusion, tour par tour identique au temps réel, aucune triche (brouillard, stocks), Recrue < Vétéran < Légende, talents de chaque peuple selon le niveau, tempérament (décalage du peuple, sauvegarde, belliqueux plus collé à ses rivaux que pacifique), sauvegarde, performance), les flottes (`tests/fleet_tests.gd` : flottes et vision de départ, chemins le long des routes, arrivée au jour annoncé, refus, demi-tour et arrêt en route, chantier spatial, colonisation par vaisseau colon, rassembler et détacher, entretien, premier contact, sauvegarde en plein trajet, rediffusion, expéditions d'exploration), le combat (`tests/combat_tests.gd` : règles de dégâts, déclaration de guerre, bataille et rapport, rapports de force, tactiques, déterminisme et sauvegarde en pleine bataille, blocus, retraite, siège et invasion, disparition d'un empire, traits de combat des 4 peuples, fusion et réparations, IA qui arme, déclare et se bat selon son tempérament et son niveau), le catalogue (`tests/catalogue_tests.gd` : classes de chaque peuple, conditions d'espèce d'une espèce personnalisée, arsenal et titan unique, torpilles, artillerie et défense ponctuelle, écran qui protège l'arrière, chasseurs qui le touchent, Martyr, tactique Adaptative, Coursier qui force le blocus, lancement du titan, IA qui se sert du catalogue, journal de bataille cohérent avec le rapport et identique après rechargement), la diplomatie (`tests/diplomacy_tests.gd` : statuts, propositions, refus, délais et expiration, trêve, alliance qui partage cartes et guerres, allié en paix qui reste en dehors, parjure, dénonciation, opinion (registres, credos, traits, souvenirs qui s'effacent), Essaim sans traité et espèce personnalisée, jugement de l'IA (guerre récente, guerre longue et perdue, tempérament, humeur de la Recrue, croisade), héritier soudoyé, banquet et trahison, arbitrage, ferveur, score de guerre, sauvegarde, partie entre IA déterministe où des traités se signent), la recherche (`tests/research_tests.gd` : arbre cohérent, arbre de chaque peuple (variantes, interdits, hérésies, peuple personnalisé), file et seuils d'ère, travail mis de côté, coûts (ère, technologies connues, taille de l'empire, talents des peuples), avancée mensuelle, effets sur l'économie, les flottes et le combat, contenu verrouillé, alliances et Chancelleries, ferveur et Exaltation, IA qui recherche selon son tempérament, déterminisme, sauvegarde), l'horloge et la scène principale avec des entrées simulées (pause, vitesse, clic, ouverture et fermeture de la vue système, bascule vers la vue de gestion, construction et colonisation depuis la fiche de la planète, renommage, F5/F9, Échap, brouillard, sélection de flotte, clic droit pour l'envoyer, fiche de flotte, F, chantier spatial), les bilans d'empire, l'interface (thème, barre d'empire, écrans Économie, Colonies, Recherche et Diplomatie (filtres, colonie choisie, anneau), pause automatique, Tab, H, flèches, fiche de sélection, lentille économique, cadran du temps, menu pause, menu principal et nouvelle partie avec faction et graine choisies, vue de replay ouverte depuis le rapport) ainsi que la géométrie de la vue système (planètes dans la scène et cliquables) :

```
godot --headless --path . -s res://tests/smoke_test.gd
```

Il affiche `OK : N vérifications passées.` et renvoie le code 0 si tout passe, 1 sinon.

## Limites connues

- Diplomatie V1 : ni vassalisation, ni conseil galactique, ni exigences ; les chiffres d'opinion et de jugement de l'IA sont à équilibrer en jouant. Les guerres contre l'Essaim ne finissent jamais (c'est voulu).
- Pas de conception modulaire des vaisseaux ni de contrôle pendant la bataille (la vue de replay ne fait que la rejouer ; conception modulaire prévue après la V1 dans le GDD), pas d'amiraux ni de héros (les héros de Vael attendent le système de personnages). Les classes du catalogue se débloquent par des technologies (et certaines par un bâtiment) ; l'éditeur de vaisseaux complet viendra avec ses modules.
- Les vaisseaux colons de l'IA ne tiennent pas encore compte des zones de guerre.
- Faute d'autre usage, les matériaux s'entassent chez les IA en milieu de partie ; l'Essaim Kh'thari, qui ne paie jamais d'influence, s'étend plus vite que les autres (équilibrage des peuples à revoir).
- Hors de vue, les systèmes explorés montrent leur propriétaire actuel, pas la dernière information connue.
- Pas encore de mécaniques signatures des factions : prochaine étape, les factions jouables.
- Équilibre des peuples bousculé par la recherche (contenu verrouillé, alliances qui attendent les Chancelleries) : sur trois parties d'essai de 9 ans entre IA Normal, Ossarane s'en sort plus mal qu'avant. À surveiller en jouant.
- Recherche, lot 1 : pas encore de marques d'armes IV-V, de doctrines, d'épaves, d'eurêkas ni de technologies ultimes ; les ères 4 et 5 sont presque vides. Les familles d'armes exclusives des peuples attendent l'éditeur de vaisseaux.
- Un seul emplacement de sauvegarde (rapide) pour l'instant ; l'écran de sauvegardes multiples viendra plus tard.
- Pas encore de sons d'interface ni de raccourcis personnalisables.
- Le multijoueur lui-même (réseau) n'est pas fait : le noyau est prêt pour un hôte qui fait autorité, mais rien n'est encore envoyé sur le réseau.
