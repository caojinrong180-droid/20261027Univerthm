/* 故事板数据层单元测试：node web/test/sb.test.js */
'use strict';

const RC = require('../js/core.js');
const SB = require('../js/sb_core.js');
const CS = require('../js/chart_stage.js');

let pass = 0;
const fails = [];

function ok(cond, name) {
  if (cond) pass++;
  else fails.push(name);
}

function eq(a, b, name) {
  const good = JSON.stringify(a) === JSON.stringify(b);
  if (!good) fails.push(name + '  →  实际 ' + JSON.stringify(a) + ' / 期望 ' + JSON.stringify(b));
  else pass++;
}

function near(a, b, eps, name) {
  const good = Math.abs(a - b) <= (eps === undefined ? 1e-6 : eps);
  if (!good) fails.push(name + '  →  实际 ' + a + ' / 期望 ' + b);
  else pass++;
}


/* ---------------- 工具函数 ---------------- */

eq(SB.hashText('abc'), SB.hashText('abc'), 'hashText 稳定');
ok(SB.hashText('abc') !== SB.hashText('abd'), 'hashText 能区分不同文本');
eq(SB.hashText('').length, 8, 'hashText 返回 8 位');
eq(SB.hexA('#ff8000', 0.5), 'rgba(255,128,0,0.5)', 'hexA');
eq(SB.hexA('', 1), 'rgba(255,255,255,1)', 'hexA 兜底');
near(SB.ease('outCubic', 0.5), 0.875, 1e-9, 'ease 借 core 的实现');

/* ---------------- 谱面引用 ---------------- */

const chart = RC.createChart({ lane_count: 4 });
chart.meta.title = 'Neon Pulse';
chart.meta.artist = 'Synth Engine';
chart.meta.charter = '我';
chart.meta.difficulty = 'HARD';
chart.meta.level = 8;
chart.notes.push({ id: 1, time: 1.0, lane: 0, type: 'tap' });
chart.notes.push({ id: 2, time: 2.5, lane: 1, type: 'hold', duration: 0.8 });

const digest = SB.chartDigest(chart, { file: 'Neon Pulse.zip', hash: SB.hashText('{}') });
eq(digest.title, 'Neon Pulse', 'digest 曲名');
eq(digest.artist, 'Synth Engine', 'digest 艺术家');
eq(digest.difficulty, 'HARD', 'digest 难度');
eq(digest.level, 8, 'digest 等级');
eq(digest.notes, 2, 'digest 音符数');
eq(digest.duration, 3.3, 'digest 时长（含 hold 尾巴）');
eq(digest.lanes, 4, 'digest 轨道数');
eq(digest.file, 'Neon Pulse.zip', 'digest 文件名');
eq(digest.hash.length, 8, 'digest 指纹');

const emptyDigest = SB.emptyDigest();
eq(SB.createStoryboard().chart.title, '未命名谱面', '空工程谱面引用默认值');

/* ---------------- 曲绘作者 ---------------- */

eq(SB.createStoryboard(digest).meta.coverArtist, '', '曲绘作者默认空串');
eq(SB.normalizeDoc({ meta: { coverArtist: 'Yuki' }, scenes: [{ kind: 'free' }] }).doc.meta.coverArtist, 'Yuki', '曲绘作者读得回来');
const illustDoc = SB.createStoryboard(digest);
illustDoc.meta.coverArtist = 'Curtain';
eq(SB.serializeDoc(illustDoc).meta.coverArtist, 'Curtain', '导出带曲绘作者');
eq(SB.normalizeDoc(JSON.parse(JSON.stringify(SB.serializeDoc(illustDoc)))).doc.meta.coverArtist, 'Curtain', '曲绘作者往返一致');
eq(SB.fillText('ILLUSTRATION  {illust}', chart.meta, { coverArtist: 'Curtain' }), 'ILLUSTRATION  Curtain', '占位符 {illust}');
eq(SB.fillText('by {illust}', chart.meta), 'by ', '没有曲绘作者时 {illust} 变空（不报错）');

const illustChart = Object.assign({}, chart, { meta: Object.assign({}, chart.meta, { illustrator: 'Yuki' }) });
eq(SB.chartDigest(illustChart, {}).illustrator, 'Yuki', '谱面的曲绘画师进引用');
eq(SB.chartDigest(chart, {}).illustrator, '', '谱面没填就是空串');
eq(SB.fillText('{illust}', illustChart.meta, {}), 'Yuki', '{illust} 没填时用谱面的画师');
eq(SB.fillText('{illust}', illustChart.meta, { coverArtist: 'Curtain' }), 'Curtain', '故事板填的画师优先');

/* ---------------- 视频图层 ---------------- */

const vdoc = SB.createStoryboard(digest);
const vLayer = SB.addLayer(vdoc.scenes[1], 'video', { start: 0, end: 3 });
eq(vLayer.type, 'video', '视频图层类型');
eq(vLayer.video.fit, 'cover', '默认铺满裁剪');
eq(vLayer.video.w, 1, '默认宽度占满');
vLayer.video.name = 'clip.mp4';
const vOut = SB.serializeDoc(vdoc);
eq(vOut.scenes[1].layers[0].video.name, 'clip.mp4', '视频名写进工程');
eq(SB.normalizeDoc(vOut).doc.scenes[1].layers[0].video.fit, 'cover', '视频字段往返');
ok(SB.isVideoAsset('a.mp4') && SB.isVideoAsset('b.WEBM') && !SB.isVideoAsset('c.png'), '视频资源名识别');

