---
titre: Ombres et senseurs
numero: 33
image: MJ-50
epigraphe: Mon capitaine, l'écran est vide. — Justement, lieutenant. Il ne l'était pas hier, et personne n'est parti.
signature: Journal de bord du croiseur Clairvoyance, frontière de l'Abysse
---
Jusqu'ici, voir un système suffisait à voir ce qui s'y trouvait. Avec la furtivité en jeu, une flotte peut se **cacher** dans la portée de vos senseurs : il faut aussi la **percer**. Deux niveaux de 0 à 5 s'affrontent, le **camouflage** de la flotte et la **détection** de celui qui regarde. La **portée** reste la vision en sauts que vous connaissez (chapitre 4) : la détection dit seulement ce que l'on distingue dans ce que l'on voit.

Le modèle vient de **Stellaris** (modules de camouflage, détection des stations, le voile qui tombe au tir), d'**Endless Space 2** (les modules anti-camouflage I à III des Quadrinix Toroids, les sondes, le Chœur Umbral et ses flottes cachées), de **Starsector** (un contact flou d'abord, identifié ensuite ; le terrain qui cache ; « faire le noir » pour passer inaperçu), de **Distant Worlds 2** (on détecte « quelque chose », puis l'empire, puis le type) et du manuel communautaire d'**Aurora 4X** (les senseurs actifs qui trahissent celui qui les allume, les brouilleurs). Le compte rendu de développement de Stellaris sur le camouflage et le wiki de Stars! étaient fermés par une vérification anti-robot : rien n'en vient.

::: capture docs/apercu-furtivite.png|Une corvette voilée en Silence radio près de la capitale : la fiche de flotte donne son camouflage, sa détection et sa posture ; plus loin, une ombre grise, sans pavillon
:::

### Le réglage

Le bloc Règles de la nouvelle partie propose le réglage **Furtivité**. **Désactivée** garde le comportement d'avant : une flotte est vue dès qu'elle est à portée, et seul le Voile des Murmurants d'Abysse cache encore.

{{st_modes}}

### La règle de repérage

Une flotte est **vue** si l'une de vos sources (colonie, flotte, balise d'écoute, ou celles d'un allié) couvre son système avec une **détection au moins égale à son camouflage**. Les **yeux nus** voient 1 : une flotte sans voile (camouflage 0) se voit comme avant. Une **tempête de radiations** aveugle tout le monde : détection 0 dans le système.

- Le **camouflage** d'une flotte est celui de son vaisseau **le plus faible** : un cuirassé sans voile trahit toute l'escadre. S'y ajoutent le terrain (nébuleuse +1, nébuleuse ionisée +2, ceinture d'astéroïdes +1 à l'arrêt), la posture Silence radio (+1), le trait d'amiral Fantôme et les talents de peuple. Plafond : 5.
- La **détection** d'une source vaut 1, plus son meilleur **Réseau de détecteurs** (flottes), le **Réseau d'écoute** et le **Poste d'écoute** (colonies), les technologies et les talents.

### Se cacher : les voiles

Le module de soutien **Voile de camouflage** existe en trois marques. Chacune cache **un point au-dessus des yeux nus** : la marque I ne vaudrait rien contre une détection de base 1, d'où des camouflages de 2 à 4. Un méga-vaisseau ne se cache qu'avec le **Voile titanesque**.

{{st_modules}}

Le voile a un prix :

- il **ralentit** la flotte (vitesse à 70, 80 ou 90 % selon la marque) ;
- il **tombe au premier tir** : bataille, siège ou débarquement ; il se relève **30 jours** plus tard, et le jour où il tombe, les boucliers de la flotte ne valent que la moitié ;
- une flotte cachée **ne déclenche ni intrusion ni bataille**, n'assiège pas, se glisse entre les blocus, les mines et les inhibiteurs de ceux qui ne la voient pas ; mais elle reste aussi **à l'écart des combats**.

### Les postures

Le bouton **Posture** de la fiche de flotte passe d'une posture à l'autre :

- **Silence radio** (furtivité complète) : +1 de camouflage, vision réduite au système, vitesse divisée par deux ;
- **Balayage actif** (furtivité complète) : +1 de détection et un saut de portée, mais la flotte est vue en entier par tous ceux qui voient son système ; son voile est baissé ;
- **Embuscade** : la flotte cachée **engage** les ennemis présents au lieu de rester à l'écart, et frappe **+25 %** le premier jour. Le voile tombe aussitôt.

### Voir : détecteurs, écoute, balises, sondes

- **Réseau de détecteurs I à III** (modules de soutien) : +1 à +3 de détection sur toute la portée de vision de la flotte.
- **Réseau d'écoute** (bâtiment de colonie, technologie Réseau de détecteurs) : +1 de détection pour la colonie.
- **Poste d'écoute** (module de station, défenses spatiales en jeu) : +2 de détection et un saut de portée de plus.
- **Senseurs quantiques** : +1 de détection pour toutes vos sources.
- **Balise d'écoute** (Senseurs tachyoniques, furtivité complète) : un éclaireur **sans armes** à l'arrêt la pose hors de chez vous pour 30 matériaux et 20 énergie (6 au plus). Camouflée (2), elle voit à un saut ; le maître du système la détruit dès qu'il la repère.
- La **sonde d’espionnage** (chapitre 13) relève les flottes cachées du système sondé jusqu'au camouflage 3.

**La lentille Senseurs.** Un second clic sur l'onglet **Guerre** (ou une seconde pression de [[W]]) affiche la couverture de vos senseurs : sur chaque système exploré, un disque bleu d'autant plus vif que la détection est forte, et le **niveau de camouflage** que vous percez là (de 0 à 5), alliés compris. Là où rien ne s'affiche, vous êtes aveugle : une flotte peut y passer sans même un contact. Les anneaux blancs marquent vos **postes fixes** (colonies, stations, balises). C'est la carte à consulter avant de laisser une frontière sans détecteurs.

### Savoir : contact, identifiée, détaillée

En furtivité complète, voir une flotte cachée ne dit pas tout. Trois degrés :

1. **Contact** : une ombre grise sur la carte, une taille, **pas de pavillon** ;
2. **Identifiée** : à un saut au plus d'une source qui la perce, on sait à qui elle est ;
3. **Détaillée** : sur place, ou avec 2 points de détection d'avance, on sait tout.

Le **brouilleur** plafonne une flotte repérée de loin à « identifiée », sauf à 3 points d'avance. Le **lance-leurres** sème, chez ceux qui n'ont qu'un contact, une flotte fantôme plus grosse dans un système voisin ; elle s'efface quand on regarde de près.

### Les Murmurants d'Abysse

Le **Voile** des peuples énergétiques voilés devient un **camouflage inné de 3** sur leurs flottes. Contre eux, une présence **à l'arrêt** sur place voit +2, et les **Détecteurs d'abysse** donnent +2 partout : exactement le Voile d'avant, mais dans les règles communes. Le Silence parfait ne change pas. **Le Voile se perce de près** : un de vos systèmes doté de senseurs de niveau 2 (un **Réseau d'écoute**, ou une technologie de détection) sent aussi les colonies voilées de ses **voisins immédiats**. Un peuple voilé installé contre votre frontière ne reste donc pas caché longtemps, et chaque repérage remet à zéro le compte à rebours du Silence parfait.

