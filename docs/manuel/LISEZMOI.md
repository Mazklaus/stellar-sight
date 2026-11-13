# Codex de l'Archonte : le manuel de Stellar Sight

Le manuel PDF du jeu (`manuel.pdf`), généré depuis ce dépôt. Étude de conception : https://claude.ai/artifact/LXvCHF7RNNozrAKVNoqrWm

## Régénérer le PDF

Il faut Python 3 (bibliothèque standard seulement), Node.js et Playwright avec Chromium.

```
cd docs/manuel
python3 build.py            # manuel.html puis manuel.pdf
python3 build.py --html     # HTML seulement (aperçu dans un navigateur)
python3 build.py --clair    # variante sur fond clair, pour l'impression
```

Si Playwright est installé globalement : `NODE_PATH=$(npm root -g) python3 build.py`. La pagination (Paged.js) prend une à deux minutes.

## Ce qui se met à jour tout seul

Les tableaux des ressources, de la stabilité, des courants, des technologies, des peuples, de la faune et des gardiens sont lus dans `data/*.json` : régénérer suffit. La date, l'édition et la version du jeu (commit) s'inscrivent en page de garde.

## Écrire ou corriger un chapitre

Un fichier par chapitre dans `chapitres/`, lus dans l'ordre des noms. En-tête :

```
---
titre: La guerre
numero: 7
image: MJ-11
epigraphe: Une phrase.
signature: Son auteur
---
```

`type: partie` fait une page de partie ; `etiquette: Annexe` remplace « Chapitre ».

Corps en markdown simple (titres `###`, listes, tableaux, **gras**, *italique*), plus :

- `[[F4]]` : une touche du clavier ;
- `{{peuples}}` seul sur sa ligne : un tableau tiré des données (`ressources`, `stabilite`, `courants`, `technologies`, `peuples`, `faune`, `gardiens`, `prompts`) ;
- des blocs `::: nom argument` … `:::` : `chronique Source|Signature` (fragment de lore), `transmission Émetteur`, `marge` (note du commandant Varrek), `conseil`, `attention Titre`, `encadre Titre`, `image MJ-07 flottant-d`, `capture docs/apercu-x.png|Légende` (avec des repères `1 12% 8% texte` à l'intérieur), `colonnes` ;
- `---saut---` : saut de page.

Les textes propres à chaque peuple (devise, histoire, chronique, conseil) sont dans `peuples.json`.

## Les illustrations Midjourney

`PROMPTS-MIDJOURNEY.md` (régénéré à chaque fabrication) liste les 30 encarts avec leur commande. Déposer l'image dans `images/` sous le nom de son identifiant (`MJ-07.png`, `.jpg` ou `.webp`) et régénérer : elle remplace l'emplacement vide, dans son cadre.

La forme des cadres se change en une ligne, `FORMES` en tête de `build.py` (`droit`, `arrondi`, `coupe`, `asym`, `arche`, `medaillon`).

## Licences

Polices Cinzel, EB Garamond, Rajdhani et Caveat : SIL Open Font License (`fonts/OFL-*.txt`). Paged.js : MIT (`vendor/LICENSE-pagedjs.md`).