/* ---------------- 谱面基准 ---------------- */

eq(SB.createStoryboard(digest).stage.chartBase, 350, '谱面基准默认 350（= 游戏逻辑舞台）');
eq(SB.normalizeDoc({ stage: { chartBase: 99 }, scenes: [{ kind: 'free' }] }).doc.stage.chartBase, 120, '基准宽下限夹到 120');
eq(SB.normalizeDoc({ stage: { chartBase: 5000 }, scenes: [{ kind: 'free' }] }).doc.stage.chartBase, 2560, '基准宽上限夹到 2560');
eq(SB.normalizeDoc({ scenes: [{ kind: 'free' }] }).doc.stage.chartBase, 350, '老工程没有基准字段就用 350');
eq(SB.serializeDoc(SB.createStoryboard(digest)).stage.chartBase, 350, '导出带谱面基准');
const baseDoc2 = SB.createStoryboard(digest);
baseDoc2.stage.chartBase = 1280;
eq(SB.normalizeDoc(JSON.parse(JSON.stringify(SB.serializeDoc(baseDoc2)))).doc.stage.chartBase, 1280, '谱面基准往返一致');

/* ---------------- 音量 ---------------- */

eq(SB.createStoryboard(digest).stage.volume, 100, '默认音量 100');
eq(SB.normalizeDoc({ stage: { volume: 150 }, scenes: [{ kind: 'free' }] }).doc.stage.volume, 100, '音量上限夹到 100');
eq(SB.normalizeDoc({ stage: { volume: -5 }, scenes: [{ kind: 'free' }] }).doc.stage.volume, 0, '音量下限夹到 0');
eq(SB.normalizeDoc({ stage: { volume: 42 }, scenes: [{ kind: 'free' }] }).doc.stage.volume, 42, '音量读得回来');
eq(SB.serializeDoc(SB.createStoryboard(digest)).stage.volume, 100, '导出带音量');
const volDoc = SB.createStoryboard(digest);
volDoc.stage.volume = 35;
near(SB.normalizeDoc(JSON.parse(JSON.stringify(SB.serializeDoc(volDoc)))).doc.stage.volume, 35, 1e-9, '音量往返一致');

/* ---------------- 场景 ---------------- */

const doc = SB.createStoryboard(digest);
eq(doc.format, 'rstory', 'format');
eq(doc.version, 2, '版本 2（带场景）');
eq(doc.scenes.length, 2, '有谱面时默认两场：解锁场 + 谱面场');
eq(doc.scenes[0].kind, 'unlock', '第一场是解锁场（在谱面之前）');
eq(doc.scenes[1].kind, 'chart', '第二场是谱面场');
eq(SB.sceneKind('nope'), 'free', '未知场景类型退回演出场');

const spans = SB.sceneSpans(doc);
eq(spans.length, 2, '场景区间两段');
near(spans[0].start, 0, 1e-9, '解锁场从 0 开始');
near(spans[0].end, 2.6, 1e-9, '解锁场 2.6 秒');
near(spans[1].start, 2.6, 1e-9, '谱面场接在解锁场后面');
near(spans[1].end, 2.6 + 3.3, 1e-9, '谱面场 = 谱面时长');
near(spans[1].len, 3.3, 1e-9, '谱面场时长跟随谱面');
near(SB.totalLength(doc), 5.9, 1e-9, '总时长 = 各场景之和');

let at = SB.sceneAt(doc, 1.0);
eq(at.span.kind, 'unlock', '1.0 秒在解锁场');
near(at.local, 1.0, 1e-9, '解锁场本地时间 = 全局时间');
at = SB.sceneAt(doc, 3.0);
eq(at.span.kind, 'chart', '3.0 秒在谱面场');
near(at.local, 0.4, 1e-9, '谱面场本地时间 = 全局 − 场景起点');
at = SB.sceneAt(doc, 99);
eq(at.span.kind, 'chart', '超出末尾时落在最后一场');
near(at.local, 3.3, 1e-9, '超末尾时本地时间夹到场景末尾');
near(SB.sceneAt(doc, -5).local, 0, 1e-9, '负数时间夹到第一场开头');

// 空谱面 → 只有一场演出场
const freeDoc = SB.createStoryboard();
eq(freeDoc.scenes.length, 1, '没谱面时默认一场');
eq(freeDoc.scenes[0].kind, 'free', '没谱面时是演出场');
near(SB.totalLength(freeDoc), 3, 1e-9, '演出场默认 3 秒');

// 加 / 删 / 挪场景
const sdoc = SB.createStoryboard(digest);
const outro = SB.addScene(sdoc, 'free', { name: '片尾', length: 4 });
eq(sdoc.scenes.length, 3, '加了一场');
eq(outro.name, '片尾', '场景名字');
near(SB.totalLength(sdoc), 2.6 + 3.3 + 4, 1e-9, '总时长把新场景算进去');
eq(SB.sceneIndex(sdoc, outro.id), 2, '新场景在末尾');
ok(SB.moveScene(sdoc, outro.id, -1), '往前挪一场');
eq(SB.sceneIndex(sdoc, outro.id), 1, '挪到中间');
eq(SB.sceneSpans(sdoc)[1].kind, 'free', '顺序真的变了');
eq(SB.removeScene(sdoc, outro.id), true, '删场景');
eq(sdoc.scenes.length, 2, '删掉了');
const onlyOne = SB.createStoryboard(digest);
eq(SB.removeScene(onlyOne, onlyOne.scenes[0].id), true, '两场时能删一场');
eq(SB.removeScene(onlyOne, onlyOne.scenes[0].id), false, '最后一场删不掉');

