// Renders the App Store images and the two promo banners from the mockup's
// screens, one folder per store locale. Needs SF Pro installed (Apple's font
// package) so the text matches the app, a CJK font (Noto Sans CJK) for ja /
// ko / zh, and Playwright with Chromium.
//
//   node docs/appstore/render.js [outDir] [--langs=pt-BR,en-US]
//
// Translations live in i18n/<locale>.json ({ lang, strings }), keyed by the
// pt-BR text that extract.js lists; pt-BR renders the mockup as is.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');
const page_ = path.join(root, 'docs', 'mockups', 'odysseus-iphone.html');
const argv = process.argv.slice(2);
const out = path.resolve(argv.find(a => !a.startsWith('--')) || path.join(root, 'docs', 'appstore', 'out'));
const only = (argv.find(a => a.startsWith('--langs=')) || '').slice(8).split(',').filter(Boolean);

const LOCALES = ['pt-BR', 'en-US', 'es-ES', 'fr-FR', 'de-DE', 'it', 'nl-NL', 'ja', 'ko', 'zh-Hans', 'zh-Hant', 'ru'];
// The iPhone Duo set exists in these two only (it is optional until 2027).
const DUO_LOCALES = ['pt-BR', 'en-US'];

const SETS = [
  // dir, kind, scale (px per pt). Store sets carry the device frame and a
  // caption; `sem-moldura` (pt-BR only) keeps the bare screens.
  ['iphone-6.9', 'fiphone69', 3],   // 1320 × 2868
  ['iphone-6.3', 'fiphone63', 3],   // 1206 × 2622
  ['iphone-duo', 'fduo', 3],        // 1398 × 2034
  ['ipad-13', 'fipad', 2],          // 2064 × 2752
  ['sem-moldura/iphone-6.9', 'iphone69', 3],
  ['sem-moldura/iphone-6.3', 'iphone63', 3],
  ['sem-moldura/iphone-duo', 'duo', 3],
  ['sem-moldura/ipad-13', 'ipad', 2],
];
const NAMES = {
  iphone63: ['01-chat', '02-voz', '03-conversas', '04-brain', '05-calendario', '06-tasks', '07-nova-conversa'],
  duo: ['01-conversas', '02-chat', '03-voz', '04-brain', '05-calendario', '06-tasks'],
  ipad: ['01-chat', '02-voz', '03-brain', '04-calendario', '05-tasks'],
};
NAMES.iphone69 = NAMES.fiphone63 = NAMES.fiphone69 = NAMES.iphone63;
NAMES.fduo = NAMES.duo;
NAMES.fipad = NAMES.ipad;

(async () => {
  const html = fs.readFileSync(page_, 'utf8');
  const shots = fs.readFileSync(path.join(__dirname, 'shots.js'), 'utf8');
  const browser = await chromium.launch();

  for (const loc of LOCALES.filter(l => !only.length || only.includes(l))) {
    let i18n = null;
    if (loc !== 'pt-BR') {
      const file = path.join(__dirname, 'i18n', loc + '.json');
      if (!fs.existsSync(file)) { console.log('skip', loc, '(no i18n/' + loc + '.json)'); continue; }
      i18n = JSON.parse(fs.readFileSync(file, 'utf8'));
    }
    async function open(w, h, scale) {
      const p = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: scale, colorScheme: 'dark' });
      await p.setContent('<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body>' + html + '</body></html>', { waitUntil: 'networkidle' });
      if (i18n) await p.addScriptTag({ content: 'window.ODY_I18N = ' + JSON.stringify(i18n) + ';' });
      await p.addScriptTag({ content: shots });
      await p.evaluate(() => document.fonts.ready);
      return p;
    }
    async function shoot(kind, i, w, h, scale, file) {
      const p = await open(w, h, scale);
      await p.evaluate(([k, n]) => window.SHOT(k, n), [kind, i]);
      await p.evaluate(() => document.fonts.ready);
      await p.waitForTimeout(150);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      await p.screenshot({ path: file, clip: { x: 0, y: 0, width: w, height: h } });
      await p.close();
    }
    const SIZE = { iphone63: [402, 874], fiphone63: [402, 874], iphone69: [440, 956], fiphone69: [440, 956],
      duo: [466, 678], fduo: [466, 678], ipad: [1032, 1376], fipad: [1032, 1376] };
    for (const [dir, kind, scale] of SETS) {
      if (dir.startsWith('sem-moldura') && loc !== 'pt-BR') continue;
      if (/duo/.test(kind) && !DUO_LOCALES.includes(loc)) continue;
      const [w, h] = SIZE[kind];
      const names = NAMES[kind];
      for (let i = 0; i < names.length; i++) {
        await shoot(kind, i, w, h, scale, path.join(out, loc, dir, names[i] + '.png'));
      }
    }
    for (const k of ['wide', 'card']) {
      await shoot('promo', k, 2000, k === 'wide' ? 857 : 1333, 1, path.join(out, loc, 'promo', 'promo-' + k + '.png'));
    }
    console.log('ok', loc);
  }
  await browser.close();
})();
