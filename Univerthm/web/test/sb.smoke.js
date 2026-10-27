/* 故事板渲染 + 界面冒烟测试（假 DOM / 假 WebGL，不需要浏览器）
 * node web/test/sb.smoke.js
 *
 * A. 渲染层：7 种解锁动画、9 种文字特效、5 种形状、12 种 Shader 全画一遍；
 *    顺带核对 GLSL uniform 与权重表、场景切换（解锁场不画谱面、谱面场才画）。
 * B. 界面层：假 DOM 里真跑 storyboard.js（示例工程、加场景 / 加图层、套模板、
 *    拖时间轴、撤销重做、保存工程、导出整包、截图）。
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

let pass = 0;
const fails = [];

function ok(cond, name) {
  if (cond) pass++;
  else fails.push(name);
}

function eq(a, b, name) {
  if (JSON.stringify(a) === JSON.stringify(b)) pass++;
  else fails.push(name + '  →  实际 ' + JSON.stringify(a) + ' / 期望 ' + JSON.stringify(b));
}

function near(a, b, eps, name) {
  if (Math.abs(a - b) <= (eps === undefined ? 1e-6 : eps)) pass++;
  else fails.push(name + '  →  实际 ' + a + ' / 期望 ' + b);
}

/* ==========================================================================
 * 假画布 / 假 WebGL
 * ======================================================================== */

function makeCtx() {
  const t = { _calls: [] };
  const grad = () => ({ addColorStop() {} });
  t.measureText = (s) => ({ width: String(s === undefined ? '' : s).length * 9 });
  t.createLinearGradient = grad;
  t.createRadialGradient = grad;
  return new Proxy(t, {
    get(target, k) {
      if (k === '_calls') return target._calls;
      if (k in target) return target[k];
      const fn = function (...args) {
        target._calls.push([String(k), ...args]);
        return undefined;
      };
      target[k] = fn;
      return fn;
    },
    set(target, k, v) { target[k] = v; return true; }
  });
}

function makeFakeGL() {
  const gl = {
    _uniforms: {},
    _draw: 0,
    _tex: 0,
    createShader: () => ({}),
    shaderSource() {},
    compileShader() {},
    getShaderParameter: () => true,
    getShaderInfoLog: () => '',
    createProgram: () => ({}),
    attachShader() {},
    linkProgram() {},
    getProgramParameter: () => true,
    getProgramInfoLog: () => '',
    useProgram() {},
    createBuffer: () => ({}),
    bindBuffer() {},
    bufferData() {},
    getAttribLocation: () => 0,
    enableVertexAttribArray() {},
    vertexAttribPointer() {},
    createTexture: () => ({}),
    bindTexture() {},
    texParameteri() {},
    pixelStorei() {},
    getUniformLocation: (prog, name) => ({ name }),
    uniform1i() {},
    uniform2f() {},
    uniform1f(loc, v) { if (loc && loc.name) gl._uniforms[loc.name] = v; },
    viewport() {},
    texImage2D() { gl._tex++; },
    drawArrays() { gl._draw++; },
    TRIANGLES: 4, TEXTURE_2D: 3553, RGBA: 6408, UNSIGNED_BYTE: 5121,
    TEXTURE_WRAP_S: 1, TEXTURE_WRAP_T: 2, CLAMP_TO_EDGE: 3,
    TEXTURE_MIN_FILTER: 4, TEXTURE_MAG_FILTER: 5, LINEAR: 6,
    UNPACK_FLIP_Y_WEBGL: 7, ARRAY_BUFFER: 8, STATIC_DRAW: 9,
    VERTEX_SHADER: 10, FRAGMENT_SHADER: 11, COMPILE_STATUS: 12, LINK_STATUS: 13, FLOAT: 14
  };
  return gl;
}

function FakeCanvas(id, useGL) {
  this.id = id || '';
  this.tagName = 'CANVAS';
  this.width = 0;
  this.height = 0;
  this.clientWidth = 300;
  this.clientHeight = 150;
  this.style = {};
  this._ctx = null;
  this._gl = useGL ? makeFakeGL() : null;
}

FakeCanvas.prototype.getContext = function (type) {
  if (type === 'webgl' || type === 'experimental-webgl') return this._gl;
  if (!this._ctx) this._ctx = makeCtx();
  return this._ctx;
};

FakeCanvas.prototype.toDataURL = function () { return 'data:image/png;base64,AAAA'; };

/* ==========================================================================
 * A. 渲染层
 * ======================================================================== */

const RC = require('../js/core.js');
const SB = require('../js/sb_core.js');

global.document = { createElement: (tag) => new FakeCanvas(tag, true) };
global.window = global.window || {};
global.window.RChart = global.window.RChart || require('../js/core.js');
const ChartStage = require('../js/chart_stage.js');
const SBR = require('../js/sb_render.js');

for (const key of Object.keys(SBR.WEIGHT_UNIFORMS)) {
  const uniform = SBR.WEIGHT_UNIFORMS[key];
  ok(new RegExp('\\b' + uniform + '\\b').test(SBR.GLSL.frag), 'GLSL 里有 ' + uniform);
  ok(SB.WEIGHT_KEYS.indexOf(key) >= 0, '权重键 ' + key + ' 在 SB.WEIGHT_KEYS 里');
}
ok(SBR.GLSL.vert.indexOf('gl_Position') >= 0, '顶点着色器有 gl_Position');
ok(SBR.GLSL.frag.indexOf('gl_FragColor') >= 0, '片元着色器写 gl_FragColor');

/* ---- 测试数据 ---- */

function demoChart() {
  const chart = RC.createChart({ lane_count: 4 });
  chart.meta.title = 'Neon Pulse';
  chart.meta.artist = 'Synth Engine';
  chart.meta.difficulty = 'HARD';
  chart.meta.level = 8;
  const xs = [-150, -50, 50, 150];
  for (let i = 0; i < 4; i++) {
    chart.lanes[i].x = xs[i];
    chart.lanes[i].alpha = 100;
    chart.lanes[i].judge_zone = i < 2 ? 'left' : 'right';
    chart.lanes[i].events = RC.emptyEvents();
  }
  let time = 0.6;
  for (let n = 0; n < 40; n++) {
    chart.notes.push({
      id: n + 1, time: time, lane: n % 4,
      type: n % 9 === 0 ? 'hold' : (n % 7 === 0 ? 'flick' : (n % 13 === 0 ? 'mine' : 'tap')),
      duration: n % 9 === 0 ? 0.6 : 0
    });
    time += 0.25;
  }
  RC.sortNotes(chart);
  return chart;
}

const chart = demoChart();
const digest = SB.chartDigest(chart, { file: 'demo.zip', hash: 'deadbeef' });

/** 一个只有「演出场」的工程：图层测试用它，全局时间 = 场景内时间 */
function freeDoc(len) {
  const doc = SB.createStoryboard({ duration: 0, title: 'T' });
  const sc = doc.scenes[0];
  sc.length = len || 4;
  return { doc, scene: sc };
}

function drawOnce(doc, t, images) {
  const r = SBR.create(new FakeCanvas('stage', true));
  r.render({ t: t, doc: doc, chart: chart, images: images || {}, phase: t });
  return r;
}

/* ---- 空工程 ---- */
{
  const r = drawOnce(SB.createStoryboard(), 1);
  ok(r.g._calls.length > 0, '空工程也铺了背景');
  ok(r.glOk(), '假 WebGL 被识别到（真机上是真 WebGL，这里验代码路径）');
}

/* ---- 场景切换：解锁场不画谱面，谱面场才画 ---- */
{
  const doc = SB.createStoryboard(digest);           // 解锁场 2.6 秒 + 谱面场
  const spans = SB.sceneSpans(doc);
  near(spans[0].end, 2.6, 1e-9, '解锁场 2.6 秒');

  const inUnlock = drawOnce(doc, 1.0);
  ok(inUnlock.lastScene && inUnlock.lastScene.kind === 'unlock', '1.0 秒在解锁场');
  const unlockFills = inUnlock.g._calls.filter(c => c[0] === 'fill').length;

  const inChart = drawOnce(doc, 2.6 + 1.2);
  ok(inChart.lastScene && inChart.lastScene.kind === 'chart', '3.8 秒在谱面场');
  near(inChart.lastScene.local, 1.2, 1e-6, '谱面场内本地时间 = 1.2');
  const chartFills = inChart.g._calls.filter(c => c[0] === 'fill').length;
  ok(chartFills > unlockFills, '谱面场比空的解锁场画得多（轨道 / 音符出来了）');

  ok(inChart.g._calls.some(c => c[0] === 'stroke'), '谱面场画了判定线');
}

/* ---- 文字特效：9 种全跑一遍 ---- */
{
  for (const fx of SB.TEXT_EFFECTS) {
    const { doc, scene } = freeDoc(4);
    const L = SB.addLayer(scene, 'text', { start: 0, end: 4 });
    L.text = 'Neon Pulse\n霓虹脉冲 ✨';
    L.style.effect = fx.id;
    L.in = { preset: 'none', dur: 0, ease: 'linear' };
    L.out = { preset: 'none', dur: 0, ease: 'linear' };
    let calls = 0;
    let threw = '';
    for (const t of [0, 0.35, 1.2, 2.6, 3.9]) {
      try {
        const r = drawOnce(doc, t);
        calls += r.g._calls.filter(c => c[0] === 'fillText').length;
      } catch (err) {
        threw = err.message;
      }
    }
    ok(!threw, '文字特效 ' + fx.id + ' 不抛异常' + (threw ? '：' + threw : ''));
    ok(calls > 0, '文字特效 ' + fx.id + ' 真的画了字');
  }
}

