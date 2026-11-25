# Vérifie que chaque entrée du jeu a son pictogramme, sans motif inconnu ni doublon dans une famille.
import sys, json, glob, collections, os
ICI = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, ICI)
DATA = os.path.join(ICI, '..', '..', 'data')
from table import TABLE
from rendu import motifs

def attendus():
    def J(f): return json.load(open(os.path.join(DATA, f)))
    def ids(x): return [k for k, v in x.items() if isinstance(v, dict)] if isinstance(x, dict) else [v['id'] for v in x]
    w = set()
    for f in glob.glob(os.path.join(DATA, 'tech', '*.json')):
        w |= {'tech/' + k for k in ids(json.load(open(f))['technologies'])}
    w |= {'batiment/' + k for k in ids(J('buildings.json'))}
    w |= {'haut_fait/' + k for k in ids(J('deeds.json')['deeds'])}
    w |= {'relique/' + k for k in ids(J('relics.json')['relics'])}
    f = J('faiths.json')
    w |= {'precepte/' + k for k in ids(f['precepts'])} | {'nature/' + k for k in ids(f['natures']['list'])}
    a = J('archaeology.json')
    for s in ['site_types', 'disparus', 'natures', 'methods']: w |= {'fouille/' + k for k in ids(a[s])}
    g = J('goods.json')
    for s in ['luxuries', 'strategic']: w |= {'ressource/' + k for k in ids(g[s])}
    return w

def verifier():
    M = motifs(); w = attendus(); ok = True
    for nom, l in [('sans pictogramme', sorted(w - set(TABLE))), ('pictogramme sans entrée', sorted(set(TABLE) - w)),
                   ('motif inconnu', [(k, v) for k, v in TABLE.items() for m in v.split('*')[0].split('+') if m not in M])]:
        if l: ok = False; print(nom, ':', l)
    by = collections.defaultdict(list)
    for k, v in TABLE.items(): by[(k.split('/')[0], v)].append(k)
    d = [v for v in by.values() if len(v) > 1]
    if d: ok = False; print('doublons :', d)
    return ok

if __name__ == '__main__':
    print(len(TABLE), 'entrées,', len(motifs()), 'motifs')
    sys.exit(0 if verifier() else 1)
