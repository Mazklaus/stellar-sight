# Planche de relecture : toutes les icônes, encadrées, par famille. Usage : python3 tools/icons/planche.py sortie.html
import sys, os, json, glob, html as H
ICI = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, ICI)
DATA = os.path.join(ICI, '..', '..', 'data')
from composer import icone_svg
from table import TABLE

def J(f): return json.load(open(os.path.join(DATA, f)))
tech = {}
for f in J('technologies.json')['catalog']:
    tech.update({k: v for k, v in json.load(open(os.path.join(DATA, 'tech', f + '.json')))['technologies'].items() if isinstance(v, dict)})
dom = {d['id']: d for d in J('technologies.json')['domains']}
fa = J('faiths.json'); ar = J('archaeology.json'); go = J('goods.json')
def noms(x, champ='label'):
    if isinstance(x, list): return {v['id']: v[champ] for v in x}
    return {k: v[champ] for k, v in x.items() if isinstance(v, dict)}

CADRES = {'disque': '<circle cx="48" cy="48" r="44"/>', 'carre': '<rect x="6" y="6" width="84" height="84"/>',
          'losange': '<polygon points="48,2 94,48 48,94 2,48"/>', 'hexa': '<polygon points="48,3 87,25.5 87,70.5 48,93 9,70.5 9,25.5"/>',
          'ogive': '<path d="M10 90 V44 C10 22 28 8 48 4 C68 8 86 22 86 44 V90 Z"/>',
          'coins': '<polygon points="20,6 76,6 90,20 90,76 76,90 20,90 6,76 6,20"/>',
          'double': '<circle cx="48" cy="48" r="44"/><circle cx="48" cy="48" r="38" class="fin"/>'}
def icone(cle, forme, teinte, t=64):
    g = 0.56 if forme == 'losange' else (0.6 if forme in ('hexa', 'ogive') else 0.64)
    return ('<span class="ic" style="width:%dpx;height:%dpx;--t:%s"><svg class="cadre" viewBox="0 0 96 96" width="%d" height="%d" aria-hidden="true">%s</svg>'
            '<span class="gl">%s</span></span>' % (t, t, teinte, t, t, CADRES[forme], icone_svg(cle, round(t * g))))
def grille(fam, items, forme, teinte):
    return '<div class="grille">%s</div>' % ''.join('<figure data-n="%s">%s<figcaption>%s</figcaption></figure>'
        % (H.escape(n.lower(), True), icone(fam + '/' + k, forme, teinte), H.escape(n)) for k, n in items)

sections, nav = '', ''
def section(sid, titre, corps, nb):
    global sections, nav
    sections += '<section id="%s"><header><h2>%s</h2><p class="nb">%d</p></header>%s</section>' % (sid, titre, nb, corps)
    nav += '<a href="#%s">%s <b>%d</b></a>' % (sid, titre, nb)

corps = ''
for d in J('technologies.json')['domains']:
    its = [(k, v['label']) for k, v in tech.items() if v.get('domain') == d['id']]
    corps += '<h3 style="color:%s">%s <span>%d</span></h3>%s' % (d['color'], H.escape(d['label']), len(its), grille('tech', its, 'disque', d['color']))
section('technologies', 'Technologies', corps, len(tech))
b = noms(J('buildings.json')); section('batiments', 'Bâtiments', grille('batiment', b.items(), 'carre', 'var(--pierre)'), len(b))
dd = J('deeds.json'); corps = ''
SORTES = [('first', 'Premières'), ('record', 'Records'), ('layer', 'Hauts faits de peuple'), ('infamous', 'Infamies'), ('secret', 'Secrets')]
for s, t in SORTES:
    its = [(k, v['label']) for k, v in dd['deeds'].items() if isinstance(v, dict) and v.get('sort') == s]
    corps += '<h3>%s <span>%d</span></h3>%s' % (t, len(its), grille('haut_fait', its, 'losange', 'var(--cyan)'))
section('hauts-faits', 'Hauts faits', corps, len(noms(dd['deeds'])))
r = [(x['id'], x['name']) for x in J('relics.json')['relics']]; section('reliques', 'Reliques', grille('relique', r, 'hexa', 'var(--rel)'), len(r))
p = noms(fa['precepts']); n = noms(fa['natures']['list'])
section('foi', 'Préceptes et natures de foi', '<h3>Préceptes <span>%d</span></h3>%s<h3>Natures <span>%d</span></h3>%s'
        % (len(p), grille('precepte', p.items(), 'ogive', 'var(--foi)'), len(n), grille('nature', n.items(), 'ogive', 'var(--foi)')), len(p) + len(n))
