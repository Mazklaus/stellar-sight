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
| Déclarer la guerre | Écran Diplomatie (F4), bouton sous l'empire rencontré, deux clics |
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

**Comment c'est fait.** L'IA fait partie de la simulation (`AiSystem`, appelé à la fin de chaque tick, et le cerveau `AiPlayer`) : elle ne voit que ce que son empire a exploré et n'agit que par les ordres ordinaires (`SimCommands`), validés comme ceux d'un joueur. Ses « oublis » viennent d'un hachage de la graine et du jour, jamais de l'aléatoire global : elle joue exactement pareil en temps réel et au tour par tour, dans une rediffusion (le journal ne garde que les ordres des joueurs, les IA se rejouent seules) et sur toutes les machines d'une partie en réseau. Le module `_military` mène la guerre (voir Combat spatial) ; `_diplomacy` est en place, vide, pour la diplomatie.

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

- **La guerre.** Les empires se déclarent la guerre depuis l'écran Diplomatie (F4), une fois rencontrés ; elle vaut dans les deux sens. L'Essaim Kh'thari est en guerre avec tout empire qu'il rencontre. La paix et les traités arriveront avec la diplomatie.
- **Trois vaisseaux de guerre** (périmètre V1 du GDD), construits au chantier spatial : la **corvette** (rapide, canons cinétiques, mortelle au contact), la **frégate** (rayons à moyenne portée, boucliers) et le **croiseur** (missiles à longue portée, blindage, 12 troupes pour les invasions). Éclaireurs et vaisseaux colons ne sont pas armés : ils subissent.
- **La bataille** est automatique et dure six jours : deux à longue portée, deux à moyenne, deux à courte. Chaque famille d'armes a sa portée (missiles 90/70/40 %, rayons 50/90/70 %, canons 20/40/90 %), les boucliers réduisent les rayons, le blindage les canons et les missiles. Tous les vaisseaux tirent chaque jour sur une cible au hasard (tirée par la simulation, donc identique sur toutes les machines), les dégâts s'appliquent ensemble. Au bout des six jours, un rapport est rédigé (B) ; si les deux camps sont encore là, une nouvelle bataille commence. Les flottes qui arrivent en cours de route rejoignent la bataille.
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
    ai/                   Empires IA : niveaux de difficulté (ai_levels.gd), cerveau (ai_player.gd)
    fleet.gd              Une flotte : vaisseaux, position, trajet
    fleets.gd             Règles des flottes : chemins, délais, vision et brouillard, vérification des ordres
    combat.gd             Règles du combat : puissance, dégâts, tactiques, guerre, garnison, siège, invasion
    empire_report.gd      Bilans d'un empire pour les menus (lecture seule) et parcours de ses systèmes
    systems/              Systèmes de simulation exécutés à chaque tick
      economy_system.gd   Fondations, chantiers, croissance chaque jour ; bilan chaque mois
      fleet_system.gd     Chantiers spatiaux, déplacements, exploration et premiers contacts
      chronicle_system.gd Petits événements racontés par le chroniqueur
      combat_system.gd    Batailles, blocus, sièges, réparations et empires disparus
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
assets/fonts/             Police Exo 2 (licence SIL OFL, fichier de licence à côté)
assets/art/               Illustrations d'habillage (vide pour l'instant, voir assets/art/LISEZMOI.md)
shaders/                  Rendu de la vue système (planète éclairée, étoile, fond étoilé)
tools/
  capture_system_view.gd  Captures d'écran de la vue système (rendu réel, voir l'en-tête du fichier)
  capture_ui.gd           Captures des menus et de l'interface
  capture_fleets.gd       Captures des flottes et du brouillard de guerre
  capture_factions.gd     Captures des 4 peuples et de leurs ordres propres
  capture_combat.gd       Captures du combat (bataille, rapport, siège, diplomatie, spectateur en guerre)
  war_bench.gd            Banc d'essai de la guerre entre IA (batailles, sièges, invasions, disparitions)
  main.gd                 Assemble le tout et gère les entrées
data/                     Données de jeu en JSON : tout l'équilibrage se règle ici
  rules.json              Ressources, coûts de colonisation, croissance, gisements, monde d'origine
  factions.json           Les 4 factions de la V1 : couleur, planètes préférées, bonus
  planet_types.json       Types de planètes : habitabilité, rendements, fréquence selon l'étoile
  buildings.json          Bâtiments : coût, durée, rendement, entretien
  ships.json              Classes de vaisseaux : coût, durée, entretien, vitesse, vision, armes, défenses, troupes
  combat.json             Combat : phases, armes, tactiques, garnisons, siège, réparations
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

