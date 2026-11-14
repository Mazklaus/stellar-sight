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

Chaque peuple commerce à sa façon. Ces **talents commerciaux** suivent les couches d'espèce, et les peuples que vous créez en héritent aussi (onglet Ressources) :

| Couche | Talent |
| --- | --- |
| Credo Profit | Frais du marché -10 points, licences de luxe vendues +25 % |
| Credo Foi | Chaque route vers un empire du même credo : +2 influence par mois |
| Credo Survie | Marché noir au prix de base, sans mauvaise réputation |
| Gouvernement Syndicat | Une route commerciale de plus |
| Gouvernement Horde | Une flotte armée qui bloque une route ennemie en touche la moitié de la valeur |
| Gouvernement Ruche | Routes vers les autres empires -50 %, routes intérieures doublées |

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

### Fin des guerres et sujets

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

::: capture docs/apercu-vassaux.png|Paix à conditions : chaque case a son prix, le total se compare au score
:::

**Le lien de sujet.** Il n'y a qu'un lien, réglé par **clauses** ; trois préréglages en donnent des versions toutes faites, et le suzerain peut tout ajuster.

| Clause | Options |
| --- | --- |
| Diplomatie | **Aucune** (aucun traité, aucune guerre), **Vote lié** (traités, mais guerre seulement aux ennemis du suzerain), **Libre** |
| Guerres suivies | **Aucune**, **Défense** (quand on attaque le suzerain), **Toutes** (même celles qu'il déclare) |
| Expansion | **Interdite**, **Dîme** (la moitié du coût en influence de chaque fondation part au suzerain), **Libre** |
| Intégration | **Permise** (après dix ans), **Interdite** |
| Tribut | 0, 10, 20 ou 30 % du revenu net, pour chaque famille : matériaux, énergie, influence, Savoir |

| Préréglage | Clauses |
| --- | --- |
| Vassal | Vote lié, toutes les guerres, dîme, 10 % des matériaux et de l'énergie |
| Tributaire | Libre de sa diplomatie et de ses guerres, mais 20 % des matériaux et de l'énergie |
| Protectorat | Vote lié, défense, dîme, intégration permise ; +50 % de Savoir tant qu'il connaît moins de technologies que son protecteur ; pas d'accord de recherche ; 1 influence par mois au protecteur |

Le suzerain défend toujours son sujet. Ni l'un ni l'autre ne peut déclarer la guerre à l'autre. Quand le suzerain signe la paix, ses sujets la signent aussi. Un sujet avance vers la conquête et la domination avec son suzerain, mais ne les gagne pas pour lui-même.

**La loyauté.** Chaque sujet a une loyauté de -100 à +100. Chaque clause la touche deux fois : tout de suite, puis chaque mois (l'infobulle du menu le dit : « Toutes (-10, -0,5/mois) »). S'y ajoutent l'habitude du lien (+1 par mois), l'opinion du sujet, un credo commun, la puissance du suzerain (un suzerain fort rassure, un plus faible que son sujet inquiète), le **patronage divisé** (-0,5 par mois pour chaque autre sujet, jusqu'à -1,5) et un suzerain qui perd une guerre. Un sujet **déloyal** (sous zéro) ne suit plus que les guerres défensives.

**Renégocier.** **Assouplir** est gratuit et possible à tout moment. **Durcir** n'est possible qu'un an après le lien puis tous les cinq ans, coûte 30 influence plus 3 par point de loyauté perdu, et un sujet sous -20 refuse de discuter.

**Intégrer.** Après dix ans, un sujet loyal dont les clauses le permettent peut être **intégré** : un an à 5 influence par mois, puis ses colonies et ses flottes deviennent les vôtres et son empire disparaît. Un joueur intégré a perdu.

**L'indépendance.** Le suzerain peut **libérer** son sujet : dix ans de trêve suivent, et beaucoup de gratitude. Le sujet peut **exiger son indépendance** : le suzerain cède, ou c'est la guerre de libération. Un tiers peut **soutenir l'indépendance** d'un sujet (20 influence) : sa puissance compte dans le rapport de forces, et il entre en guerre aux côtés du sujet si le suzerain refuse. Le suzerain le saura.

**L'allégeance secrète.** Un sujet peut jurer en secret fidélité à un rival de son suzerain. Si ce rival entre en guerre contre le suzerain, le sujet rompt son lien et passe dans son camp.

::: conseil
Un vaincu à 100 points de score contre lui n'a plus rien à perdre en se rendant. Si vous menez, proposez vos conditions avant : un vassal vivant vous rapporte un tribut, un empire mort ne vous rapporte que ses ruines.
:::

### L'Amphictyonie

Avec l'option **Amphictyonie** (active par défaut), la galaxie finit par se donner une assemblée : la **Grande Amphictyonie Galactique**, que tout le monde appelle l'Amphictyonie, et dont les membres sont les **amphictyons**. Elle ne s'ouvre pas au premier jour. Quand un empire a rencontré au moins **70 %** des autres, et pas avant l'an 8, son acte de fondation circule : il faut **trois signatures**, données dans les deux ans. Les signataires y siègent d'office. Une ruche sans diplomatie ne siège jamais, mais les résolutions et la charte la concernent quand même.

Les autres empires peuvent **adhérer** plus tard (60 influence) s'ils connaissent un membre. **Partir** coûte 40 influence plus 4 par système, et interdit le retour pendant dix ans. Seuls les membres votent et profitent des résolutions ; seuls eux accèdent au **marché commun** de la Bourse galactique. En échange, ils sont liés par la loi commune, le **Nomos**.

L'écran Amphictyonie ([[M]]) montre la séance en cours, la file des propositions, un pupitre pour proposer, les résolutions en vigueur, le Nomos et les amphictyons. Un empire que vous n'avez jamais rencontré y apparaît comme « monde inconnu ».

::: capture docs/apercu-amphictyonie.png|L'écran Amphictyonie : la séance, l'hémicycle du dernier vote, la file
:::

**Les voix.** Chaque mois, l'assemblée pèse ses membres sur 1000 voix : population pondérée par la stabilité (40 %), économie (25 %), technologies connues (20 %), puissance de flotte (15 %). Une proposition adoptée donne à son auteur +5 % de voix pendant six ans, une proposition rejetée -5 %.

**Les séances.** Chaque membre peut déposer une proposition (une à la fois). Elle coûte de l'influence selon son niveau : 40 pour un premier niveau, 70 pour un deuxième, 40 pour une abrogation, 25 pour une sanction, 50 pour un bannissement. Les autres membres la **soutiennent** ou non. Tous les **deux ans**, la plus soutenue passe en séance ; la première séance s'ouvre un an après la fondation. Le vote dure **six mois**, chacun peut changer d'avis jusqu'à la clôture, et il reste secret jusque-là. La proposition passe si les voix pour dépassent les voix contre ; l'abstention ne compte pas. Chaque séance a un **président**, le membre le plus lourd qui n'a pas encore présidé : s'il a une proposition dans la file, elle passe en premier et sans frais, et il tranche les égalités.

Pendant une séance, on peut **acheter des voix** pour ce seul vote, dans le camp de son vote : chaque tranche ajoute 3 % du total, coûte 15 influence la première fois puis 10 de plus à chaque fois (cinq tranches au plus). Si votre camp perd, la moitié est remboursée. Voter pour la proposition d'un empire lui plaît, voter contre le froisse (±8 d'opinion, jusqu'à trois fois).

::: marge
La présidence n'a presque aucun pouvoir. C'est précisément pour cela que tout le monde la veut : le fauteuil est magnifique.
:::

**Les résolutions.** Elles vont par familles de deux voies opposées, en trois niveaux à voter dans l'ordre (le troisième coûte 100 influence et prolonge les effets du deuxième). Un pas vers la voie opposée abroge d'abord le dernier niveau en vigueur. Une résolution reste en vigueur jusqu'à son abrogation, et ne vaut que pour les membres.

| Famille | Voie A | Voie B |
| --- | --- | --- |
| Commerce | **Routes franches**, puis Grand-Route des Mondes : routes +10 % puis +20 %, frais du marché réduits | **Préférence impériale**, puis Murs de douane : matériaux +4 % puis +8 %, routes -10 % puis -20 % |
| Savoir | **Savoir sans frontières**, puis Bibliothèque des Étoiles : Savoir +5 % puis +10 % | **Brevets galactiques** : vol de technologie démasqué interdit ; puis Office des brevets, énergie +5 % |
| Guerre | **Conventions de guerre** : garnisons +10 %, rompre un traité pour attaquer un membre interdit ; puis Paix armée : toute guerre d'agression contre un membre interdite | **Défense mutuelle** : défense des mondes natals ; un membre attaqué sans motif ouvre à tous un droit de guerre contre l'agresseur pendant cinq ans ; puis Bouclier commun |
| Foi (avec les religions) | **Liberté de culte**, puis Chemins des pèlerins : pression des fois +15 % puis +30 % | **Foi galactique** : la foi la plus suivie chez les membres est proclamée foi galactique ; les membres qui l'ont pour foi d'État gagnent des voix et du rayonnement |
| Peuples | **Droit d'asile**, puis Terre d'accueil : croissance et un peu de stabilité | **Frontières closes**, puis Rideau stellaire : stabilité, mais moins de croissance |
| Ombres | **Charte du renseignement** : un espion pris chez un membre est une infraction ; puis Bureau des chiffres : découverte +15 % entre membres | **Concurrence des ombres**, puis Marché des secrets : opérations -15 % puis -30 % |
| Faune et périls (avec créatures ou pirates) | **Sanctuaires** : détruire un nid est une infraction ; stabilité | **Primes et patrouilles** : chaque repaire démantelé ou nid détruit rapporte 15 puis 30 influence |

**Le Nomos et les hors-la-loi.** Ce qu'une résolution interdit devient loi pour les membres. Celui qui l'enfreint est déclaré **hors-la-loi** pour cinq ans : tous les membres s'en souviennent (-30 d'opinion), et l'assemblée peut voter contre lui des **sanctions** en trois degrés (économiques : routes -20, -35 puis -50 %, et exclusion du marché commun au troisième degré ; scientifiques : Savoir -10 à -30 % ; militaires : entretien et chantiers +10 à +30 %), puis le **bannir** pour dix ans. Les sanctions tombent avec la fin de la peine.

La première ligne du Nomos tient dès la fondation : la **charte des atrocités**. Exterminer une population, membre ou non, rend hors-la-loi avec des sanctions économiques et scientifiques automatiques. À la seconde atrocité, chaque amphictyon peut déclarer la guerre au coupable **sans être parjure**, même s'il avait signé la paix avec lui.

::: conseil
Une résolution ne s'impose qu'aux membres : un empire belliqueux a parfois intérêt à rester dehors. Mais dehors, il n'a ni voix, ni marché commun, et s'il frappe un membre sous la Défense mutuelle, c'est toute l'assemblée qui peut lui répondre.
:::

**La Haute Voûte et l'Arbitre des étoiles.** Après dix ans d'existence, l'assemblée peut voter la création de la **Haute Voûte**, son haut conseil (100 influence). Ses **trois sièges** vont aux plus fortes voix de base, et sont redistribués tous les dix ans ; un hors-la-loi n'y siège pas. Une résolution peut porter le conseil de un à cinq sièges (60 influence). Chaque conseiller gagne **+20 % de voix** et trois pouvoirs :

- le **veto**, une fois par décennie : la proposition au vote tombe sur-le-champ, quelles que soient les voix ;
- l'**urgence**, une fois par décennie : une proposition de la file passe tout de suite en séance ;
- la **dénonciation** (30 influence, une fois tous les cinq ans) : pendant cinq ans, l'empire dénoncé, membre ou non, est passible de sanctions comme un hors-la-loi. Il s'en souvient (-15 d'opinion).

Un conseiller peut proposer l'élection d'un autre conseiller (ou de lui-même) comme **Arbitre des étoiles** (80 influence). Le mandat dure quinze ans et donne **+30 % de voix** ; il se prolonge par une résolution (60 influence), et une **motion de défiance** (50 influence) y met fin. Une fois tous les deux ans, l'Arbitre peut **geler** une proposition de la file pendant deux ans, **clore** un vote plus tôt, ou **imposer une trêve** à deux membres en guerre (40 influence).

**Faveurs, observateurs et ambassadeurs.** Voter pour la proposition d'un autre membre, quand elle passe, c'est une **faveur** qu'il vous doit (dix au plus par débiteur). Secourir un membre en détresse en rapporte aussi. Pendant un vote, **appeler une faveur** fait voter 10 % des voix du débiteur dans votre camp, pour ce vote seulement.

Un empire qui ne veut pas, ou ne peut pas, adhérer peut prendre place au **banc des observateurs** s'il connaît un membre. Il ne vote pas et ne profite pas des résolutions, mais il peut appeler à l'aide et, s'il est victime d'une crise, convoquer une session extraordinaire.

Un héros peut devenir **ambassadeur** auprès de l'Amphictyonie (nouveau poste, chapitre 11) : +5 % de voix par niveau, +10 % pour un orateur, 30 % au plus.

**Crises, sessions extraordinaires et coalitions.** Certains événements ouvrent une **crise** pendant un an : une capitale prise, une atrocité, une guerre sainte, ou la Moisson de l'Essaim arrivée à mi-course. Un membre, ou la victime elle-même si elle observe, peut alors **convoquer une session extraordinaire** (50 influence). Le vote dure deux mois, et le fautif ne vote pas.

Si elle passe, ceux qui ont voté pour forment avec la victime une **coalition** contre le fautif : ils lui déclarent la guerre sans parjure (sauf trêve en cours), leurs chantiers vont 20 % plus vite, et ils ont cinq ans pour atteindre leur but : lui prendre sa capitale (après une capitale prise) ou la moitié de ses systèmes. Réussite : 60 influence pour chaque coalisé, et des souvenirs de fraternité d'armes. Échec : le fautif gagne 100 influence. Une seule coalition à la fois.

::: capture docs/apercu-amphictyonie-lot2.png|Un conseiller de la Haute Voûte en séance : veto, faveurs à appeler, et une session extraordinaire
:::

::: attention
Voter pour une coalition, c'est entrer en guerre. Regardez votre flotte avant de lever la main.
:::

**Entraide et grands travaux.** Un membre ou un observateur presque à sec (moins de 100 énergie ou matériaux) peut **appeler à l'aide** une fois tous les cinq ans : les membres ont six mois pour lui envoyer 300 de la ressource, par tranches de 50. Chaque tranche vaut une faveur et un bon souvenir (+10 d'opinion).

L'assemblée peut aussi voter un **grand chantier** (60 influence) ; les membres ont cinq ans pour le financer. Achevé, il profite à tous les membres, et les trois plus gros donateurs reçoivent une **médaille** pour toujours : +6 %, +4 % et +2 % de voix.

| Grand chantier | Coût | Effet pour les membres |
| --- | --- | --- |
| Voile des Courants | 1 200 énergie | Flottes +10 % plus rapides |
| Phare des Chantiers | 1 500 matériaux | Chantiers navals 10 % plus rapides |
| Grand Recensement | 1 000 énergie | Croissance +5 %, stabilité +1 |
| Archives des Mondes | 1 200 matériaux | Savoir +5 % |

Les réseaux d'espions ont aussi leurs coups d'assemblée (chapitre 9) : **acheter un délégué** (un quart des voix de la cible change de camp pour le vote en cours), **faire fuiter un dossier** (la proposition de la cible quitte la file) et **monter un scandale** (la cible perd ses bonus de voix et 10 % de voix pendant six ans).

**Les pleins pouvoirs.** Une résolution (90 influence) peut rendre le mandat de l'Arbitre des étoiles **illimité**. Une fois l'Arbitre à vie, lui seul peut proposer qu'on lui donne les **pleins pouvoirs** (150 influence). Si l'assemblée y consent, il devient l'**Impérateur** (+50 % de voix), et chaque autre membre a **90 jours** pour choisir :

- **se soumettre** : il paie un tribut de 3 influence par mois, et entre en guerre aux côtés de la Cour quand on l'attaque ;
- **se soulever** : il quitte l'Amphictyonie (retour interdit pendant dix ans) et entre en guerre contre l'Impérateur et ses vassaux.

Un soumis devient un **sujet** de l'Impérateur, au préréglage verrouillé **Cour impériale** (voir plus haut, « Fin des guerres et sujets ») : clauses imposées et non négociables (vote lié, défense, expansion libre, pas d'intégration), tribut fixé par l'Amphictyonie. On n'en sort pas en exigeant l'indépendance : on se soulève.

Qui ne répond pas s'est soumis. L'**autorité** de l'Impérateur part de 60 sur 100 : chaque mois, +1 par vassal (+3 au plus) et -3 par rebelle encore en guerre contre lui ; +10 pour chaque rebelle abattu. Sous 50, les réseaux d'espions peuvent **saper l'autorité** (-15) ou **allumer la rébellion** d'un vassal. À zéro, la Cour s'effondre : plus d'Impérateur, plus d'Arbitre. Contre un Impérateur, plus de motion de défiance : il faut prendre les armes.

::: marge
Les juristes de l'Amphictyonie ont longtemps débattu du titre. « Empereur » faisait vulgaire, « Président » faisait faible. « Impérateur » a mis tout le monde d'accord : personne ne sait exactement ce que ça veut dire.
:::

**Le Chancelier des étoiles.** Si la victoire diplomatique est en jeu (chapitre 15), l'assemblée élit tous les dix ans, à partir de l'an 30, un **Chancelier des étoiles** entre ses deux plus fortes voix. Le vote dure six mois ; les deux candidats votent pour eux-mêmes, les autres choisissent ou s'abstiennent. L'élu doit réunir **67 % de toutes les voix**, et les abstentions comptent contre lui. L'assemblée doit aussi parler pour la galaxie : au moins quatre membres, et au moins 75 % des empires vivants. Sinon, pas d'élection cette décennie.

Élu, le Chancelier attend 60 jours : le candidat battu peut **s'incliner**, et l'élu gagne la partie avec ses alliés, ou **refuser le verdict**. Alors commence la **Dernière Guerre** : l'élu et tous ceux qui ont voté pour lui déclarent la guerre au refusant. L'élu gagne quand celui-ci perd sa capitale ; si elle tient dix ans, le titre retourne aux archives.

::: conseil
Les 67 % sont durs à atteindre : il faut que presque toute l'assemblée vote pour vous, alors que votre rival vote pour lui-même. Les faveurs, les alliances et un rival plus faible que vous font la différence. Pour bloquer un favori, il suffit souvent de s'abstenir, ou de rester hors de l'assemblée pour qu'elle ne représente plus 75 % de la galaxie.
:::

**L'assemblée et la vie intérieure.** Avec la politique intérieure, siéger pousse chaque mois la **Concorde**. Une résolution adoptée pousse aussi, chez ceux qui l'ont votée, le courant de sa voie : Routes franches et Conventions de guerre la Concorde, Préférence impériale la Forge, Savoir sans frontières l'Académie, Foi galactique l'Autel, Défense mutuelle et Frontières closes le Glaive, Sanctuaires la Sève, et ainsi de suite. Une résolution peut heurter une loi de votre empire : Libre-échange contre Préférence impériale, Protectionnisme contre Routes franches, Hospitalité contre Frontières closes, Préférence native contre Droit d'asile, Inquisition contre Liberté de culte, Tolérance contre Foi galactique. Tant que les deux tiennent, tout l'empire perd 4 de stabilité. La loi **Souveraineté** (chapitre 12) permet, une fois par an, de se soustraire pour un an aux effets et aux interdits d'une famille de résolutions ; les autres membres vous en veulent (-10 d'opinion).

