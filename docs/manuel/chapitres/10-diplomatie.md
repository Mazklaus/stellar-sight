---
titre: La diplomatie
numero: 8
image: MJ-12
epigraphe: Un traité est une guerre que l'on a décidé de remettre à plus tard. Les bons traités la remettent à très tard.
signature: Ambassadrice Séverine d'Orvanne
---
Les empires qui se rencontrent entrent en **guerre froide** : pas encore de combat, mais chacun peut déclarer la guerre. Tout le reste se négocie dans l'écran Diplomatie ([[F4]]) : votre empire au centre d'un anneau, les autres tout autour, chaque secteur coloré par statut (rouge la guerre, ambre la guerre froide, bleu la paix, cyan l'alliance).

::: capture docs/apercu-diplomatie.png|L'écran Diplomatie
:::

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
