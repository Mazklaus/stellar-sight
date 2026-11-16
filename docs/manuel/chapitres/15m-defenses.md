---
titre: Les défenses spatiales
numero: 31
image: MJ-48
epigraphe: On ne prend pas un monde, on prend d'abord son ciel. Et notre ciel, Messieurs, a des dents.
signature: Commandeur Thessaly Vaurn, gouverneur militaire du Rempart stellaire d'Ardhan
---
Un système n'attend plus seulement ses flottes pour se défendre. Avec les défenses spatiales en jeu, chaque système peut porter une **station de défense** à trois paliers, garnie de **modules**, entourée de **plates-formes**, protégée par des **champs de mines** et un **inhibiteur de saut**, tandis que ses planètes dressent **batteries**, **hangars** et **boucliers**. Tout ce qui est armé forme une flotte fixe du défenseur qui **se bat dans chaque bataille du système**, et tant que la station tient l'orbite, l'ennemi ne peut **ni assiéger, ni bombarder, ni débarquer**. Il doit d'abord la faire taire.

Le modèle vient de **Master of Orion** (2016 ; bases de missiles, garnisons de chasseurs, bouclier planétaire, postures Garde et Blocage), de **Galactic Civilizations IV** (bases stellaires à modules, sentinelles des colonies), de **Sins of a Solar Empire II** (points de structure, plates-formes légères et lourdes, faiblesses des défenses fixes), de **Distant Worlds 2** (les quatre étapes d'une invasion, armes planétaires qui abattent les barges, opérations spéciales contre les défenses), de **Starsector** (une station vaincue se tait et se répare en quelques mois) et de **VGA Planets** (champs de mines à densité, usure et déminage). Les pages de Stellaris étaient fermées à la lecture : les quelques idées qui en viennent (capacité de plates-formes, canon ionique, inhibiteur) ont été vérifiées dans des extraits de recherche seulement.

::: capture docs/apercu-defenses.png|La vue système d'une capitale fortifiée : le panneau Défenses montre la station, ses modules, les plates-formes, le dôme, le champ de mines et l'étape de l'assaut
:::

### Le réglage

Le bloc Règles de la nouvelle partie propose le réglage **Défenses spatiales**. **Désactivées** garde le comportement d'avant : le Bastion et la Citadelle n'agissent qu'au siège.

{{def_modes}}

### Trois couches

Un système se défend sur trois couches, que l'assaillant doit percer dans l'ordre :

1. **l'orbite** : la station, ses modules, les plates-formes et les mines ;
2. **le sol-orbite** : batteries, hangars et boucliers planétaires ;
3. **le sol** : la garnison, les fortifications et la Citadelle (chapitre 9 et combat au sol), inchangés.

La fiche du système et le panneau **Défenses** de la vue système affichent l'**étape de l'assaut** : les flottes du défenseur tiennent, puis la station, puis le bouclier, puis les fortifications et la garnison, et enfin le monde est ouvert au débarquement.

### La station de défense

Une seule station par système, sur une colonie ou un avant-poste. Le **Bastion orbital** que vous connaissez en devient le palier I ; la **Forteresse orbitale** puis le **Rempart stellaire** s'améliorent sur place et gardent son rôle (garnison, tir de siège, fortifications, tir sur les barges). Un palier achevé remet le cœur à neuf.

{{def_stations}}

La **couverture** de la station profite aux flottes du propriétaire et de ses alliés dans le système : autant de dégâts en plus, et autant de dégâts subis en moins.

**Vaincue n'est pas rasée.** Quand le cœur de la station tombe au combat, elle est **réduite au silence** : ses armes se taisent, le siège devient possible. Hors combat, chaque élément regagne un soixantième de ses PV par jour ; la station reprend du service quand son cœur est réparé. Si le système est pris, elle change de mains, endommagée. Les **plates-formes détruites**, elles, sont perdues.

### Modules, plates-formes, planètes

Les **modules** se posent sur la colonie de la station, sans emplacement de planète : 2, 4 ou 6 selon le palier. Les modules d'armes ajoutent une unité à la défense ; le blindage ablatif et le générateur de bouclier renforcent le cœur (trois de chaque au plus) ; la baie de réparation répare les flottes amies pendant la bataille ; le centre de commandement ajoute des places ; les grands senseurs, un saut de vision.

Les **plates-formes** se bâtissent en série sur la même colonie, chacune prend des **places** de la **capacité de défense** du système : la base du palier, une place par tranche de 6 habitants du système, les technologies, le centre de commandement et certains talents. Pas de mur infini.

Les **défenses planétaires** se bâtissent sur n'importe quelle colonie : la batterie tire de loin et sur les barges, le hangar lance ses escadrilles, le bouclier use le siège avant tout le reste.

{{def_elements}}

Les **sentinelles** viennent gratuitement : une petite milice orbitale par colonie de 6 habitants, deux à partir de 12, sans entretien, qui ne quitte jamais le système (défenses complètes seulement).

Plates-formes et modules **gardent les marques d'armes** de leur construction (chapitre 7). Le bouton **Moderniser** du panneau Défenses les remet aux marques du jour pour un quart de leur prix.

### Le bouclier planétaire

**Bouclier I** : le bombardement et la dévastation sont divisés par deux. **Dôme** (niveau II) : tant qu'il a des points, ni bombardement ni débarquement. Le siège use d'abord les points du bouclier, puis la garnison et les fortifications ; hors siège, il remonte de 5 points par jour.

### Mines et inhibiteur

Un **champ de mines** a une densité de 0 à 100. Le module **Mouilleur** (station de palier II) en sème chaque mois, un vaisseau équipé du module **Mouilleur de mines** aussi, à l'arrêt chez vous, dans un système libre ou chez un ennemi en guerre (un seul champ par système : celui d'un autre doit d'abord être balayé). Chaque vaisseau ennemi qui entre a une chance d'être touché égale à la moitié de la densité (densité 100 : une chance sur deux) : il perd une part de sa coque (plus lourde pour les petites coques, jamais mortelle) et sa flotte perd la fin de son trajet du jour. La densité s'use de 5 % par an (trois fois plus dans une nébuleuse) ; le module **Démineur** balaie un champ ennemi chaque jour, les armes à rayons un peu en passant.

L'**inhibiteur de saut** (module, palier II) retient dans le système toute flotte ennemie qui y entre, **même les coursiers de saut** qui forcent les blocus, tant que la station tient. C'est lui qui fait les goulots d'étranglement. Une tempête le coupe.

Mines et inhibiteur ne touchent que les **ennemis en guerre**, les pirates et la faune hostile : jamais un empire en paix.

### Garder un système

Le bouton **Garder** de la fiche de flotte donne à une flotte armée la posture de **garde** du système où elle se trouve : +10 % de dégâts sur place, en plus de la couverture de la station, et si on l'attire au-dehors, elle revient dès qu'elle est à l'arrêt. Un ordre de déplacement donné à la main lève la garde.

### Attaquer des défenses

Les défenses fixes ne fuient pas et ne manœuvrent pas (tactique Rempart imposée). La **stat de siège** (bélier, canon de siège, nouvelles **Torpilles de siège**) **double les dégâts** contre stations, plates-formes et batteries ; les missiles à longue portée restent la bonne réponse aux défenses fixes. Une IA mesure la force des défenses avant d'attaquer.

### Ponts avec les autres piliers

- **Espionnage** : trois opérations de sabotage de plus, **Couper un bouclier planétaire** et **Couper un inhibiteur de saut** (30 jours), **Saboter les plates-formes** (la moitié de leurs PV).
- **Traités** : nouvelle clause de paix **Démilitariser un système** : la station et les plates-formes du système du vaincu le plus proche des vôtres sont démontées, et rien ne s'y rebâtit pendant 10 ans. À l'**Amphictyonie**, les Lois de la guerre interdisent les mines au niveau **Guerre réglée**.
- **Héros** : le trait **Ingénieur de place** d'un gouverneur ajoute 2 places et double la vitesse des réparations ; un **Général** présent dans le système fait tirer les défenses 10 % plus fort.
- **Terrain** : dans une ceinture d'astéroïdes, le cœur de la station gagne 15 de blindage ; une nébuleuse use les mines trois fois plus vite ; une tempête coupe l'inhibiteur.
- **Hauts faits** : **Inviolée**, tenir cinquante ans une capitale gardée par une station sans qu'elle soit jamais assiégée. Les défenses tirent aussi sur les flottes des crises et des puissances anciennes éveillées.
- **Peuples mineurs** : à l'âge atomique ou à l'aube spatiale, un peuple pré-spatial a sa station ; un peuple spatial, une forteresse.
- **Économie** : l'entretien des défenses passe au budget comme celui des bâtiments ; une compagnie privée peut payer une plate-forme canon dans un système à comptoir.

### Talents de peuple

{{def_talents}}
