/* =============================================================================
 * Univerthm 视觉小说编辑器 · 剧本核心
 * -----------------------------------------------------------------------------
 * 不依赖 DOM：浏览器里挂到 window.VNScript，Node 里可以 require 做单元测试。
 *
 * 剧本是**逐行**的纯文本（方便手写、方便 diff）：
 *   1. 空行 / # 注释 / // 注释        → 忽略
 *   2. * 标签名                       → 标签（跳转目标）
 *   3. @指令 [参数] [键=值]            → 一条指令（中英双写，见 COMMAND_ALIASES）
 *   4. - 选项文本 -> 标签              → 只能出现在 @choice 后面
 *   5. 名字：台词                      → 带名字的台词
 *   6. 其它文字                        → 旁白
 *   7. \ 开头的文字                    → 强制旁白（正文里出现冒号时用）
 *
 * 解析结果 steps 是一条扁平的指令流，预览器 / 导出的播放器 / 引擎都按它执行。
 * ========================================================================== */
(function (root, factory) {
  var api = factory();
  if (typeof module === 'object' && module.exports) {
    module.exports = api;
  } else {
    root.VNScript = api;
  }
})(typeof self !== 'undefined' ? self : null, function () {
  'use strict';

  var VERSION = 1;
  var FORMAT = 'vnscript';

  /** 立绘位置 → 舞台宽度百分比（预览和播放器都用这一套） */
  var POSITIONS = { left: 23, center: 50, right: 77, '左': 23, '中': 50, '右': 77 };

  var PALETTE = ['#b06bff', '#4cc9f0', '#ffd166', '#7cf5c1', '#f72585', '#ff8a5c', '#9d8bff', '#5ce1e6'];

  var COMMAND_ALIASES = {
    bg: 'bg', '背景': 'bg',
    show: 'show', '立绘': 'show', '显示': 'show',
    hide: 'hide', '隐藏': 'hide',
    move: 'move', '移动': 'move',
    clear: 'clear', '清空': 'clear',
    bgm: 'bgm', '音乐': 'bgm',
    bgmstop: 'bgmstop', bgmstop_: 'bgmstop', '停止音乐': 'bgmstop', '静音': 'bgmstop',
    sfx: 'sfx', '音效': 'sfx',
    wait: 'wait', '等待': 'wait',
    shake: 'shake', '震动': 'shake',
    flash: 'flash', '闪白': 'flash',
    chapter: 'chapter', '章节': 'chapter',
    choice: 'choice', '选择': 'choice',
    jump: 'jump', '跳转': 'jump',
    end: 'end', '结束': 'end',
    label: 'label', '标签': 'label'
  };

  /** 指令速查表：帮助页 / 插入工具条直接读它 */
  var COMMANDS = [
    { cmd: 'bg', args: '<素材名> [fade=0.6]', doc: '换背景，交叉淡化' },
    { cmd: 'show', args: '<素材名> [left|center|right] [scale=100] [flip] [fade=0.35]', doc: '显示立绘 / 图片' },
    { cmd: 'hide', args: '<素材名|all> [fade=0.3]', doc: '收起立绘' },
    { cmd: 'move', args: '<素材名> <left|center|right> [t=0.4]', doc: '立绘换位（带补间）' },
    { cmd: 'clear', args: '[fade=0.3]', doc: '清空所有立绘' },
    { cmd: 'bgm', args: '<素材名> [volume=100] [fade=1] [once]', doc: '循环播放背景音乐' },
    { cmd: 'bgmstop', args: '[fade=1]', doc: '停止背景音乐' },
    { cmd: 'sfx', args: '<素材名> [volume=100]', doc: '播放一次音效' },
    { cmd: 'wait', args: '<秒>', doc: '等待（自动继续）' },
    { cmd: 'shake', args: '[强度=6] [时长=0.4]', doc: '画面震动' },
    { cmd: 'flash', args: '[颜色=#ffffff] [时长=0.3]', doc: '闪一下' },
    { cmd: 'chapter', args: '<标题>', doc: '章节卡（黑场 + 标题）' },
    { cmd: 'choice', args: '[提示语]', doc: '选项，下面每行写「- 文本 -> 标签」' },
    { cmd: 'jump', args: '<标签>', doc: '跳到某个标签' },
    { cmd: 'end', args: '[结束语]', doc: '本段结束（停在结束画面）' },
    { cmd: 'label', args: '<标签>', doc: '定义标签（等价于 * 标签名）' }
  ];

  /* -------------------------------------------------------------------------
   * 小工具
   * ---------------------------------------------------------------------- */

  function trim(s) { return String(s === undefined || s === null ? '' : s).trim(); }

  function numOf(v, d) {
    if (v === undefined || v === null || v === '') return d;
    var n = parseFloat(v);
    return isFinite(n) ? n : d;
  }

  function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

  function round3(v) { return Math.round(v * 1000) / 1000; }

  /** 把一行拆成 token：空格分隔，双引号里的空格保留 */
  function splitTokens(s) {
    var out = [], buf = '', q = false;
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i);
      if (c === '"') { q = !q; continue; }
      if (!q && /\s/.test(c)) {
        if (buf) { out.push(buf); buf = ''; }
        continue;
      }
      buf += c;
    }
    if (buf) out.push(buf);
    return out;
  }

  /** token → { pos: 位置参数, kv: 键值参数 } */
  function readArgs(tokens) {
    var pos = [], kv = {};
    for (var i = 0; i < tokens.length; i++) {
      var t = tokens[i], eq = t.indexOf('=');
      if (eq > 0) kv[t.slice(0, eq).toLowerCase()] = t.slice(eq + 1);
      else pos.push(t);
    }
    return { pos: pos, kv: kv };
  }

  /** 布尔开关：既认 flip / flip=true，也认 flip=0 */
  function flag(a, name) {
    if (a.kv[name] !== undefined) return !/^(0|false|no|off|否)$/i.test(a.kv[name]);
    for (var i = 0; i < a.pos.length; i++) {
      if (String(a.pos[i]).toLowerCase() === name) return true;
    }
    return false;
  }

  function posOf(tok, dflt) {    if (tok === undefined) return { name: dflt, x: POSITIONS[dflt] };
    var key = String(tok).toLowerCase();
    if (POSITIONS[key] !== undefined) return { name: key === '左' ? 'left' : key === '中' ? 'center' : key === '右' ? 'right' : key, x: POSITIONS[key] };
    // 也接受直接写数字（舞台宽度的百分比）
    var n = parseFloat(tok);
    if (isFinite(n)) return { name: 'custom', x: clamp(n, 0, 100) };
    return { name: dflt, x: POSITIONS[dflt] };
  }

  function posName(tok) {
    var key = String(tok || '').toLowerCase();
    if (key === 'left' || key === '左') return 'left';
    if (key === 'center' || key === '中') return 'center';
    if (key === 'right' || key === '右') return 'right';
    return 'center';
  }

  function isDepth(t) {
    return /^[-•·]\s+/.test(t);
  }

  /* -------------------------------------------------------------------------
   * 台词 / 旁白判定
   * ---------------------------------------------------------------------- */

  /** 「名字：台词」→ { who, text }；不像台词的返回 null */
  function dialogueSplit(t) {
    var idx = -1;
    for (var i = 0; i < t.length; i++) {
      var c = t.charAt(i);
      if (c === '：' || c === ':') { idx = i; break; }
    }
    if (idx <= 0) return null;
    var who = t.slice(0, idx).trim();
    var text = t.slice(idx + 1).trim();
    if (!who || !text) return null;
    if (who.length > 12) return null;                                     // 名字不会很长
    if (/[\s　，。！？；、…,.;!?"'（）()【】「」《》\-—~～]/.test(who)) return null;   // 名字里不会有标点
    if (/^[0-9.]+$/.test(who)) return null;
    return { who: who, text: text };
  }

  /* -------------------------------------------------------------------------
   * 解析
   * ---------------------------------------------------------------------- */

  /**
   * parse(text) → { steps, labels, labelMap, characters, errors, lineCount }
   * 出错不抛异常：错误进 errors（带行号），能继续解析的部分照常输出，编辑器里好定位。
   */
  function parse(text) {
    var lines = String(text === undefined || text === null ? '' : text).replace(/\r\n?/g, '\n').split('\n');
    var steps = [];
    var labels = [];
    var labelMap = {};
    var chars = {};
    var charOrder = [];
    var errors = [];
    var openChoice = null;

    function push(step) {
      step.line = step.line === undefined ? 0 : step.line;
      steps.push(step);
      return step;
    }

    function err(line, message) { errors.push({ line: line, message: message }); }

    for (var i = 0; i < lines.length; i++) {
      var ln = i + 1;
      var raw = lines[i];
      var t = raw.trim();

      if (!t) continue;
      if (t.charAt(0) === '#' || t.slice(0, 2) === '//') continue;

      /* ---- 标签 ---- */
      if (t.charAt(0) === '*') {
        var tagName = t.slice(1).trim();
        openChoice = null;
        if (!tagName) { err(ln, '标签名为空：写成「* 标签名」'); continue; }
        if (labelMap[tagName] !== undefined) err(ln, '标签「' + tagName + '」重复定义了');
        labelMap[tagName] = steps.length;
        labels.push({ name: tagName, index: steps.length, line: ln });
        continue;
      }

      /* ---- 命令 ---- */
      if (t.charAt(0) === '@') {
        openChoice = null;
        var body = t.slice(1).trim();
        var mm = /^([A-Za-z_\u4e00-\u9fa5][A-Za-z0-9_\u4e00-\u9fa5]*)\s*([\s\S]*)$/.exec(body);
        if (!mm) { err(ln, '指令格式不对：' + t); continue; }
        var rawCmd = mm[1];
        var rest = mm[2] || '';
        var cmd = COMMAND_ALIASES[rawCmd.toLowerCase()] || COMMAND_ALIASES[rawCmd];
        if (!cmd) { err(ln, '不认识的指令 @' + rawCmd + '（点右侧「语法」看全部指令）'); continue; }

        var tokens = splitTokens(rest);
        var a = readArgs(tokens);
        var step;

        if (cmd === 'bg') {
          if (!a.pos[0]) { err(ln, '@bg 需要一个素材名，例如 @bg 教室'); continue; }
          var fade = flag(a, 'cut') ? 0 : numOf(a.kv.fade, 0.6);
          step = push({ op: 'bg', asset: a.pos[0], fade: clamp(fade, 0, 8), line: ln });
        } else if (cmd === 'show') {
          if (!a.pos[0]) { err(ln, '@show 需要一个素材名，例如 @show Stra right'); continue; }
          var p = posOf(a.pos[1], 'center');
          var scale = clamp(numOf(a.kv.scale, 100), 5, 500);
          step = push({
            op: 'show',
            asset: a.pos[0],
            pos: p.name,
            x: p.x,
            scale: round3(scale),
            flip: flag(a, 'flip') || flag(a, 'mirror'),
            fade: clamp(numOf(a.kv.fade, 0.35), 0, 8),
            line: ln
          });
        } else if (cmd === 'hide') {
          var who = a.pos[0] || 'all';
          step = push({ op: 'hide', asset: who, fade: clamp(numOf(a.kv.fade, 0.3), 0, 8), line: ln });
        } else if (cmd === 'move') {
          if (!a.pos[0]) { err(ln, '@move 需要素材名和位置，例如 @move Stra right'); continue; }
          var pm = posOf(a.pos[1], 'center');
          step = push({ op: 'move', asset: a.pos[0], pos: pm.name, x: pm.x, t: clamp(numOf(a.kv.t, 0.4), 0, 8), line: ln });
        } else if (cmd === 'clear') {
          step = push({ op: 'clear', fade: clamp(numOf(a.kv.fade, 0.3), 0, 8), line: ln });
        } else if (cmd === 'bgm') {
          if (!a.pos[0]) { err(ln, '@bgm 需要一个音频素材名'); continue; }
          step = push({
            op: 'bgm',
            asset: a.pos[0],
            volume: clamp(numOf(a.kv.volume, 100), 0, 200) / 100,
            fade: clamp(numOf(a.kv.fade, 1), 0, 20),
            loop: !flag(a, 'once'),
            line: ln
          });
        } else if (cmd === 'bgmstop') {
          step = push({ op: 'bgmstop', fade: clamp(numOf(a.kv.fade, 1), 0, 20), line: ln });
        } else if (cmd === 'sfx') {
          if (!a.pos[0]) { err(ln, '@sfx 需要一个音频素材名'); continue; }
          step = push({ op: 'sfx', asset: a.pos[0], volume: clamp(numOf(a.kv.volume, 80), 0, 200) / 100, line: ln });
        } else if (cmd === 'wait') {
          step = push({ op: 'wait', sec: clamp(numOf(a.pos[0], 1), 0.05, 60), line: ln });
        } else if (cmd === 'shake') {
          step = push({ op: 'shake', strength: clamp(numOf(a.pos[0], 6), 0, 60), dur: clamp(numOf(a.pos[1], 0.4), 0.05, 6), line: ln });
        } else if (cmd === 'flash') {
          var color = (a.pos[0] && a.pos[0].charAt(0) === '#') ? a.pos[0] : '#ffffff';
          step = push({ op: 'flash', color: color, dur: clamp(numOf(a.pos[1], 0.3), 0.05, 6), line: ln });
        } else if (cmd === 'chapter') {
          var title = trim(rest);
          if (!title) { err(ln, '@chapter 需要一个标题'); continue; }
          step = push({ op: 'chapter', text: title, line: ln });
        } else if (cmd === 'choice') {
          step = push({ op: 'choice', prompt: trim(rest), options: [], line: ln });
          openChoice = step;
        } else if (cmd === 'jump') {
          if (!a.pos[0]) { err(ln, '@jump 需要一个标签名'); continue; }
          step = push({ op: 'jump', target: a.pos[0], index: null, line: ln });
        } else if (cmd === 'end') {
          step = push({ op: 'end', text: trim(rest), line: ln });
        } else if (cmd === 'label') {
          var nm = trim(rest);
          if (!nm) { err(ln, '@label 需要一个标签名'); continue; }
          if (labelMap[nm] !== undefined) err(ln, '标签「' + nm + '」重复定义了');
          labelMap[nm] = steps.length;
          labels.push({ name: nm, index: steps.length, line: ln });
        }
        continue;
      }

      /* ---- 选项行（必须跟在 @choice 后面）---- */
      if (isDepth(t)) {
        if (!openChoice) { err(ln, '这个选项前面没有 @choice'); continue; }
        var optBody = t.replace(/^[-•·]\s+/, '');
        var tm = /^([\s\S]*?)\s*(?:->|→|=>)\s*([\s\S]+)$/.exec(optBody);
        var optText = trim(tm ? tm[1] : optBody);
        if (!optText) { err(ln, '选项文本是空的'); continue; }
        openChoice.options.push({ text: optText, target: tm ? trim(tm[2]) : null, index: null });
        continue;
      }

      /* ---- 强制旁白 ---- */
      if (t.charAt(0) === '\\') {
        openChoice = null;
        push({ op: 'narr', text: t.slice(1).trim(), line: ln });
        continue;
      }

      /* ---- 台词 / 旁白 ---- */
      openChoice = null;
      var dv = dialogueSplit(t);
      if (dv) {
        if (!chars[dv.who]) {
          chars[dv.who] = { name: dv.who, count: 0, firstLine: ln };
          charOrder.push(dv.who);
        }
        chars[dv.who].count++;
        push({ op: 'say', who: dv.who, text: dv.text, line: ln });
      } else {
        push({ op: 'narr', text: t, line: ln });
      }
    }

    /* ---- 收尾：检查选择块、解析跳转目标 ---- */
    for (var s = 0; s < steps.length; s++) {
      var st = steps[s];
      if (st.op === 'choice') {
        if (!st.options.length) err(st.line, '@choice 下面没有选项（写「- 文本 -> 标签」）');
        for (var o = 0; o < st.options.length; o++) {
          var op = st.options[o];
          if (op.target) {
            if (labelMap[op.target] === undefined) err(st.line, '选项指向的标签「' + op.target + '」不存在');
            else op.index = labelMap[op.target];
          } else {
            op.index = s + 1;                       // 不写目标 = 接着往下走
          }
        }
      } else if (st.op === 'jump') {
        if (labelMap[st.target] === undefined) err(st.line, '跳转目标「' + st.target + '」不存在');
        else st.index = labelMap[st.target];
      }
    }

    return {
      steps: steps,
      labels: labels,
      labelMap: labelMap,
      characters: charOrder.map(function (n) { return chars[n]; }),
      errors: errors,
      lineCount: lines.length
    };
  }

  /** 某一行（1 起）对应的第一条指令下标 —— 编辑器「从本行预览」用 */
  function indexAtLine(parsed, line) {
    for (var i = 0; i < parsed.steps.length; i++) {
      if (parsed.steps[i].line >= line) return i;
    }
    return parsed.steps.length;
  }

  /** 素材被剧本引用了多少次（编辑器里显示用） */
  function assetUsage(parsed) {
    var map = {};
    for (var i = 0; i < parsed.steps.length; i++) {
      var a = parsed.steps[i].asset;
      if (a) map[a] = (map[a] || 0) + 1;
    }
    return map;
  }

  /* -------------------------------------------------------------------------
   * 工程 / 导出
   * ---------------------------------------------------------------------- */

  function defaultChars() { return {}; }

  function newProject(name) {
    return {
      vn: VERSION,
      name: name || '未命名剧情',
      script: '',
      chars: defaultChars(),
      settings: { textSpeed: 40, autoDelay: 1.3 },
      assets: [],
      updatedAt: Date.now()
    };
  }

  /** 读回来的工程做一次容错，缺字段补默认值 */
  function normalizeProject(raw) {
    var p = (raw && typeof raw === 'object') ? raw : {};
    var out = newProject(trim(p.name) || '未命名剧情');
    out.script = typeof p.script === 'string' ? p.script : '';
    out.settings = { textSpeed: 40, autoDelay: 1.3 };
    if (p.settings && typeof p.settings === 'object') {
      out.settings.textSpeed = clamp(numOf(p.settings.textSpeed, 40), 5, 200);
      out.settings.autoDelay = clamp(numOf(p.settings.autoDelay, 1.3), 0, 20);
    }
    var cs = p.chars && typeof p.chars === 'object' ? p.chars : {};
    Object.keys(cs).forEach(function (k) {
      if (!k) return;
      var c = cs[k] || {};
      out.chars[k] = {
        color: typeof c.color === 'string' && c.color ? c.color : '',
        sprite: typeof c.sprite === 'string' ? c.sprite : ''
      };
    });
    var assets = Array.isArray(p.assets) ? p.assets : [];
    var seen = {};
    out.assets = assets.filter(function (a) {
      return a && typeof a === 'object' && typeof a.name === 'string' && typeof a.src === 'string';
    }).map(function (a, i) {
      var name = a.name;
      var id = typeof a.id === 'string' && a.id ? a.id : ('a' + i);
      while (seen[id]) id = id + '_';
      seen[id] = 1;
      return {
        id: id,
        name: name,
        kind: a.kind === 'char' || a.kind === 'audio' ? a.kind : 'bg',
        src: a.src,
        mime: typeof a.mime === 'string' ? a.mime : '',
        size: numOf(a.size, 0),
        w: numOf(a.w, 0),
        h: numOf(a.h, 0)
      };
    });
    out.updatedAt = numOf(p.updatedAt, Date.now());
    return out;
  }

  function charColor(project, name) {
    var c = project && project.chars ? project.chars[name] : null;
    if (c && c.color) return c.color;
    var h = 0;
    for (var i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0;
    return PALETTE[h % PALETTE.length];
  }

  function extOf(mime, src) {
    var m = String(mime || '');
    if (m.indexOf('png') >= 0) return '.png';
    if (m.indexOf('jpeg') >= 0 || m.indexOf('jpg') >= 0) return '.jpg';
    if (m.indexOf('webp') >= 0) return '.webp';
    if (m.indexOf('gif') >= 0) return '.gif';
    if (m.indexOf('ogg') >= 0) return '.ogg';
    if (m.indexOf('mpeg') >= 0 || m.indexOf('mp3') >= 0) return '.mp3';
    if (m.indexOf('wav') >= 0) return '.wav';
    if (m.indexOf('flac') >= 0) return '.flac';
    var s = String(src || '');
    if (s.charAt(0) !== 'data:') {
      var q = s.split('?')[0].split('#')[0];
      var dot = q.lastIndexOf('.');
      if (dot > 0) return q.slice(dot).toLowerCase();
    }
    return '.bin';
  }

  function fileNameOf(asset) {
    var name = String(asset.name || 'asset');
    if (/\.[a-z0-9]{2,5}$/i.test(name)) return name;
    return name + extOf(asset.mime, asset.src);
  }

  /**
   * 导出运行脚本（给游戏引擎读）：
   * 资源按**文件名**引用，不塞 base64 —— 素材原文件另行拷进工程目录。
   */
  function toRuntime(project, parsed) {
    var p = parsed || parse(project.script);
    var assets = project.assets.map(function (a) {
      return { name: a.name, kind: a.kind, file: fileNameOf(a), bytes: a.size || 0 };
    });
    var characters = p.characters.map(function (c) {
      var conf = (project.chars && project.chars[c.name]) || {};
      return {
        name: c.name,
        color: charColor(project, c.name),
        sprite: conf.sprite || '',
        lines: c.count
      };
    });
    var script = p.steps.map(function (s) {
      var o = { op: s.op };
      if (s.asset !== undefined) o.asset = s.asset;
      if (s.who !== undefined) o.who = s.who;
      if (s.text !== undefined) o.text = s.text;
      if (s.pos !== undefined) { o.pos = s.pos; o.x = s.x; }
      if (s.scale !== undefined) o.scale = s.scale;
      if (s.flip !== undefined) o.flip = s.flip;
      if (s.fade !== undefined) o.fade = s.fade;
      if (s.t !== undefined) o.t = s.t;
      if (s.sec !== undefined) o.sec = s.sec;
      if (s.strength !== undefined) { o.strength = s.strength; o.dur = s.dur; }
      if (s.color !== undefined) { o.color = s.color; o.dur = s.dur; }
      if (s.volume !== undefined) o.volume = s.volume;
      if (s.loop !== undefined) o.loop = s.loop;
      if (s.prompt !== undefined) o.prompt = s.prompt;
      if (s.target !== undefined) { o.label = s.target; o.index = s.index; }
      if (s.options !== undefined) {
        o.options = s.options.map(function (op) {
          return { text: op.text, label: op.target || '', index: op.index };
        });
      }
      o.line = s.line;
      return o;
    });
    return {
      vn: VERSION,
      format: FORMAT,
      title: project.name,
      updatedAt: project.updatedAt || Date.now(),
      stage: { width: 1280, height: 720 },
      characters: characters,
      assets: assets,
      labels: p.labels.map(function (l) { return { name: l.name, index: l.index, line: l.line }; }),
      script: script
    };
  }

  /** 导出播放器 / 演示用：脚本 + 素材地址（dataURL 或相对路径） */
  function toPlayerData(project, parsed) {
    var rt = toRuntime(project, parsed);
    var urls = {};
    project.assets.forEach(function (a) { urls[a.name] = a.src; });
    var chars = {};
    project.assets.forEach(function (a) { if (a.kind === 'char') chars[a.name] = 1; });
    return {
      title: rt.title,
      stage: rt.stage,
      script: rt.script,
      urls: urls,
      chars: chars
    };
  }

  function serializeProject(project) {
    var p = normalizeProject(project);
    p.updatedAt = Date.now();
    return JSON.stringify(p, null, 1);
  }

  function parseProject(text) {
    var raw;
    try { raw = JSON.parse(text); } catch (e) { return null; }
    if (!raw || typeof raw !== 'object') return null;
    return normalizeProject(raw);
  }

  /** 剧本字数（不含指令和注释，预览 / 统计用） */
  function wordCount(parsed) {
    var n = 0;
    for (var i = 0; i < parsed.steps.length; i++) {
      var s = parsed.steps[i];
      if (s.op === 'say' || s.op === 'narr') n += String(s.text || '').length;
      else if (s.op === 'choice') {
        for (var o = 0; o < s.options.length; o++) n += String(s.options[o].text || '').length;
      }
    }
    return n;
  }

  return {
    VERSION: VERSION,
    FORMAT: FORMAT,
    POSITIONS: POSITIONS,
    PALETTE: PALETTE,
    COMMANDS: COMMANDS,
    COMMAND_ALIASES: COMMAND_ALIASES,
    trim: trim,
    numOf: numOf,
    clamp: clamp,
    round3: round3,
    splitTokens: splitTokens,
    readArgs: readArgs,
    dialogueSplit: dialogueSplit,
    parse: parse,
    indexAtLine: indexAtLine,
    assetUsage: assetUsage,
    newProject: newProject,
    normalizeProject: normalizeProject,
    charColor: charColor,
    extOf: extOf,
    fileNameOf: fileNameOf,
    toRuntime: toRuntime,
    toPlayerData: toPlayerData,
    serializeProject: serializeProject,
    parseProject: parseProject,
    wordCount: wordCount,
    posName: posName
  };
});
