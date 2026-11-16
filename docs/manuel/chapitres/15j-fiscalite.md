---
titre: Le Trésor
numero: 28
image: MJ-45
epigraphe: L'argent n'a pas d'odeur. La dette, si : elle sent le café froid des réunions de crise et l'encre des créanciers.
signature: Ysolde Marrec, Argentière de la Concorde, discours devant les actionnaires
---
L'énergie est le trésor de l'empire. Avec la fiscalité en jeu, elle ne tombe plus simplement à zéro : vous choisissez combien vous prélevez, l'empire emprunte quand il manque d'argent, et une dette mal tenue mène à la crise, puis à la faillite. L'onglet **Trésor** de l'écran Ordre intérieur ([[F12]]) rassemble l'impôt, le budget, les emprunts et les dépenses de l'État.

Le modèle vient de **Victoria 3** (cinq crans d'impôt, budget, réserve, emprunt automatique, plafond de crédit, abandon des taux qui s'envolent), d'**Europa Universalis IV et V** (prêts de cinq ans, impôt de guerre, inflation, prêteurs privés, faillite), de **Stellaris** (pénuries en quatre paliers avec des approches, défaut), de **Distant Worlds 2** (impôt par monde, corruption qui ronge la collecte), de **Galactic Civilizations IV** (un cran neutre), de **Master of Orion** (grève fiscale) et d'**Endless Space 2** (inflation).

::: capture docs/apercu-fiscalite.png|L'onglet Trésor : le cran d'impôt, le budget du mois, la crise de la dette et les emprunts en cours
:::

### Le réglage

Le bloc Règles de la nouvelle partie propose le réglage **Fiscalité**. **Désactivée** garde l'économie d'avant : sous zéro, la pénurie arrête les chantiers.

{{fisc_modes}}

### L'impôt

Cinq crans, choisis par boutons en haut de l'onglet. **Normal** ne change rien à l'économie : c'est le jeu tel qu'il était. Changer de cran coûte **25 influence** et se fait **une fois par an** au plus.

{{fisc_crans}}

