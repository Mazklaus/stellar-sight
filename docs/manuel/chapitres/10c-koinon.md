---
titre: Le Koinon
numero: 11
image: MJ-33
epigraphe: Nous avons élu un Stratège pour cinq ans. Il a passé les deux premières à remercier ses électeurs et les trois suivantes à leur expliquer pourquoi il ne pouvait pas se représenter.
signature: Chronique de la ligue de Hale
---
Avec l'option **Koinon** (active par défaut), des alliés peuvent aller plus loin que l'alliance : fonder une **ligue** de deux à six empires, avec un **synode** qui vote, un **Stratège** élu et des **lois** communes. Le nom vient des ligues de cités grecques ; la ligue achéenne élisait chaque année un stratège, jamais deux fois de suite. Le bloc de la ligue apparaît dans l'écran Diplomatie ([[F4]]).

::: capture docs/apercu-koinon.png|Le bloc de la ligue : rang, cohésion, Stratège, lois, vote en cours, trésor
:::

### Fonder la ligue

Deux alliés depuis au moins **deux ans** fondent le Koinon depuis l'écran Diplomatie (**100 influence** chacun), en choisissant sa **forme**. Une IA accepte si elle vous apprécie (opinion d'au moins 30) ; un joueur répond lui-même. La forme donne un bonus à chaque membre, qui grandit avec le rang de la ligue :

| Forme | Rang I | Rang II | Rang III |
| --- | --- | --- | --- |
| Ligue marchande | Routes entre membres +10 % | +15 %, +1 influence par mois | +20 %, +1 influence |
| Ligue savante | +5 % de Savoir | +10 % | +15 % |
| Ligue martiale | Armes +5 % | +10 % | +15 % |
| Hégémonie | Le Stratège gagne 2 influence par mois | 3, et +1 pour chacun | 4, et +1 pour chacun |
| Communion | +10 d'opinion entre membres | +15, +1 influence | +20, +1 influence |

La **Communion** exige une même foi (ou, sans religions, un même credo) ; elle accepte aussi des empires de fois différentes si tous deux ont la loi **Tolérance**. L'**Hégémonie** est la ligue d'un seul : le plus puissant y préside à vie, les voix du synode se pèsent à la population, et l'on ne part pas sans son accord. Le catalogue des formes est ouvert : d'autres viendront.

### Entrer et voter

**Entrer.** Un empire demande à entrer depuis la relation avec un membre : **membre** de plein droit (50 influence), ou **associé**, gratuit, protégé et soumis aux lois (impôt réduit de moitié) mais sans voix ni bonus de la forme. Le synode vote.

**Le synode.** Chaque membre peut proposer :

| Proposition | Ce qu'elle fait |
| --- | --- |
| Admettre | Un candidat devient membre ou associé |
| Exclure | Un membre est chassé ; il faut les deux tiers des voix |
| Guerre commune | Ceux qui votent pour déclarent ensemble la guerre à un ennemi |
| Loi | Un cran de plus (ou de moins) dans une famille de lois |
| Forme | La ligue change de forme ; l'expérience repart de zéro |

L'élection du Stratège s'ouvre d'elle-même tous les cinq ans. Un vote dure **trente jours** ; les IA votent tout de suite. Une proposition rejetée, comme une demande d'entrée refusée, ne se représente qu'un an plus tard.

### Le Stratège

Le fondateur préside d'abord. Le Stratège est élu pour **cinq ans** et ne peut pas se succéder à lui-même (sauf une république, voir les talents). Il dispose :

- du **trésor commun**, nourri par l'impôt fédéral : jusqu'à 200 énergie par versement, pour secourir un membre (une IA le fait quand un membre tombe sous 100 énergie) ;
- de la **consigne de vote** à l'Amphictyonie : à chaque séance close, chaque membre qui l'a suivie soude la ligue (+2 de cohésion), chaque membre qui a voté contre l'abîme (-2) ;
- de la **flotte fédérale** et des **opérations communes**, plus bas.

### Les lois

Quatre familles, un cran à la fois, chacun exigeant un rang. Chaque cran de plus coûte **10 de cohésion** sur-le-champ.

| Loi | Crans |
| --- | --- |
| Politique commerciale | Aucune, **Routes privilégiées** (le commerce entre membres vaut au moins un accord commercial), **Marché commun** (il vaut le libre-échange, rang II) |
| Impôt fédéral | 0 %, **5 %** du revenu net en énergie au trésor, **10 %** (rang II) ; moitié pour les associés |
| Centralisation | Autonomie, **Union** (cartes partagées chaque mois, +5 d'opinion entre membres, rang II), **Fusion** (en plus, +5 % d'influence pour chacun, rang III) |
| Flotte fédérale | Aucune, **10 %** des matériaux nets de chaque membre à l'arsenal commun, **20 %** (rang II) |

La loi indépendante **Hégémonie** (chapitre 14) fait voter la centralisation un rang plus tôt, sans coût de cohésion, dans une ligue que vous présidez.

::: conseil
Une loi de plus coûte 10 de cohésion. Montez les lois quand la ligue est soudée (à partir de 30 de cohésion, les IA votent pour ; à 40, elles les proposent elles-mêmes), et gardez une guerre commune ou deux pour la ressouder.
:::