// 谱面场时长只读（跟随谱面）
const cdoc = SB.createStoryboard(digest);
const chartScene = cdoc.scenes[1];
eq(SB.sceneLen(cdoc, chartScene), 3.3, '谱面场时长 = 谱面时长');
chartScene.length = 99;
eq(SB.sceneLen(cdoc, chartScene), 3.3, '改谱面场 length 不生效');
cdoc.chart.duration = 10;
eq(SB.sceneLen(cdoc, chartScene), 10, '谱面换长了场景跟着长');

/* ---------------- 图层默认值与增删（都在场景里） ---------------- */

const sc0 = doc.scenes[0];
const tl = SB.addLayer(sc0, 'text', { start: 1, end: 3 });
eq(tl.id, 1, '第一个图层 id = 1');
eq(tl.type, 'text', '文字图层');
eq(tl.text, 'TITLE', '文字图层默认文本');
eq(tl.style.effect, 'glow', '文字默认特效');
eq(tl.in.preset, 'slideUp', '文字默认入场');
eq(SB.addLayer(sc0, 'unlock', { start: 0, end: 2.4 }).type, 'unlock', '加一个解锁动画');
eq(SB.addLayer(sc0, 'shape', { start: 0, end: 2 }).type, 'shape', '加一个形状');

const ul = sc0.layers[1];
eq(ul.unlock.preset, 'tape', '解锁默认预设');
eq(ul.in.preset, 'none', '解锁动画默认没有入场（动画自己就是从 0 开始的）');
eq(sc0.layers[2].shape.kind, 'rect', '形状默认方框');
eq(sc0.layers[2].in.preset, 'wipe', '形状默认揭开入场');

eq(SB.layerIndex(sc0, ul.id), 1, 'layerIndex');
eq(SB.findLayer(sc0, 999), null, '找不到图层返回 null');

const dup = SB.duplicateLayer(sc0, tl.id);
eq(sc0.layers.length, 4, '复制后 4 个图层');
eq(dup.id, 4, '副本 id 递增');
ok(dup.name.indexOf('副本') > 0, '副本名字带「副本」');
eq(SB.moveLayer(sc0, 1, 1), true, '往后挪一步');
eq(SB.moveLayer(sc0, 1, -1), true, '往前挪回来');
ok(SB.moveLayer(sc0, 1, -1) === false, '到头了不能挪');
eq(SB.removeLayer(sc0, 2), true, '删图层');
eq(sc0.layers.length, 3, '删掉一个');
eq(SB.removeLayer(sc0, 999), false, '删不存在的返回 false');

/* ---------------- 关键帧通道 ---------------- */

const lay = SB.createLayer('text', { start: 0, end: 4 });
lay.in = { preset: 'none', dur: 0, ease: 'linear' };
lay.out = { preset: 'none', dur: 0, ease: 'linear' };

SB.addLayerEvent(lay, 'x', { start: 0, end: 2, ease: 'linear', from: 0.2, to: 0.8 });
near(SB.layerParamsAt(lay, -1).x, 0.5, 1e-9, '事件开始前用静态值');
near(SB.layerParamsAt(lay, 0).x, 0.2, 1e-9, '事件起点');
near(SB.layerParamsAt(lay, 1).x, 0.5, 1e-9, '事件中点线性插值');
near(SB.layerParamsAt(lay, 2).x, 0.8, 1e-9, '事件终点取 to');
near(SB.layerParamsAt(lay, 9).x, 0.8, 1e-9, '事件结束后保持 to 不回弹');

SB.addLayerEvent(lay, 'alpha', { start: 0, end: 1, ease: 'linear', from: 0, to: 100 });
near(SB.layerParamsAt(lay, 1).alpha, 100, 1e-9, 'alpha 通道独立');
near(SB.layerParamsAt(lay, 1).x, 0.5, 1e-9, 'x 通道没被 alpha 影响');
eq(SB.removeLayerEvent(lay, 'alpha', lay.events.alpha[0].id), true, '删关键帧');
eq(lay.events.alpha.length, 0, '关键帧删掉了');

/* ---------------- 图层求值 ---------------- */

const L = SB.createLayer('text', { start: 1, end: 4 });
L.x = 0.5; L.y = 0.3; L.alpha = 100;
L.in = { preset: 'fade', dur: 0.5, ease: 'outCubic' };
L.out = { preset: 'fade', dur: 0.4, ease: 'inCubic' };

eq(SB.layerAt(L, 0.5).active, false, '图层开始之前不显示');
eq(SB.layerAt(L, 4.5).active, false, '图层结束之后不显示');
eq(SB.layerAt(L, 2).active, true, '时段内显示');
near(SB.layerAt(L, 2).alpha, 1, 1e-9, '中间完全不透明');
near(SB.layerAt(L, 1.25).alpha, 0.875, 1e-9, '淡入一半（outCubic 缓动）');
near(SB.layerAt(L, 3.8).alpha, 0.125, 1e-9, '淡出一半（inCubic 缓动）');
near(SB.layerAt(L, 2).progress, 1 / 3, 1e-9, 'progress = 层内进度');

