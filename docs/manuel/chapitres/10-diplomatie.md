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
| Migration | Avec la paix et les peuples mêlés : les habitants circulent entre les deux empires, chacun colonise avec l'espèce de l'autre ; un accord commercial double le flux |

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

### Fin des guerres

Avec l'option **Vassaux** (active par défaut), une guerre ne finit plus seulement par la paix blanche.

**La paix à conditions.** Après 60 jours de guerre, le camp qui mène propose ses conditions depuis l'écran Diplomatie, en cochant ce qu'il exige. Chaque condition a un **prix en points de score de guerre** ; une IA vaincue accepte si le prix ne dépasse pas votre score, un joueur répond lui-même.

| Condition | Prix | Effet |
| --- | --- | --- |
| Céder un système | 15 + 3 par population | Le système passe au vainqueur (trois au plus, jamais la capitale) |
| Tribut | 30 | 20 % du revenu net en matériaux et en énergie pendant cinq ans |
| Réparations | 20 | 25 % des réserves de matériaux, d'énergie et d'influence, tout de suite |
| Rompre ses alliances | 15 | Le vaincu quitte ses alliances |
| Libérer ses sujets | 15 par sujet | Ses sujets redeviennent libres |
| Devenir sujet | 40 + 10 par système | Le vaincu devient votre sujet, au préréglage choisi |

**La reddition.** Un empire qui a 100 points de score contre lui, ou qui a perdu sa capitale, peut **se rendre** : il devient le **vassal** de son vainqueur, la guerre cesse et son empire survit. Une IA à bout (deux systèmes ou moins) le fait plutôt que de disparaître. On ne se rend pas à l'Essaim : il ne signe rien.

**La protection.** Un empire faible (moins de 40 % de la puissance de l'autre) peut **demander sa protection** : il devient son **protégé**.

Le **score de guerre** (chapitre 7) compte les vaisseaux détruits et les systèmes pris ; l'IA le pèse aussi avant d'accepter une paix blanche.

::: capture docs/apercu-vassaux.png|Paix à conditions : chaque case a son prix, le total se compare au score
:::

**Avec les buts de guerre.** L'option Buts de guerre (chapitre « La guerre ») change trois choses :

- Le score est un **pourcentage**, et les prix ci-dessus se lisent en points de pourcentage. L'ancienne reddition en vassal disparaît : on **se rend au but** de l'autre (soumission comprise), et la paix à conditions reste ouverte même sans l'option Vassaux.
- Le traité à la carte s'enrichit de clauses, chacune justifiée par certains buts. Une clause **injustifiée** par le but annoncé coûte le **double**, et le vaincu s'en souvient (-15 pendant dix ans).
- Chaque paix s'inscrit au **registre des traités** (colonne de gauche de l'écran Diplomatie), avec ses clauses et leur échéance ; une clause violée y est marquée, et donne le motif Représailles.

| Clause | Prix | Justifiée par | Effet |
| --- | --- | --- | --- |
| Céder des systèmes, devenir sujet | Comme plus haut | Conquête, soumission | Comme plus haut |
| Tribut, réparations | Comme plus haut | Rançon | Comme plus haut |
| Rompre ses alliances / libérer ses sujets | Comme plus haut | Démantèlement / libération | Comme plus haut |
| Zone démilitarisée | 15 | Humiliation, conquête | Ses systèmes à 2 sauts des vôtres interdits à ses flottes de guerre pendant 5 ans (une flotte armée qui s'y arrête viole le traité) |
| Limite de flotte | 25 | Humiliation, démantèlement | Pendant 10 ans, plus de vaisseau de guerre tant que sa flotte dépasse la moitié de la vôtre |
| Passage imposé | 10 | Conquête, libération | Cartes ouvertes à vos flottes pendant 5 ans (consigné ; les frontières viendront plus tard) |
| Rendre héros et reliques | 10 | Humiliation, rançon, libération | Vos héros prisonniers rentrent ; une de ses reliques est à vous |
| Conversion | 30 | Soumission, humiliation, et toute guerre sainte | Il adopte votre foi d'État |
| Changement de régime | 35 | Soumission, démantèlement | Votre courant prend la tête de son gouvernement, jusqu'aux prochaines élections |
| Transfert d'un sujet | 30 | Soumission, démantèlement, libération | Son sujet le plus puissant devient le vôtre |
| Sortie du Koinon | 20 | Démantèlement | Il quitte son Koinon |
| Libération d'un peuple | 15 | Libération, humiliation | Votre peuple, chez lui, reçoit le meilleur statut possible |

Un **orateur** au conseil du vainqueur rabat le prix total de 5 % par niveau (30 % au plus).

::: capture docs/apercu-registre-traites.png|Le registre des traités : chaque clause et son échéance
:::

Un sujet garde ses colonies et ses flottes ; tout ce qui règle sa vie (clauses, tribut, loyauté, intégration, indépendance) fait l'objet du chapitre 10.

::: conseil
Un vaincu à 100 points de score contre lui n'a plus rien à perdre en se rendant. Si vous menez, proposez vos conditions avant : un vassal vivant vous rapporte un tribut, un empire mort ne vous rapporte que ses ruines.
:::

### Au-delà des traités

La diplomatie a ses grandes institutions, qui ont chacune leur chapitre :

| Chapitre | Ce qu'on y trouve |
| --- | --- |
| 9 · Le commerce | Paliers commerciaux, routes, luxes et stratégiques, marché, accords de recherche |
| 10 · Suzerains et sujets | Le lien de sujet, ses clauses, la loyauté, l'intégration et l'indépendance |
| 11 · Le Koinon | Les ligues d'empires : synode, Stratège, lois, cohésion, flotte fédérale |
| 12 · L'Amphictyonie | L'assemblée galactique : voix, résolutions, Nomos, Haute Voûte, pleins pouvoirs, Chancelier des étoiles |

::: chronique Minutes de la conférence de Hale|Greffier de la Concorde de Vael
« La délégation du Chœur a entonné son hymne à l'ouverture des débats. La délégation d'Ossarane a demandé combien de couplets il comptait. La délégation du Chœur a répondu : “Tous.” La séance a été suspendue jusqu'au lendemain. »
:::
