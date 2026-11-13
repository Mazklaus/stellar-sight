// Imprime manuel.html en PDF avec Chromium (Playwright) une fois que
// Paged.js a fini la pagination. Usage : node print.js manuel.html manuel.pdf
// Playwright doit être installé (npm i -D playwright, puis npx playwright install chromium).
const path = require('path');
let chromium;
try { ({ chromium } = require('playwright')); } catch (e) {
  console.error("Playwright introuvable : npm i -D playwright && npx playwright install chromium");
  process.exit(1);
}
(async () => {
  const [src, out] = process.argv.slice(2);
  const browser = await chromium.launch();
  const page = await browser.newPage();
  page.on('console', m => { if (m.type() === 'error') console.error('[page]', m.text()); });
  await page.goto('file://' + path.resolve(src), { waitUntil: 'load' });
  await page.waitForFunction(() => window.__pagine === true, null, { timeout: 180000 });
  const n = await page.evaluate(() => document.querySelectorAll('.pagedjs_page').length);
  await page.pdf({ path: out, preferCSSPageSize: true, printBackground: true });
  console.log(`${n} pages`);
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