const L2 = SB.createLayer('text', { start: 0, end: 3 });
L2.y = 0.4;
L2.in = { preset: 'slideUp', dur: 1, ease: 'linear' };
L2.out = { preset: 'none', dur: 0, ease: 'linear' };
near(SB.layerAt(L2, 0).y, 0.5, 1e-9, '入场的起点在下方 0.10 处');
near(SB.layerAt(L2, 0.5).y, 0.45, 1e-9, '滑入到一半');
near(SB.layerAt(L2, 1).y, 0.4, 1e-9, '滑入到位');

const L4 = SB.createLayer('text', { start: 0, end: 2 });
L4.in = { preset: 'fade', dur: 99, ease: 'linear' };
L4.out = { preset: 'fade', dur: 99, ease: 'linear' };
near(SB.layerAt(L4, 0.5).alpha, 0.5, 1e-9, '出入场各占一半：0.5s 时半透明');

const L5 = SB.createLayer('text', { start: 0, end: 2 });
L5.visible = false;
eq(SB.layerAt(L5, 1).active, false, 'visible=false 不显示');

// activeLayers 过滤（场景内本地时间）
const adoc = SB.createStoryboard(digest);
const asc = adoc.scenes[0];
const a1 = SB.addLayer(asc, 'text', { start: 0, end: 2 });
const a2 = SB.addLayer(asc, 'text', { start: 5, end: 7 });
a1.in = { preset: 'none', dur: 0, ease: 'linear' };
a2.in = { preset: 'none', dur: 0, ease: 'linear' };
eq(SB.activeLayers(asc, 1).length, 1, '只有一条图层在 1s 生效');
eq(SB.activeLayers(asc, 1)[0].layer.id, a1.id, '生效的是第一条');
eq(SB.activeLayers(asc, 6).length, 1, '6s 时换成第二条');
eq(SB.activeLayers(asc, 3).length, 0, '3s 时啥也没有');

/* ---------------- Shader ---------------- */

eq(SB.shaderWeights('bloom').bloom, 1, '辉光权重');
eq(JSON.stringify(SB.shaderWeights('nope')), '{}', '未知预设没有权重');

const fx = SB.createShader('glitch', { start: 1, end: 3, amount: 100, ramp: 0.25 });
near(SB.shaderValAt(fx, 0), 0, 1e-9, 'shader 开始前 = 0');
near(SB.shaderValAt(fx, 3.5), 0, 1e-9, 'shader 结束后 = 0');
near(SB.shaderValAt(fx, 2), 1, 1e-9, '中间满强度');
near(SB.shaderValAt(fx, 1.25), 0.5, 1e-6, '软启动一半');
near(SB.shaderValAt(SB.createShader('rgb', { start: 0, end: 2, amount: 50 }), 1), 0.5, 1e-9, 'amount 50%');

// RGB 分离改成「立刻」：刚进区间就是满强度，没有缓入
const rgbInstant = SB.createShader('rgb', { start: 4, end: 8, amount: 100, ramp: 0.4 });
near(SB.shaderValAt(rgbInstant, 4.05), 1, 1e-6, 'RGB 分离立刻生效（4.05s 就已经是满强度）');
near(SB.shaderValAt(rgbInstant, 4.1), 1, 1e-6, 'RGB 分离没有缓入');
near(SB.shaderValAt(rgbInstant, 7.95), 1, 1e-6, 'RGB 分离离开前也还是满强度');

// 后处理按层叠加：activeShaders 按列表顺序给出每一层
const stkScene = { shaders: [
  SB.createShader('bloom', { start: 0, end: 4, amount: 100, ramp: 0 }),
  SB.createShader('rgb', { start: 0, end: 4, amount: 50, ramp: 0 }),
  SB.createShader('vignette', { start: 0, end: 4, amount: 100, ramp: 0 })
] };
const stk = SB.activeShaders(stkScene, 2);
eq(stk.length, 3, '三层后处理都在');
eq(stk[0].preset, 'bloom', '第 1 层 = 列表第 1 条');
eq(stk[2].preset, 'vignette', '第 3 层 = 列表第 3 条');
near(stk[1].value, 0.5, 1e-6, '第 2 层强度 50%');
near(stk[1].weights.rgb, 0.425, 1e-6, '第 2 层权重 = 预设权重 × 自身强度（不是相加）');
near(stk[0].weights.bloom, 1, 1e-6, '第 1 层权重是它自己的');
near(SB.activeShaders(stkScene, 9).length, 0, 1e-9, '区间外没有层');
// 暗角 = 纯暗角；颗粒单独一条；四角拉伸是新效果
eq(SB.shaderWeights('vignette').vignette, 1, '暗角权重 1');
eq(SB.shaderWeights('vignette').grain, undefined, '暗角不再掺颗粒');
ok(SB.shaderWeights('grain').grain === 1, '颗粒预设');
eq(SB.shaderWeights('stretch').stretch, 1, '四角拉伸权重 1');

  // 放大抖动：zoom + shake 两个权重
  eq(SB.shaderWeights('zoomShake').zoom, 1, '放大抖动 zoom 权重 1');
  eq(SB.shaderWeights('zoomShake').shake, 1, '放大抖动 shake 权重 1');

  // 冲击放大：层里带上「进区间的时间点」，着色器靠它做「突然放大→回弹」
  const punchStack = SB.activeShaders({ shaders: [SB.createShader('zoomShake', { start: 4.0, end: 12.0, amount: 100, ramp: 0 })] }, 4.05);
  eq(punchStack.length, 1, '冲击放大层生效');
  near(punchStack[0].punchT0, 4.0, 1e-6, 'punchT0 = 该层起点（场景内时间）');
  ok(punchStack[0].weights.zoom > 0.9, '冲击瞬间 zoom 权重接近满值');
  ok(SB.SHADER_PRESETS.some((p) => p.id === 'zoomShake'), '预设列表里有放大抖动');
  eq(SB.shaderPreset('zoomShake').label, '放大抖动', '标签叫放大抖动');
  ok(SB.WEIGHT_KEYS.indexOf('zoom') >= 0, 'zoom 是合法权重键');
  ok(SB.WEIGHT_KEYS.indexOf('shake') >= 0, 'shake 是合法权重键');
  const wZoom = SB.combineShaderWeights({ shaders: [SB.createShader('zoomShake', { start: 0, end: 2, amount: 100 })] }, 1);
  near(wZoom.zoom, 1, 1e-6, '放大叠进权重');
  near(wZoom.shake, 1, 1e-6, '抖动叠进权重');
