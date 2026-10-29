/* 界面冒烟测试：用假 DOM 把 editor.js 真跑一遍，模拟鼠标键盘。
 * node web/test/ui.smoke.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

let pass = 0;
const fails = [];
const logs = [];

function ok(cond, name) {
  if (cond) pass++;
  else fails.push(name);
}

/* ---------------- 假 DOM ---------------- */

let nowMs = 1000;
const winListeners = {};
let rafCb = null;

function El(id) {
  this.id = id;
  this.textContent = '';
  this.value = '';
  this.disabled = false;
  this.style = {};
  this.tagName = 'DIV';
  this._listeners = {};
}
El.prototype.addEventListener = function (t, fn) {
  (this._listeners[t] = this._listeners[t] || []).push(fn);
};
El.prototype.fire = function (t, ev) {
  const list = this._listeners[t] || [];
  for (const fn of list.slice()) fn.call(this, ev || {});
};
El.prototype.getBoundingClientRect = function () {
  return { left: 0, top: 0, width: this.clientWidth || 0, height: this.clientHeight || 0 };
};
El.prototype.click = function () { this.fire('click', {}); };
El.prototype.appendChild = function () {};
El.prototype.removeChild = function () {};
El.prototype.blur = function () {};
El.prototype.focus = function () {};
El.prototype.setPointerCapture = function () {};
El.prototype.releasePointerCapture = function () {};
El.prototype.getContext = function () {
  if (!this._ctx) this._ctx = makeCtx();
  return this._ctx;
};

function makeCtx() {
  const target = { _calls: [] };
  return new Proxy(target, {
    get(t, k) {
      if (k === '_calls') return t._calls;
      if (k in t) return t[k];
      const fn = function (...args) {
        let style;
        if (k === 'fill' || k === 'fillRect') style = t.fillStyle;
        else if (k === 'stroke' || k === 'strokeRect') style = t.strokeStyle;
        t._calls.push([String(k), ...args, style]);
        return undefined;
      };
      t[k] = fn;
      return fn;
    },
    set(t, k, v) { t[k] = v; return true; }
  });
}

const els = {};
const audioInstances = [];
const blobCalls = [];
const canvasEl = new El('canvas');
canvasEl.tagName = 'CANVAS';
canvasEl.clientWidth = 1000;
canvasEl.clientHeight = 800;
canvasEl.width = 0;
canvasEl.height = 0;
els.canvas = canvasEl;
const canvasCtx = canvasEl.getContext('2d');

// 预渲染窗口：16:9，这里给 400x225
const previewEl = new El('preview');
previewEl.tagName = 'CANVAS';
previewEl.clientWidth = 400;
previewEl.clientHeight = 225;
previewEl.width = 0;
previewEl.height = 0;
els.preview = previewEl;
const previewCtx = previewEl.getContext('2d');

// 缓动曲线的小画布：200x66
const easeEl = new El('ease-canvas');
easeEl.tagName = 'CANVAS';
easeEl.clientWidth = 200;
easeEl.clientHeight = 66;
easeEl.width = 0;
easeEl.height = 0;
els['ease-canvas'] = easeEl;
const easeCtx = easeEl.getContext('2d');

function callsOf(ctx, name, pred) {
  const list = ctx._calls;
  const out = [];
  for (const c of list) {
    if (c[0] !== name) continue;
    if (!pred || pred(c)) out.push(c);
  }
  return out;
}

const documentStub = {
  readyState: 'complete',
  activeElement: null,
  body: new El('body'),
  getElementById(id) {
    if (!els[id]) els[id] = new El(id);
    return els[id];
  },
  createElement(tag) { return new El(tag); },
  addEventListener() {}
};

const ctxObj = {
  console: {
    log: (...a) => logs.push(a.join(' ')),
    warn: (...a) => logs.push('WARN ' + a.join(' ')),
    error: (...a) => logs.push('ERR ' + a.join(' '))
  },
  performance: { now: () => nowMs },
  devicePixelRatio: 2,
  requestAnimationFrame(cb) { rafCb = cb; return 1; },
  document: documentStub,
  URL: { createObjectURL: () => 'blob:stub', revokeObjectURL() {} },
  Blob: function (parts, opts) { blobCalls.push({ parts: parts, type: opts && opts.type }); },
  TextEncoder: TextEncoder,
  TextDecoder: TextDecoder,
  FileReader: function () {},
  alert(message) { logs.push('ALERT ' + message); },
  confirm: () => true,
  setTimeout: (fn) => 0,
  clearTimeout: () => {},
  addEventListener(type, fn) { (winListeners[type] = winListeners[type] || []).push(fn); },
  Audio: function (src) {
    audioInstances.push(this);
    this.volume = 1;
    this.currentTime = 0;
    this.duration = 0;
    this.readyState = 4;
    this.src = src || '';
    this.plays = 0;
    this.play = () => { this.plays++; return { catch() {} }; };
    this.pause = () => {};
  }
};
ctxObj.window = ctxObj;
ctxObj.self = ctxObj;
ctxObj.globalThis = ctxObj;

const sandbox = vm.createContext(ctxObj);

try {
  vm.runInContext(read('js/core.js'), sandbox, { filename: 'core.js' });
  vm.runInContext(read('js/editor.js'), sandbox, { filename: 'editor.js' });
  ok(true, '脚本加载 + boot 没抛异常');
} catch (err) {
  ok(false, '脚本加载 + boot 抛异常：' + err.message);
  report();
  return;
}

/* ---------------- 工具 ---------------- */

function frame(n) {
  for (let i = 0; i < (n || 1); i++) {
    const cb = rafCb;
    rafCb = null;
    if (cb) cb();
    nowMs += 16;
  }
}

function key(k, mods) {
  const ev = Object.assign({
    key: k, code: k === ' ' ? 'Space' : k,
    ctrlKey: false, shiftKey: false, metaKey: false,
    target: { tagName: 'CANVAS' },
    preventDefault() {}
  }, mods || {});
  (winListeners.keydown || []).forEach((fn) => fn(ev));
}

function ptr(type, x, y, button, extra) {
  canvasEl.fire(type, Object.assign(
    { button: button || 0, pointerId: 1, clientX: x, clientY: y },
    extra || {}
  ));
}

function wheel(deltaY, ctrl) {
  canvasEl.fire('wheel', {
    deltaY: deltaY, ctrlKey: !!ctrl, shiftKey: false, preventDefault() {}
  });
}

function statusNotes() { return els['st-notes'].textContent; }
function statusLen() { return els['st-len'].textContent; }
function statusTime() { return els['st-time'].textContent; }
function noteTotal() {
  const m = /音符\s+(\d+)/.exec(statusNotes());
  return m ? Number(m[1]) : -1;
}
function countOf(type) {
  const m = new RegExp(type + '\\s+(\\d+)').exec(statusNotes());
  return m ? Number(m[1]) : -1;
}

/* ---------------- 布局核对 ---------------- */
// clientWidth 1000 / clientHeight 800：judgeY = 672，gutter = 56
// laneW = min(160, (1000-56)/4) = 160，laneX0 = 56 + (944-640)/2 = 208
// pps = 672 / 2.0 = 336 像素/秒
// 时间轴画布 1000x800、4 轨：gutter 56 + 密度条 52 + 音符区 / 事件区各一半
const TL_GUTTER = 56, TL_PAD = 10, TL_MINI = 52, TL_DIVIDER = 14;
const TL_NOTES_LEFT = TL_GUTTER + TL_PAD + TL_MINI + 10;      // 128
const TL_HALF = Math.max(60, (1000 - TL_NOTES_LEFT - TL_PAD - TL_DIVIDER) / 2);  // 424
const TL_LANE_W = Math.max(14, Math.min(120, TL_HALF / 4));    // 106
const TL_NOTE_X0 = TL_NOTES_LEFT;                              // 128
const TL_EVENT_X0 = TL_NOTES_LEFT + TL_HALF + TL_DIVIDER;      // 566
const laneCenter = (i) => TL_NOTE_X0 + TL_LANE_W * i + TL_LANE_W / 2;
const EV_COL_W = TL_HALF / 8;   // 8 列：6 个参数 + 判定区 + 父线
const eventColCenter = (i) => TL_EVENT_X0 + EV_COL_W * i + EV_COL_W / 2;
const TL_BTN_W = Math.max(18, Math.min(38, (TL_HALF - 8) / 4 - 4));
const TL_BTN_X = TL_EVENT_X0 + (TL_HALF - (4 * (TL_BTN_W + 4) - 4)) / 2;
const laneBtnCenter = (i) => TL_BTN_X + i * (TL_BTN_W + 4) + TL_BTN_W / 2;
const laneBtnY = 672 + 40 + 9.5;

const LANE0 = laneCenter(0);   // 181
const LANE1 = laneCenter(1);   // 287
const LANE2 = laneCenter(2);   // 393
const LANE3 = laneCenter(3);   // 499
const xAt = (t) => 672 - t * 336;

// 预渲染窗口 400x300、4 轨、可视 2 秒时的几何
const PVW = 400, PVH = 225;
const JUDGE = Math.round(PVH * 0.85);                 // 255
const PV_SCALE = 1.6;
const LANE_W = Math.min(PVW * 0.05, PVW * 0.43 / 4) * PV_SCALE;  // 32
const HALF = LANE_W / 2 - 0.5;                        // 9.5（轨道半宽）
const NHALF = Math.max(2, HALF - 1);                  // 8.5（音符半宽）
const NTH = 2.0;                                      // 音符半厚
const CX = PVW / 2;                                   // 200（舞台正中）
const PPS = JUDGE / 2;                                // 127.5（1.00× 时的像素/秒）
const noteX = (xoff) => CX + (xoff || 0) - NHALF;
const noteY = (mul) => JUDGE - PPS * (mul === undefined ? 1 : mul) + NTH;