La stabilité vaut pour tous vos systèmes ; l'énergie pour toute la production de l'empire. L'impôt lourd paie la guerre aujourd'hui et ralentit l'empire demain. La horde ne lève pas d'impôt : elle prend (+5 % d'énergie en guerre).

**Fuite fiscale.** Avec la corruption en jeu (chapitre 27), chaque système retient sa part de l'impôt supplémentaire des crans Élevé et Écrasant, en proportion de sa corruption. Le Grand Intendant de la cour réduit la fuite de 10 % par point de Gestion.

**Franchises fiscales.** Un système peut être exempté d'impôt : énergie de ses colonies **-50 %**, stabilité **+10**, intégration administrative plus rapide. Une franchise, plus une par tranche de huit systèmes ; accorder ou retirer coûte **15 influence**. Idéal pour une colonie jeune, conquise ou au bord de la révolte.

### Le budget

Le bloc **Budget du mois** détaille l'énergie : la production et l'impôt des colonies, les mensualités reçues des prêts consentis, puis les dépenses (flottes, armées, bâtiments et colonies, fonctionnaires, intérêts, remboursement du capital, inflation), le solde, le trésor dans douze mois et, en déficit, le nombre de mois avant le plafond de crédit.

**La réserve.** Au-delà de **dix mois** de production brute d'énergie (au moins 1 000), l'excédent du mois ne rentre plus qu'à moitié : on n'entasse plus des milliers d'énergie, on investit, on prête ou on rembourse.

**La solde des équipages.** **Rognée** (entretien des flottes -25 %, dégâts -10 %, et -3 de stabilité en guerre : les équipages mal payés se mutinent), **Normale**, ou **Pleine** (entretien +25 %, dégâts +5 %, le Glaive approuve).

**L'impôt de guerre.** Seulement en guerre : entretien des flottes **-20 %**, stabilité **-3** ; au-delà de trois ans, il nourrit l'inflation. La paix le lève d'elle-même.

**Les traitements des fonctionnaires.** Avec l'administration en jeu, l'effort administratif (Frugal, Normal, Généreux, Grande enquête) se règle aussi depuis le Trésor.

### La dette

**L'emprunt automatique.** Quand le trésor passerait sous zéro, la **Banque intérieure** avance d'office ce qui manque : c'est la **dette courante**. Elle ne porte que des intérêts et se rembourse d'elle-même avec la moitié de l'excédent de chaque mois. La pénurie d'énergie ne frappe plus qu'au plafond.

**Le plafond de crédit.** Environ **douze mois** de production brute d'énergie (au moins 200), +10 % si la stabilité moyenne atteint 60, -25 % sous 30, puis la cote, les technologies, les lois et les talents. On ne le dépasse jamais.

**Les intérêts.** Le taux de base est de **0,5 % par mois** (environ 6 % par an), fixé à la signature. Il ne s'envole jamais près du plafond : pas de spirale de la mort. La cote, le prêteur, une faillite récente, les technologies et les talents le modulent.

**Les emprunts volontaires.** Le bloc **Lever un emprunt** propose de 100 à 1 000 énergie tout de suite, remboursés en **60 mensualités** (capital et intérêts). Chaque emprunt se rembourse d'avance quand on veut.

**Les prêteurs.** La **Banque intérieure** ; une **Grande Maison** qui vous sert (avec la cour : taux -25 %, -40 % pour une maison de marchands, au plus 600 énergie par maison, mais faveur -5 par emprunt en cours) ; un **autre empire** rencontré (une IA prête si elle garde 300 énergie, vous estime et n'est pas effrayée par votre cote ; un suzerain prête moins cher à son vassal). Vous pouvez aussi **prêter** : il vous rembourse avec intérêts, et une IA n'accepte que si elle en a besoin.

**La cote de crédit.** Chaque empire a une note selon sa dette rapportée à son plafond. Elle fixe le taux et le plafond, et les cotes des empires que vous connaissez s'affichent en bas de l'onglet.

{{fisc_cotes}}

**L'inflation.** Chaque tranche de 100 énergie empruntée ajoute 0,2 % d'inflation, la planche à billets 3 %, le Grand Krach 3 %. Elle renchérit d'autant l'entretien en énergie, et baisse de 0,05 % par mois (deux fois plus vite avec la Banque centrale).

**La planche à billets.** **Battre monnaie** donne tout de suite trois mois de production d'énergie (au moins 100), contre **+3 %** d'inflation, une fois par an.

### La crise et la faillite

Quand la dette atteint le plafond avec un solde négatif, ou que le trésor reste à sec, la **crise de la dette** monte de 4 points par mois (6 trésor à sec) et recule de 4 sinon. Tous les 25 points, un palier de plus ; à 100, la faillite. Chaque approche ralentit la montée de 2 points par mois contre ses effets.

{{fisc_paliers}}

**La faillite.** Toutes les dettes sont effacées, puis **dix ans** de malus : coûts des bâtiments et des vaisseaux +25 %, influence -50 %, dégâts -15 %, taux futurs +50 %, stabilité -15 les deux premières années, cote D. Les mercenaires s'en vont, les prêteurs étrangers s'en souviennent, et une maison créancière perd 30 d'humeur. En république, la faillite provoque des élections anticipées.

**Répudier.** Refuser de payer une Maison ou un empire : pas de malus de faillite, mais cote **D** pendant dix ans, le créancier et tous les prêteurs de la galaxie vous en veulent (-50), une Maison passe à -100 de faveur, et un empire créancier gagne pendant cinq ans le motif de guerre **Recouvrement** (buts Rançon ou Humiliation). On ne répudie ni sa propre banque (c'est la faillite) ni le Koinon. L'honneur ne répudie jamais.

### Ponts

- **Révolte fiscale.** L'impôt Écrasant tenu deux ans, ou Élevé avec un système sous 30 de stabilité : une chance par an que le système le moins stable fasse **grève** (production divisée par deux pendant six mois). La carte propose de céder (un cran de moins), de réprimer (stabilité -10 un an) ou d'acheter les meneurs (120 énergie).
- **Doléances.** Avec la politique intérieure, un cran Élevé ou plus tenu un an ouvre **Baisser les impôts** (revenir à Normal en deux ans) ; une dette au-dessus de 75 % du plafond ouvre **Rembourser la dette** (redescendre sous 40 %). Satisfaite : +5 de stabilité un an ; ignorée : -5. Chaque mois, un impôt lourd pousse la Concorde, un impôt léger la Forge, une solde pleine le Glaive.
- **Grandes Maisons.** Une maison qui tient des fiefs peut réclamer une **exemption** (faveur +15, énergie de ses fiefs -25 % pendant dix ans ; refuser coûte -10 de faveur pendant trois ans). Une maison furieuse ne paie plus : énergie de ses fiefs -50 %. En pleine crise, une maison **usurière** propose de racheter votre dette courante, à des conditions de requin (crise -25).
- **Le banquier s'enfuit.** Un empire endetté et mal noté peut voir le gouverneur de sa banque partir avec une part du trésor : le rattraper (20 influence) ou laisser les marchés douter (cote -1 cran deux ans).
- **Grand Krach.** Un empire touché voit ses taux +50 % et son plafond -25 %, et prend 3 % d'inflation ; une fois le Krach passé, la **Banque des Étoiles** relève le plafond de tous de 25 %. L'hôte de la **Bourse galactique** emprunte 20 % moins cher, les membres du marché commun 10 %.
- **Koinon.** Le trésor fédéral renfloue un membre en crise (palier Déficit ou plus) : jusqu'à 300 énergie sans intérêts, remboursables en cinq ans, contre 5 de cohésion, une fois tous les cinq ans.
- **Amphictyonie.** Famille **Finances** : Fonds de stabilité galactique (plafonds +10 % par niveau) ou Interdiction de l'usure (taux -15 %, puis Moratoire sur les dettes qui freine les crises).
- **Espionnage.** **Rumeur de faillite** (sa cote -1 cran pendant deux ans), **Maquiller les comptes** (il vous croit noté A pendant deux ans), **Racheter une créance** (sa plus grosse dette bancaire, à moitié prix : il vous paie désormais ses mensualités).
- **Cour, héros, souverain.** Le Grand Intendant abaisse le taux (3 % par point de Gestion) et la fuite fiscale ; un héros **Fiscaliste** au conseil fait l'Argentier (taux -10 %). Surnoms de souverain **le Dépensier** (trois emprunts), **l'Avare** (cinq ans sans dette, trésor plein) et **le Banqueroutier**.
- **Technologies et bâtiment.** *Bourses interstellaires* (ère III) ajoute la comptabilité stellaire : plafond +20 %, réserve +25 %. *Compagnies marchandes* (ère IV) baisse les taux de 10 %, accélère la décrue de l'inflation et débloque la **Banque centrale** (une par empire : plafond +25 %, intérêts -10 %, inflation qui décroît deux fois plus vite).
- **Hauts faits.** **Budget à l'équilibre** : le premier à tenir vingt ans sans un sou de dette avec au moins dix systèmes. **Banqueroute retentissante** (infâme) : faire faillite.

La lentille de stabilité ([[K]]) a un **mode Fiscalité** après le mode Corruption : franchises en or, grèves en rouge, fuite fiscale par système, et la cote et la dette sur la capitale. La barre du haut affiche la dette à côté du trésor, en rouge au-delà de 75 % du plafond.

### Les talents des peuples

{{fisc_talents}}

### Conseils

- Un emprunt de guerre se rembourse en paix : levez l'impôt d'un cran pendant la guerre, puis redescendez-le pour laisser la croissance repartir.
- La dette courante est la plus chère à la longue : elle ne s'éteint qu'avec l'excédent. Un emprunt volontaire bien noté coûte moins et s'arrête tout seul.
- Surveillez la cote avant d'emprunter : à AAA, le plafond monte de 20 % ; à CCC, chaque emprunt coûte 60 % de plus.
- Une franchise sur une conquête en révolte vaut souvent mieux qu'une flotte en orbite.
