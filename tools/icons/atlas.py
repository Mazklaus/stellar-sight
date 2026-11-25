# Fabrique la planche d'images du jeu : assets/icons/atlas.png (pictogrammes blancs sur fond transparent)
# et assets/icons/atlas.json (case de chaque entrée). Usage : python3 tools/icons/atlas.py
# Le rendu passe par Chromium (Playwright pour Node), seul à gérer les réserves des SVG de façon sûre.
import sys, os, json, subprocess, tempfile
ICI = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, ICI)
from composer import icone_svg
from table import TABLE
from verifier import verifier

CASE, COLS = 96, 29
SORTIE = os.path.join(ICI, '..', '..', 'assets', 'icons')

if not verifier(): sys.exit(1)
cles = sorted(TABLE)
lignes = (len(cles) + COLS - 1) // COLS
html = ('<body style="margin:0;background:transparent"><div style="width:%dpx;line-height:0;font-size:0">%s</div>'
        % (CASE * COLS, ''.join(icone_svg(k, CASE) for k in cles)))
os.makedirs(SORTIE, exist_ok=True)
with tempfile.TemporaryDirectory() as d:
    open(os.path.join(d, 'p.html'), 'w').write(html)
    js = ("const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();"
          "const p=await b.newPage({viewport:{width:%d,height:%d}});await p.goto('file://%s');"
          "await p.screenshot({path:'%s',omitBackground:true,clip:{x:0,y:0,width:%d,height:%d}});await b.close();})();"
          % (CASE * COLS, CASE * lignes, os.path.join(d, 'p.html'), os.path.join(SORTIE, 'atlas.png'), CASE * COLS, CASE * lignes))
    open(os.path.join(d, 'r.js'), 'w').write(js)
    subprocess.run(['node', os.path.join(d, 'r.js')], check=True, cwd=os.environ.get('PLAYWRIGHT_DIR', d))
json.dump({'_doc': "Planche des pictogrammes, produite par tools/icons/atlas.py. Ne pas modifier à la main : changer tools/icons/table.py ou les motifs, puis relancer.",
           'cell': CASE, 'cols': COLS, 'index': {k: i for i, k in enumerate(cles)}},
          open(os.path.join(SORTIE, 'atlas.json'), 'w'), ensure_ascii=False, separators=(',', ':'))
print(len(cles), 'pictogrammes,', COLS, 'x', lignes, 'cases')