(async function runPhases() {
try {
  frame(1);
  ok(els['st-hint'].textContent.length > 0, '状态栏提示已初始化');
  ok(noteTotal() === 0, '初始 0 个音符，实际 ' + noteTotal());
  ok(statusLen().includes('00:00.000'), '初始时长 0，实际 ' + statusLen());

  // 每个阶段从空谱面开始；需要媒体的阶段显式重装测试媒体。
  function reset() {
    const previousAudio = audioInstances.filter((a) => a.src === 'blob:stub').slice(-1)[0];
    const hadCover = els['cover-img'] && els['cover-img'].src === 'blob:stub' && !els['cover-img'].hidden;
    els['btn-new'].fire('click', {});
    if (previousAudio) {
      els['file-audio'].fire('change', {
        target: { files: [{ name: 'song.mp3', arrayBuffer: () => Promise.resolve(new Uint8Array([1, 2, 3, 4]).buffer) }], value: '' }
      });
      audioInstances[audioInstances.length - 1].duration = previousAudio.duration;
    }
    if (hadCover) {
      els['file-cover'].fire('change', {
        target: { files: [{ name: 'cover.png', arrayBuffer: () => Promise.resolve(new Uint8Array([137, 80, 78, 71]).buffer) }], value: '' }
      });
    }
    frame(1);
  }

  // 侧栏那套参数输入框已经取消，轨道参数改成「起点处的默认事件」，统一走事件面板
  function selectLane(i) {
    ptr('pointerdown', laneBtnCenter(i), laneBtnY);
    ptr('pointerup', laneBtnCenter(i), laneBtnY);
  }

  /** 点开某条通道在 0 ~ 0.5s 的那条默认事件（要求在 viewTime = 0 时调用） */
  function openLaneEvent(colIdx) {
    ptr('pointerdown', eventColCenter(colIdx), xAt(0.25));
    ptr('pointerup', eventColCenter(colIdx), xAt(0.25));
  }

  /** 改某条轨道某个参数的默认事件（colIdx: 0=x 1=y 2=alpha 3=rotation 4=speed 5=length） */
  function setLaneParam(laneIdx, colIdx, from, to) {
    selectLane(laneIdx);
    openLaneEvent(colIdx);
    if (from !== undefined) {
      els['ev-from'].value = String(from);
      els['ev-from'].fire('change', {});
    }
    if (to !== undefined) {
      els['ev-to'].value = String(to);
      els['ev-to'].fire('change', {});
    }
  }

  function setAllAlpha(v) {
    const n = Number(els['f-lanecount'].value) || 1;
    for (let i = 0; i < n; i++) setLaneParam(i, 2, v, v);
  }

  /* ============ 阶段 A：放置 / 吸附 / 拖动 / 撤销 ============ */

  reset();
  ok(noteTotal() === 0, '新建后 0 个音符');
  ok(statusLen().includes('00:00.000'), '新建后时长归零，实际 ' + statusLen());

  // 透明度默认 0 = 完全隐藏，这里先把 4 条轨道点亮才能验绘制
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'moveTo').length === 0, '透明度 0 时预渲染里什么都不画');

  setAllAlpha(100);
  frame(1);

  // 点在 0.97s：150BPM、吸附 1/4 拍（0.1s 网格）→ 应该落到 1.000s
  ptr('pointerdown', LANE0, xAt(0.97));
  ptr('pointerup', LANE0, xAt(0.97));
  ok(noteTotal() === 1, '左键点一下 = 一个 tap，实际 ' + noteTotal());
  ok(countOf('tap') === 1, '类型是 tap');
  ok(statusLen().includes('00:01.000'), '0.97s 被吸附到 1.000s，实际 ' + statusLen());
  ok(els['btn-undo'].disabled === false, '出现了可撤销的步');

  /* ---- 绘制坐标核对：判号线 == judgeY，音符画在 time→y 算出来的位置 ---- */
  canvasCtx._calls.length = 0;
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(canvasCtx, 'moveTo', (c) => c[2] === 672.5).length > 0, '判号线画在 judgeY = 672');
  const tlNoteX = TL_NOTE_X0 + 6 + 5;      // 音符矩形左边缘 + 圆角
  const tlNoteY = xAt(1.0) - 6;            // 1.000s 位置减去半个音符高
  ok(callsOf(canvasCtx, 'moveTo', (c) => Math.abs(c[1] - tlNoteX) < 0.5 && Math.abs(c[2] - tlNoteY) < 0.5).length > 0,
    'tap 画在 lane0 / 1.000s 对应的位置（' + tlNoteX + ', ' + tlNoteY + '）');
  ok(callsOf(canvasCtx, 'fillText', (c) => c[1] === 'Lane 1').length > 0, '轨道名画出来了');
  ok(callsOf(canvasCtx, 'lineTo', (c) => c[2] > 0 && c[2] < 672 && c[1] > 208 && c[1] < 848).length > 0,
    '节拍网格线画出来了');

  /* ---- 预渲染窗口 4:3 ----
     400x225（16:9）、判定线 y=191、轨道宽 20、音符半宽 8.5、半厚 1.25
     X=0 就在舞台正中 cx=200；1.000s 的 tap 距判定线 127.5 */
  ok(previewEl.width === 800 && previewEl.height === 450, '预渲染窗口按 16:9 + dpr 开了 800x450 的后备缓冲');
  ok(callsOf(previewCtx, 'moveTo', (c) => c[2] === JUDGE).length > 0, '判定线段画在 85% 高度（255）');
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - noteX(0)) < 0.5 && Math.abs(c[2] - noteY(1)) < 0.5).length > 0,
    'X=0 的轨道在舞台正中，1.000s 的音符画在 (' + noteX(0) + ', ' + noteY(1) + ')');

  // 播放头往后走，音符要往判定线掉
  const beforeY = callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - noteX(0)) < 0.5);
  previewCtx._calls.length = 0;
  wheel(-100);   // 往后一拍
  frame(1);
  const afterY = callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - noteX(0)) < 0.5);
  ok(beforeY.length > 0 && afterY.length > 0, '预渲染里音符还在画');
  ok(afterY[0][2] > beforeY[0][2], '往后走之后音符往下掉了（' + beforeY[0][2] + ' → ' + afterY[0][2] + '）');

  wheel(100);    // 滚回 0
  frame(1);
  ok(statusTime() === '00:00.000', '滚回开头，实际 ' + statusTime());

  // 拖动改时间
  ptr('pointerdown', LANE0, xAt(1.0));
  ptr('pointermove', LANE0, xAt(2.0));
  ptr('pointerup', LANE0, xAt(2.0));
  ok(statusLen().includes('00:02.000'), '拖动后变成 2.000s，实际 ' + statusLen());

  // 撤销 / 重做
  key('z', { ctrlKey: true });
  ok(statusLen().includes('00:01.000'), '撤销回到 1.000s，实际 ' + statusLen());
  key('z', { ctrlKey: true, shiftKey: true });
  ok(statusLen().includes('00:02.000'), '重做回到 2.000s，实际 ' + statusLen());
  key('z', { ctrlKey: true });
  ok(statusLen().includes('00:01.000'), '再撤销一次，实际 ' + statusLen());

  // 拖到别的轨道，再在那个轨道上右键删掉（验证轨道横坐标换算）
  ptr('pointerdown', LANE0, xAt(1.0));
  ptr('pointermove', LANE2, xAt(1.0));
  ptr('pointerup', LANE2, xAt(1.0));
  ok(noteTotal() === 1, '换轨后音符还在');
  ptr('pointerdown', LANE0, xAt(1.0), 2);
  ok(noteTotal() === 1, '在原轨道右键没删掉（说明确实换过去了）');
  ptr('pointerdown', LANE2, xAt(1.0), 2);
  ok(noteTotal() === 0, '在新轨道右键删掉了它');

  /* ============ 阶段 B：hold 画 / 拉长 / 双击换类型 ============ */

  reset();
  ptr('pointerdown', LANE1, xAt(1.0), 2);
  ptr('pointermove', LANE1, xAt(1.8));
  ptr('pointerup', LANE1, xAt(1.8));
  ok(noteTotal() === 1, '右键空白上下拖画出一个 hold，实际 ' + noteTotal());
  ok(countOf('hold') === 1, '类型是 hold，实际 ' + statusNotes());
  ok(statusLen().includes('00:01.800'), 'hold 尾巴在 1.800s，实际 ' + statusLen());

  // 拖尾端（顶端）拉长到 2.0s
  ptr('pointerdown', LANE1, xAt(1.8));
  ptr('pointermove', LANE1, xAt(2.0));
  ptr('pointerup', LANE1, xAt(2.0));
  ok(noteTotal() === 1, '拖尾端没多出音符');
  ok(statusLen().includes('00:02.000'), '尾端拉到 2.000s，实际 ' + statusLen());

  // 双击 hold → tap（flick / mine 都删掉了，只剩 tap ↔ hold）
  ptr('pointerdown', LANE1, xAt(1.0));
  ptr('pointerup', LANE1, xAt(1.0));
  canvasEl.fire('dblclick', { clientX: LANE1, clientY: xAt(1.0), button: 0 });
  ok(noteTotal() === 1, '双击没多出音符，实际 ' + noteTotal());
  ok(countOf('tap') === 1, '双击把 hold 切成 tap，实际 ' + statusNotes());
  ok(statusLen().includes('00:01.000'), '切成 tap 后长度归零，实际 ' + statusLen());
  ok(statusNotes().indexOf('flick') < 0 && statusNotes().indexOf('mine') < 0, '状态栏里不再有 flick / mine');

  // 再双击一次绕回 hold
  canvasEl.fire('dblclick', { clientX: LANE1, clientY: xAt(1.0), button: 0 });
  ok(countOf('hold') === 1, '再双击回到 hold，实际 ' + statusNotes());

  /* ============ 阶段 C：键盘 ============ */

  reset();
  ptr('pointerdown', LANE0, xAt(1.0));
  ptr('pointerup', LANE0, xAt(1.0));
  key('ArrowRight', {});
  key('ArrowRight', {});
  ptr('pointerdown', LANE0, xAt(1.0), 2);
  ok(noteTotal() === 1, '→→ 之后原轨道右键没删掉（确实挪走了）');
  ptr('pointerdown', LANE2, xAt(1.0), 2);
  ok(noteTotal() === 0, '→→ 两次后落在 lane2，右键删除成功');

  ptr('pointerdown', LANE1, xAt(0.5));
  ptr('pointerup', LANE1, xAt(0.5));
  ok(noteTotal() === 1, '重新放一个，实际 ' + noteTotal());
  key('Delete', {});
  ok(noteTotal() === 0, 'Del 删掉选中的音符，实际 ' + noteTotal());

  key(' ', {});
  frame(3);
  ok(els['btn-play'].textContent.includes('暂停'), '空格开始播放');
  key(' ', {});
  ok(els['btn-play'].textContent.includes('播放'), '再按空格暂停');

  key('z', { ctrlKey: true });
  ok(noteTotal() === 1, '撤销把删掉的音符找回来了，实际 ' + noteTotal());

  /* ============ 阶段 D：滚轮 / 缩放 / 侧栏 ============ */

  reset();
  const t0 = statusTime();
  canvasEl.fire('wheel', { deltaY: -100, ctrlKey: false, shiftKey: false, preventDefault() {} });
  ok(statusTime() !== t0, '滚轮翻了播放头：' + t0 + ' → ' + statusTime());
  ok(statusTime() === '00:00.400', '滚轮向上 = 往后走一拍（150BPM = 0.4s），实际 ' + statusTime());
  canvasEl.fire('wheel', { deltaY: 100, ctrlKey: false, shiftKey: false, preventDefault() {} });
  ok(statusTime() === '00:00.000', '滚轮向下 = 往回走一拍，且不会跑成负数，实际 ' + statusTime());

  canvasEl.fire('wheel', { deltaY: -100, ctrlKey: true, shiftKey: false, preventDefault() {} });
  ok(Number(els['f-highway'].value) !== 2, 'Ctrl+滚轮改了可视秒数，实际 ' + els['f-highway'].value);

  // 轨道数 6
  els['f-lanecount'].value = '6';
  els['f-lanecount'].fire('change', {});
  ok(Number(els['f-lanecount'].value) === 6, '轨道数改成 6，实际 ' + els['f-lanecount'].value);
  frame(1);

  // 放一个音符再改 BPM：音符时间必须不动
  ptr('pointerdown', LANE0, xAt(1.0));
  ptr('pointerup', LANE0, xAt(1.0));
  const lenBefore = statusLen();
  els['f-bpm'].value = '90';
  els['f-bpm'].fire('change', {});
  ok(statusLen() === lenBefore, '改 BPM 没挪动已有音符（' + lenBefore + ' → ' + statusLen() + '）');
  ok(els['st-bpm'].textContent.includes('90'), '状态栏 BPM 跟着变，实际 ' + els['st-bpm'].textContent);

  // 侧栏文本改曲名
  els['f-title'].value = '测试曲目';
  els['f-title'].fire('input', {});
  els['f-title'].fire('change', {});
  ok(els['file-name'].textContent.indexOf('●') >= 0, '改曲名后标记未保存');

  // 曲绘画师一栏
  ok(els['f-illustrator'] !== undefined, '侧栏有曲绘画师输入框');
  els['f-illustrator'].value = 'Yuki';
  els['f-illustrator'].fire('input', {});
  els['f-illustrator'].fire('change', {});
  ok(els['file-name'].textContent.indexOf('●') >= 0, '改曲绘画师后也标记未保存');

  // 校验按钮
  els['btn-validate'].fire('click', {});
  ok(els['st-hint'].textContent.indexOf('✓') >= 0 || els['st-hint'].textContent.indexOf('⚠') >= 0,
    '校验按钮给出结果：' + els['st-hint'].textContent);

  /* ============ 阶段 E：判定区（现在只能靠 zone 事件改） ============ */

  const fills = () => previewCtx._calls
    .filter((c) => c[0] === 'fillRect' || c[0] === 'fill')
    .map((c) => (c[0] === 'fillRect' ? c[5] : c[1]))
    .filter((s) => typeof s === 'string');
  const hasColor = (sub) => fills().some((s) => s.indexOf(sub) >= 0);

  reset();
  setAllAlpha(100);
  previewCtx._calls.length = 0;
  frame(1);
  ok(hasColor('255,255,255'), '四条轨道默认都画成白色');
  ok(!hasColor('176,107,255') && !hasColor('255,209,102'), '默认没有紫/黄');

  // 第 2 轨：在判定区那一列画一条 0~0.5s 的事件，值改成 1 = 左
  selectLane(1);
  ptr('pointerdown', eventColCenter(6), xAt(0));
  ptr('pointermove', eventColCenter(6), xAt(0.5));
  ptr('pointerup', eventColCenter(6), xAt(0.5));
  ok(els['ev-prop'].textContent.indexOf('判定区') >= 0, '拖出来的是判定区事件：' + els['ev-prop'].textContent);
  els['ev-from'].value = '1';
  els['ev-from'].fire('change', {});
  els['ev-to'].value = '1';
  els['ev-to'].fire('change', {});
  previewCtx._calls.length = 0;
  frame(1);
  ok(hasColor('176,107,255'), '第 2 轨变成紫色 #b06bff');
  ok(hasColor('255,255,255'), '其它轨道还是白的');

  // 另一条轨道设成 2 = 右（黄）
  selectLane(2);
  ptr('pointerdown', eventColCenter(6), xAt(0));
  ptr('pointermove', eventColCenter(6), xAt(0.5));
  ptr('pointerup', eventColCenter(6), xAt(0.5));
  els['ev-from'].value = '2';
  els['ev-from'].fire('change', {});
  els['ev-to'].value = '2';
  els['ev-to'].fire('change', {});
  previewCtx._calls.length = 0;
  frame(1);
  ok(hasColor('255,209,102'), '第 3 轨变成黄色 #ffd166');
  ok(hasColor('176,107,255'), '第 2 轨还紫着（各自独立）');

  // 撤销把黄色那条退回去（from 和 to 是两次操作，撤两次）
  key('z', { ctrlKey: true });
  key('z', { ctrlKey: true });
  previewCtx._calls.length = 0;
  frame(1);
  ok(!hasColor('255,209,102'), '撤销后黄色消失');

  // 轨道数改成 6，第 2 轨的紫色还在
  els['f-lanecount'].value = '6';
  els['f-lanecount'].fire('change', {});
  previewCtx._calls.length = 0;
  frame(1);
  ok(hasColor('176,107,255'), '改轨道数后紫色还在');

  /* ============ 阶段 F：轨道参数（坐标 / 透明度 / 流速 / 长度 / 旋转） ============ */

  reset();
  els['f-lanecount'].value = '4';
  els['f-lanecount'].fire('change', {});
  frame(1);

  // 新轨道在起点自带 6 条默认事件（侧栏那套输入框已经被它替代）
  openLaneEvent(0);
  ok(els['ev-prop'].textContent.indexOf('X') >= 0, 'X 列 0~0.5s 有默认事件：' + els['ev-prop'].textContent);
  ok(Number(els['ev-from'].value) === 0 && Number(els['ev-to'].value) === 0, 'X 默认事件头尾都是 0');
  openLaneEvent(4);
  ok(Number(els['ev-from'].value) === 10, '流速默认事件头值是 10，实际 ' + els['ev-from'].value);
  openLaneEvent(5);
  ok(Number(els['ev-from'].value) === 10, '长度默认事件头值是 10');

  // 点亮 track（alpha 100 = 完全不透明），否则预渲染里什么都看不到
  setAllAlpha(100);
  frame(1);

  // X=0 = 舞台正中：所有轨道都落在 cx=200，左右边线只有 CX±HALF 两个 x
  previewCtx._calls.length = 0;
  frame(1);
  const allX = callsOf(previewCtx, 'moveTo').map((c) => c[1]);
  ok(allX.length > 0 && allX.every((x) => Math.abs(x - (CX - HALF)) < 0.5 || Math.abs(x - (CX + HALF)) < 0.5),
    '4 条轨道默认全部重合在舞台正中（画出来的 x 只有 ' + (CX - HALF) + ' / ' + (CX + HALF) + '）');

  // 选中第 2 轨（lane1），把它的 X 事件改成 60，再放一个 1.000s 的 tap
  setLaneParam(1, 0, 60, 60);
  ptr('pointerdown', LANE1, xAt(1.0));
  ptr('pointerup', LANE1, xAt(1.0));
  ok(noteTotal() === 1, '第 2 轨上放了一个音符');

  // X = 100 → 基点从 CX+60 移到 CX+100
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - noteX(60)) < 0.6 && Math.abs(c[2] - noteY(1)) < 0.6).length > 0,
    'X=60 时音符在 (' + noteX(60) + ', ' + noteY(1) + ')');
  setLaneParam(1, 0, 100, 100);
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - noteX(100)) < 0.6 && Math.abs(c[2] - noteY(1)) < 0.6).length > 0,
    'X=100 时音符右移到 (' + noteX(100) + ', ' + noteY(1) + ')');

  // Y = 20 → 向上为正，所以整条轨道（连同音符）上移 20
  setLaneParam(1, 1, 20, 20);
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - noteX(100)) < 0.6 && Math.abs(c[2] - (noteY(1) - 20)) < 0.6).length > 0,
    'Y=20 之后整条轨道（连同音符）上移 20');
  setLaneParam(1, 1, -20, -20);
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - noteX(100)) < 0.6 && Math.abs(c[2] - (noteY(1) + 20)) < 0.6).length > 0,
    'Y=-20 之后向下移 20');
  setLaneParam(1, 1, 0, 0);
  setLaneParam(1, 0, 60, 60);

  // 旋转 90° → 轨道横过来，音符跑到右边
  const rotX = CX + 60 + PPS - NTH;
  const rotY = JUDGE - NHALF;
  setLaneParam(1, 3, 90, 90);
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - rotX) < 0.6 && Math.abs(c[2] - rotY) < 0.6).length > 0,
    '旋转 90° 之后音符跑到右侧 (' + rotX + ', ' + rotY + ')');
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - noteX(60)) < 0.5 && Math.abs(c[2] - noteY(1)) < 0.5).length === 0,
    '横过来之后原来那个竖直位置不再画音符');
  setLaneParam(1, 3, 0, 0);

  // 流速 15 = 2.25×（平方曲线）→ 1.000s 的音符跑得更快
  setLaneParam(1, 4, 15, 15);
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - noteX(60)) < 0.6 && Math.abs(c[2] - noteY(2.25)) < 0.6).length > 0,
    '流速 15（2.25×）之后音符从 y=' + noteY(1) + ' 冲到 y=' + noteY(2.25).toFixed(1));

  // 流速 100 = 100× → 1 秒后的音符早飞出去了，不画
  setLaneParam(1, 4, 100, 100);
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - noteX(60)) < 0.6).length === 0,
    '流速 100（100×）时 1 秒后的音符已经飞出视野');

  // 流速 0 = 停住：音符一直钉在判定线上（看得见才打得到）
  setLaneParam(1, 4, 0, 0);
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - noteX(60)) < 0.6 && Math.abs(c[2] - noteY(0)) < 0.6).length > 0,
    '流速 0 时音符停在判定线上');

  setLaneParam(1, 4, 10, 10);

  // 长度：10 = 标准全长（判定线到画面顶），20 = 两倍，0 = 只剩判定线
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'lineTo', (c) => Math.abs(c[2]) < 0.6).length > 0,
    '默认长度 10 → 轨道地面画到画面顶 y = 0');

  setLaneParam(1, 5, 20, 20);
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'lineTo', (c) => Math.abs(c[2] + JUDGE) < 0.6).length > 0,
    '长度 20 → 地面画到 y = ' + (-JUDGE) + '（两倍长）');

  for (let i = 0; i < 4; i++) setLaneParam(i, 5, 0, 0);
  previewCtx._calls.length = 0;
  frame(1);
  const ysZero = callsOf(previewCtx, 'moveTo').map((c) => c[2]);
  ok(ysZero.length > 0 && ysZero.every((y) => y >= JUDGE - 1),
    '长度 0 时所有轨道只剩判定线一条（没有东西画在判定线上方）');

  for (let i = 0; i < 4; i++) setLaneParam(i, 5, 10, 10);
  selectLane(1);

  // 透明度 0（完全隐藏）→ 只藏轨道本体 / 判定线，音符照画
  setLaneParam(1, 2, 0, 0);
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - (CX + 60 + HALF)) < 0.5).length === 0,
    '透明度 0 之后这条轨道的本体 / 判定线不再绘制');
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - noteX(60)) < 0.6 && Math.abs(c[2] - noteY(1)) < 0.6).length > 0,
    '透明度 0 不影响音符，note 还画在 (' + noteX(60) + ', ' + noteY(1) + ')');
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - (CX - HALF)) < 0.5).length > 0,
    '其它轨道照常画');

  // 撤销能退回透明度（撤销后面板里的头尾值回到 100）
  key('z', { ctrlKey: true });
  frame(1);
  ok(Number(els['ev-to'].value) === 100, '撤销把透明度事件退回 100，实际 ' + els['ev-to'].value);

  // 越界值被夹住
  els['ev-to'].value = '500';
  els['ev-to'].fire('change', {});
  ok(Number(els['ev-to'].value) === 100, '透明度超过 100 被夹到 100，实际 ' + els['ev-to'].value);

  openLaneEvent(0);
  els['ev-from'].value = 'abc';
  els['ev-from'].fire('change', {});
  ok(Number(els['ev-from'].value) === 0, '乱填 X 退回默认 0，实际 ' + els['ev-from'].value);


  /* ============ 阶段 G：音符密度条 ============ */

  reset();
  frame(1);
  ok(callsOf(canvasCtx, 'fillText', (c) => c[1] === '空').length > 0, '空谱面时密度条显示「空」');

  // 三个音符，最后一个在 2.0s → 谱面时长 2.0
  ptr('pointerdown', LANE0, xAt(1.0));
  ptr('pointerup', LANE0, xAt(1.0));
  ptr('pointerdown', LANE1, xAt(1.5));
  ptr('pointerup', LANE1, xAt(1.5));
  ptr('pointerdown', LANE2, xAt(2.0));
  ptr('pointerup', LANE2, xAt(2.0));
  ok(noteTotal() === 3, '放了 3 个音符，实际 ' + noteTotal());
  ok(statusLen().includes('00:02.000'), '谱面时长 2.000s，实际 ' + statusLen());

  frame(1);
  const miniBars = callsOf(canvasCtx, 'fillRect', (c) => c[1] >= 62 && c[1] <= 118 && c[4] > 0 && c[4] <= 3);
  ok(miniBars.length >= 3, '3 个音符在密度条里各自画出一根柱子（实际 ' + miniBars.length + ' 根）');

  // 密度条几何：gutter 56 + pad 10 → 窄带在 x = 66..118，高度到判定线 672
  const MINI_X = 56 + 10 + 26;   // 窄带中心 92
  ok(callsOf(canvasCtx, 'strokeRect', (c) => Math.abs(c[1] - 66.5) < 0.6).length > 0, '密度条画在 x=66');

  // 点中间 → 整首的 50% → 1.000s
  ptr('pointerdown', MINI_X, 336);
  ptr('pointerup', MINI_X, 336);
  ok(statusTime() === '00:01.000', '点密度条中间跳到 1.000s，实际 ' + statusTime());

  // 点靠上（y=67.2）→ 90% → 1.800s
  ptr('pointerdown', MINI_X, 672 * 0.1);
  ptr('pointerup', MINI_X, 672 * 0.1);
  ok(statusTime() === '00:01.800', '点靠上跳到 1.800s，实际 ' + statusTime());

  // 点最底（判定线处）→ 0
  ptr('pointerdown', MINI_X, 672);
  ptr('pointerup', MINI_X, 672);
  ok(statusTime() === '00:00.000', '点最底回到开头，实际 ' + statusTime());

  // 同一个 y、但 x 不在窄带里 → 不跳转（落在轨道区就是放音符）
  ptr('pointerdown', LANE2, 336);
  ptr('pointerup', LANE2, 336);
  ok(noteTotal() === 4, '窄带右边点一下是正常放音符，不是跳转，实际 ' + noteTotal());

  // 载入音频后，密度条按整首歌的长度算（尾部跟歌曲尾部重合）
  els['file-audio'].fire('change', {
    target: {
      files: [{
        name: 'song.mp3',
        arrayBuffer: () => Promise.resolve(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]).buffer)
      }],
      value: ''
    }
  });
  const chartAudios = () => audioInstances.filter((a) => a.src === 'blob:stub');
  ok(chartAudios().length === 1, '音频对象建出来了');
  ok(els['audio-name'].textContent === 'song.mp3', '音频文件名显示出来了');
  chartAudios().slice(-1)[0].duration = 4;
  frame(1);

  ptr('pointerdown', MINI_X, 336);        // 50% 处
  ptr('pointerup', MINI_X, 336);
  ok(statusTime() === '00:02.000', '歌曲 4 秒 → 密度条中点 = 2.000s（不再按谱面时长 2.0 算）');

  ptr('pointerdown', MINI_X, 100);        // 85% 处
  ptr('pointerup', MINI_X, 100);
  ok(statusTime() === '00:03.400', '靠近顶部 = 接近歌曲尾部（3.400s）');

  /* ============ 阶段 H：事件区（6 条参数通道 + 轨道切换按钮） ============ */

  reset();
  frame(1);

  // 轨道 1 点亮，放一个 2.0s 的音符给密度条一个时长
  setLaneParam(0, 2, 100, 100);



  ptr('pointerdown', LANE0, xAt(2.0));
  ptr('pointerup', LANE0, xAt(2.0));
  ok(noteTotal() === 1, '放了 1 个音符，实际 ' + noteTotal());

  const EVX = eventColCenter(0);
  const EVY = eventColCenter(1);
  ok(Math.abs(EVX - (TL_EVENT_X0 + EV_COL_W / 2)) < 0.5, 'X 通道在事件区第 1 列（x=' + EVX.toFixed(1) + '）');

  // 在 X 通道拖一个 1.0 → 1.5 的事件
  ptr('pointerdown', EVX, xAt(1.0));
  ptr('pointermove', EVX, xAt(1.5));
  ptr('pointerup', EVX, xAt(1.5));
  ok(noteTotal() === 1, '事件区拖拽没有误放音符，实际 ' + noteTotal());
  ok(els['ev-title'].textContent.indexOf('00:01.000') >= 0 &&
     els['ev-title'].textContent.indexOf('00:01.500') >= 0,
    '事件起止时间对：' + els['ev-title'].textContent);
  ok(els['ev-prop'].textContent.indexOf('X') >= 0, '面板属性显示 X：' + els['ev-prop'].textContent);
  ok(Number(els['ev-from'].value) === 0 && Number(els['ev-to'].value) === 0,
    '事件头尾默认等于当前参数（都是 0）');

  // 把尾值改成 100
  els['ev-to'].value = '100';
  els['ev-to'].fire('change', {});

  // 播放头在 0（事件还没开始）→ 轨道在原位
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - (CX - HALF)) < 0.5 && Math.abs(c[2] - JUDGE) < 0.5).length > 0,
    '事件开始前轨道还在原位 x=' + (CX - HALF));

  // 播放头跳到 1.5（事件结尾）→ 轨道已经移到 x=100
  ptr('pointerdown', MINI_X, 420);   // 音频 4 秒，spanspan = 4s
  ptr('pointerup', MINI_X, 420);
  ok(statusTime() === '00:01.500', '跳到 1.500s，实际 ' + statusTime());
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - (CX + 100 - HALF)) < 0.5 && Math.abs(c[2] - JUDGE) < 0.5).length > 0,
    '事件结尾轨道右移到 x=' + (CX + 100 - HALF));

  // 换成 step 缓动 → 中途还停在起点
  els['ev-ease'].value = 'step';
  els['ev-ease'].fire('change', {});
  ptr('pointerdown', MINI_X, 470.4);   // 1.20s
  ptr('pointerup', MINI_X, 470.4);
  ok(statusTime() === '00:01.200', '跳到 1.200s，实际 ' + statusTime());
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[1] - (CX - HALF)) < 0.5 && Math.abs(c[2] - JUDGE) < 0.5).length > 0,
    'step 缓动中途轨道还停在起点');

  // 回到开头，在 Y 通道再画一个，确认通道互相独立
  ptr('pointerdown', MINI_X, 672);
  ptr('pointerup', MINI_X, 672);
  ptr('pointerdown', EVY, xAt(1.0));
  ptr('pointermove', EVY, xAt(1.6));
  ptr('pointerup', EVY, xAt(1.6));
  ok(els['ev-prop'].textContent.indexOf('Y') >= 0, '换到 Y 通道后面板跟着变：' + els['ev-prop'].textContent);
  ok(els['ev-title'].textContent.indexOf('00:01.000') >= 0 &&
     els['ev-title'].textContent.indexOf('00:01.600') >= 0,
    'Y 事件有自己的起止：' + els['ev-title'].textContent);

  // 点一下 X 通道那个事件，选回它再右键删掉
  ptr('pointerdown', EVX, 250);
  ptr('pointerup', EVX, 250);
  ok(els['ev-prop'].textContent.indexOf('X') >= 0, '点一下切回 X 通道的事件');
  ptr('pointerdown', EVX, 250, 2);
  ok(els['ev-title'].textContent.indexOf('拖一下') >= 0,
    '右键删掉事件后面板清空：' + els['ev-title'].textContent);
  ok(noteTotal() === 1, '删事件没弄坏音符');

  // 底部轨道切换按钮：点第 3 轨，事件区跟着切
  selectLane(0);
  openLaneEvent(0);
  ok(els['ev-prop'].textContent.indexOf('轨道 1') >= 0, '先在轨道 1：' + els['ev-prop'].textContent);
  ptr('pointerdown', laneBtnCenter(2), laneBtnY);
  ptr('pointerup', laneBtnCenter(2), laneBtnY);
  openLaneEvent(0);
  ok(els['ev-prop'].textContent.indexOf('轨道 3') >= 0,
    '点事件区的轨道按钮切到第 3 轨，实际 ' + els['ev-prop'].textContent);

  /* ============ 阶段 I：打击音 ============ */

  reset();
  frame(1);

  const hitAudios = () => audioInstances.filter((a) => a.src === 'audio/hit.wav');
  const hitPlays = () => hitAudios().reduce((s, a) => s + a.plays, 0);
  ok(hitAudios().length >= 4, '打击音预加载了一组实例，实际 ' + hitAudios().length);

  // 放一个 1.0s 的音符（放音符本身会响一声）
  const beforePlace = hitPlays();
  ptr('pointerdown', LANE0, xAt(1.0));
  ptr('pointerup', LANE0, xAt(1.0));
  ok(hitPlays() === beforePlace + 1, '放一个音符就响一声，实际 +' + (hitPlays() - beforePlace));

  // 播放，让播放头跨过这个音符 → 再响一声
  const beforePass = hitPlays();
  key(' ', {});
  ok(els['btn-play'].textContent.includes('暂停'), '开始播放');
  chartAudios().slice(-1)[0].currentTime = 0.9;
  frame(1);
  chartAudios().slice(-1)[0].currentTime = 1.05;
  frame(1);
  key(' ', {});
  ok(hitPlays() === beforePass + 1, '音符过判定线响了一声，实际 +' + (hitPlays() - beforePass));

  // 关掉打击音之后不再响
  els['chk-hit'].checked = false;
  els['chk-hit'].fire('change', {});
  const beforeMute = hitPlays();
  ptr('pointerdown', LANE1, xAt(0.5));
  ptr('pointerup', LANE1, xAt(0.5));
  ok(hitPlays() === beforeMute, '关掉打击音后放音符不响了');
  els['chk-hit'].checked = true;
  els['chk-hit'].fire('change', {});
  const beforeOn = hitPlays();
  ptr('pointerdown', LANE1, xAt(2.0));
  ptr('pointerup', LANE1, xAt(2.0));
  ok(hitPlays() === beforeOn + 1, '再打开又开始响了');

  /* ============ 阶段 J：曲绘 + zip 导出 ============ */

  const fakeCover = {
    name: 'cover.png',
    arrayBuffer: () => Promise.resolve(new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]).buffer)
  };
  els['file-cover'].fire('change', { target: { files: [fakeCover], value: '' } });
  ok(els['cover-name'].textContent === 'cover.png', '曲绘文件名显示出来了：' + els['cover-name'].textContent);
  ok(els['cover-img'].hidden === false, '曲绘缩略图显示了');
  ok(els['cover-img'].src === 'blob:stub', '缩略图用的是 object URL');

  const blobBefore = blobCalls.length;
  els['btn-save'].fire('click', {});
  await new Promise((res) => setTimeout(res, 10));

  ok(blobCalls.length === blobBefore + 1, '导出产出了一个 Blob');
  const zip = blobCalls[blobCalls.length - 1];
  ok(zip.type === 'application/zip', 'Blob 类型是 application/zip，实际 ' + zip.type);

  const bytes = zip.parts[0];
  // 跨 vm 上下文 instanceof 不通用，这里只看形状
  ok(bytes && bytes.byteLength > 0 && typeof bytes[0] === 'number', 'Blob 里是字节数组');
  const n = bytes.length;
  const sig = (bytes[n - 22] | (bytes[n - 21] << 8) | (bytes[n - 20] << 16) | (bytes[n - 19] << 24)) >>> 0;
  ok(sig === 0x06054b50, 'zip 末尾是 EOCD 签名');
  const entryCount = bytes[n - 12] | (bytes[n - 11] << 8);
  ok(entryCount === 3, 'zip 里有 3 个文件，实际 ' + entryCount);

  const text = Buffer.from(bytes).toString('latin1');
  ok(text.indexOf('chart.json') >= 0, 'zip 里有 chart.json');
  ok(text.indexOf('song.mp3') >= 0, 'zip 里有音频');
  ok(text.indexOf('cover.png') >= 0, 'zip 里有曲绘');
  ok(text.indexOf('"cover": "cover.png"') >= 0 || text.indexOf('cover.png"') >= 0, 'json 里记了曲绘文件名');

  /* ============ 阶段 K：Shift 框选 ============ */

  reset();
  frame(1);

  ptr('pointerdown', LANE0, xAt(1.0)); ptr('pointerup', LANE0, xAt(1.0));   // 1.0s
  ptr('pointerdown', LANE1, xAt(2.0)); ptr('pointerup', LANE1, xAt(2.0));   // 2.0s
  ptr('pointerdown', LANE2, xAt(1.5)); ptr('pointerup', LANE2, xAt(1.5));   // 1.5s
  ok(noteTotal() === 3, '放了 3 个音符，实际 ' + noteTotal());
  ok(statusLen().includes('00:02.000'), '谱面时长 2.000s，实际 ' + statusLen());

  // 按住 Shift 从 lane0 拖到 lane1，纵向盖住 0.9~2.0s
  const boxX0 = TL_NOTE_X0 + 12;
  const boxX1 = TL_NOTE_X0 + TL_LANE_W + 12;
  ptr('pointerdown', boxX0, 370, 0, { shiftKey: true });
  ptr('pointermove', boxX1, 0, 0, { shiftKey: true });

  canvasCtx._calls.length = 0;
  frame(1);
  ok(callsOf(canvasCtx, 'strokeRect', (c) => Math.abs(c[1] - (boxX0 + 0.5)) < 1).length > 0,
    '拖的时候画出了框选矩形');

  ptr('pointerup', boxX1, 0, 0, { shiftKey: true });
  ok(noteTotal() === 3, '框选没有误加音符，实际 ' + noteTotal());
  ok(els['st-hint'].textContent.indexOf('框选了 2 个音符') >= 0,
    '框住了 2 个音符（1.0s 和 2.0s）：' + els['st-hint'].textContent);

  // 拖其中一个 → 两个一起走（往后 0.5s），谱面时长从 2.000 变 2.500
  ptr('pointerdown', LANE0, xAt(1.0));
  ptr('pointermove', LANE0, xAt(1.5));
  ptr('pointerup', LANE0, xAt(1.5));
  ok(statusLen().includes('00:02.500'), '整组往后挪了 0.5s，时长变成 ' + statusLen());

  // Del 把整组删掉
  key('Delete', {});
  ok(noteTotal() === 1, 'Del 一次删掉整组，剩 ' + noteTotal() + ' 个');
  ok(statusLen().includes('00:01.500'), '剩下的那个还在 1.500s，实际 ' + statusLen());

  // Shift 点一下空白（几乎没拖动）= 清空选择，之后 Del 只删刚点的那个
  ptr('pointerdown', LANE0, xAt(1.0), 0, { shiftKey: true });
  ptr('pointerup', LANE0, xAt(1.0), 0, { shiftKey: true });
  ptr('pointerdown', LANE0, xAt(1.5));   // 又放了一个（原来的在 lane2）
  ptr('pointerup', LANE0, xAt(1.5));
  ok(noteTotal() === 2, '又放了一个，实际 ' + noteTotal());
  key('Delete', {});
  ok(noteTotal() === 1, '只删掉刚点的那个，原来那个还在，实际 ' + noteTotal());

  /* ============ 阶段 L：缓动曲线可视化 ============ */

  reset();
  frame(1);

  // 点亮轨道 + 一个 2.0s 的音符（给密度条时长），然后在 X 通道画事件
  setLaneParam(0, 2, 100, 100);



  ptr('pointerdown', LANE0, xAt(2.0));
  ptr('pointerup', LANE0, xAt(2.0));
  ptr('pointerdown', eventColCenter(0), xAt(1.0));
  ptr('pointermove', eventColCenter(0), xAt(1.5));
  ptr('pointerup', eventColCenter(0), xAt(1.5));

  ok(easeEl.width === 400 && easeEl.height === 132, '曲线画布按 dpr 开了 400x132，实际 ' + easeEl.width + 'x' + easeEl.height);

  // 200x66、padding 8 → 绘图区 x 8..192、y 8..58；k=0.5 处 x = 100
  const E_X0 = 8, E_Y0 = 8, E_W = 184, E_H = 50;

  easeCtx._calls.length = 0;
  els['ev-ease'].value = 'linear';
  els['ev-ease'].fire('change', {});
  ok(callsOf(easeCtx, 'lineTo', (c) => Math.abs(c[1] - (E_X0 + E_W / 2)) < 1 && Math.abs(c[2] - (E_Y0 + E_H / 2)) < 1).length > 0,
    'linear 曲线在 k=0.5 处正好是中点');

  easeCtx._calls.length = 0;
  els['ev-ease'].value = 'step';
  els['ev-ease'].fire('change', {});
  ok(callsOf(easeCtx, 'lineTo', (c) => Math.abs(c[1] - (E_X0 + E_W / 2)) < 1 && Math.abs(c[2] - (E_Y0 + E_H)) < 1).length > 0,
    'step 曲线在 k=0.5 处还趴在底部');
  ok(callsOf(easeCtx, 'lineTo', (c) => Math.abs(c[1] - (E_X0 + E_W / 2)) < 1 && Math.abs(c[2] - (E_Y0 + E_H / 2)) < 1).length === 0,
    'step 曲线不再经过中点——形状真的换了');

  // 播放头进到事件里 → 曲线上多一个进度点
  // 注意：阶段 G 载入的音频还在，span = 4s，所以 y = 672*(1-t/4)
  easeCtx._calls.length = 0;
  ptr('pointerdown', MINI_X, 462);
  ptr('pointerup', MINI_X, 462);
  ok(statusTime() === '00:01.300', '播放头落在事件区间里（1.300s），实际 ' + statusTime());
  els['ev-ease'].value = 'inOutQuad';
  els['ev-ease'].fire('change', {});
  ok(callsOf(easeCtx, 'arc').length > 0, '播放头在事件内时画出了进度点');

  /* ============ 阶段 M：拖事件头尾直接改参数值 ============ */

  reset();
  frame(1);
  selectLane(0);
  openLaneEvent(2);   // 透明度列，默认事件 from=to=0
  ok(Number(els['ev-from'].value) === 0 && Number(els['ev-to'].value) === 0,
    '默认透明度事件头尾都是 0');

  const evColW = TL_HALF / 8;
  const perPx = 100 / evColW;          // 透明度：一列宽 = 100
  const tailY = xAt(0.5);              // 事件尾巴在 0.5s
  const headY = xAt(0);                // 事件头在 0s

  // 拖尾巴往右 20px
  ptr('pointerdown', eventColCenter(2), tailY);
  ptr('pointermove', eventColCenter(2) + 20, tailY);
  ptr('pointerup', eventColCenter(2) + 20, tailY);
  const expectTo = Math.round(20 * perPx * 10) / 10;
  ok(Math.abs(Number(els['ev-to'].value) - expectTo) < 1.5,
    '拖尾巴横向 20px → 尾值 ' + els['ev-to'].value + '（期望约 ' + expectTo + '）');
  ok(Number(els['ev-from'].value) === 0, '拖尾巴没有动头值');

  // 拖头往右 15px → 头值也上去，头尾不再相等
  ptr('pointerdown', eventColCenter(2), headY);
  ptr('pointermove', eventColCenter(2) + 15, headY);
  ptr('pointerup', eventColCenter(2) + 15, headY);
  const expectFrom = Math.round(15 * perPx * 10) / 10;
  ok(Math.abs(Number(els['ev-from'].value) - expectFrom) < 1.5,
    '拖头横向 15px → 头值 ' + els['ev-from'].value + '（期望约 ' + expectFrom + '）');
  ok(Number(els['ev-from'].value) !== Number(els['ev-to'].value), '头尾现在不一样了');

  // 改完值预渲染照常出图
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'fillRect').length > 0, '改完值预渲染还在正常画');

  // 撤销能退回
  key('z', { ctrlKey: true });
  frame(1);
  ok(Number(els['ev-from'].value) === 0, '撤销把拖出来的头值退回 0，实际 ' + els['ev-from'].value);

  /* ============ 阶段 N：导出 zip，再打开回来 ============ */

  reset();
  frame(1);
  els['f-title'].value = 'ZIP 往返';
  els['f-title'].fire('input', {});
  els['f-title'].fire('change', {});
  els['f-illustrator'].value = '画师往返';
  els['f-illustrator'].fire('input', {});
  els['f-illustrator'].fire('change', {});
  ptr('pointerdown', LANE0, xAt(1.0));
  ptr('pointerup', LANE0, xAt(1.0));
  ptr('pointerdown', LANE1, xAt(2.0));
  ptr('pointerup', LANE1, xAt(2.0));
  ok(noteTotal() === 2, '导出前 2 个音符，实际 ' + noteTotal());

  const zipBefore = blobCalls.length;
  els['btn-save'].fire('click', {});
  await new Promise((res) => setTimeout(res, 10));
  ok(blobCalls.length === zipBefore + 1, '导出了 zip');
  const zipBytes = blobCalls[blobCalls.length - 1].parts[0];

  // 清空，再从刚导出的 zip 打开
  reset();
  frame(1);
  ok(noteTotal() === 0, '先清空到 0 个音符');

  els['file-chart'].fire('change', {
    target: {
      files: [{ name: 'roundtrip.zip', arrayBuffer: () => Promise.resolve(zipBytes.buffer) }],
      value: ''
    }
  });
  await new Promise((res) => setTimeout(res, 30));

  ok(noteTotal() === 2, '从 zip 打开后有 2 个音符，实际 ' + noteTotal());
  ok(els['f-title'].value === 'ZIP 往返', '曲名读回来了：' + els['f-title'].value);
  ok(els['audio-name'].textContent === 'song.mp3', '音频从 zip 里带回来了：' + els['audio-name'].textContent);
  ok(els['f-illustrator'].value === '画师往返', '曲绘画师也读回来了：' + els['f-illustrator'].value);
  ok(els['cover-name'].textContent === 'cover.png', '曲绘从 zip 里带回来了：' + els['cover-name'].textContent);
  ok(els['file-name'].textContent.indexOf('roundtrip.zip') >= 0,
    '文件名显示成 zip 的名字：' + els['file-name'].textContent);

  // 打开后还能再导出（音频/曲绘是内存里的虚拟文件）
  const againBefore = blobCalls.length;
  els['btn-save'].fire('click', {});
  await new Promise((res) => setTimeout(res, 10));
  ok(blobCalls.length === againBefore + 1, '从 zip 打开后还能再导出');
  const againBytes = blobCalls[blobCalls.length - 1].parts[0];
  const againText = Buffer.from(againBytes).toString('latin1');
  ok(againText.indexOf('chart.json') >= 0 && againText.indexOf('song.mp3') >= 0 &&
     againText.indexOf('cover.png') >= 0, '再导出的 zip 里三样东西都在');

  /* ============ 阶段 O：事件多选 / 复制粘贴 ============ */

  reset();
  frame(1);
  selectLane(0);

  // 默认事件铺在 0~0.5s；框住 X、Y 两列
  const evTop = xAt(0.5) - 6;
  const evBot = xAt(0) + 6;
  ptr('pointerdown', eventColCenter(0), evTop, 0, { shiftKey: true });
  ptr('pointermove', eventColCenter(1), evBot, 0, { shiftKey: true });
  ptr('pointerup', eventColCenter(1), evBot, 0, { shiftKey: true });

  ok(els['st-hint'].textContent.indexOf('框选了 2 个事件') >= 0,
    'Shift 拖框选到 2 个事件：' + els['st-hint'].textContent);
  ok(els['ev-prop'].textContent.indexOf('选中 2 个') >= 0,
    '面板显示选中数量：' + els['ev-prop'].textContent);

  // 复制
  key('c', { ctrlKey: true });
  ok(els['st-hint'].textContent.indexOf('复制了 2 个事件') >= 0,
    '复制成功：' + els['st-hint'].textContent);

  // 播放头挪到 2.000s，粘贴
  chartAudios().forEach((a) => { a.duration = 4; });
  ptr('pointerdown', MINI_X, 336);     // 密度条 50% 处 = 2.0s（span 4s）
  ptr('pointerup', MINI_X, 336);
  ok(statusTime() === '00:02.000', '播放头在 2.000s，实际 ' + statusTime());

  key('v', { ctrlKey: true });
  ok(els['st-hint'].textContent.indexOf('贴到了') >= 0, '粘贴成功：' + els['st-hint'].textContent);
  ok(els['ev-title'].textContent.indexOf('00:02.000') >= 0,
    '贴到播放头位置上：' + els['ev-title'].textContent);
  ok(els['ev-title'].textContent.indexOf('00:02.500') >= 0,
    '长度也一起搬过去了（0.5s）：' + els['ev-title'].textContent);
  ok(els['ev-prop'].textContent.indexOf('选中 2 个') >= 0, '贴完两个都是选中状态');

  // 画布上确实多了一组事件（viewTime 现在是 2.0，尾巴在 2.5s → y = 672 - 0.5*336）
  const pastedTailY = xAt(0.5);
  canvasCtx._calls.length = 0;
  frame(1);
  ok(callsOf(canvasCtx, 'arc', (c) => Math.abs(c[2] - pastedTailY) < 2).length > 0,
    '2.5s 处画出了粘贴事件的尾巴（y≈' + pastedTailY.toFixed(1) + '）');

  // Del 删掉粘贴出来的这一组
  key('Delete', {});
  ok(els['st-hint'].textContent.indexOf('删掉了 2 个事件') >= 0,
    'Del 批量删掉 2 个：' + els['st-hint'].textContent);
  ok(els['ev-prop'].textContent.indexOf('选中') < 0, '删完选择清空');

  // 回到 0，整组拖动：抓 0.3s 处拖到 0.8s = +0.5s
  ptr('pointerdown', MINI_X, 672);
  ptr('pointerup', MINI_X, 672);
  ok(statusTime() === '00:00.000', '播放头回到 0');

  ptr('pointerdown', eventColCenter(0), evTop, 0, { shiftKey: true });
  ptr('pointermove', eventColCenter(1), evBot, 0, { shiftKey: true });
  ptr('pointerup', eventColCenter(1), evBot, 0, { shiftKey: true });
  ok(els['st-hint'].textContent.indexOf('框选了 2 个事件') >= 0, '重新框住 2 个');

  ptr('pointerdown', eventColCenter(0), xAt(0.3));
  ptr('pointermove', eventColCenter(0), xAt(0.8));
  ptr('pointerup', eventColCenter(0), xAt(0.8));
  ok(els['ev-title'].textContent.indexOf('00:00.500') >= 0 &&
     els['ev-title'].textContent.indexOf('00:01.000') >= 0,
    '整组往后挪了 0.5s：' + els['ev-title'].textContent);

  // 两个一起挪了：在新时间上再框一次还是 2 个
  ptr('pointerdown', eventColCenter(0), xAt(1.0) - 6, 0, { shiftKey: true });
  ptr('pointermove', eventColCenter(1), xAt(0.5) + 6, 0, { shiftKey: true });
  ptr('pointerup', eventColCenter(1), xAt(0.5) + 6, 0, { shiftKey: true });
  ok(els['st-hint'].textContent.indexOf('框选了 2 个事件') >= 0,
    '两条都挪到 0.5~1.0s 了：' + els['st-hint'].textContent);
  ok(els['st-hint'].textContent.indexOf('框选了 0') < 0, '确实框到了东西');

  /* ============ 阶段 P：判定区（None/Left/Right）也能做成事件 ============ */

  reset();
  frame(1);
  selectLane(0);
  setLaneParam(0, 2, 100, 100);          // 点亮第 1 轨

  previewCtx._calls.length = 0;
  frame(1);
  ok(hasColor('255,255,255'), '默认全是白色');
  ok(!hasColor('176,107,255'), '还没改的时候不应该有紫色');

  // 在第 7 列（判定区）1.0 ~ 1.5s 拖一条事件出来
  ptr('pointerdown', eventColCenter(6), xAt(1.0));
  ptr('pointermove', eventColCenter(6), xAt(1.5));
  ptr('pointerup', eventColCenter(6), xAt(1.5));
  ok(els['ev-prop'].textContent.indexOf('判定区') >= 0,
    '拖出来的是判定区事件：' + els['ev-prop'].textContent);
  ok(Number(els['ev-from'].value) === 0 && Number(els['ev-to'].value) === 0,
    '新事件的起止值都等于当时的判定区（0 = 无）');

  // 头尾都改成 1 = 左 → 紫色
  els['ev-from'].value = '1';
  els['ev-from'].fire('change', {});
  els['ev-to'].value = '1';
  els['ev-to'].fire('change', {});

  // 跳到 1.2s（事件区间内）→ 这条轨道变紫
  ptr('pointerdown', MINI_X, 672 - (1.2 / 4) * 672);
  ptr('pointerup', MINI_X, 672 - (1.2 / 4) * 672);
  ok(statusTime().indexOf('00:01.') === 0, '播放头在 1.x 秒，实际 ' + statusTime());
  previewCtx._calls.length = 0;
  frame(1);
  ok(hasColor('176,107,255'), '判定区事件生效后轨道画成紫色 #b06bff');

  // 跳到 0.2s（事件之前）→ 还是白色
  ptr('pointerdown', MINI_X, 672 - (0.2 / 4) * 672);
  ptr('pointerup', MINI_X, 672 - (0.2 / 4) * 672);
  previewCtx._calls.length = 0;
  frame(1);
  ok(!hasColor('176,107,255'), '事件之前的时刻还是白色');

  // 改成 2 = 右 → 黄色（先回到 0，把那条 1.0~1.5s 的事件重新点开）
  ptr('pointerdown', MINI_X, 672);
  ptr('pointerup', MINI_X, 672);
  ok(statusTime() === '00:00.000', '播放头回到 0');
  ptr('pointerdown', eventColCenter(6), xAt(1.25));
  ptr('pointerup', eventColCenter(6), xAt(1.25));
  ok(els['ev-prop'].textContent.indexOf('判定区') >= 0, '点开了判定区事件');
  els['ev-from'].value = '2';
  els['ev-from'].fire('change', {});
  els['ev-to'].value = '2';
  els['ev-to'].fire('change', {});
  ptr('pointerdown', MINI_X, 672 - (1.2 / 4) * 672);
  ptr('pointerup', MINI_X, 672 - (1.2 / 4) * 672);
  previewCtx._calls.length = 0;
  frame(1);
  ok(hasColor('255,209,102'), '改成 2 之后变成黄色 #ffd166');

  // 值超出 0~2 会被夹住
  els['ev-to'].value = '9';
  els['ev-to'].fire('change', {});
  ok(Number(els['ev-to'].value) === 2, '判定区尾值超过 2 被夹到 2，实际 ' + els['ev-to'].value);
  els['ev-to'].value = '-5';
  els['ev-to'].fire('change', {});
  ok(Number(els['ev-to'].value) === 0, '判定区尾值小于 0 被夹到 0，实际 ' + els['ev-to'].value);

  /* ============ 阶段 Q：左边最多 6 条轨道 + DOM 滚动条 ============ */

  // 滚动条是 DOM 控件，先把元素拿全
  ['lane-scroll', 'ls-range', 'ls-left', 'ls-right', 'ls-info'].forEach((id) => documentStub.getElementById(id));

  reset();
  frame(1);
  els['f-lanecount'].value = '8';
  els['f-lanecount'].fire('change', {});

  const laneNames = () => canvasCtx._calls
    .filter((c) => c[0] === 'fillText' && String(c[1]).indexOf('Lane ') === 0)
    .map((c) => c[1]);

  canvasCtx._calls.length = 0;
  frame(1);
  const shown = laneNames();
  ok(shown.length === 6, '8 条轨道只画 6 条，实际 ' + shown.length);
  ok(shown[0] === 'Lane 1' && shown[5] === 'Lane 6', '画的是 Lane 1~6：' + shown.join(','));

  // 8 条 → 滚动条出现，滑轨范围 0~2
  ok(els['lane-scroll'].hidden === false, '超过 6 条时滚动条出现');
  ok(els['ls-range'].max === '2', '滑轨最大值 = 8-6 = 2，实际 ' + els['ls-range'].max);
  ok(els['ls-info'].textContent === '1–6 / 8', '范围提示：' + els['ls-info'].textContent);

  // 拖滑轨到最后
  els['ls-range'].value = '2';
  els['ls-range'].fire('input', {});
  canvasCtx._calls.length = 0;
  frame(1);
  const shown2 = laneNames();
  ok(shown2[0] === 'Lane 3' && shown2[5] === 'Lane 8',
    '滑到最右显示 Lane 3~8：' + shown2.join(','));
  ok(els['ls-info'].textContent === '3–8 / 8', '提示跟着变：' + els['ls-info'].textContent);

  // ◀ ▶ 按钮一格一格走
  els['ls-left'].fire('click', {});
  canvasCtx._calls.length = 0;
  frame(1);
  ok(laneNames()[0] === 'Lane 2', '点 ◀ 往回一条：' + laneNames().join(','));
  ok(els['ls-info'].textContent === '2–7 / 8', '提示：' + els['ls-info'].textContent);

  els['ls-right'].fire('click', {});
  canvasCtx._calls.length = 0;
  frame(1);
  ok(laneNames()[0] === 'Lane 3', '点 ▶ 往后一条：' + laneNames().join(','));

  // 到边界按钮变灰
  ok(els['ls-right'].disabled === true, '已经在最右，▶ 变灰');
  ok(els['ls-left'].disabled === false, '还能往左，◀ 可点');

  // 点事件区底部第 8 个按钮 → 左边自动滚到能看见它
  const bw8 = Math.max(18, Math.min(38, (TL_HALF - 8) / 8 - 4));
  const btotal8 = 8 * (bw8 + 4) - 4;
  const bx8 = TL_EVENT_X0 + (TL_HALF - btotal8) / 2;
  els['ls-range'].value = '0';
  els['ls-range'].fire('input', {});
  ptr('pointerdown', bx8 + 7 * (bw8 + 4) + bw8 / 2, laneBtnY);
  ptr('pointerup', bx8 + 7 * (bw8 + 4) + bw8 / 2, laneBtnY);
  canvasCtx._calls.length = 0;
  frame(1);
  const shown3 = laneNames();
  ok(shown3[5] === 'Lane 8', '点第 8 轨的按钮后自动滚过去：' + shown3.join(','));

  // 第 8 轨（全局序号 7）滚动后是第 6 个可见列，在那一列放个音符
  const SB_LANE_W = TL_HALF / 6;
  const lane7X = TL_NOTE_X0 + 5 * SB_LANE_W + SB_LANE_W / 2;
  ptr('pointerdown', lane7X, xAt(1.0));
  ptr('pointerup', lane7X, xAt(1.0));
  ok(noteTotal() === 1, '滚过去的轨道上能放音符，实际 ' + noteTotal());
  canvasCtx._calls.length = 0;
  frame(1);
  const noteX8 = TL_NOTE_X0 + 5 * SB_LANE_W + 6;
  ok(callsOf(canvasCtx, 'moveTo', (c) => Math.abs(c[1] - (noteX8 + 5)) < 1.5 && Math.abs(c[2] - (xAt(1.0) - 6)) < 2).length > 0,
    '音符落在第 8 轨那一列（x≈' + (noteX8 + 5) + '）');

  // 轨道数改回 4 → 滚动条消失
  els['f-lanecount'].value = '4';
  els['f-lanecount'].fire('change', {});
  canvasCtx._calls.length = 0;
  frame(1);
  ok(laneNames().length === 4, '4 条轨道时全显示');
  ok(els['lane-scroll'].hidden === true, '4 条轨道时滚动条隐藏');

  /* ============ 阶段 R：预览里长条随流速变长 ============ */

  reset();
  frame(1);
  selectLane(0);
  setLaneParam(0, 2, 100, 100);          // 点亮第 1 轨

  // 右键上下拖画一个 hold：0.1s 起，长 0.2s
  ptr('pointerdown', LANE0, xAt(0.1), 2);
  ptr('pointermove', LANE0, xAt(0.3), 2);
  ptr('pointerup', LANE0, xAt(0.3), 2);
  ok(noteTotal() === 1 && countOf('hold') === 1, '画了一个长条，实际 ' + statusNotes());

  // 流速 10 = 1.00× → 预览里长条长度 = 0.2 * PPS * 1
  const yOf = (d) => JUDGE - d;
  const y10Top = yOf(0.3 * PPS * 1);
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'lineTo', (c) => Math.abs(c[2] - y10Top) < 1.5).length > 0,
    '流速 10 时长条顶到 y≈' + y10Top.toFixed(1));

  // 时间轴不受影响：流速 20 时 hold 的高度还是按时间算的 0.2*336 = 67.2px，不是 4 倍
  setLaneParam(0, 4, 20, 20);
  canvasCtx._calls.length = 0;
  frame(1);
  const holdH = 0.2 * 336;
  ok(callsOf(canvasCtx, 'fillRect', (c) => Math.abs(c[2] - xAt(0.3)) < 3 && Math.abs(c[4] - holdH) < 2).length > 0,
    '时间轴里的长条高度仍按时间算（' + holdH.toFixed(1) + 'px），没被流速放大');

  // 流速 20 = 4.00× → 预览里长条拉成 4 倍
  previewCtx._calls.length = 0;
  frame(1);
  const y20Top = yOf(0.3 * PPS * 4);
  ok(callsOf(previewCtx, 'lineTo', (c) => Math.abs(c[2] - y20Top) < 2).length > 0,
    '流速 20（4×）后长条顶到 y≈' + y20Top.toFixed(1) + '（原来是 ' + y10Top.toFixed(1) + '）');

  // 流速 0：长条回退到上一个非零流速，不会缩成一条线。
  // 前提是这条长条「已经到线」—— 流速 0 时未来长条的 head 恒为 0，
  // 所以先把播放头推到 0.6s（长条是 0.1~0.3s，已经过线）再验。
  setLaneParam(0, 4, 0, 0);
  chartAudios().forEach((a) => { a.duration = 4; });
  ptr('pointerdown', MINI_X, 672 - (0.6 / 4) * 672);
  ptr('pointerup', MINI_X, 672 - (0.6 / 4) * 672);
  ok(statusTime() === '00:00.600', '播放头在 0.600s，实际 ' + statusTime());
  previewCtx._calls.length = 0;
  frame(1);
  const bodyTop = callsOf(previewCtx, 'lineTo', (c) => c[2] < JUDGE - 3).length;
  ok(bodyTop > 0, '流速 0 且长条已经过线时长条依然有高度（没缩没）');


  /* ============ 阶段 S：音符也能复制粘贴 ============ */

  reset();
  frame(1);

  ptr('pointerdown', LANE0, xAt(1.0)); ptr('pointerup', LANE0, xAt(1.0));
  ptr('pointerdown', LANE1, xAt(2.0)); ptr('pointerup', LANE1, xAt(2.0));
  ok(noteTotal() === 2, '先放 2 个音符，实际 ' + noteTotal());

  // Shift 在音符区框选这两个
  ptr('pointerdown', LANE0 - 40, xAt(2.1), 0, { shiftKey: true });
  ptr('pointermove', LANE1 + 40, xAt(0.9), 0, { shiftKey: true });
  ptr('pointerup', LANE1 + 40, xAt(0.9), 0, { shiftKey: true });
  ok(els['st-hint'].textContent.indexOf('框选了 2 个音符') >= 0,
    '框住 2 个音符：' + els['st-hint'].textContent);

  key('c', { ctrlKey: true });
  ok(els['st-hint'].textContent.indexOf('复制了 2 个音符') >= 0,
    '复制音符：' + els['st-hint'].textContent);

  // 播放头跳到 3.0s（span 4s → y=168），贴上去
  chartAudios().forEach((a) => { a.duration = 4; });
  ptr('pointerdown', MINI_X, 168);
  ptr('pointerup', MINI_X, 168);
  ok(statusTime() === '00:03.000', '播放头在 3.000s，实际 ' + statusTime());

  key('v', { ctrlKey: true });
  ok(noteTotal() === 4, '粘贴后 4 个音符，实际 ' + noteTotal());
  ok(statusLen().includes('00:04.000'), '贴出来的最晚一个在 4.000s（3.0 + 相对 1.0），实际 ' + statusLen());
  ok(els['st-hint'].textContent.indexOf('把 2 个音符贴到了 00:03.000') >= 0,
    '提示对：' + els['st-hint'].textContent);

  // 贴完是选中状态，Del 能整批删掉
  key('Delete', {});
  ok(noteTotal() === 2, 'Del 删掉刚贴的 2 个，剩 ' + noteTotal());
  ok(statusLen().includes('00:02.000'), '原来的还在（2.000s），实际 ' + statusLen());

  // 回到 0 秒，切到事件区之后 Ctrl+C 复制的是事件、不是音符
  ptr('pointerdown', MINI_X, 672);
  ptr('pointerup', MINI_X, 672);
  selectLane(0);
  openLaneEvent(0);
  ok(els['ev-prop'].textContent.indexOf('X') >= 0, '点开了 X 列的事件');
  key('c', { ctrlKey: true });
  ok(els['st-hint'].textContent.indexOf('个事件') >= 0,
    '在事件区按 Ctrl+C 复制的是事件：' + els['st-hint'].textContent);
  // ---- 长条头过线、尾还没过：身体要继续画，不能整条消失 ----
  reset();
  frame(1);
  selectLane(0);
  setLaneParam(0, 2, 100, 100);

  ptr('pointerdown', LANE0, xAt(1.0), 2);
  ptr('pointermove', LANE0, xAt(1.8), 2);
  ptr('pointerup', LANE0, xAt(1.8), 2);
  ok(countOf('hold') === 1, '画了一个 1.0~1.8s 的长条');

  // 播放头推到 1.5s：头已经过线 0.5 秒（-47.75px，超过 40px 的剔除阈值）
  chartAudios().forEach((a) => { a.duration = 4; });
  ptr('pointerdown', MINI_X, 672 - (1.5 / 4) * 672);
  ptr('pointerup', MINI_X, 672 - (1.5 / 4) * 672);
  ok(statusTime() === '00:01.500', '播放头在 1.500s，实际 ' + statusTime());

  previewCtx._calls.length = 0;
  frame(1);
  const tailY2 = yOf(0.3 * PPS);            // 尾巴还剩 0.3 秒 → 28.65px
  ok(callsOf(previewCtx, 'lineTo', (c) => Math.abs(c[2] - tailY2) < 2).length > 0 ||
     callsOf(previewCtx, 'moveTo', (c) => Math.abs(c[2] - tailY2) < 2).length > 0,
    '头过线后长条身体还在（顶到 y≈' + tailY2.toFixed(1) + '）');
  ok(callsOf(previewCtx, 'lineTo', (c) => c[2] > JUDGE + 20).length === 0,
    '过线的头不再画到判定线下面');
  // ---- 过线的音符不再往下沉：停在判定线上淡出 ----
  reset();
  frame(1);
  selectLane(0);
  setLaneParam(0, 2, 100, 100);

  ptr('pointerdown', LANE0, xAt(1.2));
  ptr('pointerup', LANE0, xAt(1.2));
  ok(noteTotal() === 1 && countOf('tap') === 1, '在 1.2s 放了一个 tap');

  // 移到正好落在判定线上的位置（1.2s = 音符时刻）→ 还在画
  chartAudios().forEach((a) => { a.duration = 4; });
  ptr('pointerdown', MINI_X, 672 - (1.2 / 4) * 672);
  ptr('pointerup', MINI_X, 672 - (1.2 / 4) * 672);
  ok(statusTime() === '00:01.200', '播放头在 1.200s，实际 ' + statusTime());
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'fill', (c) => String(c[1]).indexOf('rgba(255,255,255,0.92)') >= 0).length > 0,
    '正好落到判定线上时 tap 还在');

  // 再往后 0.1s → 直接消失，不做缓动
  ptr('pointerdown', MINI_X, 672 - (1.3 / 4) * 672);
  ptr('pointerup', MINI_X, 672 - (1.3 / 4) * 672);
  ok(statusTime() === '00:01.300', '播放头在 1.300s，实际 ' + statusTime());

  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'lineTo', (c) => c[2] > JUDGE + 6).length === 0,
    '过线的 tap 没有沉到判定线下面');
  ok(callsOf(previewCtx, 'fill', (c) => String(c[1]).indexOf('rgba(255,255,255,0.92)') >= 0).length === 0,
    '过线的 tap 直接消失，没有缓动残留');

  // 长条头过线也一样停在线上
  reset();
  frame(1);
  selectLane(0);
  setLaneParam(0, 2, 100, 100);
  ptr('pointerdown', LANE0, xAt(1.0), 2);
  ptr('pointermove', LANE0, xAt(1.8), 2);
  ptr('pointerup', LANE0, xAt(1.8), 2);
  chartAudios().forEach((a) => { a.duration = 4; });
  ptr('pointerdown', MINI_X, 672 - (1.5 / 4) * 672);
  ptr('pointerup', MINI_X, 672 - (1.5 / 4) * 672);
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'lineTo', (c) => c[2] > JUDGE + 6).length === 0,
    '长条的头也没有沉到判定线下面');
  /* ============ 阶段 T：音乐 / 打击音音量 ============ */

  reset();
  frame(1);
  ['vol-music', 'vol-hit', 'vol-music-txt', 'vol-hit-txt'].forEach((id) => documentStub.getElementById(id));

  const hitGainAvg = () => {
    const list = hitAudios();
    if (!list.length) return -1;
    return list.reduce((s, a) => s + a.volume, 0) / list.length;
  };

  ok(els['vol-music'].value === '100', '音乐音量默认 100%，实际 ' + els['vol-music'].value);
  ok(els['vol-hit'].value === '71', '打击音默认 71%（-3dB，和原来 0.7 的响度一致），实际 ' + els['vol-hit'].value);

  // 拖到 50% → 存成 -6dB，音频元素音量同步
  els['vol-music'].value = '50';
  els['vol-music'].fire('input', {});
  ok(els['vol-music-txt'].textContent === '50%', '滑条旁边显示 50%');
  const liveAudio = chartAudios().slice(-1)[0];
  ok(Math.abs(liveAudio.volume - 0.5) < 0.02, '音频元素音量也跟着变成 0.5，实际 ' + liveAudio.volume);

  // 存进谱面的是 dB
  els['btn-save'].fire('click', {});
  await new Promise((res) => setTimeout(res, 10));
  const zipB = blobCalls[blobCalls.length - 1].parts[0];
  const txtB = Buffer.from(zipB).toString('latin1');
  ok(txtB.indexOf('"volume_db": -6') >= 0, '谱面里存的是 -6 dB');

  // 打击音拖到 0 → 静音
  els['vol-hit'].value = '0';
  els['vol-hit'].fire('input', {});
  ok(els['vol-hit-txt'].textContent === '0%', '打击音显示 0%');
  ok(chartAudios().filter((a) => a.src && a.src.indexOf('hit') >= 0).every((a) => a.volume === 0) ||
     hitPoolProbe() === 0, '打击音被静音');

  // 拉回 100%
  els['vol-hit'].value = '100';
  els['vol-hit'].fire('input', {});
  ok(Math.abs(hitGainAvg() - 1) < 0.02, '打击音拉回 100% → gain 1.0，实际 ' + hitGainAvg());
  /* ============ 阶段 U：播放倍速（慢放） ============ */

  reset();
  frame(1);
  documentStub.getElementById('f-rate');

  const curAudio = chartAudios().slice(-1)[0] || audioInstances[audioInstances.length - 1];
  ok(els['f-rate'].value === '1', '默认 1.00×，实际 ' + els['f-rate'].value);

  // 切到 0.5×
  els['f-rate'].value = '0.5';
  els['f-rate'].fire('change', {});
  ok(Math.abs(curAudio.playbackRate - 0.5) < 1e-6, '音频 playbackRate 变成 0.5，实际 ' + curAudio.playbackRate);
  ok(els['st-hint'].textContent.indexOf('0.5') >= 0, '状态栏提示倍速：' + els['st-hint'].textContent);

  // 慢放时播放：谱面时间来自 audio.currentTime，所以不会跑偏
  els['btn-play'].fire('click', {});
  ok(els['btn-play'].textContent.indexOf('暂停') >= 0, '开始播放');
  chartAudios().forEach((a) => { a.currentTime = 2.0; a.readyState = 4; });
  frame(6);   // 状态栏有 90ms 节流，多走几帧
  ok(Math.abs(Number(statusTime().split(':')[1]) - 2) < 0.05,
    '慢放时播放头跟着音频走（2.000s），实际 ' + statusTime());
  key(' ', {});
  ok(els['btn-play'].textContent.indexOf('播放') >= 0, '空格能暂停');

  // 切回 1×
  els['f-rate'].value = '1';
  els['f-rate'].fire('change', {});
  ok(Math.abs(curAudio.playbackRate - 1) < 1e-6, '切回 1.00×');

  // 倍速不进谱面
  const beforeZip = blobCalls.length;
  els['btn-save'].fire('click', {});
  await new Promise((res) => setTimeout(res, 10));
  const zt = Buffer.from(blobCalls[blobCalls.length - 1].parts[0]).toString('latin1');
  ok(zt.indexOf('playRate') < 0 && zt.indexOf('playbackRate') < 0, '倍速只是编辑器的，不会写进谱面');
  /* ============ 阶段 V：改流速后长条要能正常消失 ============ */

  reset();
  frame(1);
  selectLane(0);
  setLaneParam(0, 2, 100, 100);          // 点亮

  // 流速拉到 100（100×）—— 起点那条默认事件
  setLaneParam(0, 4, 100, 100);

  // 再在 1.6~1.7s 放一条 100 → 15 的流速事件（之后流速变慢）
  ptr('pointerdown', eventColCenter(4), xAt(1.6));
  ptr('pointermove', eventColCenter(4), xAt(1.7));
  ptr('pointerup', eventColCenter(4), xAt(1.7));
  els['ev-from'].value = '100';
  els['ev-from'].fire('change', {});
  els['ev-to'].value = '15';
  els['ev-to'].fire('change', {});

  // 在 1.0s 画一个 0.4 秒的长条（1.0 ~ 1.4）
  ptr('pointerdown', LANE0, xAt(1.0), 2);
  ptr('pointermove', LANE0, xAt(1.4), 2);
  ptr('pointerup', LANE0, xAt(1.4), 2);
  ok(countOf('hold') === 1, '画了一个 1.0~1.4s 的长条，实际 ' + statusNotes());

  // 100× 下每秒 9550px，只有接近音符时刻才看得见：推到 1.0s 确认它在画
  chartAudios().forEach((a) => { a.duration = 4; });
  ptr('pointerdown', MINI_X, 672 - (1.0 / 4) * 672);
  ptr('pointerup', MINI_X, 672 - (1.0 / 4) * 672);
  ok(statusTime() === '00:01.000', '播放头在 1.000s，实际 ' + statusTime());
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'fill', (c) => String(c[1]).indexOf('rgba(255,255,255,0.3)') >= 0).length > 0,
    '高速时长条身体画出来了');

  // 播放头推到 1.8s：头早就过线，流速也已经降到 15 倍率 2.25
  chartAudios().forEach((a) => { a.duration = 4; });
  ptr('pointerdown', MINI_X, 672 - (1.8 / 4) * 672);
  ptr('pointerup', MINI_X, 672 - (1.8 / 4) * 672);
  ok(statusTime() === '00:01.800', '播放头在 1.800s，实际 ' + statusTime());

  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'fill', (c) => String(c[1]).indexOf('rgba(255,255,255,0.3)') >= 0).length === 0,
    '流速变慢后长条正常消失，没有卡在判定线上');
  /* ============ 阶段 V2：流速 0 时还没到线的长条不许凭空长出身体 ============ */

  reset();
  frame(1);
  selectLane(0);
  setLaneParam(0, 2, 100, 100);          // 点亮
  setLaneParam(0, 4, 0, 0);              // 起点流速事件 0 → 0，全程停住

  // 1.0s 画一个 0.4 秒的长条（1.0 ~ 1.4）
  ptr('pointerdown', LANE0, xAt(1.0), 2);
  ptr('pointermove', LANE0, xAt(1.4), 2);
  ptr('pointerup', LANE0, xAt(1.4), 2);
  ok(countOf('hold') === 1, '画了一个 1.0~1.4s 的长条，实际 ' + statusNotes());

  const bodyFills = () => callsOf(previewCtx, 'fill', (c) => String(c[1]).indexOf('rgba(255,255,255,0.3)') >= 0);
  const headFills = () => callsOf(previewCtx, 'fill', (c) => String(c[1]).indexOf('rgba(255,255,255,0.92)') >= 0);

  // 播放头 0.2s：长条时刻还没到。0 速下头一直钉在判定线上（看得见才打得到），
  // 但不能凭空长出身体。
  chartAudios().forEach((a) => { a.duration = 4; });
  ptr('pointerdown', MINI_X, 672 - (0.2 / 4) * 672);
  ptr('pointerup', MINI_X, 672 - (0.2 / 4) * 672);
  ok(statusTime() === '00:00.200', '播放头在 0.200s，实际 ' + statusTime());
  previewCtx._calls.length = 0;
  frame(1);
  ok(headFills().length > 0, '流速 0 时音符头照旧钉在判定线上（没提前消失）');
  ok(bodyFills().length === 0, '流速 0 且长条还没到线时，预览里不画它的身体');

  // 播放头 1.2s：长条已经到线 / 过线 —— 身体照旧留着，不会缩没
  chartAudios().forEach((a) => { a.duration = 4; });
  ptr('pointerdown', MINI_X, 672 - (1.2 / 4) * 672);
  ptr('pointerup', MINI_X, 672 - (1.2 / 4) * 672);
  ok(statusTime() === '00:01.200', '播放头在 1.200s，实际 ' + statusTime());
  previewCtx._calls.length = 0;
  frame(1);
  ok(bodyFills().length > 0, '流速 0 但长条已经到线时，身体照旧画出来（没缩没）');
  /* ============ 阶段 W：可视秒数与预览流速解耦 ============ */

  reset();
  frame(1);
  selectLane(0);
  setLaneParam(0, 2, 100, 100);

  // 1.0s 放一个 tap；预览秒数默认 2s → 音符离判定线 1.0 * PPS
  ptr('pointerdown', LANE0, xAt(1.0));
  ptr('pointerup', LANE0, xAt(1.0));
  const atPv = (sec) => JUDGE - (1.0 * (JUDGE / sec));
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'lineTo', (c) => Math.abs(c[2] - atPv(2)) < 3).length > 0,
    '预览秒数 2s 时音符在 y≈' + atPv(2).toFixed(1));

  // 把「可视秒数」改成 8（时间轴缩放）—— 预览完全不动
  els['f-highway'].value = '8';
  els['f-highway'].fire('change', {});
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'lineTo', (c) => Math.abs(c[2] - atPv(2)) < 3).length > 0,
    '改可视秒数后预览里音符位置没变（还是 y≈' + atPv(2).toFixed(1) + '）');

  // 改「预览秒数」到 4 —— 只会让预览里的音符下移一半
  els['f-pvsec'].value = '4';
  els['f-pvsec'].fire('change', {});
  previewCtx._calls.length = 0;
  frame(1);
  ok(callsOf(previewCtx, 'lineTo', (c) => Math.abs(c[2] - atPv(4)) < 3).length > 0,
    '预览秒数 4s 时音符移到 y≈' + atPv(4).toFixed(1));
  ok(callsOf(previewCtx, 'lineTo', (c) => Math.abs(c[2] - atPv(2)) < 1.5).length === 0,
    '原来 2s 的位置上已经没有音符了');

  // 改回去
  els['f-pvsec'].value = '2';
  els['f-pvsec'].fire('change', {});
  els['f-highway'].value = '2';
  els['f-highway'].fire('change', {});
  /* ============ 阶段 X：预渲染里给轨道标编号 ============ */

  reset();
  frame(1);

  // 四条轨道错开一点，方便核对编号位置
  for (let i = 0; i < 4; i++) setLaneParam(i, 2, 100, 100);
  setLaneParam(0, 0, -60, -60);
  setLaneParam(1, 0, -20, -20);
  setLaneParam(2, 0, 20, 20);
  setLaneParam(3, 0, 60, 60);

  previewCtx._calls.length = 0;
  frame(1);
  const numAt = (i) => callsOf(previewCtx, 'fillText', (c) => c[1] === String(i + 1));
  const labels = callsOf(previewCtx, 'fillText').map((c) => c[1]);
  ok(labels[0] === '1' && labels[1] === '2' && labels[2] === '3' && labels[3] === '4',
    '四条轨道按顺序标了 1 2 3 4：' + labels.join(','));

  // 编号贴在判定线外面一点：y = JUDGE + 11，x = 轨道中心
  const X0 = CX - 60, X1 = CX + 60;
  const NUM_OFF = 11;
  ok(Math.abs(numAt(0)[0][2] - X0) < 1, '1 号在轨道 1 的中心 x=' + X0 + '，实际 ' + numAt(0)[0][2]);
  ok(Math.abs(numAt(3)[0][2] - X1) < 1, '4 号在轨道 4 的中心 x=' + X1 + '，实际 ' + numAt(3)[0][2]);
  ok(Math.abs(numAt(0)[0][3] - (JUDGE + NUM_OFF)) < 1,
    '编号在判定线下方 11px（y=' + (JUDGE + NUM_OFF) + '），实际 ' + numAt(0)[0][3]);

  // 轨道旋转时编号跟着转
  setLaneParam(0, 3, 90, 90);
  previewCtx._calls.length = 0;
  frame(1);
  const rot = numAt(0)[0];
  // 转 90° 后轨道朝右，编号在判定线外侧 = 往左退 11px
  ok(Math.abs(rot[2] - (X0 - NUM_OFF)) < 1 && Math.abs(rot[3] - JUDGE) < 1,
    '轨道转 90° 后编号跟着转到 (' + (X0 - NUM_OFF) + ', ' + JUDGE + ')，实际 (' + rot[2].toFixed(1) + ', ' + rot[3].toFixed(1) + ')');

  // 轨道全透明时编号仍然在（方便定位）
  setLaneParam(0, 3, 0, 0);
  setLaneParam(0, 2, 0, 0);
  previewCtx._calls.length = 0;
  frame(1);
  ok(numAt(0).length > 0, '透明度 0 的轨道也还标着编号');
  /* ============ 阶段 Y：轨道增删按钮 ============ */

  reset();
  frame(1);
  documentStub.getElementById('btn-lane-add');
  documentStub.getElementById('btn-lane-del');
  ok(String(els['f-lanecount'].value) === '4', '新建是 4 条轨道，实际 ' + els['f-lanecount'].value);

  // ＋ 加一条
  els['btn-lane-add'].fire('click', {});
  ok(String(els['f-lanecount'].value) === '5', '点 ＋ 变成 5 条，实际 ' + els['f-lanecount'].value);
  ok(els['st-hint'].textContent.indexOf('5') >= 0, '提示新的轨道数：' + els['st-hint'].textContent);

  // － 删一条
  els['btn-lane-del'].fire('click', {});
  ok(String(els['f-lanecount'].value) === '4', '点 － 回到 4 条，实际 ' + els['f-lanecount'].value);

  // 连点到只剩 1 条就停
  for (let i = 0; i < 6; i++) els['btn-lane-del'].fire('click', {});
  ok(String(els['f-lanecount'].value) === '1', '删到 1 条就不动了，实际 ' + els['f-lanecount'].value);
  ok(els['st-hint'].textContent.indexOf('至少要留一条') >= 0, '提示至少一条：' + els['st-hint'].textContent);

  // 输入框直接改也还能用
  els['f-lanecount'].value = '9';
  els['f-lanecount'].fire('change', {});
  ok(String(els['f-lanecount'].value) === '9', '输入框改成 9 条，实际 ' + els['f-lanecount'].value);

  // 撤销能退回
  key('z', { ctrlKey: true });
  ok(String(els['f-lanecount'].value) === '1', '撤销退回改之前（1 条），实际 ' + els['f-lanecount'].value);

  // 新加的轨道自带默认事件（判定区那列不铺）
  els['f-lanecount'].value = '6';
  els['f-lanecount'].fire('change', {});
  canvasCtx._calls.length = 0;
  frame(1);
  const shown6 = canvasCtx._calls.filter((c) => c[0] === 'fillText' && String(c[1]).indexOf('Lane ') === 0).map((c) => c[1]);
  ok(shown6.length === 6, '6 条轨道全画出来，实际 ' + shown6.length);
  /* ============ 阶段 Z：父线 / 子线（父线也是一条事件通道） ============ */

  reset();
  els['f-lanecount'].value = '4';        // 底部轨道按钮宽度按 4 轨算，selectLane 才对得准
  els['f-lanecount'].fire('change', {});
  frame(1);

  for (let i = 0; i < 4; i++) setLaneParam(i, 2, 100, 100);
  setLaneParam(1, 0, 60, 60);       // 轨道 2 放到 x=60

  const numOf = (i) => callsOf(previewCtx, 'fillText', (c) => c[1] === String(i + 1))[0];
  previewCtx._calls.length = 0;
  frame(1);
  ok(Math.abs(numOf(0)[2] - CX) < 1, '轨道 1 单独时编号在 x=' + CX + '，实际 ' + numOf(0)[2]);

  // 父线默认事件是 0（= 无父线）
  selectLane(0);
  openLaneEvent(7);
  ok(els['ev-prop'].textContent.indexOf('父线') >= 0, '第 8 列是父线通道：' + els['ev-prop'].textContent);
  ok(Number(els['ev-from'].value) === 0, '默认父线值 0 = 不挂');

  // 把父线设成 2 = 挂在第 2 条轨道上（值 = 序号 + 1）
  els['ev-from'].value = '2';
  els['ev-from'].fire('change', {});
  els['ev-to'].value = '2';
  els['ev-to'].fire('change', {});
  previewCtx._calls.length = 0;
  frame(1);
  ok(Math.abs(numOf(0)[2] - (CX + 60)) < 1,
    '子线基准点跟着父线到 x=' + (CX + 60) + '，实际 ' + numOf(0)[2]);

  // 子线自己再偏 10 / 20（相对父线坐标系）
  setLaneParam(0, 0, 10, 10);       // x 沿父线横向
  setLaneParam(0, 1, 20, 20);       // y 沿父线自身方向（向上）
  previewCtx._calls.length = 0;
  frame(1);
  ok(Math.abs(numOf(0)[2] - (CX + 70)) < 1,
    'x=10 沿父线横向偏移 → 编号 x=' + (CX + 70) + '，实际 ' + numOf(0)[2]);
  ok(Math.abs(numOf(0)[3] - (JUDGE - 20 + 11)) < 1,
    'y=20 沿父线方向抬起 → 编号 y=' + (JUDGE - 9) + '，实际 ' + numOf(0)[3]);

  // 父线转 90°，子线跟着转（旋转叠加）
  setLaneParam(1, 3, 90, 90);
  previewCtx._calls.length = 0;
  frame(1);
  ok(Math.abs(numOf(0)[2] - (CX + 60 + 20 - 11)) < 1.5 &&
     Math.abs(numOf(0)[3] - (JUDGE + 10)) < 1.5,
    '父线转 90° 后子线跟着转，编号到 (' + (CX + 69) + ', ' + (JUDGE + 10) + ')，实际 (' +
    numOf(0)[2].toFixed(1) + ', ' + numOf(0)[3].toFixed(1) + ')');

  // 把父线事件设回 0 = 取消跟随
  selectLane(0);
  openLaneEvent(7);
  els['ev-from'].value = '0';
  els['ev-from'].fire('change', {});
  els['ev-to'].value = '0';
  els['ev-to'].fire('change', {});
  previewCtx._calls.length = 0;
  frame(1);
  ok(Math.abs(numOf(0)[2] - (CX + 10)) < 1,
    '父线设回 0 后回到自己的绝对坐标 x=' + (CX + 10) + '，实际 ' + numOf(0)[2]);

  // 父线可以随时间切换：0.5s 之后才挂上去
  selectLane(0);
  ptr('pointerdown', eventColCenter(7), xAt(0.6));
  ptr('pointermove', eventColCenter(7), xAt(0.8));
  ptr('pointerup', eventColCenter(7), xAt(0.8));
  els['ev-from'].value = '2';
  els['ev-from'].fire('change', {});
  els['ev-to'].value = '2';
  els['ev-to'].fire('change', {});
  chartAudios().forEach((a) => { a.duration = 4; });
  ptr('pointerdown', MINI_X, 672 - (0.7 / 4) * 672);   // 0.7s：在父线事件里
  ptr('pointerup', MINI_X, 672 - (0.7 / 4) * 672);
  previewCtx._calls.length = 0;
  frame(1);
  ok(Math.abs(numOf(0)[2] - (CX + 60 + 10)) < 1.5,
    '0.7s 时父线生效，编号在 x≈' + (CX + 70) + '，实际 ' + numOf(0)[2].toFixed(1));

  ptr('pointerdown', MINI_X, 672);                      // 回到 0s：还没挂
  ptr('pointerup', MINI_X, 672);
  previewCtx._calls.length = 0;
  frame(1);
  ok(Math.abs(numOf(0)[2] - (CX + 10)) < 1.5,
    '0s 时父线还没生效，编号在 x≈' + (CX + 10) + '，实际 ' + numOf(0)[2].toFixed(1));

  /* ============ 阶段 AA：重叠音符的标记与定位 ============ */

  reset();
  frame(1);
  documentStub.getElementById('btn-dup');
  documentStub.getElementById('st-dup');

  // 先放一个音符，复制后原地粘贴 → 造出一组重叠
  ptr('pointerdown', LANE0, xAt(1.0));
  ptr('pointerup', LANE0, xAt(1.0));
  ok(noteTotal() === 1, '放了 1 个音符');

  ptr('pointerdown', LANE0 - 40, xAt(1.1), 0, { shiftKey: true });
  ptr('pointermove', LANE0 + 40, xAt(0.9), 0, { shiftKey: true });
  ptr('pointerup', LANE0 + 40, xAt(0.9), 0, { shiftKey: true });
  key('c', { ctrlKey: true });

  // 播放头挪到 1.0s 再粘贴 → 正好叠在原音符上
  chartAudios().forEach((a) => { a.duration = 4; });
  ptr('pointerdown', MINI_X, 672 - (1.0 / 4) * 672);
  ptr('pointerup', MINI_X, 672 - (1.0 / 4) * 672);
  ok(statusTime() === '00:01.000', '播放头到 1.000s，实际 ' + statusTime());
  key('v', { ctrlKey: true });
  ok(noteTotal() === 2, '粘贴后 2 个音符，实际 ' + noteTotal());

  // 状态栏报出重叠组数
  frame(1);
  ok(els['st-dup'].textContent.indexOf('重叠 1 组') >= 0,
    '状态栏标出重叠：' + els['st-dup'].textContent);

  // 画面上有粉色的虚线框
  canvasCtx._calls.length = 0;
  frame(1);
  ok(callsOf(canvasCtx, 'setLineDash', (c) => Array.isArray(c[1]) && c[1][0] === 3).length > 0,
    '重叠处画了虚线框');
  const NOTE_H = 12;   // 时间轴里音符厚度
  // 播放头现在就在 1.0s，音符画在判定线上 → 框的 y = 672 - 10
  ok(callsOf(canvasCtx, 'strokeRect', (c) => Math.abs(c[2] - (672 - NOTE_H / 2 - 4)) < 2 &&
     Math.abs(c[1] - (TL_NOTE_X0 + 1.5)) < 2).length > 0,
    '框正好套在那一格音符上（x=' + (TL_NOTE_X0 + 1.5) + ', y=' + (672 - 10) + '）');

  // 「找重叠」按钮跳过去并选中整组
  ptr('pointerdown', MINI_X, 672 - (0.5 / 4) * 672);   // 先把播放头挪到 0.5s
  ptr('pointerup', MINI_X, 672 - (0.5 / 4) * 672);
  els['btn-dup'].fire('click', {});
  ok(statusTime() === '00:01.000', '点「找重叠」跳到 1.000s，实际 ' + statusTime());
  ok(els['st-hint'].textContent.indexOf('1/1 组重叠') >= 0,
    '提示是第几组：' + els['st-hint'].textContent);
  key('Delete', {});
  ok(noteTotal() === 0, '跳过去以后 Del 一次能删掉整组，实际 ' + noteTotal());
  frame(1);
  ok(els['st-dup'].textContent === '', '删完重叠标记消失');

  // 没有重叠时点按钮只给提示
  els['btn-dup'].fire('click', {});
  ok(els['st-hint'].textContent.indexOf('没有重叠') >= 0, '没重叠时提示：' + els['st-hint'].textContent);
  /* ============ 阶段 AB：「跳到问题」按钮 ============ */

  reset();
  frame(1);
  documentStub.getElementById('btn-issue');

  // 造三种问题：1.0s 重复音符、2.0s 零长 hold、4.0s 长条压音符
  ptr('pointerdown', LANE0, xAt(1.0));
  ptr('pointerup', LANE0, xAt(1.0));
  ptr('pointerdown', LANE0 - 40, xAt(1.1), 0, { shiftKey: true });
  ptr('pointermove', LANE0 + 40, xAt(0.9), 0, { shiftKey: true });
  ptr('pointerup', LANE0 + 40, xAt(0.9), 0, { shiftKey: true });
  key('c', { ctrlKey: true });
  chartAudios().forEach((a) => { a.duration = 4; });
  ptr('pointerdown', MINI_X, 672 - (1.0 / 4) * 672);
  ptr('pointerup', MINI_X, 672 - (1.0 / 4) * 672);
  key('v', { ctrlKey: true });
  ok(noteTotal() === 2, '先造一组重复，实际 ' + noteTotal());

  // 先在 5.0s 放个 tap，再用 4.0~5.6 的长条把它包起来（反过来点的话会抓到长条而不是放音符）
  chartAudios().forEach((a) => { a.duration = 8; });
  ptr('pointerdown', MINI_X, 672 - (5.0 / 8) * 672);   // 播放头到 5.0s
  ptr('pointerup', MINI_X, 672 - (5.0 / 8) * 672);
  ok(statusTime() === '00:05.000', '播放头到 5.000s，实际 ' + statusTime());
  ptr('pointerdown', LANE1, 672);
  ptr('pointerup', LANE1, 672);
  ok(noteTotal() === 3, '在 5.0s 放了个 tap，实际 ' + noteTotal());

  // 回到 0，右键拖一个 4.0~5.6 的长条包住它
  ptr('pointerdown', MINI_X, 672);
  ptr('pointerup', MINI_X, 672);
  ptr('pointerdown', LANE1, xAt(4.0), 2);
  ptr('pointermove', LANE1, xAt(5.6), 2);
  ptr('pointerup', LANE1, xAt(5.6), 2);
  ok(countOf('hold') === 1, '画了一个长条，实际 ' + statusNotes());
  ok(noteTotal() === 4, '长条 + 被包住的 tap 都在，实际 ' + noteTotal());

  // 把播放头推回 0 附近再点按钮，逐个跳
  ptr('pointerdown', MINI_X, 672);
  ptr('pointerup', MINI_X, 672);
  els['btn-issue'].fire('click', {});
  ok(statusTime() === '00:01.000', '第一次跳到 1.000s（重复音符），实际 ' + statusTime());
  ok(els['st-hint'].textContent.indexOf('同轨同位置') >= 0,
    '提示问题类型：' + els['st-hint'].textContent);
  ok(els['st-hint'].textContent.indexOf('1/') >= 0, '提示是第几处：' + els['st-hint'].textContent);

  els['btn-issue'].fire('click', {});
  ok(statusTime() === '00:05.000', '第二处是长条里压的音符（5.000s），实际 ' + statusTime());
  ok(els['st-hint'].textContent.indexOf('长条中间压了') >= 0,
    '提示是长条压音符：' + els['st-hint'].textContent);
  // 绕回：连续点到超过总数会回到第一处
  let guard = 0;
  while (guard++ < 10 && statusTime() !== '00:01.000') els['btn-issue'].fire('click', {});
  ok(statusTime() === '00:01.000', '转一圈会绕回第一处，实际 ' + statusTime());

  // 没有问题时给提示
  reset();
  frame(1);
  els['btn-issue'].fire('click', {});
  ok(els['st-hint'].textContent.indexOf('没发现问题') >= 0, '空谱面点按钮：' + els['st-hint'].textContent);
  /* ============ 阶段 AC：打开带故事板的 zip 再导出，别把它弄丢 ============ */

  reset();
  frame(1);

  // 造一个「故事板整包」：chart.json + song.mp3 + cover.png + storyboard.json + assets/bg.png
  const sbChart = sandbox.RChart.createChart({ lane_count: 2 });
  sbChart.meta.title = '带故事板';
  sbChart.meta.cover = 'cover.png';
  sbChart.audio.file = 'song.mp3';
  sandbox.RChart.addNote(sbChart, { time: 1, lane: 0, type: 'tap' });
  const sbJson = JSON.stringify(sandbox.RChart.serialize(sbChart), null, '\t');
  const sbDoc = JSON.stringify({
    format: 'rchart-storyboard', version: 1,
    scenes: [{ id: 's1', name: '开场', layers: [], shader: [{ start: 0, end: 2, preset: 'glitch', amount: 0.6 }] }]
  });
  const sbZip = sandbox.RChart.zipStore([
    { name: 'chart.json', data: new TextEncoder().encode(sbJson) },
    { name: 'storyboard.json', data: new TextEncoder().encode(sbDoc) },
    { name: 'song.mp3', data: new Uint8Array([1, 2, 3, 4]) },
    { name: 'cover.png', data: new Uint8Array([137, 80, 78, 71]) },
    { name: 'assets/bg.png', data: new Uint8Array([9, 9, 9]) }
  ]);

  els['file-chart'].fire('change', {
    target: {
      files: [{ name: 'with-sb.zip', arrayBuffer: () => Promise.resolve(sbZip.buffer) }],
      value: ''
    }
  });
  await new Promise((res) => setTimeout(res, 30));

  ok(els['f-title'].value === '带故事板', '谱面读进来了：' + els['f-title'].value);
  ok(els['st-hint'].textContent.indexOf('故事板') >= 0,
    '打开时提示里带故事板：' + els['st-hint'].textContent);
  ok(els['file-name'].textContent.indexOf('含故事板') >= 0,
    '标题栏标出「含故事板」：' + els['file-name'].textContent);

  // 再导出：storyboard.json 和 assets/ 必须还在
  const beforeZip2 = blobCalls.length;
  els['btn-save'].fire('click', {});
  await new Promise((res) => setTimeout(res, 20));
  const outZip = blobCalls[blobCalls.length - 1].parts[0];
  const outText = Buffer.from(outZip).toString('latin1');
  ok(outText.indexOf('storyboard.json') >= 0, '导出的 zip 里还有 storyboard.json');
  ok(outText.indexOf('assets/bg.png') >= 0, 'assets/ 里的文件也在');
  ok(outText.indexOf('chart.json') >= 0 && outText.indexOf('song.mp3') >= 0,
    '谱面和音频照旧');

  const back = await sandbox.RChart.zipRead(outZip);
  const sbBack = JSON.parse(Buffer.from(back['storyboard.json']).toString('utf8'));
  ok(sbBack.scenes[0].shader[0].preset === 'glitch',
    'Shader 数据原样保留：' + sbBack.scenes[0].shader[0].preset);

  // 打开普通 json 时不该带着上一个 zip 的残留
  reset();
  frame(1);
  els['file-chart'].fire('change', {
    target: { files: [{ name: 'plain.json', arrayBuffer: () => Promise.resolve(new TextEncoder().encode(sbJson).buffer) }], value: '' }
  });
  await new Promise((res) => setTimeout(res, 20));
  els['btn-save'].fire('click', {});
  await new Promise((res) => setTimeout(res, 20));
  const plainZip = Buffer.from(blobCalls[blobCalls.length - 1].parts[0]).toString('latin1');
  ok(plainZip.indexOf('storyboard.json') < 0, '换成纯 json 后不再夹带旧故事板');

  // 切换谱面后，旧音频、曲绘不能混进新工程。
  ok(els['audio-name'].textContent !== 'song.mp3', '打开纯 JSON 清掉上一首的音频');
  ok(els['cover-name'].textContent !== 'cover.png', '打开纯 JSON 清掉上一首的曲绘');
  const plainFiles = await sandbox.RChart.zipRead(blobCalls[blobCalls.length - 1].parts[0]);
  ok(!plainFiles['song.mp3'] && !plainFiles['cover.png'], '打开纯 JSON 后导出不夹带旧媒体');

  // 无效谱面包应保留当前谱面和资源，不继续套用包内的媒体。
  const titleBeforeBadZip = els['f-title'].value;
  const badZip = sandbox.RChart.zipStore([
    { name: 'chart.json', data: new TextEncoder().encode('null') },
    { name: 'bad.mp3', data: new Uint8Array([8, 8]) },
    { name: 'bad.png', data: new Uint8Array([9, 9]) }
  ]);
  const alertsBeforeBadZip = logs.filter((s) => s.startsWith('ALERT ')).length;
  els['file-chart'].fire('change', {
    target: { files: [{ name: 'bad.zip', arrayBuffer: () => Promise.resolve(badZip.buffer) }], value: '' }
  });
  await new Promise((res) => setTimeout(res, 20));
  ok(els['f-title'].value === titleBeforeBadZip, '无效谱面包不替换当前谱面');
  ok(els['audio-name'].textContent !== 'bad.mp3', '无效谱面包不污染当前音频');
  ok(els['cover-name'].textContent !== 'bad.png', '无效谱面包不污染当前曲绘');
  ok(els['st-hint'].textContent.indexOf('已打开 bad.zip') < 0, '无效谱面包不提示打开成功');
  ok(logs.filter((s) => s.startsWith('ALERT ')).length === alertsBeforeBadZip + 1, '无效谱面包只提示一次错误');

  // 新建也清空媒体，避免把上一份工程的文件带进空谱面。
  els['file-chart'].fire('change', {
    target: { files: [{ name: 'with-sb.zip', arrayBuffer: () => Promise.resolve(sbZip.buffer) }], value: '' }
  });
  await new Promise((res) => setTimeout(res, 20));
  els['btn-new'].fire('click', {});
  els['btn-save'].fire('click', {});
  await new Promise((res) => setTimeout(res, 20));
  const newFiles = await sandbox.RChart.zipRead(blobCalls[blobCalls.length - 1].parts[0]);
  ok(Object.keys(newFiles).length === 1 && !!newFiles['chart.json'], '新建空谱面只导出 chart.json');
  /* ---- 连续画很多帧不炸 ---- */
  for (let i = 0; i < 40; i++) frame(1);
  ok(true, '连续 40 帧绘制没抛异常');
  ok(els.canvas.width > 0 && els.canvas.height > 0, 'canvas 分辨率已按 dpr 设置');

} catch (err) {
  ok(false, '交互流程抛异常：' + err.stack.split('\n').slice(0, 4).join(' | '));
}

/* ---------------- 收尾 ---------------- */

function report() {
  console.log('--- ui.smoke.js ---');
  console.log('pass = ' + pass + ', fail = ' + fails.length);
  if (fails.length) {
    for (const f of fails) console.log('  FAIL: ' + f);
    process.exit(1);
  }
}

report();
})();
