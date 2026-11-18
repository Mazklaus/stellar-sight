---
titre: Ce que boit une civilisation
numero: 42
image: MJ-59
epigraphe: On nous demande souvent à quoi sert tant de lumière. Nous répondons que la question est mal posée : c'est la lumière qui se demande à quoi nous servons.
signature: Propos attribué au premier Intendant de la Sphère
---
L'**échelle de Kardashev** classe les civilisations par la puissance qu'elles captent. Une civilisation de **type I** maîtrise l'énergie de sa planète ; de **type II**, celle de son étoile ; de **type III**, celle d'une galaxie. Dans Stellar Sight, c'est un **indice** affiché partout (écran des Victoires, Diplomatie, Mégastructures) qui monte de **0,70** au départ jusqu'à **3,00**. Il récompense ceux qui bâtissent grand, donne une prérogative à chaque demi-palier, et trahit les puissants par leur chaleur.

L'échelle vient de l'astronome **Nikolaï Kardashev** (1964). La formule logarithmique qui donne les décimales et le point de départ à 0,7 viennent de **Carl Sagan** ; la recherche de la chaleur des civilisations avancées, du programme **G-HAT** (Wright et ses collègues, 2014). Les idées de jeu viennent des sources consultées pour l'étude : les dévouements des âges de **Civilization VI** (une récompense au choix à chaque palier, l'Âge sombre et l'Âge héroïque), une discussion de **CivFanatics** sur un 4X bâti autour de Kardashev, l'« esprit de compétition » de **Humankind** (le rattrapage), la puissance relative de **Stellaris** (l'opinion change selon qu'on est plus fort ou plus faible) et l'imagerie de **Warhammer 40K** (l'âge d'or perdu). L'étude n'a trouvé aucun 4X qui fasse de Kardashev un pilier : les verrous, la chaleur et les prérogatives sont propres à Stellar Sight.

::: capture docs/apercu-kardashev.png|L'onglet L'Échelle de l'écran des Victoires : votre indice, votre puissance par source, le verrou du type suivant, les prérogatives et l'échelle des empires connus
:::

### Réglages

{{kd_modes}}

Une partie sauvegardée avant l'édition 2.38 où les mégastructures étaient en jeu passe en réglage Complète : l'ancien indice (1,5 par exemple) devient 1,50, et se recalcule au premier mois.

### La puissance captée

Chaque mois, l'indice se calcule sur votre **puissance captée** :

- l'**énergie brute** de vos colonies (avant entretien) ;
- la **puissance des mégastructures** qui boivent l'énergie d'un astre, par étape achevée, multipliée par la couleur de l'étoile pour l'Essaim et la Sphère. Elle compte qu'on la verse au trésor ou non : une Sphère que recouvre un Cerveau Matriochka compte toujours ;
- les **mondes forgés ou démantelés**, si le pilier des planètes artificielles est en jeu.

{{kd_capture}}

### L'indice et ses verrous

Entre deux ancres, la décimale suit une échelle **logarithmique** : doubler sa puissance fait toujours gagner à peu près la même chose. Les ancres suivent le **rythme** choisi.

{{kd_echelle}}

Un type entier ne se franchit qu'avec son **verrou**. Sans lui, l'indice plafonne à x,99, quelle que soit votre puissance. Sans mégastructures en jeu, il plafonne donc à 1,99. Chaque type franchi donne du **Rayonnement**, et la galaxie entière apprend qui l'a franchi le premier.

### Les prérogatives

À chaque **demi-palier** (1,00 ; 1,50 ; 2,00 ; 2,50 ; 3,00), vous choisissez **une prérogative parmi trois**, une fois pour toutes, dans l'onglet L'Échelle. Si l'indice retombe sous ce palier, la prérogative **dort** jusqu'à ce que vous y remontiez.

{{kd_prerogatives}}

Les **actions** demandent leur prérogative éveillée : le **Voile stellaire** se tire depuis l'onglet L'Échelle ; l'**Allumeur d'étoiles** propose les naines rouges et blanches des systèmes que vous tenez. Un système perdu pendant le chantier fait perdre l'étoile.

### Le rattrapage : l'Émulation

Quand un empire franchit le premier un type, ceux qui sont encore en dessous se piquent au jeu : les technologies et les étapes de mégastructures qui mènent à ce verrou leur coûtent **25 % de moins**, puis 10 % de plus par empire déjà passé (55 % au plus), jusqu'à ce qu'ils le franchissent à leur tour. Type I : la Fusion compacte. Type II : l'Essaim de Dyson, la Méga-ingénierie et les Étoiles captives, et les étapes de l'Essaim et de la Sphère. Type III : la Méga-ingénierie avancée et les étapes des grandes mégastructures.

### La chaleur trahit les puissants

Toute énergie captée finit en chaleur, et la chaleur se voit de loin. Votre **signature thermique** vaut votre indice. À **1,50**, votre capitale et vos mégastructures sont connues de tous les empires ; à **2,50**, tous vos systèmes peuplés. Les **crises** visent d'abord la signature la plus forte, à distance comparable (un type III attire une crise d'un saut et demi plus loin qu'un empire sans chaleur).

- La **Sobriété thermique** (onglet L'Échelle) baisse la signature de 0,50, au prix de 15 % de puissance captée.
- Le **Voile stellaire** l'éteint 120 jours, une fois par an.
- **Techniquement immortels** fait passer les crises chez les autres d'abord.

### Âge sombre et Âge héroïque

Retomber d'au moins un type sous le meilleur que vous ayez atteint ouvre un **Âge sombre** : stabilité −2, mais les réparations et le relèvement des mégastructures coûtent moitié moins (on ressort les vieux plans). Remonter à son meilleur type ouvre un **Âge héroïque** : une prérogative de plus, au choix parmi celles des paliers atteints.

### Le rang parmi les empires

Un empire d'au moins un type au-dessus du vôtre change votre regard sur lui : **révérence** (+8 d'opinion) si vous êtes en paix ou alliés, **crainte** sinon (−8 par type d'écart), ce qui pousse les empires faibles à se méfier du plus fort. Les prérogatives **Prestige de la puissance** et **Phare de la galaxie** ajoutent de l'estime.

### L'IA

L'IA choisit ses prérogatives selon un ordre de préférence, proclame la Sobriété quand une crise est en jeu et qu'elle brille à plus de 1,50, tire le Voile dès qu'il est prêt en temps de guerre et rallume la première étoile possible.

### Hauts faits

**Civilisation stellaire** et **Civilisation galactique** (chapitre 38) se lisent désormais sur l'échelle : ils demandent le type II et le type III.