Avec les religions, la foi galactique gagne **1 de zèle par mois** ; une **guerre sainte** réunit d'elle-même une session extraordinaire si aucune ne siège ; et deux théocraties de même foi d'État forment un **Conclave** : voter pareil leur laisse un bon souvenir (+6 d'opinion).

**Les talents d'assemblée.** Chaque peuple a sa manière de siéger. Comme les talents diplomatiques, ils suivent les couches d'espèce : un peuple créé qui a la bonne couche en profite aussi.

| Talent | Couche | Effet |
| --- | --- | --- |
| Landsraad | féodalité (Ossarane) | Chaque lignée unie à la vôtre qui vote comme vous ajoute 25 % de ses voix à votre camp |
| Anathème | credo de foi (Chœur) | Résolutions Foi à moitié prix ; une fois par décennie, frapper d'anathème un empire d'une autre foi d'État (25 influence) : une session extraordinaire s'ouvre contre lui |
| Tribune | république (Vael) | Propositions 25 % moins chères, deux à la fois ; on vous voit volontiers Arbitre |
| Hors du concert | ruche (Kh'thari) | Les sanctions glissent sur la ruche ; mais sa Moisson déclenche une crise à 25, 50 et 75 % |
| Consensus calculé | conscience (Teyl) | Dans les 30 derniers jours d'un vote, vous voyez le vrai décompte, délégués achetés et faveurs compris |
| Droit du plus fort | horde (Ferrocornes) | Votre flotte compte double dans vos voix ; une fois par décennie, un duel de champions (40 influence) contre l'auteur d'une résolution adoptée depuis moins d'un an que vous aviez votée contre : si votre flotte pèse plus que la sienne, elle est abrogée |
| Lobby | syndicat (Brisecomète) | Voix achetées en énergie (4 pour 1 influence) ; 5 énergie de commission sur chaque tranche achetée par un autre |
| Siège voilé | archétype énergétique (Murmurants) | Votre nom n'apparaît pas sur vos propositions, et vos votes ne laissent aucun souvenir |

::: capture docs/apercu-amphictyonie-lot3.png|Pouvoir et légitimité : la Cour impériale attend votre réponse, et l'élection du Chancelier des étoiles est ouverte
:::