### Cohésion et rangs

La **cohésion** va de -100 à +100 et part de 30. Chaque mois, elle bouge de la somme de ces lignes, toutes détaillées dans l'infobulle :

| Chaque mois | Effet |
| --- | --- |
| Vie commune | +3 |
| Membres au-delà de deux | -1 par membre |
| Credos différents | -1 par credo de plus (rien dans une Communion présidée par une théocratie) |
| Gouvernements différents | -1 par gouvernement de plus |
| Centralisation | -1 par cran (rien sous la loi Hégémonie) |
| Délégués au Koinon | +1 ou plus par héros délégué, selon son niveau |
| Guerre commune | +1 tant que deux membres combattent le même ennemi |

| Une fois | Effet |
| --- | --- |
| Une entrée | -10 |
| Un départ | -15 |
| Une proposition rejetée | -5 |
| Un cran de loi | -10 |
| Une guerre gagnée ensemble | +10 |
| Consigne suivie, ou bafouée, à l'Amphictyonie | +2, ou -2, par membre |
| Opération commune réussie, ou ratée | +15, ou -10 |

Tant qu'elle est positive, la ligue gagne chaque mois **1 point d'expérience, plus un dixième de sa cohésion** ; négative, elle en perd 5. Elle passe au **rang II** à 120 points, au **rang III** à 360. Une ligue très soudée (cohésion 100) gagne 11 points par mois : un peu moins d'un an pour le rang II, moins de trois pour le rang III.

### Défense, paix et départ

Les membres ne peuvent pas se faire la guerre. Quand on attaque un membre, les autres entrent en guerre à ses côtés. Entre membres, la frontière ne crée plus de friction.

**Partir.** Hors Hégémonie, on part librement : une trêve de deux ans suit avec chaque membre, qui s'en souviendra. En Hégémonie, il faut l'accord du Stratège ; s'il refuse, c'est la **guerre de sécession**. Une IA songe à partir quand la cohésion tombe sous -50. Une ligue réduite à un membre se dissout ; un membre qui devient sujet en sort.

**Victoire.** Après cinq ans dans la même ligue, les membres avancent ensemble vers la conquête et la domination, comme des alliés. Ce délai de grâce empêche les ligues de la dernière heure.

### La flotte fédérale

Sous la loi Flotte fédérale, chaque membre verse 10 % (rang I) puis 20 % (rang II) de ses matériaux nets dans un **arsenal** commun. Dès qu'il suffit, un vaisseau de guerre sort du chantier de la capitale du Stratège : un croiseur si un membre sait en construire, sinon une frégate, sinon une corvette, quatre par rang au plus. La flotte fédérale ne coûte d'entretien à personne et suit toujours le Stratège en exercice : changer de chef, c'est changer d'amiral. Elle disparaît avec la ligue.

::: capture docs/apercu-koinon-flotte.png|Le Stratège voit la flotte fédérale, son arsenal et l'opération commune en cours
:::

### Les opérations communes

Une fois par décennie, au rang II et en paix, le Stratège peut lancer une **opération commune** (150 énergie du trésor, six mois). Ses chances valent 50 % plus la moitié de la cohésion, entre 15 et 90 %. Réussie, elle ressoude la ligue (+15 de cohésion, +40 d'expérience) et rapporte selon la forme :

| Forme | Opération | Récompense |
| --- | --- | --- |
| Ligue savante | Relevé d'une anomalie | 150 Savoir pour chaque membre |
| Ligue martiale | Grandes manœuvres | Expérience pour les flottes |
| Ligue marchande | Norme de fret | 150 énergie pour chacun |
| Communion | Concile | 30 influence pour chacun |
| Hégémonie | Monument au Stratège | 60 influence, pour lui seul |

Ratée, chacun accuse l'autre (-10 de cohésion).

### Le Koinon et le reste du monde

- **Héros.** Un héros peut devenir **délégué au Koinon** (chapitre 16).
- **Politique.** Fonder une ligue ou y admettre un membre pousse la Concorde.
- **Ombres.** Un réseau d'espions peut **semer la discorde au synode** d'une ligue rivale (-15 de cohésion, chapitre 13).
- **Amphictyonie.** La consigne du Stratège pèse sur les votes de l'assemblée (chapitre 12).

| Talent | Couche | Effet sur le Koinon |
| --- | --- | --- |
| Fédéralisme | république (Vael) | Fonde sans deux ans d'alliance ; peut être réélu Stratège |
| Foi unificatrice | théocratie | Dans une Communion qu'elle préside, les credos différents ne coûtent pas de cohésion |
| Revues partagées | conscience (Teyl) | Dans une Ligue savante, son bonus compte un rang de plus |
| Ni maîtres ni pairs | ruche de survie (Kh'thari) | N'entre dans aucun Koinon |

::: marge
La ligue martiale a voté la guerre commune à l'unanimité. Puis chacun a attendu que l'autre envoie sa flotte en premier. L'ennemi a eu le temps de construire des fortifications, et de nous envoyer ses vœux.
:::
