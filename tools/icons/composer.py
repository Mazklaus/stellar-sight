# Compose le pictogramme d'une entrée à partir de la table : motif seul, motif et insigne, crans de rang.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from formes import T, C, NG
from rendu import motifs, svg
from table import TABLE

_M = motifs()

def couches(spec):
    base, _, n = spec.partition('*')
    principal, _, insigne = base.partition('+')
    n = int(n) if n else 0
    out = list(_M[principal])
    if insigne:
        out = [(s, T(m, 'scale(.84)')) for s, m in out]
        out.append(('-', C(47.5, 47.5, 16.5)))
        out += [(s, T(m, 'translate(33.5 33.5) scale(.44)')) for s, m in _M[insigne]]
    if n:
        out = [(s, T(m, 'translate(5 0) scale(.84)')) for s, m in out]
        x0 = 32 - (n - 1) * 5
        out.append(('-', ''.join(NG(x0 + i * 10, 58.5, 6.2, 4, 0) for i in range(n))))
        out.append(('+', ''.join(NG(x0 + i * 10, 58.5, 4.2, 4, 0) for i in range(n))))
    return out

def icone_svg(cle, taille=64, couleur='#fff'):
    return svg(couches(TABLE[cle]), taille, couleur)
