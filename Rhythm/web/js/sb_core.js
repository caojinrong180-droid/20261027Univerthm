/* =============================================================================
 * Rhythm 故事板制作器 · 数据层
 * -----------------------------------------------------------------------------
 * 只描述「演出」：图层（文字 / 图片 / 形状 / 解锁动画）+ 后处理（Shader）。
 * 谱面只读：这个文件里没有任何修改谱面的函数，工程文件里也不存谱面内容，
 * 只存一份引用信息 `chart = { file, title, ..., hash }`（hash 用来提示「谱面换了」）。
 *
 * 不依赖 DOM：浏览器里挂到 window.SB，Node 里可以 require 做单元测试。
 * 依赖 core.js（只看缓动 / 时间换算），浏览器里要先加载 core.js。
 * ========================================================================== */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory(require('./core.js'));
  } else {
    root.SB = factory(root.RChart);
  }
})(typeof self !== 'undefined' ? self : this, function (RC) {
  'use strict';

  var FORMAT = 'rstory';
  var VERSION = 2;
  var STAGE_W = 1280;
  var STAGE_H = 720;

  /**
   * 场景：故事板 = 一串场景拼起来（解锁场 → 谱面场 → 片尾场 …）。
   * 图层和 Shader 都挂在场景里，时间是**场景内的本地时间**，移动场景不会打乱它们。
   * 只有 `chart` 场景会真的画谱面、并让音乐从这里开始。
   */
  var SCENE_KINDS = [
    { id: 'unlock', label: '解锁场', defLength: 2.6, chart: false, desc: '谱面之前：解锁动画 / 标题卡' },
    { id: 'chart', label: '谱面场', defLength: 0, chart: true, desc: '真正放谱面，音乐从这里开始' },
    { id: 'free', label: '演出场', defLength: 3, chart: false, desc: '片尾 / 结算 / 过场' }
  ];

  var SCENE_MAP = {};
  for (var sk = 0; sk < SCENE_KINDS.length; sk++) SCENE_MAP[SCENE_KINDS[sk].id] = SCENE_KINDS[sk];

  /* ==========================================================================
   * 小工具
   * ======================================================================== */

  function isNum(v) { return typeof v === 'number' && isFinite(v); }

  function num(v, def) {
    if (isNum(v)) return v;
    var f = parseFloat(v);
    return isFinite(f) ? f : def;
  }

  function int(v, def) { return Math.round(num(v, def)); }

  function str(v, def) { return typeof v === 'string' ? v : def; }

  function bool(v, def) { return typeof v === 'boolean' ? v : def; }

  function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

  function round3(v) { return Math.round(num(v, 0) * 1000) / 1000; }

  /** k 处缓动（直接借 core 的实现，故事板和制谱器用同一套曲线） */
  function ease(name, k) { return RC.easeAt(name, k); }

  function easeOutBack(k) {
    var c1 = 1.70158, c3 = c1 + 1;
    return 1 + c3 * Math.pow(k - 1, 3) + c1 * Math.pow(k - 1, 2);
  }

  function hexA(hex, a) {
    var m = /^#?([0-9a-f]{6})$/i.exec(String(hex || ''));
    if (!m) return 'rgba(255,255,255,' + a + ')';
    var n = parseInt(m[1], 16);
    return 'rgba(' + ((n >> 16) & 255) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',' + a + ')';
  }

  /** FNV-1a 32 位：算谱面文本指纹，判断「打开工程时谱面是不是同一份」 */
  function hashText(text) {
    var h = 0x811c9dc5;
    var s = String(text || '');
    for (var i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0;
    }
    return ('00000000' + h.toString(16)).slice(-8);
  }

  /* ==========================================================================
   * 预设目录（UI 下拉框、渲染器、测试都从这里取，避免三处各写一份）
   * ======================================================================== */

  /* ---------- 图层类型 ---------- */

  var LAYER_TYPES = ['text', 'image', 'video', 'shape', 'unlock'];
  var VIDEO_EXT = /\.(mp4|webm|mov|m4v|ogv)$/i;

  var TYPE_LABELS = {
    text: '文字',
    image: '图片',
    shape: '形状',
    unlock: '解锁动画'
  };

  /* ---------- 入场 / 出场 ---------- */

  var IN_PRESETS = [
    { id: 'none', label: '无' },
    { id: 'fade', label: '淡入' },
    { id: 'slideUp', label: '从下滑入' },
    { id: 'slideDown', label: '从上滑入' },
    { id: 'slideLeft', label: '从左滑入' },
    { id: 'slideRight', label: '从右滑入' },
    { id: 'pop', label: '弹入' },
    { id: 'zoom', label: '放大进入' },
    { id: 'zoomOut', label: '缩小进入' },
    { id: 'blurIn', label: '模糊聚焦' },
    { id: 'wipe', label: '揭开' }
  ];

  var OUT_PRESETS = [
    { id: 'none', label: '无' },
    { id: 'fade', label: '淡出' },
    { id: 'slideUp', label: '上滑出场' },
    { id: 'slideDown', label: '下滑出场' },
    { id: 'slideLeft', label: '左滑出场' },
    { id: 'slideRight', label: '右滑出场' },
    { id: 'pop', label: '缩掉' },
    { id: 'zoom', label: '放大出场' },
    { id: 'blurOut', label: '虚化淡出' },
    { id: 'wipe', label: '盖住' }
  ];

  /** 入场姿态：k = 0 还没出现 → 1 完全就位 */
  var IN_POSES = {
    none: function () { return {}; },
    fade: function (k) { return { a: k }; },
    slideUp: function (k) { return { dy: (1 - k) * 0.10, a: k }; },
    slideDown: function (k) { return { dy: -(1 - k) * 0.10, a: k }; },
    slideLeft: function (k) { return { dx: -(1 - k) * 0.14, a: k }; },
    slideRight: function (k) { return { dx: (1 - k) * 0.14, a: k }; },
    pop: function (k) { return { ds: 0.55 + 0.45 * easeOutBack(k), a: Math.min(1, k * 1.8) }; },
    zoom: function (k) { return { ds: 0.25 + 0.75 * k, a: k }; },
    zoomOut: function (k) { return { ds: 1.9 - 0.9 * k, a: k }; },
    blurIn: function (k) { return { blur: 1 - k, a: k }; },
    wipe: function (k) { return { wipe: k, a: 1 }; }
  };

  /** 出场姿态：k = 1 还在 → 0 已经消失 */
  var OUT_POSES = {
    none: function () { return {}; },
    fade: function (k) { return { a: k }; },
    slideUp: function (k) { return { dy: -(1 - k) * 0.10, a: k }; },
    slideDown: function (k) { return { dy: (1 - k) * 0.10, a: k }; },
    slideLeft: function (k) { return { dx: -(1 - k) * 0.14, a: k }; },
    slideRight: function (k) { return { dx: (1 - k) * 0.14, a: k }; },
    pop: function (k) { return { ds: 0.55 + 0.45 * k, a: Math.min(1, k * 1.8) }; },
    zoom: function (k) { return { ds: 1 + (1 - k) * 0.8, a: k }; },
    blurOut: function (k) { return { blur: 1 - k, a: k }; },
    wipe: function (k) { return { wipe: k, a: 1 }; }
  };

  function pose(list, preset, k) {
    var f = list[preset] || list.fade;
    var p = f(clamp(k, 0, 1)) || {};
    return {
      dx: num(p.dx, 0), dy: num(p.dy, 0), ds: num(p.ds, 1),
      rot: num(p.rot, 0), a: num(p.a, 1),
      blur: num(p.blur, 0), wipe: num(p.wipe, 1)
    };
  }

  /* ---------- 文字特效 ---------- */

  var TEXT_EFFECTS = [
    { id: 'plain', label: '普通' },
    { id: 'glow', label: '霓虹发光' },
    { id: 'glitch', label: '故障错位' },
    { id: 'type', label: '打字机' },
    { id: 'perchar', label: '逐字弹入' },
    { id: 'wave', label: '波浪' },
    { id: 'outline', label: '描边' },
    { id: 'gradient', label: '渐变填充' },
    { id: 'shake', label: '抖动' }
  ];

  /* ---------- 文字字体（都用系统里有的，不联网） ---------- */

  var FONTS = [
    { id: 'auto', label: 'Bahnschrift', stack: '"Bahnschrift", "Segoe UI", "Microsoft YaHei", sans-serif' },
    { id: 'sans', label: '黑体', stack: '"Microsoft YaHei", "PingFang SC", system-ui, sans-serif' },
    { id: 'serif', label: '宋体', stack: '"Songti SC", "SimSun", "Times New Roman", serif' },
    { id: 'mono', label: '等宽', stack: 'Consolas, "Courier New", monospace' },
    { id: 'impact', label: 'Impact', stack: 'Impact, "Arial Black", "Microsoft YaHei", sans-serif' }
  ];

  var FONT_MAP = {};
  for (var fi = 0; fi < FONTS.length; fi++) FONT_MAP[FONTS[fi].id] = FONTS[fi];

  function fontStack(id) {
    return (FONT_MAP[id] || FONT_MAP.auto).stack;
  }

  /* ---------- 形状 ---------- */

  var SHAPE_KINDS = [
    { id: 'rect', label: '方框' },
    { id: 'line', label: '横线' },
    { id: 'circle', label: '圆' },
    { id: 'ring', label: '圆环' },
    { id: 'grid', label: '网格' }
  ];

  /* ---------- 解锁动画 ---------- */

  var UNLOCK_PRESETS = [
    { id: 'tape', label: '磁带插入', desc: '磁带滑入 + 卡扣 + 「UNLOCKED」盖章' },
    { id: 'scan', label: '扫描解锁', desc: '扫描线上下扫，曲名与难度逐帧点亮' },
    { id: 'progress', label: '进度解锁', desc: '进度条冲到 100%，闪白后解锁' },
    { id: 'shards', label: '碎片汇聚', desc: '碎片从四周飞入，拼成标题框' },
    { id: 'chain', label: '锁链破碎', desc: '挂锁抖动 → 冲击波 → 碎成渣' },
    { id: 'shutter', label: '快门开启', desc: '四片快门从中心拉开，露出标题' },
    { id: 'ring', label: '环印盖章', desc: '双环旋转收拢，盖上难度章' }
  ];

  /* ---------- 混合模式 ---------- */

  var BLENDS = [
    { id: 'normal', label: '正常' },
    { id: 'add', label: '叠加发光' },
    { id: 'screen', label: '滤色' },
    { id: 'multiply', label: '正片叠底' },
    { id: 'overlay', label: '叠加' }
  ];

  var BLEND_CANVAS = {
    normal: 'source-over',
    add: 'lighter',
    screen: 'screen',
    multiply: 'multiply',
    overlay: 'overlay'
  };

  /* ---------- Shader 后处理 ---------- */

  /**
   * 每个预设 = 一组「权重」，渲染器把它们加在一起喂给同一个 GLSL 主着色器。
   * 这样多条 Shader 事件可以同时生效（比如「故障 + 暗角」），不需要多趟离屏。
   * 权重键就是 GLSL 里的 uniform 名（去掉 u 前缀的小写形式）。
   */
  var SHADER_PRESETS = [
    { id: 'none', label: '无', weights: {} },
    { id: 'bloom', label: '辉光', weights: { bloom: 1, grain: 0.08 } },
    // instant: 不做两头渐入渐出，一到点就是满强度（RGB 分离要"啪"一下）
    { id: 'rgb', label: 'RGB 分离', instant: true, weights: { rgb: 0.85 } },
    { id: 'crt', label: 'CRT 扫描线', weights: { scan: 1, rgb: 0.3, vignette: 0.5 } },
    { id: 'wave', label: '水波扭曲', weights: { wave: 1 } },
    { id: 'glitch', label: '故障', weights: { glitch: 1, rgb: 0.55 } },
    { id: 'heat', label: '热浪', weights: { heat: 1, wave: 0.35 } },
    { id: 'pixel', label: '像素化', weights: { pixel: 1 } },
    { id: 'posterize', label: '色调分离', weights: { poster: 1 } },
    { id: 'vignette', label: '暗角', weights: { vignette: 1 } },
    { id: 'grain', label: '颗粒', weights: { grain: 1, vignette: 0.3 } },
    { id: 'stretch', label: '四角拉伸', weights: { stretch: 1 } },
    { id: 'zoomShake', label: '放大抖动', weights: { zoom: 1, shake: 1 } },
    { id: 'dream', label: '梦幻柔光', weights: { bloom: 0.7, wave: 0.22, grain: 0.12 } },
    { id: 'flash', label: '反色闪白', weights: { invert: 1, bloom: 0.4 } }
  ];

  var SHADER_MAP = {};
  for (var si = 0; si < SHADER_PRESETS.length; si++) SHADER_MAP[SHADER_PRESETS[si].id] = SHADER_PRESETS[si];

  var WEIGHT_KEYS = ['bloom', 'rgb', 'scan', 'wave', 'glitch', 'heat', 'pixel', 'poster', 'grain', 'vignette', 'invert', 'stretch', 'zoom', 'shake'];

  function isVideoAsset(name) { return VIDEO_EXT.test(String(name || '')); }

  function shaderPreset(id) { return SHADER_MAP[id] || null; }

  function shaderWeights(preset) {
    var p = SHADER_MAP[preset];
    return p ? p.weights : {};
  }

  function emptyWeights() {
    var w = {};
    for (var i = 0; i < WEIGHT_KEYS.length; i++) w[WEIGHT_KEYS[i]] = 0;
    return w;
  }

  /* ---------- 吸附 ---------- */

  var SNAP_DIVS = [1, 2, 3, 4, 6, 8, 12];

  /* ==========================================================================
   * 事件（关键帧）—— 和图层的静态值同样的思路：
   * 通道独立、跑完保持尾值不回弹，直接借 core 的事件模型与求值函数。
   * ======================================================================== */

  var CHANNELS = ['x', 'y', 'scale', 'rot', 'alpha'];

  var CHANNEL_LABELS = { x: 'X', y: 'Y', scale: '缩放', rot: '旋转', alpha: '透明度' };

  function emptyEvents() {
    var o = {};
    for (var i = 0; i < CHANNELS.length; i++) o[CHANNELS[i]] = [];
    return o;
  }

  function mkEvent(spec) {
    spec = spec || {};
    // 允许负数：前置段（谱面开始之前）也要能打关键帧
    var start = clamp(round3(num(spec.start, 0)), -3600, 3600);
    return {
      id: int(spec.id, 0),
      start: start,
      end: Math.max(start, round3(num(spec.end, start))),
      ease: str(spec.ease, 'inOutCubic'),
      from: round3(num(spec.from, 0)),
      to: round3(num(spec.to, 0))
    };
  }

  function nextEventId(layer) {
    var m = 0;
    var evs = (layer && layer.events) || {};
    for (var i = 0; i < CHANNELS.length; i++) {
      var arr = evs[CHANNELS[i]] || [];
      for (var j = 0; j < arr.length; j++) if (arr[j].id > m) m = arr[j].id;
    }
    return m + 1;
  }

  function channel(layer, key) {
    if (!layer.events) layer.events = emptyEvents();
    if (!Array.isArray(layer.events[key])) layer.events[key] = [];
    return layer.events[key];
  }

  function addLayerEvent(layer, key, spec) {
    var arr = channel(layer, key);
    var ev = mkEvent(spec);
    ev.id = nextEventId(layer);
    arr.push(ev);
    arr.sort(function (a, b) { return a.start - b.start || a.id - b.id; });
    return ev;
  }

  function removeLayerEvent(layer, key, id) {
    var arr = channel(layer, key);
    for (var i = 0; i < arr.length; i++) {
      if (arr[i].id === id) { arr.splice(i, 1); return true; }
    }
    return false;
  }

  /** 图层的静态参数打底，逐条通道套事件（语义同 laneParamsAt） */
  function layerParamsAt(layer, t) {
    var p = {
      x: num(layer.x, 0.5),
      y: num(layer.y, 0.5),
      scale: num(layer.scale, 100),
      rot: num(layer.rot, 0),
      alpha: num(layer.alpha, 100)
    };
    for (var i = 0; i < CHANNELS.length; i++) {
      var k = CHANNELS[i];
      var cur = RC.eventAt(layer, k, t);
      if (!cur) continue;
      var span = cur.end - cur.start;
      var a = span > 1e-9 ? clamp((t - cur.start) / span, 0, 1) : 1;
      p[k] = cur.from + (cur.to - cur.from) * ease(cur.ease, a);
    }
    return p;
  }

  /**
   * 图层在 t 时刻的最终状态。
   * 坐标 x/y 是**舞台归一化坐标**（0~1，0.5/0.5 = 正中央，y 向下为正，和画布一致），
   * 入场 / 出场在归一化坐标上做位移，所以换分辨率也不会跑偏。
   * alpha 返回 0~1（已经乘上入场出场），scale 返回倍率（1 = 100%）。
   */
  function layerAt(layer, t) {
    var blank = {
      active: false, x: 0.5, y: 0.5, scale: 1, rot: 0, alpha: 0,
      blur: 0, wipe: 0, progress: 0, kIn: 0, kOut: 0, elapsed: 0, base: null
    };
    if (!layer || layer.visible === false) return blank;
    var start = num(layer.start, 0);
    var end = Math.max(start, num(layer.end, start));
    if (t < start - 1e-9 || t > end + 1e-9) return blank;

    var span = Math.max(1e-6, end - start);
    var base = layerParamsAt(layer, t);

    var inCfg = layer.in || {};
    var outCfg = layer.out || {};
    var inDur = Math.max(0, num(inCfg.dur, 0));
    var outDur = Math.max(0, num(outCfg.dur, 0));
    // 出入场不能互相吃掉：各自最多占图层时长的一半
    if (inDur > span / 2) inDur = span / 2;
    if (outDur > span / 2) outDur = span / 2;

    var kIn = inDur > 1e-6 ? clamp((t - start) / inDur, 0, 1) : 1;
    var kOut = outDur > 1e-6 ? clamp((end - t) / outDur, 0, 1) : 1;

    var pin = pose(IN_POSES, str(inCfg.preset, 'fade'), ease(str(inCfg.ease, 'outCubic'), kIn));
    var pout = pose(OUT_POSES, str(outCfg.preset, 'fade'), ease(str(outCfg.ease, 'inCubic'), kOut));

    return {
      active: true,
      x: base.x + pin.dx + pout.dx,
      y: base.y + pin.dy + pout.dy,
      scale: (base.scale / 100) * pin.ds * pout.ds,
      rot: base.rot + pin.rot + pout.rot,
      alpha: clamp((base.alpha / 100) * pin.a * pout.a, 0, 1),
      blur: pin.blur + pout.blur,
      wipe: Math.min(pin.wipe, pout.wipe),
      progress: clamp((t - start) / span, 0, 1),
      kIn: kIn,
      kOut: kOut,
      elapsed: t - start,
      base: base
    };
  }

  /* ==========================================================================
   * Shader 时间线求值
   * ======================================================================== */

  /** 一条 shader 事件在 t 时刻的强度（0~1）：默认两头软、中间平 */
  function shaderValAt(fx, t) {
    if (!fx) return 0;
    var start = num(fx.start, 0);
    var end = Math.max(start, num(fx.end, start));
    if (t < start - 1e-9 || t > end + 1e-9) return 0;
    var span = Math.max(1e-6, end - start);
    var k = clamp((t - start) / span, 0, 1);
    var presetDef = SHADER_MAP[fx.preset];
    var ramp = clamp(num(fx.ramp, 0.28), 0, 0.49);
    if (presetDef && presetDef.instant) ramp = 0;      // 「立刻」型：不做缓入缓出
    var env;
    if (ramp < 1e-6) env = 1;
    else if (k < ramp) env = ease(num(fx.ease, 'inOutSine'), k / ramp);
    else if (k > 1 - ramp) env = ease(num(fx.ease, 'inOutSine'), (1 - k) / ramp);
    else env = 1;
    return clamp(env * clamp(num(fx.amount, 100) / 100, 0, 1), 0, 1);
  }

  /**
   * 此刻生效的后处理「层」：按场景里的顺序，每层带上自己的预设权重 × 自己的强度。
   * 渲染时逐层各跑一遍 pass（不是把权重相加成一个着色器），所以叠 3 条 RGB 分离 = 分 3 次，
   * 顺序也有意义（先辉光后暗角 ≠ 先暗角后辉光）。
   */
  function activeShaders(scene, t) {
    var out = [];
    var list = (scene && scene.shaders) || [];
    for (var i = 0; i < list.length; i++) {
      var fx = list[i];
      var v = shaderValAt(fx, t);
      if (v <= 1e-4) continue;
      var w = shaderWeights(fx.preset);
      var ww = {};
      var any = false;
      for (var k in w) {
        if (!Object.prototype.hasOwnProperty.call(w, k)) continue;
        ww[k] = w[k] * v;
        any = true;
      }
      if (!any) continue;
      var def = SHADER_MAP[fx.preset] || null;
      out.push({
        id: fx.id,
        preset: fx.preset,
        label: def ? def.label : fx.preset,
        value: v,
        weights: ww,
        instant: !!(def && def.instant),
        // 冲击放大用：这一层在时间轴上的起点（进区间那一下触发）
        punchT0: fx.start
      });
    }
    return out;
  }

  /** 所有生效的 shader 叠加后的 uniform 权重（同一键相加，封顶 1.5） */
  function combineShaderWeights(doc, t) {
    var w = emptyWeights();
    var list = (doc && doc.shaders) || [];
    for (var i = 0; i < list.length; i++) {
      var fx = list[i];
      var v = shaderValAt(fx, t);
      if (v <= 1e-4) continue;
      var ww = shaderWeights(fx.preset);
      for (var key in ww) {
        if (!Object.prototype.hasOwnProperty.call(ww, key)) continue;
        w[key] = (w[key] || 0) + ww[key] * v;
      }
    }
    for (var k in w) {
      if (Object.prototype.hasOwnProperty.call(w, k)) w[k] = clamp(w[k], 0, 1.5);
    }
    return w;
  }

  /* ==========================================================================
   * 图层增删改（全部接收 doc，返回/修改同一个 doc）
   * ======================================================================== */

  function nextId(list) {
    var m = 0;
    for (var i = 0; i < (list || []).length; i++) if (list[i].id > m) m = list[i].id;
    return m + 1;
  }

  function findLayer(doc, id) {
    var list = (doc && doc.layers) || [];
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
    return null;
  }

  function layerIndex(doc, id) {
    var list = (doc && doc.layers) || [];
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return i;
    return -1;
  }

  function findShader(doc, id) {
    var list = (doc && doc.shaders) || [];
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
    return null;
  }

  function layerDefaults(type) {
    var t = LAYER_TYPES.indexOf(type) >= 0 ? type : 'text';
    var d = {
      type: t,
      name: TYPE_LABELS[t] + ' ' + (t === 'text' ? '' : '').trim(),
      start: 0,
      end: 3,
      x: 0.5,
      y: 0.5,
      scale: 100,
      rot: 0,
      alpha: 100,
      blend: 'normal',
      visible: true,
      color: '#ffffff',
      in: { preset: 'fade', dur: 0.5, ease: 'outCubic' },
      out: { preset: 'fade', dur: 0.4, ease: 'inCubic' },
      events: emptyEvents()
    };

    if (t === 'text') {
      d.y = 0.42;
      d.name = '标题';
      d.text = 'TITLE';
      d.style = {
        size: 76, weight: 800, color: '#ffffff', effect: 'glow',
        glow: 0.6, letter: 0.06, lineH: 1.15, align: 'center', font: 'auto',
        stroke: '#000000', strokeW: 0, c1: '#4cc9f0', c2: '#f72585', speed: 20
      };
      d.in = { preset: 'slideUp', dur: 0.6, ease: 'outCubic' };
    } else if (t === 'shape') {
      d.name = '形状';
      d.y = 0.6;
      d.color = '#4cc9f0';
      d.shape = { kind: 'rect', w: 0.4, h: 0.02, radius: 8, line: 0, fill: true, count: 8 };
      d.in = { preset: 'wipe', dur: 0.5, ease: 'outCubic' };
      d.out = { preset: 'fade', dur: 0.3, ease: 'inCubic' };
    } else if (t === 'image') {
      d.name = '图片';
      d.image = { name: '', w: 0.4 };
      d.in = { preset: 'pop', dur: 0.5, ease: 'outBack' };
    } else if (t === 'video') {
      // 视频默认铺满整个舞台（解锁动画 / 开场画面一般就是全屏）
      d.name = '视频';
      d.video = { name: '', w: 1, fit: 'cover', speed: 1, volume: 100, mute: false };
      d.in = { preset: 'fade', dur: 0.3, ease: 'outCubic' };
    } else if (t === 'unlock') {
      d.name = '解锁动画';
      d.x = 0.5;
      d.y = 0.42;
      d.in = { preset: 'none', dur: 0, ease: 'linear' };
      d.out = { preset: 'fade', dur: 0.3, ease: 'inCubic' };
      d.unlock = {
        preset: 'tape',
        label: '',
        sub: '',
        color: '#4cc9f0',
        accent: '#f72585',
        scale: 1
      };
    }
    return d;
  }

  function createLayer(type, opts) {
    opts = opts || {};
    var d = layerDefaults(type);
    var layer = { id: int(opts.id, 0), type: d.type };
    for (var k in d) {
      if (k === 'type') continue;
      layer[k] = d[k];
    }
    layer.start = clamp(round3(num(opts.start, layer.start)), -3600, 3600);
    layer.end = round3(Math.max(layer.start + 0.2, num(opts.end, layer.start + 3)));
    if (typeof opts.name === 'string') layer.name = opts.name;
    return layer;
  }

  function addLayer(doc, type, opts) {
    var o = opts || {};
    var layer = createLayer(type, {
      start: num(o.start, 0),
      end: num(o.end, num(o.start, 0) + 3),
      name: o.name
    });
    layer.id = nextId(doc.layers);
    if (layer.type === 'text') {
      layer.text = str(o.text, layer.text);
      if (o.text === '') layer.text = '';
    }
    if (layer.type === 'image' && o.image) layer.image.name = str(o.image, '');
  if (layer.type === 'video' && o.video) layer.video.name = str(o.video, '');
    if (layer.type === 'unlock' && o.preset) layer.unlock.preset = str(o.preset, 'tape');
    doc.layers.push(layer);
    return layer;
  }

  function removeLayer(doc, id) {
    var i = layerIndex(doc, id);
    if (i < 0) return false;
    doc.layers.splice(i, 1);
    return true;
  }

  function duplicateLayer(doc, id) {
    var i = layerIndex(doc, id);
    if (i < 0) return null;
    var copy = JSON.parse(JSON.stringify(doc.layers[i]));
    copy.id = nextId(doc.layers);
    copy.name = (copy.name || '图层') + ' 副本';
    copy.start = round3(copy.start);
    copy.end = round3(copy.end);
    copy.events = copy.events || emptyEvents();
    for (var c = 0; c < CHANNELS.length; c++) {
      var key = CHANNELS[c];
      var arr = copy.events[key] || [];
      for (var j = 0; j < arr.length; j++) arr[j].id = 0;
    }
    doc.layers.splice(i + 1, 0, copy);
    return copy;
  }

  /** 图层在列表里挪位置：delta = -1 往前（更晚画 = 更上层），+1 往后 */
  function moveLayer(doc, id, delta) {
    var i = layerIndex(doc, id);
    if (i < 0) return false;
    var j = i + delta;
    if (j < 0 || j >= doc.layers.length) return false;
    var tmp = doc.layers[i];
    doc.layers[i] = doc.layers[j];
    doc.layers[j] = tmp;
    return true;
  }

  function activeLayers(doc, t) {
    var out = [];
    var list = (doc && doc.layers) || [];
    for (var i = 0; i < list.length; i++) {
      var st = layerAt(list[i], t);
      if (st.active && st.alpha > 0.001) out.push({ layer: list[i], state: st });
    }
    return out;
  }

  function createShader(preset, opts) {
    opts = opts || {};
    var start = round3(num(opts.start, 0));
    return {
      id: int(opts.id, 0),
      preset: SHADER_MAP[preset] ? preset : 'bloom',
      start: start,
      end: round3(Math.max(start + 0.2, num(opts.end, start + 2))),
      amount: clamp(num(opts.amount, 100), 0, 100),
      ramp: clamp(num(opts.ramp, 0.28), 0, 0.49),
      ease: str(opts.ease, 'inOutSine')
    };
  }

  function addShader(doc, preset, opts) {
    var fx = createShader(preset, opts);
    fx.id = nextId(doc.shaders);
    doc.shaders.push(fx);
    doc.shaders.sort(function (a, b) { return a.start - b.start || a.id - b.id; });
    return fx;
  }

  function removeShader(doc, id) {
    var list = doc.shaders || [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) { list.splice(i, 1); return true; }
    }
    return false;
  }

  /* ==========================================================================
   * 谱面引用（只读）
   * ======================================================================== */

  function emptyDigest() {
    return {
      file: '', title: '未命名谱面', artist: '', charter: '', illustrator: '',
      difficulty: 'NORMAL', level: 1, notes: 0, duration: 0,
      bpm: 150, lanes: 4, hash: ''
    };
  }

  function chartDigest(chart, opts) {
    var o = opts || {};
    var d = emptyDigest();
    if (!chart) return d;
    var meta = chart.meta || {};
    d.file = str(o.file, '');
    d.title = str(meta.title, d.title) || d.title;
    d.artist = str(meta.artist, '');
    d.charter = str(meta.charter, '');
    d.illustrator = str(meta.illustrator, '');   // 曲绘作者（来自谱面）
    d.difficulty = str(meta.difficulty, 'NORMAL');
    d.level = clamp(int(meta.level, 1), 1, 99);
    d.notes = (chart.notes || []).length;
    d.duration = round3(RC.chartDuration(chart));
    d.bpm = round3(RC.num(chart.timing && chart.timing.bpm, 150));
    d.lanes = (chart.lanes || []).length;
    d.hash = str(o.hash, '');
    return d;
  }

  /* ==========================================================================
   * 场景
   * ======================================================================== */

  function sceneKind(kind) {
    return SCENE_MAP[kind] ? kind : 'free';
  }

  function sceneKindDef(kind) {
    return SCENE_MAP[sceneKind(kind)];
  }

  /** 建一个场景（id 由 addScene 分配） */
  function createScene(kind, opts) {
    var o = opts || {};
    var k = sceneKind(kind || o.kind);
    return {
      id: int(o.id, 0),
      kind: k,
      name: str(o.name, '') || SCENE_MAP[k].label,
      length: k === 'chart' ? 0 : clamp(num(o.length, SCENE_MAP[k].defLength), 0.1, 3600),
      layers: [],
      shaders: []
    };
  }

  function findScene(doc, id) {
    var list = (doc && doc.scenes) || [];
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
    return null;
  }

  function sceneIndex(doc, id) {
    var list = (doc && doc.scenes) || [];
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return i;
    return -1;
  }

  /** 场景实际时长：谱面场跟着谱面时长走，其它场用自己的 length */
  function sceneLen(doc, scene) {
    if (!scene) return 0;
    if (sceneKind(scene.kind) === 'chart') {
      var dur = num(doc && doc.chart && doc.chart.duration, 0);
      if (dur > 0.05) return round3(dur);
      return round3(Math.max(0.5, num(scene.length, 0) || 3));
    }
    return round3(Math.max(0.1, num(scene.length, SCENE_MAP[sceneKind(scene.kind)].defLength)));
  }

  /** 每个场景在全局时间轴上的区间：[start, end) */
  function sceneSpans(doc) {
    var out = [];
    var t = 0;
    var list = (doc && doc.scenes) || [];
    for (var i = 0; i < list.length; i++) {
      var len = sceneLen(doc, list[i]);
      out.push({ scene: list[i], index: i, start: round3(t), end: round3(t + len), len: len, kind: sceneKind(list[i].kind) });
      t += len;
    }
    return out;
  }

  /** 全局时间 t 落在哪个场景，local = 场景内时间 */
  function sceneAt(doc, t) {
    var spans = sceneSpans(doc);
    if (!spans.length) return null;
    if (t < 0) return { span: spans[0], index: 0, local: 0 };
    for (var i = 0; i < spans.length; i++) {
      if (t < spans[i].end - 1e-9 || i === spans.length - 1) {
        return {
          span: spans[i],
          index: i,
          local: round3(clamp(t - spans[i].start, 0, spans[i].len))
        };
      }
    }
    var last = spans[spans.length - 1];
    return { span: last, index: spans.length - 1, local: last.len };
  }

  function addScene(doc, kind, opts) {
    var o = opts || {};
    var sc = createScene(kind, o);
    sc.id = nextId(doc.scenes);
    if (o.index !== undefined && o.index >= 0 && o.index <= doc.scenes.length) {
      doc.scenes.splice(o.index, 0, sc);
    } else {
      doc.scenes.push(sc);
    }
    return sc;
  }

  function removeScene(doc, id) {
    var i = sceneIndex(doc, id);
    if (i < 0) return false;
    if (doc.scenes.length <= 1) return false;      // 至少留一场
    doc.scenes.splice(i, 1);
    return true;
  }

  function moveScene(doc, id, delta) {
    var i = sceneIndex(doc, id);
    if (i < 0) return false;
    var j = i + delta;
    if (j < 0 || j >= doc.scenes.length) return false;
    var tmp = doc.scenes[i];
    doc.scenes[i] = doc.scenes[j];
    doc.scenes[j] = tmp;
    return true;
  }

  function createStoryboard(digest) {
    var ch = digest || emptyDigest();
    ch = JSON.parse(JSON.stringify(ch));    // 拷贝一份：别让多个故事板共享同一个谱面引用对象
    var doc = {
      format: FORMAT,
      version: VERSION,
      stage: { width: STAGE_W, height: STAGE_H, bg: '#05070c', chartAlpha: 100, highway: 2, length: 0, volume: 100, chartBase: 350 },
      timing: { bpm: num(ch.bpm, 150), beat_offset: 0 },
      chart: ch,
      meta: { author: '', note: '', coverArtist: '' },
      assets: {},
      scenes: []
    };
    // 有谱面 → 默认「解锁场 + 谱面场」；没谱面 → 一场空的演出场
    if (num(ch.duration, 0) > 0.05) {
      doc.scenes.push(createScene('chart', { id: 2, name: '谱面' }));
      doc.scenes.unshift(createScene('unlock', { id: 1, name: '解锁演出', length: SCENE_MAP.unlock.defLength }));
    } else {
      doc.scenes.push(createScene('free', { id: 1, name: '演出场' }));
    }
    return doc;
  }

  /* ==========================================================================
   * 容错读取 / 导出
   * ======================================================================== */

  function normEvents(raw) {
    var out = emptyEvents();
    if (!raw || typeof raw !== 'object') return out;
    for (var c = 0; c < CHANNELS.length; c++) {
      var key = CHANNELS[c];
      var arr = raw[key];
      if (!Array.isArray(arr)) continue;
      for (var i = 0; i < arr.length; i++) {
        var e = arr[i];
        if (!e || typeof e !== 'object') continue;
        var start = clamp(round3(num(e.start, 0)), -3600, 3600);
        out[key].push({
          id: int(e.id, i + 1),
          start: start,
          end: Math.max(start, round3(num(e.end, start))),
          ease: str(e.ease, 'linear'),
          from: round3(num(e.from, 0)),
          to: round3(num(e.to, 0))
        });
      }
      out[key].sort(function (a, b) { return a.start - b.start || a.id - b.id; });
    }
    return out;
  }

  function normAnim(raw, fallback) {
    var r = raw && typeof raw === 'object' ? raw : {};
    var f = fallback || { preset: 'fade', dur: 0.4, ease: 'outCubic' };
    return {
      preset: str(r.preset, f.preset),
      dur: clamp(num(r.dur, f.dur), 0, 10),
      ease: str(r.ease, f.ease)
    };
  }

  function normLayer(raw, index) {
    var warnings = [];
    var r = raw && typeof raw === 'object' ? raw : {};
    var type = LAYER_TYPES.indexOf(r.type) >= 0 ? r.type : 'text';
    if (r.type !== undefined && LAYER_TYPES.indexOf(r.type) < 0) {
      warnings.push('图层 ' + (index + 1) + ' 的类型「' + r.type + '」不认识，按文字处理');
    }
    var d = layerDefaults(type);

    // 允许负数：谱面开始之前（前置段）也能放图层
    var start = clamp(round3(num(r.start, 0)), -3600, 3600);
    var end = round3(num(r.end, start + 3));
    if (end <= start) { end = round3(start + 0.2); warnings.push('图层 ' + (index + 1) + ' 的结束时间早于开始，已改成 +0.2 秒'); }

    var layer = {
      id: int(r.id, index + 1),
      type: type,
      name: str(r.name, d.name),
      start: start,
      end: end,
      x: clamp(num(r.x, d.x), -1, 2),
      y: clamp(num(r.y, d.y), -1, 2),
      scale: clamp(num(r.scale, d.scale), -4000, 4000),
      rot: clamp(num(r.rot, d.rot), -36000, 36000),
      alpha: clamp(num(r.alpha, d.alpha), 0, 100),
      blend: BLEND_CANVAS[str(r.blend, d.blend)] ? str(r.blend, d.blend) : 'normal',
      visible: bool(r.visible, true),
      color: /^#[0-9a-f]{6}$/i.test(str(r.color, '')) ? str(r.color, '') : d.color,
      in: normAnim(r.in, d.in),
      out: normAnim(r.out, d.out),
      events: normEvents(r.events)
    };

    if (type === 'text') {
      var st = r.style && typeof r.style === 'object' ? r.style : {};
      var ds = d.style;
      layer.text = str(r.text, ds ? 'TITLE' : '');
      layer.style = {
        size: clamp(num(st.size, ds.size), 8, 420),
        weight: clamp(int(st.weight, ds.weight), 100, 900),
        color: /^#[0-9a-f]{6}$/i.test(str(st.color, '')) ? st.color : ds.color,
        effect: TEXT_EFFECTS.some(function (e) { return e.id === st.effect; }) ? st.effect : ds.effect,
        glow: clamp(num(st.glow, ds.glow), 0, 1),
        letter: clamp(num(st.letter, ds.letter), -0.5, 1),
        lineH: clamp(num(st.lineH, ds.lineH), 0.6, 3),
        align: ['left', 'center', 'right'].indexOf(st.align) >= 0 ? st.align : 'center',
        font: FONT_MAP[st.font] ? st.font : 'auto',
        stroke: /^#[0-9a-f]{6}$/i.test(str(st.stroke, '')) ? st.stroke : ds.stroke,
        strokeW: clamp(num(st.strokeW, ds.strokeW), 0, 24),
        c1: /^#[0-9a-f]{6}$/i.test(str(st.c1, '')) ? st.c1 : ds.c1,
        c2: /^#[0-9a-f]{6}$/i.test(str(st.c2, '')) ? st.c2 : ds.c2,
        speed: clamp(num(st.speed, ds.speed), 1, 200)
      };
    } else if (type === 'shape') {
      var sp = r.shape && typeof r.shape === 'object' ? r.shape : {};
      var dp = d.shape;
      layer.shape = {
        kind: SHAPE_KINDS.some(function (s) { return s.id === sp.kind; }) ? sp.kind : 'rect',
        w: clamp(num(sp.w, dp.w), 0.005, 4),
        h: clamp(num(sp.h, dp.h), 0.001, 4),
        radius: clamp(num(sp.radius, dp.radius), 0, 400),
        line: clamp(num(sp.line, dp.line), 0, 80),
        fill: bool(sp.fill, true),
        count: clamp(int(sp.count, dp.count), 2, 40)
      };
    } else if (type === 'image') {
      var ip = r.image && typeof r.image === 'object' ? r.image : {};
      layer.image = {
        name: str(ip.name, ''),
        w: clamp(num(ip.w, 0.4), 0.02, 4)
      };
    } else if (type === 'video') {
      var vp = r.video && typeof r.video === 'object' ? r.video : {};
      layer.video = {
        name: str(vp.name, ''),
        w: clamp(num(vp.w, 1), 0.05, 4),
        fit: (vp.fit === 'contain' || vp.fit === 'stretch') ? vp.fit : 'cover',
        speed: clamp(num(vp.speed, 1), 0.1, 4),
        volume: clamp(num(vp.volume, 100), 0, 100),
        mute: bool(vp.mute, false)
      };
    } else if (type === 'unlock') {
      var up = r.unlock && typeof r.unlock === 'object' ? r.unlock : {};
      var presetOk = UNLOCK_PRESETS.some(function (u) { return u.id === up.preset; });
      layer.unlock = {
        preset: presetOk ? up.preset : 'tape',
        label: str(up.label, ''),
        sub: str(up.sub, ''),
        color: /^#[0-9a-f]{6}$/i.test(str(up.color, '')) ? up.color : '#4cc9f0',
        accent: /^#[0-9a-f]{6}$/i.test(str(up.accent, '')) ? up.accent : '#f72585',
        scale: clamp(num(up.scale, 1), 0.2, 4)
      };
    }

    return { layer: layer, warnings: warnings };
  }

  function warn(warnings, text) { warnings.push(text); }

  /**
   * 容错读取一份故事板工程。返回 { doc, warnings }，任何脏数据都不会抛异常。
   */
  function normalizeDoc(raw) {
    var warnings = [];
    if (!raw || typeof raw !== 'object') {
      return { doc: createStoryboard(), warnings: ['工程文件不是合法的 JSON 对象'] };
    }

    var digest = emptyDigest();
    var ch = raw.chart && typeof raw.chart === 'object' ? raw.chart : {};
    digest.file = str(ch.file, '');
    digest.title = str(ch.title, digest.title) || digest.title;
    digest.artist = str(ch.artist, '');
    digest.charter = str(ch.charter, '');
    digest.illustrator = str(ch.illustrator, '');
    digest.difficulty = str(ch.difficulty, 'NORMAL');
    digest.level = clamp(int(ch.level, 1), 1, 99);
    digest.notes = Math.max(0, int(ch.notes, 0));
    digest.duration = Math.max(0, round3(num(ch.duration, 0)));
    digest.bpm = clamp(round3(num(ch.bpm, 150)), 20, 1000);
    digest.lanes = clamp(int(ch.lanes, 4), 1, 16);
    digest.hash = str(ch.hash, '');

    var doc = createStoryboard(digest);
    doc.scenes.length = 0;      // 场景完全按工程文件重建（createStoryboard 只是给默认值）

    var stage = raw.stage && typeof raw.stage === 'object' ? raw.stage : {};
    doc.stage.width = clamp(int(stage.width, STAGE_W), 320, 3840);
    doc.stage.height = clamp(int(stage.height, STAGE_H), 180, 2160);
    doc.stage.bg = /^#[0-9a-f]{6}$/i.test(str(stage.bg, '')) ? stage.bg : '#05070c';
    doc.stage.chartAlpha = clamp(num(stage.chartAlpha, 100), 0, 100);
    // 谱面 x/y 的基准画幅宽度（默认 380 = 制谱器预渲染窗，这样两边构图一致）
    doc.stage.chartBase = clamp(num(stage.chartBase, 350), 120, 2560);
    doc.stage.highway = clamp(num(stage.highway, 2), 0.3, 20);
    // 故事板自己的播放音量（0~100）。谱面里的 audio.volume_db 是谱面内容，只读，不改它。
    doc.stage.volume = clamp(num(stage.volume, 100), 0, 100);
    // 0 = 自动（取谱面时长与所有图层 / 后处理末端的最大值）
    doc.stage.length = clamp(num(stage.length, 0), 0, 3600);

    var timing = raw.timing && typeof raw.timing === 'object' ? raw.timing : {};
    doc.timing.bpm = clamp(round3(num(timing.bpm, digest.bpm)), 20, 1000);
    doc.timing.beat_offset = round3(num(timing.beat_offset, 0));

    var meta = raw.meta && typeof raw.meta === 'object' ? raw.meta : {};
    doc.meta.author = str(meta.author, '');
    doc.meta.coverArtist = str(meta.coverArtist, '');
    doc.meta.note = str(meta.note, '');

    if (raw.assets && typeof raw.assets === 'object') {
      for (var k in raw.assets) {
        if (!Object.prototype.hasOwnProperty.call(raw.assets, k)) continue;
        if (typeof raw.assets[k] === 'string' && raw.assets[k].indexOf('data:') === 0) {
          doc.assets[k] = raw.assets[k];
        }
      }
    }

    var rawScenes = Array.isArray(raw.scenes) ? raw.scenes : null;
    var rawLayers = Array.isArray(raw.layers) ? raw.layers : [];
    var rawShaders = Array.isArray(raw.shaders) ? raw.shaders : [];

    // 旧版工程（v1）：图层挂在根上，没有场景 → 收进一场
    if (!rawScenes) {
      if (rawLayers.length || rawShaders.length) {
        rawScenes = [{
          kind: digest.duration > 0.05 ? 'chart' : 'free',
          name: digest.duration > 0.05 ? '谱面' : '演出场',
          length: 0,
          layers: rawLayers,
          shaders: rawShaders
        }];
        warn(warnings, '这是旧版工程（没有场景），已把图层放进一个场景');
      } else {
        rawScenes = [];
      }
    }
    if (!rawScenes.length) {
      rawScenes = [{ kind: digest.duration > 0.05 ? 'chart' : 'free', name: '' }];
    }
    if (rawScenes.length > 40) warn(warnings, '场景超过 40 个，只读了前 40 个');

    var usedSceneIds = {};
    for (var si = 0; si < rawScenes.length && si < 40; si++) {
      var rs = rawScenes[si] && typeof rawScenes[si] === 'object' ? rawScenes[si] : {};
      var kind = sceneKind(rs.kind);
      var def = SCENE_MAP[kind];
      var sc = createScene(kind, {
        id: int(rs.id, si + 1),
        name: str(rs.name, '') || (kind === 'chart' ? '谱面' : def.label),
        length: num(rs.length, def.defLength)
      });
      if (usedSceneIds[sc.id]) { sc.id = nextId(doc.scenes); warn(warnings, '场景 id 重复，已重新编号'); }
      usedSceneIds[sc.id] = true;

      var sLayers = Array.isArray(rs.layers) ? rs.layers : [];
      if (sLayers.length > 400) warn(warnings, '场景「' + sc.name + '」图层超过 400 个，只读了前 400 个');
      var usedIds = {};
      for (var i = 0; i < sLayers.length && i < 400; i++) {
        var res = normLayer(sLayers[i], i);
        for (var w = 0; w < res.warnings.length; w++) warn(warnings, res.warnings[w]);
        var layer = res.layer;
        if (usedIds[layer.id]) { layer.id = nextId(sc.layers); warn(warnings, '图层 id 重复，已重新编号'); }
        usedIds[layer.id] = true;
        sc.layers.push(layer);
      }

      var sShaders = Array.isArray(rs.shaders) ? rs.shaders : [];
      for (var s2 = 0; s2 < sShaders.length && s2 < 200; s2++) {
        var r2 = sShaders[s2];
        if (!r2 || typeof r2 !== 'object') continue;
        sc.shaders.push(createShader(SHADER_MAP[r2.preset] ? r2.preset : 'none', {
          id: int(r2.id, s2 + 1),
          start: num(r2.start, 0),
          end: num(r2.end, num(r2.start, 0) + 2),
          amount: num(r2.amount, 100),
          ramp: num(r2.ramp, 0.28),
          ease: r2.ease
        }));
      }
      sc.shaders.sort(function (a, b) { return a.start - b.start || a.id - b.id; });
      doc.scenes.push(sc);
    }

    var layerTotal = 0;
    for (var z = 0; z < doc.scenes.length; z++) layerTotal += doc.scenes[z].layers.length;
    if (!layerTotal) warn(warnings, '工程里还没有图层');
    if (!doc.chart.hash && !doc.chart.file) warn(warnings, '这份工程没有关联谱面，打开后需要重新导入谱面');

    return { doc: doc, warnings: warnings };
  }

  function serializeDoc(doc) {
    function anim(a) {
      return {
        preset: a.preset,
        dur: round3(a.dur),
        ease: a.ease
      };
    }
    function events(ev) {
      var o = {};
      for (var c = 0; c < CHANNELS.length; c++) {
        var key = CHANNELS[c];
        var arr = (ev && ev[key]) || [];
        if (!arr.length) continue;
        o[key] = arr.map(function (e) {
          return {
            start: round3(e.start), end: round3(e.end),
            ease: e.ease, from: round3(e.from), to: round3(e.to)
          };
        });
      }
      return o;
    }

    return {
      format: FORMAT,
      version: VERSION,
      stage: {
        width: int(doc.stage.width, STAGE_W),
        height: int(doc.stage.height, STAGE_H),
        bg: doc.stage.bg,
        chartAlpha: round3(num(doc.stage.chartAlpha, 100)),
        chartBase: round3(num(doc.stage.chartBase, 350)),
        highway: round3(num(doc.stage.highway, 2)),
        volume: round3(num(doc.stage.volume, 100)),
        length: round3(num(doc.stage.length, 0))
      },
      timing: { bpm: round3(doc.timing.bpm), beat_offset: round3(doc.timing.beat_offset) },
      chart: {
        file: doc.chart.file, title: doc.chart.title, artist: doc.chart.artist,
        charter: doc.chart.charter, illustrator: doc.chart.illustrator || '',
        difficulty: doc.chart.difficulty,
        level: doc.chart.level, notes: doc.chart.notes,
        duration: round3(doc.chart.duration), bpm: round3(doc.chart.bpm),
        lanes: doc.chart.lanes, hash: doc.chart.hash
      },
      meta: { author: doc.meta.author, note: doc.meta.note, coverArtist: doc.meta.coverArtist },
      assets: doc.assets || {},
      scenes: doc.scenes.map(function (sc, si2) {
        return {
          id: si2 + 1,
          kind: sceneKind(sc.kind),
          name: sc.name,
          length: sceneKind(sc.kind) === 'chart' ? 0 : round3(sc.length),
          layers: sc.layers.map(function (L, i) {
            var o = {
              id: i + 1,
              type: L.type,
              name: L.name,
              start: round3(L.start),
              end: round3(L.end),
              x: round3(L.x),
              y: round3(L.y),
              scale: round3(L.scale),
              rot: round3(L.rot),
              alpha: round3(L.alpha),
              blend: L.blend,
              visible: L.visible !== false,
              color: L.color,
              in: anim(L.in),
              out: anim(L.out)
            };
            var ev = events(L.events);
            if (Object.keys(ev).length) o.events = ev;

            if (L.type === 'text') {
              o.text = L.text;
              o.style = {
                size: round3(L.style.size), weight: L.style.weight, color: L.style.color,
                effect: L.style.effect, glow: round3(L.style.glow), letter: round3(L.style.letter),
                lineH: round3(L.style.lineH), align: L.style.align, font: L.style.font,
                stroke: L.style.stroke, strokeW: round3(L.style.strokeW),
                c1: L.style.c1, c2: L.style.c2, speed: round3(L.style.speed)
              };
            } else if (L.type === 'shape') {
              o.shape = {
                kind: L.shape.kind, w: round3(L.shape.w), h: round3(L.shape.h),
                radius: round3(L.shape.radius), line: round3(L.shape.line),
                fill: !!L.shape.fill, count: L.shape.count
              };
            } else if (L.type === 'image') {
              o.image = { name: L.image.name, w: round3(L.image.w) };
            } else if (L.type === 'video') {
              o.video = { name: L.video.name, w: round3(L.video.w), fit: L.video.fit, speed: round3(L.video.speed), volume: round3(L.video.volume), mute: !!L.video.mute };
            } else if (L.type === 'unlock') {
              o.unlock = {
                preset: L.unlock.preset, label: L.unlock.label, sub: L.unlock.sub,
                color: L.unlock.color, accent: L.unlock.accent, scale: round3(L.unlock.scale)
              };
            }
            return o;
          }),
          shaders: sc.shaders.map(function (fx, i) {
            return {
              id: i + 1,
              preset: fx.preset,
              start: round3(fx.start),
              end: round3(fx.end),
              amount: round3(fx.amount),
              ramp: round3(fx.ramp),
              ease: fx.ease
            };
          })
        };
      })
    };
  }

  /* ==========================================================================
   * 时长 / 校验
   * ======================================================================== */

  /** 整条故事板多长：所有场景时长之和（`stage.length` 手动填了就以它为准） */
  function totalLength(doc) {
    var spans = sceneSpans(doc);
    var end = spans.length ? spans[spans.length - 1].end : 0;
    var manual = num(doc && doc.stage && doc.stage.length, 0);
    if (manual > 0) return round3(manual);
    return round3(end);
  }

  function validateDoc(doc) {
    var issues = [];
    var spans = sceneSpans(doc);
    var layerTotal = 0;
    var chartScenes = 0;

    for (var s = 0; s < spans.length; s++) {
      var sc = spans[s].scene;
      var layers = sc.layers || [];
      layerTotal += layers.length;
      if (sceneKind(sc.kind) === 'chart') chartScenes++;

      for (var i = 0; i < layers.length; i++) {
        var L = layers[i];
        var tag = '「' + (sc.name || '场景') + ' · ' + L.name + '」';
        if (L.end - L.start < 0.05) issues.push({ level: 'warn', text: tag + '时长太短（< 0.05 秒）' });
        if (L.start > spans[s].len + 0.5) issues.push({ level: 'warn', text: tag + '排在场景结束之后，播不到' });
        if (L.type === 'text' && !String(L.text || '').trim()) {
          issues.push({ level: 'warn', text: tag + '文字是空的' });
        }
        if (L.type === 'video' && !L.video.name) {
        issues.push({ level: 'warn', text: tag + '还没有选视频' });
      }
      if (L.type === 'video' && L.video.name && !(doc.assets || {})[L.video.name]) {
        issues.push({ level: 'warn', text: tag + '引用的视频不在工程里（' + L.video.name + '）' });
      }
      if (L.type === 'image' && !L.image.name) {
          issues.push({ level: 'warn', text: tag + '还没选图片' });
        }
        if (L.type === 'image' && L.image.name && !(doc.assets || {})[L.image.name]) {
          issues.push({ level: 'warn', text: tag + '引用的图片不在工程里（' + L.image.name + '）' });
        }
      }

      for (var j = 0; j < (sc.shaders || []).length; j++) {
        var fx = sc.shaders[j];
        if (fx.preset === 'none') {
          issues.push({ level: 'info', text: '「' + (sc.name || '场景') + '」第 ' + (j + 1) + ' 条后处理是「无」' });
        }
      }
    }

    if (!layerTotal) issues.push({ level: 'warn', text: '故事板里还没有图层' });
    if (!doc.chart.notes) issues.push({ level: 'info', text: '还没有导入谱面（只读），谱面场里没有音符' });
    if (doc.scenes.length && !chartScenes) issues.push({ level: 'info', text: '没有谱面场：整条故事板都不会放谱面' });

    if (!issues.length) issues.push({ level: 'ok', text: '没发现问题' });
    return issues;
  }

  /* ==========================================================================
   * 模板（一键套用）
   * ======================================================================== */

  function t0num(t0) { return clamp(round3(num(t0, 0)), -3600, 3600); }

  /**
   * 模板返回 { layers: [...], shaders: [...] }（都还没分配 id，由 applyTemplate 编号）。
   * 文字里可以用 {title} {artist} {difficulty} {level} 占位，套用时按谱面引用替换。
   */
  var TEMPLATES = [
    {
      id: 'opening',
      label: '开场标题卡',
      desc: '曲名发光滑入 + 艺术家 + 一条横线 + 辉光',
      dur: 4.2,
      build: function (t0) {
        return {
          layers: [
            {
              type: 'shape', name: '标题底线', start: t0 + 0.2, end: t0 + 4.2,
              x: 0.5, y: 0.56, scale: 100, rot: 0, alpha: 90, color: '#4cc9f0',
              blend: 'add',
              in: { preset: 'wipe', dur: 0.7, ease: 'outExpo' },
              out: { preset: 'fade', dur: 0.5, ease: 'inCubic' },
              shape: { kind: 'line', w: 0.52, h: 0.004, radius: 0, line: 2, fill: true, count: 8 }
            },
            {
              type: 'text', name: '曲名', start: t0, end: t0 + 4.2,
              x: 0.5, y: 0.42, scale: 100, rot: 0, alpha: 100, blend: 'normal', color: '#ffffff',
              text: '{title}',
              style: {
                size: 82, weight: 800, color: '#ffffff', effect: 'glow', glow: 0.75,
                letter: 0.06, lineH: 1.1, align: 'center',
                stroke: '#000000', strokeW: 0, c1: '#7ef0ff', c2: '#ffffff', speed: 22
              },
              in: { preset: 'slideUp', dur: 0.7, ease: 'outExpo' },
              out: { preset: 'fade', dur: 0.5, ease: 'inCubic' }
            },
            {
              type: 'text', name: '艺术家', start: t0 + 0.45, end: t0 + 4.2,
              x: 0.5, y: 0.63, scale: 100, rot: 0, alpha: 90, blend: 'normal', color: '#c9d3e6',
              text: '{artist}',
              style: {
                size: 30, weight: 500, color: '#c9d3e6', effect: 'plain', glow: 0.2,
                letter: 0.3, lineH: 1.2, align: 'center',
                stroke: '#000000', strokeW: 0, c1: '#c9d3e6', c2: '#ffffff', speed: 24
              },
              in: { preset: 'fade', dur: 0.6, ease: 'outCubic' },
              out: { preset: 'fade', dur: 0.5, ease: 'inCubic' }
            }
          ],
          shaders: [
            { preset: 'bloom', start: t0, end: t0 + 4.2, amount: 55, ramp: 0.3 }
          ]
        };
      }
    },
    {
      id: 'unlock',
      label: '解锁演出',
      desc: '解锁动画 + 「解锁成功」打字机 + 故障闪',
      dur: 5.0,
      build: function (t0) {
        return {
          layers: [
            {
              type: 'unlock', name: '解锁动画', start: t0, end: t0 + 2.6,
              x: 0.5, y: 0.42, scale: 100, rot: 0, alpha: 100, blend: 'normal', color: '#4cc9f0',
              in: { preset: 'none', dur: 0, ease: 'linear' },
              out: { preset: 'fade', dur: 0.4, ease: 'inCubic' },
              unlock: {
                preset: 'tape', label: '{title}', sub: '{difficulty} {level}',
                color: '#4cc9f0', accent: '#f72585', scale: 1
              }
            },
            {
              type: 'text', name: '解锁成功', start: t0 + 2.3, end: t0 + 5.0,
              x: 0.5, y: 0.5, scale: 100, rot: 0, alpha: 100, blend: 'normal', color: '#ffffff',
              text: '解锁成功',
              style: {
                size: 64, weight: 900, color: '#ffffff', effect: 'type', glow: 0.4,
                letter: 0.16, lineH: 1.2, align: 'center',
                stroke: '#0a0d14', strokeW: 3, c1: '#4cc9f0', c2: '#f72585', speed: 10
              },
              in: { preset: 'fade', dur: 0.1, ease: 'linear' },
              out: { preset: 'fade', dur: 0.5, ease: 'inCubic' }
            }
          ],
          shaders: [
            { preset: 'glitch', start: t0 + 2.15, end: t0 + 2.85, amount: 100, ramp: 0.35 },
            { preset: 'bloom', start: t0 + 2.2, end: t0 + 5.0, amount: 45, ramp: 0.4 }
          ]
        };
      }
    },
    {
      id: 'result',
      label: '结算卡',
      desc: '难度等级放大 + 曲名 + 暗角颗粒',
      dur: 4.0,
      build: function (t0) {
        return {
          layers: [
            {
              type: 'shape', name: '衬底', start: t0, end: t0 + 4.0,
              x: 0.5, y: 0.5, scale: 100, rot: 0, alpha: 100, color: '#0b1120',
              blend: 'normal',
              in: { preset: 'fade', dur: 0.6, ease: 'outCubic' },
              out: { preset: 'fade', dur: 0.6, ease: 'inCubic' },
              shape: { kind: 'rect', w: 0.62, h: 0.4, radius: 18, line: 0, fill: true, count: 8 }
            },
            {
              type: 'text', name: '难度', start: t0 + 0.25, end: t0 + 4.0,
              x: 0.5, y: 0.42, scale: 100, rot: 0, alpha: 100, blend: 'add', color: '#ffffff',
              text: '{difficulty}',
              style: {
                size: 88, weight: 900, color: '#ffffff', effect: 'gradient', glow: 0.5,
                letter: 0.08, lineH: 1.1, align: 'center',
                stroke: '#000000', strokeW: 0, c1: '#4cc9f0', c2: '#f72585', speed: 20
              },
              in: { preset: 'zoom', dur: 0.7, ease: 'outExpo' },
              out: { preset: 'pop', dur: 0.5, ease: 'inCubic' }
            },
            {
              type: 'text', name: '等级', start: t0 + 0.5, end: t0 + 4.0,
              x: 0.5, y: 0.56, scale: 100, rot: 0, alpha: 100, blend: 'normal', color: '#ffffff',
              text: 'LEVEL {level}',
              style: {
                size: 34, weight: 700, color: '#e8eefc', effect: 'plain', glow: 0.3,
                letter: 0.24, lineH: 1.2, align: 'center',
                stroke: '#000000', strokeW: 0, c1: '#e8eefc', c2: '#ffffff', speed: 24
              },
              in: { preset: 'fade', dur: 0.5, ease: 'outCubic' },
              out: { preset: 'fade', dur: 0.4, ease: 'inCubic' }
            }
          ],
          shaders: [
            { preset: 'vignette', start: t0, end: t0 + 4.0, amount: 80, ramp: 0.35 }
          ]
        };
      }
    }
  ];

  var TEMPLATE_MAP = {};
  for (var ti = 0; ti < TEMPLATES.length; ti++) TEMPLATE_MAP[TEMPLATES[ti].id] = TEMPLATES[ti];

  /**
   * 模板 / 文字里的占位符：{title} {artist} {charter} {difficulty} {level} {illust}
   * chart = 谱面引用（只读），meta = 故事板自己的信息（曲绘作者就在这里，谱面格式里没有这一栏）
   */
  function fillText(text, chart, meta) {
    var c = chart || emptyDigest();
    var m = meta || {};
    return String(text || '')
      .replace(/\{title\}/g, c.title || '')
      .replace(/\{artist\}/g, c.artist || '')
      .replace(/\{charter\}/g, c.charter || '')
      .replace(/\{difficulty\}/g, c.difficulty || '')
      .replace(/\{illust\}/g, m.coverArtist || c.illustrator || '')
      .replace(/\{level\}/g, String(c.level === undefined ? '' : c.level));
  }

  /**
   * 套用模板：把模板产出的图层/后处理追加到 doc，返回 { layers, shaders }（新建出来的）。
   * 文字里的占位符用 doc.chart 替换。
   *
   * opts.clipEnd = 数字时，把整段模板**收尾到该时刻**（用于「铺在谱面开始之前」：
   * 传 0，模板里超出 0 的那部分被截掉，完全在 0 之后的图层直接不生成）。
   */
  /**
   * 把一套模板铺进**某个场景**。
   * opts.chart = 谱面引用（替换 {title} 之类的占位符）
   * opts.fit   = 场景长度：模板比场景长时按比例压进场景（结构保留，只是快放）
   * opts.limit = 场景长度上限：兜底裁掉超出场景的部分
   */
  function applyTemplate(scene, id, t0, opts) {
    var tpl = TEMPLATE_MAP[id];
    if (!tpl) return null;
    var o = opts || {};
    var chart = o.chart || emptyDigest();
    var meta = o.meta || {};
    var limit = (o.limit === undefined || o.limit === null) ? null : round3(num(o.limit, 0));
    var fit = (o.fit === undefined || o.fit === null) ? null : round3(num(o.fit, 0));
    var t0v = t0num(t0);
    var built = tpl.build(t0v);
    var madeLayers = [];
    var madeShaders = [];

    // 场景放不下整段模板 → 按比例压缩（比如解锁场 2.6 秒放 5 秒的解锁演出）
    var k = 1;
    if (fit !== null && tpl.dur > 1e-6) {
      var avail = fit - t0v;
      if (avail > 0.2 && tpl.dur > avail + 1e-6) k = avail / tpl.dur;
    }
    function T(x) { return round3(t0v + (num(x, t0v) - t0v) * k); }

    for (var i = 0; i < built.layers.length; i++) {
      var spec = JSON.parse(JSON.stringify(built.layers[i]));
      spec.start = T(spec.start);
      spec.end = T(spec.end);
      if (spec.in && spec.in.dur) spec.in.dur = round3(num(spec.in.dur, 0) * k);
      if (spec.out && spec.out.dur) spec.out.dur = round3(num(spec.out.dur, 0) * k);

      var res = normLayer(spec, scene.layers.length);
      var layer = res.layer;
      if (limit !== null) {
        if (layer.start >= limit - 1e-9) continue;
        if (layer.end > limit) layer.end = limit;
      }
      if (layer.start < 0) layer.start = 0;
      if (layer.end - layer.start < 0.05) continue;

      layer.id = nextId(scene.layers);
      if (layer.type === 'text') layer.text = fillText(layer.text, chart, meta);
      if (layer.type === 'unlock') {
        layer.unlock.label = fillText(layer.unlock.label, chart, meta);
        layer.unlock.sub = fillText(layer.unlock.sub, chart, meta);
      }
      scene.layers.push(layer);
      madeLayers.push(layer);
    }

    for (var j = 0; j < (built.shaders || []).length; j++) {
      var fxSpec = JSON.parse(JSON.stringify(built.shaders[j]));
      fxSpec.start = T(fxSpec.start);
      fxSpec.end = T(fxSpec.end);
      var fx = createShader(fxSpec.preset, fxSpec);
      if (limit !== null) {
        if (fx.start >= limit - 1e-9) continue;
        if (fx.end > limit) fx.end = limit;
      }
      if (fx.start < 0) fx.start = 0;
      if (fx.end - fx.start < 0.05) continue;
      fx.id = nextId(scene.shaders);
      scene.shaders.push(fx);
      madeShaders.push(fx);
    }
    scene.shaders.sort(function (a, b) { return a.start - b.start || a.id - b.id; });

    return { layers: madeLayers, shaders: madeShaders, scale: round3(k) };
  }

  /* ==========================================================================
   * 给 UI 用的小函数
   * ======================================================================== */

  /** 图层在列表里的行描述：一行副标题 */
  function describeLayer(layer) {
    if (!layer) return '';
    if (layer.type === 'text') {
      var t = String(layer.text || '').replace(/\n/g, ' / ');
      return t.length > 22 ? t.slice(0, 22) + '…' : t;
    }
    if (layer.type === 'unlock') {
      var u = UNLOCK_PRESETS.filter(function (p) { return p.id === layer.unlock.preset; })[0];
      return u ? u.label : layer.unlock.preset;
    }
    if (layer.type === 'shape') {
      var s = SHAPE_KINDS.filter(function (p) { return p.id === layer.shape.kind; })[0];
      return s ? s.label : layer.shape.kind;
    }
    if (layer.type === 'image') return layer.image.name || '未选图片';
    if (layer.type === 'video') return layer.video.name || '未选视频';
    return '';
  }

  /** 有没有关键帧（用于 UI 上给图层行标个点） */
  function layerKeyCount(layer) {
    var n = 0;
    for (var i = 0; i < CHANNELS.length; i++) {
      n += ((layer.events && layer.events[CHANNELS[i]]) || []).length;
    }
    return n;
  }

  function snapTime(t, timing, div) {
    return RC.snapSec(t, timing || { bpm: 150, beat_offset: 0 }, div || 4);
  }

  function label(list, id) {
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i].label;
    return id;
  }

  /* ==========================================================================
   * 导出
   * ======================================================================== */

  return {
    FORMAT: FORMAT,
    VERSION: VERSION,
    STAGE_W: STAGE_W,
    STAGE_H: STAGE_H,

    clamp: clamp,
    num: num,
    int: int,
    str: str,
    round3: round3,
    ease: ease,
    hexA: hexA,
    hashText: hashText,

    LAYER_TYPES: LAYER_TYPES,
    TYPE_LABELS: TYPE_LABELS,
    IN_PRESETS: IN_PRESETS,
    OUT_PRESETS: OUT_PRESETS,
    TEXT_EFFECTS: TEXT_EFFECTS,
    FONTS: FONTS,
    FONT_MAP: FONT_MAP,
    fontStack: fontStack,
    SHAPE_KINDS: SHAPE_KINDS,
    UNLOCK_PRESETS: UNLOCK_PRESETS,
    BLENDS: BLENDS,
    BLEND_CANVAS: BLEND_CANVAS,
    SHADER_PRESETS: SHADER_PRESETS,
    SHADER_MAP: SHADER_MAP,
    WEIGHT_KEYS: WEIGHT_KEYS,
    SNAP_DIVS: SNAP_DIVS,

    SCENE_KINDS: SCENE_KINDS,
    SCENE_MAP: SCENE_MAP,
    sceneKind: sceneKind,
    sceneKindDef: sceneKindDef,
    createScene: createScene,
    addScene: addScene,
    removeScene: removeScene,
    moveScene: moveScene,
    findScene: findScene,
    sceneIndex: sceneIndex,
    sceneLen: sceneLen,
    sceneSpans: sceneSpans,
    sceneAt: sceneAt,

    CHANNELS: CHANNELS,
    CHANNEL_LABELS: CHANNEL_LABELS,

    emptyEvents: emptyEvents,
    mkEvent: mkEvent,
    addLayerEvent: addLayerEvent,
    removeLayerEvent: removeLayerEvent,
    layerParamsAt: layerParamsAt,
    layerAt: layerAt,

    isVideoAsset: isVideoAsset,
    shaderPreset: shaderPreset,
    activeShaders: activeShaders,
    shaderWeights: shaderWeights,
    emptyWeights: emptyWeights,
    shaderValAt: shaderValAt,
    combineShaderWeights: combineShaderWeights,

    nextId: nextId,
    findLayer: findLayer,
    layerIndex: layerIndex,
    findShader: findShader,
    layerDefaults: layerDefaults,
    createLayer: createLayer,
    addLayer: addLayer,
    removeLayer: removeLayer,
    duplicateLayer: duplicateLayer,
    moveLayer: moveLayer,
    activeLayers: activeLayers,
    createShader: createShader,
    addShader: addShader,
    removeShader: removeShader,

    emptyDigest: emptyDigest,
    chartDigest: chartDigest,
    createStoryboard: createStoryboard,
    normalizeDoc: normalizeDoc,
    serializeDoc: serializeDoc,
    totalLength: totalLength,
    validateDoc: validateDoc,

    TEMPLATES: TEMPLATES,
    TEMPLATE_MAP: TEMPLATE_MAP,
    applyTemplate: applyTemplate,
    fillText: fillText,

    describeLayer: describeLayer,
    layerKeyCount: layerKeyCount,
    snapTime: snapTime,
    label: label
  };
});
