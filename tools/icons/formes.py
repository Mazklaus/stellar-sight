# Outils de dessin des pictogrammes, boîte 64x64.
# Un pictogramme est une liste de couches (signe, svg) : '+' ajoute de la matière, '-' en retire (réserve).
import math

def S(d, w=3): return '<path class="s" d="%s" stroke-width="%s"/>' % (d, w)
def P(d): return '<path d="%s"/>' % d
def G(pts): return '<polygon points="%s"/>' % pts
def R(x, y, w, h, extra=''): return '<rect x="%s" y="%s" width="%s" height="%s" %s/>' % (x, y, w, h, extra)
def RR(x, y, w, h, r): return R(x, y, w, h, 'rx="%s"' % r)
def C(x, y, r): return '<circle cx="%s" cy="%s" r="%s"/>' % (x, y, r)
def O(x, y, r, w=3): return '<circle class="s" cx="%s" cy="%s" r="%s" stroke-width="%s"/>' % (x, y, r, w)
def E(x, y, rx, ry, rot=0):
    return '<ellipse cx="%s" cy="%s" rx="%s" ry="%s" transform="rotate(%s %s %s)"/>' % (x, y, rx, ry, rot, x, y)
def EO(x, y, rx, ry, w=3, rot=0):
    return '<ellipse class="s" cx="%s" cy="%s" rx="%s" ry="%s" stroke-width="%s" transform="rotate(%s %s %s)"/>' % (x, y, rx, ry, w, rot, x, y)
def T(svg, tr): return '<g transform="%s">%s</g>' % (tr, svg)
def ROT(svg, a, x=32, y=32): return T(svg, 'rotate(%s %s %s)' % (a, x, y))

def _pts(l): return ' '.join('%.1f,%.1f' % p for p in l)
def NG(x, y, r, n, rot=-90):
    """Polygone régulier plein."""
    return G(_pts([(x + r * math.cos(math.radians(rot + i * 360 / n)), y + r * math.sin(math.radians(rot + i * 360 / n))) for i in range(n)]))
def NGO(x, y, r, n, w=3, rot=-90):
    l = [(x + r * math.cos(math.radians(rot + i * 360 / n)), y + r * math.sin(math.radians(rot + i * 360 / n))) for i in range(n)]
    return S('M' + ' L'.join('%.1f %.1f' % p for p in l) + ' Z', w)
def STAR(x, y, r, n=4, k=.4, rot=-90):
    """Étoile à n branches, k = rayon intérieur relatif."""
    l = []
    for i in range(n * 2):
        rr = r if i % 2 == 0 else r * k
        a = math.radians(rot + i * 180 / n)
        l.append((x + rr * math.cos(a), y + rr * math.sin(a)))
    return G(_pts(l))
def RAYS(x, y, r1, r2, n, w=3, rot=-90, span=360):
    d = ''
    for i in range(n):
        a = math.radians(rot + i * span / (n if span == 360 else max(1, n - 1)))
        d += 'M%.1f %.1f L%.1f %.1f ' % (x + r1 * math.cos(a), y + r1 * math.sin(a), x + r2 * math.cos(a), y + r2 * math.sin(a))
    return S(d, w)
def GEAR(x, y, r, n=8, tooth=5, hole=0.42):
    """Roue dentée pleine ; renvoie (plein, trou)."""
    l = []
    for i in range(n):
        a0 = 360 / n * i
        for da, rr in [(-0.28, r), (-0.16, r + tooth), (0.16, r + tooth), (0.28, r)]:
            a = math.radians(a0 + da * 360 / n)
            l.append((x + rr * math.cos(a), y + rr * math.sin(a)))
    return G(_pts(l)), C(x, y, r * hole)
def ARC(x, y, r, a0, a1, w=3):
    """Arc de cercle en trait, angles en degrés (0 = droite, sens horaire à l'écran)."""
    p0 = (x + r * math.cos(math.radians(a0)), y + r * math.sin(math.radians(a0)))
    p1 = (x + r * math.cos(math.radians(a1)), y + r * math.sin(math.radians(a1)))
    big = 1 if abs(a1 - a0) > 180 else 0
    return S('M%.1f %.1f A%s %s 0 %d 1 %.1f %.1f' % (p0[0], p0[1], r, r, big, p1[0], p1[1]), w)
def PERS(x, y, s=1.0):
    """Buste : tête et épaules, x,y = centre de la tête."""
    return C(x, y, 5.5 * s) + P('M%.1f %.1f A%.1f %.1f 0 0 1 %.1f %.1f V%.1f H%.1f Z' % (x - 10 * s, y + 20 * s, 10 * s, 12 * s, x + 10 * s, y + 20 * s, y + 24 * s, x - 10 * s))