ok(SB.SHADER_PRESETS.some((p) => p.id === 'stretch'), '预设列表里有四角拉伸');
ok(SB.SHADER_PRESETS.some((p) => p.id === 'vignette'), '预设列表里有暗角');
ok(SB.WEIGHT_KEYS.indexOf('stretch') >= 0, 'stretch 是合法权重键');
const wStretch = SB.combineShaderWeights({ shaders: [SB.createShader('stretch', { start: 0, end: 2, amount: 100 })] }, 1);
near(wStretch.stretch, 1, 1e-6, '四角拉伸叠进权重');

const mixDoc = SB.createStoryboard(digest);
const mixScene = mixDoc.scenes[0];
SB.addShader(mixScene, 'bloom', { start: 0, end: 4, amount: 100 });
SB.addShader(mixScene, 'rgb', { start: 0, end: 4, amount: 100 });
const w1 = SB.combineShaderWeights(mixScene, 2);
near(w1.bloom, 1, 1e-9, '叠加：辉光 1');
near(w1.rgb, 0.85, 1e-9, '叠加：RGB 0.85');
near(w1.grain, 0.08, 1e-9, '叠加：颗粒 0.08');
SB.addShader(mixScene, 'bloom', { start: 0, end: 4, amount: 100 });
near(SB.combineShaderWeights(mixScene, 2).bloom, 1.5, 1e-9, '同一键相加后封顶 1.5');
near(SB.combineShaderWeights(mixScene, 9).bloom, 0, 1e-9, '没有生效时全 0');
eq(SB.removeShader(mixScene, mixScene.shaders[0].id), true, '删后处理');
eq(mixScene.shaders.length, 2, '删掉一条');

// 场景之间互不影响
const isoDoc = SB.createStoryboard(digest);
SB.addShader(isoDoc.scenes[0], 'glitch', { start: 0, end: 2, amount: 100 });
near(SB.combineShaderWeights(isoDoc.scenes[0], 1).glitch, 1, 1e-9, '解锁场的 shader 在解锁场生效');
near(SB.combineShaderWeights(isoDoc.scenes[1], 1).glitch, 0, 1e-9, '谱面场看不到解锁场的 shader');

/* ---------------- 容错读取 ---------------- */

const dirty = {
  chart: { title: '' },
  stage: { width: 99999 },
  assets: { good: 'data:image/png;base64,AAA', bad: 'http://x/y.png' },
  scenes: [
    { kind: 'unlock', name: '解锁', length: 2, layers: [
      { id: 1, type: 'nope', start: 3, end: 1, text: 'hi' },
      { id: 1, type: 'text', start: -5, end: 2, x: 9, alpha: 999, blend: 'zzz' },
      { type: 'unlock', unlock: { preset: 'not-a-preset' } }
    ], shaders: [{ preset: 'zzz' }, { preset: 'crt', start: 1, end: 4, amount: 500 }] },
    { kind: 'zzz', layers: [{ type: 'shape', shape: { kind: 'zzz', w: -3 } }] }
  ]
};

const read = SB.normalizeDoc(dirty);
eq(read.doc.scenes.length, 2, '两场都读进来了');
eq(read.doc.scenes[1].kind, 'free', '未知场景类型退回演出场');
eq(read.doc.scenes[0].layers.length, 3, '三个图层都读进来了');
eq(read.doc.scenes[0].layers[0].type, 'text', '不认识的图层类型退回文字');
ok(read.doc.scenes[0].layers[0].end > read.doc.scenes[0].layers[0].start, '结束早于开始会被修正');
eq(read.doc.scenes[0].layers[1].blend, 'normal', '未知混合模式退回 normal');
near(read.doc.scenes[0].layers[1].alpha, 100, 1e-9, 'alpha 夹到 100');
eq(read.doc.scenes[0].layers[2].unlock.preset, 'tape', '未知解锁预设退回磁带');
eq(read.doc.scenes[1].layers[0].shape.kind, 'rect', '未知形状退回方框');
eq(read.doc.scenes[0].shaders[0].preset, 'none', '未知后处理预设退回 none');
near(read.doc.scenes[0].shaders[1].amount, 100, 1e-9, 'amount 夹到 100');
eq(read.doc.stage.width, 3840, '舞台宽度夹到上限');
eq(read.doc.chart.title, '未命名谱面', '空曲名用默认值');
eq(read.doc.assets.good, 'data:image/png;base64,AAA', 'dataURL 资源保留');
eq(read.doc.assets.bad, undefined, '外部 URL 资源丢弃');
ok(read.doc.scenes[0].layers[0].id !== read.doc.scenes[0].layers[1].id, '重复 id 会重新编号');

