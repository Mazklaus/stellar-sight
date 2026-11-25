# Atelier des fichiers son

`son.py` prépare les fichiers de `assets/sounds/`. Il lui faut Python 3, numpy et ffmpeg.

| Commande | Effet |
|---|---|
| `mesurer fichier…` | Durée, niveau perçu (LUFS) et crête. |
| `tempo morceau` | Tempo estimé d'un morceau. |
| `poser source dossier/id` | Met un son court au niveau de son dossier et l'écrit en OGG. |
| `boucler source dossier/id --debut s --duree s` | Découpe une ambiance qui boucle, raccord en fondu d'une seconde. |
| `boucler source dossier/id --debut s --mesures n [--bpm t]` | Découpe une boucle musicale d'un nombre entier de mesures. |
| `verifier` | Contrôle tout `assets/sounds/` : fiche, licence, niveau, raccord des boucles. |

Ajouter `--outil`, `--consigne` et `--licence` à `poser` et `boucler` : ils remplissent la fiche d'origine
du son dans `assets/sounds/origines.json`. Un son sans fiche ou sans licence fait échouer `tests/sound_tests.gd`.

Les niveaux de référence sont dans le bloc `levels` de `data/audio.json`. Les dossiers `carte` et `ecran`
sont réglés bas : ce sont des fonds, toujours sous la musique.

Le nom du fichier décide de son emploi : `assets/sounds/ui/ui_valider.ogg` remplace l'esquisse de synthèse
du repère `ui_valider` (voir `data/audio.json`), sans rien changer au code.
