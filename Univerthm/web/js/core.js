/* =============================================================================
 * Rhythm 制谱器 · 核心逻辑
 * 不依赖 DOM：浏览器里挂到 window.RChart，Node 里可以 require 做单元测试。
 * 数据格式是 docs/CHART_FORMAT.md 里 rchart 的子集（只留基础字段，动效以后加）。
 * ========================================================================== */
(function (root, factory) {
  var api = factory();
  if (typeof module === 'object' && module.exports) {
    module.exports = api;
  } else {
    root.RChart = api;
  }
})(typeof self !== 'undefined' ? self : null, function () {
  'use strict';

  var FORMAT = 'rchart';
  var VERSION = 3;
  var NOTE_TYPES = ['tap', 'hold'];

  /* 判定区：决定这条轨道上的音符能被哪些键打到，同时决定显示颜色 */
  var ZONES = ['none', 'left', 'right'];
  var ZONE_COLORS = { none: '#ffffff', left: '#b06bff', right: '#ffd166' };
  var ZONE_LABELS = { none: '无（白）', left: '左（紫）', right: '右（黄）' };
  var ZONE_KEYS = {
    none: ['A', 'S', 'D', 'F', 'J', 'K', 'L', ';'],
    left: ['A', 'S', 'D', 'F'],
    right: ['J', 'K', 'L', ';']
  };
  var DEFAULT_LANE_COLOR = '#ffffff';
  var MAX_LANES = 16;

  /* ---------- 小工具 ---------- */

  function isNum(v) { return typeof v === 'number' && isFinite(v); }

  function num(v, def) {
    if (isNum(v)) return v;
    var f = parseFloat(v);
    return isFinite(f) ? f : def;
  }

  function int(v, def) { return Math.round(num(v, def)); }
  function str(v, def) { return typeof v === 'string' ? v : def; }
  function clamp(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v; }

  function color(v, def) {
    return (typeof v === 'string' && /^#[0-9a-fA-F]{6}$/.test(v)) ? v.toLowerCase() : def;
  }

  function round3(v) { return Math.round(num(v, 0) * 1000) / 1000; }

  /* ---------- 判定区 ---------- */

  function normalizeZone(v) {
    return ZONES.indexOf(v) >= 0 ? v : 'none';
  }

  /** 这条轨道实际用什么颜色画：判定区是 none 时用轨道自己的颜色（默认白） */
  function displayColor(lane) {
    var z = normalizeZone(lane && lane.judge_zone);
    if (z === 'none') return color(lane && lane.color, DEFAULT_LANE_COLOR);
    return ZONE_COLORS[z];
  }

  /** 这条轨道能被哪些键判定 */
  function laneKeys(lane) {
    return ZONE_KEYS[normalizeZone(lane && lane.judge_zone)].slice();
  }

  /* ---------- 时间换算 ---------- */

  function secPerBeat(timing) {
    var bpm = num(timing && timing.bpm, 120);
    if (bpm <= 0) bpm = 120;
    return 60 / bpm;
  }

  /** 第 beat 拍落在第几秒 */
  function beatToSec(beat, timing) {
    return num(timing && timing.beat_offset, 0) + num(beat, 0) * secPerBeat(timing);
  }

  /** 第几秒是第几拍 */
  function secToBeat(sec, timing) {
    return (num(sec, 0) - num(timing && timing.beat_offset, 0)) / secPerBeat(timing);
  }

  /** 把时间吸到 1/div 拍网格上（div=4 → 十六分音符） */
  function snapSec(sec, timing, div) {
    div = num(div, 4) > 0 ? num(div, 4) : 4;
    var beat = secToBeat(sec, timing);
    return beatToSec(Math.round(beat * div) / div, timing);
  }

  /** 00:06.400 */
  function formTime(sec) {
    var neg = num(sec, 0) < 0;
    var s = Math.abs(num(sec, 0));
    var m = Math.floor(s / 60);
    var r = s - m * 60;
    return (neg ? '-' : '') + String(m).padStart(2, '0') + ':' + r.toFixed(3).padStart(6, '0');
  }

  /* ---------- 轨道参数（5 组：坐标 / 透明度 / 流速 / 长度 / 旋转） ---------- */

  var LANE_NUMS = [
    { key: 'x', def: 0, min: -2000, max: 2000, step: 1 },
    { key: 'y', def: 0, min: -2000, max: 2000, step: 1 },
    { key: 'alpha', def: 0, min: 0, max: 100, step: 1 },
    { key: 'speed', def: 10, min: 0, max: 100, step: 1 },
    { key: 'length', def: 10, min: 0, max: 100, step: 1 },
    { key: 'rotation', def: 0, min: -3600, max: 3600, step: 1 }
  ];

  function laneNumDef(key) {
    for (var i = 0; i < LANE_NUMS.length; i++) {
      if (LANE_NUMS[i].key === key) return LANE_NUMS[i];
    }
    return null;
  }

  /** 参数数值范围（事件里改值时用；zone 不是普通数值参数，单独处理） */
  function clampLaneNum(key, v) {
    if (key === 'zone') return clamp(Math.round(num(v, 0)), 0, 2);
    if (key === 'parent') return clamp(Math.round(num(v, 0)), 0, MAX_LANES);
    var f = laneNumDef(key);
    if (!f) return 0;
    return round3(clamp(num(v, f.def), f.min, f.max));
  }

  function laneDefaults() {
    var o = {};
    for (var i = 0; i < LANE_NUMS.length; i++) o[LANE_NUMS[i].key] = LANE_NUMS[i].def;
    return o;
  }

  /** 透明度：0 = 完全隐藏，100 = 完全不透明 → 返回 0~1 的实际不透明度 */
  function laneAlpha(lane) {
    return clamp(num(lane && lane.alpha, 0) / 100, 0, 1);
  }

  /** 音符流速：10 = 1.00×，平方曲线（20 = 4.00×，100 = 100×），0 = 停住 */
  function laneSpeed(lane) {
    var v = clamp(num(lane && lane.speed, 10), 0, 100);
    return v * v / 100;
  }

  /** 轨道长度：10 = 标准长度（判定线到画面顶），0 = 只留底部判定线，100 = 十倍长 */
  function laneLength(lane) {
    return clamp(num(lane && lane.length, 10) / 10, 0, 10);
  }

  function hasLaneParams(lane) {
    for (var i = 0; i < LANE_NUMS.length; i++) {
      var f = LANE_NUMS[i];
      if (num(lane && lane[f.key], f.def) !== f.def) return true;
    }
    return false;
  }

  /* ---------- 缓动（参考 PhiEdit） ---------- */

  var EASE_NAMES = [
    'linear', 'step',
    'inSine', 'outSine', 'inOutSine',
    'inQuad', 'outQuad', 'inOutQuad',
    'inCubic', 'outCubic', 'inOutCubic',
    'inQuart', 'outQuart', 'inOutQuart',
    'inExpo', 'outExpo', 'inOutExpo',
    'inBack', 'outBack', 'inOutBack'
  ];

  /** 同 CSS cubic-bezier：给定 x 反解 t，再算 y */
  function cubicBezierEase(x1, y1, x2, y2) {
    function A(a1, a2) { return 1 - 3 * a2 + 3 * a1; }
    function B(a1, a2) { return 3 * a2 - 6 * a1; }
    function C(a1) { return 3 * a1; }
    function calc(t, a1, a2) { return ((A(a1, a2) * t + B(a1, a2)) * t + C(a1)) * t; }
    function slope(t, a1, a2) { return 3 * A(a1, a2) * t * t + 2 * B(a1, a2) * t + C(a1); }

    return function (x) {
      if (x <= 0) return 0;
      if (x >= 1) return 1;
      var t = x;
      for (var i = 0; i < 8; i++) {
        var d = slope(t, x1, x2);
        if (Math.abs(d) < 1e-6) break;
        t -= (calc(t, x1, x2) - x) / d;
        if (t < 0) t = 0;
        else if (t > 1) t = 1;
      }
      return calc(t, y1, y2);
    };
  }

  /** 缓动求值：k 是 0~1 的线性进度，返回缓动后的进度 */
  function easeAt(name, k) {
    k = clamp(num(k, 0), 0, 1);
    var s = typeof name === 'string' ? name.replace(/\s+/g, '') : 'linear';

    if (s.indexOf('bezier(') === 0) {
      var parts = s.slice(7).replace(/\)/g, '').split(',');
      var nums = [];
      for (var i = 0; i < parts.length; i++) nums.push(parseFloat(parts[i]));
      if (nums.length === 4 && nums.every(isNum)) {
        return cubicBezierEase(nums[0], nums[1], nums[2], nums[3])(k);
      }
      return k;
    }

    var c1 = 1.70158;
    var c3 = c1 + 1;

    switch (s) {
      case 'step': return k < 1 ? 0 : 1;
      case 'inSine': return 1 - Math.cos((k * Math.PI) / 2);
      case 'outSine': return Math.sin((k * Math.PI) / 2);
      case 'inOutSine': return -(Math.cos(Math.PI * k) - 1) / 2;
      case 'inQuad': return k * k;
      case 'outQuad': return 1 - (1 - k) * (1 - k);
      case 'inOutQuad': return k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
      case 'inCubic': return k * k * k;
      case 'outCubic': return 1 - Math.pow(1 - k, 3);
      case 'inOutCubic': return k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
      case 'inQuart': return k * k * k * k;
      case 'outQuart': return 1 - Math.pow(1 - k, 4);
      case 'inOutQuart': return k < 0.5 ? 8 * k * k * k * k : 1 - Math.pow(-2 * k + 2, 4) / 2;
      case 'inExpo': return k === 0 ? 0 : Math.pow(2, 10 * k - 10);
      case 'outExpo': return k === 1 ? 1 : 1 - Math.pow(2, -10 * k);
      case 'inOutExpo':
        if (k === 0) return 0;
        if (k === 1) return 1;
        return k < 0.5 ? Math.pow(2, 20 * k - 10) / 2 : (2 - Math.pow(2, -20 * k + 20)) / 2;
      case 'inBack': return c3 * k * k * k - c1 * k * k;
      case 'outBack': return 1 + c3 * Math.pow(k - 1, 3) + c1 * Math.pow(k - 1, 2);
      case 'inOutBack':
        return k < 0.5
          ? (Math.pow(2 * k, 2) * ((c1 + 1) * 2 * k - c1)) / 2
          : (Math.pow(2 * k - 2, 2) * ((c1 + 1) * (k * 2 - 2) + c1) + 2) / 2;
      default: return k;
    }
  }

  /* ---------- 事件（轨道动画：6 个参数各一条独立通道） ---------- */

  var EVENT_KEYS = ['x', 'y', 'alpha', 'rotation', 'speed', 'length'];
  /** 事件区里的全部通道：6 个数值参数 + 判定区 */
  var ALL_KEYS = EVENT_KEYS.concat(['zone', 'parent']);
  var ZONE_NAMES = ['none', 'left', 'right'];

  function zoneIndex(z) {
    var i = ZONE_NAMES.indexOf(normalizeZone(z));
    return i < 0 ? 0 : i;
  }

  function zoneName(i) {
    return ZONE_NAMES[clamp(Math.round(num(i, 0)), 0, 2)];
  }

  function emptyEvents() {
    var o = {};
    for (var i = 0; i < ALL_KEYS.length; i++) o[ALL_KEYS[i]] = [];
    return o;
  }

  function makeEvent(spec) {
    spec = spec || {};
    var start = Math.max(0, round3(num(spec.start, 0)));
    var end = round3(Math.max(start, num(spec.end, start)));
    return {
      id: int(spec.id, 0),
      start: start,
      end: end,
      ease: (typeof spec.ease === 'string' && spec.ease) ? spec.ease : 'linear',
      from: round3(num(spec.from, 0)),
      to: round3(num(spec.to, 0))
    };
  }

  function sortEvents(arr) {
    arr.sort(function (a, b) { return a.start - b.start || a.id - b.id; });
    return arr;
  }

  function nextEventId(lane) {
    var m = 0;
    var evs = (lane && lane.events) || {};
    for (var i = 0; i < ALL_KEYS.length; i++) {
      var arr = evs[ALL_KEYS[i]] || [];
      for (var j = 0; j < arr.length; j++) if (arr[j].id > m) m = arr[j].id;
    }
    return m + 1;
  }

  function laneEvents(lane, key) {
    if (!lane.events) lane.events = emptyEvents();
    if (!Array.isArray(lane.events[key])) lane.events[key] = [];
    return lane.events[key];
  }

  function addEvent(lane, key, spec) {
    var arr = laneEvents(lane, key);
    var ev = makeEvent(spec);
    ev.id = nextEventId(lane);
    arr.push(ev);
    sortEvents(arr);
    return ev;
  }

  function findEvent(lane, key, id) {
    var arr = (lane && lane.events && lane.events[key]) || [];
    for (var i = 0; i < arr.length; i++) if (arr[i].id === id) return arr[i];
    return null;
  }

  function removeEvent(lane, key, id) {
    var arr = (lane && lane.events && lane.events[key]) || [];
    for (var i = 0; i < arr.length; i++) {
      if (arr[i].id === id) {
        arr.splice(i, 1);
        return true;
      }
    }
    return false;
  }

  /** 某条通道在 t 时刻生效的事件（起点 ≤ t 且起点最晚的那条） */
  function eventAt(lane, key, t) {
    var arr = (lane && lane.events && lane.events[key]) || [];
    var cur = null;
    for (var i = 0; i < arr.length; i++) {
      if (arr[i].start <= t + 1e-9) cur = arr[i];
      else break;
    }
    return cur;
  }

  /** 轨道在某一时刻的 6 个参数：静态值打底，逐条通道套事件 */
  function laneParamsAt(lane, t) {
    var p = {};
    var i, k;

    for (i = 0; i < EVENT_KEYS.length; i++) {
      k = EVENT_KEYS[i];
      p[k] = num(lane && lane[k], laneNumDef(k).def);
    }

    for (i = 0; i < EVENT_KEYS.length; i++) {
      k = EVENT_KEYS[i];
      var cur = eventAt(lane, k, t);
      if (!cur) continue;
      var span = cur.end - cur.start;
      var a = span > 1e-9 ? clamp((t - cur.start) / span, 0, 1) : 1;
      var e = easeAt(cur.ease, a);
      p[k] = cur.from + (cur.to - cur.from) * e;
    }

    p.zone = zoneIndex(zoneAt(lane, t));
    return p;
  }

  /** 判定区在某时刻是哪个：有 zone 事件就按事件，没有就用静态值 */
  function zoneAt(lane, t) {
    var cur = eventAt(lane, 'zone', t);
    if (!cur) return normalizeZone(lane && lane.judge_zone);
    var span = cur.end - cur.start;
    var a = span > 1e-9 ? clamp((t - cur.start) / span, 0, 1) : 1;
    var v = cur.from + (cur.to - cur.from) * easeAt(cur.ease, a);
    return zoneName(v);
  }

  /** 某一刻该轨道画什么颜色（判定区会随时间变） */
  function displayColorAt(lane, t) {
    var z = zoneAt(lane, t);
    if (z === 'none') return color(lane && lane.color, DEFAULT_LANE_COLOR);
    return ZONE_COLORS[z] || ZONE_COLORS.none;
  }

  /**
   * 父线的事件值编码：0 = 没有父线，i + 1 = 挂在第 i 条轨道上
   * （用偏移一位是为了让 0 干净地表示「无」，不和「挂在第 0 条」撞）
   */
  function parentValueOf(index) {
    return index >= 0 ? index + 1 : 0;
  }

  /** 某一刻该轨道的父线序号（-1 = 没有）；没有 parent 事件就用静态值 */
  function parentAt(lane, t, count) {
    var cur = eventAt(lane, 'parent', t);
    if (!cur) return laneParentIndex(lane, count);
    var span = cur.end - cur.start;
    var a = span > 1e-9 ? clamp((t - cur.start) / span, 0, 1) : 1;
    var v = cur.from + (cur.to - cur.from) * easeAt(cur.ease, a);
    var idx = Math.round(v) - 1;
    if (idx < 0 || idx >= count) return -1;
    return idx;
  }

  /**
   * 长条（hold）用的流速倍率。
   * 流速为 0 时音符全压在判定线上、长条会缩成一条线，所以这里回退到
   * 「时间上最近的非零流速」——先往回找（已发生过的），没有再往前找（还没到的那段）。
   * 全篇都找不到非零流速时退回 1.0×，保证长条不会凭空消失。
   */
  function holdSpeed(lane, t) {
    var EPS = 0.001;
    var here = laneSpeed(laneParamsAt(lane, t));
    if (here > EPS) return here;

    // 探测点：每条 speed 事件的两侧稳态 + 最初的静态值
    var probes = [-1e9];
    var arr = (lane && lane.events && lane.events.speed) || [];
    for (var i = 0; i < arr.length; i++) {
      probes.push(arr[i].start - 1e-6);   // 事件开始前那一刻
      probes.push(arr[i].end + 1e-6);     // 事件结束后那一刻
    }

    var best = 0;
    var bestD = Infinity;
    var bestPast = false;
    for (var j = 0; j < probes.length; j++) {
      var pt = probes[j];
      var m = laneSpeed(laneParamsAt(lane, pt));
      if (!(m > EPS)) continue;
      var past = pt <= t;
      var dd = Math.abs(pt - t);
      // 一样近的时候优先「已经发生过的」那一侧
      if (dd < bestD - 1e-9 || (dd <= bestD + 1e-9 && past && !bestPast)) {
        best = m;
        bestD = dd;
        bestPast = past;
      }
    }
    return best > EPS ? best : 1;
  }

  function hasEvents(lane) {
    if (!lane || !lane.events) return false;
    for (var i = 0; i < ALL_KEYS.length; i++) {
      if (((lane.events[ALL_KEYS[i]]) || []).length) return true;
    }
    return false;
  }

  function cloneEvents(src) {
    var out = emptyEvents();
    var used = {};
    var serial = 1;
    var list = [];
    var i, j;

    for (i = 0; i < ALL_KEYS.length; i++) {
      var k = ALL_KEYS[i];
      var arr = (src && Array.isArray(src[k])) ? src[k] : [];
      for (j = 0; j < arr.length; j++) {
        var ev = makeEvent(arr[j]);
        if (!(ev.id > 0) || used[ev.id]) ev.id = 0;
        if (ev.id) used[ev.id] = true;
        list.push([k, ev]);
      }
    }

    for (i = 0; i < list.length; i++) {
      var e2 = list[i][1];
      if (!e2.id) {
        while (used[serial]) serial++;
        e2.id = serial;
        used[serial] = true;
      }
      out[list[i][0]].push(e2);
    }

    for (i = 0; i < ALL_KEYS.length; i++) sortEvents(out[ALL_KEYS[i]]);
    return out;
  }

  /* ---------- ZIP 打包（store 模式，不压缩） ---------- */

  var CRC_TABLE = null;

  function crc32(bytes) {
    if (!CRC_TABLE) {
      CRC_TABLE = new Int32Array(256);
      for (var n = 0; n < 256; n++) {
        var c = n;
        for (var k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
        CRC_TABLE[n] = c;
      }
    }
    var crc = -1;
    for (var i = 0; i < bytes.length; i++) {
      crc = (crc >>> 8) ^ CRC_TABLE[(crc ^ bytes[i]) & 0xFF];
    }
    return (crc ^ -1) >>> 0;
  }

  /** files: [{ name: 'a.json', data: Uint8Array }] → 一个完整 zip 的字节 */
  function zipStore(files) {
    var enc = new TextEncoder();
    var chunks = [];
    var central = [];
    var offset = 0;
    var now = new Date();
    var dosTime = ((now.getHours() << 11) | (now.getMinutes() << 5) | (now.getSeconds() >> 1)) & 0xFFFF;
    var dosDate = (((now.getFullYear() - 1980) << 9) | ((now.getMonth() + 1) << 5) | now.getDate()) & 0xFFFF;
    var i;

    for (i = 0; i < files.length; i++) {
      var f = files[i];
      var nameBytes = enc.encode(f.name);
      var data = f.data;
      var crc = crc32(data);

      var local = new Uint8Array(30 + nameBytes.length);
      var dv = new DataView(local.buffer);
      dv.setUint32(0, 0x04034b50, true);
      dv.setUint16(4, 20, true);
      dv.setUint16(6, 0x0800, true);   // 文件名 UTF-8
      dv.setUint16(8, 0, true);        // store
      dv.setUint16(10, dosTime, true);
      dv.setUint16(12, dosDate, true);
      dv.setUint32(14, crc, true);
      dv.setUint32(18, data.length, true);
      dv.setUint32(22, data.length, true);
      dv.setUint16(26, nameBytes.length, true);
      dv.setUint16(28, 0, true);
      local.set(nameBytes, 30);

      var cd = new Uint8Array(46 + nameBytes.length);
      var cv = new DataView(cd.buffer);
      cv.setUint32(0, 0x02014b50, true);
      cv.setUint16(4, 20, true);
      cv.setUint16(6, 20, true);
      cv.setUint16(8, 0x0800, true);
      cv.setUint16(10, 0, true);
      cv.setUint16(12, dosTime, true);
      cv.setUint16(14, dosDate, true);
      cv.setUint32(16, crc, true);
      cv.setUint32(20, data.length, true);
      cv.setUint32(24, data.length, true);
      cv.setUint16(28, nameBytes.length, true);
      cv.setUint16(30, 0, true);
      cv.setUint16(32, 0, true);
      cv.setUint16(34, 0, true);
      cv.setUint16(36, 0, true);
      cv.setUint32(38, 0, true);
      cv.setUint32(42, offset, true);
      cd.set(nameBytes, 46);

      chunks.push(local, data);
      central.push(cd);
      offset += local.length + data.length;
    }

    var cdOffset = offset;
    var cdSize = 0;
    for (i = 0; i < central.length; i++) {
      chunks.push(central[i]);
      cdSize += central[i].length;
    }

    var eocd = new Uint8Array(22);
    var ev = new DataView(eocd.buffer);
    ev.setUint32(0, 0x06054b50, true);
    ev.setUint16(4, 0, true);
    ev.setUint16(6, 0, true);
    ev.setUint16(8, central.length, true);
    ev.setUint16(10, central.length, true);
    ev.setUint32(12, cdSize, true);
    ev.setUint32(16, cdOffset, true);
    ev.setUint16(20, 0, true);
    chunks.push(eocd);

    var total = 0;
    for (i = 0; i < chunks.length; i++) total += chunks[i].length;
    var out = new Uint8Array(total);
    var pos = 0;
    for (i = 0; i < chunks.length; i++) {
      out.set(chunks[i], pos);
      pos += chunks[i].length;
    }
    return out;
  }

  /** 读一个 zip：返回 Promise<{ 文件名: Uint8Array }> */
  function zipRead(bytes) {
    var n = bytes.length;
    if (n < 22) return Promise.reject(new Error('文件太小，不是 zip'));

    // 从尾部找 EOCD
    var eocd = -1;
    var lowest = Math.max(0, n - 65558);
    for (var i = n - 22; i >= lowest; i--) {
      if (bytes[i] === 0x50 && bytes[i + 1] === 0x4b &&
          bytes[i + 2] === 0x05 && bytes[i + 3] === 0x06) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) return Promise.reject(new Error('没找到 zip 目录（可能不是 zip）'));

    var dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    var count = dv.getUint16(eocd + 10, true);
    var cdOff = dv.getUint32(eocd + 16, true);
    if (cdOff <= 0 || cdOff >= n) return Promise.reject(new Error('zip 中央目录位置不对'));

    var dec = new TextDecoder();
    var p = cdOff;
    var entries = [];

    for (var k = 0; k < count; k++) {
      if (p + 46 > n || dv.getUint32(p, true) !== 0x02014b50) break;
      var method = dv.getUint16(p + 10, true);
      var csize = dv.getUint32(p + 20, true);
      var nameLen = dv.getUint16(p + 28, true);
      var extraLen = dv.getUint16(p + 30, true);
      var commentLen = dv.getUint16(p + 32, true);
      var localOff = dv.getUint32(p + 42, true);
      var name = dec.decode(bytes.subarray(p + 46, p + 46 + nameLen));
      entries.push({ name: name, method: method, csize: csize, localOff: localOff });
      p += 46 + nameLen + extraLen + commentLen;
    }

    var jobs = [];
    for (var j = 0; j < entries.length; j++) {
      (function (e) {
        if (e.name.charAt(e.name.length - 1) === '/') return;   // 目录
        var lo = e.localOff;
        if (lo + 30 > n) return;
        var nl = dv.getUint16(lo + 26, true);
        var el = dv.getUint16(lo + 28, true);
        var start = lo + 30 + nl + el;
        var raw = bytes.subarray(start, start + e.csize);

        if (e.method === 0) {
          jobs.push(Promise.resolve({ name: e.name, data: raw }));
          return;
        }
        if (e.method === 8) {
          if (typeof DecompressionStream === 'undefined') {
            jobs.push(Promise.reject(new Error('这个 zip 用了 deflate，当前浏览器不支持解压')));
            return;
          }
          var ds = new DecompressionStream('deflate-raw');
          jobs.push(
            new Response(new Blob([raw]).stream().pipeThrough(ds))
              .arrayBuffer()
              .then(function (buf) { return { name: e.name, data: new Uint8Array(buf) }; })
          );
          return;
        }
        jobs.push(Promise.reject(new Error('不支持的压缩方式：' + e.method)));
      })(entries[j]);
    }

    return Promise.all(jobs).then(function (list) {
      var out = {};
      for (var m = 0; m < list.length; m++) out[list[m].name] = list[m].data;
      return out;
    });
  }

  /* ---------- 谱面对象 ---------- */

  function makeLane(name, col, zone, src) {
    var lane = { name: name, color: col, judge_zone: zone, parent: -1 };
    for (var i = 0; i < LANE_NUMS.length; i++) {
      var f = LANE_NUMS[i];
      lane[f.key] = clampLaneNum(f.key, src ? src[f.key] : f.def);
    }
    lane.parent = int(src && src.parent, -1);
    lane.events = cloneEvents(src ? src.events : null);
    return lane;
  }

  /** 父线序号：越界 / 指向自己都当没有父线 */
  function laneParentIndex(lane, count) {
    var idx = int(lane && lane.parent, -1);
    if (idx < 0 || idx >= count) return -1;
    return idx;
  }

  /** 打断父线关系里的环，顺便夹到合法范围 */
  function fixLaneParents(lanes) {
    var n = lanes.length;
    for (var i = 0; i < n; i++) {
      var p = int(lanes[i].parent, -1);
      if (p < 0 || p >= n || p === i) { lanes[i].parent = -1; continue; }
      var cur = p;
      var guard = 0;
      while (cur >= 0 && guard++ < n + 2) {
        if (cur === i) { lanes[i].parent = -1; break; }
        cur = laneParentIndex(lanes[cur], n);
      }
    }
    return lanes;
  }

  function makeLanes(count, existing) {
    var out = [];
    for (var i = 0; i < count; i++) {
      var old = existing && existing[i];
      var lane = makeLane(
        old && old.name ? old.name : ('Lane ' + (i + 1)),
        color(old && old.color, DEFAULT_LANE_COLOR),
        normalizeZone(old && old.judge_zone),
        old
      );
      // 新建的轨道在起点铺 6 条默认事件，这样侧栏不用单独放一套参数输入框
      if (!hasEvents(lane)) seedDefaultEvents(lane);
      out.push(lane);
    }
    return fixLaneParents(out);
  }

  /** 默认事件长度（秒） */
  var DEFAULT_EVENT_LEN = 0.5;

  /** 在 t=0 处给 6 条数值通道各放一条「头尾都等于当前值」的事件
   *  （判定区不铺：没事件时就用静态 judge_zone，铺了反而会盖住侧栏那个下拉） */
  function seedDefaultEvents(lane) {
    if (!lane.events) lane.events = emptyEvents();
    var seedKeys = EVENT_KEYS.concat(['parent']);
    for (var i = 0; i < seedKeys.length; i++) {
      var k = seedKeys[i];
      if ((lane.events[k] || []).length) continue;
      var baseV = (k === 'parent') ? parentValueOf(laneParentIndex(lane, MAX_LANES)) : lane[k];
      lane.events[k].push(makeEvent({
        id: nextEventId(lane),
        start: 0,
        end: DEFAULT_EVENT_LEN,
        ease: 'linear',
        from: baseV,
        to: baseV
      }));
    }
    return lane;
  }

  function createChart(opts) {
    opts = opts || {};
    var lanes = clamp(int(opts.lane_count, 4), 1, MAX_LANES);
    return {
      format: FORMAT,
      version: VERSION,
      meta: {
        title: '未命名谱面',
        artist: '',
        charter: '',
        illustrator: '',
        difficulty: 'NORMAL',
        level: 1,
        cover: ''
      },
      audio: { file: '', offset: 0, volume_db: 0, hit_volume_db: -3 },
      timing: { bpm: 150, beat_offset: 0 },
      stage: { lane_count: lanes, highway_length: 2.0 },
      lanes: makeLanes(lanes),
      notes: []
    };
  }

  /* ---------- 音符 ---------- */

  function noteEnd(n) {
    return n.type === 'hold' ? n.time + Math.max(0, num(n.duration, 0)) : n.time;
  }

  function sortNotes(chart) {
    chart.notes.sort(function (a, b) {
      return a.time - b.time || a.lane - b.lane || a.id - b.id;
    });
    return chart.notes;
  }

  function nextId(chart) {
    var m = 0;
    for (var i = 0; i < chart.notes.length; i++) {
      if (chart.notes[i].id > m) m = chart.notes[i].id;
    }
    return m + 1;
  }

  function findNote(chart, id) {
    for (var i = 0; i < chart.notes.length; i++) {
      if (chart.notes[i].id === id) return chart.notes[i];
    }
    return null;
  }

  function addNote(chart, spec) {
    spec = spec || {};
    var lanes = chart.lanes.length;
    var n = {
      id: nextId(chart),
      time: Math.max(0, round3(num(spec.time, 0))),
      lane: clamp(int(spec.lane, 0), 0, lanes - 1),
      type: NOTE_TYPES.indexOf(spec.type) >= 0 ? spec.type : 'tap',
      duration: 0
    };
    if (n.type === 'hold') n.duration = Math.max(0, round3(num(spec.duration, 0)));
    chart.notes.push(n);
    sortNotes(chart);
    return n;
  }

  function removeNote(chart, id) {
    for (var i = 0; i < chart.notes.length; i++) {
      if (chart.notes[i].id === id) {
        chart.notes.splice(i, 1);
        return true;
      }
    }
    return false;
  }

  /** 同一轨道、几乎同一时间的音符（防手抖重复放置） */
  function findAt(chart, lane, time, eps) {
    eps = num(eps, 1e-4);
    for (var i = 0; i < chart.notes.length; i++) {
      var n = chart.notes[i];
      if (n.lane === lane && Math.abs(n.time - time) <= eps) return n;
    }
    return null;
  }

  function countNotes(chart) {
    var c = { tap: 0, hold: 0, total: chart.notes.length };
    for (var i = 0; i < chart.notes.length; i++) {
      var t = chart.notes[i].type;
      if (c[t] === undefined) c[t] = 0;
      c[t]++;
    }
    return c;
  }

  function chartDuration(chart) {
    var d = 0;
    for (var i = 0; i < chart.notes.length; i++) {
      var e = noteEnd(chart.notes[i]);
      if (e > d) d = e;
    }
    return d;
  }

  /* ---------- 轨道 ---------- */

  function setLaneCount(chart, count) {
    var n = clamp(int(count, 4), 1, MAX_LANES);
    chart.stage.lane_count = n;
    chart.lanes = makeLanes(n, chart.lanes);
    var moved = 0;
    for (var i = 0; i < chart.notes.length; i++) {
      if (chart.notes[i].lane > n - 1) {
        chart.notes[i].lane = n - 1;
        moved++;
      }
    }
    return { laneCount: n, moved: moved };
  }

  /* ---------- 读入 / 写出 ---------- */

  function normalize(raw) {
    var warnings = [];

    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
      return { chart: null, warnings: ['文件内容不是 JSON 对象，打不开'] };
    }
    if (raw.format !== undefined && raw.format !== FORMAT) {
      return { chart: null, warnings: ['文件格式不是 rchart 谱面，打不开'] };
    }

    var rawStage = (raw.stage && typeof raw.stage === 'object') ? raw.stage : {};
    var rawLanes = Array.isArray(raw.lanes) ? raw.lanes : [];
    var laneCount = rawLanes.length > 0 ? rawLanes.length : int(rawStage.lane_count, 4);
    laneCount = clamp(laneCount, 1, MAX_LANES);

    var chart = createChart({ lane_count: laneCount });

    // meta
    var meta = (raw.meta && typeof raw.meta === 'object') ? raw.meta : {};
    chart.meta.title = str(meta.title, chart.meta.title);
    chart.meta.artist = str(meta.artist, '');
    chart.meta.charter = str(meta.charter, '');
    chart.meta.illustrator = str(meta.illustrator, '');   // 曲绘作者（画师）
    chart.meta.difficulty = str(meta.difficulty, 'NORMAL');
    chart.meta.level = clamp(int(meta.level, 1), 1, 99);
    chart.meta.cover = str(meta.cover, '');

    // timing
    var timing = (raw.timing && typeof raw.timing === 'object') ? raw.timing : {};
    var bpm = num(timing.bpm, 150);
    if (Array.isArray(timing.bpm_events) && timing.bpm_events.length > 1) {
      warnings.push('这个谱面有变速（bpm_events），当前版本只按第一个 BPM 读');
      bpm = num(timing.bpm_events[0] && timing.bpm_events[0].bpm, bpm);
    }
    if (!(bpm > 0)) {
      warnings.push('BPM 不合法，已改成 150');
      bpm = 150;
    }
    chart.timing.bpm = clamp(round3(bpm), 20, 1000);
    chart.timing.beat_offset = round3(num(timing.beat_offset, 0));

    // audio
    var audio = (raw.audio && typeof raw.audio === 'object') ? raw.audio : {};
    chart.audio.file = str(audio.file, '');
    chart.audio.offset = round3(num(audio.offset, 0));
    chart.audio.volume_db = clamp(num(audio.volume_db, 0), -60, 12);
    chart.audio.hit_volume_db = clamp(num(audio.hit_volume_db, -3), -60, 12);

    // stage
    chart.stage.lane_count = laneCount;
    chart.stage.highway_length = clamp(num(rawStage.highway_length, 2.0), 0.25, 30);

    // lanes
    for (var i = 0; i < laneCount; i++) {
      var rl = (rawLanes[i] && typeof rawLanes[i] === 'object') ? rawLanes[i] : {};
      chart.lanes[i] = makeLane(
        str(rl.name, chart.lanes[i].name),
        color(rl.color, DEFAULT_LANE_COLOR),
        normalizeZone(rl.judge_zone),
        rl
      );
    }

    // notes：先认下合法的 id，再给缺的补新 id
    var rawNotes = Array.isArray(raw.notes) ? raw.notes : [];
    var used = {};
    var loose = [];
    var badCount = 0;

    for (var k = 0; k < rawNotes.length; k++) {
      var rn = rawNotes[k];
      if (!rn || typeof rn !== 'object') { badCount++; continue; }
      var id = int(rn.id, 0);
      if (id > 0 && !used[id]) {
        used[id] = true;
      } else {
        id = 0;
      }
      loose.push({ raw: rn, id: id });
    }

    var out = [];
    var serial = 1;
    for (var j = 0; j < loose.length; j++) {
      var item = loose[j];
      var r = item.raw;
      var nid = item.id;
      if (!nid) {
        while (used[serial]) serial++;
        nid = serial;
        used[nid] = true;
      }

      var t = Math.max(0, round3(num(r.time, 0)));
      var lane = int(r.lane, 0);
      if (lane < 0 || lane > laneCount - 1) {
        lane = clamp(lane, 0, laneCount - 1);
        warnings.push('有音符的轨道越界，已夹到合法轨道');
      }
      var type = NOTE_TYPES.indexOf(r.type) >= 0 ? r.type : 'tap';
      if (type !== r.type && r.type !== undefined) {
        warnings.push('有音符类型不认识（' + String(r.type) + '），当成 tap');
      }
      var dur = 0;
      if (type === 'hold') {
        dur = Math.max(0, round3(num(r.duration, 0)));
        if (dur <= 0.001) type = 'tap';
      }
      out.push({ id: nid, time: t, lane: lane, type: type, duration: dur });
    }

    if (badCount > 0) warnings.push('丢掉了 ' + badCount + ' 条格式不对的音符');
    chart.notes = out;
    sortNotes(chart);

    // 去重告警
    var dup = 0;
    for (var a = 1; a < chart.notes.length; a++) {
      var p = chart.notes[a - 1], c = chart.notes[a];
      if (p.lane === c.lane && Math.abs(p.time - c.time) <= 1e-4) dup++;
    }
    if (dup > 0) warnings.push('有 ' + dup + ' 组同轨同位置的重复音符');

    return { chart: chart, warnings: warnings };
  }

  function serialize(chart) {
    var notes = sortNotes(chart).map(function (n) {
      var o = { id: n.id, time: round3(n.time), lane: n.lane, type: n.type };
      if (n.type === 'hold') o.duration = round3(n.duration);
      return o;
    });

    return {
      format: FORMAT,
      version: VERSION,
      meta: {
        title: chart.meta.title,
        artist: chart.meta.artist,
        charter: chart.meta.charter,
        illustrator: chart.meta.illustrator || '',
        difficulty: chart.meta.difficulty,
        level: chart.meta.level,
        cover: chart.meta.cover || ''
      },
      audio: {
        file: chart.audio.file,
        offset: chart.audio.offset,
        volume_db: chart.audio.volume_db,
        hit_volume_db: chart.audio.hit_volume_db
      },
      timing: {
        bpm: round3(chart.timing.bpm),
        beat_offset: round3(chart.timing.beat_offset)
      },
      stage: {
        lane_count: chart.lanes.length,
        highway_length: chart.stage.highway_length
      },
      lanes: chart.lanes.map(function (l) {
        var o = {
          name: l.name,
          color: l.color,
          judge_zone: normalizeZone(l.judge_zone)
        };
        if (int(l.parent, -1) >= 0) o.parent = int(l.parent, -1);
        for (var i = 0; i < LANE_NUMS.length; i++) {
          var k = LANE_NUMS[i].key;
          o[k] = clampLaneNum(k, l[k]);
        }
        if (hasEvents(l)) {
          var eo = {};
          for (var ei = 0; ei < ALL_KEYS.length; ei++) {
            var ek = ALL_KEYS[ei];
            var arr = (l.events && l.events[ek]) || [];
            if (!arr.length) continue;
            eo[ek] = arr.map(function (ev) {
              return {
                start: round3(ev.start),
                end: round3(ev.end),
                ease: ev.ease,
                from: round3(ev.from),
                to: round3(ev.to)
              };
            });
          }
          o.events = eo;
        }
        return o;
      }),
      notes: notes
    };
  }

  /* ---------- 校验 ---------- */

  /** 同轨道、同时间的音符分组（每组 >= 2 个才算重叠），按时间排好 */
  function duplicateGroups(chart) {
    var map = {};
    var notes = (chart && chart.notes) || [];
    var i;
    for (i = 0; i < notes.length; i++) {
      var n = notes[i];
      var k = n.lane + '@' + round3(n.time);
      if (!map[k]) map[k] = [];
      map[k].push(n);
    }
    var out = [];
    for (var key in map) {
      if (!Object.prototype.hasOwnProperty.call(map, key)) continue;
      if (map[key].length > 1) {
        out.push({ lane: map[key][0].lane, time: map[key][0].time, notes: map[key] });
      }
    }
    out.sort(function (a, b) { return a.time - b.time || a.lane - b.lane; });
    return out;
  }

  /** 有问题的位置（按时间排好），给「跳到问题」用 */
  function chartIssues(chart) {
    var out = [];
    var notes = (chart && chart.notes) || [];
    var lanes = (chart && chart.lanes) ? chart.lanes.length : 0;
    var i, j;

    // 1. 同轨同位置的重复音符
    var groups = duplicateGroups(chart);
    for (i = 0; i < groups.length; i++) {
      var ids = [];
      for (j = 0; j < groups[i].notes.length; j++) ids.push(groups[i].notes[j].id);
      out.push({
        kind: 'dup', level: 'warn', time: groups[i].time, lane: groups[i].lane,
        text: '同轨同位置有 ' + groups[i].notes.length + ' 个音符', ids: ids
      });
    }

    // 2. 长度为 0 的 hold / 时间或轨道非法
    for (i = 0; i < notes.length; i++) {
      var n = notes[i];
      if (n.type === 'hold' && !(n.duration > 0.001)) {
        out.push({ kind: 'zero-hold', level: 'warn', time: n.time, lane: n.lane, text: 'hold 长度为 0', ids: [n.id] });
      }
      if (!(n.time >= 0)) {
        out.push({ kind: 'bad-time', level: 'error', time: n.time, lane: n.lane, text: '音符时间是负的', ids: [n.id] });
      }
      if (n.lane < 0 || n.lane >= lanes) {
        out.push({ kind: 'bad-lane', level: 'error', time: n.time, lane: n.lane, text: '音符轨道越界', ids: [n.id] });
      }
    }

    // 3. hold 的时段里压了别的音符（同轨）—— 打起来会互相干扰
    var byLane = {};
    for (i = 0; i < notes.length; i++) {
      if (!byLane[notes[i].lane]) byLane[notes[i].lane] = [];
      byLane[notes[i].lane].push(notes[i]);
    }
    for (var lk in byLane) {
      if (!Object.prototype.hasOwnProperty.call(byLane, lk)) continue;
      var list = byLane[lk];
      for (i = 0; i < list.length; i++) {
        var h = list[i];
        if (h.type !== 'hold' || !(h.duration > 0.001)) continue;
        var hEnd = h.time + h.duration;
        for (j = 0; j < list.length; j++) {
          var o = list[j];
          if (o === h) continue;
          if (o.time > h.time + 0.002 && o.time < hEnd - 0.002) {
            out.push({
              kind: 'hold-cover', level: 'warn', time: o.time, lane: h.lane,
              text: '长条中间压了别的音符', ids: [h.id, o.id]
            });
          }
        }
      }
    }

    out.sort(function (a, b) { return a.time - b.time || a.lane - b.lane; });
    return out;
  }

  function validate(chart) {
    var issues = [];
    var laneCount = chart.lanes.length;

    if (chart.notes.length === 0) {
      issues.push({ level: 'warn', text: '谱面里还没有音符' });
      return issues;
    }

    var badTime = 0, badLane = 0, badHold = 0, dup = 0;
    var prev = null;

    for (var i = 0; i < chart.notes.length; i++) {
      var n = chart.notes[i];
      if (!(n.time >= 0)) badTime++;
      if (n.lane < 0 || n.lane > laneCount - 1) badLane++;
      if (n.type === 'hold' && !(n.duration > 0.001)) badHold++;
      if (prev && prev.lane === n.lane && Math.abs(prev.time - n.time) <= 1e-4) dup++;
      prev = n;
    }

    if (badTime) issues.push({ level: 'error', text: badTime + ' 个音符时间为负' });
    if (badLane) issues.push({ level: 'error', text: badLane + ' 个音符轨道越界' });
    if (badHold) issues.push({ level: 'warn', text: badHold + ' 个 hold 长度为 0（会按 tap 算）' });
    if (dup) issues.push({ level: 'warn', text: dup + ' 组同轨同位置的重复音符' });

    return issues;
  }

  return {
    FORMAT: FORMAT,
    VERSION: VERSION,
    NOTE_TYPES: NOTE_TYPES,
    ZONES: ZONES,
    ZONE_COLORS: ZONE_COLORS,
    ZONE_LABELS: ZONE_LABELS,
    ZONE_KEYS: ZONE_KEYS,
    DEFAULT_LANE_COLOR: DEFAULT_LANE_COLOR,
    MAX_LANES: MAX_LANES,

    num: num,
    int: int,
    clamp: clamp,
    round3: round3,
    formTime: formTime,

    normalizeZone: normalizeZone,
    displayColor: displayColor,
    laneKeys: laneKeys,

    LANE_NUMS: LANE_NUMS,
    laneNumDef: laneNumDef,
    clampLaneNum: clampLaneNum,
    laneDefaults: laneDefaults,
    laneAlpha: laneAlpha,
    laneSpeed: laneSpeed,
    laneLength: laneLength,
    hasLaneParams: hasLaneParams,

    EASE_NAMES: EASE_NAMES,
    easeAt: easeAt,
    cubicBezierEase: cubicBezierEase,
    EVENT_KEYS: EVENT_KEYS,
    ALL_KEYS: ALL_KEYS,
    ZONE_NAMES: ZONE_NAMES,
    zoneIndex: zoneIndex,
    zoneName: zoneName,
    zoneAt: zoneAt,
    parentAt: parentAt,
    parentValueOf: parentValueOf,
    laneParentIndex: laneParentIndex,
    fixLaneParents: fixLaneParents,
    displayColorAt: displayColorAt,
    holdSpeed: holdSpeed,
    makeEvent: makeEvent,
    cloneEvents: cloneEvents,
    emptyEvents: emptyEvents,
    addEvent: addEvent,
    findEvent: findEvent,
    removeEvent: removeEvent,
    eventAt: eventAt,
    sortEvents: sortEvents,
    laneEvents: laneEvents,
    hasEvents: hasEvents,
    laneParamsAt: laneParamsAt,

    crc32: crc32,
    zipStore: zipStore,
    zipRead: zipRead,

    beatToSec: beatToSec,
    secToBeat: secToBeat,
    secPerBeat: secPerBeat,
    snapSec: snapSec,

    createChart: createChart,
    normalize: normalize,
    serialize: serialize,
    validate: validate,
    duplicateGroups: duplicateGroups,
    chartIssues: chartIssues,

    noteEnd: noteEnd,
    sortNotes: sortNotes,
    findNote: findNote,
    findAt: findAt,
    addNote: addNote,
    removeNote: removeNote,
    countNotes: countNotes,
    chartDuration: chartDuration,
    setLaneCount: setLaneCount
  };
});
