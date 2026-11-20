# Performance : référence et points lents

## Fin de partie, étude approfondie (2026-11-20)

Étude : https://claude.ai/artifact/KR4kwB4YpjZPLYHgZENSy2 (37 propositions). Seules celles qui gardent la
partie identique ont été codées. Empreintes de contrôle, identiques avant et après : 90 jours depuis l'an 30
(graine 7) `f17295c64b906022`, l'an 40 (graine 7) `e26cb039e9a09951`, l'an 50 (graine 11) `681d099dca6e36d3` ;
30 jours : `9f5fad3b3fa81da1`, `46f5e2b729dfae5a`, `21493d924dc7de9a` ; 14 ans graine 3 `76c4385475954e73`.

| 90 jours depuis | avant (ms/jour) | après | Flottes avant | après | IA avant | après |
| --- | --- | --- | --- | --- | --- | --- |
| an 30 | 414 | 365 | 91 | 62 | 122 | 113 |
| an 40 | 750 | 611 | 136 | 90 | 280 | 236 |
| an 50 | 912 | 730 | 201 | 109 | 278 | 236 |

(Conteneur cloud, les deux versions mesurées en même temps. Le 1er du mois reste autour de 3 s à l'an 50.)

Ce qui a changé :
- clé des talents de peuple et marque « peuple voilé » gardées avec la fiche (`Empire.species_key`, `veiled`) ;
- table de couverture de détection par empire et par jour (`Stealth._cover`) : chaque source est propagée une
  fois dans son rayon, au lieu d'être relue pour chaque flotte testée ; alliés et bonus gardés pendant le relevé ;
- repérages quotidiens (`StealthBridges.daily`) sous le même mémo que le relevé d'Intel ;
- camouflage et détection d'une flotte arrêtés dès que le résultat est acquis ; voiles jugés une fois par
  propriétaire dans un relevé (`Veil.filter_survey`) ;
- puissance d'un vaisseau gardée par modèle (`Combat.ship_strength`, vidée par `GameData.ship_gen`) ;
- cible de colonisation : les systèmes candidats d'abord, la recherche de chemins seulement s'il en reste ;
- fiches de vaisseaux en table directe, tables de réglages gardées par pilier, capacité d'une colonie calculée
  seulement quand elle sert, bonus de population des mégastructures lu sans copie.

Ce qui n'a pas été fait, et pourquoi : le profil est plat (les 10 premières fonctions pèsent 16 %). Le reste
du gain annoncé par l'étude vient de caches gardés d'un jour à l'autre (revenus d'empire, zones de
ravitaillement, opinions, régiments triés, adjacence des routes). Ils demandent des compteurs de version
posés à chaque écriture de l'état (propositions 27 et 28) : sans eux, rien ne garantit la partie identique.
C'est un chantier à part, à faire avec un mode « cache vérifié » qui recalcule et compare.

Outils ajoutés : `tools/instrument_edges.py` (profil avec arêtes appelant > appelé, sur une copie),
`tools/deep_profile_edges.gd` (temps par système et empreinte depuis une sauvegarde : `LOAD`, `DAYS`, `OUT`),
`tools/profile_report.py` (`top`, `fn`, `tree`, `days`).

## Parties longues, an 30 à 50 (2026-11-20)

Étude : https://claude.ai/artifact/2kMB5CmUnXUApuZT3tgaio. Lot A (empreinte identique) : 30 jours depuis la
sauvegarde de l'an 30 (graine 7) = `9f5fad3b3fa81da1`, depuis l'an 50 (graine 11) = `21493d924dc7de9a`, 14 ans
graine 3 = `76c4385475954e73`, identiques avant et après.

| 30 jours depuis | avant (ms/jour) | après | 1er du mois avant | après |
| --- | --- | --- | --- | --- |
| an 30 | 613 | 534 | 3 943 | 2 822 |
| an 50 | 1 660 | 1 135 | 13 287 | 4 327 |

