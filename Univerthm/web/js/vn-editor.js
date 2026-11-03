/* =============================================================================
 * Univerthm 视觉小说编辑器 · 界面与预览
 * -----------------------------------------------------------------------------
 * 剧本解析在 js/vn.js（可以做单测），这里只做：素材库、舞台预览、导出。
 * 预览器按 parser 给出的扁平指令流执行，和导出的播放器是同一套语义。
 * ========================================================================== */
(function () {
  'use strict';

  var VS = window.VNScript;
  if (!VS) { document.body.innerHTML = '<p style="padding:24px">缺少 js/vn.js</p>'; return; }

  function $(id) { return document.getElementById(id); }

  function esc(s) {
    return String(s === undefined || s === null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function cssUrl(u) { return 'url("' + String(u).replace(/"/g, '%22') + '")'; }

  var KIND_LABEL = { bg: '背景', char: '立绘', audio: '音频' };

  var DB_NAME = 'univerthm-vn';
  var DB_STORE = 'kv';
  var KEY_META = 'project-meta';
  var KEY_ASSETS = 'assets';
  var LS_META = 'univerthm-vn-meta';
  var LS_ASSETS = 'univerthm-vn-assets';
  var LS_ASSET_LIMIT = 3200000;

  /* ==========================================================================
   * 示例素材 / 示例剧本（相对本文件，第一次打开就有东西可看）
   * ======================================================================== */

  var DEMO_ASSETS = [
    { name: '黑洞', kind: 'bg', src: '../game/assets/menu_black_hole.png', mime: 'image/png' },
    { name: '深空', kind: 'bg', src: '../game/assets/menu_deep_space.png', mime: 'image/png' },
    { name: '主界面', kind: 'bg', src: '../game/assets/main_bg.png', mime: 'image/png' },
    { name: '故障', kind: 'bg', src: '../game/assets/settings_black_hole_glitch.png', mime: 'image/png' },
    { name: 'Stra', kind: 'char', src: '../game/assets/banners/stra1.png', mime: 'image/png' },
    { name: 'Stra2', kind: 'char', src: '../game/assets/banners/stra2.png', mime: 'image/png' },
    { name: 'Stra3', kind: 'char', src: '../game/assets/banners/stra3.png', mime: 'image/png' },
    { name: 'Kisai', kind: 'char', src: '../game/assets/banners/Kisai1.png', mime: 'image/png' },
    { name: 'Kisai2', kind: 'char', src: '../game/assets/banners/Kisai2.png', mime: 'image/png' },
    { name: 'Diffusion', kind: 'audio', src: '../game/audio/difusion.mp3', mime: 'audio/mpeg' },
    { name: '点击', kind: 'audio', src: '../game/audio/click.wav', mime: 'audio/wav' }
  ];

  var DEMO_SCRIPT = [
    '# Univerthm · 序章占位剧情（示例）',
    '# 左边点素材可以插入，右上「语法」里有全部指令',
    '',
    '@bg 黑洞 fade=0.8',
    '@bgm Diffusion fade=1.2',
    '@chapter 序章丨一切的开端',
    '',
    '* 开篇',
    '@show Stra center fade=0.6',
    'Stra：你听见了吗？这座城市，已经很久没有声音了。',
    'Stra：不对……不是没有声音，是所有人都不敢听。',
    '\\ 她把手里的星图平板转过来，屏幕上是一片正在坍缩的星点。',
    '@bg 深空 fade=1.0',
    '@move Stra right t=0.5',
    'Stra：看这里。每一次旋律响起，星图就亮一点。',
    '@sfx 点击 volume=60',
    '@wait 0.4',
    '@choice 你要怎么回答？',
    '- 「那就弹给我们听。」 -> 靠近',
    '- 「我凭什么信你？」 -> 后退',
    '',
    '* 靠近',
    '@show Stra center fade=0.4',
    'Stra：好。那你要跟紧我，别在半路上走丢了。',
    '@jump 收束',
    '',
    '* 后退',
    '@show Stra right fade=0.4',
    '@shake 8 0.4',
    'Stra：……也行。怀疑是好事，至少说明你还在思考。',
    '@jump 收束',
    '',
    '* 收束',
    '@hide Stra fade=0.6',
    '@bg 主界面 fade=1.2',
    '\\ 音轨交叠的地方，第一首曲子的前奏响起。',
    '@end 序章 · 完'
  ].join('\n');

  /* ==========================================================================
   * 状态
   * ======================================================================== */

  var S = {
    project: VS.newProject(),
    parsed: VS.parse(''),
    db: null,
    kind: 'all',
    query: '',
    selected: '',
    saved: true,
    parseTimer: 0,
    gutterTimer: 0,
    saveTimer: 0,
    toastTimer: 0
  };

  var PV = {
    active: false, token: 0, pc: 0, line: 0,
    steps: [], labels: {},
    typing: 0, full: '', shown: 0, done: true, pending: 0, stepTimer: 0,
    sprites: {}, state: {}, bgTop: 0, bgName: '',
    bgm: null, bgmName: '', bgmScale: 1, bgmTimer: 0,
    auto: false, volume: 0.8, hideSeq: 0
  };

  /* ==========================================================================
   * 存储
   * ======================================================================== */

  function openDB() {
    return new Promise(function (resolve) {
      if (!window.indexedDB) { resolve(null); return; }
      var settled = false;
      var finish = function (db) {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve(db);
      };
      // 有些环境（file:// 的部分浏览器 / 隐私模式）open() 既不 success 也不 error，会一直挂着
      var timer = setTimeout(function () { finish(null); }, 900);
      var req;
      try { req = indexedDB.open(DB_NAME, 1); } catch (e) { finish(null); return; }
      req.onupgradeneeded = function () {
        var db = req.result;
        if (!db.objectStoreNames.contains(DB_STORE)) db.createObjectStore(DB_STORE);
      };
      req.onsuccess = function () { finish(req.result); };
      req.onerror = function () { finish(null); };
      req.onblocked = function () { finish(null); };
    });
  }

  function dbGet(db, key) {
    return new Promise(function (resolve) {
      if (!db) { resolve(null); return; }
      try {
        var r = db.transaction(DB_STORE, 'readonly').objectStore(DB_STORE).get(key);
        r.onsuccess = function () { resolve(r.result || null); };
        r.onerror = function () { resolve(null); };
      } catch (e) { resolve(null); }
    });
  }

  function dbSet(db, key, val) {
    return new Promise(function (resolve) {
      if (!db) { resolve(false); return; }
      try {
        var tx = db.transaction(DB_STORE, 'readwrite');
        tx.objectStore(DB_STORE).put(val, key);
        tx.oncomplete = function () { resolve(true); };
        tx.onerror = function () { resolve(false); };
        tx.onabort = function () { resolve(false); };
      } catch (e) { resolve(false); }
    });
  }

  /* localStorage 兜底：IndexedDB 用不了的时候（file:// / 隐私模式）至少别丢剧本 */

  function lsGet(key) {
    try {
      var s = window.localStorage.getItem(key);
      return s ? JSON.parse(s) : null;
    } catch (e) { return null; }
  }

  function lsSet(key, val) {
    try {
      var s = JSON.stringify(val);
      if (s.length > LS_ASSET_LIMIT) return false;
      window.localStorage.setItem(key, s);
      return true;
    } catch (e) { return false; }
  }

  function metaPayload() {
    return {
      vn: VS.VERSION,
      name: S.project.name,
      script: S.project.script,
      chars: S.project.chars,
      settings: S.project.settings,
      ids: S.project.assets.map(function (a) { return a.id; }),
      updatedAt: Date.now()
    };
  }

  function scheduleSave() {
    S.saved = false;
    renderSaveState();
    clearTimeout(S.saveTimer);
    S.saveTimer = setTimeout(function () { saveNow(true); }, 900);
  }

  /**
   * 剧本 / 角色 / 名字存一条，素材（base64 很大）另存一条。
   * 打字时只重写前一条，不然每次输入都要把几 MB 的图片再写一遍。
   */
  function persistMeta() {
    if (!S.db) return Promise.resolve(lsSet(LS_META, metaPayload()));
    return dbSet(S.db, KEY_META, metaPayload());
  }

  function persistAssets() {
    var map = {};
    S.project.assets.forEach(function (a) { map[a.id] = a; });
    if (!S.db) return Promise.resolve(lsSet(LS_ASSETS, { map: map, ids: S.project.assets.map(function (a) { return a.id; }) }));
    return dbSet(S.db, KEY_ASSETS, map);
  }

  function saveNow(silent) {
    clearTimeout(S.saveTimer);
    S.saveTimer = 0;
    S.project.updatedAt = Date.now();
    return persistMeta().then(function (ok) {
      S.saved = true;
      renderSaveState();
      if (!ok && !silent) toast('浏览器没让写本地存储，记得用「保存工程」存成文件', true);
      return ok;
    });
  }

  function saveAssets() {
    return persistAssets().then(function () { return scheduleSave(); });
  }

  function renderSaveState() {
    var el = $('statusSave');
    if (!el) return;
    if (S.saved) {
      el.textContent = S.db ? '已自动保存到浏览器' : '已存剧本（素材请用「保存工程」）';
      el.className = 'savedot ok';
    } else {
      el.textContent = S.db ? '有改动未保存' : '有改动未保存 · 素材只存在内存里';
      el.className = 'savedot dirty';
    }
  }

  /* ==========================================================================
   * 提示 / 状态栏
   * ======================================================================== */

  function toast(text, isErr) {
    var box = $('toast');
    box.textContent = text;
    box.className = 'toast' + (isErr ? ' err' : '');
    box.hidden = false;
    clearTimeout(S.toastTimer);
    S.toastTimer = setTimeout(function () { box.hidden = true; }, isErr ? 4200 : 2400);
  }

  function setPvStatus(text) { $('pvStatus').textContent = text || ''; }

  function renderStatus() {
    var p = S.parsed;
    var words = VS.wordCount(p);
    var chars = p.characters.length;
    var steps = p.steps.length;
    $('statusLeft').textContent = '指令 ' + steps + ' · 说话人 ' + chars + ' · 字数 ' + words + ' · 素材 ' + S.project.assets.length;
    $('assetCount').textContent = String(S.project.assets.length);
  }

  function renderEditorFoot() {
    var ta = $('script');
    var line = caretLine();
    var p = S.parsed;
    var stepAt = p.steps.filter(function (s) { return s.line <= line; }).length;
    $('editorFoot').textContent = '第 ' + line + ' 行 · 这一行之前有 ' + stepAt + ' 条指令 · 总 ' + p.lineCount + ' 行';
  }

  /* ==========================================================================
   * 解析 / 渲染
   * ======================================================================== */

  function reparse() {
    S.parsed = VS.parse(S.project.script);
    renderGutter();
    renderOutline();
    renderChars();
    updateUsageBadges();
    renderAssetDetail();
    renderStatus();
    renderEditorFoot();
  }

  /** 打字时只刷新引用计数，不重建整个素材网格（不然网格会跳回顶部） */
  function updateUsageBadges() {
    var usage = VS.assetUsage(S.parsed || VS.parse(''));
    var nodes = $('assetGrid').children;
    for (var i = 0; i < nodes.length; i++) {
      var id = nodes[i].dataset && nodes[i].dataset.id;
      if (!id) continue;
      var asset = null;
      for (var k = 0; k < S.project.assets.length; k++) {
        if (S.project.assets[k].id === id) { asset = S.project.assets[k]; break; }
      }
      if (!asset) continue;
      var badge = nodes[i].querySelector('.ause');
      if (!badge) continue;
      var used = usage[asset.name] || 0;
      badge.textContent = '×' + used;
      badge.className = 'ause' + (used ? '' : ' zero');
    }
  }

  function onScriptInput() {
    S.project.script = $('script').value;
    scheduleSave();
    clearTimeout(S.parseTimer);
    S.parseTimer = setTimeout(reparse, 110);
    clearTimeout(S.gutterTimer);
    S.gutterTimer = setTimeout(renderGutter, 150);
    markCaretLine();
    renderEditorFoot();
  }

  /* ---------------- 行号 ---------------- */

  function lineTypes() {
    var map = {};
    var p = S.parsed;
    if (!p) return map;
    for (var i = 0; i < p.steps.length; i++) {
      var st = p.steps[i];
      map[st.line] = (st.op === 'say' || st.op === 'narr') ? 'say'
        : (st.op === 'choice' || st.op === 'jump' || st.op === 'end') ? 'flow' : 'cmd';
    }
    for (var l = 0; l < p.labels.length; l++) map[p.labels[l].line] = 'flow';
    for (var e = 0; e < p.errors.length; e++) map[p.errors[e].line] = 'err';
    return map;
  }

  function renderGutter() {
    var ta = $('script');
    var gut = $('gutter');
    var mirror = $('gutterMirror');
    if (!ta || !gut || !mirror) return;

    var lines = ta.value.split('\n');
    var limit = 2400;
    var use = lines.length > limit ? lines.slice(0, limit) : lines;
    var width = Math.max(40, ta.clientWidth - 24);

    mirror.style.width = width + 'px';
    var buf = [];
    for (var i = 0; i < use.length; i++) buf.push('<div>' + (use[i] ? esc(use[i]) : '&#8203;') + '</div>');
    mirror.innerHTML = buf.join('');

    var types = lineTypes();
    var html = [];
    for (var j = 0; j < use.length; j++) {
      var row = mirror.children[j];
      var h = row ? (row.offsetHeight || 21) : 21;
      var t = types[j + 1];
      html.push('<div class="gl' + (t ? ' t-' + t : '') + '" data-line="' + (j + 1) + '" style="height:' + h + 'px">' + (j + 1) + '</div>');
    }
    if (lines.length > limit) html.push('<div class="gl" style="height:21px">…</div>');
    gut.innerHTML = html.join('');
    syncGutterScroll();
    markCaretLine();
  }

  function syncGutterScroll() {
    var ta = $('script'), gut = $('gutter');
    if (ta && gut) gut.scrollTop = ta.scrollTop;
  }

  function markCaretLine() {
    var gutter = $('gutter');
    if (!gutter) return;
    var cur = gutter.querySelector('.gl.cur');
    if (cur) cur.classList.remove('cur');
    var line = caretLine();
    var row = gutter.children[line - 1];
    if (row && row.classList.contains('gl')) row.classList.add('cur');
  }

  function caretLine() {
    var ta = $('script');
    if (!ta) return 1;
    var upto = ta.value.slice(0, ta.selectionStart);
    return upto.split('\n').length;
  }

  /* ---------------- 大纲 ---------------- */

  function renderOutline() {
    var p = S.parsed || VS.parse('');
    var box = $('outlineList');
    if (!p.labels.length) {
      box.innerHTML = '<div style="padding:2px 8px 10px;font-size:11px;color:#5d6678">还没有标签。写「* 开篇」就能当跳转和分支的落点。</div>';
    } else {
      box.innerHTML = p.labels.map(function (l) {
        return '<button class="olabel" data-line="' + l.line + '">' +
          '<span class="ln">' + l.line + '</span>' +
          '<span class="nm">' + esc(l.name) + '</span>' +
          '<span class="cnt">#' + l.index + '</span></button>';
      }).join('');
    }

    var issues = [];
    p.errors.forEach(function (e) { issues.push({ line: e.line, msg: e.message, cls: '' }); });
    p.characters.forEach(function (c) {
      if (c.name.length >= 6) {
        issues.push({ line: c.firstLine, msg: '「' + c.name + '」被当成了说话人。如果它本来是旁白，在这一行开头加一个反斜杠。', cls: 'warn' });
      }
    });
    if (!issues.length) issues.push({ line: 0, msg: '没有发现问题', cls: 'ok' });

    $('issueList').innerHTML = issues.map(function (it) {
      if (!it.line) return '<div class="issue ' + (it.cls || 'ok') + '">' + esc(it.msg) + '</div>';
      return '<button class="issue ' + (it.cls || '') + '" data-line="' + it.line + '"><span class="ln">' + it.line + '</span><span>' + esc(it.msg) + '</span></button>';
    }).join('');
  }

  /* ---------------- 角色 ---------------- */

  function renderChars() {
    var p = S.parsed || VS.parse('');
    var sprites = S.project.assets.filter(function (a) { return a.kind === 'char'; });
    var box = $('charList');
    if (!p.characters.length) {
      box.innerHTML = '<div style="padding:2px 8px 10px;font-size:11px;color:#5d6678">还没有角色。写一句「Stra：你好」就出现了。</div>';
    } else {
      box.innerHTML = '';
      p.characters.forEach(function (c) {
        var conf = S.project.chars[c.name] || {};
        var color = VS.charColor(S.project, c.name);
        var row = document.createElement('div');
        row.className = 'charrow';
        row.innerHTML = '<input type="color" class="swatch" data-char="' + esc(c.name) + '" value="' + color + '" title="台词名字的颜色">' +
          '<span class="cname">' + esc(c.name) + '</span>' +
          '<span class="ccount">' + c.count + ' 句</span>' +
          '<select data-sprite="' + esc(c.name) + '" title="默认立绘"><option value="">默认立绘</option>' +
          sprites.map(function (a) {
            return '<option value="' + esc(a.name) + '"' + (conf.sprite === a.name ? ' selected' : '') + '>' + esc(a.name) + '</option>';
          }).join('') + '</select>';
        box.appendChild(row);
      });
    }
    $('charStats').innerHTML =
      '说话人 <b>' + p.characters.length + '</b><br>' +
      '台词 <b>' + p.steps.filter(function (s) { return s.op === 'say'; }).length + '</b> 句 · 旁白 <b>' +
      p.steps.filter(function (s) { return s.op === 'narr'; }).length + '</b> 段<br>' +
      '字数 <b>' + VS.wordCount(p) + '</b> · 选项 <b>' +
      p.steps.filter(function (s) { return s.op === 'choice'; }).length + '</b> 处 · 标签 <b>' + p.labels.length + '</b> 个';
  }

  /* ---------------- 素材库 ---------------- */

  function renderAssets() {
    var grid = $('assetGrid');
    var usage = VS.assetUsage(S.parsed || VS.parse(''));
    var q = S.query.toLowerCase();
    var list = S.project.assets.filter(function (a) {
      if (S.kind !== 'all' && a.kind !== S.kind) return false;
      if (q && a.name.toLowerCase().indexOf(q) < 0) return false;
      return true;
    });
    grid.innerHTML = '';
    if (!list.length) {
      var empty = document.createElement('div');
      empty.style.cssText = 'grid-column:1/-1;padding:10px 6px;font-size:11px;color:#5d6678;line-height:1.9';
      empty.textContent = S.project.assets.length ? '这个分类下没有素材。' : '还没有素材。点上面「导入素材」，或者把图片直接拖进窗口。';
      grid.appendChild(empty);
      renderAssetDetail();
      return;
    }
    list.forEach(function (a) {
      var used = usage[a.name] || 0;
      var btn = document.createElement('button');
      btn.className = 'asset' + (S.selected === a.id ? ' on' : '');
      btn.dataset.id = a.id;
      btn.title = a.name + ' · ' + KIND_LABEL[a.kind] + (a.w ? ' · ' + a.w + '×' + a.h : '');

      var thumb = document.createElement('span');
      thumb.className = 'thumb' + (a.kind === 'audio' ? ' audio' : '');
      if (a.kind === 'audio') thumb.textContent = '♪';
      else thumb.style.backgroundImage = cssUrl(a.src);

      var name = document.createElement('span');
      name.className = 'aname';
      name.textContent = a.name;

      var kind = document.createElement('span');
      kind.className = 'akind';
      kind.textContent = KIND_LABEL[a.kind];

      var use = document.createElement('span');
      use.className = 'ause' + (used ? '' : ' zero');
      use.textContent = '×' + used;

      btn.appendChild(thumb);
      btn.appendChild(name);
      btn.appendChild(kind);
      btn.appendChild(use);
      grid.appendChild(btn);
    });
    renderAssetDetail();
  }

  function findAsset(name) {
    for (var i = 0; i < S.project.assets.length; i++) {
      if (S.project.assets[i].name === name) return S.project.assets[i];
    }
    return null;
  }

  function selectedAsset() {
    for (var i = 0; i < S.project.assets.length; i++) {
      if (S.project.assets[i].id === S.selected) return S.project.assets[i];
    }
    return null;
  }

  function renderAssetDetail() {
    var box = $('assetDetail');
    var a = selectedAsset();
    if (!a) { box.hidden = true; box.innerHTML = ''; return; }
    box.hidden = false;
    var usage = VS.assetUsage(S.parsed || VS.parse(''));
    var meta = KIND_LABEL[a.kind] + ' · 被引用 ' + (usage[a.name] || 0) + ' 次';
    if (a.w) meta += ' · ' + a.w + '×' + a.h;
    if (a.size) meta += ' · ' + Math.round(a.size / 1024) + ' KB';

    box.innerHTML = '<div class="ad-name">' + esc(a.name) + '</div><div class="ad-meta">' + meta + '</div>';
    var acts = document.createElement('div');
    acts.className = 'ad-actions';

    function addBtn(label, fn, primary) {
      var b = document.createElement('button');
      b.className = 'btn' + (primary ? ' primary' : '');
      b.textContent = label;
      b.addEventListener('click', fn);
      acts.appendChild(b);
    }

    if (a.kind === 'bg') addBtn('插到光标', function () { insertSnippet('@bg ' + a.name + ' fade=0.6'); }, true);
    if (a.kind === 'char') addBtn('插到光标', function () { insertSnippet('@show ' + a.name + ' center fade=0.4'); }, true);
    if (a.kind === 'audio') {
      addBtn('插入音乐', function () { insertSnippet('@bgm ' + a.name + ' fade=1'); }, true);
      addBtn('插入音效', function () { insertSnippet('@sfx ' + a.name); });
    }
    addBtn('改名', function () { renameAsset(a); });
    if (a.kind === 'audio') addBtn('试听', function () { previewAudio(a); });
    addBtn('删除', function () { removeAsset(a); });
    box.appendChild(acts);

    var kindRow = document.createElement('div');
    kindRow.className = 'ad-actions';
    kindRow.style.marginTop = '6px';
    ['bg', 'char', 'audio'].forEach(function (k) {
      var b = document.createElement('button');
      b.className = 'btn tiny' + (a.kind === k ? ' primary' : '');
      b.textContent = KIND_LABEL[k];
      b.addEventListener('click', function () {
        a.kind = k;
        saveAssets();
        renderAssets();
        renderChars();
      });
      kindRow.appendChild(b);
    });
    box.appendChild(kindRow);
  }

  function previewAudio(a) {
    try {
      var el = new Audio(a.src);
      el.volume = PV.volume;
      el.play().catch(function () { toast('浏览器没让播：先点一下页面再试', true); });
    } catch (e) { toast('这个音频读不出来', true); }
  }

  function renameAsset(a) {
    var name = window.prompt('素材名（剧本里就用这个名字引用）', a.name);
    if (name === null) return;
    name = name.trim();
    if (!name || name === a.name) return;
    if (/[\s]/.test(name)) { toast('素材名里不要带空格', true); return; }
    if (S.project.assets.some(function (x) { return x.id !== a.id && x.name === name; })) {
      toast('已经有同名素材了', true);
      return;
    }
    var old = a.name;
    a.name = name;
    if (S.project.script.indexOf(old) >= 0 && window.confirm('剧本里还有「' + old + '」，要一起换成「' + name + '」吗？')) {
      S.project.script = S.project.script.split(old).join(name);
      $('script').value = S.project.script;
      reparse();
    }
    if (S.project.chars[old]) {
      S.project.chars[name] = S.project.chars[old];
      delete S.project.chars[old];
    }
    saveAssets();
    renderAssets();
    renderChars();
  }

  function removeAsset(a) {
    if (!window.confirm('删除素材「' + a.name + '」？剧本里的引用会变成空占位。')) return;
    S.project.assets = S.project.assets.filter(function (x) { return x.id !== a.id; });
    if (S.selected === a.id) S.selected = '';
    scheduleSave();
    renderAssets();
    renderChars();
  }

  /* ==========================================================================
   * 导入
   * ======================================================================== */

  function readFile(file) {
    return new Promise(function (resolve) {
      var fr = new FileReader();
      fr.onload = function () { resolve(String(fr.result || '')); };
      fr.onerror = function () { resolve(''); };
      fr.readAsDataURL(file);
    });
  }

  function imageSize(src) {
    return new Promise(function (resolve) {
      var im = new Image();
      im.onload = function () { resolve({ w: im.naturalWidth || 0, h: im.naturalHeight || 0 }); };
      im.onerror = function () { resolve({ w: 0, h: 0 }); };
      im.src = src;
    });
  }

  function baseName(n) {
    return String(n || 'asset').replace(/\.[^.]+$/, '').trim() || 'asset';
  }

  function guessKind(file) {
    var n = file.name || '';
    if (/^audio\//.test(file.type) || /\.(mp3|ogg|wav|flac|m4a)$/i.test(n)) return 'audio';
    if (/(立绘|角色|人物|char|sprite|portrait|tachie|tachi)/i.test(n)) return 'char';
    return 'bg';
  }

  function uniqueName(base) {
    var name = base;
    var n = 2;
    while (findAsset(name)) { name = base + '_' + n; n++; }
    return name;
  }

  function nextAssetId() {
    var max = 0;
    S.project.assets.forEach(function (a) {
      var m = /^a(\d+)$/.exec(a.id || '');
      if (m) max = Math.max(max, parseInt(m[1], 10));
    });
    return 'a' + (max + 1);
  }

  function importFiles(files) {
    var arr = Array.prototype.slice.call(files || []);
    if (!arr.length) return;
    var added = 0, skipped = [];

    var chain = Promise.resolve();
    arr.forEach(function (f) {
      chain = chain.then(function () {
        var isMedia = /^image\//.test(f.type) || /^audio\//.test(f.type) ||
          /\.(png|jpe?g|webp|gif|avif|mp3|ogg|wav|flac|m4a)$/i.test(f.name || '');
        if (!isMedia) return;
        if (f.size > 48 * 1024 * 1024) { skipped.push(f.name); return; }
        return readFile(f).then(function (src) {
          if (!src) return;
          var kind = guessKind(f);
          var asset = {
            id: nextAssetId(),
            name: uniqueName(baseName(f.name)),
            kind: kind,
            src: src,
            mime: f.type || '',
            size: f.size,
            w: 0,
            h: 0
          };
          S.project.assets.push(asset);
          added++;
          if (kind === 'audio') return null;
          return imageSize(src).then(function (d) {
            asset.w = d.w;
            asset.h = d.h;
            // 竖图默认当立绘（除非文件名明显是背景）
            if (asset.kind === 'bg' && d.w && d.h > d.w * 1.15 &&
              !/(bg|背景|back|scene|场景|space|洞|天|夜|room|教室)/i.test(f.name || '')) {
              asset.kind = 'char';
            }
          });
        });
      });
    });

    chain.then(function () {
      saveAssets();
      renderAssets();
      renderChars();
      renderStatus();
      var msg = '导入 ' + added + ' 个素材';
      if (skipped.length) msg += '，跳过 ' + skipped.length + ' 个（超过 48MB）';
      toast(msg, !added);
      if (!S.db && added) {
        setTimeout(function () {
          toast('这个环境只能用 localStorage，大素材不会自动存下来，记得用「保存工程」落盘', true);
        }, 2600);
      }
    });
  }

  /* ==========================================================================
   * 剧本编辑：插入片段
   * ======================================================================== */

  function insertSnippet(snippet, selStart, selLen) {
    var ta = $('script');
    var v = ta.value;
    var s = ta.selectionStart;
    var e = ta.selectionEnd;
    var prefix = (s > 0 && v.charAt(s - 1) !== '\n') ? '\n' : '';
    var suffix = (e < v.length && v.charAt(e) !== '\n') ? '\n' : '';
    ta.value = v.slice(0, s) + prefix + snippet + suffix + v.slice(e);
    var base = s + prefix.length;
    ta.focus();
    if (selStart !== undefined) {
      ta.selectionStart = base + selStart;
      ta.selectionEnd = base + selStart + (selLen || 0);
    } else {
      var pos = base + snippet.length;
      ta.selectionStart = ta.selectionEnd = pos;
    }
    onScriptInput();
    renderGutter();
    var line = ta.value.slice(0, ta.selectionStart).split('\n').length;
    ta.scrollTop = Math.max(0, (line - 4) * 21);
    syncGutterScroll();
    markCaretLine();
    renderEditorFoot();
  }

  function firstAsset(kind) {
    for (var i = 0; i < S.project.assets.length; i++) {
      if (S.project.assets[i].kind === kind) return S.project.assets[i];
    }
    return null;
  }

  function firstLabel() {
    if (S.parsed && S.parsed.labels.length) return S.parsed.labels[0].name;
    return '标签';
  }

  function insertOf(kind) {
    if (kind === 'bg') {
      var a = firstAsset('bg');
      var name = a ? a.name : '素材名';
      var text = '@bg ' + name + ' fade=0.6';
      insertSnippet(text, a ? undefined : 4, a ? 0 : 3);
    } else if (kind === 'show') {
      var c = firstAsset('char');
      var cn = c ? c.name : '素材名';
      insertSnippet('@show ' + cn + ' center fade=0.4', c ? undefined : 6, c ? 0 : 3);
    } else if (kind === 'say') {
      var speaker = S.parsed.characters.length ? S.parsed.characters[0].name : '角色名';
      var t = speaker + '：台词';
      insertSnippet(t, t.indexOf('：') + 1, 2);
    } else if (kind === 'wait') {
      insertSnippet('@wait 0.8');
    } else if (kind === 'choice') {
      insertSnippet('@choice 你怎么想？\n- 选项一 -> ' + firstLabel() + '\n- 选项二');
    } else if (kind === 'jump') {
      insertSnippet('@jump ' + firstLabel(), 6, firstLabel().length);
    } else if (kind === 'bgm') {
      var m = firstAsset('audio');
      insertSnippet('@bgm ' + (m ? m.name : '素材名') + ' fade=1', m ? undefined : 5, m ? 0 : 3);
    } else if (kind === 'sfx') {
      var f = firstAsset('audio');
      insertSnippet('@sfx ' + (f ? f.name : '素材名'), f ? undefined : 5, f ? 0 : 3);
    } else if (kind === 'chapter') {
      insertSnippet('@chapter 第一章丨标题', 9, 5);
    } else if (kind === 'label') {
      insertSnippet('* 标签', 2, 2);
    }
  }

  function jumpToLine(line, withPreview) {
    var ta = $('script');
    var lines = ta.value.split('\n');
    var idx = 0;
    for (var i = 0; i < Math.min(line - 1, lines.length); i++) idx += lines[i].length + 1;
    ta.focus();
    ta.selectionStart = ta.selectionEnd = idx;
    var per = 21;
    ta.scrollTop = Math.max(0, (line - 5) * per);
    syncGutterScroll();
    markCaretLine();
    renderEditorFoot();
    if (withPreview) pvStart(line);
    switchPane('script');
  }

  /* ==========================================================================
   * 预览引擎
   * ======================================================================== */

  function missBox(name) {
    var d = document.createElement('div');
    d.className = 'missbox';
    d.textContent = '缺少素材「' + name + '」';
    return d;
  }

  function applyPos(box, x, scale, flip) {
    var sc = (scale || 100) / 100;
    box.style.left = (x === undefined ? 50 : x) + '%';
    box.style.height = (82 * sc) + '%';
    box.style.transform = 'translateX(-50%)' + (flip ? ' scaleX(-1)' : '');
  }

  function pvClearStage(showIdle) {
    PV.token++;
    if (PV.typing) { clearInterval(PV.typing); PV.typing = 0; }
    if (PV.pending) { clearTimeout(PV.pending); PV.pending = 0; }
    if (PV.stepTimer) { clearTimeout(PV.stepTimer); PV.stepTimer = 0; }
    Object.keys(PV.sprites).forEach(function (k) {
      var b = PV.sprites[k];
      if (b && b.parentNode) b.parentNode.removeChild(b);
    });
    PV.sprites = {};
    PV.state = {};
    PV.active = false;
    PV.pc = 0;
    PV.line = 0;
    PV.full = '';
    PV.done = true;

    $('dialog').hidden = true;
    $('nextMark').hidden = true;
    $('choices').hidden = true;
    $('choices').innerHTML = '';
    $('endcard').hidden = true;
    $('chapter').style.opacity = '0';
    $('flash').style.opacity = '0';
    $('stageInner').classList.remove('shake');

    ['bgA', 'bgB'].forEach(function (id) {
      var n = $(id);
      n.style.transition = 'none';
      n.style.opacity = '0';
      n.style.backgroundImage = '';
      n.className = 'bglayer';
      n.removeAttribute('data-name');
    });
    PV.bgName = '';
    PV.bgTop = 0;
    stopBgm(0.2);
    $('idle').hidden = !showIdle;
  }

  function pvStart(fromLine) {
    // 先按当前文本框重新解析一次：避免「刚打完字就按 Ctrl+Enter」用到 110ms 前的旧结果
    if ($('script').value !== S.project.script) {
      S.project.script = $('script').value;
      S.parsed = VS.parse(S.project.script);
    } else if (!S.parsed) {
      S.parsed = VS.parse(S.project.script);
    }
    if (!S.parsed.steps.length) { toast('剧本还是空的，先写两行'); return; }
    pvClearStage(false);
    PV.steps = S.parsed.steps;
    PV.labels = S.parsed.labelMap;
    PV.active = true;
    PV.pc = fromLine ? VS.indexAtLine(S.parsed, fromLine) : 0;
    PV.done = true;
    $('idle').hidden = true;
    setPvStatus('预览中 · 从第 ' + (fromLine || 1) + ' 行开始');
    pvStep();
  }

  function pvStep() {
    if (!PV.active) return;
    var guard = 0;
    while (PV.active && guard++ < 5000) {
      if (PV.pc >= PV.steps.length) { pvEnd(''); return; }
      var s = PV.steps[PV.pc];
      PV.line = s.line;
      if (s.op === 'say' || s.op === 'narr') { pvSay(s); return; }
      if (s.op === 'choice') { pvChoice(s); return; }
      if (s.op === 'wait') { pvWait(s); return; }
      if (s.op === 'chapter') { pvChapter(s); return; }
      if (s.op === 'end') { pvEnd(s.text); return; }
      if (s.op === 'jump') {
        if (s.index === null || s.index === undefined) { pvEnd('跳转目标不存在：「' + s.target + '」'); return; }
        PV.pc = s.index;
        continue;
      }
      pvApply(s);
      PV.pc++;
    }
  }

  function pvApply(s) {
    if (s.op === 'bg') return pvBg(s);
    if (s.op === 'show') return pvShow(s);
    if (s.op === 'hide') return pvHide(s);
    if (s.op === 'move') return pvMove(s);
    if (s.op === 'clear') return pvHide({ asset: 'all', fade: s.fade });
    if (s.op === 'bgm') return pvBgm(s);
    if (s.op === 'bgmstop') return stopBgm(s.fade);
    if (s.op === 'sfx') return pvSfx(s);
    if (s.op === 'shake') return pvShake(s);
    if (s.op === 'flash') return pvFlash(s);
  }

  function pvBg(s) {
    var layers = [$('bgA'), $('bgB')];
    var cur = layers[PV.bgTop];
    var nxt = layers[1 - PV.bgTop];
    var asset = findAsset(s.asset);

    nxt.style.transition = 'none';
    nxt.style.opacity = '0';
    if (asset && asset.src) {
      nxt.className = 'bglayer';
      nxt.style.backgroundImage = cssUrl(asset.src);
      nxt.removeAttribute('data-name');
    } else {
      nxt.className = 'bglayer miss';
      nxt.style.backgroundImage = '';
      nxt.setAttribute('data-name', '缺少背景「' + s.asset + '」');
    }
    nxt.style.zIndex = '2';
    cur.style.zIndex = '1';
    void nxt.offsetWidth;

    var fade = s.fade === undefined ? 0.6 : s.fade;
    nxt.style.transition = 'opacity ' + fade + 's linear';
    cur.style.transition = 'opacity ' + fade + 's linear';
    nxt.style.opacity = '1';
    cur.style.opacity = '0';
    PV.bgTop = 1 - PV.bgTop;
    PV.bgName = s.asset;
  }

  function pvShow(s) {
    var box = PV.sprites[s.asset];
    if (!box) {
      box = document.createElement('div');
      box.className = 'sprite';
      var asset = findAsset(s.asset);
      if (asset && asset.src) {
        var im = document.createElement('img');
        im.alt = s.asset;
        im.draggable = false;
        im.addEventListener('error', function () {
          box.innerHTML = '';
          box.appendChild(missBox(s.asset));
        });
        im.src = asset.src;
        box.appendChild(im);
      } else {
        box.appendChild(missBox(s.asset));
      }
      box.dataset.hide = '0';
      $('sprites').appendChild(box);
      PV.sprites[s.asset] = box;
      box.style.opacity = '0';
      box.style.transition = 'none';
    }
    box.dataset.hide = '0';
    PV.state[s.asset] = { scale: s.scale, flip: s.flip };
    applyPos(box, s.x, s.scale, s.flip);
    void box.offsetWidth;
    var fade = s.fade === undefined ? 0.35 : s.fade;
    box.style.transition = 'opacity ' + fade + 's linear, left .3s ease, height .3s ease, transform .3s ease';
    box.style.opacity = '1';
  }

  function pvHide(s) {
    var ids = s.asset === 'all' ? Object.keys(PV.sprites) : [s.asset];
    var tok = PV.token;
    var seq = ++PV.hideSeq;
    var fade = s.fade === undefined ? 0.3 : s.fade;
    ids.forEach(function (id) {
      var box = PV.sprites[id];
      if (!box) return;
      box.dataset.hide = String(seq);
      box.style.transition = 'opacity ' + fade + 's linear';
      box.style.opacity = '0';
      setTimeout(function () {
        if (tok !== PV.token) return;
        if (box.dataset.hide !== String(seq)) return;
        if (box.parentNode) box.parentNode.removeChild(box);
        if (PV.sprites[id] === box) delete PV.sprites[id];
      }, fade * 1000 + 40);
    });
  }

  function pvMove(s) {
    var box = PV.sprites[s.asset];
    if (!box) return;
    var st = PV.state[s.asset] || { scale: 100, flip: false };
    var t = s.t === undefined ? 0.4 : s.t;
    box.style.transition = 'left ' + t + 's ease, height ' + t + 's ease, transform ' + t + 's ease';
    applyPos(box, s.x, st.scale, st.flip);
    void box.offsetWidth;
  }

  function pvSay(s) {
    var dlg = $('dialog');
    dlg.hidden = false;
    var who = $('who');
    if (s.who) {
      who.hidden = false;
      who.textContent = s.who;
      who.style.color = VS.charColor(S.project, s.who);
    } else {
      who.hidden = true;
    }
    PV.full = s.text || '';
    PV.shown = 0;
    PV.done = false;
    $('dline').textContent = '';
    $('nextMark').hidden = true;
    if (PV.typing) { clearInterval(PV.typing); PV.typing = 0; }

    var speed = S.project.settings.textSpeed || 40;
    var ms = Math.max(8, Math.round(1000 / speed));
    var tok = PV.token;
    PV.typing = setInterval(function () {
      if (tok !== PV.token) { clearInterval(PV.typing); PV.typing = 0; return; }
      PV.shown++;
      $('dline').textContent = PV.full.slice(0, PV.shown);
      if (PV.shown >= PV.full.length) pvTypingDone();
    }, ms);
    setPvStatus('第 ' + s.line + ' 行');
  }

  function pvTypingDone() {
    if (PV.typing) { clearInterval(PV.typing); PV.typing = 0; }
    $('dline').textContent = PV.full;
    PV.done = true;
    $('nextMark').hidden = false;
    scheduleAuto();
  }

  function scheduleAuto() {
    if (PV.pending) { clearTimeout(PV.pending); PV.pending = 0; }
    if (!PV.auto || !PV.active || !PV.done) return;
    var tok = PV.token;
    PV.pending = setTimeout(function () {
      if (tok !== PV.token || !PV.active) return;
      pvAdvance();
    }, (S.project.settings.autoDelay || 1.3) * 1000);
  }

  function pvAdvance() {
    if (!PV.active) return;
    if (!$('choices').hidden) return;
    if (!PV.done) { pvTypingDone(); return; }
    if (PV.pending) { clearTimeout(PV.pending); PV.pending = 0; }
    if (PV.stepTimer) { clearTimeout(PV.stepTimer); PV.stepTimer = 0; }
    $('chapter').style.opacity = '0';
    PV.pc++;
    pvStep();
  }

  function pvChoice(s) {
    var box = $('choices');
    box.innerHTML = '';
    if (s.prompt) {
      var p = document.createElement('div');
      p.style.cssText = 'font-size:11px;color:#9aa6bb;letter-spacing:.1em;margin-bottom:2px';
      p.textContent = s.prompt;
      box.appendChild(p);
    }
    s.options.forEach(function (op) {
      var b = document.createElement('button');
      b.className = 'choice';
      b.type = 'button';
      b.textContent = op.text;
      b.addEventListener('click', function (ev) {
        ev.stopPropagation();
        box.hidden = true;
        PV.pc = (op.index === null || op.index === undefined) ? PV.pc + 1 : op.index;
        PV.done = true;
        pvStep();
      });
      box.appendChild(b);
    });
    box.hidden = false;
    setPvStatus('第 ' + s.line + ' 行 · 等选择');
  }

  function pvWait(s) {
    var tok = PV.token;
    setPvStatus('第 ' + s.line + ' 行 · 等 ' + s.sec + ' 秒');
    if (PV.stepTimer) { clearTimeout(PV.stepTimer); PV.stepTimer = 0; }
    PV.stepTimer = setTimeout(function () {
      if (tok !== PV.token) return;
      PV.stepTimer = 0;
      PV.pc++;
      pvStep();
    }, s.sec * 1000);
  }

  function pvChapter(s) {
    var ch = $('chapter');
    ch.querySelector('span').textContent = s.text || '';
    ch.style.opacity = '1';
    var tok = PV.token;
    if (PV.stepTimer) { clearTimeout(PV.stepTimer); PV.stepTimer = 0; }
    PV.stepTimer = setTimeout(function () {
      if (tok !== PV.token) return;
      ch.style.opacity = '0';
      PV.stepTimer = setTimeout(function () {
        if (tok !== PV.token) return;
        PV.stepTimer = 0;
        PV.pc++;
        pvStep();
      }, 620);
    }, 1600);
  }

  function pvShake(s) {
    var inner = $('stageInner');
    inner.classList.remove('shake');
    void inner.offsetWidth;
    inner.classList.add('shake');
    var tok = PV.token;
    setTimeout(function () {
      if (tok !== PV.token) return;
      inner.classList.remove('shake');
    }, (s.dur || 0.4) * 1000);
  }

  function pvFlash(s) {
    var fl = $('flash');
    fl.style.transition = 'none';
    fl.style.background = s.color || '#ffffff';
    fl.style.opacity = '0.9';
    void fl.offsetWidth;
    fl.style.transition = 'opacity ' + (s.dur || 0.3) + 's ease-out';
    fl.style.opacity = '0';
  }

  function rampVolume(el, from, to, dur) {
    if (PV.bgmTimer) { clearInterval(PV.bgmTimer); PV.bgmTimer = 0; }
    var t0 = Date.now();
    var ms = Math.max(1, dur * 1000);
    el.volume = Math.max(0, Math.min(1, from));
    PV.bgmTimer = setInterval(function () {
      var k = Math.min(1, (Date.now() - t0) / ms);
      el.volume = Math.max(0, Math.min(1, from + (to - from) * k));
      if (k >= 1) { clearInterval(PV.bgmTimer); PV.bgmTimer = 0; }
    }, 40);
  }

  function pvBgm(s) {
    var a = findAsset(s.asset);
    if (!a || !a.src) { setPvStatus('缺少音频素材「' + s.asset + '」'); return; }
    var scale = (s.volume === undefined ? 1 : s.volume);
    if (PV.bgm && PV.bgmName === s.asset) {
      PV.bgmScale = scale;
      PV.bgm.volume = Math.max(0, Math.min(1, PV.volume * scale));
      return;
    }
    stopBgm(0.2);
    var el = new Audio(a.src);
    el.loop = s.loop !== false;
    el.volume = 0;
    var p = el.play();
    if (p && p.catch) {
      p.catch(function () { setPvStatus('浏览器拦截了自动播放：点一下舞台任意处即可开始'); });
    }
    PV.bgm = el;
    PV.bgmName = s.asset;
    PV.bgmScale = scale;
    rampVolume(el, 0, PV.volume * scale, s.fade === undefined ? 1 : s.fade);
  }

  function stopBgm(fade) {
    if (PV.bgmTimer) { clearInterval(PV.bgmTimer); PV.bgmTimer = 0; }
    var el = PV.bgm;
    PV.bgm = null;
    PV.bgmName = '';
    if (!el) return;
    if (fade && fade > 0.02) {
      rampVolume(el, el.volume, 0, fade);
      setTimeout(function () {
        try { el.pause(); } catch (e) { /* 忽略 */ }
      }, fade * 1000 + 60);
    } else {
      try { el.pause(); } catch (e) { /* 忽略 */ }
    }
  }

  function pvSfx(s) {
    var a = findAsset(s.asset);
    if (!a || !a.src) { setPvStatus('缺少音效素材「' + s.asset + '」'); return; }
    try {
      var el = new Audio(a.src);
      el.volume = Math.max(0, Math.min(1, PV.volume * (s.volume === undefined ? 1 : s.volume)));
      var p = el.play();
      if (p && p.catch) p.catch(function () { /* 忽略 */ });
    } catch (e) { /* 忽略 */ }
  }

  function pvEnd(text) {
    PV.active = false;
    if (PV.typing) { clearInterval(PV.typing); PV.typing = 0; }
    if (PV.pending) { clearTimeout(PV.pending); PV.pending = 0; }
    if (PV.stepTimer) { clearTimeout(PV.stepTimer); PV.stepTimer = 0; }
    var e = $('endcard');
    e.textContent = text || '— 本章完 —';
    e.hidden = false;
    $('choices').hidden = true;
    $('nextMark').hidden = true;
    stopBgm(1.2);
    setPvStatus('演完了 · 停在第 ' + (PV.line || 0) + ' 行');
  }

  /* ==========================================================================
   * 导出
   * ======================================================================== */

  function safeName() {
    return (S.project.name || '剧情').replace(/[\\/:*?"<>|\s]+/g, '_').slice(0, 60);
  }

  function download(filename, text, mime) {
    var blob = new Blob([text], { type: mime + ';charset=utf-8' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    setTimeout(function () {
      URL.revokeObjectURL(url);
      if (a.parentNode) a.parentNode.removeChild(a);
    }, 3000);
  }

  function exportProject() {
    reparse();
    download(safeName() + '.vnproj.json', VS.serializeProject(S.project), 'application/json');
    toast('已导出工程（含 ' + S.project.assets.length + ' 个素材），双击不了就直接拖回来自动打开');
  }

  function exportRuntime() {
    reparse();
    var rt = VS.toRuntime(S.project, S.parsed);
    download(safeName() + '.vn.json', JSON.stringify(rt, null, 1), 'application/json');
    toast('已导出运行脚本：' + rt.script.length + ' 条指令 / ' + rt.assets.length + ' 个素材');
  }

  function exportAssets() {
    reparse();
    var list = S.project.assets.map(function (a) {
      return {
        name: a.name,
        kind: a.kind,
        file: VS.fileNameOf(a),
        bytes: a.size || 0,
        size: a.w ? a.w + '×' + a.h : ''
      };
    });
    var payload = {
      title: S.project.name,
      count: list.length,
      assets: list,
      note: '把 file 列出的文件按原文件名放进游戏素材目录；剧本里用 name 引用。'
    };
    download(safeName() + '.assets.json', JSON.stringify(payload, null, 1), 'application/json');
    toast('已导出素材清单（' + list.length + ' 个文件）');
  }

  function exportPlayer() {
    reparse();
    var tpl = $('playerTpl');
    if (!tpl) { toast('找不到播放器模板', true); return; }
    var data = VS.toPlayerData(S.project, S.parsed);
    var json = JSON.stringify(data)
      .replace(/</g, '\\u003c')
      .replace(/\u2028/g, '\\u2028')
      .replace(/\u2029/g, '\\u2029');
    var html = '<!DOCTYPE html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n' +
      '<meta name="viewport" content="width=device-width,initial-scale=1">\n<title>' + esc(S.project.name) + '</title>\n' +
      '</head>\n<body>\n' + tpl.innerHTML.replace('__VN_DATA__', function () { return json; }) + '\n</body>\n</html>';
    download(safeName() + '.html', html, 'text/html');

    var relative = S.project.assets.filter(function (a) { return a.src.indexOf('data:') !== 0; }).length;
    if (relative) toast('已导出播放器。注意：有 ' + relative + ' 个示例素材是相对路径，换电脑可能加载不出来，正式用建议「导入素材」重新导一遍', true);
    else toast('已导出独立播放器，双击就能演');
  }

  /* ==========================================================================
   * 工程加载 / 新建
   * ======================================================================== */

  function loadProject(project, silent, persist) {
    S.project = VS.normalizeProject(project);
    S.selected = '';
    $('projName').value = S.project.name;
    $('script').value = S.project.script;
    $('script').selectionStart = 0;
    $('script').selectionEnd = 0;
    S.saved = true;
    reparse();
    renderAssets();
    pvClearStage(true);
    renderSaveState();
    renderAssetDetail();
    if (persist) {
      persistAssets();
      persistMeta();
    }
    if (!silent) toast('已载入《' + S.project.name + '》');
  }

  function loadDemo() {
    var p = VS.newProject('序章丨一切的开端');
    p.script = DEMO_SCRIPT;
    p.assets = DEMO_ASSETS.map(function (a, i) {
      return { id: 'a' + (i + 1), name: a.name, kind: a.kind, src: a.src, mime: a.mime || '', size: 0, w: 0, h: 0 };
    });
    p.chars = { 'Stra': { color: '#b06bff', sprite: 'Stra' } };
    loadProject(p, true, true);
    toast('已载入本作示例素材和一段序章占位剧情，可以直接改');
  }

  function newProject() {
    saveNow(true).then(function () {
      if (!window.confirm('新建会清空当前工程（已经自动保存过一份到浏览器），继续？')) return;
      loadProject(VS.newProject('未命名剧情'), true, true);
      $('script').focus();
      toast('新工程。先把素材拖进来，然后写 @bg 素材名');
    });
  }

  function openProjectFile(file) {
    if (!file) return;
    var fr = new FileReader();
    fr.onload = function () {
      var p = VS.parseProject(String(fr.result || ''));
      if (!p) { toast('这个文件不是工程 JSON', true); return; }
      loadProject(p);
    };
    fr.onerror = function () { toast('读不了这个文件', true); };
    fr.readAsText(file);
  }

  /* ==========================================================================
   * 面板 / 标签切换
   * ======================================================================== */

  function switchPane(name) {
    Array.prototype.forEach.call(document.querySelectorAll('#rightTabs .tab'), function (b) {
      b.classList.toggle('on', b.dataset.pane === name);
    });
    Array.prototype.forEach.call(document.querySelectorAll('.right .pane'), function (p) {
      p.classList.toggle('on', p.id === 'pane-' + name);
    });
    if (name === 'script') setTimeout(renderGutter, 30);
  }

  function setKind(kind) {
    S.kind = kind;
    Array.prototype.forEach.call(document.querySelectorAll('#assetTabs .tab'), function (b) {
      b.classList.toggle('on', b.dataset.kind === kind);
    });
    renderAssets();
  }

  /* ==========================================================================
   * 尺寸
   * ======================================================================== */

  function fitStage() {
    var wrap = $('stageWrap');
    var stage = $('stage');
    if (!wrap || !stage) return;
    var w = wrap.clientWidth - 4;
    var h = wrap.clientHeight - 4;
    if (w <= 0 || h <= 0) return;
    var W = Math.min(w, h * 16 / 9);
    stage.style.width = Math.floor(W) + 'px';
    stage.style.height = Math.floor(W * 9 / 16) + 'px';
    renderGutter();
  }

  /* ==========================================================================
   * 绑定
   * ======================================================================== */

  function bind() {
    var ta = $('script');

    ta.addEventListener('input', onScriptInput);
    ta.addEventListener('scroll', syncGutterScroll);
    ta.addEventListener('click', function () { markCaretLine(); renderEditorFoot(); });
    ta.addEventListener('keyup', function (e) {
      if (/^Arrow|^Home$|^End$|^Page/.test(e.key)) { markCaretLine(); renderEditorFoot(); }
    });

    $('gutter').addEventListener('click', function (e) {
      var row = e.target.closest ? e.target.closest('.gl') : null;
      if (!row || !row.dataset.line) return;
      jumpToLine(parseInt(row.dataset.line, 10));
    });

    $('projName').addEventListener('input', function () {
      S.project.name = this.value.trim() || '未命名剧情';
      scheduleSave();
    });

    $('assetTabs').addEventListener('click', function (e) {
      var b = e.target.closest ? e.target.closest('.tab') : null;
      if (!b) return;
      setKind(b.dataset.kind);
    });

    $('rightTabs').addEventListener('click', function (e) {
      var b = e.target.closest ? e.target.closest('.tab') : null;
      if (!b) return;
      switchPane(b.dataset.pane);
    });

    $('assetSearch').addEventListener('input', function () {
      S.query = this.value.trim();
      renderAssets();
    });

    $('assetGrid').addEventListener('click', function (e) {
      var b = e.target.closest ? e.target.closest('.asset') : null;
      if (!b) return;
      S.selected = (S.selected === b.dataset.id) ? '' : b.dataset.id;
      renderAssets();
    });

    $('insertBar').addEventListener('click', function (e) {
      var b = e.target.closest ? e.target.closest('.chip') : null;
      if (!b) return;
      switchPane('script');
      insertOf(b.dataset.insert);
    });

    $('outlineList').addEventListener('click', function (e) {
      var b = e.target.closest ? e.target.closest('.olabel') : null;
      if (!b) return;
      jumpToLine(parseInt(b.dataset.line, 10));
    });

    $('issueList').addEventListener('click', function (e) {
      var b = e.target.closest ? e.target.closest('.issue[data-line]') : null;
      if (!b) return;
      jumpToLine(parseInt(b.dataset.line, 10));
    });

    $('charList').addEventListener('input', function (e) {
      var t = e.target;
      if (t.dataset && t.dataset.char) {
        var name = t.dataset.char;
        if (!S.project.chars[name]) S.project.chars[name] = { color: '', sprite: '' };
        S.project.chars[name].color = t.value;
        scheduleSave();
      }
    });

    $('charList').addEventListener('change', function (e) {
      var t = e.target;
      if (t.dataset && t.dataset.sprite) {
        var name = t.dataset.sprite;
        if (!S.project.chars[name]) S.project.chars[name] = { color: '', sprite: '' };
        S.project.chars[name].sprite = t.value;
        scheduleSave();
      }
    });

    $('btnImport').addEventListener('click', function () { $('fileInput').click(); });
    $('btnImportDir').addEventListener('click', function () { $('dirInput').click(); });
    $('btnDemo').addEventListener('click', loadDemo);

    $('fileInput').addEventListener('change', function () {
      importFiles(this.files);
      this.value = '';
    });
    $('dirInput').addEventListener('change', function () {
      importFiles(this.files);
      this.value = '';
    });
    $('projInput').addEventListener('change', function () {
      openProjectFile(this.files && this.files[0]);
      this.value = '';
    });

    $('btnNew').addEventListener('click', newProject);
    $('btnOpen').addEventListener('click', function () { $('projInput').click(); });
    $('btnSave').addEventListener('click', function () {
      saveNow(false);
      exportProjectFile();
    });

    $('btnExport').addEventListener('click', function (e) {
      e.stopPropagation();
      var m = $('exportMenu');
      m.hidden = !m.hidden;
    });
    document.addEventListener('click', function (e) {
      var m = $('exportMenu');
      if (!m.hidden && !m.contains(e.target) && e.target.id !== 'btnExport') m.hidden = true;
    });
    $('exportMenu').addEventListener('click', function (e) {
      var b = e.target.closest ? e.target.closest('[data-export]') : null;
      if (!b) return;
      $('exportMenu').hidden = true;
      var what = b.dataset.export;
      if (what === 'project') exportProject();
      else if (what === 'runtime') exportRuntime();
      else if (what === 'player') exportPlayer();
      else if (what === 'assets') exportAssets();
    });

    $('btnFromLine').addEventListener('click', function () { pvStart(caretLine()); });
    $('btnRestart').addEventListener('click', function () { pvStart(1); });
    $('btnAuto').addEventListener('click', function () {
      PV.auto = !PV.auto;
      this.dataset.on = PV.auto ? '1' : '0';
      if (PV.auto) scheduleAuto();
    });
    $('volRange').addEventListener('input', function () {
      PV.volume = Math.max(0, Math.min(1, parseInt(this.value, 10) / 100));
      if (PV.bgm) PV.bgm.volume = Math.max(0, Math.min(1, PV.volume * PV.bgmScale));
    });
    $('speedRange').addEventListener('input', function () {
      S.project.settings.textSpeed = Math.max(8, Math.min(120, parseInt(this.value, 10) || 40));
      scheduleSave();
    });

    $('stage').addEventListener('click', function (e) {
      if (e.target.closest && e.target.closest('.choice')) return;
      pvAdvance();
    });

    document.addEventListener('keydown', function (e) {
      var tag = (document.activeElement && document.activeElement.tagName) || '';
      var typing = tag === 'TEXTAREA' || tag === 'INPUT';
      var key = (e.key || '').toLowerCase();

      if ((e.ctrlKey || e.metaKey) && key === 's') {
        e.preventDefault();
        saveNow(false);
        exportProjectFile();
        return;
      }
      if ((e.ctrlKey || e.metaKey) && key === 'e') {
        e.preventDefault();
        $('exportMenu').hidden = false;
        return;
      }
      if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
        e.preventDefault();
        pvStart(caretLine());
        return;
      }
      if (typing) return;
      if (e.key === ' ' || e.key === 'Enter') {
        if ($('choices').hidden) { e.preventDefault(); pvAdvance(); }
      }
    });

    window.addEventListener('resize', fitStage);
    if (window.ResizeObserver) {
      try { new ResizeObserver(fitStage).observe($('stageWrap')); } catch (err) { /* 忽略 */ }
    }

    // 拖文件进来
    var depth = 0;
    window.addEventListener('dragenter', function (e) {
      if (!e.dataTransfer || !e.dataTransfer.types) return;
      depth++;
      $('dropZone').classList.add('on');
    });
    window.addEventListener('dragover', function (e) { e.preventDefault(); });
    window.addEventListener('dragleave', function () {
      depth = Math.max(0, depth - 1);
      if (!depth) $('dropZone').classList.remove('on');
    });
    window.addEventListener('drop', function (e) {
      e.preventDefault();
      depth = 0;
      $('dropZone').classList.remove('on');
      var files = (e.dataTransfer && e.dataTransfer.files) || [];
      if (!files.length) return;
      var first = files[0];
      if (/\.(json|vnproj)$/i.test(first.name || '')) {
        openProjectFile(first);
        return;
      }
      importFiles(files);
    });

    window.addEventListener('beforeunload', function () {
      if (!S.saved) saveNow(true);
    });
  }

  function exportProjectFile() {
    download(safeName() + '.vnproj.json', VS.serializeProject(S.project), 'application/json');
    toast('工程已存成 .vnproj.json（下次直接拖回窗口打开）');
  }

  /* ==========================================================================
   * 启动
   * ======================================================================== */

  function renderHelp() {
    $('helpCmds').innerHTML = VS.COMMANDS.map(function (c) {
      return '<div class="cmdrow"><span class="c1">@' + c.cmd + ' ' + esc(c.args) + '</span>' +
        '<span class="c3">' + esc(c.doc) + '</span></div>';
    }).join('') +
      '<div class="cmdrow" style="border:0"><span class="c1">名字：台词</span><span class="c3">带名字的台词（中英文冒号都行）</span></div>' +
      '<div class="cmdrow" style="border:0"><span class="c1">\\ 文字</span><span class="c3">强制当旁白（正文里有冒号时用）</span></div>' +
      '<div class="cmdrow" style="border:0"><span class="c1">* 标签</span><span class="c3">跳转落点</span></div>' +
      '<div class="cmdrow" style="border:0"><span class="c1">- 选项 -> 标签</span><span class="c3">跟在 @choice 后面的选项</span></div>';
  }

  function boot() {
    bind();
    renderHelp();
    $('volRange').value = String(Math.round(PV.volume * 100));
    openDB().then(function (db) {
      S.db = db;
      if (db) return Promise.all([dbGet(db, KEY_META), dbGet(db, KEY_ASSETS)]);
      return Promise.resolve([lsGet(LS_META), lsGet(LS_ASSETS)]);
    }).then(function (res) {
      var meta = res && res[0];
      var pack = (res && res[1]) || {};
      var assetsMap = (pack && pack.map) ? pack.map : pack;
      var ids = (pack && pack.ids) || (meta && meta.ids) || [];
      if (meta && typeof meta.script === 'string') {
        var list = ids.map(function (id) { return assetsMap[id]; }).filter(Boolean);
        loadProject({
          name: meta.name,
          script: meta.script,
          chars: meta.chars,
          settings: meta.settings,
          assets: list
        }, true, false);
      } else {
        loadDemo();
      }
      $('speedRange').value = String(S.project.settings.textSpeed || 40);
      renderSaveState();
      fitStage();
      setTimeout(fitStage, 120);
      setTimeout(fitStage, 420);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
