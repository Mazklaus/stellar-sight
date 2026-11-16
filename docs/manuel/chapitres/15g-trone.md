---
titre: Le trône et la lignée
numero: 25
image: MJ-42
epigraphe: Une couronne ne pèse que quelques grammes. Le reste du poids, c'est tout ce qu'on attend de celui qui la porte.
signature: Pernelle l'Inspirée, reine d'Ossarane, carnets intimes (édition expurgée)
---
Chaque empire a désormais une tête : un **souverain**, avec un nom, un visage, un âge, des aptitudes, une **légitimité** et des **surnoms** gagnés au fil du règne. Il vieillit, il meurt, et quelqu'un doit le remplacer : selon votre gouvernement, un héritier, un élu, un pontife ou le vainqueur d'une Épreuve. L'écran **Trône** ([[Maj]]+[[F10]], ou un clic sur le nom de l'empire dans la barre d'empire) rassemble tout ce qui le concerne.

Le modèle vient d'**Old World** (souverain qui vieillit, archétypes, légitimité nourrie par les surnoms et les ambitions, héritiers à éduquer), de **Crusader Kings III** (lois de succession, régence, mariages et alliances de sang, héritages de la maison, prétendants), de **Stellaris** (gouvernements qui changent la façon de choisir le chef) et d'**Endless Legend** pour l'idée qu'un peuple étrange se gouverne étrangement.

::: capture docs/apercu-trone.png|L'écran Trône : le souverain, ses aptitudes, son pouvoir, son ambition et sa lignée
:::

### Les réglages

Le bloc Règles de la nouvelle partie propose deux réglages :

{{souverains_modes}}

### Le souverain

Le souverain occupe une **place à part** : il ne compte pas dans la limite des héros et ne se renvoie pas. Son **portrait** est tiré d'une galerie propre aux souverains (59 portraits, une série par archétype d'espèce), sans jamais reprendre un visage déjà porté dans l'empire.

Il a **quatre aptitudes**, de 0 à 6, qui valent pour tout l'empire :

| Aptitude | Par point |
| --- | --- |
| Gestion | +2 % de production partout |
| Guerre | +2 % de dégâts pour toutes les flottes, le double pour celle qu'il commande |
| Éloquence | +1 influence par mois, et un peu d'opinion chez ceux qui vous connaissent |
| Intrigue | Opérations d'espionnage 3 % moins chères, chiffrement renforcé |

Il a un **archétype de règne**, avec un petit effet permanent et un **pouvoir** qu'il invoque depuis l'écran Trône, une fois tous les deux ans. Chaque archétype penche aussi vers un **courant** (chapitre 14) : chaque mois, il y pousse l'opinion de la capitale.

{{archetypes_regne}}

**Le poste.** Le souverain reste au palais, ou prend la tête d'une flotte armée : il double alors son bonus de Guerre pour elle, mais peut être **blessé** (quatre mois loin du front) ou **tué** si elle est anéantie. Une Reine-mère ne quitte jamais la ruche.

### La légitimité

La légitimité, de 0 à 100, dit à quel point l'empire accepte son maître. Elle part d'une valeur qui dépend de la façon dont il est monté sur le trône (60 pour un fondateur, 50 pour un héritier, 20 pour un usurpateur), puis :

- chaque **surnom** l'augmente (ou la baisse, pour l'Infortuné ou le Parjure) ;
- les surnoms des **prédécesseurs** comptent aussi, de moins en moins : la moitié pour le précédent, le tiers pour celui d'avant ;
- les victoires, les ambitions et les héritages l'élèvent ; les défaites, les systèmes perdus et surtout la **capitale perdue** (-15) la rongent ;
- le **sacre** : +10 si la foi d'État tient son monde saint ;
- la **Couronne vacillante** : -10 pendant la première année de chaque règne. Pendant ce temps, les rivaux paient leurs revendications **moitié prix**.

Au-dessus de **75**, la stabilité gagne 5 partout ; sous **25**, elle en perd 5. Sous 25 pendant un an, un **prétendant** se proclame : un quart des systèmes les plus lointains fait sécession avec lui, et il vous déclare la guerre.

### Surnoms et ambitions

