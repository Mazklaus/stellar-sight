---
titre: Gouverner l'empire
numero: 27
image: MJ-44
epigraphe: Un empire, c'est d'abord une montagne de formulaires. Les étoiles, les flottes et la gloire viennent ensuite, quand le tampon est sec.
signature: Oriel Vasque, préfet de troisième classe, note de service n° 48 112
---
Conquérir est facile ; tenir est une autre affaire. Chaque système, chaque colonie, chaque millier d'habitants ajoute des dossiers sur le bureau de vos fonctionnaires. Tant qu'ils suivent, tout va bien. Quand ils ne suivent plus, l'empire ralentit, ses sujets grognent, et dans les provinces lointaines, des gouverneurs commencent à se servir. L'onglet **Administration** de l'écran Ordre intérieur ([[F12]]) rassemble tout ce qui les concerne.

Le modèle vient de **Stellaris** (taille d'empire, secteurs), de **Victoria 3** (bureaucratie, États non incorporés, loi sur la bureaucratie), de **Humankind** (capacité de villes), d'**Endless Space 2** (surcolonisation), de **Civilization IV** (entretien des villes, Tribunal, déplacer le palais), de **Distant Worlds 2** et d'**Europa Universalis IV** (corruption), de **Galactic Civilizations IV** (mondes-cœurs) et d'**Imperator: Rome** (gouverneurs).

::: capture docs/apercu-administration.png|L'onglet Administration : la jauge charge contre capacité, l'effort administratif et vos systèmes du plus corrompu au moins corrompu
:::

### Le réglage

Le bloc Règles de la nouvelle partie propose le réglage **Administration**. **Désactivée** garde les règles d'avant : la surextension de la stabilité (au-delà de 12 systèmes peuplés) et le surcoût de recherche par colonie.

{{admin_modes}}

Quand le pilier tourne, il **remplace** la surextension et le surcoût de recherche des grands empires : il n'y a jamais de double peine.

### Charge et capacité

Tout ce que l'empire possède crée de la **charge** : **4** par système peuplé, **2** par colonie de plus dans le même système, **1** par tranche de 10 habitants, **1** par avant-poste, **2** par système ennemi occupé en guerre. Les systèmes **non intégrés** et les **vassaux** ne pèsent rien ; en féodalité, les fiefs d'une Grande Maison ne pèsent que pour moitié.

La **capacité administrative** vient de la capitale (**50**), des Forums impériaux (**+10**), des Préfectures (**+8**), des Tribunaux (**+2**), des technologies d'administration, de l'aptitude **Gestion** du souverain (**+2** par point), du **Grand Intendant** de la cour, des héros au trait **Bureaucrate** au conseil, et de l'effort administratif. Au départ, un empire tient une dizaine de systèmes.

Au-dessus de la capacité, chaque tranche de **10 %** de charge en trop coûte :

- **-2 de stabilité** dans tous vos systèmes (jusqu'à -15) ;
- **+5 %** au coût de la recherche ;
- **+5 %** aux coûts en influence (décrets, lois, intégration) ;
- **+3 de corruption** dans tous vos systèmes.

La jauge du haut de l'onglet devient orange puis rouge ; le détail de la charge et de la capacité est listé ligne à ligne.

### La corruption

Chaque système a une **corruption** de **0 à 50 %**. Elle détourne cette part de son **énergie**, de ses **matériaux**, de son **influence** et de son **Savoir**. Jamais la nourriture : même un préfet véreux veut que ses administrés mangent.

| Ce qui la fait monter | Valeur |
| --- | --- |
| La distance au siège le plus proche | +3 par saut au-delà de 3, jusqu'à +30 |
| Une enclave (siège injoignable par vos systèmes, les systèmes libres ou ceux d'un allié) | distance ×1,5 |
| Une grosse population | +1 par tranche de 5 habitants au-delà de 20 |
| Une stabilité basse (sous 30) | +10 |
| Un monde conquis (5 ans) | +10 |
| Un empire au-dessus de sa capacité | +3 par tranche de 10 % |
| Un gouverneur Vénal | +5 |
| Un fief d'une maison mécontente (féodalité) | +5 |

| Ce qui la fait baisser | Valeur |
| --- | --- |
| La capitale | -10 |
| Un Intendant gouverneur | -5, plus selon son niveau |
| Un Intendant gouverneur de province, dans toute la province | moitié de son effet |
| Un **Tribunal** | ÷2 |
| Un gouverneur **Intègre** | ÷2 |
| Les lois, les talents et l'effort administratif | voir plus bas |

Au-dessus de **30 %**, le système perd **5 de stabilité** : la corruption nourrit l'agitation, et l'agitation nourrit la corruption. Le détail de chaque système s'affiche en infobulle, et la lentille de stabilité ([[K]]) a un **mode Corruption** au deuxième appui : vos systèmes cerclés selon leur corruption, les sièges marqués, les systèmes non intégrés en pointillé.

**Le Tribunal.** Un bâtiment par système (150 matériaux, 2 énergie par mois) qui divise la corruption locale par deux et ajoute 2 de capacité. La technologie *Cadastre algorithmique* le rend 40 % moins cher.

### L'effort administratif

Combien payez-vous vos fonctionnaires ? Le choix se fait en haut de l'onglet et vaut pour tout l'empire.

{{admin_efforts}}

### Provinces et sièges

Chaque **Préfecture** devient un **siège** : les systèmes à moins de **4 sauts** s'y rattachent et forment une **province**, dont la distance se compte depuis la Préfecture et non plus depuis la capitale. Un **Intendant** posté comme gouverneur du système de la Préfecture étend la moitié de son effet à toute la province. Les autres systèmes dépendent de la capitale.

### Intégrer les conquêtes

Un système **conquis, cédé, réintégré, absorbé ou annexé** arrive **non intégré** : il ne pèse rien dans la charge, mais sa production est divisée par deux et il n'accepte aucun décret. Le bouton **Intégrer** coûte de l'influence (20, plus 10 par colonie) et prend **180 jours**, avec une stabilité d'au moins 30. La horde intègre moitié moins cher.

### Déplacer la capitale

Vers une colonie d'au moins **10 habitants** et intégrée, pour **150 influence et 400 matériaux**. Pendant **un an**, la transition coûte **10 de stabilité** partout ; ensuite, il faut attendre **vingt ans** avant un nouveau transfert. Ni la horde (sa capitale, c'est sa flotte-ville) ni la ruche (sa capitale, c'est sa reine) ne déménagent.

### Héros, cour et lois

- Trois traits de héros : **Vénal** (+5 de corruption là où il gouverne), **Intègre** (corruption divisée par deux là où il gouverne), **Bureaucrate** (+5 de capacité au conseil).
- Le **Grand Intendant** de la cour ajoute 2 de capacité par point de Gestion ; l'aptitude **Gestion** du souverain aussi.
- Deux lois indépendantes : **Fonctionnaires élus** (corruption -20 %, capacité -10 %, la Concorde applaudit) et **Inspection impériale** (corruption -5 partout, stabilité -2, le Glaive approuve).
- Deux technologies : **Cadastre algorithmique** (ère III : +10 capacité, Tribunal moins cher) et **Administration quantique** (ère V : +15 capacité, distances comptées à moitié pour la corruption). Les technologies qui repoussaient le seuil de surextension donnent **4 de capacité par point**.

### Scandales et ponts

- **Scandales.** Une fois par an, un système au-dessus de 30 % de corruption peut tirer un scandale : un **marché noir** (jusqu'à 40 énergie évaporées), des **fonctionnaires achetés** (les réseaux d'espions étrangers grandissent plus vite chez vous pendant un an) ou un **détournement révélé**, une carte où il faut punir (purge des bureaux : -10 de corruption pendant deux ans, mais le gouverneur vous en veut), étouffer (30 influence) ou laisser la presse s'en charger (stabilité -10 pendant un an). Ensuite, plus rien pendant dix ans dans ce système.
- **Pirates.** Les pirates visent d'abord les systèmes au-dessus de 35 % de corruption, et un système au-dessus de 40 % peut voir un repaire s'installer à côté.
- **Espionnage.** L'opération **Acheter les fonctionnaires** (intrigue, niveau 2) ajoute 15 de corruption au système le plus corrompu d'un rival (hors capitale) pendant un an. Un empire trop vaste laisse aussi les réseaux étrangers grandir plus vite.
- **Commerce.** Une route perd la corruption de son port de départ ; le credo du profit l'en dispense.
- **Politique.** Une corruption moyenne de 25 % ou plus ouvre la doléance **Assainir l'administration** (deux ans pour la ramener sous 20 %) et coûte 10 % des voix aux courants au pouvoir.
- **Haut fait.** **Mains propres** : le premier empire d'au moins 20 systèmes qui garde une corruption moyenne sous 5 % pendant dix ans.

### Les talents des peuples

{{admin_talents}}

### Conseils

- Une Préfecture bien placée vaut mieux que trois Tribunaux : elle rapproche tout un quartier de l'empire de son siège et ajoute de la capacité.
- N'intégrez pas une conquête en révolte : elle produit déjà moitié moins, et elle ne pèse rien tant qu'elle attend.
- La Grande enquête est un remède de cheval. Une année suffit souvent ; ensuite, Généreux tient la corruption à distance pour moins cher.
- Pour une ruche ou une conscience, la corruption n'existe pas ; mais la jauge, elle, ne pardonne pas.