// 旧版工程（根上是 layers / shaders，没有 scenes）
const legacy = SB.normalizeDoc({
  chart: { duration: 9 },
  layers: [{ type: 'text', text: 'hi' }],
  shaders: [{ preset: 'bloom' }]
});
eq(legacy.doc.scenes.length, 1, '旧版工程被收进一场');
eq(legacy.doc.scenes[0].kind, 'chart', '旧版有谱面 → 谱面场');
eq(legacy.doc.scenes[0].layers.length, 1, '旧版图层搬进来了');
eq(legacy.doc.scenes[0].shaders.length, 1, '旧版后处理搬进来了');
ok(legacy.warnings.some(w => w.indexOf('旧版') >= 0), '旧版工程给出迁移提示');

const notObj = SB.normalizeDoc('nope');
eq(notObj.doc.scenes.length, 1, '不是对象也给一份能用的空工程');
eq(notObj.warnings.length, 1, '给出原因');

/* ---------------- 导出 / 往返 ---------------- */

const rd = SB.createStoryboard(digest);
SB.applyTemplate(rd.scenes[0], 'unlock', 0, { chart: rd.chart, fit: SB.sceneLen(rd, rd.scenes[0]), limit: SB.sceneLen(rd, rd.scenes[0]) });
SB.applyTemplate(rd.scenes[1], 'opening', 0, { chart: rd.chart, fit: SB.sceneLen(rd, rd.scenes[1]), limit: SB.sceneLen(rd, rd.scenes[1]) });
SB.addShader(rd.scenes[0], 'crt', { start: 0, end: 2 });
rd.meta.author = '我';

const text = SB.serializeDoc(rd);
eq(text.format, 'rstory', '导出 format');
ok(Array.isArray(text.scenes), '导出 scenes');
eq(text.scenes.length, rd.scenes.length, '导出场景数一致');
eq(text.scenes[0].kind, 'unlock', '导出场景类型');
eq(text.scenes[0].layers.length, rd.scenes[0].layers.length, '导出图层数一致');
eq(text.scenes[0].layers[0].id, 1, '导出时 id 重新从 1 编号');
eq(text.scenes[0].shaders.length, rd.scenes[0].shaders.length, '导出后处理数一致');
ok(JSON.stringify(text).indexOf('data:') < 0, '没有资源时不写 assets');

const back = SB.normalizeDoc(JSON.parse(JSON.stringify(text)));
eq(back.warnings.filter(w => w.indexOf('不认识') >= 0 || w.indexOf('旧版') >= 0).length, 0, '往返没有迁移/未知字段警告');
eq(back.doc.scenes.length, rd.scenes.length, '往返场景数一致');
const rdText = rd.scenes[0].layers.filter(l => l.type === 'text')[0];
const backText = back.doc.scenes[0].layers.filter(l => l.type === 'text')[0];
eq(back.doc.scenes[0].layers.length, rd.scenes[0].layers.length, '往返图层数一致');
eq(backText.style.effect, rdText.style.effect, '往返文字特效一致');
near(backText.start, rdText.start, 1e-9, '往返图层起点一致');
eq(back.doc.scenes[1].kind, 'chart', '往返谱面场类型一致');
eq(back.doc.scenes[0].shaders[0].preset, rd.scenes[0].shaders[0].preset, '往返 shader 一致');
eq(back.doc.chart.hash, digest.hash, '往返谱面指纹一致');
near(SB.totalLength(back.doc), SB.totalLength(rd), 1e-9, '往返总时长一致');

/* ---------------- 模板 ---------------- */

for (const tpl of SB.TEMPLATES) {
  const tdoc = SB.createStoryboard(digest);
  const scene = tdoc.scenes[0];
  const made = SB.applyTemplate(scene, tpl.id, 0, { chart: tdoc.chart, fit: 2.6, limit: 2.6 });
  ok(!!made, '模板 ' + tpl.id + ' 能套用');
  ok(made.layers.length > 0, '模板 ' + tpl.id + ' 有图层');
  ok(made.shaders.length > 0, '模板 ' + tpl.id + ' 有后处理');
  for (const l of made.layers) {
    ok(l.start >= 0 && l.end <= 2.6 + 1e-9, '模板 ' + tpl.id + ' 的图层落在场景里');
  }
  const ids = scene.layers.map(l => l.id);
  ok(new Set(ids).size === ids.length, '模板 ' + tpl.id + ' 的 id 不重复');
  const joined = JSON.stringify(made.layers);
  ok(joined.indexOf('{title}') < 0, '模板 ' + tpl.id + ' 占位符都替换了');
}
eq(SB.TEMPLATES.length, 3, '三个模板');
eq(SB.fillText('{title} - {artist} [{difficulty} {level}]', chart.meta), 'Neon Pulse - Synth Engine [HARD 8]', '占位符替换');

