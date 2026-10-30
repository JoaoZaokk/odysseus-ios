// Runs inside docs/mockups/odysseus-iphone.html (injected by render.js) and
// turns one of its screens into a single full-bleed App Store image.
(function () {
  var O = window.ODY;
  var css = document.createElement('style');
  css.textContent = [
    'body.shot { padding: 0 !important; margin: 0; background: #262624; overflow: hidden; }',
    'body.shot::before { display: none; }',
    'html:lang(ja) body.shot { --cjk: "Hiragino Sans", "Noto Sans CJK JP"; } html:lang(ko) body.shot { --cjk: "Apple SD Gothic Neo", "Noto Sans CJK KR"; }',
    'html:lang(zh-Hans) body.shot { --cjk: "PingFang SC", "Noto Sans CJK SC"; } html:lang(zh-Hant) body.shot { --cjk: "PingFang TC", "Noto Sans CJK TC"; }',
    'html[lang] body.shot { --ui: -apple-system, "SF Pro Text", var(--cjk, "SF Pro"), system-ui, sans-serif; }',
    // Korean wraps at spaces, as the app does; Chromium would split syllables.
    'html:lang(ko) body.shot { word-break: keep-all; }',
    // CJK has no italic: the slant would be synthetic. The border marks the quote.
    'html:lang(ja) .quote, html:lang(ko) .quote, html:lang(zh-Hans) .quote, html:lang(zh-Hant) .quote { font-style: normal; }',
    // The CJK fallback's tall default line box pushed the promo subline onto the phone.
    'html:lang(ja) .promo :is(h1, h2), html:lang(ko) .promo :is(h1, h2), html:lang(zh-Hans) .promo :is(h1, h2), html:lang(zh-Hant) .promo :is(h1, h2) { line-height: 1.15; }',
    'html[lang] .canvas, html[lang] .promo { font-family: "SF Pro Display", var(--cjk, "SF Pro Display"), sans-serif !important; }',
    'html[lang] .canvas .cap p { font-family: "SF Pro Text", var(--cjk, "SF Pro Text"), sans-serif !important; }',
    'body.shot > *:not(#shot) { display: none !important; }',
    '#shot { position: fixed; inset: 0; overflow: hidden; }',
    // Screens: no bezel, no island, square corners, exact point size.
    '#shot > .phone, #shot > .duo { margin: 0; border-radius: 0; box-shadow: none; }',
    '#shot > .phone .island, #shot > .duo .rail .pill { display: none; }',
    // iPad split view
    '.ipad { width: 1032px; height: 1376px; background: var(--bg); position: relative; overflow: hidden; display: flex; flex-direction: column; font-family: var(--app-font); color: var(--fg); -webkit-font-smoothing: antialiased; }',
    '.ipad .istatus { height: 32px; flex: none; display: flex; align-items: center; justify-content: space-between; padding: 0 22px 0 28px; font-family: var(--ui); font-size: 15px; font-weight: 600; }',
    '.ipad .istatus span { display: inline-flex; gap: 6px; align-items: center; }',
    '.ipad .istatus small { font-weight: 500; font-size: 15px; margin-left: 6px; }',
    '.ipad .split { flex: 1; display: flex; min-height: 0; }',
    '.ipad .side { width: 320px; flex: none; background: #2c2c2a; display: flex; flex-direction: column; overflow: hidden; border-right: 1px solid rgba(245,244,240,.06); }',
    '.ipad .side .nav, .ipad .detail .nav { margin-top: 0; }',
    '.ipad .side .row { padding-top: 9px; padding-bottom: 9px; }',
    // One line, like the app's search field ("Rechercher des conversations").
    '.ipad .side .search { white-space: nowrap; overflow: hidden; }',
    '.ipad .side .row.on { background: rgba(198,97,63,.14); box-shadow: inset 3px 0 0 var(--accent); }',
    '.ipad .side .row.on::before, .ipad .side .row.on + .row::before { display: none; }',
    '.ipad .detail { flex: 1; min-width: 0; display: flex; flex-direction: column; position: relative; }',
    '.ipad .detail .body, .ipad .detail .composer { width: 100%; max-width: 720px; margin: 0 auto; }',
    '.ipad .detail .nav .t { max-width: 420px; }',
    '.ipad .home { width: 320px; }',
    '.ipad .vsheet { position: absolute; left: 50%; top: 50%; width: 580px; height: 780px; transform: translate(-50%, -50%); border-radius: 38px; overflow: hidden; box-shadow: 0 30px 80px rgba(0,0,0,.55); z-index: 40; }',
    '.ipad .vsheet .behind { display: none; }',
    '.ipad .vsheet .sheet { inset: 0; border-radius: 38px; }',
    '.ipad .dim { position: absolute; inset: 0; background: rgba(0,0,0,.45); z-index: 39; }',
    // Promo banners
    '.promo { position: relative; overflow: hidden; background: radial-gradient(120% 90% at 50% 105%, #7a3a22 0%, #3a2016 35%, #1d1714 62%, #161412 100%); font-family: "SF Pro Display", var(--ui); color: #f5f4f0; }',
    '.promo h1 { margin: 0; text-align: center; font-weight: 700; letter-spacing: -0.025em; }',
    '.promo h2 { margin: 0; text-align: center; font-weight: 600; color: #e0896a; letter-spacing: -0.015em; }',
    '.promo .ph { position: absolute; transform-origin: top left; }',
    '.promo .ph .phone { margin: 0; }'
  ].join('\n');
  document.head.appendChild(css);

  var ic = O.ic;
  var istatus = '<div class="istatus"><span>9:41<small>sex. 10 de out.</small></span><span>' +
    '<svg width="18" height="12" viewBox="0 0 18 12"><rect x="0" y="8" width="3" height="4" rx="1" fill="currentColor"/><rect x="5" y="5.5" width="3" height="6.5" rx="1" fill="currentColor"/><rect x="10" y="3" width="3" height="9" rx="1" fill="currentColor"/><rect x="15" y="0" width="3" height="12" rx="1" fill="currentColor"/></svg>' +
    '<svg width="16" height="12" viewBox="0 0 16 12"><path d="M8 11.5 5.6 9a3.4 3.4 0 0 1 4.8 0zM3.5 6.9a6.4 6.4 0 0 1 9 0l-1.4 1.4a4.4 4.4 0 0 0-6.2 0zM1.3 4.7a9.5 9.5 0 0 1 13.4 0l-1.4 1.4a7.5 7.5 0 0 0-10.6 0z" fill="currentColor"/></svg>' +
    '<svg width="27" height="13" viewBox="0 0 27 13"><rect x=".5" y=".5" width="23" height="12" rx="3.8" fill="none" stroke="currentColor" opacity=".4"/><rect x="2" y="2" width="20" height="9" rx="2.5" fill="currentColor"/></svg></span></div>';

  var EXTRA = {
    envelope: '<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="m3.5 6.5 8.5 6.5 8.5-6.5"/>',
    checklist: '<path d="m3.5 6.5 1.5 1.5 3-3M3.5 13.5l1.5 1.5 3-3M11 7h10M11 14h10M11 20h10"/>',
    books: '<rect x="3" y="4" width="4.5" height="16" rx="1"/><rect x="8.5" y="4" width="4.5" height="16" rx="1"/><path d="m14.5 5.2 4.3-1.1 3.4 15.3-4.3 1.1z"/>',
    split: '<rect x="3" y="4" width="18" height="16" rx="2.5"/><path d="M12 4v16"/>',
    fork: '<path d="M7 3v8M5 3v5a2 2 0 0 0 4 0V3M7 11v10M17 21V3c-2.2 1.5-3 4-3 7v3h3"/>',
    sidebar: '<rect x="3" y="4" width="18" height="16" rx="2.5"/><path d="M9 4v16M5.5 8h1.5M5.5 11h1.5"/>'
  };
  function icon(n) {
    if (!EXTRA[n]) return ic(n);
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + EXTRA[n] + '</svg>';
  }
  function sideRow(name, title, on) {
    return '<div class="row' + (on ? ' on' : '') + '"><span class="lead">' + icon(name) + '</span><div class="main"><span class="ttl">' + title + '</span></div></div>';
  }
  function chatRow(title, model, time, on) {
    return '<div class="row' + (on ? ' on' : '') + '"><div class="main"><span class="ttl">' + title + '</span><span class="sub">' + model + '</span></div><span class="meta">' + time + '</span></div>';
  }
  function sidebar(active) {
    var sec = [['brain', 'Brain'], ['note', 'Notes'], ['cal', 'Calendário'], ['photo', 'Galeria'], ['envelope', 'Email'],
      ['checklist', 'Tasks'], ['books', 'Library'], ['split', 'Comparar'], ['fork', 'Cookbook']];
    return '<div class="side">' + O.nav(O.g('gear'), 'Odysseus', '', O.g('compose')) +
      '<div class="search">' + ic('search') + 'Buscar conversas</div>' +
      sideRow('deep', 'Deep Search', false) +
      '<div class="sechead">' + ic('down') + 'Espaços</div>' +
      sec.map(function (x) { return sideRow(x[0], x[1], active === x[1]); }).join('') +
      '<div class="sechead">' + ic('down') + 'Hoje<span class="n">2</span></div>' +
      chatRow('Emails de hoje', 'mimo-v2.6-pro', '09:35', active === 'chat') +
      chatRow('Roteiro de 3 dias em Lisboa', 'mimo-v2.6-flash', '08:11', false) +
      '</div>';
  }

  function ipad(active, detail, extra) {
    var back = O.g('back'), toggle = '<span class="gbtn">' + icon('sidebar') + '</span>';
    detail = detail.split(back).join(toggle);
    return '<div class="ipad">' + istatus + '<div class="split">' + sidebar(active) +
      '<div class="detail">' + detail + '</div></div>' + (extra || '') + '<div class="home"></div></div>';
  }

  var S = O.S, D = O.D;
  // Cookbook stays out: its packages are third-party AI engines by name.
  var IPHONE = [2, 4, 0, 6, 7, 8, 1];   // Chat, Voz, Conversas, Brain, Calendário, Tasks, Nova conversa
  var IPAD = [
    function () { return ipad('chat', S[2].h); },
    function () { return ipad('chat', S[2].h, '<div class="dim"></div><div class="vsheet">' + S[4].h + '</div>'); },
    function () { return ipad('Brain', S[6].h); },
    function () { return ipad('Calendário', S[7].h); },
    function () { return ipad('Tasks', S[8].h); }
  ];

  function framed(i, w, h) {
    var el = O.phone(S[i].h);
    return el.replace('<div class="phone">', '<div class="phone" style="width:' + w + 'px;height:' + h + 'px">');
  }

  function promo(kind) {
    var W = 2000, H = kind === 'wide' ? 857 : 1333;
    var html = '<div class="promo" style="width:' + W + 'px;height:' + H + 'px">';
    if (kind === 'wide') {
      html += '<h1 style="font-size:84px;padding-top:44px">Seu servidor de IA num app nativo</h1>' +
        '<h2 style="font-size:46px;margin-top:6px">Sem nuvem de terceiros.</h2>';
      // Every device, rotated corners included, stays inside the canvas.
      var sc = 0.56, y = 258, dw = 418 * sc;
      html += phoneAt(2, 560, y + 34, sc, -6) + phoneAt(4, 1000 - dw / 2, y, sc, 0) + phoneAt(6, 1440 - dw + 20, y + 34, sc, 6);
    } else {
      html += '<h1 style="font-size:96px;padding-top:70px">Seu servidor de IA num app nativo</h1>' +
        '<h2 style="font-size:54px;margin-top:10px">Sem nuvem de terceiros.</h2>';
      var s2 = 0.98, y2 = 296, w2 = 418 * s2;
      html += phoneAt(2, 250, y2 + 60, s2 * 0.94, 0) + phoneAt(4, 1000 - w2 / 2, y2, s2, 0) + phoneAt(6, 1750 - 418 * s2 * 0.94, y2 + 60, s2 * 0.94, 0);
    }
    return html + '</div>';
  }
  function phoneAt(i, x, y, scale, rot) {
    var d = iphoneDevice(O.phone(S[i].h), 402, 874);
    return '<div class="dev" style="left:' + x + 'px;top:' + y + 'px;width:' + d.w + 'px;height:' + d.h + 'px;transform:scale(' + scale + ') rotate(' + rot + 'deg)">' + d.html + '</div>';
  }

  // ---------- App Store images with the device frame ----------
  var css2 = document.createElement('style');
  css2.textContent = [
    '.canvas { position: relative; overflow: hidden; background: radial-gradient(130% 75% at 50% 100%, #8a4227 0%, #4a2618 30%, #221a16 62%, #171513 100%); font-family: "SF Pro Display", var(--ui); color: #f5f4f0; -webkit-font-smoothing: antialiased; }',
    '.canvas .cap { position: absolute; left: 0; right: 0; text-align: center; padding: 0 6%; }',
    '.canvas .cap h1 { margin: 0; font-weight: 700; letter-spacing: -0.02em; text-wrap: balance; line-height: 1.08; }',
    '.canvas .cap p { margin: 0; font-family: "SF Pro Text", var(--ui); font-weight: 500; color: #e3a58d; letter-spacing: -0.01em; text-wrap: balance; line-height: 1.25; }',
    '.dev { position: absolute; transform-origin: top left; }',
    '.dev .shell { position: relative; background: #000; box-shadow: 0 0 0 1px #1a1a19, 0 0 0 3px #6b6862, 0 0 0 4px #2e2d2a, 0 40px 70px -10px rgba(0,0,0,.6); }',
    '.dev .shell::after { content: ""; position: absolute; inset: 0; border-radius: inherit; box-shadow: inset 0 0 0 1px rgba(255,255,255,.06); pointer-events: none; }',
    '.dev .hinge { position: absolute; left: -12px; top: 5%; bottom: 5%; width: 9px; border-radius: 5px; background: linear-gradient(90deg, #1c1b19, #6b6862 45%, #2a2926 75%, #121211); }',
    '.dev .cam { position: absolute; width: 9px; height: 9px; border-radius: 50%; background: radial-gradient(circle at 35% 35%, #2b3a4a, #050505 70%); }',
    '.dev .shell > .phone, .dev .shell > .duo, .dev .shell > .ipad { margin: 0; box-shadow: none; position: relative; }',
    '.dev .btn { position: absolute; background: linear-gradient(90deg, #3a3936, #85827b 50%, #3a3936); border-radius: 3px; }',
    '.dev .btn.h { background: linear-gradient(180deg, #3a3936, #85827b 50%, #3a3936); }'
  ].join('\n');
  document.head.appendChild(css2);

  var CAP = {
    chat: ['Converse com seu servidor de IA', 'Respostas ao vivo, com busca na web e fotos.'],
    voz: ['Fale e ouça a resposta', 'Modo de voz mãos-livres, com interrupção natural.'],
    conversas: ['Todas as conversas à mão', 'Busque no conteúdo e fixe as favoritas.'],
    brain: ['Uma memória que é sua', 'O que o assistente lembra de você, organizado.'],
    calendario: ['Agenda em linguagem natural', 'Escreva “reunião amanhã 14h” e pronto.'],
    tasks: ['Tarefas que rodam sozinhas', 'Pause, retome ou rode agora.'],
    nova: ['Seu servidor no bolso', 'Conversas e memórias no seu servidor.']
  };
  var IPHONE_CAP = ['chat', 'voz', 'conversas', 'brain', 'calendario', 'tasks', 'nova'];
  var DUO_CAP = ['conversas', 'chat', 'voz', 'brain', 'calendario', 'tasks'];
  var IPAD_CAP = ['chat', 'voz', 'brain', 'calendario', 'tasks'];

  // Each device drawn at its real point size; the canvas scales it to fit.
  function iphoneDevice(inner, w, h) {
    var b = 8, r = 62 + b;
    var x = function (side, top, len, wid) {
      return '<span class="btn" style="' + side + ':-' + (wid + 3) + 'px;top:' + top + 'px;width:' + wid + 'px;height:' + len + 'px"></span>';
    };
    return { w: w + 2 * b, h: h + 2 * b, html:
      '<div class="shell" style="padding:' + b + 'px;border-radius:' + r + 'px">' + inner +
      x('left', 150, 32, 3) + x('left', 210, 60, 3) + x('left', 284, 60, 3) +
      x('right', 236, 96, 3) + x('right', 520, 54, 3) + '</div>' };
  }
  function duoDevice(inner) {
    // The fold sits on the left: square corners there and a hinge spine.
    var b = 7;
    return { w: 466 + 2 * b, h: 678 + 2 * b, html:
      '<div class="shell" style="padding:' + b + 'px;border-radius:' + (10 + b) + 'px ' + (59 + b) + 'px ' + (59 + b) + 'px ' + (10 + b) + 'px">' + inner +
      '<span class="btn h" style="top:-7px;left:120px;width:60px;height:4px"></span>' +
      '<span class="btn" style="right:-7px;top:150px;width:3px;height:70px"></span><span class="hinge"></span></div>' };
  }
  function ipadDevice(inner) {
    var b = 20;
    return { w: 1032 + 2 * b, h: 1376 + 2 * b, html:
      '<div class="shell" style="padding:' + b + 'px;border-radius:' + (30 + b) + 'px">' +
      inner.replace('<div class="ipad">', '<div class="ipad" style="border-radius:30px">') +
      '<span class="btn h" style="top:-7px;right:120px;width:56px;height:4px"></span>' +
      '<span class="btn" style="right:-7px;top:110px;width:4px;height:50px"></span>' +
      '<span class="btn" style="right:-7px;top:172px;width:4px;height:50px"></span>' +
      '<span class="cam" style="right:5px;top:calc(50% - 4px)"></span></div>' };
  }

  // The device is sized for a two-line headline in every image of a set, so
  // the frames line up when the set is scrolled; a one-line caption sits
  // centred in that band instead of floating at the top.
  function canvas(W, H, cap, dev, o) {
    var band = o.capTop + o.h1 * 1.08 * o.lines + o.gap + o.p * 1.25 + o.afterCap;
    var s = Math.min((H - band - o.bottom) / dev.h, (W * o.maxW) / dev.w);
    var x = (W - dev.w * s) / 2;
    return '<div class="canvas" style="width:' + W + 'px;height:' + H + 'px">' +
      '<div class="cap" data-band="' + (band - o.afterCap / 2) + '" style="top:' + o.capTop + 'px"><h1 style="font-size:' + o.h1 + 'px">' + cap[0] + '</h1>' +
      '<p style="font-size:' + o.p + 'px;margin-top:' + o.gap + 'px">' + cap[1] + '</p></div>' +
      '<div class="dev" style="left:' + x + 'px;top:' + band + 'px;width:' + dev.w + 'px;height:' + dev.h + 'px;transform:scale(' + s + ')">' + dev.html + '</div></div>';
  }
  function centreCaptions() {
    document.querySelectorAll('.canvas .cap').forEach(function (c) {
      var band = Number(c.getAttribute('data-band')), h1 = c.querySelector('h1'), p = c.querySelector('p');
      // A longer translation shrinks instead of running into the device.
      for (var n = 0; n < 30 && c.offsetHeight > band - 12; n++) {
        h1.style.fontSize = (parseFloat(getComputedStyle(h1).fontSize) * 0.96) + 'px';
        p.style.fontSize = (parseFloat(getComputedStyle(p).fontSize) * 0.97) + 'px';
      }
      c.style.top = Math.max(10, (band - c.offsetHeight) / 2) + 'px';
    });
  }

  function phoneScreen(i, w, h) {
    return O.phone(S[i].h).replace('<div class="phone">', '<div class="phone" style="width:' + w + 'px;height:' + h + 'px">');
  }

  var FRAMED = {
    fiphone63: function (i) { return { w: 402, h: 874, html: canvas(402, 874, CAP[IPHONE_CAP[i]], iphoneDevice(phoneScreen(IPHONE[i], 402, 874), 402, 874),
      { capTop: 44, h1: 27, lines: 2, gap: 8, p: 14, afterCap: 30, bottom: 30, maxW: 0.86 }) }; },
    fiphone69: function (i) { return { w: 440, h: 956, html: canvas(440, 956, CAP[IPHONE_CAP[i]], iphoneDevice(phoneScreen(IPHONE[i], 440, 956), 440, 956),
      { capTop: 48, h1: 29, lines: 2, gap: 9, p: 15, afterCap: 32, bottom: 32, maxW: 0.86 }) }; },
    fduo: function (i) { return { w: 466, h: 678, html: canvas(466, 678, CAP[DUO_CAP[i]], duoDevice(O.duo(D[i].h, D[i].rail)),
      { capTop: 22, h1: 23, lines: 1, gap: 5, p: 15, afterCap: 20, bottom: 20, maxW: 0.9 }) }; },
    fipad: function (i) { return { w: 1032, h: 1376, html: canvas(1032, 1376, CAP[IPAD_CAP[i]], ipadDevice(IPAD[i]()),
      { capTop: 64, h1: 56, lines: 1, gap: 14, p: 30, afterCap: 46, bottom: 46, maxW: 0.9 }) }; }
  };

  // ---------- translation ----------
  // A "text container" is an element with text of its own. Its whole inner
  // HTML is the unit of translation, with each icon swapped for {0}, {1}… so
  // word order can change around them and bold spans stay whole.
  var SVG = /<svg[\s\S]*?<\/svg>/g;
  function ownText(el) {
    for (var n = el.firstChild; n; n = n.nextSibling) if (n.nodeType === 3 && n.nodeValue.trim()) return true;
    return false;
  }
  function keyOf(el) {
    var svgs = [], k = el.innerHTML.replace(SVG, function (m) { svgs.push(m); return '{' + (svgs.length - 1) + '}'; });
    return { key: k.replace(/\s+/g, ' ').trim(), svgs: svgs };
  }
  function eachContainer(root, fn) {
    (function walk(el) {
      for (var c = el.firstElementChild; c; c = c.nextElementSibling) {
        if (c.tagName.toLowerCase() === 'svg') continue;
        if (ownText(c)) fn(c); else walk(c);
      }
    })(root);
  }
  function translate(root, dict) {
    eachContainer(root, function (el) {
      var k = keyOf(el), t = dict[k.key];
      if (t == null) return;
      el.innerHTML = t.replace(/\{(\d+)\}/g, function (_, n) { return k.svgs[Number(n)] || ''; });
    });
  }
  window.EXTRACT = function () {
    var out = {}, kinds = { fiphone63: IPHONE.length, fduo: D.length, fipad: IPAD.length };
    function grab(label) {
      eachContainer(document.getElementById('shot'), function (el) {
        var k = keyOf(el).key;
        if (!(k in out)) out[k] = label;
      });
    }
    Object.keys(kinds).forEach(function (kind) {
      for (var i = 0; i < kinds[kind]; i++) { window.SHOT(kind, i, true); grab(kind + ' #' + (i + 1)); }
    });
    ['wide', 'card'].forEach(function (k) { window.SHOT('promo', k, true); grab('promo ' + k); });
    return out;
  };

  window.SHOT = function (kind, i, raw) {
    var L = window.ODY_I18N;
    if (L && L.lang) document.documentElement.lang = L.lang;
    document.body.setAttribute('data-font', 'sf');
    document.body.classList.add('shot');
    var box = document.getElementById('shot') || document.body.appendChild(Object.assign(document.createElement('div'), { id: 'shot' }));
    var html, w, h;
    if (kind === 'iphone63') { html = framed(IPHONE[i], 402, 874); w = 402; h = 874; }
    else if (kind === 'iphone69') { html = framed(IPHONE[i], 440, 956); w = 440; h = 956; }
    else if (kind === 'duo') { html = O.duo(D[i].h, D[i].rail); w = 466; h = 678; }
    else if (kind === 'ipad') { html = IPAD[i](); w = 1032; h = 1376; }
    else if (kind === 'promo') { html = promo(i); w = 2000; h = i === 'wide' ? 857 : 1333; }
    else if (FRAMED[kind]) { var f = FRAMED[kind](i); html = f.html; w = f.w; h = f.h; }
    box.innerHTML = html;
    if (L && L.strings && !raw) translate(box, L.strings);
    centreCaptions();
    return { w: w, h: h };
  };
  window.SHOT_COUNTS = { iphone63: IPHONE.length, iphone69: IPHONE.length, duo: D.length, ipad: IPAD.length,
    fiphone63: IPHONE.length, fiphone69: IPHONE.length, fduo: D.length, fipad: IPAD.length };
})();