Les surnoms se gagnent : trois victoires font « le Vaillant », quinze technologies « le Savant », cinq traités « le Pacificateur », dix ans de règne dans une foi d'État « le Saint ». Un règne en porte quatre au plus ; le plus prestigieux suit le nom (« Reine Aldra II la Vaillante »). Certains ne viennent qu'à l'avènement (le Jeune, l'Usurpateur), d'autres qu'à la mort (le Bref, l'Assassiné). Les titres des hauts faits (chapitre 24) deviennent des surnoms : le Cartographe, la Conquérante. Les surnoms **propres à un peuple** dépendent de son credo, de son registre, de son archétype ou de son gouvernement.

{{surnoms}}

À l'avènement, puis deux mois après chaque réussite, le souverain choisit une **ambition** parmi trois, tirées selon son archétype. Réussie, elle donne +15 de légitimité et un surnom.

{{ambitions_souverain}}

### La succession

Le souverain meurt de vieillesse (l'espérance de vie dépend de l'espèce, comme pour les héros), d'un accident, au front, assassiné, ou renversé. Chaque gouvernement règle sa succession à sa façon :

{{successions}}

Pendant un **interrègne** (Conclave, Épreuve, attente de la couvée royale), le trône reste vide : pas d'aptitudes, pas de pouvoir. Une République élit son Premier Archonte au mandat de trois ans ; réélu si sa légitimité atteint 50, jamais plus de deux mandats. Le Conseil des actionnaires vote la défiance si le revenu d'énergie baisse deux trimestres de suite, avec un parachute doré pour le partant.

**Les funérailles.** À la mort d'un souverain, une carte propose trois façons de l'honorer, selon votre credo (un bûcher des braves, sept jours de chants, le corps donné à la science…). L'effet dure cinq ans, et les souvenirs des héros sont prolongés d'un an.

### La dynastie

Seule une **Féodalité** a une maison, des héritiers et une **loi de succession**, qu'on change contre 80 influence et 10 de légitimité :

- **Primogéniture** : l'aîné hérite de tout. La plus stable.
- **Partage** : l'aîné hérite du trône, chaque cadet reçoit un fief lointain qui devient un **vassal** (chapitre 10).
- **Élection des lignées** : la Diète choisit parmi les héros les plus loyaux et les héritiers ; l'élu a +10 de légitimité.

**Les héritiers.** Le souverain a un consort et des enfants (une couvée chez les reptiliens, jamais chez les synthétiques), cinq au plus. Chaque enfant a ses aptitudes ; à dix ans, vous choisissez son **éducation** (stratège, intendant, orateur, ombre), qui renforce l'aptitude liée ; à seize ans, il devient un héros de sang. L'**héritier d'Ossarane** passe devant les enfants. Un héritier déclaré **bâtard** perd 15 de légitimité en montant sur le trône.

**La Cour.** Les trois héros les plus loyaux forment la Cour : la moitié de leurs points d'aptitude s'ajoute à celles du souverain, trois au plus.

**La régence.** Un souverain mineur règne sous un **régent** (le meilleur orateur, ou un conseil) : pas de déclaration de guerre, pas de pouvoir, et la légitimité perd 1 par mois. À la majorité, le régent rend les sceaux… sauf dans 15 % des cas, où il garde le trône pour lui.

**L'extinction.** Sans héritier, la lignée s'éteint. Un empire lié par un **mariage** hérite du trône (union personnelle : l'empire devient son vassal) ; sinon, une nouvelle maison monte sur le trône, avec deux ans de troubles.

**Les mariages.** Deux dynasties qui se connaissent et ne sont pas en guerre peuvent unir leurs lignées : +20 d'opinion entre elles, et chacune pourra réclamer le trône de l'autre si elle s'éteint.

**L'étoile montante.** Quand le renom d'un héros dépasse de 15 la légitimité du trône, la cour murmure : vous pouvez l'acheter (60 influence), l'éloigner (sa loyauté baisse), ou abdiquer en sa faveur.

### Héritages de la maison

Chaque règne achevé laisse du **renom** à la maison (ou à l'État, pour les régimes sans dynastie, qui parlent de **traditions d'État**) : sa légitimité finale et ses surnoms. Le renom achète des héritages **permanents**, voie après voie :

{{heritages}}

### La mort des héros au combat

Désormais, un héros peut **tomber** au combat. Quand sa flotte est anéantie, il meurt une fois sur dix (au réglage Normale) ; quand le plus gros vaisseau de sa flotte est détruit, trois fois sur cent ; quand son système est perdu ou son armée vaincue, une fois sur vingt. Sinon, il est blessé et peut être capturé, comme avant.

- Le trait **Trompe-la-mort** divise ce risque par deux ; le trait **Téméraire** le double, contre +5 % de dégâts.
- Le module **Capsules de survie** (chapitre 6) retire trois points au risque.
- Un **Avatar** des énergétiques meurt une fois et demie plus souvent, mais se **reforme** six mois plus tard, un niveau plus bas.
- Un héros **synthétique** revient un an plus tard, un niveau plus bas, si l'empire connaît la technologie IA de bord (sauvegarde de la personnalité).

La mort d'un héros de niveau 3 ou plus ouvre une **fenêtre** qui lui rend hommage ; son nom s'inscrit dans le rapport de bataille. Tombé au combat, il laisse son souvenir et compte comme **Martyr** pour une foi (chapitre 15).

### Les ponts

- **Foi** : le Pontife est le chef de sa foi ; une Théocratie dont la foi tient son monde saint sacre son souverain (+10 de légitimité). Un souverain tué compte comme un martyr.
- **Politique** : un **coup d'État** issu d'une crise de régime installe un usurpateur ; une crise de régime renverse un souverain dont la légitimité est sous 50.
- **Ombres** : trois opérations nouvelles, **Assassiner le souverain** (sauf une Reine-mère), **Soutenir un prétendant** (-15 de légitimité) et **Révéler une bâtardise**. Découvertes, elles font un incident diplomatique.
- **Guerre** : un trône usurpé donne aux dynasties le motif **Guerre de succession**, avec le but **Imposer un héritier** : le vainqueur met sur le trône un candidat de sa maison.
- **Hauts faits** : leurs titres deviennent des surnoms.
- **Diplomatie** : l'Éloquence et les mariages comptent dans l'opinion ; un souverain assassiné laisse une rancune.

### Les rivaux

Les empires IA placent leur souverain (au front seulement pour un tempérament belliqueux en guerre), invoquent son pouvoir au bon moment (le Conquérant en guerre, le Savant quand une recherche est en cours), éduquent leurs héritiers, achètent des héritages, arrangent des mariages et abdiquent quand le souverain est trop vieux et qu'un héritier est prêt. Ils profitent aussi d'eux-mêmes d'une Couronne vacillante chez un rival.