// 场景太短 → 按比例压进场景（结构保留）
const fitDoc = SB.createStoryboard(digest);
const fitScene = fitDoc.scenes[0];          // 解锁场 2.6 秒
const fitted = SB.applyTemplate(fitScene, 'unlock', 0, { chart: fitDoc.chart, fit: SB.sceneLen(fitDoc, fitScene), limit: SB.sceneLen(fitDoc, fitScene) });
ok(fitted.scale < 0.999 && fitted.scale > 0.3, '解锁模板被压进 2.6 秒场景（scale=' + fitted.scale + '）');
const unlockLayer = fitScene.layers.filter(l => l.type === 'unlock')[0];
ok(!!unlockLayer, '压缩后仍有解锁动画');
near(unlockLayer.end, 1.352, 0.01, '解锁动画被压到 1.35 秒');
near(fitScene.layers[fitScene.layers.length - 1].end, 2.6, 1e-6, '最后一个图层正好铺到场景末尾');

// 场景够长时不压缩
const bigDoc = SB.createStoryboard(digest);
const bigScene = SB.addScene(bigDoc, 'free', { name: '大片场', length: 12 });
const bigMade = SB.applyTemplate(bigScene, 'opening', 0, { chart: bigDoc.chart, fit: 12, limit: 12 });
near(bigMade.scale, 1, 1e-9, '放得下就不压缩');
near(bigMade.layers[bigMade.layers.length - 1].end, 4.2, 1e-6, '模板原长 4.2 秒');

eq(SB.applyTemplate(SB.createStoryboard(digest).scenes[0], 'nope', 0), null, '不存在的模板返回 null');

/* ---------------- 校验 / 描述 ---------------- */

const emptyIssues = SB.validateDoc(SB.createStoryboard(digest));
ok(emptyIssues.some(i => i.level === 'warn' && i.text.indexOf('还没有图层') >= 0), '空工程会提示没图层');

const badDoc = SB.createStoryboard(digest);
const badScene = badDoc.scenes[0];
const emptyText = SB.addLayer(badScene, 'text', { start: 0, end: 2 });
emptyText.text = '   ';
const imgLayer = SB.addLayer(badScene, 'image', { start: 0, end: 2 });
imgLayer.image.name = 'nope.png';
const issues = SB.validateDoc(badDoc);
ok(issues.some(i => i.text.indexOf('文字是空的') >= 0), '校验：空文字');
ok(issues.some(i => i.text.indexOf('不在工程里') >= 0), '校验：图片丢了');
ok(issues.some(i => i.text.indexOf('解锁') >= 0), '校验信息带场景名');

const descDoc = SB.createStoryboard(digest);
const descScene = descDoc.scenes[0];
const dText = SB.addLayer(descScene, 'text', { start: 0, end: 2 });
dText.text = '很短';
eq(SB.describeLayer(dText), '很短', 'describeLayer 文字');
eq(SB.describeLayer(SB.addLayer(descScene, 'unlock', { start: 0, end: 2 })), '磁带插入', 'describeLayer 解锁预设名');
eq(SB.describeLayer(SB.addLayer(descScene, 'shape', { start: 0, end: 2 })), '方框', 'describeLayer 形状名');
eq(SB.describeLayer(SB.addLayer(descScene, 'image', { start: 0, end: 2 })), '未选图片', 'describeLayer 未选图片');
eq(SB.layerKeyCount(dText), 0, 'layerKeyCount 0');
SB.addLayerEvent(dText, 'x', { start: 0, end: 1, from: 0, to: 1 });
eq(SB.layerKeyCount(dText), 1, 'layerKeyCount 1');

near(SB.snapTime(0.93, { bpm: 150, beat_offset: 0 }, 4), 0.9, 1e-9, 'snapTime 借 core 的吸附');
eq(SB.label(SB.UNLOCK_PRESETS, 'tape'), '磁带插入', 'label 取中文名');
eq(SB.label(SB.UNLOCK_PRESETS, 'zzz'), 'zzz', 'label 找不到就原样返回');

/* ---------------- 预设目录完整性 ---------------- */

ok(SB.IN_PRESETS.length >= 8, '入场预设够用');
ok(SB.OUT_PRESETS.length >= 8, '出场预设够用');
ok(SB.TEXT_EFFECTS.length >= 8, '文字特效够用');
ok(SB.UNLOCK_PRESETS.length >= 6, '解锁动画够用');
ok(SB.SHADER_PRESETS.length >= 10, 'Shader 够用');
ok(SB.SCENE_KINDS.length === 3, '三种场景');
for (const e of SB.TEXT_EFFECTS) ok(!!e.label, '文字特效 ' + e.id + ' 有中文名');
for (const u of SB.UNLOCK_PRESETS) ok(!!u.desc, '解锁动画 ' + u.id + ' 有说明');
for (const s of SB.SCENE_KINDS) {
  ok(!!s.label && !!s.desc, '场景 ' + s.id + ' 有名字和说明');
  ok(s.chart === (s.id === 'chart'), '场景 ' + s.id + ' 的 chart 标记正确');
}
for (const s of SB.SHADER_PRESETS) {
  for (const k of Object.keys(s.weights)) {
    ok(SB.WEIGHT_KEYS.indexOf(k) >= 0, 'shader ' + s.id + ' 的权重键 ' + k + ' 渲染器认识');
    ok(s.weights[k] > 0, 'shader ' + s.id + ' 的权重 ' + k + ' 是正数');
  }
}