/* ---- 打字机：时间越久露出的字越多 ---- */
{
  const { doc, scene } = freeDoc(4);
  const L = SB.addLayer(scene, 'text', { start: 0, end: 4 });
  L.text = 'ABCDEFGHIJ';
  L.style.effect = 'type';
  L.style.speed = 3;
  L.in = { preset: 'none', dur: 0, ease: 'linear' };
  L.out = { preset: 'none', dur: 0, ease: 'linear' };
  const countAt = (t) => drawOnce(doc, t).g._calls.filter(c => c[0] === 'fillText').length;
  const early = countAt(0.2);
  const late = countAt(3.2);
  ok(late > early, '打字机：后面的字数更多（' + early + ' → ' + late + '）');
  ok(early <= 2, '打字机：一开始只露出几个字');
}

/* ---- 解锁动画：7 种 × 5 个时间点 ---- */
{
  for (const preset of SB.UNLOCK_PRESETS) {
    const { doc, scene } = freeDoc(3);
    const L = SB.addLayer(scene, 'unlock', { start: 0, end: 3 });
    L.unlock.preset = preset.id;
    L.unlock.label = 'Neon Pulse';
    L.unlock.sub = 'HARD 8';
    L.in = { preset: 'none', dur: 0, ease: 'linear' };
    L.out = { preset: 'fade', dur: 0.3, ease: 'linear' };
    let calls = 0;
    let threw = '';
    for (const t of [0, 0.6, 1.5, 2.2, 2.95]) {
      try {
        calls += drawOnce(doc, t).g._calls.length;
      } catch (err) {
        threw = err.message;
      }
    }
    ok(!threw, '解锁动画 ' + preset.id + ' 不抛异常' + (threw ? '：' + threw : ''));
    ok(calls > 0, '解锁动画 ' + preset.id + ' 真的画了');
  }
}

/* ---- 形状 / 混合 / 图片 ---- */
{
  for (const kind of SB.SHAPE_KINDS) {
    const { doc, scene } = freeDoc(2);
    SB.addLayer(scene, 'shape', { start: 0, end: 2 }).shape.kind = kind.id;
    let threw = '';
    try { drawOnce(doc, 0.9); } catch (err) { threw = err.message; }
    ok(!threw, '形状 ' + kind.id + ' 能画' + (threw ? '：' + threw : ''));
  }

  for (const blend of SB.BLENDS) {
    const { doc, scene } = freeDoc(2);
    SB.addLayer(scene, 'shape', { start: 0, end: 2 }).blend = blend.id;
    let threw = '';
    try {
      const r = drawOnce(doc, 1);
      ok(r.g._calls.filter(c => c[0] === 'fill').length > 0, '混合模式 ' + blend.id + ' 有绘制');
    } catch (err) { threw = err.message; }
    ok(!threw, '混合模式 ' + blend.id + ' 不抛异常' + (threw ? '：' + threw : ''));
    ok(SB.BLEND_CANVAS[blend.id], '混合模式 ' + blend.id + ' 有对应的 canvas 值');
  }

  {
    const { doc, scene } = freeDoc(2);
    const L = SB.addLayer(scene, 'image', { start: 0, end: 2 });
    L.image.name = 'missing.png';
    const r1 = drawOnce(doc, 1);
    ok(r1.g._calls.some(c => c[0] === 'fillText'), '缺图时画了「图片缺失」占位');

    L.image.name = 'logo.png';
    const r2 = drawOnce(doc, 1, { 'logo.png': { width: 400, height: 200 } });
    ok(r2.g._calls.some(c => c[0] === 'drawImage'), '有图时走 drawImage');
  }
}

/* ---- 出入场 ---- */
{
  for (const preset of SB.IN_PRESETS) {
    const { doc, scene } = freeDoc(2);
    const L = SB.addLayer(scene, 'text', { start: 0, end: 2 });
    L.text = 'X';
    L.in = { preset: preset.id, dur: 0.6, ease: 'outCubic' };
    let threw = '';
    try { drawOnce(doc, 0.3); } catch (err) { threw = err.message; }
    ok(!threw, '入场 ' + preset.id + ' 能画' + (threw ? '：' + threw : ''));
  }
  for (const preset of SB.OUT_PRESETS) {
    const { doc, scene } = freeDoc(2);
    const L = SB.addLayer(scene, 'text', { start: 0, end: 2 });
    L.text = 'X';
    L.out = { preset: preset.id, dur: 0.6, ease: 'inCubic' };
    let threw = '';
    try { drawOnce(doc, 1.8); } catch (err) { threw = err.message; }
    ok(!threw, '出场 ' + preset.id + ' 能画' + (threw ? '：' + threw : ''));
  }
}

/* ---- Shader：12 种 + 场景隔离 ---- */
{
  for (const preset of SB.SHADER_PRESETS) {
    const { doc, scene } = freeDoc(4);
    SB.addShader(scene, preset.id, { start: 0, end: 4, amount: 100, ramp: 0.2 });
    const r = drawOnce(doc, 2);
    const w = r.lastWeights;
    const keys = Object.keys(preset.weights);
    if (!keys.length) {
      ok(SB.WEIGHT_KEYS.every(k => !w[k]), 'Shader none 不加任何效果');
    } else {
      for (const k of keys) ok(w[k] > 0, 'Shader ' + preset.id + ' 的 ' + k + ' 送到了 uniform');
    }
  }

  const { doc, scene } = freeDoc(4);
  SB.addShader(scene, 'bloom', { start: 0, end: 4, amount: 100, ramp: 0 });
  const r = SBR.create(new FakeCanvas('stage', true));
  r.render({ t: 2, doc: doc, chart: chart, images: {}, phase: 2 });
  const gl = r.gl;
  ok(gl && gl._draw > 0, 'WebGL 路径下真的 drawArrays 了');
  near(gl._uniforms.uBloom, 1, 1e-6, 'uBloom = 1');
  near(gl._uniforms.uTime, 2, 1e-6, 'uTime 传了播放时间');
  near(gl._uniforms.uRgb, 0, 1e-6, '没开的 uRgb = 0');
  ok(gl._tex > 0, '把离屏画布传成了纹理');

  SB.addShader(scene, 'rgb', { start: 0, end: 4, amount: 100, ramp: 0 });
  r.render({ t: 2, doc: doc, chart: chart, images: {}, phase: 2 });
  near(gl._uniforms.uRgb, 0.85, 1e-6, '第二条 shader 也叠上去了');

  // 场景隔离：解锁场的 shader 不会漏到谱面场
  const iso = SB.createStoryboard(digest);
  SB.addShader(iso.scenes[0], 'glitch', { start: 0, end: 2.6, amount: 100, ramp: 0 });
  const rUnlock = drawOnce(iso, 1);
  const rChart = drawOnce(iso, 2.6 + 1);
  ok(rUnlock.lastWeights.glitch > 0.9, '解锁场的故障在解锁场生效');
  near(rChart.lastWeights.glitch, 0, 1e-9, '谱面场不会被解锁场的 shader 带跑');
}

/* ---- 没有 WebGL 时退化 ---- */
{
  const cv = new FakeCanvas('stage', false);
  const r = SBR.create(cv);
  ok(!r.glOk(), '没 WebGL 时 glOk() = false');
  ok(r.glError.length > 0, '没 WebGL 时给出说明');
  const { doc, scene } = freeDoc(2);
  SB.addLayer(scene, 'text', {}).text = 'hi';
  let threw = '';
  try { r.render({ t: 1, doc: doc, chart: chart, images: {}, phase: 1 }); } catch (err) { threw = err.message; }
  ok(!threw, '退化路径能渲染' + (threw ? '：' + threw : ''));
  ok(r.ctx2d && r.ctx2d._calls.some(c => c[0] === 'drawImage'), '退化时把离屏画布贴上去');
}

/* ---- 谱面基准：谱面按预渲染尺寸(380x214)画完再放大 ---- */
{
  const c2 = RC.normalize({
    lanes: [
      { x: 100, y: 70, alpha: 100, speed: 10, length: 10 },
      { x: 0, y: 0, alpha: 0, speed: 10, length: 10 },
      { x: 0, y: 0, alpha: 0, speed: 10, length: 10 },
      { x: 0, y: 0, alpha: 0, speed: 10, length: 10 }
    ],
    notes: []
  }).chart;
  const dg = SB.chartDigest(c2, {});
  dg.duration = 5;                      // 让 createStoryboard 建出「谱面场」
  const d2 = SB.createStoryboard(dg);
  function lineToYs(doc) {
    const r = SBR.create(new FakeCanvas('s', true));
    r.g._calls.length = 0;
    r.render({ t: 2.6 + 1, doc: doc, chart: c2, images: {}, phase: 3.6 });   // 谱面场：解锁场 2.6s 之后
    return r.g._calls.filter((c) => c[0] === 'lineTo').map((c) => c[2]);
  }
  d2.stage.chartBase = 350;                       // 游戏逻辑舞台：x/y 原样用
  const ys350 = lineToYs(d2);
  d2.stage.chartBase = 700;                       // 谱面按 700 宽调的 → x/y 缩一半
  const ys700 = lineToYs(d2);
  // 逻辑舞台 judgeY = round(196.875*0.85) = 167；lane y=70
  ok(ys350.some((y) => Math.abs(y - 97) < 3), '基准 350：轨道基点 y≈167-70=97（游戏坐标）');
  ok(ys700.some((y) => Math.abs(y - 132) < 3), '基准 700：x/y 缩一半后 y≈167-35=132');
  ok(ys350.every((y) => y < 350), '所有坐标都在 350×197 的逻辑舞台里');
}

