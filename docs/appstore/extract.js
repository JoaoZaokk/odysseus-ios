// Lists every piece of text in the store images, for translation:
//   node docs/appstore/extract.js  →  docs/appstore/i18n/source.json
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..', '..');
(async () => {
  const html = fs.readFileSync(path.join(root, 'docs', 'mockups', 'odysseus-iphone.html'), 'utf8');
  const shots = fs.readFileSync(path.join(__dirname, 'shots.js'), 'utf8');
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 2100, height: 1500 } });
  await p.setContent('<!doctype html><html><head><meta charset="utf-8"></head><body>' + html + '</body></html>', { waitUntil: 'networkidle' });
  await p.addScriptTag({ content: shots });
  const keys = await p.evaluate(() => window.EXTRACT());
  fs.mkdirSync(path.join(__dirname, 'i18n'), { recursive: true });
  fs.writeFileSync(path.join(__dirname, 'i18n', 'source.json'), JSON.stringify(keys, null, 1) + '\n');
  console.log(Object.keys(keys).length, 'strings');
  await b.close();
})();
