// Runs inside docs/mockups/odysseus-iphone.html (injected by render.js) and
// turns one of its screens into a single full-bleed App Store image.
(function () {
  var O = window.ODY;
  var css = document.createElement('style');
  css.textContent = [
    'body.shot { padding: 0 !important; margin: 0; background: #262624; overflow: hidden; }',
    'body.shot::before { display: none; }',
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
    '.ipad .side .row.on { background: rgba(198,97,63,.16); border-radius: 12px; margin: 0 8px; padding-left: 8px; padding-right: 8px; }',
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
  var istatus = '<div class="istatus"><span>9:41<small>Sexta-feira, 10 de out.</small></span><span>' +
    '<svg width="18" height="12" viewBox="0 0 18 12"><rect x="0" y="8" width="3" height="4" rx="1" fill="currentColor"/><rect x="5" y="5.5" width="3" height="6.5" rx="1" fill="currentColor"/><rect x="10" y="3" width="3" height="9" rx="1" fill="currentColor"/><rect x="15" y="0" width="3" height="12" rx="1" fill="currentColor"/></svg>' +
    '<svg width="27" height="13" viewBox="0 0 27 13"><rect x=".5" y=".5" width="23" height="12" rx="3.8" fill="none" stroke="currentColor" opacity=".4"/><rect x="2" y="2" width="20" height="9" rx="2.5" fill="currentColor"/></svg></span></div>';

  function sideRow(icon, title, on) {
    return '<div class="row' + (on ? ' on' : '') + '"><span class="lead">' + ic(icon) + '</span><div class="main"><span class="ttl">' + title + '</span></div></div>';
  }
  function chatRow(title, model, time, on) {
    return '<div class="row' + (on ? ' on' : '') + '"><div class="main"><span class="ttl">' + title + '</span><span class="sub">' + model + '</span></div><span class="meta">' + time + '</span></div>';
  }
  function sidebar(active) {
    var sec = [['brain', 'Brain'], ['note', 'Notes'], ['cal', 'Calendário'], ['photo', 'Galeria'], ['envelope', 'Email'], ['check', 'Tasks'], ['box', 'Cookbook']];
    return '<div class="side">' + O.nav(O.g('gear'), 'Odysseus', '', O.g('compose')) +
      '<div class="search">' + ic('search') + 'Buscar conversas</div>' +
      sideRow('deep', 'Deep Search', false) +
      '<div class="sechead">' + ic('down') + 'Espaços</div>' +
      sec.map(function (x) { return sideRow(P(x[0]), x[1], active === x[1]); }).join('') +
      '<div class="sechead">' + ic('down') + 'Hoje<span class="n">2</span></div>' +
      chatRow('Emails de hoje', 'mimo-v2.6-pro', '09:35', active === 'chat') +
      chatRow('Roteiro de 3 dias em Lisboa', 'mimo-v2.6-flash', '08:11', false) +
      '</div>';
  }
  // Icons the mockup set lacks fall back to ones it has.
  function P(n) { return ({ envelope: 'note' })[n] || n; }

  function ipad(active, detail, extra) {
    return '<div class="ipad">' + istatus + '<div class="split">' + sidebar(active) +
      '<div class="detail">' + detail + '</div></div>' + (extra || '') + '<div class="home"></div></div>';
  }

  var S = O.S, D = O.D;
  var IPHONE = [2, 4, 0, 6, 7, 8, 9, 1];   // Chat, Voz, Conversas, Brain, Calendário, Tasks, Cookbook, Nova conversa
  var IPAD = [
    function () { return ipad('chat', S[2].h); },
    function () { return ipad('chat', S[2].h, '<div class="dim"></div><div class="vsheet">' + S[4].h + '</div>'); },
    function () { return ipad('Brain', S[6].h); },
    function () { return ipad('Calendário', S[7].h); },
    function () { return ipad('Tasks', S[8].h); },
    function () { return ipad('Cookbook', S[9].h); }
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
      var sc = 0.62, y = 262;
      html += phoneAt(2, 540, y + 46, sc, -6) + phoneAt(4, 1000 - 424 * sc / 2, y, sc, 0) + phoneAt(6, 1200, y + 46, sc, 6);
    } else {
      html += '<h1 style="font-size:96px;padding-top:70px">Seu servidor de IA num app nativo</h1>' +
        '<h2 style="font-size:54px;margin-top:10px">Sem nuvem de terceiros.</h2>';
      var s2 = 0.98, y2 = 300;
      html += phoneAt(2, 230, y2 + 70, s2 * 0.96, 0) + phoneAt(4, 1000 - (424 * s2) / 2, y2, s2, 0) + phoneAt(6, 1350, y2 + 70, s2 * 0.96, 0);
    }
    return html + '</div>';
  }
  function phoneAt(i, x, y, scale, rot) {
    return '<div class="ph" style="left:' + x + 'px;top:' + y + 'px;transform:scale(' + scale + ') rotate(' + rot + 'deg)">' + O.phone(S[i].h) + '</div>';
  }

  // ---------- App Store images with the device frame ----------
  var css2 = document.createElement('style');
  css2.textContent = [
    '.canvas { position: relative; overflow: hidden; background: radial-gradient(130% 75% at 50% 100%, #8a4227 0%, #4a2618 30%, #221a16 62%, #171513 100%); font-family: "SF Pro Display", var(--ui); color: #f5f4f0; -webkit-font-smoothing: antialiased; }',
    '.canvas .cap { position: absolute; left: 0; right: 0; text-align: center; padding: 0 6%; }',
    '.canvas .cap h1 { margin: 0; font-weight: 700; letter-spacing: -0.02em; text-wrap: balance; line-height: 1.08; }',
    '.canvas .cap p { margin: 0; font-family: "SF Pro Text", var(--ui); font-weight: 500; color: #e3a58d; letter-spacing: -0.01em; text-wrap: balance; line-height: 1.25; }',
    '.dev { position: absolute; transform-origin: top left; }',
    '.dev .shell { position: relative; background: #050505; filter: drop-shadow(0 40px 60px rgba(0,0,0,.55)); }',
    '.dev .shell::before { content: ""; position: absolute; inset: -4px; border-radius: inherit; background: linear-gradient(145deg, #5e5b55, #34332f 30%, #1f1e1c 55%, #4a4844 85%, #2b2a27); z-index: -1; }',
    '.dev .shell::after { content: ""; position: absolute; inset: -1px; border-radius: inherit; box-shadow: inset 0 0 0 1px rgba(255,255,255,.08); pointer-events: none; }',
    '.dev .shell > .phone, .dev .shell > .duo, .dev .shell > .ipad { margin: 0; box-shadow: none; position: relative; }',
    '.dev .btn { position: absolute; background: linear-gradient(90deg, #3a3936, #85827b 50%, #3a3936); border-radius: 3px; }',
    '.dev .btn.h { background: linear-gradient(180deg, #3a3936, #85827b 50%, #3a3936); }'
  ].join('\n');
  document.head.appendChild(css2);

  var CAP = {
    chat: ['Converse com o seu servidor de IA', 'Respostas do seu próprio modelo, num app nativo.'],
    voz: ['Fale e ouça a resposta', 'Modo de voz mãos-livres, com interrupção natural.'],
    conversas: ['Todas as conversas à mão', 'Busca, fixadas e grupos por dia.'],
    brain: ['Uma memória que é sua', 'O que o assistente lembra de você, organizado.'],
    calendario: ['Agenda em linguagem natural', 'Escreva “reunião amanhã 14h” e pronto.'],
    tasks: ['Tarefas que rodam sozinhas', 'Agende, pause e rode quando quiser.'],
    cookbook: ['Motores e modelos pelo celular', 'Instale pacotes no seu servidor.'],
    nova: ['Seu servidor no bolso', 'Sem nuvem de terceiros.']
  };
  var IPHONE_CAP = ['chat', 'voz', 'conversas', 'brain', 'calendario', 'tasks', 'cookbook', 'nova'];
  var DUO_CAP = ['conversas', 'chat', 'voz', 'brain', 'calendario', 'tasks'];
  var IPAD_CAP = ['chat', 'voz', 'brain', 'calendario', 'tasks', 'cookbook'];

  // Each device drawn at its real point size; the canvas scales it to fit.
  function iphoneDevice(inner, w, h) {
    var b = 13, r = 62 + b;
    var x = function (side, top, len, wid) {
      return '<span class="btn" style="' + side + ':-' + (wid + 3) + 'px;top:' + top + 'px;width:' + wid + 'px;height:' + len + 'px"></span>';
    };
    return { w: w + 2 * b, h: h + 2 * b, html:
      '<div class="shell" style="padding:' + b + 'px;border-radius:' + r + 'px">' + inner +
      x('left', 150, 32, 4) + x('left', 210, 60, 4) + x('left', 284, 60, 4) +
      x('right', 236, 96, 4) + x('right', 520, 54, 4) + '</div>' };
  }
  function duoDevice(inner) {
    var b = 9;
    return { w: 466 + 2 * b, h: 678 + 2 * b, html:
      '<div class="shell" style="padding:' + b + 'px;border-radius:' + (10 + b) + 'px ' + (59 + b) + 'px ' + (59 + b) + 'px ' + (10 + b) + 'px">' + inner +
      '<span class="btn h" style="top:-7px;left:120px;width:60px;height:4px"></span>' +
      '<span class="btn" style="right:-7px;top:150px;width:4px;height:70px"></span></div>' };
  }
  function ipadDevice(inner) {
    var b = 22;
    return { w: 1032 + 2 * b, h: 1376 + 2 * b, html:
      '<div class="shell" style="padding:' + b + 'px;border-radius:' + (30 + b) + 'px">' +
      inner.replace('<div class="ipad">', '<div class="ipad" style="border-radius:30px">') +
      '<span class="btn h" style="top:-7px;right:120px;width:56px;height:4px"></span>' +
      '<span class="btn" style="right:-7px;top:110px;width:4px;height:50px"></span>' +
      '<span class="btn" style="right:-7px;top:172px;width:4px;height:50px"></span></div>' };
  }

  function canvas(W, H, cap, dev, o) {
    // o: capTop, h1, p, gap, bottom (all in canvas points)
    var capH = o.capTop + o.h1 * 1.08 * o.lines + o.gap + o.p * 1.25 + o.afterCap;
    var s = Math.min((H - capH - o.bottom) / dev.h, (W * o.maxW) / dev.w);
    var x = (W - dev.w * s) / 2, y = capH;
    return '<div class="canvas" style="width:' + W + 'px;height:' + H + 'px">' +
      '<div class="cap" style="top:' + o.capTop + 'px"><h1 style="font-size:' + o.h1 + 'px">' + cap[0] + '</h1>' +
      '<p style="font-size:' + o.p + 'px;margin-top:' + o.gap + 'px">' + cap[1] + '</p></div>' +
      '<div class="dev" style="left:' + x + 'px;top:' + y + 'px;width:' + dev.w + 'px;height:' + dev.h + 'px;transform:scale(' + s + ')">' + dev.html + '</div></div>';
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
      { capTop: 26, h1: 23, lines: 1, gap: 5, p: 13, afterCap: 22, bottom: 22, maxW: 0.9 }) }; },
    fipad: function (i) { return { w: 1032, h: 1376, html: canvas(1032, 1376, CAP[IPAD_CAP[i]], ipadDevice(IPAD[i]()),
      { capTop: 70, h1: 54, lines: 1, gap: 14, p: 26, afterCap: 50, bottom: 50, maxW: 0.9 }) }; }
  };

  window.SHOT = function (kind, i) {
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
    return { w: w, h: h };
  };
  window.SHOT_COUNTS = { iphone63: IPHONE.length, iphone69: IPHONE.length, duo: D.length, ipad: IPAD.length,
    fiphone63: IPHONE.length, fiphone69: IPHONE.length, fduo: D.length, fipad: IPAD.length };
})();