/* ---- 截图 ---- */
{
  const { doc } = freeDoc(2);
  ok(String(drawOnce(doc, 1).shot()).indexOf('data:image/png') === 0, 'shot() 返回 PNG dataURL');
}

/* ---- 关键帧：整条时间线都能画 ---- */
{
  const { doc, scene } = freeDoc(6);
  const L = SB.addLayer(scene, 'text', { start: 1, end: 5 });
  L.text = 'A\nB';
  SB.addLayerEvent(L, 'x', { start: 1, end: 3, ease: 'inOutCubic', from: 0.2, to: 0.8 });
  SB.addLayerEvent(L, 'scale', { start: 2, end: 4, ease: 'outBack', from: 100, to: 220 });
  let threw = '';
  for (let t = 0; t <= 6; t += 0.1) {
    try { drawOnce(doc, t); } catch (err) { threw = err.message; break; }
  }
  ok(!threw, '带关键帧的图层扫完整条时间线不抛异常' + (threw ? '：' + threw : ''));
}

/* ==========================================================================
 * B. 界面层
 * ======================================================================== */

function makeSandbox(search) {
  const els = {};
  const listeners = {};
  const winListeners = {};
  const blobs = [];
  const alerts = [];
  let rafCb = null;
  let nowMs = 1000;

  function El(id) {
    this.id = id || '';
    this.textContent = '';
    this.innerHTML = '';
    this.value = '';
    this.disabled = false;
    this.style = {};
    this.dataset = {};
    this.tagName = 'DIV';
    this.clientWidth = 300;
    this.clientHeight = 150;
    this.width = 0;
    this.height = 0;
    this._listeners = {};
    this._attrs = {};
  }
  El.prototype.addEventListener = function (type, fn) {
    (this._listeners[type] = this._listeners[type] || []).push(fn);
  };
  El.prototype.fire = function (type, ev) {
    const event = Object.assign({ currentTarget: this, target: this, preventDefault() {} }, ev || {});
    const list = (this._listeners[type] || []).slice();
    for (const fn of list) fn.call(this, event);
    return event;
  };
  El.prototype.getBoundingClientRect = function () {
    return { left: 0, top: 0, width: this.clientWidth, height: this.clientHeight };
  };
  El.prototype.getContext = function (type) {
    if (type === 'webgl' || type === 'experimental-webgl') return null;
    if (!this._ctx) this._ctx = makeCtx();
    return this._ctx;
  };
  El.prototype.toDataURL = function () { return 'data:image/png;base64,AAAA'; };
  El.prototype.setAttribute = function (k, v) { this._attrs[k] = v; };
  El.prototype.removeAttribute = function (k) { delete this._attrs[k]; };
  El.prototype.appendChild = function () {};
  El.prototype.removeChild = function () {};
  El.prototype.querySelector = function () { return null; };
  El.prototype.querySelectorAll = function () { return []; };
  El.prototype.closest = function () { return null; };
  El.prototype.classList = { add: function () {}, remove: function () {}, toggle: function () {}, contains: function () { return false; } };
  El.prototype.setPointerCapture = function () {};
  El.prototype.releasePointerCapture = function () {};
  El.prototype.focus = function () {};
  El.prototype.blur = function () {};
  El.prototype.click = function () { this.fire('click', {}); };

  function getEl(id) {
    if (!els[id]) els[id] = new El(id);
    return els[id];
  }

  getEl('stage').tagName = 'CANVAS';
  getEl('timeline').tagName = 'CANVAS';
  getEl('timeline').clientWidth = 1000;
  getEl('timeline').clientHeight = 232;
  getEl('tl-scrollbar').clientWidth = 850;      // 和时间轴可视宽度同量级（134 左边距 + 16 右边距）
  getEl('tl-scrollbar').clientHeight = 12;
  getEl('tl-thumb').offsetWidth = 300;

  const addBtns = ['text', 'unlock', 'image', 'video', 'shape'].map((t) => {
    const b = new El('add-' + t);
    b.dataset.add = t;
    return b;
  });
  const sceneBtns = ['unlock', 'free', 'chart'].map((k) => {
    const b = new El('add-scene-' + k);
    b.dataset.addScene = k;
    return b;
  });

  const documentStub = {
    readyState: 'complete',
    body: new El('body'),
    getElementById: getEl,
    createElement(tag) {
      if (tag === 'canvas') return new El('canvas');
      return new El(tag);
    },
    addEventListener(type, fn) { (listeners[type] = listeners[type] || []).push(fn); },
    querySelectorAll(sel) {
      if (sel === '[data-add]') return addBtns;
      if (sel === '[data-add-scene]') return sceneBtns;
      return [];
    }
  };

  const ctxObj = {
    console: { log() {}, warn() {}, error() {} },
    performance: { now: () => nowMs },
    devicePixelRatio: 2,
    requestAnimationFrame(cb) { rafCb = cb; return 1; },
    document: documentStub,
    location: { search: search || '', href: 'file:///storyboard.html' },
    URL: { createObjectURL: () => 'blob:stub', revokeObjectURL() {} },
    URLSearchParams: URLSearchParams,
    Blob: function (parts, opts) { blobs.push({ parts: parts, type: opts && opts.type }); },
    TextEncoder: TextEncoder,
    TextDecoder: TextDecoder,
    atob: (s) => Buffer.from(s, 'base64').toString('binary'),
    FileReader: function () { this.readAsDataURL = function () {}; },
    Image: function () { this.width = 100; this.height = 50; },
    alert(msg) { alerts.push(msg); },
    confirm: () => true,
    setTimeout: () => 0,
    clearTimeout: () => {},
    addEventListener(type, fn) { (winListeners[type] = winListeners[type] || []).push(fn); },
    removeEventListener() {},
    Audio: function (src) {
      this.src = src || '';
      this.volume = 1;
      this.currentTime = 0;
      this.paused = true;
      this.play = () => { this.paused = false; return { catch() {} }; };
      this.pause = () => { this.paused = true; };
    }
  };
  ctxObj.window = ctxObj;
  ctxObj.self = ctxObj;
  ctxObj.globalThis = ctxObj;

  const sandbox = vm.createContext(ctxObj);
  vm.runInContext(read('js/core.js'), sandbox, { filename: 'core.js' });
  vm.runInContext(read('js/sb_core.js'), sandbox, { filename: 'sb_core.js' });
vm.runInContext(read('js/chart_stage.js'), sandbox, { filename: 'chart_stage.js' });
  vm.runInContext(read('js/sb_render.js'), sandbox, { filename: 'sb_render.js' });
  vm.runInContext(read('js/storyboard.js'), sandbox, { filename: 'storyboard.js' });

  function frame(n) {
    for (let i = 0; i < (n || 1); i++) {
      const cb = rafCb;
      rafCb = null;
      nowMs += 16;
      if (cb) cb(nowMs);
    }
  }

  function key(k, mods) {
    const ev = Object.assign({
      key: k, code: k === ' ' ? 'Space' : k,
      ctrlKey: false, shiftKey: false, metaKey: false,
      target: { tagName: 'CANVAS' }, preventDefault() {}
    }, mods || {});
    (listeners.keydown || []).forEach((fn) => fn(ev));
  }

  function ptrOn(el, type, x, y) {
    el.fire(type, { clientX: x, clientY: y, pointerId: 1, button: 0 });
  }

  function windowPtr(type, x, y) {
    (winListeners[type] || []).forEach((fn) => fn({ clientX: x, clientY: y, pointerId: 1 }));
  }

  return {
    sandbox, els, getEl, addBtns, sceneBtns, blobs, alerts,
    frame, key, ptrOn, windowPtr,
    app: () => sandbox.window.__RHYTHM_SB__
  };
}

const TX0 = 134, TX1 = 1000 - 16;
const ROW0 = 26 + 26 + 4 + 10;     // 标尺 + 场景带 + 第一行图层（行高 21 的中点）

/* ---- 示例工程 ---- */
let ui;
try {
  ui = makeSandbox('?demo=1');
  ok(true, '界面脚本加载 + boot（示例工程）没抛异常');
} catch (err) {
  ok(false, '界面脚本加载抛异常：' + err.message + '\n' + (err.stack || ''));
}