for (const p of SB.IN_PRESETS) {
  const l = SB.createLayer('text', { start: 0, end: 2 });
  l.in = { preset: p.id, dur: 0.5, ease: 'outCubic' };
  l.out = { preset: 'none', dur: 0, ease: 'linear' };
  const st = SB.layerAt(l, 0.25);
  ok(st.active && isFinite(st.alpha) && isFinite(st.x), '入场预设 ' + p.id + ' 能求值');
}
for (const p of SB.OUT_PRESETS) {
  const l = SB.createLayer('text', { start: 0, end: 2 });
  l.in = { preset: 'none', dur: 0, ease: 'linear' };
  l.out = { preset: p.id, dur: 0.5, ease: 'inCubic' };
  const st = SB.layerAt(l, 1.75);
  ok(st.active && isFinite(st.alpha) && isFinite(st.y), '出场预设 ' + p.id + ' 能求值');
}

/* ---------------- 父线 / 子线 ---------------- */

{
  const mk = (lanes) => ({ lanes: lanes, stage: { highway_length: 2 }, notes: [] });
  const half = CS.halfWidth(2);

  const plain = mk([{ x: 0, y: 0, rotation: 0, alpha: 100, speed: 1, length: 1, name: "A", color: "#fff" }]);
  const g0 = CS.laneGeom(plain, 0, 0, half, 1);
  eq(g0.parent, -1, '普通轨道没有父线');
  near(g0.cx, CS.STAGE_W * 0.5, 1e-6, '默认在舞台中线');

  const withChild = mk([
    { x: 0, y: 0, rotation: 0, alpha: 100, speed: 1, length: 1, name: "P", color: "#fff" },
    { x: 40, y: 0, rotation: 0, alpha: 100, speed: 1, length: 1, name: "C", color: "#fff", parent: 0 },
  ]);
  const gc = CS.laneGeom(withChild, 1, 0, half, 1);
  eq(gc.parent, 0, '子线记住了父线');
  near(gc.cx, CS.STAGE_W * 0.5 + 40, 1e-6, '子线横向偏移 40');

  const rotated = mk([
    { x: 0, y: 0, rotation: 90, alpha: 100, speed: 1, length: 1, name: "P", color: "#fff" },
    { x: 40, y: 0, rotation: 0, alpha: 100, speed: 1, length: 1, name: "C", color: "#fff", parent: 0 },
  ]);
  const gr = CS.laneGeom(rotated, 1, 0, half, 1);
  const pg = CS.laneGeom(rotated, 0, 0, half, 1);
  near(gr.cx, pg.cx + pg.sx * 40 + pg.dx * 0, 1e-6, '子线 x 沿父线横向轴');
  near(gr.cy, pg.cy + pg.sy * 40 + pg.dy * 0, 1e-6, '子线 y 沿父线横向轴');
  near(gr.rotDeg, 90, 1e-6, '旋转叠加：父 90 + 子 0');

  const moving = mk([
    {
      x: 0, y: 0, rotation: 0, alpha: 100, speed: 1, length: 1, name: "P", color: "#fff",
      events: { x: [{ start: 0, end: 1, from: 0, to: 100, ease: "linear" }] },
    },
    { x: 10, y: 0, rotation: 0, alpha: 100, speed: 1, length: 1, name: "C", color: "#fff", parent: 0 },
  ]);
  const at0 = CS.laneGeom(moving, 1, 0, half, 1);
  const at1 = CS.laneGeom(moving, 1, 1, half, 1);
  near(at1.cx - at0.cx, 100, 0.5, '父线走 100，子线跟着走 100');

  const selfLoop = mk([
    { x: 20, y: 0, rotation: 0, alpha: 100, speed: 1, length: 1, name: "A", color: "#fff", parent: 0 },
  ]);
  const gl = CS.laneGeom(selfLoop, 0, 0, half, 1);
  eq(gl.parent, -1, '指向自己按没有父线处理');
  near(gl.cx, CS.STAGE_W * 0.5 + 20, 1e-6, '自己指自己时仍画在原位');

  const chain = mk([
    { x: 0, y: 0, rotation: 0, alpha: 100, speed: 1, length: 1, name: "G", color: "#fff" },
    { x: 30, y: 0, rotation: 0, alpha: 100, speed: 1, length: 1, name: "P", color: "#fff", parent: 0 },
    { x: 20, y: 0, rotation: 0, alpha: 100, speed: 1, length: 1, name: "C", color: "#fff", parent: 1 },
  ]);
  const g2 = CS.laneGeom(chain, 2, 0, half, 1);
  near(g2.cx, CS.STAGE_W * 0.5 + 30 + 20, 1e-6, '两级父子：30 + 20 一路加起来');
}

/* ---------------- 结果 ---------------- */

console.log('');
if (fails.length) {
  console.log('✗ ' + fails.length + ' 条失败 / 共 ' + (pass + fails.length) + ' 条');
  for (const f of fails) console.log('   · ' + f);
  process.exitCode = 1;
} else {
  console.log('✓ 故事板数据层 ' + pass + ' 条全部通过');
}