corps, nb = '', 0
for cle, t, champ in [('site_types', 'Types de sites', 'label'), ('disparus', 'Disparus', 'label'), ('natures', 'Natures de fragments', 'label'), ('methods', 'Méthodes', 'label')]:
    its = [(k, (v.get('label') or v.get('name') or k)) for k, v in ar[cle].items() if isinstance(v, dict)]
    its = [(k, n[0].upper() + n[1:]) for k, n in its]; nb += len(its)
    corps += '<h3>%s <span>%d</span></h3>%s' % (t, len(its), grille('fouille', its, 'coins', 'var(--pierre)'))
section('fouilles', 'Fouilles', corps, nb)
l = noms(go['luxuries']); s = noms(go['strategic'])
section('ressources', 'Luxes et ressources stratégiques', grille('ressource', list(l.items()) + list(s.items()), 'double', 'var(--rel)'), len(l) + len(s))

page = '''<title>Icônes de Stellar Sight</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Source+Sans+3:wght@300;400;600&display=swap">
<style>
/* Planche d'atelier sombre : un champ de recherche, puis une grille d'icônes encadrées par famille. */
:root { color-scheme: dark; --fond: #0a1118; --panneau: #121c26; --filet: #2a3a48; --texte: #dfe7ee; --doux: #8c9dab; --cyan: #5fdbe9;
  --rel: #e3c16a; --foi: #b98be6; --pierre: #9fb0bd; --ui: "Source Sans 3", "Segoe UI", system-ui, sans-serif; }
body { background: var(--fond); color: var(--texte); font-family: var(--ui); font-weight: 300; font-size: 16px; line-height: 1.5; }
.page { max-width: 1120px; margin: 0 auto; padding-block: 32px 80px; display: flex; flex-direction: column; gap: 36px;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
h1 { font-weight: 300; font-size: 34px; margin: 0; text-wrap: balance; }
h2 { font-weight: 400; font-size: 15px; letter-spacing: .16em; text-transform: uppercase; margin: 0; }
h3 { font-weight: 400; font-size: 15px; margin: 14px 0 0; } h3 span, .nb { color: var(--doux); font-size: 14px; font-variant-numeric: tabular-nums; }
p { margin: 0; max-width: 70ch; } .chapo { color: var(--doux); font-size: 17px; }
.tete { display: flex; flex-direction: column; gap: 12px; }
nav { display: flex; flex-wrap: wrap; gap: 8px; } nav a { color: var(--texte); text-decoration: none; border: 1px solid var(--filet); padding: 4px 12px; font-size: 14px; }
nav a:hover { border-color: var(--cyan); } nav b { color: var(--doux); font-weight: 400; margin-left: 4px; }
input { font: inherit; color: var(--texte); background: var(--panneau); border: 1px solid var(--filet); padding: 8px 12px; width: 100%; max-width: 360px; box-sizing: border-box; }
input:focus { outline: 2px solid var(--cyan); outline-offset: 1px; }
section { display: flex; flex-direction: column; gap: 14px; scroll-margin-top: 16px; }
section > header { display: flex; justify-content: space-between; align-items: baseline; gap: 16px; border-bottom: 1px solid var(--filet); padding-bottom: 8px; }
.grille { display: grid; grid-template-columns: repeat(auto-fill, minmax(104px, 1fr)); gap: 18px 8px; }
figure { margin: 0; display: flex; flex-direction: column; align-items: center; gap: 6px; text-align: center; }
figcaption { font-size: 12.5px; line-height: 1.25; overflow-wrap: anywhere; }
.ic { position: relative; display: inline-flex; align-items: center; justify-content: center; flex: none; }
.ic .cadre { position: absolute; inset: 0; fill: #16222d; stroke: var(--t); stroke-width: 2; vector-effect: non-scaling-stroke; }
.ic .cadre * { vector-effect: non-scaling-stroke; } .ic .cadre .fin { fill: none; stroke-width: 1; opacity: .7; }
.ic .gl { position: relative; display: inline-flex; }
</style>
<div class="page">
  <div class="tete">
    <h1>Icônes de Stellar Sight</h1>
    <p class="chapo">Les {{TOTAL}} icônes du jeu, dans le style validé sur l'échantillon. Chaque entrée a son pictogramme. Quand deux entrées se ressemblent, un petit insigne en bas à droite ou des crans de rang les distinguent.</p>
    <input id="q" type="search" placeholder="Chercher une icône par son nom" aria-label="Chercher une icône par son nom">
    <nav>{{NAV}}</nav>
  </div>
  {{BODY}}
</div>
<script>
document.getElementById('q').addEventListener('input', function () {
  var q = this.value.trim().toLowerCase();
  document.querySelectorAll('figure').forEach(function (f) { f.hidden = q !== '' && f.dataset.n.indexOf(q) < 0; });
});
</script>
'''
open(sys.argv[1], 'w').write(page.replace('{{TOTAL}}', str(len(TABLE))).replace('{{NAV}}', nav).replace('{{BODY}}', sections))
print(len(TABLE), os.path.getsize(sys.argv[1]))