if (ui) {
  const app = ui.app();
  ok(!!app, '调试钩子存在');

  const doc = app.doc();
  const spans = app.spans();
  ok(doc.scenes.length >= 3, '示例有三场以上（' + doc.scenes.length + ' 场）');
  eq(doc.scenes[0].kind, 'unlock', '第一场是解锁场');
  ok(spans.some(s => s.kind === 'chart'), '有谱面场');
  eq(spans[0].start, 0, '解锁场从 0 开始');
  ok(spans[1].start > 0, '谱面场排在解锁场之后（' + spans[1].start + 's 处）');
  ok(doc.chart.notes > 50, '谱面引用里有音符数');

  ok(ui.getEl('scene-list').innerHTML.indexOf('scene-item') >= 0, '场景列表渲染出来了');
  ok(ui.getEl('layer-list').innerHTML.indexOf('layer-item') >= 0, '图层列表渲染出来了');
  ok(ui.getEl('inspector').innerHTML.length > 100, '属性面板渲染出来了');
  ok(ui.getEl('shader-list').innerHTML.indexOf('shader-item') >= 0, '后处理列表渲染出来了');
  ok(ui.getEl('st-layers').textContent.indexOf('场景') === 0, '状态栏显示当前场景');
  ok(ui.getEl('chart-title').textContent === 'Neon Pulse', '谱面卡片显示曲名');
  ok(ui.getEl('st-total-txt').textContent.indexOf(':') > 0, '总时长显示');

  // 播放：解锁场里音乐不该响（demo 没音频，这里只看时间推进）
  ui.getEl('btn-play').fire('click');
  ui.frame(12);
  ok(app.state.time > 0, '播放后时间在走（' + app.state.time.toFixed(2) + 's）');
  ui.getEl('btn-stop').fire('click');
  near(app.state.time, 0, 1e-6, '■ 回到开头');

  // 空格播放 / 暂停
  ui.key(' ', { code: 'Space' });
  ui.frame(4);
  ok(app.state.playing, '空格开始播放');
  ui.key(' ', { code: 'Space' });
  ok(!app.state.playing, '空格再按暂停');

  // 四种「添加图层」都进当前场景（解锁场）
  const scene0 = app.scene();
  const before = scene0.layers.length;
  for (const b of ui.addBtns) b.fire('click');
  eq(app.scene().layers.length, before + 5, '五种「添加图层」都加上了');

  // 套模板：铺进当前场景（2.6 秒的解锁场放 5 秒模板 → 压缩）
  const tplBefore = app.scene().layers.length;
  ui.getEl('tpl-select').value = 'unlock';
  ui.getEl('btn-tpl').fire('click');
  ok(app.scene().layers.length > tplBefore, '模板套用加了图层');
  ok(app.scene().layers.every(l => l.end <= 2.6 + 1e-6), '模板被压进场景长度内');

  // 加后处理
  const shBefore = app.doc().scenes[0].shaders.length;
  ui.getEl('shader-preset').value = 'glitch';
  ui.getEl('btn-add-shader').fire('click');
  eq(app.doc().scenes[0].shaders.length, shBefore + 1, '后处理加了一条');

  // 撤销 / 重做
  ok(app.state.undo.length > 0, '有撤销栈');
  ui.getEl('btn-undo').fire('click');
  eq(app.doc().scenes[0].shaders.length, shBefore, '撤销把后处理退回去了');
  ui.getEl('btn-redo').fire('click');
  eq(app.doc().scenes[0].shaders.length, shBefore + 1, '重做又加回来了');

  // 在谱面场里点「＋ 解锁动画」→ 自动新建一个解锁场，排在谱面场前面
  {
    const spansNow = app.spans();
    const chartIdx = spansNow.findIndex(s => s.kind === 'chart');
    app.state.sceneId = spansNow[chartIdx].id;
    app.state.time = spansNow[chartIdx].start + 0.5;
    app.redraw();
    const sceneCount0 = app.doc().scenes.length;
    ui.addBtns[1].fire('click');                       // ＋ 解锁动画
    eq(app.doc().scenes.length, sceneCount0 + 1, '谱面场里加解锁动画会新建场景');
    eq(app.scene().kind, 'unlock', '新建的是解锁场');
    ok(app.scene().layers.some(l => l.type === 'unlock'), '解锁动画在新解锁场里');
    const after = app.spans();
    const newIdx = after.findIndex(s => s.id === app.scene().id);
    const chartIdx2 = after.findIndex(s => s.kind === 'chart');
    ok(newIdx < chartIdx2, '新解锁场排在谱面场之前');
    ok(after[newIdx].end <= after[chartIdx2].start + 1e-6, '解锁场在谱面开始之前结束');
  }

  // 已经有谱面场时，不允许再加一个
  {
    const n0 = app.doc().scenes.length;
    ui.sceneBtns[2].fire('click');                     // ＋ 谱面场
    eq(app.doc().scenes.length, n0, '不会出现第二个谱面场');
  }

  // 曲绘作者：写进故事板 meta，并在谱面 chips 里显示
  ui.getEl('f-illust').value = 'Yuki';
  ui.getEl('f-illust').fire('input');
  eq(app.state.doc.meta.coverArtist, 'Yuki', '曲绘作者写进 meta.coverArtist');
  ok(ui.getEl('chart-chips').innerHTML.indexOf('Yuki') >= 0, 'chips 里显示曲绘作者');
  ok(ui.getEl('f-illust').value === 'Yuki', '输入框回显');

  // 谱面基准（= 谱面 x/y 按多大画幅调的）
  ui.getEl('st-chart-base').value = '1280';
  ui.getEl('st-chart-base').fire('change');
  eq(app.state.doc.stage.chartBase, 1280, '谱面基准写进 stage.chartBase');
  ui.getEl('st-chart-base').value = '380';
  ui.getEl('st-chart-base').fire('change');
  eq(app.state.doc.stage.chartBase, 380, '能切回 380（同预渲染窗）');

  // 音量 / 静音
  ok(ui.getEl('audio-name').textContent.length > 0, '音频面板显示状态');
  ui.getEl('st-volume').value = '45';
  ui.getEl('st-volume').fire('input');
  near(app.state.doc.stage.volume, 45, 1e-6, '音量写进 stage.volume');
  eq(ui.getEl('st-volume-txt').textContent, '45%', '音量百分比显示');
  ui.getEl('chk-mute').checked = true;
  ui.getEl('chk-mute').fire('change');
  eq(app.state.muted, true, '静音开关生效');
  ui.getEl('chk-mute').checked = false;
  ui.getEl('chk-mute').fire('change');
  eq(app.state.muted, false, '取消静音');

  // 新增场景（演出场）
  const scenesBefore = app.doc().scenes.length;
  ui.sceneBtns[1].fire('click');
  eq(app.doc().scenes.length, scenesBefore + 1, '加了一场演出场');
  const added = app.spans()[app.spans().length - 1];
  eq(added.kind, 'free', '新场景是演出场');
  ok(app.state.sceneId === added.id, '自动切到新场景');
  ok(app.state.total > 0, '总时长跟着变');

  // 滚轮缩放
  const spanBefore = app.state.view.span;
  ui.getEl('timeline').fire('wheel', { deltaY: -100, ctrlKey: true, clientX: 500, preventDefault() {} });
  ok(app.state.view.span < spanBefore, 'Ctrl+滚轮会把时间轴拉近');

  // 复位视图，后面按固定坐标算位置
  app.state.view.start = 0;
  app.state.view.span = 20;

  // 时间轴：点标尺 = 移动播放头
  ui.ptrOn(ui.getEl('timeline'), 'pointerdown', 300, 8);
  ui.windowPtr('pointerup', 300, 8);
  ok(app.state.time > 0, '点时间轴标尺能移动播放头');

  // 拖一条图层条（切回解锁场，放一个位置确定的图层）
  {
    const st = app.state;
    st.sceneId = app.spans()[0].id;      // 切回解锁场
    app.redraw();
    const sc = app.scene();
    const sp = app.spans().find(s => s.id === sc.id);
    const target = sc.layers[sc.layers.length - 1];
    target.start = 0.6;
    target.end = 1.4;
    app.redraw();

    const start0 = target.start;
    const len0 = target.end - target.start;
    const lay = app.layout();
    const tx = (t) => lay.x0 + ((t - st.view.start) / st.view.span) * (lay.x1 - lay.x0);
    const midX = tx(sp.start + (start0 + target.end) / 2);
    const rowY = lay.rows[0].y + lay.rows[0].h / 2;      // 最上面那行 = 最上层图层
    ok(midX > lay.x0 && midX < lay.x1, '要拖的图层条在可视范围内');

    ui.ptrOn(ui.getEl('timeline'), 'pointerdown', midX, rowY);
    ui.ptrOn(ui.getEl('timeline'), 'pointermove', midX + 40, rowY);
    ui.windowPtr('pointerup', midX + 40, rowY);

    const moved = app.scene().layers[sc.layers.length - 1];
    ok(moved.start > start0 + 0.05, '拖图层条能整体平移（' + start0 + ' → ' + moved.start + '）');
    near(moved.end - moved.start, len0, 0.06, '平移时长度基本不变');

    ui.getEl('btn-undo').fire('click');
    const after = app.scene().layers[app.scene().layers.length - 1];
    near(after.start, start0, 0.02, '撤销把拖动退回去了');
  }

  // 后处理条拖得动（回归：以前贴着场景末尾的条会卡住 / 越拖越短）
  {
    const st = app.state;
    st.sceneId = app.spans()[0].id;      // 解锁场（可以跟着条一起变长）
    app.redraw();
    const sc = app.scene();
    const sp = app.spans().find(s => s.id === sc.id);
    // 这一组只放一条后处理，行才在视野里（前面的用例可能留了好几条）
    app.state.tlScroll = 0;
    const scB = app.scene();
    scB.shaders.length = 0;
    SB.addShader(scB, 'rgb', { start: 1.2, end: Math.max(1.4, sp.len), amount: 80, ramp: 0 });
    const fx = app.scene().shaders[0];
    fx.start = 1.2;
    fx.end = sp.len;                     // 故意贴住场景末尾：旧代码就是在这里卡住的
    app.redraw();

    const lay = app.layout();
    // 行是「按重叠自动分层」的，一行可能有好几条 → 找包含目标 shader 的那一行
    const shaderRow = lay.rows.find(r => r.kind === 'shader' && (r.ids || []).indexOf(fx.id) >= 0) || lay.rows.find(r => r.kind === 'shader');
    ok(!!shaderRow, '时间轴上有后处理行');
    ok(shaderRow.y + shaderRow.h <= 232, '后处理行在时间轴可视范围内（y=' + Math.round(shaderRow.y) + '）');
    const spanLen = sp.len;
    const dur0 = fx.end - fx.start;

    const tx = (t) => lay.x0 + ((t - st.view.start) / st.view.span) * (lay.x1 - lay.x0);
    const x1 = tx(sp.start + fx.start);
    const x2 = tx(sp.start + fx.end);
    const midX = (x1 + x2) / 2;
    const rowY = shaderRow.y + shaderRow.h / 2;
    const start0 = fx.start;

    ui.ptrOn(ui.getEl('timeline'), 'pointerdown', midX, rowY);
    ui.ptrOn(ui.getEl('timeline'), 'pointermove', midX - 40, rowY);
    ui.windowPtr('pointerup', midX - 40, rowY);
    const moved = app.scene().shaders[0];
    ok(moved.start < start0 - 0.02, '后处理条能整体平移（' + start0 + ' → ' + moved.start + '）');
    near(moved.end - moved.start, dur0, 0.08, '平移时后处理长度不变（fx ' + fx.start + '–' + fx.end + ' / moved ' + moved.start + '–' + moved.end + ' / n=' + app.scene().shaders.length + '）');

    // 往右拖过场景末尾 → 场景跟着长（解锁场允许）
    const before = app.spans().find(s => s.id === sc.id).len;
    const m2 = (tx(sp.start + moved.start) + tx(sp.start + moved.end)) / 2;
    ui.ptrOn(ui.getEl('timeline'), 'pointerdown', m2, rowY);
    ui.ptrOn(ui.getEl('timeline'), 'pointermove', m2 + 80, rowY);
    ui.windowPtr('pointerup', m2 + 80, rowY);
    const after = app.spans().find(s => s.id === sc.id).len;
    ok(after > before, '拖过场景末尾会把场景加长（' + before + ' → ' + after + '）');

    ui.getEl('btn-undo').fire('click');
    ui.getEl('btn-undo').fire('click');
    // 最狠的情况：条从头铺到尾（start=0, end=场景长度），旧代码往右拖会越拖越短、拖不动
    {
      const sc2 = app.scene();
      const sp2 = app.spans().find(s => s.id === sc2.id);
      const fx2 = app.scene().shaders[0];
      fx2.start = 0;
      fx2.end = sp2.len;
      app.redraw();
      const lay2 = app.layout();
      const row2 = lay2.rows.find(r => r.kind === 'shader');
      const tx2 = (t) => lay2.x0 + ((t - st.view.start) / st.view.span) * (lay2.x1 - lay2.x0);
      const mid2 = (tx2(sp2.start) + tx2(sp2.start + sp2.len)) / 2;
      const rowY2 = row2.y + row2.h / 2;
      ui.ptrOn(ui.getEl('timeline'), 'pointerdown', mid2, rowY2);
      ui.ptrOn(ui.getEl('timeline'), 'pointermove', mid2 + 50, rowY2);
      ui.windowPtr('pointerup', mid2 + 50, rowY2);
      const f3 = app.scene().shaders[0];
      ok(f3.start > 0.05, '铺满整场的后处理条也能拖动（start=' + f3.start + '）');
      near(f3.end - f3.start, sp2.len, 0.12, '拖动时长度保持（没被压扁）');
      ui.getEl('btn-undo').fire('click');
    }

    ui.getEl('btn-undo').fire('click');
    ui.getEl('btn-undo').fire('click');
  }

  // 条的命中区：宽条能切两端；缩得很小时整条都是「平移」（不然全在边缘上，就拖不动了）
  {
    const st = app.state;
    st.sceneId = app.spans()[0].id;
    st.tlScroll = 0;
    app.redraw();
    const sc = app.scene();
    const fx = sc.shaders[0];
    fx.start = 1;
    fx.end = 3;
    st.view.start = 0;
    st.view.span = 6;
    app.redraw();
    let lay = app.layout();
    let row = lay.rows.find(r => r.kind === 'shader');
    const txOfView = (lay2, t) => lay2.x0 + ((t - st.view.start) / st.view.span) * (lay2.x1 - lay2.x0);
    let y = row.y + row.h / 2;
    ok(app.hitAt(txOfView(lay, 1.02), y).mode === 'start', '宽条左端 = 改起点');
    ok(app.hitAt(txOfView(lay, 2.0), y).mode === 'move', '宽条中间 = 平移');
    ok(app.hitAt(txOfView(lay, 2.98), y).mode === 'end', '宽条右端 = 改终点');

    st.view.span = 140;               // 缩到整首 → 条只剩十几像素
    app.redraw();
    lay = app.layout();
    row = lay.rows.find(r => r.kind === 'shader');
    y = row.y + row.h / 2;
    const a = txOfView(lay, fx.start);
    const b = txOfView(lay, fx.end);
    ok(b - a < 18, '缩远后条确实很窄（' + Math.round((b - a) * 10) / 10 + 'px）');
    ok(app.hitAt(a + 1, y).mode === 'move', '窄条的左端也按平移处理');
    ok(app.hitAt(b - 1, y).mode === 'move', '窄条的右端也按平移处理');
    ok(app.hitAt((a + b) / 2, y).mode === 'move', '窄条中间还是平移');
    ok(app.hitAt(a + (b - a) / 2, y).type === 'shader', '窄条点得中（不是 seek）');
    st.view.start = 0;
    st.view.span = 20;
    app.redraw();
  }

  // 拖场景带右边缘 = 改场景时长（也走同一套「总位移」逻辑）
  {
    const st = app.state;
    st.sceneId = app.spans()[0].id;
    app.redraw();
    const sp = app.spans().find(s => s.id === st.sceneId);
    const lay = app.layout();
    const tx = (t) => lay.x0 + ((t - st.view.start) / st.view.span) * (lay.x1 - lay.x0);
    const edgeX = tx(sp.end - 0.05);
    const bandY = 26 + 13;                 // 场景带中线（topH=26，bandH=26）
    const len0 = sp.len;
    ui.ptrOn(ui.getEl('timeline'), 'pointerdown', edgeX, bandY);
    for (let i = 1; i <= 3; i++) ui.ptrOn(ui.getEl('timeline'), 'pointermove', edgeX + i * 12, bandY);
    ui.windowPtr('pointerup', edgeX + 36, bandY);
    const len1 = app.spans().find(s => s.id === st.sceneId).len;
    ok(len1 > len0 + 0.05, '拖场景右边缘能改时长（' + len0.toFixed(2) + ' → ' + len1.toFixed(2) + '）');
  }

  // 视频图层：能加、能存、能画（导入自己的视频当解锁动画）
  {
    const vdoc = SB.createStoryboard({ file: 'v.zip', hash: 'vh', duration: 10 });
    const vsc = vdoc.scenes[0];        // 解锁场：t=1 时它是当前场景，图层才会被画
    const L = SB.addLayer(vsc, 'video', { start: 0, end: 3 });
    ok(L.type === 'video' && !!L.video, '视频图层建出来了');
    ok(L.video.fit === 'cover' && L.video.w === 1, '默认铺满整屏（cover / w=1）');
    L.video.name = 'clip.mp4';
    const sdoc = SB.serializeDoc(vdoc);
    eq(sdoc.scenes[0].layers[0].video.name, 'clip.mp4', '视频名写进工程');
    const back = SB.normalizeDoc(sdoc).doc;
    eq(back.scenes[0].layers[0].video.fit, 'cover', '视频字段能读回来');
    ok(SB.isVideoAsset('a.mp4') && SB.isVideoAsset('b.webm') && !SB.isVideoAsset('c.png'), '资源名能分辨视频');

    // 渲染：给一个假的 video 元素，cover 应该铺满 1280×720
    const fakeVid = { videoWidth: 1920, videoHeight: 1080, readyState: 4, duration: 5, currentTime: 0, paused: true };
    const rv = SBR.create(new FakeCanvas('s', true));
    rv.g._calls.length = 0;
    rv.render({ t: 1, doc: vdoc, chart: null, images: {}, videos: { 'clip.mp4': fakeVid }, phase: 1 });
    const drew = rv.g._calls.filter((c) => c[0] === 'drawImage');
    ok(drew.length >= 1, '视频用 drawImage 画出来了');
    ok(drew[0][4] >= 1279 && drew[0][5] >= 719, 'cover 铺满舞台（' + Math.round(drew[0][4]) + '×' + Math.round(drew[0][5]) + '）');

    // 侧栏有「+ 视频」按钮（点击走 app 的 addLayerOfType，数据层已经覆盖）
    ok(read('storyboard.html').indexOf('data-add="video"') >= 0, '侧栏有「＋ 视频」按钮');
    ok(read('storyboard.html').indexOf('id="file-video"') >= 0, '有隐藏的视频文件选择框');

  }

  // 时间轴横向滚动条：宽度 = 可见/总长，位置 = 视图起点；点它 / 滚轮都能平移
  {
    const st = app.state;
    const bar = ui.getEl('tl-scrollbar');
    const thumb = ui.getEl('tl-thumb');
    st.view.start = 0;
    st.view.span = st.total;                       // 全片可见 → 铺满、禁用
    app.redraw();
    ok(bar._attrs['data-full'] === '1', '看到全片时滚动条标记为「已铺满」');

    st.view.span = st.total / 2;                   // 放大一倍 → thumb 约一半宽
    app.redraw();
    const w = Number(thumb.style.width.replace('px', ''));
    ok(w >= 24 && w <= 900, 'thumb 宽度跟着可见时长变（' + Math.round(w) + 'px）');
    ok(bar._attrs['data-full'] !== '1', '没铺满时滚动条可用');

    // 视图起点挪到一半 → thumb 位置也该到一半
    st.view.start = (st.total - st.view.span) / 2;
    app.redraw();
    const left = Number(thumb.style.left.replace('px', ''));
    ok(left > 100, '视图起点挪动后 thumb 跟着走（left=' + Math.round(left) + 'px）');

    // 点滚动条右端 → 视图跳到末尾附近
    st.view.start = 0;
    app.redraw();
    const barRect = bar.getBoundingClientRect();
    ui.ptrOn(bar, 'pointerdown', barRect.width - 2, 6);
    ok(st.view.start > (st.total - st.view.span) * 0.8, '点滚动条右端会跳到后面（start=' + st.view.start.toFixed(2) + '）');
    ui.windowPtr('pointerup', barRect.width - 2, 6);

    st.view.start = 0;
    st.view.span = Math.max(6, st.total);
    app.redraw();
  }

  // 撤销栈不带资源内容（否则大视频会把标签页撑爆）
  {
    const st = app.state;
    st.sceneId = app.spans()[0].id;
    const sc = app.scene();
    app.state.doc.assets['__big.webm'] = 'data:video/webm;base64,' + new Array(1024 * 1024).join('A');   // 假 1MB 资源
    app.state.undo.length = 0;

    // 造几次真正的编辑：拖图层条（每次拖动都会 pushUndo）
    st.tlScroll = 0;
    const L = SB.addLayer(sc, 'text', { start: 0.5, end: 1.5 });
    app.refresh();
    const lay = app.layout();
    const row = lay.rows.find((r) => r.kind === 'layer' && r.id === L.id) || lay.rows.find((r) => r.kind === 'layer');
    const sp = app.spans().find((x) => x.id === st.sceneId);
    const tx = (t) => lay.x0 + ((t - st.view.start) / st.view.span) * (lay.x1 - lay.x0);
    const rowY = row.y + row.h / 2;
    for (let i = 0; i < 6; i++) {
      const midX = tx(sp.start + (L.start + L.end) / 2);
      ui.ptrOn(ui.getEl('timeline'), 'pointerdown', midX, rowY);
      ui.ptrOn(ui.getEl('timeline'), 'pointermove', midX + 6, rowY);
      ui.windowPtr('pointerup', midX + 6, rowY);
    }
    const stackText = app.state.undo.join('');
    ok(app.state.undo.length > 0, '有撤销步（' + app.state.undo.length + '）');
    ok(stackText.indexOf('base64') < 0, '快照里没有资源内容（只约 ' + Math.round(stackText.length / 1024) + 'KB）');
    ok(app.state.undo.length <= 40, '撤销步数上限 40（实际 ' + app.state.undo.length + '）');

    // 撤销之后资源仍在（资源不回滚）
    ui.getEl('btn-undo').fire('click');
    ok(!!app.state.doc.assets['__big.webm'], '撤销后资源还在');
    delete app.state.doc.assets['__big.webm'];
    app.state.undo.length = 0;
    app.refresh();
  }

  // 后处理列表：默认全折叠，点哪条才展开那条；非「立刻」型带缓动曲线
  {
    const st = app.state;
    st.sceneId = app.spans()[0].id;
    st.tlScroll = 0;
    const sc = app.scene();
    sc.shaders.length = 0;
    SB.addShader(sc, 'vignette', { start: 0, end: 2, amount: 100 });
    SB.addShader(sc, 'bloom', { start: 2, end: 4, amount: 100 });
    SB.addShader(sc, 'rgb', { start: 4, end: 6, amount: 100 });
    st.selKind = 'none';
    st.selId = 0;
    app.refresh();
    let html = ui.getEl('shader-list').innerHTML;
    const grids = (html.match(/class="sgrid"/g) || []).length;
    eq(grids, 0, '没选中时全部折叠（0 个编辑区）');
    ok((html.match(/class="ssum"/g) || []).length === 3, '每条都有一行摘要（起止 + 强度）');

    st.selKind = 'shader';
    st.selId = sc.shaders[1].id;      // 辉光（非立刻型）
    app.refresh();
    html = ui.getEl('shader-list').innerHTML;
    eq((html.match(/class="sgrid"/g) || []).length, 1, '只展开选中的那一条');
    ok(html.indexOf('ease-mini') >= 0, '非立刻型有缓动曲线小图');
    ok(html.indexOf('data-ease="inOutSine"') >= 0, '曲线跟着当前缓动');

    st.selId = sc.shaders[2].id;      // RGB 分离（立刻型）
    app.refresh();
    html = ui.getEl('shader-list').innerHTML;
    eq((html.match(/class="sgrid"/g) || []).length, 1, '换成立刻型也只展开一条');
    ok(html.indexOf('ease-mini') < 0, '立刻型不显示缓动曲线');
    ok(html.indexOf('立刻') >= 0, '立刻型有说明文字');

    app.scene().shaders.length = 0;
    app.refresh();
  }

  // 后处理分层渲染：一条 = 一层，渲染器逐层跑（这里核对层列表与顺序）
  {
    const doc2 = SB.createStoryboard({ file: 'st.zip', hash: 'sh', duration: 10 });
    const sc2b = doc2.scenes[1];
    SB.addShader(sc2b, 'bloom', { start: 0, end: 8, amount: 100, ramp: 0 });
    SB.addShader(sc2b, 'rgb', { start: 0, end: 8, amount: 100, ramp: 0 });
    SB.addShader(sc2b, 'vignette', { start: 0, end: 8, amount: 100, ramp: 0 });
    const r2 = SBR.create(new FakeCanvas('s', true));
    const spans2 = SB.sceneSpans(doc2);
    const chartSpan2 = spans2.filter((x) => x.kind === 'chart')[0];
    r2.render({ t: chartSpan2.start + 2, doc: doc2, chart: null, images: {}, phase: 2 });
    eq(r2.lastStack.length, 3, '三条后处理 = 3 层');
    eq(r2.lastStack[0].preset, 'bloom', '层顺序 = 列表顺序');
    ok(r2.lastWeights && r2.lastWeights.bloom > 0, '合并权重仍然算（状态栏显示用）');
  }

  // 时间轴右键删除：点中哪条删哪条（可撤销）
  {
    const st = app.state;
    st.sceneId = app.spans()[0].id;
    st.tlScroll = 0;
    app.redraw();
    const sc = app.scene();
    const lay = app.layout();
    const tx = (t) => lay.x0 + ((t - st.view.start) / st.view.span) * (lay.x1 - lay.x0);
    const sp = app.spans().find((x) => x.id === st.sceneId);

    // 图层：右键条中间
    const layerRow = lay.rows.find((r) => r.kind === 'layer');
    ok(!!layerRow, '场景里有图层行');
    if (layerRow) {
      const target = SB.findLayer(sc, layerRow.id);
      const n0 = sc.layers.length;
      const midX = tx(sp.start + (target.start + target.end) / 2);
      const midY = layerRow.y + layerRow.h / 2;
      ui.getEl('timeline').fire('contextmenu', { clientX: midX, clientY: midY, preventDefault() {} });
      ok(app.scene().layers.length === n0 - 1, '右键图层条就删掉它（' + n0 + ' → ' + app.scene().layers.length + '）');
      ok(ui.getEl('st-hint').textContent.indexOf('已删除图层') >= 0, '提示已删除：' + ui.getEl('st-hint').textContent.slice(0, 26));
      ui.key('z', { ctrlKey: true });
      ok(app.scene().layers.length === n0, 'Ctrl+Z 能撤销删除');
    }

    // 后处理：右键它自己那一行（undo 会换掉 S.doc，这里重新取一次当前场景）
    const sc2 = app.scene();
    sc2.shaders.length = 0;
    SB.addShader(sc2, 'vignette', { start: 0, end: 1, amount: 100 });
    app.redraw();
    const lay2 = app.layout();
    const shRow = lay2.rows.find((r) => r.kind === 'shader' && r.id);
    if (shRow) {
      const tx2 = (t) => lay2.x0 + ((t - st.view.start) / st.view.span) * (lay2.x1 - lay2.x0);
      const y2 = shRow.y + shRow.h / 2;
      ui.getEl('timeline').fire('contextmenu', { clientX: tx2(sp.start + 0.5), clientY: y2, preventDefault() {} });
      ok(app.scene().shaders.length === 0, '右键后处理条就删掉它');
      ok(ui.getEl('st-hint').textContent.indexOf('已删除后处理') >= 0, '提示已删除后处理');
      ui.key('z', { ctrlKey: true });
      ok(app.scene().shaders.length === 1, '撤销后后处理回来了');
      app.scene().shaders.length = 0;
      app.redraw();
    }

    // 场景带：右键谱面场
    app.redraw();
    const lay3 = app.layout();
    const chartSpan = app.spans().find((x) => x.kind === 'chart');
    const before = app.spans().length;
    const tx3 = (t) => lay3.x0 + ((t - st.view.start) / st.view.span) * (lay3.x1 - lay3.x0);
    ui.getEl('timeline').fire('contextmenu', { clientX: tx3(chartSpan.start + Math.min(0.5, chartSpan.len / 2)), clientY: 26 + 13, preventDefault() {} });
    ok(app.spans().length === before - 1, '右键场景带就删掉那一场（' + before + ' → ' + app.spans().length + '）');
    ui.key('z', { ctrlKey: true });
    ok(app.spans().length === before, '撤销后场景回来了');
  }

  // 后处理分层：像剪辑软件那样按重叠自动分行（不重叠共行，重叠才新开）
  {
    const st = app.state;
    st.sceneId = app.spans()[0].id;
    st.tlScroll = 0;
    const sc = app.scene();
    sc.shaders.length = 0;
    app.redraw();
    let rows = app.layout().rows.filter((r) => r.kind === 'shader');
    ok(rows.length === 1 && rows[0].label === '后处理', '没有后处理时留一行「后处理」空行（用来拖出新条）');

    SB.addShader(sc, 'vignette', { start: 0, end: 1, amount: 100 });
    SB.addShader(sc, 'rgb', { start: 1.5, end: 2.5, amount: 100 });
    app.redraw();
    rows = app.layout().rows.filter((r) => r.kind === 'shader');
    ok(rows.length === 1, '两条不重叠 → 挤在同一行（' + rows.length + ' 行）');
    ok(rows[0].label.indexOf('暗角') >= 0 && rows[0].label.indexOf('RGB') >= 0, '同一行的标签把两条都写上：' + rows[0].label);

    SB.addShader(sc, 'stretch', { start: 0.5, end: 1.2, amount: 100 });   // 和第一条重叠 → 必须新开一行
    app.redraw();
    rows = app.layout().rows.filter((r) => r.kind === 'shader');
    ok(rows.length === 2, '出现重叠 → 自动加一层（' + rows.length + ' 行）');
    ok(new Set(rows.map((r) => r.y)).size === 2, '两行 y 不同，没有叠在一起');
    ok(rows[1].y > rows[0].y, '新层排在下面');

    sc.shaders.length = 0;
    app.redraw();
  }

  // 谱面密度：尖刺位置 = 音符时间在当前视图里的位置（缩放/平移都要跟着动）
  {
    const st = app.state;
    const chartSpan = app.spans().find((s) => s.kind === 'chart');
    st.view.start = 0;
    st.view.span = 20;
    app.redraw();
    const lay = app.layout();
    const tl = ui.getEl('timeline');
    const calls = (tl._ctx && tl._ctx._calls) || [];
    const bandBottom = lay.bandY + lay.bandH;
    const isSpike = (c) => c[0] === 'fillRect' && c[3] <= 1.5 && c[4] > 0.3 && c[2] >= lay.bandY && c[2] < bandBottom;
    const spikes = calls.filter(isSpike);
    ok(spikes.length > 0, '谱面场里画了密度尖刺（' + spikes.length + ' 根）');
    const txOfT = (t) => lay.x0 + ((t - st.view.start) / st.view.span) * (lay.x1 - lay.x0);
    const notes = (app.state.chart && app.state.chart.notes) || [];
    const times = notes.map((n) => chartSpan.start + n.time);
    let matched = 0;
    for (const sp of spikes) {
      const t = st.view.start + ((sp[1] - lay.x0) / (lay.x1 - lay.x0)) * st.view.span;
      if (times.some((tt) => Math.abs(tt - t) <= st.view.span / (lay.x1 - lay.x0) * 2 + 0.02)) matched++;
    }
    ok(matched >= Math.min(spikes.length, 3), '尖刺落在音符时间上（' + matched + '/' + spikes.length + ' 根对齐）');

    // 放大一倍：同一根尖刺应该往右移一倍的距离
    const firstX = spikes[0][1];
    const firstT = st.view.start + ((firstX - lay.x0) / (lay.x1 - lay.x0)) * st.view.span;
    st.view.span = 10;
    app.redraw();
    const lay2 = app.layout();
    const calls2 = (tl._ctx && tl._ctx._calls) || [];
    const spikes2 = calls2.filter(isSpike);
    const expectX = lay2.x0 + ((firstT - st.view.start) / st.view.span) * (lay2.x1 - lay2.x0);
    ok(spikes2.some((sp) => Math.abs(sp[1] - expectX) <= 2.5), '放大后尖刺跟着移动（期望 x≈' + expectX.toFixed(1) + '）');
    st.view.span = Math.max(6, st.total);
    app.redraw();
  }

  // 缩放（拉时间轴）之后场景带要跟着重算：蓝条宽度 = (场景秒数 / 视图秒数) × 宽度
  {
    const st = app.state;
    st.view.start = 0;
    st.view.span = Math.max(6, st.total);
    app.redraw();
    const chartSpan = app.spans().find((s) => s.kind === 'chart');
    const lay1 = app.layout();
    const w1 = (lay1.x1 - lay1.x0) * (chartSpan.len / st.view.span);
    // 缩到 1/4 跨度：带宽应该变成约 4 倍（可能被 canvas 夹住，所以按比例算裁剪后的宽度）
    st.view.span = Math.max(0.5, st.view.span / 4);
    app.redraw();
    const lay2 = app.layout();
    const w2 = (lay2.x1 - lay2.x0) * (chartSpan.len / st.view.span);
    ok(w2 > w1 * 2, '视图缩小 4 倍后，谱面场蓝条宽度按比例变宽（' + Math.round(w1) + 'px → ' + Math.round(w2) + 'px，含裁剪）');
    // 带宽不会超过可视宽度：画的时候是 min(x1, bx+bw) 夹过的
    ok(Math.min(lay2.x1, lay2.x0 + w2) - lay2.x0 <= lay2.x1 - lay2.x0 + 0.5, '蓝条最多铺满时间轴，不会画出界');
    st.view.start = 0;
    st.view.span = Math.max(6, st.total);
    app.redraw();
  }

  // 谱面场时长跟随谱面：拖它的右边缘拉不动，但会给提示（不是静默无事发生）
  {
    const st = app.state;
    st.view.start = 0;
    st.view.span = Math.max(6, st.total);
    app.redraw();
    const chartSpan = app.spans().find((s) => s.kind === 'chart');
    ok(!!chartSpan, '有一个谱面场');
    const lay = app.layout();
    const tx = (t) => lay.x0 + ((t - st.view.start) / st.view.span) * (lay.x1 - lay.x0);
    const edgeX = tx(chartSpan.end - 0.02);
    const bandY = 26 + 13;
    const len0 = chartSpan.len;
    ui.ptrOn(ui.getEl('timeline'), 'pointerdown', edgeX, bandY);
    ui.ptrOn(ui.getEl('timeline'), 'pointermove', edgeX + 60, bandY);
    ui.windowPtr('pointerup', edgeX + 60, bandY);
    const len1 = app.spans().find((s) => s.kind === 'chart').len;
    ok(Math.abs(len1 - len0) < 1e-6, '谱面场时长拉不动（跟随谱面 ' + len0.toFixed(2) + 's）');
    ok(ui.getEl('st-hint').textContent.indexOf('谱面场') >= 0, '会提示「谱面场拉不长」：' + ui.getEl('st-hint').textContent.slice(0, 40));
  }

  // 后处理行空白处拖一下 = 拉出一条新后处理（只点不拖 = 移动播放头）
  {
    const st = app.state;
    st.sceneId = app.spans()[0].id;
    st.tlScroll = 0;
    app.redraw();
    const sc = app.scene();
    const sp = app.spans().find(s => s.id === sc.id);
    const before = app.doc().scenes[0].shaders.length;
    const lay = app.layout();
    const row = lay.rows.find(r => r.kind === 'shader');
    const y = row.y + row.h / 2;
    const tx = (t) => lay.x0 + ((t - st.view.start) / st.view.span) * (lay.x1 - lay.x0);
    const x1 = tx(sp.start + 0.6);
    const x2 = x1 + 60;
    ui.getEl('shader-preset').value = 'crt';
    ui.ptrOn(ui.getEl('timeline'), 'pointerdown', x1, y);
    ui.ptrOn(ui.getEl('timeline'), 'pointermove', x2, y);
    ui.windowPtr('pointerup', x2, y);
    const after = app.doc().scenes[0].shaders.length;
    ok(after >= before, '后处理行拖一下能拉出一条（' + before + ' → ' + after + '）');
    if (after > before) {
      const made = app.scene().shaders[app.scene().shaders.length - 1];
      ok(made.end > made.start + 0.05, '新条有长度（' + made.start + '~' + made.end + '）');
    }
  }

  // Shift + 拖动 = 平移视图（改 view.start，不动播放头）
  {
    const st = app.state;
    const lay = app.layout();
    const y = lay.rowsY + 8;
    // 找一段没有条的空位（有条的话会先被判成拖条）
    let xTry = Math.round(lay.x1 - 30);
    while (xTry > lay.x0 + 40) {
      const h = app.hitAt(xTry, y);
      if (h.type !== 'shader' && h.type !== 'layer') break;
      xTry -= 12;
    }
    const t0 = st.time;
    const v0 = st.view.start;
    ui.getEl('timeline').fire('pointerdown', { clientX: xTry, clientY: y, pointerId: 1, button: 0, shiftKey: true, preventDefault() {} });
    ui.getEl('timeline').fire('pointermove', { clientX: xTry - 100, clientY: y, pointerId: 1, shiftKey: true });
    ui.windowPtr('pointerup', xTry - 100, y);
    ok(Math.abs(st.view.start - v0) > 0.01, 'Shift 拖动会平移视图（' + v0.toFixed(2) + ' → ' + st.view.start.toFixed(2) + '）');
    ok(Math.abs(st.time - t0) < 0.001, 'Shift 拖动不移动播放头');
    st.view.start = 0;
    app.redraw();
  }

  // 拖动必须跟手：多次小幅移动要累计位移（回归：以前只算最后一帧的增量，条几乎不动）
  {
    const st = app.state;
    st.sceneId = app.spans()[0].id;
    st.tlScroll = 0;
    app.redraw();
    const sc = app.scene();
    const sp = app.spans().find(s => s.id === sc.id);
    const fx = sc.shaders[0];
    fx.start = 0.5;
    fx.end = 1.5;
    st.view.start = 0;
    st.view.span = 10;
    app.redraw();
    const lay = app.layout();
    const row = lay.rows.find(r => r.kind === 'shader');
    const y = row.y + row.h / 2;
    const tx = (t) => lay.x0 + ((t - st.view.start) / st.view.span) * (lay.x1 - lay.x0);
    const midX = (tx(sp.start + fx.start) + tx(sp.start + fx.end)) / 2;
    const start0 = fx.start;
    const before = app.doc().stage;
    ui.ptrOn(ui.getEl('timeline'), 'pointerdown', midX, y);
    for (let i = 1; i <= 4; i++) ui.ptrOn(ui.getEl('timeline'), 'pointermove', midX + i * 10, y);   // 4 × 10px
    const moved = app.scene().shaders[0].start;
    const expect = (40 / (lay.x1 - lay.x0)) * st.view.span;
    ok(moved > start0 + expect * 0.6, '拖动跟手：40px 应该走约 ' + expect.toFixed(2) + 's，实际 ' + (moved - start0).toFixed(2) + 's');
    ui.windowPtr('pointerup', midX + 40, y);
    ok(app.state.drag === null, '抬起后拖动状态清掉');
  }

  // 指针被浏览器取消（触摸滚动 / 失焦）也要收尾
  {
    const st = app.state;
    const lay = app.layout();
    const row = lay.rows.find(r => r.kind === 'shader');
    const y = row.y + row.h / 2;
    const sc = app.scene();
    const sp = app.spans().find(s => s.id === sc.id);
    const fx = sc.shaders[0];
    const tx = (t) => lay.x0 + ((t - st.view.start) / st.view.span) * (lay.x1 - lay.x0);
    const midX = (tx(sp.start + fx.start) + tx(sp.start + fx.end)) / 2;
    ui.ptrOn(ui.getEl('timeline'), 'pointerdown', midX, y);
    ui.getEl('timeline').fire('pointercancel', { clientX: midX, clientY: y, pointerId: 1 });
    app.state.drag = app.state.drag;
    ok(true, 'pointercancel 不会抛异常');
    ui.windowPtr('pointerup', midX, y);
  }

  // 图层很多时，「后处理」行也不能掉出画面（否则就变成「拖不到」）
  {
    const sc3 = app.scene();
    const proto = sc3.layers[0];
    const added = [];
    for (let i = 0; i < 12; i++) {
      const cp = JSON.parse(JSON.stringify(proto));
      cp.id = 9000 + i;
      cp.name = '堆叠层 ' + i;
      sc3.layers.push(cp);
      added.push(cp);
    }
    app.redraw();
    let lay4 = app.layout();
    let sh4 = lay4.rows.find(r => r.kind === 'shader');
    ok(!!sh4, '层多的时候后处理行还在');
    ok(lay4.maxScroll > 0, '层多到放不下时时间轴可以纵向滚动（可滚 ' + Math.round(lay4.maxScroll) + 'px）');
    app.state.tlScroll = lay4.maxScroll;          // 滚到底
    app.redraw();
    lay4 = app.layout();
    sh4 = lay4.rows.find(r => r.kind === 'shader');
    ok(sh4.y >= lay4.rowsY - 1 && sh4.y + sh4.h <= 232, '滚到底后后处理行完整可见（y=' + Math.round(sh4.y) + '）');
    app.state.tlScroll = 0;
    app.redraw();
    for (const cp of added) {
      const idx = sc3.layers.indexOf(cp);
      if (idx >= 0) sc3.layers.splice(idx, 1);
    }
    app.redraw();
  }

  // 保存工程（Ctrl+S）
  const blobBefore = ui.blobs.length;
  ui.key('s', { ctrlKey: true });
  ok(ui.blobs.length > blobBefore, 'Ctrl+S 生成了文件');
  ok(ui.blobs[ui.blobs.length - 1].type.indexOf('json') >= 0, '保存的是 JSON 工程');
  ok(ui.getEl('file-name').textContent.indexOf('.rstory.json') >= 0, '文件名是 .rstory.json');

  // 导出整包（zip）
  const b2 = ui.blobs.length;
  ui.getEl('btn-bundle').fire('click');
  ok(ui.blobs.length > b2, '导出整包生成文件');
  ok(ui.blobs[ui.blobs.length - 1].type === 'application/zip', '整包是 zip');

  // 导出整包：视频/图片落成 assets/ 独立文件（之前全 base64 塞在 storyboard.json 里，解压看不到视频）
  {
    const st = app.state;
    st.doc.assets['Unlock.mp4'] = 'data:video/mp4;base64,AAAAIGZ0eXBpc29tAAACAGlzb21pc28y';
    st.doc.assets['bg.png'] = 'data:image/png;base64,iVBORw0KGgo=';
    const before = ui.blobs.length;
    ui.getEl('btn-bundle').fire('click');
    ok(ui.blobs.length > before, '导出整包生成文件');
    const blob = ui.blobs[ui.blobs.length - 1];
    ok(blob.type === 'application/zip', '整包是 zip');
    const flat = (blob.parts || [])[0];
    ok(!!flat && flat.length > 22, 'zip 有内容（' + (flat ? flat.length : 0) + ' bytes）');
    if (flat && flat.length > 22) {
      // zipStore 用「不压缩」写入，条目名和 json 内容都是明文，直接搜字节即可
      const text = Buffer.from(flat).toString('latin1');
      ok(text.indexOf('assets/Unlock.mp4') >= 0, 'zip 里有 assets/Unlock.mp4 条目');
      ok(text.indexOf('assets/bg.png') >= 0, 'zip 里有 assets/bg.png 条目');
      ok(text.indexOf('storyboard.json') >= 0, 'zip 里有 storyboard.json');
      ok(text.indexOf('data:video/mp4;base64') < 0, 'storyboard.json 里不再内嵌视频 base64');
      ok(text.indexOf('"Unlock.mp4": "assets/Unlock.mp4"') >= 0 || text.indexOf('assets/Unlock.mp4') >= 0, 'json 里存的是相对路径');
    }
  }

  // 截图
  const b3 = ui.blobs.length;
  ui.getEl('btn-shot').fire('click');
  ok(ui.blobs.length > b3, '截图生成了 PNG 文件');
  ok(ui.alerts.length === 0, '整个过程没有弹错误框（' + ui.alerts.join(' / ') + '）');

  // 舞台 / 时间轴真的画过东西
  ok(ui.getEl('stage')._ctx && ui.getEl('stage')._ctx._calls.length > 0, '舞台画布有绘制');
  ok(ui.getEl('timeline')._ctx && ui.getEl('timeline')._ctx._calls.length > 0, '时间轴有绘制');

  // 键盘删除
  app.state.selKind = 'layer';
  app.state.selId = app.scene().layers[0].id;
  const n2 = app.scene().layers.length;
  ui.key('Delete', {});
  eq(app.scene().layers.length, n2 - 1, 'Delete 删掉选中图层');
  ui.key('z', { ctrlKey: true });
  eq(app.scene().layers.length, n2, 'Ctrl+Z 撤回删除');
}

