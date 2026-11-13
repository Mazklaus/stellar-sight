---
titre: La diplomatie
numero: 8
image: MJ-12
epigraphe: Un traité est une guerre que l'on a décidé de remettre à plus tard. Les bons traités la remettent à très tard.
signature: Ambassadrice Séverine d'Orvanne
---
Les empires qui se rencontrent entrent en **guerre froide** : pas encore de combat, mais chacun peut déclarer la guerre. Tout le reste se négocie dans l'écran Diplomatie ([[F4]]) : votre empire au centre d'un anneau, les autres tout autour, chaque secteur coloré par statut (rouge la guerre, ambre la guerre froide, bleu la paix, cyan l'alliance).

### Statuts et traités

| Statut ou traité | Effet |
| --- | --- |
| Guerre froide | Statut de départ : pas de combat, la guerre reste possible |
| Guerre | Combats, sièges, invasions. Un score de guerre compte vaisseaux détruits et systèmes pris |
| Paix | Aucune attaque. Une **trêve d'un an** suit la signature. +1 influence par mois |
| Alliance | Après six mois de paix. Guerres, cartes et vision partagées. +2 influence par mois |
| Commerce | Avec la paix, en trois paliers : voir plus bas |
| Échange de cartes | Chacun reçoit les systèmes explorés par l'autre ; une fois tous les deux ans |

Après la trêve, on peut **dénoncer** la paix et revenir à la guerre froide. On peut aussi attaquer sans prévenir : vous voilà **parjure** aux yeux de toute la galaxie, et elle s'en souviendra longtemps.

Une IA répond tout de suite ; un joueur humain a 30 jours pour répondre. Un refus impose un délai avant de reproposer.

::: capture docs/apercu-diplomatie.png|L'écran Diplomatie
:::

### L'opinion

Chaque empire pense quelque chose de chacun des autres, de -100 à 100, et l'infobulle en donne toutes les raisons :

- le **choc des tons** : deux registres qui s'opposent se détestent d'instinct (le grimdark face au space opera héroïque, -15) ;
- les **credos** et les **gouvernements** (foi contre raison, féodalité contre république…), l'archétype (une ruche inspire l'horreur) ;
- les **frontières communes** (-3 par système voisin, jusqu'à -15) ;
- le statut, la **confiance** qui monte de 2 par mois sous traité, l'**ennemi commun** (+15) ;
- l'**histoire commune** : des souvenirs qui s'effacent avec les années, du traité rompu (-50) à l'allié venu à la rescousse (+15).

Avant de proposer, le bouton du traité affiche le verdict de l'IA (« Accepterait (+13) ») et son détail : opinion, lassitude de la guerre, rapport de forces, tempérament.

### Le commerce

Le commerce se signe palier par palier, toujours en temps de paix, et chacun se propose dans l'écran Diplomatie comme un traité :

| Palier | Conditions | Effet |
| --- | --- | --- |
| Comptoirs ouverts | La paix | Les routes circulent, la douane en prend 20 % ; +3 d'opinion |
| Accord commercial | Des comptoirs ouverts | Tarif de 10 %, +1 influence par mois ; +5 d'opinion |
| Libre-échange | Deux ans d'accord, opinion d'au moins 20 de part et d'autre | Ni douane ni tarif, routes +25 %, +2 influence par mois ; +8 d'opinion |

Chaque mois, chaque empire envoie ses **routes commerciales** vers ses partenaires, les plus rentables d'abord. Une route part de votre capitale ou d'un **comptoir** et suit les couloirs. Elle vaut d'autant plus qu'elle est longue et que les deux systèmes qu'elle relie sont peuplés, jusqu'à 24 énergie. Les **deux bouts** touchent la même somme, chacun moins le tarif du palier : vos partenaires vous enrichissent avec leurs propres routes autant que vous avec les vôtres.

Le nombre de routes est votre **capacité** : une au départ, une de plus par comptoir (un par système), une avec les Bourses et une avec les Compagnies marchandes. Une place libre sert une **route intérieure** : de la capitale vers une colonie de moins de 6 habitants, elle apporte 2 nourriture et 2 matériaux par mois, et la colonie grandit plus vite. Dans l'écran Commerce ([[C]]), vous pouvez réserver des places pour ces routes, qui passent alors avant les partenaires.

Une route a ses dangers :

- une **flotte armée hostile** sur son chemin (en guerre avec l'un des deux bouts, pirates, faune) la **bloque** tant qu'elle y reste ;
- les systèmes traversés hors de tout territoire et sans flotte pour les garder attirent les **pirates** : le risque monte chaque mois, plus vite près d'un repaire, et retombe dès qu'une flotte ou une patrouille y passe. Une route perd le risque de son système le plus exposé, jusqu'à 25 % de sa valeur (50 % près d'un repaire payé contre vous). Un système laissé cinq ans sans garde voit s'installer un nouveau repaire ;
- un **embargo** coupe tout commerce avec la cible et interdit d'en signer. Vos alliés IA qui ne l'aiment pas s'y joignent. Rompre le commerce laisse un mauvais souvenir, double si les routes étaient riches.

Le commerce rapproche : chaque année de routes ininterrompues ajoute 2 d'opinion, jusqu'à cinq ans. La **lentille du commerce** ([[G]]) montre vos routes sur la carte, à la couleur de leur palier, en rouge si elles sont bloquées, avec le risque pirate des systèmes traversés.

### Luxes, stratégiques et marché

Certaines planètes portent un **gisement** : un luxe ou une ressource stratégique, visible dans la fiche du système. Une colonie ou un avant-poste établi l'exploite. La quantité de gisements se règle dans la nouvelle partie (aucuns, rares, normaux, abondants).

Les **luxes** comptent par variété : le premier exemplaire de chaque luxe donne de la stabilité dans tous vos systèmes, selon son palier, et un petit effet. Chaque gisement de plus du même luxe ne rapporte que 2 énergie par mois.

{{luxes}}

Un luxe que vous n'avez pas s'obtient par **licence** : le vendeur garde son gisement et vous en accorde l'usage, contre un loyer mensuel (le prix du palier, plus 1 par tranche de quatre sauts entre les capitales). Il faut un palier de commerce entre vous. Chaque licence ajoute aussi 2 à la valeur de vos routes avec le vendeur. Vous pouvez fermer vos licences à tout le monde. L'empire qui exploite au moins 60 % des gisements d'un luxe (et au moins deux) en a le **monopole** : 5 à 25 énergie par mois selon sa part, des licences 50 % plus chères, et la réputation d'accapareur chez ceux qui le connaissent.

Les **stratégiques** s'ouvrent avec les ères : un gisement ne produit rien avant que vous ayez atteint son ère, puis 1 unité par mois. Les pièces d'artillerie, les hangars et les modules titanesques en consomment au Chantier, et la Bourse des Mille Soleils demande du ferronoir. Sans gisements en jeu, ces coûts disparaissent.

{{strategiques}}

Le **marché** (onglet Marché de l'écran Commerce) échange matériaux, nourriture, cristaux et stratégiques contre de l'énergie. Les frais sont de 30 %, moins ce que retirent vos technologies, vos lois et vos talents. Chaque achat fait monter le prix et chaque vente le fait baisser, de 0,4 % par tranche de dix unités ; il revient à moitié vers la normale chaque mois. Une **commande mensuelle** achète ou vend la même quantité tous les mois. Le marché peut être coupé dans la nouvelle partie.

Entre empires, un **accord** échange ce que vous voulez : énergie, ressources, stratégiques, en une fois ou chaque mois pendant un à dix ans. L'IA répond aussitôt selon les prix du marché, ses besoins et son opinion de vous ; une proposition qui vous est faite attend votre réponse dans l'onglet Marché. Un accord rompu ou impayé laisse le souvenir d'un contrat rompu.

Les prix **vivent** avec la galaxie. Chaque guerre en cours renchérit les stratégiques de 6 % (jusqu'à 40 %) ; une galaxie entièrement en paix paie les licences de luxe 25 % plus cher ; un fléau errant fait monter nourriture et matériaux ; un empire qui tient 60 % des gisements d'un stratégique le fait grimper de 25 %. Une fois l'an, il peut survenir un **krach** ou une **envolée** sur une ressource, qui s'efface en six mois. Dans l'onglet Marché, la flèche à côté de chaque prix en donne les raisons.

La **Bourse galactique** est une merveille unique (Bourses interstellaires, ère III). Le premier empire qui la bâtit fonde le **marché commun** : dès lors, tout le monde partage les mêmes prix, et l'achat de l'un renchérit pour tous. L'hôte paie 10 % de frais en moins et gagne jusqu'à 8 influence par mois sur les échanges des autres. Tous les six mois, la Bourse met en vente trois **vaisseaux d'occasion** d'une même classe, même sans la technologie, remis en état à 70 % et livrés à la capitale, pour l'hôte et ceux qui commercent avec lui. L'hôte touche un cinquième du prix. Conquérir la planète, c'est prendre la Bourse.

Un **port franc** pirate que vous connaissez tient un **marché noir** : des stratégiques sans traité ni marché, au double du prix, trente unités par mois au plus. Ceux qui vous connaissent s'en souviennent un temps.

Le **Savoir** circule aussi, mais on n'échange jamais une technologie toute faite (onglet Savoir de l'écran Commerce) :

- un **accord de recherche** se signe entre deux empires en paix depuis un an. Chacun verse de l'énergie (80, plus 60 par ère du plus avancé). Trois ans plus tard, chacun reçoit un bond de Savoir sur sa recherche en cours (150, plus 150 par ère). Une guerre entre eux l'annule, et l'énergie est perdue. Deux accords à la fois au plus ;
- une **licence de technologie** s'achète à un partenaire commercial. Il doit avoir trouvé la technologie lui-même : ni technologie de peuple, ni méga-vaisseau, une ère d'avance au plus. Vous recevez 60 % de son coût en Savoir et payez deux énergie par point de Savoir. Une technologie obtenue ainsi ne se revend pas ;
- la **diffusion** : chaque route active vers un empire qui connaît plus de technologies que vous rapporte 1 Savoir par technologie d'écart, au plus 5 par route et 12 en tout.

::: conseil
Les routes les plus longues rapportent le plus, mais ce sont aussi celles qui traversent le plus de vide. Une corvette en patrouille sur le bon carrefour vaut parfois mieux qu'un comptoir de plus.
:::

::: chronique Minutes de la conférence de Hale|Greffier de la Concorde de Vael
« La délégation du Chœur a entonné son hymne à l'ouverture des débats. La délégation d'Ossarane a demandé combien de couplets il comptait. La délégation du Chœur a répondu : “Tous.” La séance a été suspendue jusqu'au lendemain. »
:::

### Les talents diplomatiques

| Talent | Qui | Effet |
| --- | --- | --- |
| L'héritier | Féodalité (Ossarane) | L'héritier a une loyauté de 0 à 100. Les rivaux peuvent la **soudoyer** ; la dynastie offre un **banquet des lignées** pour la regagner. À 0, il trahit et livre son fief le plus lointain |
| Les Veilleurs du Seuil | République (Vael) | **Arbitrer** une guerre de plus de deux mois entre deux empires qui vous respectent : la paix est imposée, avec sa trêve |
| Pas de paix avec les hérétiques | Théocratie de foi (Chœur) | Déclarer la guerre à un autre credo : +10 ferveur. Chaque paix avec un autre credo coûte 1 ferveur par mois |
| Flottes à louer | Syndicat (Brisecomète) | Louer ses flottes à un empire en guerre, payées chaque mois en énergie |
| Faim sans traité | Ruche de survie (Kh'thari) | Ne signe rien, ne reçoit personne |

::: marge
Le banquet des lignées coûte 20 influence et 3 cristaux. L'héritier qui vous trahit en coûte infiniment plus. Faites le calcul, ou mieux : faites servir le vin.
:::

::: conseil
Une alliance entraîne ses membres dans les guerres l'un de l'autre. Avant de signer, regardez les cordes rouges qui partent de votre futur allié sur l'anneau : elles deviennent les vôtres.
:::
