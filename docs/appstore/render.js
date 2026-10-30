// Renders the App Store screenshots and the two promo images from the
// mockup's screens. Needs SF Pro installed (Apple's font package) so the
// text matches the app; Playwright with Chromium.
//
//   node docs/appstore/render.js [outDir]
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');
const page_ = path.join(root, 'docs', 'mockups', 'odysseus-iphone.html');
const out = path.resolve(process.argv[2] || path.join(root, 'docs', 'appstore', 'out'));

const SETS = [
  // dir, kind, scale (px per pt). The App Store sets carry the device frame
  // and a caption; `sem-moldura` keeps the bare screens.
  ['iphone-6.3', 'fiphone63', 3],   // 1206 × 2622
  ['iphone-6.9', 'fiphone69', 3],   // 1320 × 2868
  ['iphone-duo', 'fduo', 3],        // 1398 × 2034
  ['ipad-13', 'fipad', 2],          // 2064 × 2752
  ['sem-moldura/iphone-6.3', 'iphone63', 3],
  ['sem-moldura/iphone-6.9', 'iphone69', 3],
  ['sem-moldura/iphone-duo', 'duo', 3],
  ['sem-moldura/ipad-13', 'ipad', 2],
];
const NAMES = {
  iphone63: ['01-chat', '02-voz', '03-conversas', '04-brain', '05-calendario', '06-tasks', '07-cookbook', '08-nova-conversa'],
  duo: ['01-conversas', '02-chat', '03-voz', '04-brain', '05-calendario', '06-tasks'],
  ipad: ['01-chat', '02-voz', '03-brain', '04-calendario', '05-tasks', '06-cookbook'],
};
NAMES.iphone69 = NAMES.iphone63;
NAMES.fiphone63 = NAMES.fiphone69 = NAMES.iphone63;
NAMES.fduo = NAMES.duo;
NAMES.fipad = NAMES.ipad;

(async () => {
  const html = fs.readFileSync(page_, 'utf8');
  const shots = fs.readFileSync(path.join(__dirname, 'shots.js'), 'utf8');
  const browser = await chromium.launch();
  async function open(w, h, scale) {
    const p = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: scale, colorScheme: 'dark' });
    await p.setContent('<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body>' + html + '</body></html>', { waitUntil: 'networkidle' });
    await p.addScriptTag({ content: shots });
    await p.evaluate(() => document.fonts.ready);
    return p;
  }
  for (const [dir, kind, scale] of SETS) {
    fs.mkdirSync(path.join(out, dir), { recursive: true });
    const names = NAMES[kind];
    for (let i = 0; i < names.length; i++) {
      const probe = await open(400, 400, scale);
      const size = await probe.evaluate(([k, n]) => window.SHOT(k, n), [kind, i]);
      await probe.close();
      const p = await open(size.w, size.h, scale);
      await p.evaluate(([k, n]) => window.SHOT(k, n), [kind, i]);
      await p.waitForTimeout(150);
      await p.screenshot({ path: path.join(out, dir, names[i] + '.png'), clip: { x: 0, y: 0, width: size.w, height: size.h } });
      await p.close();
    }
  }
  fs.mkdirSync(path.join(out, 'promo'), { recursive: true });
  for (const k of ['wide', 'card']) {
    const p = await open(2000, k === 'wide' ? 857 : 1333, 1);
    await p.evaluate((kk) => window.SHOT('promo', kk), k);
    await p.waitForTimeout(150);
    await p.screenshot({ path: path.join(out, 'promo', 'promo-' + k + '.png'), clip: { x: 0, y: 0, width: 2000, height: k === 'wide' ? 857 : 1333 } });
    await p.close();
  }
  await browser.close();
  console.log('ok', out);
})();