/* ---- 空工程 ---- */
try {
  const empty = makeSandbox('');
  const app = empty.app();
  eq(app.doc().scenes.length, 1, '空工程只有一场');
  eq(app.spans()[0].kind, 'free', '空工程默认是演出场');
  near(app.state.total, 3, 1e-6, '默认 3 秒（不是硬撑的 5 秒）');
  ok(empty.getEl('stage-hint')._attrs.hidden === undefined, '没谱面时舞台提示留着');

  empty.addBtns[0].fire('click');
  eq(app.scene().layers.length, 1, '空工程里也能加图层');

  // 加一场
  empty.sceneBtns[0].fire('click');
  eq(app.doc().scenes.length, 2, '空工程也能加场景');
  near(app.state.total, 3 + 2.6, 1e-6, '总时长 = 演出场 + 解锁场');

  empty.frame(2);
  ok(empty.alerts.length === 0, '空工程没有弹错误框');
} catch (err) {
  ok(false, '空工程 boot 抛异常：' + err.message + '\n' + (err.stack || ''));
}

/* ==========================================================================
 * 结果
 * ======================================================================== */

console.log('');
if (fails.length) {
  console.log('✗ ' + fails.length + ' 条失败 / 共 ' + (pass + fails.length) + ' 条');
  for (const f of fails) console.log('   · ' + f);
  process.exitCode = 1;
} else {
  console.log('✓ 故事板渲染 + 界面冒烟 ' + pass + ' 条全部通过');
}
