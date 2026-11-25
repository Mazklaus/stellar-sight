# Rendu des pictogrammes : SVG autonome d'un glyphe, planche de contrôle.
import importlib, sys
_n = [0]
STYLE = '<style>.s{fill:none;stroke:currentColor;stroke-linecap:round;stroke-linejoin:round}</style>'

def couches_svg(couches):
    return ''.join('<g fill="%s" color="%s">%s</g>' % (('#fff', '#fff', m) if s == '+' else ('#000', '#000', m)) for s, m in couches)

def svg(couches, taille=64, couleur='#fff'):
    _n[0] += 1
    mid = 'm%d' % _n[0]
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="%s" height="%s">%s'
            '<mask id="%s" maskUnits="userSpaceOnUse" x="0" y="0" width="64" height="64"><rect width="64" height="64" fill="#000"/>%s</mask>'
            '<rect width="64" height="64" fill="%s" mask="url(#%s)"/></svg>') % (taille, taille, STYLE, mid, couches_svg(couches), couleur, mid)

def motifs():
    out = {}
    for m in 'abcd':
        try: out.update(importlib.import_module('motifs_' + m).M)
        except ModuleNotFoundError: pass
    return out

if __name__ == '__main__':
    # planche de contrôle : python3 rendu.py sortie.html [module]
    M = importlib.import_module(sys.argv[2]).M if len(sys.argv) > 2 else motifs()
    cells = ''.join('<div><span class="b">%s</span><span class="p">%s</span><i>%s</i></div>' % (svg(c, 72), svg(c, 24), k) for k, c in M.items())
    open(sys.argv[1], 'w').write('<body style="background:#0a1118;color:#9ab;font:11px sans-serif;margin:8px"><style>div{display:inline-block;width:104px;text-align:center;margin:3px 0}'
        '.b{display:inline-block;background:#121c26;border-radius:50%;padding:12px;line-height:0}.p{display:inline-block;vertical-align:top;margin-left:-6px}i{display:block;font-style:normal;white-space:nowrap;overflow:hidden}</style>' + cells)
    print(len(M))
