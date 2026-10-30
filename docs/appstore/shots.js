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
    box.innerHTML = html;
    return { w: w, h: h };
  };
  window.SHOT_COUNTS = { iphone63: IPHONE.length, iphone69: IPHONE.length, duo: D.length, ipad: IPAD.length };
})();