### Ponts avec les autres piliers

- **Espionnage** : l'opération **Voler les codes de camouflage** donne +2 de détection contre toutes les flottes du rival pendant un an ; un réseau au palier **Amirauté** perce de lui-même le camouflage de ses flottes.
- **Défenses spatiales** : mines, inhibiteurs et blocus ne retiennent que ce que leur maître voit ; le Poste d'écoute se monte sur la station.
- **Puissances non impériales** : les **pirates** se cachent (camouflage 2) en furtivité complète, le **Spectre des pulsars** et ses éclats aussi ; les crises et les puissances anciennes voient tout sur place (5).
- **Héros** : traits d'amiral **Fantôme** (+1 de camouflage), **Œil-de-lynx** (+1 de détection), **Chasseur d'ombres** (+25 % de dégâts dans une bataille où un ennemi était caché).
- **Griefs** : repérer chez soi, en temps de paix, une flotte camouflée d'un autre empire laisse un souvenir amer (−10 d'opinion pendant un an).
- **Hauts faits** : **Premier voile** (lancer une flotte camouflée), **Spectre** (traverser dix systèmes rivaux sans être vu), **Nul ne passe** (repérer cinq flottes cachées).
- **IA** : dès le niveau Normal, une IA qui subit une embuscade ou entre en guerre cherche le Réseau de détecteurs et bâtit des Réseaux d'écoute ; le Vétéran envoie ses flottes voilées en Embuscade.

### Talents de peuple

{{st_talents}}