Ce qui a changé : test d'inhibiteur des portails après le test de guerre (il parcourait tous les bâtiments
du système), station de défense calculée une fois par test, raccourcis civils mémorisés pendant le calcul
des routes commerciales et de la desserte des ports (`Portals.memo_begin/memo_end`), bouts de portail
mémorisés pendant une recherche de chemin, détection gardée par système pendant le relevé des flottes
(`Stealth.at_memo_begin/at_memo_end`), cible de migration sans calculer toutes les capacités, clés de
relation et fiches de vaisseaux gardées. Commerce : 209 → 15 ms/jour à l'an 50 ; Spatioports : 85 → 11.

Ce qui reste à l'an 50 (ms/jour, conteneur) : IA 345, Flottes 251 (relevé de vision), Économie 159.

Bug corrigé en chemin : une technologie obtenue sans recherche (relique des ruines d'un peuple parti,
défenses de la Sporemère) restait dans la file ; la sauvegarde était refusée au chargement et, en tête de
file, `Research.advance` tournait sans fin (partie graine 3 figée à l'an 32). `Research.unqueue`.

Outils : `tools/long_game.gd` a un fil de garde (`HANG_S`, 120 s) qui écrit où la partie est restée
bloquée ; banc `tests/endgame_perf_tests.gd` à l'an 40 (`tests/data/fin_de_partie_an40.json.gz`).

## Grande passe d'optimisation (2026-11-19, PR #152)

Étude : https://claude.ai/artifact/8Yp78SgMZRpyGfNSvCR8Hw. Seules les propositions qui laissent la partie
identique ont été retenues : l'empreinte finale (graine 3, 14 ans) reste `5ae4f7b8cdc5fe6d`, la même que sur
main avant la passe ; 30 jours depuis la sauvegarde de l'an 12 donnent `f68b9ef06cd68e54` des deux côtés.

| An | avant (ms/jour) | après | pire jour avant | après |
| --- | --- | --- | --- | --- |
| 1 | 102 | 58 | 567 | 322 |
| 6 | 215 | 142 | 1 288 | 925 |
| 9 | 357 | 229 | 2 368 | 1 592 |
| 12 | 418 | 263 | 2 491 | 1 911 |
| 14 | 462 | 263 | 2 899 | 1 860 |

Moyenne sur 14 ans (ms/jour), avant → après : IA 89,6 → 60,6 · Logistique 39,4 → 14,9 · Flottes 38,3 → 31,1 ·
Économie 32,3 → 24,6 · Combat au sol 29,3 → 7,9.

Ce qui a changé : ère courante comptée en un passage (`Research.open_eras`), partie commune des zones de
ravitaillement (`Logistics._shared`) et bouts de corridor mémorisés, régiments triés par flotte seulement,
détection calculée une fois par flotte vue, plafonds des régiments mémorisés pendant la récupération,
héros filtrés avant le tri, bilan Kardashev une fois par mois, `get_empire` / `is_npc` / `GameData.building`
plus directs.

Ce qui reste (fin de partie, conteneur) : l'IA (≈ 100 ms/jour), les revenus des empires recalculés par chaque
traitement mensuel le 1er du mois (pic ≈ 1,9 s), la vision. Les gains suivants demandent de changer le rythme
de la simulation (propositions 14, 17, 18 de l'étude, écartées pour l'instant).

### Changement de rythme (propositions 14 et 17, acceptées ensuite)

- 14 : le bilan mensuel de chaque IA tombe sur son propre jour du mois (`EconomySystem.month_offset`, jours 2
  à 29 selon l'empire). Le joueur humain et les PNJ gardent le 1er. Le bilan Kardashev suit le même jour.
- 17 : après `slow_after_days` (an 6, `data/ai.json`), l'IA ne revoit ses bâtiments et ses plans de vaisseaux
  qu'une fois par mois (`AiPlayer.slow_turn`) ; avant, rien ne change.
- 18 (réflexions de l'IA étalées) : inutile, la mesure montre qu'elles le sont déjà, un empire par jour.

La partie change donc : nouvelle empreinte graine 3, 14 ans = `76c4385475954e73`. An 12 : 263 → 229 ms/jour,
pire jour 1 911 → ≈ 1 250 ; an 14 : 263 → 232, pire jour 1 860 → 1 349. Le pic du 1er du mois (30 jours depuis
l'an 12) passe de 1 554 à 1 005 ms. Force de l'IA vérifiée sur 14 ans (graines 3 et 17) : score total +1 %,
bâtiments −4,5 %.

Outils : `tools/profile_game.gd` (suit `Simulation.daily_systems()`, `SAVE_AT` pour garder une sauvegarde),
`tools/instrument_profile.py` + `tools/deep_profile.gd` (temps de chaque fonction, sur une copie instrumentée),
banc `tests/endgame_perf_tests.gd` (sauvegarde de l'an 12 dans `tests/data/fin_de_partie.json.gz`).

## Petite passe (2026-11-18)

Mesure du 2026-11-18 (petite passe d'optimisation), à refaire avant et après la grande passe.
Rapport complet : https://claude.ai/artifact/DhzaeHwU8Hnm6gtqm3mGwK

## Comment mesurer

- `godot --headless --path . -s res://tools/profile_game.gd` : partie entre IA avec les réglages par
  défaut de Nouvelle partie (8 empires, tous les piliers, spectateur), coût de chaque système par jour,
  année par année, mémoire et sauvegardes. Variables : `YEARS` (40), `SEED` (3), `LEVEL`, `SAVE_EVERY`, `OUT`.
- La dernière ligne donne l'empreinte finale : même graine et même durée = même empreinte, sinon
  l'optimisation a changé la partie. Graine 3, 12 ans, IA Normale : `0c8b7e6848fd74a1` (au 2026-11-18).
- Rediriger la sortie vers un fichier (vers un tube, Godot la tamponne).

## Référence (conteneur cloud, environ deux fois plus lent qu'un PC de jeu)

| An | ms par jour | Pire jour (ms) | Colonies |
| --- | --- | --- | --- |
| 1 | 59 | 271 | 85 |
| 3 | 102 | 532 | 150 |
| 6 | 236 | 1 396 | 298 |
| 9 | 438 | 2 634 | 437 |
| 12 | 539 | 3 460 | 450 |
| 14 | 674 | 4 523 | 461 |

À la vitesse 5, un jour dure 40 ms. Mémoire statique : 120 Mo (an 1), 134 Mo (an 14). Sauvegarde :
220 Ko au départ, 1,7 Mo l'an 12 ; empreinte (checksum) 17 ms puis 131 ms.

## Coût moyen par système sur 12 ans (ms par jour)

IA 68,7 · Logistique 50,6 · Économie 39,6 · Flottes 36,8 · Combat au sol 27,3 · Combat 9,9 ·
Hauts faits 5,4 · Diplomatie 5,1 · Commerce 3,4 · Culture 2,6 · Spatioports 2,5 · le reste sous 2,2.

## Pistes pour la grande passe

1. IA : découper le coût par décision, puis espacer les décisions lentes (mensuelles, étalées).
2. Logistique : zones de ravitaillement recalculées chaque jour pour chaque empire, `log_cache` vidé en
   plein jour ; ne recalculer qu'au changement de possession ou de tête de pont.
3. Économie : continue de monter quand la galaxie est pleine (76 → 155 ms entre l'an 10 et l'an 14).
4. Flottes : chantiers, exploration et vision recalculées chaque jour.
5. Combat au sol : `aboard()` / `used_places()` trient tous les régiments pour chaque flotte.
6. Débuts de mois : tous les traitements mensuels le même jour (pires jours de 3 à 4,5 s).
7. Chercher systématiquement les `Array(x)` qui partagent un tableau (voir tests/data_integrity_tests.gd).