Un test de fumée vérifie la génération (plusieurs graines : 150 systèmes, galaxie connectée, noms uniques, déterminisme), le noyau de simulation (`tests/sim_tests.gd` : déterminisme sur 1000 ticks, ordres valides et refusés, ordres en pause, rediffusion, sauvegarde/chargement à l'identique, reprise après chargement identique à une partie jamais interrompue, fichiers abîmés refusés, performance), l'économie (`tests/economy_tests.gd` : données, planètes déterministes, départ des 4 empires, bilan mensuel exact, traits de faction, colonisation et chacun de ses refus, avant-poste transformé en colonie, chantiers et emplacements, croissance plafonnée, famine, pénurie d'énergie, déterminisme, rediffusion et sauvegarde avec colonies, 10 ans sans stock négatif), les empires IA (`tests/ai_tests.gd` : niveaux ordonnés, rivaux et spectateur, expansion en 2 ans sans famine, déterminisme et rediffusion, tour par tour identique au temps réel, aucune triche (brouillard, stocks), Recrue < Vétéran < Légende, talents de chaque peuple selon le niveau, tempérament (décalage du peuple, sauvegarde, belliqueux plus collé à ses rivaux que pacifique), sauvegarde, performance), les flottes (`tests/fleet_tests.gd` : flottes et vision de départ, chemins le long des routes, arrivée au jour annoncé, refus, demi-tour et arrêt en route, chantier spatial, colonisation par vaisseau colon, rassembler et détacher, entretien, premier contact, sauvegarde en plein trajet, rediffusion, expéditions d'exploration), le combat (`tests/combat_tests.gd` : règles de dégâts, déclaration de guerre, bataille et rapport, rapports de force, tactiques, déterminisme et sauvegarde en pleine bataille, blocus, retraite, siège et invasion, disparition d'un empire, traits de combat des 4 peuples, fusion et réparations, IA qui arme, déclare et se bat selon son tempérament et son niveau), l'horloge et la scène principale avec des entrées simulées (pause, vitesse, clic, ouverture et fermeture de la vue système, bascule vers la vue de gestion, construction et colonisation depuis la fiche de la planète, renommage, F5/F9, Échap, brouillard, sélection de flotte, clic droit pour l'envoyer, fiche de flotte, F, chantier spatial), les bilans d'empire, l'interface (thème, barre d'empire, écrans Économie, Colonies, Recherche et Diplomatie (filtres, colonie choisie, anneau), pause automatique, Tab, H, flèches, fiche de sélection, lentille économique, cadran du temps, menu pause, menu principal et nouvelle partie avec faction et graine choisies) ainsi que la géométrie de la vue système (planètes dans la scène et cliquables) :

```
godot --headless --path . -s res://tests/smoke_test.gd
```

Il affiche `OK : N vérifications passées.` et renvoie le code 0 si tout passe, 1 sinon.

## Limites connues

- L'IA ne négocie pas encore : pas de paix possible tant que la diplomatie n'existe pas (une guerre déclarée dure jusqu'à la disparition d'un des deux empires).
- Pas de conception modulaire des vaisseaux ni de vue tactique de bataille (prévues après la V1 dans le GDD), pas d'amiraux ni de héros.
- Les vaisseaux colons de l'IA ne tiennent pas encore compte des zones de guerre.
- Faute d'autre usage, les matériaux s'entassent chez les IA en milieu de partie ; l'Essaim Kh'thari, qui ne paie jamais d'influence, s'étend plus vite que les autres (équilibrage des peuples à revoir).
- Hors de vue, les systèmes explorés montrent leur propriétaire actuel, pas la dernière information connue.
- Pas encore de mécaniques signatures des factions : prochaine étape, les factions jouables.
- Les matériaux servent maintenant aux vaisseaux ; la recherche viendra aussi les consommer.
- Un seul emplacement de sauvegarde (rapide) pour l'instant ; l'écran de sauvegardes multiples viendra plus tard.
- Pas encore de sons d'interface ni de raccourcis personnalisables.
- Le multijoueur lui-même (réseau) n'est pas fait : le noyau est prêt pour un hôte qui fait autorité, mais rien n'est encore envoyé sur le réseau.
