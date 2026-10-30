/* =============================================================================
 * Rhythm 故事板制作器 · 界面
 * -----------------------------------------------------------------------------
 * 故事板 = 一串**场景**：解锁场（谱面之前）→ 谱面场（画谱面、放音乐）→ 演出场（片尾）。
 * 图层 / Shader 都挂在场景里，时间用**场景内本地时间**。
 *
 * 谱面只读：这个文件里没有任何写谱面的地方。
 *   · 导入时只调 RChart.normalize() 读，原始 chart.json 字节原样留一份，导出整包时直接复制
 *   · 舞台上的谱面画面是「按谱面实时算出来的」，谱面本身一个字节都不改
 * ========================================================================== */
(function () {
  'use strict';

  var RC = window.RChart;
  var SB = window.SB;
  var SBR = window.SBRender;

  function $(id) { return document.getElementById(id); }

  function esc(s) {
    return String(s === undefined || s === null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function fmt(t) { return RC.formTime(t || 0); }

  function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

  var KIND_CLASS = { unlock: 'k-unlock', chart: 'k-chart', free: 'k-free' };

  /* ==========================================================================
   * 状态
   * ======================================================================== */

  var S = {
    doc: SB.createStoryboard(),
    chart: null,
    chartName: '',
    chartRaw: null,           // { name, bytes } —— 原样保留，导出整包时复制
    chartHash: '',
    audioEl: null,
    audioBytes: null,
    coverBytes: null,
    coverUrl: '',
    images: {},
    videos: {},
    imageUrls: {},
    time: 0,                  // 全局时间
    total: 5,
    playing: false,
    loop: false,
    lastTs: 0,
    audioPending: false,
    sceneId: 0,               // 当前编辑的场景
    selKind: 'layer',         // 'layer' | 'shader' | 'scene' | 'none'
    selId: 0,
    view: { start: 0, span: 12 },
    tlScroll: 0,             // 时间轴图层行的纵向滚动（层多的时候用）
    snap: true,
    div: 4,
    undo: [],
    redo: [],
    editOpen: false,
    fileName: '',
    renderer: null,
    rafPending: false,
    drag: null,
    hintTimer: 0,
    recorder: null,
    audioNodeMade: false,
    muted: false,             // 只影响本机试听，不存工程
    audioSrcNode: null,
    recordCtx: null,
    recordStream: null
  };

  /* ==========================================================================
   * 场景工具
   * ======================================================================== */

  function spans() { return SB.sceneSpans(S.doc); }

  function curScene() {
    var sc = SB.findScene(S.doc, S.sceneId);
    if (sc) return sc;
    sc = S.doc.scenes[0] || null;
    if (sc) S.sceneId = sc.id;
    return sc;
  }

  function curSpan() {
    var list = spans();
    for (var i = 0; i < list.length; i++) if (list[i].scene.id === S.sceneId) return list[i];
    return list[0] || null;
  }

  function sceneLen(sc) { return SB.sceneLen(S.doc, sc); }

  function spanOf(sceneId) {
    var list = spans();
    for (var i = 0; i < list.length; i++) if (list[i].scene.id === sceneId) return list[i];
    return null;
  }

  /** 全局时间 t 落在哪个场景：直接返回场景区间对象（{scene, index, start, end, len, kind}） */
  function spanAt(t) {
    var at = SB.sceneAt(S.doc, t);
    return at ? at.span : null;
  }

  function chartSpan() {
    var list = spans();
    for (var i = 0; i < list.length; i++) if (list[i].kind === 'chart') return list[i];
    return null;
  }

  /* ==========================================================================
   * 提示 / 撤销
   * ======================================================================== */

  function hint(text) {
    var el = $('st-hint');
    if (!el) return;
    el.textContent = text || '';
    if (S.hintTimer) clearTimeout(S.hintTimer);
    if (text) S.hintTimer = setTimeout(function () { el.textContent = ''; }, 6000);
  }

  /**
   * 快照只存「结构」，不存资源内容（视频/图片是几 MB~几十 MB 的 dataURL，
   * 之前每步撤销都复制一份，120 步就是把整包资源复制 120 遍 —— 标签页直接崩）。
   * 只记资源名；撤销时资源用**当前内存里的**（资源只增不减，不需要回滚）。
   */
  function snapshot() {
    var data = SB.serializeDoc(S.doc);
    data.assets = {};
    data.assetNames = Object.keys(S.doc.assets || {});
    return JSON.stringify(data);
  }

  function pushUndo() {
    var s = snapshot();
    if (S.undo.length && S.undo[S.undo.length - 1] === s) return;
    S.undo.push(s);
    if (S.undo.length > 40) S.undo.shift();   // 40 步足够，别让内存无限涨
    S.redo.length = 0;
    refreshUndo();
  }

  function beginEdit() {
    if (S.editOpen) return;
    pushUndo();
    S.editOpen = true;
  }

  function endEdit() { S.editOpen = false; }

  function refreshUndo() {
    $('btn-undo').disabled = S.undo.length === 0;
    $('btn-redo').disabled = S.redo.length === 0;
  }

  function applySnapshot(text) {
    var parsed;
    try { parsed = JSON.parse(text); } catch (err) { return; }
    // 资源内容不在快照里：按名字从当前内存接回来（资源只增不减）
    var names = parsed.assetNames || [];
    delete parsed.assetNames;
    var cur = (S.doc && S.doc.assets) || {};
    var assets = {};
    for (var ai = 0; ai < names.length; ai++) {
      if (cur[names[ai]]) assets[names[ai]] = cur[names[ai]];
    }
    parsed.assets = assets;
    var res = SB.normalizeDoc(parsed);
    S.doc = res.doc;
    if (!SB.findScene(S.doc, S.sceneId)) S.sceneId = S.doc.scenes.length ? S.doc.scenes[0].id : 0;
    var sc = curScene();
    if (S.selKind === 'layer' && !SB.findLayer(sc, S.selId)) { S.selKind = 'none'; S.selId = 0; }
    if (S.selKind === 'shader' && !SB.findShader(sc, S.selId)) { S.selKind = 'none'; S.selId = 0; }
    if (S.selKind === 'scene' && !SB.findScene(S.doc, S.selId)) { S.selKind = 'none'; S.selId = 0; }
    syncTimes();
    clampView();
    refreshAll();
  }

  function undo() {
    if (!S.undo.length) return;
    S.redo.push(snapshot());
    applySnapshot(S.undo.pop());
    refreshUndo();
    hint('撤销');
  }

  function redo() {
    if (!S.redo.length) return;
    S.undo.push(snapshot());
    while (S.undo.length > 40) S.undo.shift();
    applySnapshot(S.redo.pop());
    refreshUndo();
    hint('重做');
  }

  /* ==========================================================================
   * 时间 / 播放
   * ======================================================================== */

  function chartDuration() {
    return S.chart ? RC.chartDuration(S.chart) : 0;
  }

  function totalDuration() {
    var t = SB.totalLength(S.doc);
    return t > 0.05 ? t : 5;      // 什么都没有：给 5 秒编辑底
  }

  function syncTimes() {
    S.total = totalDuration();
    if (!SB.findScene(S.doc, S.sceneId)) {
      S.sceneId = S.doc.scenes.length ? S.doc.scenes[0].id : 0;
    }
  }

  function audioOffset() {
    return S.chart ? RC.num(S.chart.audio && S.chart.audio.offset, 0) : 0;
  }

  /** 这一时刻音乐该不该响：只有谱面场里才放 */
  function audioInside(t) {
    var cs = chartSpan();
    return !!cs && t >= cs.start - 1e-6 && t < cs.end - 1e-6;
  }

  /** 全局时间 → 音频时间（谱面场内本地时间 + offset） */
  function audioTimeAt(t) {
    var cs = chartSpan();
    if (!cs) return 0;
    return clamp(t - cs.start, 0, cs.len) + audioOffset();
  }

  function holdAudio() {
    if (!S.audioEl) return;
    try { S.audioEl.pause(); } catch (err) { /* 忽略 */ }
    try { S.audioEl.currentTime = 0; } catch (err) { /* 忽略 */ }
  }

  function startAudioAt(t) {
    if (!S.audioEl) return;
    S.audioPending = false;
    try {
      S.audioEl.currentTime = Math.max(0, audioTimeAt(t));
      var p = S.audioEl.play();
      if (p && p.catch) p.catch(function () { /* 浏览器不给自动播，那就靠时间轴自己走 */ });
    } catch (err) { /* 忽略 */ }
  }

  function seek(t) {
    if (!isFinite(t)) t = 0;
    S.time = clamp(t, 0, S.total);
    if (S.audioEl) {
      if (audioInside(S.time)) {
        if (S.playing) startAudioAt(S.time);
        else {
          try { S.audioEl.pause(); } catch (err) { /* 忽略 */ }
          try { S.audioEl.currentTime = Math.max(0, audioTimeAt(S.time)); } catch (err) { /* 忽略 */ }
        }
      } else {
        holdAudio();
        S.audioPending = S.playing;
      }
    }
    followPlayhead();
    S.draw(true);
  }

  function play() {
    if (S.playing) return;
    if (S.time >= S.total - 1e-6) S.time = 0;
    S.playing = true;
    $('btn-play').textContent = '⏸ 暂停';
    $('btn-play2').textContent = '⏸';
    S.lastTs = 0;
    S.audioPending = !!S.audioEl;
    if (S.audioEl) {
      if (audioInside(S.time)) startAudioAt(S.time);
      else holdAudio();
    }
    requestAnimationFrame(tick);
  }

  function pause() {
    if (!S.playing) return;
    S.playing = false;
    S.audioPending = false;
    $('btn-play').textContent = '▶ 播放';
    $('btn-play2').textContent = '▶';
    if (S.audioEl) { try { S.audioEl.pause(); } catch (err) { /* 忽略 */ } }
    S.draw(true);
  }

  function togglePlay() { if (S.playing) pause(); else play(); }

  /** 播放头进入别的场景时，编辑目标跟着切过去（不然左边面板和画面会对不上） */
  function followPlayhead() {
    var at = spanAt(S.time);
    if (!at || at.scene.id === S.sceneId) return false;
    S.sceneId = at.scene.id;
    S.tlScroll = 0;
    if (S.selKind === 'layer' && !SB.findLayer(at.scene, S.selId)) { S.selKind = 'none'; S.selId = 0; }
    if (S.selKind === 'shader' && !SB.findShader(at.scene, S.selId)) { S.selKind = 'none'; S.selId = 0; }
    if (S.selKind === 'scene') S.selId = S.sceneId;
    renderSceneList();
    renderLayerList();
    renderInspector();
    renderShaderList();
    return true;
  }

  function tick(ts) {
    if (!S.playing) return;
    if (!S.lastTs) S.lastTs = ts;
    var dt = Math.min(0.12, (ts - S.lastTs) / 1000);
    S.lastTs = ts;

    var at = spanAt(S.time);
    var inChart = !!at && at.kind === 'chart';

    if (inChart) {
      if (S.audioEl && !S.audioEl.paused && S.audioEl.currentTime > 0.001) {
        S.time = at.start + (S.audioEl.currentTime - audioOffset());
      } else {
        if (S.audioEl && S.audioPending) startAudioAt(S.time);
        S.time += dt;
      }
    } else {
      if (S.audioEl && !S.audioEl.paused) holdAudio();
      S.time += dt;
    }

    // 进入 / 离开谱面场时切音频
    var nowAt = spanAt(S.time);
    if (S.audioEl && nowAt && nowAt.kind === 'chart' && S.audioEl.paused && S.audioPending) {
      startAudioAt(S.time);
    }
    if (S.audioEl && (!nowAt || nowAt.kind !== 'chart') && !S.audioEl.paused) holdAudio();

    if (S.time >= S.total) {
      if (S.loop) {
        S.time = 0;
        holdAudio();
        S.audioPending = !!S.audioEl;
      } else {
        S.time = S.total;
        pause();
        if (S.recorder) stopRecord();
      }
    }

    followPlayhead();
    S.draw(true);
    if (S.playing) requestAnimationFrame(tick);
  }

  /* ==========================================================================
   * 绘制
   * ======================================================================== */

  function requestDraw() {
    if (S.rafPending) return;
    S.rafPending = true;
    requestAnimationFrame(function () {
      S.rafPending = false;
      S.draw(true);
      syncTlScrollbar();
    });
  }

  function drawStage() {
    var r = S.renderer;
    if (!r) return;
    syncVideos(S.time);
    r.render({ t: S.time, doc: S.doc, chart: S.chart, images: S.images, videos: S.videos, phase: S.time });
    var h = $('stage-hint');
    if (h) {
      var nothing = !S.chart && S.doc.scenes.every(function (sc) { return !sc.layers.length; });
      if (nothing) h.removeAttribute('hidden');
      else h.setAttribute('hidden', 'hidden');
    }
  }

  S.draw = function (withStage) {
    if (withStage) drawStage();
    drawTimeline();
    if (typeof syncTlScrollbar === 'function') syncTlScrollbar();
    syncTransport();
    syncStatus();
  };

  function refreshAll() {
    syncTimes();
    renderSceneList();
    renderChartPanel();
    renderAudioPanel();
    renderLayerList();
    renderInspector();
    renderShaderList();
    applyVolume();
    refreshUndo();
    S.draw(true);
  }

  /* ==========================================================================
   * 时间轴
   * ======================================================================== */

  var TL = { padL: 134, padR: 16, topH: 26, bandH: 26, rowH: 21 };

  function tlCanvas() { return $('timeline'); }

  /** 时间轴横向滚动条：thumb 宽度 = 可见时长 / 总时长，位置 = 视图起点 */
  function syncTlScrollbar() {
    var bar = $('tl-scrollbar');
    var thumb = $('tl-thumb');
    if (!bar || !thumb) return;
    var total = Math.max(0.001, S.total);
    if (S.view.span >= total - 1e-6) {
      bar.setAttribute('data-full', '1');
      thumb.style.left = '0px';
      thumb.style.width = '100%';
      return;
    }
    bar.removeAttribute('data-full');
    var w = Math.max(1, bar.clientWidth - 2);
    var ratio = clamp(S.view.span / total, 0.03, 1);
    var thumbW = Math.max(24, Math.round(w * ratio));
    var maxStart = Math.max(0, total - S.view.span);
    var frac = maxStart > 0 ? clamp(S.view.start / maxStart, 0, 1) : 0;
    thumb.style.width = thumbW + 'px';
    thumb.style.left = Math.round((w - thumbW) * frac) + 'px';
  }

  /** 把滚动条上的 x 变成视图起点（点在哪儿就把哪儿移到中间） */
  function scrollToBarX(clientX) {
    var bar = $('tl-scrollbar');
    var thumb = $('tl-thumb');
    if (!bar || !thumb) return;
    var rect = bar.getBoundingClientRect();
    var w = Math.max(1, rect.width - 2);
    var thumbW = Math.max(24, thumb.offsetWidth || 24);
    var maxStart = Math.max(0, S.total - S.view.span);
    if (maxStart <= 0) return;
    var x = clamp(clientX - rect.left - 1 - thumbW / 2, 0, Math.max(0, w - thumbW));
    var frac = (w - thumbW) > 0 ? x / (w - thumbW) : 0;
    S.view.start = frac * maxStart;
    clampView();
    drawTimeline();
    syncTlScrollbar();
  }

  function bindTlScrollbar() {
    var bar = $('tl-scrollbar');
    if (!bar) return;
    bar.addEventListener('pointerdown', function (e) {
      if (S.view.span >= S.total - 1e-6) return;
      bar.classList.add('dragging');
      S.scrollDrag = true;
      bar.setPointerCapture(e.pointerId);
      scrollToBarX(e.clientX);
      e.preventDefault();
    });
    window.addEventListener('pointermove', function (e) {
      if (!S.scrollDrag) return;
      scrollToBarX(e.clientX);
    });
    window.addEventListener('pointerup', function () {
      if (!S.scrollDrag) return;
      S.scrollDrag = false;
      bar.classList.remove('dragging');
    });
    bar.addEventListener('wheel', function (e) {
      e.preventDefault();
      S.view.start += (e.deltaY > 0 ? 1 : -1) * S.view.span * 0.12;
      clampView();
      drawTimeline();
      syncTlScrollbar();
    }, { passive: false });
  }

  function tlSize() {
    var cv = tlCanvas();
    var w = Math.max(200, cv.clientWidth || 0);
    var h = Math.max(60, cv.clientHeight || 0);
    var dpr = Math.min(2, window.devicePixelRatio || 1);
    if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) {
      cv.width = Math.round(w * dpr);
      cv.height = Math.round(h * dpr);
    }
    return { cv: cv, w: w, h: h, dpr: dpr };
  }

  /**
   * 后处理按「时间重叠」自动分层（剪辑软件那种）：
   * 不重叠的排在同一个 lane，只有和 lane 里已有条重叠时才新开一层。
   */
  function shaderLanes(sc) {
    var lanes = [];
    var list = (sc && sc.shaders) || [];
    var sorted = list.slice().sort(function (a, b) { return a.start - b.start; });
    for (var i = 0; i < sorted.length; i++) {
      var fx = sorted[i];
      var placed = false;
      for (var k = 0; k < lanes.length; k++) {
        var last = lanes[k][lanes[k].length - 1];
        if (fx.start >= last.end - 0.001) {
          lanes[k].push(fx);
          placed = true;
          break;
        }
      }
      if (!placed) lanes.push([fx]);
    }
    return lanes;
  }

  function tlLayout() {
    var sz = tlSize();
    var rows = [];
    var rowsY = TL.topH + TL.bandH + 4;
    var sc = curScene();
    // 每条后处理一行（重叠的时间段也能分开看）；一条都没有时留一行空行给「拖出新后处理」
    var lanesTmp = sc ? shaderLanes(sc) : [];
    var shaderRows = sc ? Math.max(1, lanesTmp.length) : 0;
    var count = sc ? sc.layers.length + shaderRows : 0;
    var avail = Math.max(0, sz.h - rowsY - 4);
    // 行多的时候先压行高（21 → 15），再压不下就纵向滚动
    var rowH = count > 0 ? clamp(Math.floor(avail / count) - 1, 15, TL.rowH) : TL.rowH;
    var contentH = count * (rowH + 1);
    var maxScroll = Math.max(0, contentH - avail);
    S.tlScroll = clamp(S.tlScroll, 0, maxScroll);

    var y = rowsY - S.tlScroll;
    if (sc) {
      var disp = sc.layers.slice().reverse();
      for (var i = 0; i < disp.length; i++) {
        rows.push({ kind: 'layer', id: disp[i].id, y: y, h: rowH, label: disp[i].name });
        y += rowH + 1;
      }
      if (!lanesTmp.length) {
        rows.push({ kind: 'shader', y: y, h: rowH, label: '后处理', empty: true, ids: [] });
        y += rowH + 1;
      } else {
        for (var si = 0; si < lanesTmp.length; si++) {
          var lane = lanesTmp[si];
          var names = [];
          for (var lj = 0; lj < lane.length && lj < 2; lj++) {
            var pd = SB.shaderPreset(lane[lj].preset);
            names.push(pd ? pd.label : lane[lj].preset);
          }
          var label = (si + 1) + '. ' + names.join(' + ') + (lane.length > 2 ? ' +' + (lane.length - 2) : '');
          var ids = [];
          for (var li = 0; li < lane.length; li++) ids.push(lane[li].id);
          rows.push({ kind: 'shader', lane: si, ids: ids, y: y, h: rowH, label: label });
          y += rowH + 1;
        }
      }
    }
    return {
      w: sz.w, h: sz.h, dpr: sz.dpr, cv: sz.cv,
      x0: TL.padL, x1: Math.max(TL.padL + 60, sz.w - TL.padR),
      bandY: TL.topH, bandH: TL.bandH,
      rowsY: rowsY, rowH: rowH, contentH: contentH, maxScroll: maxScroll,
      rows: rows, bottom: y
    };
  }

  function txOf(L, t) {
    return L.x0 + ((t - S.view.start) / S.view.span) * (L.x1 - L.x0);
  }

  function tOf(L, x) {
    return S.view.start + ((x - L.x0) / Math.max(1, L.x1 - L.x0)) * S.view.span;
  }

  function clampView() {
    if (!isFinite(S.view.span)) S.view.span = 12;
    if (!isFinite(S.view.start)) S.view.start = 0;
    var maxSpan = Math.max(3, S.total * 1.15);
    if (S.view.span > maxSpan) S.view.span = maxSpan;
    var maxStart = Math.max(0, S.total - S.view.span * 0.2);
    S.view.start = clamp(S.view.start, -0.3, maxStart);
    S.view.span = clamp(S.view.span, 0.5, 600);
  }

  function beatSec() {
    var bpm = SB.num(S.doc.timing && S.doc.timing.bpm, 150);
    return 60 / clamp(bpm, 20, 1000);
  }

  function drawTimeline() {
    if (!tlCanvas()) return;
    var L = tlLayout();
    var g = L.cv.getContext('2d');
    var dpr = L.dpr;
    var list = spans();
    var sc = curScene();
    var cspan = curSpan();

    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, L.w, L.h);
    g.fillStyle = '#07090e';
    g.fillRect(0, 0, L.w, L.h);

    // ---- 拍网格 ----
    var beat = beatSec();
    var bar = beat * 4;
    var pxPerSec = (L.x1 - L.x0) / S.view.span;
    var step = bar;
    while (step * pxPerSec < 34) step *= 2;
    while (step * pxPerSec > 220 && step > beat) step /= 2;

    var t = Math.floor(S.view.start / step) * step;
    while (t <= S.view.start + S.view.span + step) {
      var x = txOf(L, t);
      if (x >= L.x0 - 1 && x <= L.x1 + 1) {
        var isBar = Math.abs(t / bar - Math.round(t / bar)) < 1e-6;
        g.strokeStyle = isBar ? 'rgba(255,255,255,0.10)' : 'rgba(255,255,255,0.045)';
        g.lineWidth = 1;
        g.beginPath();
        g.moveTo(Math.round(x) + 0.5, TL.topH);
        g.lineTo(Math.round(x) + 0.5, L.h);
        g.stroke();
        if (isBar) {
          g.fillStyle = '#3d4658';
          g.font = '10px ui-monospace, Consolas, monospace';
          g.textAlign = 'left';
          g.textBaseline = 'middle';
          g.fillText(fmt(t), x + 3, TL.topH / 2 + 1);
        }
      }
      t += step;
    }

    // ---- 场景带 ----
    for (var i = 0; i < list.length; i++) {
      var sp = list[i];
      var bx = txOf(L, sp.start);
      var bw = Math.max(2, txOf(L, sp.end) - bx);
      if (bx + bw < L.x0 || bx > L.x1) continue;
      var active = sp.scene.id === S.sceneId;
      var fill = sp.kind === 'chart' ? 'rgba(76,201,240,' + (active ? 0.26 : 0.14) + ')'
        : sp.kind === 'unlock' ? 'rgba(247,37,133,' + (active ? 0.26 : 0.13) + ')'
          : 'rgba(124,245,193,' + (active ? 0.24 : 0.12) + ')';
      var stroke = sp.kind === 'chart' ? '#4cc9f0' : sp.kind === 'unlock' ? '#f72585' : '#7cf5c1';

      var cx0 = Math.max(L.x0, bx);
      var cw = Math.max(2, Math.min(L.x1, bx + bw) - cx0);
      g.fillStyle = fill;
      roundRectPath(g, cx0, L.bandY + 2, cw, L.bandH - 4, 4);
      g.fill();
      g.strokeStyle = active ? stroke : 'rgba(255,255,255,0.14)';
      g.lineWidth = active ? 1.5 : 1;
      roundRectPath(g, cx0, L.bandY + 2, cw, L.bandH - 4, 4);
      g.stroke();

      if (cw > 44) {
        g.save();
        g.beginPath();
        g.rect(cx0 + 3, L.bandY, cw - 6, L.bandH);
        g.clip();
        g.fillStyle = active ? '#ffffff' : '#9aa6bb';
        g.font = '11px ui-sans-serif, system-ui, "Microsoft YaHei", sans-serif';
        g.textAlign = 'left';
        g.textBaseline = 'middle';
        g.fillText(sp.scene.name, cx0 + 7, L.bandY + L.bandH / 2 - 1);
        g.restore();
      }
    }

    // 谱面场里叠一条音符密度
    var csp = chartSpan();
    if (csp) {
      var d0 = txOf(L, csp.start);
      var d1 = txOf(L, csp.end);
      if (d1 > L.x0 && d0 < L.x1) {
        var count = Math.max(1, Math.round(L.x1 - L.x0));
        var buckets = chartBuckets(count, csp);
        var maxN = 1;
        for (var bi = 0; bi < buckets.length; bi++) if (buckets[bi] > maxN) maxN = buckets[bi];
        g.save();
        g.beginPath();
        g.rect(Math.max(L.x0, d0), L.bandY + 2, Math.min(L.x1, d1) - Math.max(L.x0, d0), L.bandH - 4);
        g.clip();
        for (var b = 0; b < buckets.length; b++) {
          if (!buckets[b]) continue;
          var hh = (buckets[b] / maxN) * (L.bandH - 6);
          g.fillStyle = 'rgba(200,240,255,' + (0.18 + 0.45 * (buckets[b] / maxN)).toFixed(3) + ')';
          g.fillRect(L.x0 + b, L.bandY + L.bandH - 3 - hh, 1, hh);
        }
        g.restore();
      }
    }

    // ---- 当前场景以外的区域压暗 ----
    if (cspan) {
      var sx0 = txOf(L, cspan.start);
      var sx1 = txOf(L, cspan.end);
      g.fillStyle = 'rgba(3,5,9,0.55)';
      if (sx0 > L.x0) g.fillRect(L.x0, L.topH + TL.bandH + 2, Math.min(L.x1, sx0) - L.x0, L.h - L.topH - TL.bandH);
      if (sx1 < L.x1) g.fillRect(Math.max(L.x0, sx1), TL.topH + TL.bandH + 2, L.x1 - Math.max(L.x0, sx1), L.h - TL.topH - TL.bandH);
    }

    // ---- 行（超出可视区就靠 tlScroll 滚，clip 住防止画到场景带上）----
    g.save();
    g.beginPath();
    g.rect(0, L.rowsY, L.w, Math.max(0, L.h - L.rowsY));
    g.clip();
    for (var r = 0; r < L.rows.length; r++) {
      var row = L.rows[r];
      var selected = (row.kind === 'layer' && S.selKind === 'layer' && row.id === S.selId) ||
        (row.kind === 'shader' && S.selKind === 'shader');
      g.fillStyle = row.kind === 'layer' && selected ? 'rgba(76,201,240,0.07)' : 'rgba(255,255,255,0.022)';
      g.fillRect(0, row.y, L.w, row.h);
      g.fillStyle = row.kind === 'layer' && selected ? '#cdf3ff' : '#8a93a6';
      g.font = '11px ui-sans-serif, system-ui, "Microsoft YaHei", sans-serif';
      g.textAlign = 'left';
      g.textBaseline = 'middle';
      var label = row.kind === 'layer'
        ? (SB.layerIndex(sc, row.id) + 1) + '. ' + row.label
        : row.label;
      g.fillText(cut(g, label, TL.padL - 12), 8, row.y + row.h / 2);
    }

    // ---- 图层条（场景内本地时间 → 全局坐标）----
    if (sc && cspan) {
      for (var li = 0; li < sc.layers.length; li++) {
        var layer = sc.layers[li];
        var rowOf = null;
        for (var q = 0; q < L.rows.length; q++) {
          if (L.rows[q].kind === 'layer' && L.rows[q].id === layer.id) { rowOf = L.rows[q]; break; }
        }
        if (!rowOf) continue;
        var gx1 = txOf(L, cspan.start + layer.start);
        var gx2 = txOf(L, cspan.start + layer.end);
        if (gx2 < L.x0 || gx1 > L.x1) continue;
        var lg = barGeom(L, gx1, gx2);
        var rx = lg.x;
        var rw = lg.w;
        var on = S.selKind === 'layer' && S.selId === layer.id;

        g.fillStyle = on ? 'rgba(76,201,240,0.85)' : layerColor(layer, 0.55);
        g.strokeStyle = on ? '#cdf3ff' : layerColor(layer, 0.9);
        g.lineWidth = 1;
        roundRectPath(g, rx, rowOf.y + 3, rw, rowOf.h - 6, 4);
        g.fill();
        g.stroke();

        if (rw > 46) {
          g.save();
          g.beginPath();
          g.rect(rx + 2, rowOf.y, rw - 4, rowOf.h);
          g.clip();
          g.fillStyle = '#05070c';
          g.font = '10px ui-sans-serif, system-ui, "Microsoft YaHei", sans-serif';
          g.textAlign = 'left';
          g.textBaseline = 'middle';
          g.fillText(layer.name, rx + 5, rowOf.y + rowOf.h / 2);
          g.restore();
        }

        for (var c = 0; c < SB.CHANNELS.length; c++) {
          var evs = (layer.events && layer.events[SB.CHANNELS[c]]) || [];
          for (var e = 0; e < evs.length; e++) {
            var kx = txOf(L, cspan.start + evs[e].start);
            if (kx < L.x0 || kx > L.x1) continue;
            g.fillStyle = 'rgba(255,255,255,0.75)';
            g.fillRect(kx, rowOf.y + 2, 1.5, 4);
          }
        }
      }
    }

    // ---- Shader 条（按重叠自动分层：不重叠的在同一行）----
    if (sc && cspan) {
      var shaderRowsAll = [];
      for (var s3 = 0; s3 < L.rows.length; s3++) {
        if (L.rows[s3].kind === 'shader' && L.rows[s3].ids && L.rows[s3].ids.length) shaderRowsAll.push(L.rows[s3]);
      }
      for (var s4 = 0; s4 < shaderRowsAll.length; s4++) {
        var srow = shaderRowsAll[s4];
        for (var s5 = 0; s5 < srow.ids.length; s5++) {
          var fx = SB.findShader(sc, srow.ids[s5]);
          if (!fx) continue;
          var fx1 = txOf(L, cspan.start + fx.start);
        var fx2 = txOf(L, cspan.start + fx.end);
        if (fx2 < L.x0 || fx1 > L.x1) continue;
        var sg = barGeom(L, fx1, fx2);
        var frx = sg.x;
        var frw = sg.w;
        var son = S.selKind === 'shader' && S.selId === fx.id;
        g.fillStyle = son ? 'rgba(247,37,133,0.85)' : 'rgba(247,37,133,0.42)';
        g.strokeStyle = son ? '#ffb3d1' : 'rgba(247,37,133,0.9)';
        roundRectPath(g, frx, srow.y + 4, frw, srow.h - 8, 4);
        g.fill();
        g.stroke();
        if (frw > 54) {
          g.save();
          g.beginPath();
          g.rect(frx + 2, srow.y, frw - 4, srow.h);
          g.clip();
          g.fillStyle = '#fff';
          g.font = '10px ui-sans-serif, system-ui, "Microsoft YaHei", sans-serif';
          g.textAlign = 'left';
          g.textBaseline = 'middle';
          g.fillText(SB.label(SB.SHADER_PRESETS, fx.preset), frx + 5, srow.y + srow.h / 2);
          g.restore();
        }
      }
      }
    }

    g.restore();

    // ---- 图层行滚动条（层多时才有）----
    if (L.maxScroll > 0.5) {
      var trackX = L.w - 7;
      var trackY = L.rowsY;
      var trackH = Math.max(20, L.h - L.rowsY - 4);
      g.fillStyle = 'rgba(255,255,255,0.06)';
      g.fillRect(trackX, trackY, 3, trackH);
      var thumbH = Math.max(16, trackH * (trackH / Math.max(1, L.contentH)));
      var thumbY = trackY + (trackH - thumbH) * (S.tlScroll / L.maxScroll);
      g.fillStyle = 'rgba(76,201,240,0.55)';
      g.fillRect(trackX, thumbY, 3, thumbH);
    }

    // ---- 总时长之后的区域压暗 ----
    var endX = txOf(L, S.total);
    if (endX < L.x1 - 1) {
      var shadeX = Math.max(L.x0, endX);
      g.fillStyle = 'rgba(0,0,0,0.45)';
      g.fillRect(shadeX, TL.topH, L.x1 - shadeX, L.h - TL.topH);
      if (endX >= L.x0) {
        g.save();
        g.strokeStyle = 'rgba(255,209,102,0.45)';
        g.setLineDash([4, 4]);
        g.beginPath();
        g.moveTo(endX + 0.5, TL.topH);
        g.lineTo(endX + 0.5, L.h);
        g.stroke();
        g.restore();
      }
    }

    // ---- 播放头 ----
    var px = txOf(L, S.time);
    if (px >= L.x0 - 1 && px <= L.x1 + 1) {
      g.strokeStyle = '#4cc9f0';
      g.lineWidth = 1.5;
      g.beginPath();
      g.moveTo(px, TL.topH - 6);
      g.lineTo(px, L.h);
      g.stroke();
      g.fillStyle = '#4cc9f0';
      g.beginPath();
      g.moveTo(px - 5, TL.topH - 12);
      g.lineTo(px + 5, TL.topH - 12);
      g.lineTo(px, TL.topH - 3);
      g.closePath();
      g.fill();
    }

    g.strokeStyle = '#222836';
    g.lineWidth = 1;
    g.beginPath();
    g.moveTo(TL.padL - 0.5, 0);
    g.lineTo(TL.padL - 0.5, L.h);
    g.stroke();

    // 空场景提示
    if (sc && !sc.layers.length && !sc.shaders.length) {
      g.fillStyle = 'rgba(138,147,166,0.55)';
      g.font = '11px ui-sans-serif, system-ui, "Microsoft YaHei", sans-serif';
      g.textAlign = 'left';
      g.textBaseline = 'middle';
      g.fillText('这一场还没有图层 —— 左边「添加图层」或套模板', TL.padL + 10, Math.min(L.h - 12, L.bottom + 14));
    }
  }

  function cut(g, text, maxW) {
    var s = String(text || '');
    if (g.measureText(s).width <= maxW) return s;
    while (s.length > 1 && g.measureText(s + '…').width > maxW) s = s.slice(0, -1);
    return s + '…';
  }

  function roundRectPath(g, x, y, w, h, r) {
    var rr = Math.max(0, Math.min(r, Math.min(w, h) / 2));
    g.beginPath();
    g.moveTo(x + rr, y);
    g.lineTo(x + w - rr, y);
    g.quadraticCurveTo(x + w, y, x + w, y + rr);
    g.lineTo(x + w, y + h - rr);
    g.quadraticCurveTo(x + w, y + h, x + w - rr, y + h);
    g.lineTo(x + rr, y + h);
    g.quadraticCurveTo(x, y + h, x, y + h - rr);
    g.lineTo(x, y + rr);
    g.quadraticCurveTo(x, y, x + rr, y);
    g.closePath();
  }

  function layerColor(layer, a) {
    var map = { text: '#4cc9f0', unlock: '#f72585', shape: '#7cf5c1', image: '#ffd166' };
    return SB.hexA(map[layer.type] || '#8a93a6', a);
  }

  /** 谱面场里的音符密度（按当前视图的像素宽度分桶） */
  /**
   * 谱面密度分桶。按**当前视图窗口**分桶（不是整首谱面），这样缩放 / 平移时
   * 纹理和下面的时间轴一一对应，不会出现"密度不动、还错位"。
   */
  function chartBuckets(count, csp) {
    var arr = new Array(count);
    for (var i = 0; i < count; i++) arr[i] = 0;
    if (!S.chart || !csp) return arr;
    var v0 = S.view.start;
    var v1 = S.view.start + S.view.span;
    var span = Math.max(0.001, v1 - v0);
    for (var n = 0; n < S.chart.notes.length; n++) {
      var gt = csp.start + S.chart.notes[n].time;    // 音符的全局时间
      if (gt < v0 || gt > v1) continue;
      var idx = Math.floor(((gt - v0) / span) * count);
      if (idx < 0) idx = 0;
      if (idx >= count) idx = count - 1;
      arr[idx]++;
    }
    return arr;
  }

  /* ---------- 吸附 / 命中 ---------- */

  function snapT(t) {
    var v = S.snap ? SB.snapTime(t, S.doc.timing, S.div) : t;
    return SB.round3(clamp(v, -0.5, Math.max(60, S.total + 60)));
  }

  /** 全局时间 → 当前场景内的本地时间（吸附后再相减） */
  function snapLocal(tGlobal) {
    var sp = curSpan();
    var base = sp ? sp.start : 0;
    return SB.round3(clamp(snapT(tGlobal) - base, 0, Math.max(0.05, (sp ? sp.len : 1) - 0.05)));
  }

  function tlHit(mx, my) {
    var L = tlLayout();
    if (my < TL.topH) return { type: 'ruler' };
    if (my >= L.bandY && my <= L.bandY + L.bandH) {
      var list = spans();
      for (var i = 0; i < list.length; i++) {
        var a = txOf(L, list[i].start);
        var b = txOf(L, list[i].end);
        if (mx >= a - 3 && mx <= b + 3) {
          // 谱面场的右边缘也返回 'end'：点上去会提示「拉不长」，而不是把播放头跳回场首
          var edge = (Math.abs(mx - b) <= 6) ? 'end' : 'move';
          return { type: 'scene', id: list[i].scene.id, mode: edge };
        }
      }
      return { type: 'band' };
    }
    if (my < L.rowsY) return { type: 'band' };
    if (mx < L.x0 || mx > L.x1) return { type: 'empty' };

    var sc = curScene();
    var cspan = curSpan();
    for (var r = 0; r < L.rows.length; r++) {
      var row = L.rows[r];
      if (my < row.y || my > row.y + row.h) continue;

      if (row.kind === 'shader') {
        if (!sc || !cspan) return { type: 'row', rowKind: 'shader' };
        if (row.empty || !row.ids || !row.ids.length) return { type: 'row', rowKind: 'shader' };   // 空行：拖一下新建
        for (var si = 0; si < row.ids.length; si++) {
          var fx = SB.findShader(sc, row.ids[si]);
          if (!fx) continue;
          var gs = barGeom(L, txOf(L, cspan.start + fx.start), txOf(L, cspan.start + fx.end));
          var ms = barMode(mx, gs);
          if (ms) return { type: 'shader', id: fx.id, mode: ms };
        }
        return { type: 'row', rowKind: 'shader' };
      }

      if (row.kind === 'layer') {
        var layer = sc ? SB.findLayer(sc, row.id) : null;
        if (!layer || !cspan) return { type: 'row' };
        var gl = barGeom(L, txOf(L, cspan.start + layer.start), txOf(L, cspan.start + layer.end));
        var ml = barMode(mx, gl);
        if (ml) return { type: 'layer', id: layer.id, mode: ml };
        return { type: 'row' };
      }
    }
    return { type: 'empty' };
  }

  /** 时间轴上的条：最细也给 10px 宽，否则缩得很小的时候根本点不中 */
  function barGeom(L, x1, x2) {
    var rx = Math.max(L.x0, x1);
    var rw = Math.max(10, Math.min(L.x1, x2) - rx);
    return { x: rx, w: rw };
  }

  /**
   * 鼠标在条上的哪个部位：
   *   'start' / 'end' = 拖两端改起止，'move' = 整条平移，null = 没点到
   * 条太窄（< 18px）时**不做边缘裁剪**，整条都是平移 —— 不然缩远了整条都在"边缘"上，就变成拖不动了。
   */
  function barMode(mx, g) {
    var tol = 4;
    if (mx < g.x - tol || mx > g.x + g.w + tol) return null;
    if (g.w < 18) return 'move';
    var zone = clamp(Math.round(g.w * 0.25), 3, 6);
    if (Math.abs(mx - g.x) <= zone) return 'start';
    if (Math.abs(mx - (g.x + g.w)) <= zone) return 'end';
    return 'move';
  }

  function bindTimeline() {
    var cv = tlCanvas();

    cv.addEventListener('pointerdown', function (e) {
      var L = tlLayout();
      var rect = cv.getBoundingClientRect();
      var mx = e.clientX - rect.left;
      var my = e.clientY - rect.top;
      var hit = tlHit(mx, my);
      var tAt = tOf(L, mx);

      if (hit.type === 'scene') {
        var sp = spanOf(hit.id);
        S.sceneId = hit.id;
        S.selKind = 'scene';
        S.selId = hit.id;
        if (hit.mode === 'end' && sp) {
          if (sp.kind === 'chart') {
            // 谱面场时长 = 谱面时长（只读），拉不动；给一句明确的提示
            hint('谱面场时长跟着谱面走（' + fmt(sp.len) + '），拉不长。想更长就在前面加【+ 解锁场】、后面加【+ 演出场】。');
            renderSceneList();
            renderInspector();
            return;
          }
          pushUndo();
          S.editOpen = true;
          S.drag = { type: 'sceneEnd', kind: 'scene', id: hit.id, x0: mx, lastX: mx, len0: sp.len };
        } else {
          seek(sp ? sp.start : 0);
        }
        renderSceneList();
        renderLayerList();
        renderInspector();
        renderShaderList();
        requestDraw();
        cv.setPointerCapture(e.pointerId);
        return;
      }

      if (hit.type === 'layer') {
        S.selKind = 'layer';
        S.selId = hit.id;
        renderLayerList();
        renderInspector();
        renderShaderList();
        pushUndo();
        S.editOpen = true;
        var layer = SB.findLayer(curScene(), hit.id);
        S.drag = {
          type: hit.mode, kind: 'layer', id: hit.id,
          x0: mx, lastX: mx,
          start0: layer.start, end0: layer.end
        };
      } else if (hit.type === 'shader') {
        S.selKind = 'shader';
        S.selId = hit.id;
        renderLayerList();
        renderInspector();
        renderShaderList();
        pushUndo();
        S.editOpen = true;
        var fx = SB.findShader(curScene(), hit.id);
        S.drag = {
          type: hit.mode, kind: 'shader', id: hit.id,
          x0: mx, lastX: mx,
          start0: fx.start, end0: fx.end
        };
      } else if (e.shiftKey || e.button === 1) {
        // Shift + 拖动 / 中键拖动 = 平移视图（剪辑软件习惯）
        if (e.button === 1) e.preventDefault();
        S.drag = { type: 'pan', x0: mx, viewStart0: S.view.start };
        cv.setPointerCapture(e.pointerId);
        cv.style.cursor = 'grabbing';
        requestDraw();
        return;
      } else if (hit.type === 'row' && hit.rowKind === 'shader') {
        // 后处理行空白：拖一下 = 拉出一条新的后处理；只点不拖 = 移动播放头
        S.drag = { type: 'pendingShader', x0: mx, t0: tOf(L, mx) };
        cv.setPointerCapture(e.pointerId);
        requestDraw();
        return;
      } else {
        S.drag = { type: 'seek' };
        seek(snapT(tAt));
      }

      cv.setPointerCapture(e.pointerId);
      requestDraw();
    });

    cv.addEventListener('pointermove', function (e) {
      var cv2 = tlCanvas();
      var L = tlLayout();
      var rect = cv2.getBoundingClientRect();
      var mx = e.clientX - rect.left;
      var my = e.clientY - rect.top;

      if (!S.drag) {
        var h = tlHit(mx, my);
        var sceneEditable = true;
        if (h.type === 'scene') {
          var hsp = spanOf(h.id);
          sceneEditable = !(hsp && hsp.kind === 'chart');
        }
        cv2.style.cursor = (h.type === 'scene')
          ? (h.mode === 'end' ? (sceneEditable ? 'ew-resize' : 'not-allowed') : 'pointer')
          : (h.type === 'layer' || h.type === 'shader')
            ? (h.mode === 'move' ? 'grab' : 'ew-resize')
            : (h.type === 'ruler' ? 'ew-resize' : 'pointer');
        return;
      }

      if (S.drag.type === 'seek') {
        seek(snapT(tOf(L, mx)));
        return;
      }
      cv2.style.cursor = 'grabbing';

      var sp = curSpan();

      // 平移视图（Shift / 中键拖动）
      if (S.drag.type === 'pan') {
        var dx = (mx - S.drag.x0) / Math.max(1, L.x1 - L.x0) * S.view.span;
        S.view.start = S.drag.viewStart0 - dx;
        clampView();
        drawTimeline();
        return;
      }

      // 后处理行空白：拖动超过 6px 才真的拉一条出来（避免误触）
      if (S.drag.type === 'pendingShader') {
        if (Math.abs(mx - S.drag.x0) < 6) return;
        var sceneP = curScene();
        var spP = curSpan();
        if (!sceneP || !spP) { S.drag = null; return; }
        var lenP = sceneLen(sceneP);
        var tA = Math.min(S.drag.t0, tOf(L, mx)) - spP.start;
        var tB = Math.max(S.drag.t0, tOf(L, mx)) - spP.start;
        var sA = clamp(SB.round3(tA), 0, Math.max(0, lenP - 0.2));
        var sB = clamp(SB.round3(tB), sA + 0.1, Math.max(sA + 0.1, lenP));
        pushUndo();
        var newFx = SB.addShader(sceneP, $('shader-preset').value, { start: sA, end: sB, amount: 80, ramp: 0.28 });
        S.selKind = 'shader';
        S.selId = newFx.id;
        S.drag = { type: 'end', kind: 'shader', id: newFx.id, x0: mx, lastX: mx, start0: sA, end0: sB };
        syncTimes();
        renderShaderList();
        renderInspector();
        renderLayerList();
        requestDraw();
        hint('在「' + sceneP.name + '」拉出一条后处理：' + SB.label(SB.SHADER_PRESETS, newFx.preset));
        return;
      }

      // 位移一律按「相对按下点的总位移」算：每帧增量加在起点上会让条只挪 1/N
      var grabX = (S.drag.x0 === undefined) ? mx : S.drag.x0;
      var totalSeconds = ((mx - grabX) / Math.max(1, L.x1 - L.x0)) * S.view.span;
      S.drag.lastX = mx;

      if (S.drag.type === 'sceneEnd') {
        var scEnd = SB.findScene(S.doc, S.drag.id);
        if (!scEnd || scEnd.kind === 'chart') return;
        scEnd.length = SB.round3(clamp(S.drag.len0 + totalSeconds, 0.2, 120));
        syncTimes();
        requestDraw();
        renderSceneList();
        return;
      }

      if (!sp) return;
      var seconds = totalSeconds;

      var scene = curScene();
      var item = S.drag.kind === 'layer'
        ? SB.findLayer(scene, S.drag.id)
        : SB.findShader(scene, S.drag.id);
      if (!item) return;

      var len = sceneLen(scene);
      var minGap = 0.05;
      // 场景内本地时间（只吸附，不做上限夹 —— 拖过场景末尾时按需把场景加长）
      function toLocal(globalT) {
        return SB.round3(snapT(globalT) - sp.start);
      }
      // 谱面场的长度由谱面决定，不能拖长；解锁场 / 演出场可以跟着条一起长
      var canGrow = SB.sceneKind(scene.kind) !== 'chart';

      if (S.drag.type === 'move') {
        var dur = Math.max(minGap, S.drag.end0 - S.drag.start0);
        var nl = Math.max(0, toLocal(sp.start + S.drag.start0 + seconds));
        if (nl + dur > len + 1e-6) {
          if (canGrow) {
            scene.length = SB.round3(nl + dur);
            len = scene.length;
          } else {
            nl = Math.max(0, len - dur);      // 谱面场：贴住末尾，保住长度
          }
        }
        item.start = SB.round3(nl);
        item.end = SB.round3(nl + dur);
      } else if (S.drag.type === 'start') {
        var ns = toLocal(sp.start + S.drag.start0 + seconds);
        item.start = SB.round3(clamp(ns, 0, item.end - minGap));
      } else if (S.drag.type === 'end') {
        var ne = Math.max(item.start + minGap, toLocal(sp.start + S.drag.end0 + seconds));
        if (ne > len + 1e-6) {
          if (canGrow) {
            scene.length = SB.round3(ne);
            len = scene.length;
          } else {
            ne = Math.max(item.start + minGap, len);
          }
        }
        item.end = SB.round3(ne);
      }

      syncTimes();
      requestDraw();
      syncTimeFields();
    });

    function stopDrag() {
      if (!S.drag) return;
      if (S.drag.type === 'pendingShader') {
        // 只按没拖：当成"点空白 = 移动播放头"
        var L2 = tlLayout();
        var t2 = tOf(L2, S.drag.x0);
        S.drag = null;
        seek(snapT(t2));
        return;
      }
      if (S.drag.type !== 'seek' && S.drag.type !== 'pan') {
        endEdit();
        syncTimes();
        syncTimeFields();
        renderSceneList();
        requestDraw();
      }
      S.drag = null;
      cv.style.cursor = '';
    }


    /** 右键时间轴：删掉点中的那条（图层 / 后处理 / 场景），都能 Ctrl+Z 撤销 */
    cv.addEventListener('contextmenu', function (e) {
      e.preventDefault();
      var L = tlLayout();
      var rect = cv.getBoundingClientRect();
      var mx = e.clientX - rect.left;
      var my = e.clientY - rect.top;
      var hit = tlHit(mx, my);
      var sc = curScene();

      if (hit.type === 'layer' && sc) {
        var lay = SB.findLayer(sc, hit.id);
        if (!lay) return;
        pushUndo();
        SB.removeLayer(sc, hit.id);
        if (S.selKind === 'layer' && S.selId === hit.id) { S.selKind = 'none'; S.selId = 0; }
        refreshAll();
        hint('已删除图层「' + lay.name + '」（Ctrl+Z 撤销）');
        return;
      }

      if (hit.type === 'shader' && sc) {
        var fx = SB.findShader(sc, hit.id);
        if (!fx) return;
        var pdef = SB.shaderPreset(fx.preset);
        pushUndo();
        SB.removeShader(sc, hit.id);
        if (S.selKind === 'shader' && S.selId === hit.id) { S.selKind = 'none'; S.selId = 0; }
        refreshAll();
        hint('已删除后处理「' + (pdef ? pdef.label : fx.preset) + '」（Ctrl+Z 撤销）');
        return;
      }

      if (hit.type === 'scene') {
        var sp = spanOf(hit.id);
        if (!sp) return;
        var name = sp.scene.name;
        pushUndo();
        if (!SB.removeScene(S.doc, hit.id)) {
          hint('最后一场不能删；想清空内容可以直接删它下面的图层');
          return;
        }
        S.sceneId = S.doc.scenes[0].id;
        S.selKind = 'scene';
        S.selId = S.sceneId;
        S.drag = null;
        clampView();
        refreshAll();
        hint('已删除场景「' + name + '」（Ctrl+Z 撤销）');
        return;
      }
    });
    window.addEventListener('pointerup', stopDrag);
    // 指针被浏览器取消（触摸滚动 / 手势 / 窗口失焦）也要收尾，不然会卡在拖动状态
    window.addEventListener('pointercancel', stopDrag);
    window.addEventListener('blur', stopDrag);

    cv.addEventListener('wheel', function (e) {
      e.preventDefault();
      var L = tlLayout();
      var rect = cv.getBoundingClientRect();
      var mx = e.clientX - rect.left;
      if (!isFinite(mx)) mx = (L.x0 + L.x1) / 2;
      if (e.ctrlKey || e.metaKey) {
        var tAt = tOf(L, mx);
        var factor = e.deltaY > 0 ? 1.14 : 1 / 1.14;
        S.view.span = clamp(S.view.span * factor, 0.5, 600);
        var frac = (mx - L.x0) / (L.x1 - L.x0);
        S.view.start = tAt - frac * S.view.span;
      } else if (L.maxScroll > 0.5 && !e.shiftKey && my > L.rowsY) {
        S.tlScroll = clamp(S.tlScroll + (e.deltaY > 0 ? 1 : -1) * 24, 0, L.maxScroll);
      } else {
        S.view.start += (e.deltaY > 0 ? 1 : -1) * S.view.span * 0.08;
      }
      syncTlScrollbar();
      clampView();
      syncZoomSlider();
      drawTimeline();
    }, { passive: false });
  }

  /** 拖时间轴时只同步起止时间输入框 */
  function syncTimeFields() {
    var box = $('inspector');
    var target = selectedLayer() || (S.selKind === 'shader' ? SB.findShader(curScene(), S.selId) : null);
    if (box && target) {
      var a = box.querySelector('[data-path="start"]');
      var b = box.querySelector('[data-path="end"]');
      if (a) a.value = SB.round3(target.start);
      if (b) b.value = SB.round3(target.end);
    }
    if (S.selKind === 'shader') {
      var fx = SB.findShader(curScene(), S.selId);
      var item = $('shader-list') && $('shader-list').querySelector('.shader-item.on');
      if (fx && item) {
        var si = item.querySelector('[data-shader-field="start"]');
        var ei = item.querySelector('[data-shader-field="end"]');
        if (si) si.value = SB.round3(fx.start);
        if (ei) ei.value = SB.round3(fx.end);
      }
    }
  }

  /* ==========================================================================
   * 侧栏：场景列表
   * ======================================================================== */

  function renderSceneList() {
    var list = spans();
    var html = list.map(function (sp) {
      var on = sp.scene.id === S.sceneId;
      var kindLabel = SB.SCENE_MAP[sp.kind] ? SB.SCENE_MAP[sp.kind].label : sp.kind;
      var lenTxt = sp.kind === 'chart' ? '跟随谱面' : fmt(sp.len).replace('00:', '');
      return '<li class="scene-item' + (on ? ' on' : '') + '" data-scid="' + sp.scene.id + '">' +
        '<span class="scene-kind ' + (KIND_CLASS[sp.kind] || '') + '">' + esc(kindLabel) + '</span>' +
        '<div style="min-width:0">' +
          '<div class="scene-name">' + esc(sp.scene.name) + '</div>' +
          '<div class="scene-len">' + esc(lenTxt) + (sp.kind === 'chart' ? '' : 's') + '</div>' +
        '</div>' +
        '<div class="lacts">' +
          '<button class="lbtn" data-scene-act="up" title="往前挪">▲</button>' +
          '<button class="lbtn" data-scene-act="down" title="往后挪">▼</button>' +
          '<button class="lbtn" data-scene-act="del" title="删除场景">✕</button>' +
        '</div>' +
      '</li>';
    }).join('');
    $('scene-list').innerHTML = html || '<li style="font-size:11px;color:#5d6678;padding:4px">没有场景</li>';
    $('btn-add-chart').disabled = !!chartSpan();
  }

  function bindSceneList() {
    $('scene-list').addEventListener('click', function (e) {
      var li = e.target.closest('.scene-item');
      if (!li) return;
      var id = parseInt(li.dataset.scid, 10);
      var btn = e.target.closest('button[data-scene-act]');
      S.sceneId = id;
      S.selKind = 'scene';
      S.selId = id;

      if (btn) {
        var act = btn.dataset.sceneAct;
        var sc = SB.findScene(S.doc, id);
        pushUndo();
        if (act === 'up') SB.moveScene(S.doc, id, -1);
        else if (act === 'down') SB.moveScene(S.doc, id, 1);
        else if (act === 'del') {
          if (!SB.removeScene(S.doc, id)) {
            hint('至少要留一场，删不掉');
          } else {
            S.sceneId = S.doc.scenes.length ? S.doc.scenes[0].id : 0;
            S.selKind = 'scene';
            S.selId = S.sceneId;
            hint('已删除场景「' + (sc ? sc.name : '') + '」');
          }
        }
        syncTimes();
        clampView();
        var sp = spanOf(S.sceneId);
        if (sp) seek(sp.start);
        refreshAll();
        return;
      }

      var sp = spanOf(id);
      if (sp) seek(sp.start);
      renderSceneList();
      renderLayerList();
      renderInspector();
      renderShaderList();
      requestDraw();
    });

    var addBtns = document.querySelectorAll('[data-add-scene]');
    for (var i = 0; i < addBtns.length; i++) {
      addBtns[i].addEventListener('click', function (e) {
        addSceneOfKind(e.currentTarget.dataset.addScene);
      });
    }
  }

  function addSceneOfKind(kind) {
    if (kind === 'chart' && chartSpan()) {
      hint('已经有谱面场了：一段故事板里只放一次谱面');
      return;
    }
    pushUndo();
    var idx = S.doc.scenes.length;
    if (kind === 'unlock') {
      var cs = chartSpan();
      idx = cs ? cs.index : S.doc.scenes.length;      // 解锁场默认插在谱面场前面
    } else if (kind === 'chart') {
      var us = spans();
      var lastUnlock = -1;
      for (var i = 0; i < us.length; i++) if (us[i].kind === 'unlock') lastUnlock = i;
      idx = lastUnlock >= 0 ? lastUnlock + 1 : S.doc.scenes.length;
    }
    var sc = SB.addScene(S.doc, kind, { index: idx });
    S.sceneId = sc.id;
    S.selKind = 'scene';
    S.selId = sc.id;
    syncTimes();
    clampView();
    var sp = spanOf(sc.id);
    if (sp) seek(sp.start);
    refreshAll();
    hint('加了「' + sc.name + '」' + (kind === 'unlock' ? '（在谱面之前）' : ''));
  }

  /* ==========================================================================
   * 侧栏：谱面卡片
   * ======================================================================== */

  function renderChartPanel() {
    var c = S.doc.chart;
    $('chart-title').textContent = c.title || '还没导入谱面';
    $('chart-artist').textContent = c.artist || '—';
    $('chart-charter').textContent = c.charter ? '谱师 ' + c.charter : '—';
    $('chart-illust').textContent = c.illustrator ? '曲绘 ' + c.illustrator : '—';
    $('kv-notes').textContent = c.notes || 0;
    $('kv-len').textContent = fmt(c.duration || 0);
    $('kv-bpm').textContent = c.bpm || 150;
    $('kv-lanes').textContent = c.lanes || 4;

    var chips = [];
    if (S.chart) {
      chips.push('<span class="chip accent">' + esc(c.difficulty || 'NORMAL') + '</span>');
      chips.push('<span class="chip">Lv ' + esc(c.level || 1) + '</span>');
      if (c.file) chips.push('<span class="chip">' + esc(c.file) + '</span>');
      if (c.hash) chips.push('<span class="chip">#' + esc(c.hash) + '</span>');
      if (S.doc.meta.coverArtist) chips.push('<span class="chip">曲绘 · ' + esc(S.doc.meta.coverArtist) + '</span>');
    }
    $('chart-chips').innerHTML = chips.join('');

    var img = $('cover-img');
    if (S.coverUrl) {
      img.src = S.coverUrl;
      img.removeAttribute('hidden');
    } else {
      img.removeAttribute('src');
      img.setAttribute('hidden', 'hidden');
    }

    $('f-illust').value = S.doc.meta.coverArtist || '';
    $('f-illust').placeholder = c.illustrator
      ? '空 = 用谱面的「' + c.illustrator + '」'
      : '谱面没有这一栏，存在故事板里';
    $('st-chart-alpha').value = S.doc.stage.chartAlpha;
    $('st-chart-alpha-txt').textContent = Math.round(S.doc.stage.chartAlpha) + '%';
    $('st-highway').value = S.doc.stage.highway;
    $('st-chart-base').value = String(SB.num(S.doc.stage.chartBase, 350));
    $('st-total-txt').textContent = fmt(S.total) + '（' + S.doc.scenes.length + ' 场）';
    $('st-bg').value = S.doc.stage.bg;
  }

  /* ==========================================================================
   * 侧栏：图层列表（当前场景）
   * ======================================================================== */

  function renderLayerList() {
    var sc = curScene();
    var layers = sc ? sc.layers : [];
    var disp = layers.slice().reverse();
    var html = disp.map(function (L) {
      var on = S.selKind === 'layer' && S.selId === L.id;
      var sub = SB.describeLayer(L) + ' · ' + SB.round3(L.start) + '–' + SB.round3(L.end) + 's';
      return '<li class="layer-item' + (on ? ' on' : '') + (L.visible === false ? ' dead' : '') + '" data-lid="' + L.id + '">' +
        '<span class="dot" style="background:' + layerColor(L, 0.95) + '"></span>' +
        '<div style="min-width:0">' +
          '<div class="lname">' + esc(L.name) + '</div>' +
          '<div class="lsub">' + esc(sub) + '</div>' +
        '</div>' +
        '<div class="lacts">' +
          '<button class="lbtn" data-act="up" title="上移一层">▲</button>' +
          '<button class="lbtn" data-act="down" title="下移一层">▼</button>' +
          '<button class="lbtn" data-act="dup" title="复制">⧉</button>' +
          '<button class="lbtn" data-act="del" title="删除">✕</button>' +
        '</div>' +
      '</li>';
    }).join('');

    $('layer-list').innerHTML = html ||
      '<li style="font-size:11px;color:#5d6678;padding:6px 2px">这一场还没有图层 —— 上面「添加图层」或套模板</li>';
    $('layer-count').textContent = layers.length;
  }

  function bindLayerList() {
    $('layer-list').addEventListener('click', function (e) {
      var li = e.target.closest('.layer-item');
      if (!li) return;
      var id = parseInt(li.dataset.lid, 10);
      var btn = e.target.closest('button[data-act]');
      var sc = curScene();
      S.selKind = 'layer';
      S.selId = id;

      if (btn) {
        var act = btn.dataset.act;
        var layer = SB.findLayer(sc, id);
        pushUndo();
        if (act === 'up') SB.moveLayer(sc, id, 1);
        else if (act === 'down') SB.moveLayer(sc, id, -1);
        else if (act === 'dup') {
          var copy = SB.duplicateLayer(sc, id);
          if (copy) S.selId = copy.id;
        } else if (act === 'del') {
          SB.removeLayer(sc, id);
          S.selKind = 'none';
          S.selId = 0;
          hint('已删除「' + (layer ? layer.name : '') + '」');
        }
        syncTimes();
        renderLayerList();
        renderInspector();
        refreshUndo();
        requestDraw();
        return;
      }

      renderLayerList();
      renderInspector();
      renderShaderList();
      requestDraw();
    });
  }

  /* ==========================================================================
   * 侧栏：属性面板
   * ======================================================================== */

  function selectedLayer() {
    if (S.selKind !== 'layer') return null;
    return SB.findLayer(curScene(), S.selId);
  }

  function optHtml(list, value, keyName, labelName) {
    var k = keyName || 'id';
    var lb = labelName || 'label';
    return list.map(function (item) {
      var v = item[k];
      return '<option value="' + esc(v) + '"' + (v === value ? ' selected' : '') + '>' + esc(item[lb]) + '</option>';
    }).join('');
  }

  function numIn(path, value, step, min, max) {
    return '<input type="number" data-path="' + path + '" data-kind="num" value="' + value + '"' +
      (step !== undefined ? ' step="' + step + '"' : '') +
      (min !== undefined ? ' min="' + min + '"' : '') +
      (max !== undefined ? ' max="' + max + '"' : '') + '>';
  }

  function strIn(path, value) {
    return '<input type="text" data-path="' + path + '" data-kind="str" value="' + esc(value) + '">';
  }

  function colorIn(path, value) {
    return '<input type="color" data-path="' + path + '" data-kind="str" value="' + esc(value) + '">';
  }

  function selIn(path, list, value, keyName, labelName) {
    return '<select data-path="' + path + '" data-kind="str">' + optHtml(list, value, keyName, labelName) + '</select>';
  }

  function chkIn(path, value) {
    return '<input type="checkbox" data-path="' + path + '" data-kind="bool"' + (value ? ' checked' : '') + '>';
  }

  function row(label, html) {
    return '<div class="frow"><span>' + label + '</span>' + html + '</div>';
  }

  function fgroup(text) {
    return '<div class="fgroup">' + text + '</div>';
  }

  function easeList() {
    return RC.EASE_NAMES.concat(['bezier(0.25, 0.1, 0.25, 1)']).map(function (n) {
      return { id: n, label: n };
    });
  }

  function optionsSel(path, list, value) {
    return '<select data-path="' + path + '" data-kind="str">' +
      list.map(function (o) {
        return '<option value="' + esc(o.id) + '"' + (o.id === value ? ' selected' : '') + '>' + esc(o.label) + '</option>';
      }).join('') + '</select>';
  }

  function renderInspector() {
    var box = $('inspector');
    var typeEl = $('insp-type');
    var sc = curScene();

    // ---- 场景属性 ----
    if (S.selKind === 'scene' && sc) {
      typeEl.textContent = '场景';
      var kindDef = SB.SCENE_MAP[SB.sceneKind(sc.kind)];
      var sp = curSpan();
      var html = fgroup('场景');
      html += row('名称', strIn('name', sc.name));
      html += '<div class="frow wide"><span style="color:#5d6678;font-size:10.5px">' + esc(kindDef.desc) + '</span></div>';
      if (sc.kind === 'chart') {
        html += '<div class="frow wide"><span style="color:#7cf5c1;font-size:11px">时长跟随谱面：' + fmt(SB.sceneLen(S.doc, sc)) + '（只读）</span></div>';
      } else {
        html += row('时长 (s)', numIn('length', sc.length, 0.1, 0.2, 120));
      }
      html += '<div class="frow wide"><span style="color:#5d6678;font-size:10.5px">在整条故事板里：' +
        fmt(sp ? sp.start : 0) + ' → ' + fmt(sp ? sp.end : 0) + '</span></div>';
      html += '<div class="frow wide"><span style="color:#5d6678;font-size:10.5px">这一场有 ' +
        sc.layers.length + ' 个图层 / ' + sc.shaders.length + ' 条后处理</span></div>';
      box.innerHTML = html;
      return;
    }

    // ---- 后处理 ----
    if (S.selKind === 'shader') {
      var fx = SB.findShader(sc, S.selId);
      typeEl.textContent = '后处理';
      box.innerHTML = fx
        ? '<div class="empty">正在编辑<b style="color:#ffb3d1">后处理</b>「' + esc(SB.label(SB.SHADER_PRESETS, fx.preset)) +
          '」，它只属于当前这一场。</div>' +
          fgroup('时间（场景内）') +
          row('开始 (s)', numIn('start', fx.start, 0.1, 0)) +
          row('结束 (s)', numIn('end', fx.end, 0.1, 0)) +
          row('强度 %', numIn('amount', fx.amount, 1, 0, 100)) +
          row('软边 0~0.49', numIn('ramp', fx.ramp, 0.01, 0, 0.49)) +
          row('缓动', selIn('ease', easeList(), fx.ease)) +
          '<div class="insp-btns"><button class="btn" data-act="del-shader">删除这条后处理</button></div>'
        : '<div class="empty">没有选中后处理。</div>';
      return;
    }

    var L = selectedLayer();
    if (!L) {
      typeEl.textContent = '';
      box.innerHTML = '<div class="empty">在左边「场景」里点一场，或在时间轴上点一个图层。<br><br>' +
        '解锁动画通常放在<b style="color:#ffb3d1">解锁场</b>（谱面之前），' +
        '文字 / 形状 / 图片在哪一场都行；属性里的时间都是<b>场景内时间</b>。</div>';
      return;
    }

    typeEl.textContent = SB.TYPE_LABELS[L.type];
    var len = sc ? sceneLen(sc) : 10;
    var html = '';

    html += fgroup('基本（场景内 ' + SB.round3(len) + 's）');
    html += row('名称', strIn('name', L.name));
    html += row('开始 (s)', numIn('start', L.start, 0.05, 0, len));
    html += row('结束 (s)', numIn('end', L.end, 0.05, 0, len));
    html += row('X (0~1)', numIn('x', L.x, 0.005, -1, 2));
    html += row('Y (0~1)', numIn('y', L.y, 0.005, -1, 2));
    html += row('缩放 %', numIn('scale', L.scale, 1, -4000, 4000));
    html += row('旋转 °', numIn('rot', L.rot, 1, -36000, 36000));
    html += row('透明度 %', numIn('alpha', L.alpha, 1, 0, 100));
    html += row('混合', selIn('blend', SB.BLENDS, L.blend));
    html += row('显示', chkIn('visible', L.visible !== false));

    if (L.type === 'text') {
      html += fgroup('文字');
      html += '<div class="frow wide"><span>内容（支持换行）</span><textarea data-path="text" data-kind="str">' + esc(L.text) + '</textarea></div>';
      html += row('字体', optionsSel('style.font', SB.FONTS, L.style.font));
      html += row('字号', numIn('style.size', L.style.size, 1, 8, 420));
      html += row('字重', numIn('style.weight', L.style.weight, 100, 100, 900));
      html += row('字距 ×字', numIn('style.letter', L.style.letter, 0.01, -0.5, 1));
      html += row('行高', numIn('style.lineH', L.style.lineH, 0.05, 0.6, 3));
      html += row('对齐', selIn('style.align', [
        { id: 'left', label: '左' }, { id: 'center', label: '中' }, { id: 'right', label: '右' }
      ], L.style.align));
      html += fgroup('文字特效');
      html += row('特效', optionsSel('style.effect', SB.TEXT_EFFECTS, L.style.effect));
      html += row('颜色', colorIn('style.color', L.style.color));
      html += row('发光', numIn('style.glow', L.style.glow, 0.05, 0, 1));
      html += row('渐变起', colorIn('style.c1', L.style.c1));
      html += row('渐变止', colorIn('style.c2', L.style.c2));
      html += row('描边色', colorIn('style.stroke', L.style.stroke));
      html += row('描边宽', numIn('style.strokeW', L.style.strokeW, 0.5, 0, 24));
      html += row('打字速度', numIn('style.speed', L.style.speed, 1, 1, 200));
    } else if (L.type === 'unlock') {
      html += fgroup('解锁动画');
      html += row('预设', optionsSel('unlock.preset', SB.UNLOCK_PRESETS, L.unlock.preset));
      var desc = SB.UNLOCK_PRESETS.filter(function (u) { return u.id === L.unlock.preset; })[0];
      if (desc) html += '<div class="frow wide"><span style="color:#5d6678;font-size:10.5px">' + esc(desc.desc) + '</span></div>';
      html += '<div class="frow wide"><span>标题（空 = 用曲名）</span><input type="text" data-path="unlock.label" data-kind="str" value="' + esc(L.unlock.label) + '"></div>';
      html += '<div class="frow wide"><span>副标题（空 = 难度 等级）</span><input type="text" data-path="unlock.sub" data-kind="str" value="' + esc(L.unlock.sub) + '"></div>';
      html += row('主色', colorIn('unlock.color', L.unlock.color));
      html += row('辅色', colorIn('unlock.accent', L.unlock.accent));
      html += row('尺寸', numIn('unlock.scale', L.unlock.scale, 0.05, 0.2, 4));
      html += '<div class="frow wide"><span style="color:#5d6678;font-size:10.5px">解锁动画从所在场景的第 0 秒开始演；想演在谱面之前，就放进「解锁场」。</span></div>';
    } else if (L.type === 'shape') {
      html += fgroup('形状');
      html += row('种类', optionsSel('shape.kind', SB.SHAPE_KINDS, L.shape.kind));
      html += row('宽 (0~1)', numIn('shape.w', L.shape.w, 0.01, 0.005, 4));
      html += row('高 (0~1)', numIn('shape.h', L.shape.h, 0.005, 0.001, 4));
      html += row('圆角', numIn('shape.radius', L.shape.radius, 1, 0, 400));
      html += row('线宽', numIn('shape.line', L.shape.line, 0.5, 0, 80));
      html += row('填充', chkIn('shape.fill', L.shape.fill));
      html += row('网格数', numIn('shape.count', L.shape.count, 1, 2, 40));
      html += row('颜色', colorIn('color', L.color));
    } else if (L.type === 'video') {
      html += fgroup('视频');
      html += '<div class="frow"><span>资源</span><div class="pair"><input type="text" data-path="video.name" data-kind="str" value="' + esc(L.video.name) + '" readonly><button class="lbtn" data-act="pick-video" title="选视频">视频</button></div></div>';
      html += row('宽度 (0~1)', numIn('video.w', L.video.w, 0.01, 0.05, 4));
      html += row('适配', '<select data-path="video.fit"><option value="cover"' + (L.video.fit === 'cover' ? ' selected' : '') + '>铺满裁剪 cover</option><option value="contain"' + (L.video.fit === 'contain' ? ' selected' : '') + '>完整显示 contain</option><option value="stretch"' + (L.video.fit === 'stretch' ? ' selected' : '') + '>拉伸 stretch</option></select>');
      html += row('播放速度', numIn('video.speed', L.video.speed, 0.1, 0.1, 4));
      html += row('音量 %', numIn('video.volume', L.video.volume === undefined ? 100 : L.video.volume, 1, 0, 100));
      html += row('静音', '<label class="chk"><input type="checkbox" data-path="video.mute" data-kind="bool"' + (L.video.mute ? ' checked' : '') + '><span>这个视频不出声</span></label>');
      var vnames = Object.keys(S.doc.assets || {}).filter(function (n) { return SB.isVideoAsset(n); });
      if (vnames.length) {
        html += '<div class="frow wide"><span>工程里的视频（点一下就用）</span><div style="display:flex;flex-wrap:wrap;gap:4px">' +
          vnames.map(function (n) { return '<button class="lbtn" data-act="use-asset" data-name="' + esc(n) + '" style="width:auto;padding:0 5px">' + esc(n) + '</button>'; }).join('') +
          '</div></div>';
      }
    } else if (L.type === 'image') {
      html += fgroup('图片');
      html += '<div class="frow"><span>资源</span><div class="pair"><input type="text" data-path="image.name" data-kind="str" value="' + esc(L.image.name) + '" readonly><button class="lbtn" data-act="pick-image" title="选图">图</button></div></div>';
      html += row('宽度 (0~1)', numIn('image.w', L.image.w, 0.01, 0.02, 4));
      var names = Object.keys(S.doc.assets || {});
      if (names.length) {
        html += '<div class="frow wide"><span>工程里的资源（点一下就用）</span><div style="display:flex;flex-wrap:wrap;gap:4px">' +
          names.map(function (n) { return '<button class="lbtn" data-act="use-asset" data-name="' + esc(n) + '" style="width:auto;padding:0 5px">' + esc(n) + '</button>'; }).join('') +
          '</div></div>';
      }
    }

    html += fgroup('入场 / 出场');
    html += row('入场', optionsSel('in.preset', SB.IN_PRESETS, L.in.preset));
    html += row('入场时长', numIn('in.dur', L.in.dur, 0.05, 0, 10));
    html += row('入场缓动', selIn('in.ease', easeList(), L.in.ease));
    html += row('出场', optionsSel('out.preset', SB.OUT_PRESETS, L.out.preset));
    html += row('出场时长', numIn('out.dur', L.out.dur, 0.05, 0, 10));
    html += row('出场缓动', selIn('out.ease', easeList(), L.out.ease));

    html += fgroup('关键帧（' + SB.layerKeyCount(L) + '）');
    html += '<div class="frow wide"><div class="pair" style="grid-template-columns:1fr auto">' +
      '<select id="key-channel">' + SB.CHANNELS.map(function (c) {
        return '<option value="' + c + '">' + SB.CHANNEL_LABELS[c] + '</option>';
      }).join('') + '</select>' +
      '<button class="btn" data-act="add-key">＋ 在播放头</button></div></div>';

    var keyRows = [];
    for (var c2 = 0; c2 < SB.CHANNELS.length; c2++) {
      var key = SB.CHANNELS[c2];
      var arr = (L.events && L.events[key]) || [];
      for (var e = 0; e < arr.length; e++) {
        var ev = arr[e];
        var tag = key + ':' + ev.id;
        keyRows.push('<div class="key-row">' +
          '<b>' + SB.CHANNEL_LABELS[key] + '</b>' +
          '<input type="number" step="0.05" style="width:52px" data-key="' + tag + ':start" value="' + ev.start + '">' +
          '<input type="number" step="0.05" style="width:52px" data-key="' + tag + ':end" value="' + ev.end + '">' +
          '<input type="number" step="0.005" style="width:56px" data-key="' + tag + ':from" value="' + ev.from + '">' +
          '<span style="color:#5d6678">→</span>' +
          '<input type="number" step="0.005" style="width:56px" data-key="' + tag + ':to" value="' + ev.to + '">' +
          '<button class="lbtn del" data-act="del-key" data-key="' + tag + '">✕</button>' +
        '</div>');
      }
    }
    html += keyRows.length ? '<div class="key-list">' + keyRows.join('') + '</div>'
      : '<div class="frow wide"><span style="color:#5d6678;font-size:10.5px">没有关键帧。X/Y/缩放/旋转/透明度都能在播放头处打点，跑完保持尾值。</span></div>';

    html += '<div class="insp-btns">' +
      '<button class="btn" data-act="dup">复制</button>' +
      '<button class="btn" data-act="del">删除</button>' +
      '</div>';

    box.innerHTML = html;
  }

  function setPath(obj, path, value) {
    var parts = String(path).split('.');
    var o = obj;
    for (var i = 0; i < parts.length - 1; i++) {
      if (!o[parts[i]] || typeof o[parts[i]] !== 'object') o[parts[i]] = {};
      o = o[parts[i]];
    }
    o[parts[parts.length - 1]] = value;
  }

  function bindInspector() {
    var box = $('inspector');

    // 点标题行：展开 / 收起（点下拉、删除按钮时不算）
    box.addEventListener('click', function (e) {
      if (e.target.closest('[data-shader-field]')) return;
      var head = e.target.closest('.shead');
      if (!head) return;
      var item = head.closest('.shader-item');
      if (!item) return;
      var id = parseInt(item.dataset.sid, 10);
      var already = S.selKind === 'shader' && S.selId === id;
      S.selKind = already ? 'none' : 'shader';
      S.selId = already ? 0 : id;
      renderShaderList();
      renderInspector();
      requestDraw();
    });

    box.addEventListener('input', function (e) {
      var t = e.target;
      var sc = curScene();

      if (t.dataset.path) {
        var target = (S.selKind === 'scene' && sc) ? sc
          : S.selKind === 'shader' ? SB.findShader(sc, S.selId)
            : selectedLayer();
        if (!target) return;
        beginEdit();
        var kind = t.dataset.kind || 'str';
        var val = kind === 'num' ? parseFloat(t.value)
          : kind === 'bool' ? !!t.checked
            : t.value;
        if (kind === 'num' && !isFinite(val)) val = 0;
        setPath(target, t.dataset.path, val);
        afterEdit(t.dataset.path);
        return;
      }

      if (t.dataset.key) {
        var L2 = selectedLayer();
        if (!L2) return;
        var pieces = t.dataset.key.split(':');
        var chKey = pieces[0];
        var evId = parseInt(pieces[1], 10);
        var field = pieces[2];
        var arr = (L2.events && L2.events[chKey]) || [];
        for (var i = 0; i < arr.length; i++) {
          if (arr[i].id !== evId) continue;
          beginEdit();
          var v = parseFloat(t.value);
          if (!isFinite(v)) v = 0;
          if (field === 'start') { arr[i].start = Math.max(0, v); if (arr[i].end < arr[i].start) arr[i].end = arr[i].start; }
          else if (field === 'end') arr[i].end = Math.max(arr[i].start, v);
          else if (field === 'from' || field === 'to') arr[i][field] = v;
          arr.sort(function (a, b) { return a.start - b.start || a.id - b.id; });
          requestDraw();
          return;
        }
      }
    });

    box.addEventListener('change', function () { endEdit(); });

    box.addEventListener('click', function (e) {
      var btn = e.target.closest('button[data-act]');
      if (!btn) return;
      var act = btn.dataset.act;
      var sc = curScene();
      var L = selectedLayer();

      if (act === 'del-shader' && S.selKind === 'shader') {
        pushUndo();
        SB.removeShader(sc, S.selId);
        S.selKind = 'none';
        S.selId = 0;
        refreshAll();
        return;
      }

      if (!L) return;

      if (act === 'del') {
        pushUndo();
        SB.removeLayer(sc, L.id);
        S.selKind = 'none';
        S.selId = 0;
        syncTimes();
        refreshAll();
        hint('已删除「' + L.name + '」');
      } else if (act === 'dup') {
        pushUndo();
        var cp = SB.duplicateLayer(sc, L.id);
        if (cp) S.selId = cp.id;
        syncTimes();
        refreshAll();
      } else if (act === 'pick-image') {
        $('file-image').click();
      } else if (act === 'pick-video') {
        $('file-video').click();
      } else if (act === 'use-asset') {
        pushUndo();
        L.image.name = btn.dataset.name;
        renderInspector();
        requestDraw();
      } else if (act === 'add-key') {
        var ch = ($('key-channel') || {}).value || 'x';
        var localNow = localTime();
        var cur = SB.layerParamsAt(L, localNow);
        pushUndo();
        SB.addLayerEvent(L, ch, {
          start: SB.round3(localNow),
          end: SB.round3(Math.min(L.end, localNow + 0.6)),
          ease: 'inOutCubic',
          from: SB.round3(cur[ch]),
          to: SB.round3(cur[ch])
        });
        renderInspector();
        requestDraw();
        hint('在场景内 ' + SB.round3(localNow) + 's 给「' + SB.CHANNEL_LABELS[ch] + '」打了一个关键帧');
      } else if (act === 'del-key') {
        var parts = btn.dataset.key.split(':');
        pushUndo();
        SB.removeLayerEvent(L, parts[0], parseInt(parts[1], 10));
        renderInspector();
        requestDraw();
      }
    });
  }

  /** 播放头在当前场景里的本地时间 */
  function localTime() {
    var sp = curSpan();
    if (!sp) return 0;
    return clamp(S.time - sp.start, 0, sp.len);
  }

  function afterEdit(path) {
    syncTimes();
    if (path === 'name' || path === 'visible' || path === 'start' || path === 'end' || path === 'length' ||
        path === 'style.effect' || path === 'unlock.preset' || path === 'shape.kind' ||
        path.indexOf('unlock.') === 0 || path === 'text') {
      renderSceneList();
      renderLayerList();
      renderChartPanel();
      drawTimeline();
    }
    requestDraw();
  }

  /* ==========================================================================
   * 侧栏：后处理列表（当前场景）
   * ======================================================================== */

  function renderShaderList() {
    var sc = curScene();
    var list = sc ? sc.shaders : [];
    $('shader-count').textContent = list.length;
    $('shader-list').innerHTML = list.map(function (fx) {
      var on = S.selKind === 'shader' && S.selId === fx.id;
      var presetDef = SB.shaderPreset(fx.preset);
      var isInstant = !!(presetDef && presetDef.instant);
      var sum = fx.start.toFixed(2) + '–' + fx.end.toFixed(2) + 's · ' + Math.round(fx.amount) + '%';
      return '<div class="shader-item' + (on ? ' on' : '') + '" data-sid="' + fx.id + '">' +
        '<div class="shead">' +
          '<span class="scaret">' + (on ? '▾' : '▸') + '</span>' +
          '<select class="spreset" data-shader-field="preset">' +
            SB.SHADER_PRESETS.map(function (p) {
              return '<option value="' + p.id + '"' + (p.id === fx.preset ? ' selected' : '') + '>' + esc(p.label) + '</option>';
            }).join('') +
          '</select>' +
          '<span class="ssum">' + sum + '</span>' +
          '<button class="lbtn" data-shader-act="del" title="删除">✕</button>' +
        '</div>' +
        (on ? '<div class="sgrid">' +
          '<label>起<input type="number" step="0.1" data-shader-field="start" value="' + fx.start + '"></label>' +
          '<label>止<input type="number" step="0.1" data-shader-field="end" value="' + fx.end + '"></label>' +
          '<label>强度<input type="number" step="1" min="0" max="100" data-shader-field="amount" value="' + fx.amount + '"></label>' +
          (isInstant
            ? '<label class="wide" style="color:#6f7c92;font-size:10.5px">这个效果是<b style="color:#7cf5c1;font-weight:600">立刻</b>生效的（不做缓入缓出）</label>'
            : '<label>软边<input type="number" step="0.01" min="0" max="0.49" data-shader-field="ramp" value="' + fx.ramp + '"></label>' +
              '<label>缓动<select data-shader-field="ease">' +
              RC.EASE_NAMES.map(function (n) {
                return '<option value="' + n + '"' + (n === fx.ease ? ' selected' : '') + '>' + n + '</option>';
              }).join('') +
              '</select></label>' +
              '<label class="wide"><span class="easeline"><span class="etag">曲线</span>' +
              '<canvas class="ease-mini" data-ease="' + esc(fx.ease) + '" width="300" height="84"></canvas></span></label>') +
        '</div>' : '') +
      '</div>';
    }).join('') || '<div style="font-size:11px;color:#5d6678">这一场还没有后处理。选一个预设点「加到播放头」。</div>';
    paintEaseMinis();
  }

  /** 画缓动曲线小图：x = 时间进度，y = 缓动后的进度（虚线是线性参考） */
  function paintEaseMinis() {
    var cvs = document.querySelectorAll('.ease-mini');
    for (var i = 0; i < cvs.length; i++) {
      var cv = cvs[i];
      var name = cv.getAttribute('data-ease') || 'linear';
      var w = Math.max(40, cv.clientWidth || 150);
      var h = Math.max(24, cv.clientHeight || 42);
      var dpr = Math.min(2, window.devicePixelRatio || 1);
      if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) {
        cv.width = Math.round(w * dpr);
        cv.height = Math.round(h * dpr);
      }
      var g = cv.getContext('2d');
      if (!g) continue;
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, w, h);
      g.fillStyle = '#0b0f16';
      g.fillRect(0, 0, w, h);
      g.strokeStyle = '#1d2330';
      g.lineWidth = 1;
      for (var gx = 1; gx <= 3; gx++) {
        g.beginPath();
        g.moveTo((w / 4) * gx + 0.5, 0);
        g.lineTo((w / 4) * gx + 0.5, h);
        g.stroke();
      }
      g.beginPath();
      g.moveTo(0, h / 2 + 0.5);
      g.lineTo(w, h / 2 + 0.5);
      g.stroke();
      g.setLineDash([3, 3]);
      g.strokeStyle = '#2b3444';
      g.beginPath();
      g.moveTo(4, h - 4);
      g.lineTo(w - 4, 4);
      g.stroke();
      g.setLineDash([]);
      g.beginPath();
      for (var k = 0; k <= 48; k++) {
        var u = k / 48;
        var v = RC.easeAt(name, u);
        var x = 4 + u * (w - 8);
        var y = (h - 4) - v * (h - 8);
        if (k === 0) g.moveTo(x, y); else g.lineTo(x, y);
      }
      g.strokeStyle = '#4cc9f0';
      g.lineWidth = 1.6;
      g.stroke();
    }
  }

  function bindShaderList() {
    var box = $('shader-list');

    box.addEventListener('input', function (e) {
      var item = e.target.closest('.shader-item');
      if (!item) return;
      var fx = SB.findShader(curScene(), parseInt(item.dataset.sid, 10));
      if (!fx) return;
      var field = e.target.dataset.shaderField;
      if (!field) return;
      beginEdit();
      if (field === 'preset' || field === 'ease') {
        fx[field] = e.target.value;
      } else {
        var v = parseFloat(e.target.value);
        if (!isFinite(v)) return;
        if (field === 'amount') fx.amount = clamp(v, 0, 100);
        else if (field === 'ramp') fx.ramp = clamp(v, 0, 0.49);
        else if (field === 'start') { fx.start = Math.max(0, v); if (fx.end < fx.start) fx.end = fx.start + 0.2; }
        else if (field === 'end') fx.end = Math.max(fx.start + 0.05, v);
      }
      syncTimes();
      requestDraw();
    });

    box.addEventListener('change', function () { endEdit(); });

    box.addEventListener('click', function (e) {
      var item = e.target.closest('.shader-item');
      if (!item) return;
      var id = parseInt(item.dataset.sid, 10);
      S.selKind = 'shader';
      S.selId = id;
      var del = e.target.closest('button[data-shader-act]');
      if (del) {
        pushUndo();
        SB.removeShader(curScene(), id);
        S.selKind = 'none';
        S.selId = 0;
        refreshAll();
        return;
      }
      renderShaderList();
      renderInspector();
      renderLayerList();
      drawTimeline();
    });
  }

  /* ==========================================================================
   * 工具栏 / 全局控件
   * ======================================================================== */

  function syncTransport() {
    $('time-code').textContent = fmt(S.time);
    $('total-code').textContent = fmt(S.total);
    var sc = $('scrub');
    sc.value = Math.round((S.time / Math.max(0.001, S.total)) * 1000);
  }

  function syncZoomSlider() {
    var z = clamp((24 * 60) / Math.max(0.5, S.view.span), 20, 600);
    $('zoom').value = Math.round(z);
  }

  function syncStatus() {
    var sp = spanAt(S.time);
    var sc = curScene();
    $('st-time').textContent = fmt(S.time);
    $('st-layers').textContent = '场景 ' + (sp ? sp.scene.name : '-') +
      ' · 图层 ' + (sc ? sc.layers.length : 0) + ' · 后处理 ' + (sc ? sc.shaders.length : 0);
    $('st-chart').textContent = S.chart
      ? '谱面：' + S.doc.chart.title + '（' + S.doc.chart.notes + ' 音符，只读）'
      : '谱面未导入';
    var w = S.renderer && S.renderer.lastWeights;
    var stackN = (S.renderer && S.renderer.lastStack) ? S.renderer.lastStack.length : 0;
    if (stackN > 0) $('st-layers').textContent += ' · 生效 ' + stackN + ' 层';
    var warn = '';
    if (w) {
      var hot = [];
      for (var k in w) {
        if (Object.prototype.hasOwnProperty.call(w, k) && w[k] > 0.001) hot.push(k + ' ' + w[k].toFixed(2));
      }
      warn = hot.length ? 'Shader：' + hot.join(' · ') : '';
    }
    $('st-warn').textContent = warn;
    $('file-name').textContent = S.fileName || '未命名故事板';
    $('lock-badge').style.display = S.chart ? '' : 'none';
  }

  /** 在播放头所在场景加一个图层；解锁动画会自动放进解锁场 */
  function addLayerOfType(type) {
    var sp = spanAt(S.time);
    var scene = sp ? sp.scene : curScene();

    if (type === 'unlock' && scene && scene.kind === 'chart') {
      // 解锁动画不该压在谱面上：自动建一个解锁场放进去
      pushUndo();
      var us = spans();
      var idx = sp.index;
      var newScene = SB.addScene(S.doc, 'unlock', { index: idx });
      var made = SB.addLayer(newScene, 'unlock', { start: 0, end: SB.round3(sceneLen(newScene)) });
      made.unlock.label = '';
      made.unlock.sub = '';
      made.name = '解锁动画';
      S.sceneId = newScene.id;
      S.selKind = 'layer';
      S.selId = made.id;
      syncTimes();
      clampView();
      var nsp = spanOf(newScene.id);
      if (nsp) seek(nsp.start);
      refreshAll();
      hint('解锁动画放在谱面之前：新建了「' + newScene.name + '」');
      return made;
    }

    if (!scene) return null;
    pushUndo();
    var local = clamp(localTime(), 0, Math.max(0, sceneLen(scene) - 0.3));
    var dur = type === 'unlock' ? Math.min(2.6, Math.max(0.5, sceneLen(scene))) : 2.5;
    var start = SB.round3(Math.min(local, Math.max(0, sceneLen(scene) - 0.3)));
    var end = SB.round3(Math.min(sceneLen(scene), start + dur));

    var L = SB.addLayer(scene, type, { start: start, end: Math.max(start + 0.2, end) });
    if (type === 'text') {
      var title = S.doc.chart && S.doc.chart.title;
      if (title && title !== '未命名谱面') L.text = title;
    } else if (type === 'unlock') {
      L.unlock.label = '';
      L.unlock.sub = '';
    }

    S.sceneId = scene.id;
    S.selKind = 'layer';
    S.selId = L.id;
    syncTimes();
    refreshAll();
    hint('已添加「' + L.name + '」到「' + scene.name + '」的 ' + start + 's');
    return L;
  }

  function bindToolbar() {
    $('btn-play').addEventListener('click', togglePlay);
    $('btn-play2').addEventListener('click', togglePlay);
    $('btn-stop').addEventListener('click', function () { pause(); seek(0); });
    $('chk-loop').addEventListener('change', function (e) { S.loop = e.target.checked; });

    $('btn-undo').addEventListener('click', undo);
    $('btn-redo').addEventListener('click', redo);

    $('scrub').addEventListener('input', function (e) {
      pause();
      seek((parseFloat(e.target.value) / 1000) * S.total);
    });

    $('zoom').addEventListener('input', function (e) {
      var z = parseFloat(e.target.value);
      var center = S.view.start + S.view.span * 0.5;
      S.view.span = clamp((24 * 60) / z, 0.5, 600);
      S.view.start = center - S.view.span * 0.5;
      clampView();
      drawTimeline();
    });

    $('snap-div').addEventListener('change', function (e) { S.div = parseInt(e.target.value, 10) || 4; });
    $('chk-snap').addEventListener('change', function (e) { S.snap = e.target.checked; });

    var addBtns = document.querySelectorAll('[data-add]');
    for (var i = 0; i < addBtns.length; i++) {
      addBtns[i].addEventListener('click', function (e) {
        addLayerOfType(e.currentTarget.dataset.add);
      });
    }

    $('tpl-select').innerHTML = SB.TEMPLATES.map(function (t) {
      return '<option value="' + t.id + '">' + esc(t.label) + ' — ' + esc(t.desc) + '</option>';
    }).join('');

    $('btn-tpl').addEventListener('click', function () {
      var id = $('tpl-select').value;
      var scene = curScene();
      if (!scene) return;
      pushUndo();
      // 模板铺满当前场景：从场景开头铺，太长就压进来（解锁场 2.6 秒也能放整段解锁演出）
      var made = SB.applyTemplate(scene, id, 0, {
        chart: S.doc.chart,
        meta: S.doc.meta,
        fit: sceneLen(scene),
        limit: sceneLen(scene)
      });
      if (!made || !made.layers.length) {
        hint('这一场放不下这个模板（场景太短）');
        endEdit();
        return;
      }
      S.selKind = 'layer';
      S.selId = made.layers[made.layers.length - 1].id;
      syncTimes();
      refreshAll();
      var label = SB.TEMPLATE_MAP[id] ? SB.TEMPLATE_MAP[id].label : id;
      hint('模板「' + label + '」铺进了「' + scene.name + '」' +
        (made.scale < 0.999 ? '（压到 ' + Math.round(made.scale * 100) + '% 才放得下）' : ''));
    });

    $('btn-demo').addEventListener('click', function () { loadDemo(); });

    $('shader-preset').innerHTML = SB.SHADER_PRESETS.map(function (p) {
      return '<option value="' + p.id + '"' + (p.id === 'bloom' ? ' selected' : '') + '>' + esc(p.label) + '</option>';
    }).join('');

    $('btn-add-shader').addEventListener('click', function () {
      var scene = curScene();
      if (!scene) return;
      pushUndo();
      var len2 = sceneLen(scene);
      var start = clamp(localTime(), 0, Math.max(0, len2 - 0.4));
      var end = Math.min(len2, start + 2.5);
      if (end - start < 0.2) start = Math.max(0, end - 0.2);
      var fx = SB.addShader(scene, $('shader-preset').value, {
        start: SB.round3(start),
        end: SB.round3(end),
        amount: 80,
        ramp: 0.28
      });
      S.selKind = 'shader';
      S.selId = fx.id;
      syncTimes();
      refreshAll();
      hint('在「' + scene.name + '」加了一条后处理：' + SB.label(SB.SHADER_PRESETS, fx.preset));
    });

    $('f-illust').addEventListener('input', function (e) {
      beginEdit();
      S.doc.meta.coverArtist = e.target.value;
      renderChartPanel();
    });
    $('f-illust').addEventListener('change', endEdit);

    $('st-chart-alpha').addEventListener('input', function (e) {
      beginEdit();
      S.doc.stage.chartAlpha = clamp(parseFloat(e.target.value), 0, 100);
      $('st-chart-alpha-txt').textContent = Math.round(S.doc.stage.chartAlpha) + '%';
      requestDraw();
    });
    $('st-chart-alpha').addEventListener('change', endEdit);

    $('st-highway').addEventListener('input', function (e) {
      beginEdit();
      var v = parseFloat(e.target.value);
      S.doc.stage.highway = clamp(isFinite(v) ? v : 2, 0.3, 20);
      requestDraw();
    });
    $('st-highway').addEventListener('change', endEdit);

    $('st-chart-base').addEventListener('change', function (e) {
      beginEdit();
      S.doc.stage.chartBase = clamp(parseFloat(e.target.value) || 350, 120, 2560);
      endEdit();
      requestDraw();
      hint('谱面基准改成 ' + S.doc.stage.chartBase + '×' + Math.round(S.doc.stage.chartBase * 9 / 16) + '（谱面 x/y 按这个画幅算；游戏逻辑舞台是 350）');
    });

    $('st-bg').addEventListener('input', function (e) {
      beginEdit();
      S.doc.stage.bg = e.target.value;
      requestDraw();
    });
    $('st-bg').addEventListener('change', endEdit);

    $('btn-shot').addEventListener('click', exportShot);
    $('btn-record').addEventListener('click', function () {
      if (S.recorder) stopRecord(); else startRecord();
    });

    $('btn-import').addEventListener('click', function () { $('file-chart').click(); });
    $('btn-audio').addEventListener('click', function () { $('file-audio').click(); });
    $('btn-audio2').addEventListener('click', function () { $('file-audio').click(); });

    $('st-volume').addEventListener('input', function (e) {
      beginEdit();
      S.doc.stage.volume = clamp(parseFloat(e.target.value), 0, 100);
      $('st-volume-txt').textContent = Math.round(S.doc.stage.volume) + '%';
      applyVolume();
    });
    $('st-volume').addEventListener('change', endEdit);

    $('chk-mute').addEventListener('change', function (e) {
      S.muted = !!e.target.checked;
      applyVolume();
    });
    $('btn-open').addEventListener('click', function () { $('file-project').click(); });
    $('btn-save').addEventListener('click', saveProject);
    $('btn-bundle').addEventListener('click', exportBundle);

    bindFiles();
    bindSceneList();
  }

  /* ==========================================================================
   * 键盘
   * ======================================================================== */

  function bindKeys() {
    document.addEventListener('keydown', function (e) {
      var tag = (e.target && e.target.tagName) || '';
      var typing = tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT';

      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
        e.preventDefault();
        saveProject();
        return;
      }
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        if (e.shiftKey) redo(); else undo();
        return;
      }
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'y') {
        e.preventDefault();
        redo();
        return;
      }
      if (typing) return;

      if (e.code === 'Space') {
        e.preventDefault();
        togglePlay();
      } else if (e.key === 'Delete' || e.key === 'Backspace') {
        e.preventDefault();
        var sc = curScene();
        if (S.selKind === 'layer') {
          pushUndo();
          SB.removeLayer(sc, S.selId);
          S.selKind = 'none';
          S.selId = 0;
          syncTimes();
          refreshAll();
        } else if (S.selKind === 'shader') {
          pushUndo();
          SB.removeShader(sc, S.selId);
          S.selKind = 'none';
          S.selId = 0;
          refreshAll();
        } else if (S.selKind === 'scene') {
          pushUndo();
          if (!SB.removeScene(S.doc, S.selId)) hint('至少要留一场，删不掉');
          else S.sceneId = S.doc.scenes.length ? S.doc.scenes[0].id : 0;
          syncTimes();
          refreshAll();
        }
      } else if (e.key === 'Home') {
        seek(0);
      } else if (e.key === 'End') {
        seek(S.total);
      } else if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        var step = S.snap ? beatSec() / S.div : 0.05;
        seek(snapT(S.time + (e.key === 'ArrowRight' ? step : -step)));
      } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'd') {
        e.preventDefault();
        if (S.selKind === 'layer') {
          pushUndo();
          var cp = SB.duplicateLayer(curScene(), S.selId);
          if (cp) { S.selId = cp.id; syncTimes(); refreshAll(); }
        }
      } else if (e.key === '[' || e.key === ']') {
        if (S.selKind === 'layer') {
          pushUndo();
          SB.moveLayer(curScene(), S.selId, e.key === ']' ? 1 : -1);
          renderLayerList();
          drawTimeline();
        }
      }
    });
  }

  /* ==========================================================================
   * 文件：谱面 / 工程 / 音频 / 图片
   * ======================================================================== */

  function mimeOf(name) {
    var n = String(name || '').toLowerCase();
    if (/\.mp3$/.test(n)) return 'audio/mpeg';
    if (/\.ogg$/.test(n)) return 'audio/ogg';
    if (/\.wav$/.test(n)) return 'audio/wav';
    if (/\.png$/.test(n)) return 'image/png';
    if (/\.jpe?g$/.test(n)) return 'image/jpeg';
    if (/\.webp$/.test(n)) return 'image/webp';
    if (/\.gif$/.test(n)) return 'image/gif';
    return 'application/octet-stream';
  }

  function bindFiles() {
    $('file-chart').addEventListener('change', function (e) {
      var f = e.target.files && e.target.files[0];
      if (!f) return;
      e.target.value = '';
      importChartFile(f);
    });

    $('file-project').addEventListener('change', function (e) {
      var f = e.target.files && e.target.files[0];
      if (!f) return;
      e.target.value = '';

      // 导出整包（zip）也能直接打开：故事板在 json 里，视频/图片在 assets/ 里
      if (/\.zip$/i.test(f.name)) {
        f.arrayBuffer().then(function (buf) {
          return RC.zipRead(new Uint8Array(buf)).then(function (files) {
            var storyName = pickEntry(files, 'storyboard.json', /(?!)/);
            if (!storyName) throw new Error('zip 里没有 storyboard.json');
            if (pickEntry(files, 'chart.json', /(?!)/)) {
              applyChartFromZip(files, f.name);
            } else {
              var raw = JSON.parse(new TextDecoder().decode(files[storyName]));
              applyLoadedDoc(restoreZipAssets(raw, files, storyName), f.name);
            }
          });
        }).catch(function (err) {
          window.alert('打开整包失败：' + (err && err.message ? err.message : err));
        });
        return;
      }

      f.text().then(function (text) {
        var raw;
        try { raw = JSON.parse(text); } catch (err) {
          window.alert('这个文件不是合法 JSON：' + err.message);
          return;
        }
        applyLoadedDoc(raw, f.name);
      });
    });

    $('file-audio').addEventListener('change', function (e) {
      var f = e.target.files && e.target.files[0];
      if (!f) return;
      e.target.value = '';
      f.arrayBuffer().then(function (buf) {
        setAudio({ name: f.name, bytes: new Uint8Array(buf) });
        hint('音频已载入：' + f.name);
      });
    });

    $('file-video').addEventListener('change', function (e) {
      var f = e.target.files && e.target.files[0];
      if (!f) return;
      e.target.value = '';
      if (f.size > 64 * 1024 * 1024) {
        hint('这个视频 ' + (f.size / 1048576).toFixed(1) + 'MB，工程会变得很大（建议剪短或压一下）');
      }
      var reader = new FileReader();
      reader.onload = function () {
        var url = String(reader.result);
        var name = f.name.replace(/[\\/:*?"<>|]/g, '_');
        pushUndo();
        S.doc.assets[name] = url;
        loadVideo(name, url);
        var L = selectedLayer();
        if (L && L.type === 'video') {
          L.video.name = name;
          // 视频解码出时长后，把图层时长对齐过去（不超过场景长度）
          var vv = S.videos[name];
          if (vv) {
            if (!fitVideoLayerToDuration(L, vv)) {
              whenVideoReady(vv, function () { fitVideoLayerToDuration(L, vv); });
            }
          }
          renderInspector();
          renderLayerList();
        }
        requestDraw();
        hint('视频已加入工程资源：' + name + '（整包导出时会一起打包）');
      };
      reader.readAsDataURL(f);
    });

    $('file-image').addEventListener('change', function (e) {
      var f = e.target.files && e.target.files[0];
      if (!f) return;
      e.target.value = '';
      var reader = new FileReader();
      reader.onload = function () {
        var url = String(reader.result);
        var name = f.name.replace(/[\\/:*?"<>|]/g, '_');
        pushUndo();
        S.doc.assets[name] = url;
        loadImage(name, url);
        var L = selectedLayer();
        if (L && L.type === 'image') {
          L.image.name = name;
          renderInspector();
        }
        requestDraw();
        hint('图片已加入工程资源：' + name);
      };
      reader.readAsDataURL(f);
    });
  }

  function loadImage(name, url) {
    var img = new Image();
    img.onload = function () { requestDraw(); };
    img.src = url;
    S.images[name] = img;
    S.imageUrls[name] = url;
  }

  function loadVideo(name, url) {
    var v = document.createElement('video');
    v.muted = true;          // 先静音：避免还没交互就被浏览器拦掉；真正播放时按图层设置改
    v.volume = 1;
    v.playsInline = true;
    v.loop = false;
    v.preload = 'auto';
    v.addEventListener('loadeddata', function () { requestDraw(); });
    v.addEventListener('seeked', function () { if (!S.playing) requestDraw(); });
    v.src = url;
    S.videos[name] = v;
    return v;
  }

  /**
   * 把视频图层的时长对齐到视频本身：
   *   - 立刻能算出 duration 就马上对齐（别等事件，dataURL 往往同步就绪，事件早就过去了）
   *   - 算不出就挂 loadedmetadata / durationchange 兜底
   *   - 录制出来的 webm 常见 duration = Infinity：seek 一个超大值逼它算出真实时长
   */
  function fitVideoLayerToDuration(L, vv) {
    if (!L || L.type !== 'video' || !vv) return false;
    var dur = vv.duration;
    if (!isFinite(dur) || dur <= 0.05) return false;
    var sc0 = curScene();
    if (!sc0) return true;
    var lim = Math.max(0.2, sceneLen(sc0));
    var speed = Math.max(0.1, SB.num(L.video.speed, 1));
    var d = Math.min(dur / speed, lim - L.start);
    if (d <= 0.2) return true;
    L.end = SB.round3(Math.min(lim, L.start + d));
    syncTimes();
    renderInspector();
    renderLayerList();
    requestDraw();
    hint('视频时长 ' + dur.toFixed(2) + 's → 图层自动拉到 ' + L.end.toFixed(2) + 's');
    return true;
  }

  /** 等元数据就绪后再对齐（只跑一次） */
  function whenVideoReady(vv, cb) {
    if (!vv) return;
    if (isFinite(vv.duration) && vv.duration > 0.05) { cb(); return; }
    var done = false;
    var run = function () {
      if (done) return;
      if (!isFinite(vv.duration) || vv.duration <= 0.05) return;
      done = true;
      vv.removeEventListener('loadedmetadata', run);
      vv.removeEventListener('durationchange', run);
      cb();
    };
    vv.addEventListener('loadedmetadata', run);
    vv.addEventListener('durationchange', run);
    if (vv.duration === Infinity) { try { vv.currentTime = 1e101; } catch (e) { /* 忽略 */ } }
  }

  /** 让每条视频的 currentTime 跟着播放头走：暂停时精确 seek，播放时只纠偏 */
  function syncVideos(t) {
    var scenes = S.doc.scenes || [];
    for (var i = 0; i < scenes.length; i++) {
      var layers = scenes[i].layers || [];
      for (var j = 0; j < layers.length; j++) {
        var L = layers[j];
        if (L.type !== 'video') continue;
        var v = L.video && L.video.name ? S.videos[L.video.name] : null;
        if (!v || !v.duration) continue;
        var want = clamp((t - L.start) * SB.num(L.video.speed, 1), 0, Math.max(0, v.duration - 0.02));
        // 音量 / 静音跟着图层走（故事板总音量再乘一次）
        var lv = clamp(SB.num(L.video.volume, 100), 0, 100) / 100;
        var master = clamp(SB.num(S.doc.stage.volume, 100), 0, 100) / 100;
        var wantMuted = !!L.video.mute || S.muted || lv <= 0.001;
        if (v.muted !== wantMuted) v.muted = wantMuted;
        var wantVol = clamp(lv * master, 0, 1);
        if (Math.abs(v.volume - wantVol) > 0.01) v.volume = wantVol;
        if (S.playing) {
          if (Math.abs(v.currentTime - want) > 0.22) { try { v.currentTime = want; } catch (e) { /* 忽略 */ } }
          if (v.paused) {
            var pr = null;
            try { pr = v.play(); } catch (e) { pr = null; }
            if (pr && pr.catch) {
              pr.catch(function () {
                // 浏览器不允许带声音自动播放：退回静音播画面，只提示一次
                if (!S.videoMutedOnce) {
                  S.videoMutedOnce = true;
                  v.muted = true;
                  try { v.play(); } catch (e) { /* 忽略 */ }
                  hint('浏览器拦了带声音的自动播放：点一下舞台或按空格，视频就有声音了');
                }
              });
            }
          }
        } else {
          if (!v.paused) { try { v.pause(); } catch (e) { /* 忽略 */ } }
          if (Math.abs(v.currentTime - want) > 0.04) { try { v.currentTime = want; } catch (e) { /* 忽略 */ } }
        }
      }
    }
  }
  function loadDocAssets() {
    // 先把上一份工程的视频/图片松掉，别让解码器一直占着内存
    Object.keys(S.videos || {}).forEach(function (n) {
      var v = S.videos[n];
      try { v.pause(); v.removeAttribute('src'); v.load(); } catch (e) { /* 忽略 */ }
    });
    Object.keys(S.images || {}).forEach(function (n) {
      try { S.images[n].src = ''; } catch (e) { /* 忽略 */ }
    });
    S.images = {};
    S.videos = {};
    Object.keys(S.doc.assets || {}).forEach(function (name) {
      if (SB.isVideoAsset(name)) loadVideo(name, S.doc.assets[name]);
    });
    Object.keys(S.doc.assets || {}).forEach(function (name) {
      loadImage(name, S.doc.assets[name]);
    });
  }

  /** 故事板自己的音量：作用在音频元素上（录制时也走这里） */
  function applyVolume() {
    if (!S.audioEl) return;
    var v = clamp(SB.num(S.doc.stage.volume, 100), 0, 100) / 100;
    try { S.audioEl.volume = S.muted ? 0 : v; } catch (err) { /* 忽略 */ }
  }

  function renderAudioPanel() {
    var el = $('audio-name');
    if (el) el.textContent = S.audioBytes ? S.audioBytes.name : (S.chart ? '谱面没带音频（可单独载入）' : '未载入');
    var v = clamp(SB.num(S.doc.stage.volume, 100), 0, 100);
    $('st-volume').value = v;
    $('st-volume-txt').textContent = Math.round(v) + '%';
    $('chk-mute').checked = !!S.muted;
  }

  function setAudio(audio) {
    if (S.audioEl) {
      try { S.audioEl.pause(); } catch (err) { /* 忽略 */ }
      if (S.audioEl.src) URL.revokeObjectURL(S.audioEl.src);
    }
    S.audioBytes = audio || null;
    S.audioEl = audio ? new Audio(URL.createObjectURL(new Blob([audio.bytes], { type: mimeOf(audio.name) }))) : null;
    if (S.audioEl) S.audioEl.preload = 'auto';
    S.audioNodeMade = false;
    S.audioSrcNode = null;
    applyVolume();
    renderAudioPanel();
  }

  function clearCover() {
    if (S.coverUrl) URL.revokeObjectURL(S.coverUrl);
    S.coverUrl = '';
    S.coverBytes = null;
  }

  /** 整包里的资源路径转回内存资源；两个打开入口使用同一套逻辑。 */
  function restoreZipAssets(raw, files, storyName) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return raw;
    var fixed = {};
    var src = raw.assets || {};
    var prefix = storyName.slice(0, storyName.lastIndexOf('/') + 1);
    Object.keys(src).forEach(function (name) {
      var value = src[name];
      if (typeof value !== 'string') return;
      if (value.indexOf('data:') === 0) { fixed[name] = value; return; }
      var bytes = files[prefix + value] || files[value] || files[prefix + 'assets/' + name];
      if (bytes && bytes.length) fixed[name] = bytesToDataUrl(bytes, name);
    });
    raw.assets = fixed;
    return raw;
  }

  function pickEntry(files, wanted, extRe) {
    var keys = Object.keys(files);
    if (wanted) {
      for (var i = 0; i < keys.length; i++) if (keys[i] === wanted) return keys[i];
      for (var j = 0; j < keys.length; j++) {
        if (keys[j].split('/').pop() === wanted) return keys[j];
      }
    }
    for (var k = 0; k < keys.length; k++) if (extRe.test(keys[k])) return keys[k];
    return '';
  }

  function importChartFile(file) {
    file.arrayBuffer().then(function (buf) {
      var bytes = new Uint8Array(buf);
      if (bytes.length > 4 && bytes[0] === 0x50 && bytes[1] === 0x4b &&
          bytes[2] === 0x03 && bytes[3] === 0x04) {
        return RC.zipRead(bytes).then(function (files) {
          applyChartFromZip(files, file.name);
        });
      }
      var text = new TextDecoder().decode(bytes);
      pause();
      applyChartText(text, file.name, new TextEncoder().encode(text));
      setAudio(null);
      clearCover();
      finishChartImport();
    }).catch(function (err) {
      window.alert('谱面打不开：' + (err && err.message ? err.message : err));
    });
  }

  function applyChartFromZip(files, zipName) {
    var jsonName = pickEntry(files, 'chart.json', /\.json$/i);
    if (!jsonName) throw new Error('zip 里没有 .json 谱面');
    var chartBytes = files[jsonName];
    var text = new TextDecoder().decode(chartBytes);
    var storyName = pickEntry(files, 'storyboard.json', /(?!)/);
    var storyRaw = storyName ? restoreZipAssets(JSON.parse(new TextDecoder().decode(files[storyName])), files, storyName) : null;

    pause();
    applyChartText(text, zipName, chartBytes);

    var audioName = pickEntry(files, S.chart.audio && S.chart.audio.file, /\.(mp3|ogg|wav)$/i);
    setAudio(audioName ? { name: audioName, bytes: files[audioName] } : null);

    var coverName = pickEntry(files, S.chart.meta && S.chart.meta.cover, /\.(png|jpe?g|webp|gif)$/i);
    clearCover();
    if (coverName) {
      S.coverBytes = { name: coverName, bytes: files[coverName] };
      S.coverUrl = URL.createObjectURL(new Blob([files[coverName]], { type: mimeOf(coverName) }));
      renderChartPanel();
    }

    // 整包里如果带了故事板，一起恢复
    if (storyName) {
      var res = SB.normalizeDoc(storyRaw);
      res.doc.chart = SB.chartDigest(S.chart, { file: zipName, hash: S.chartHash });
      applyLoadedDoc(res.doc, zipName);
      hint('整包里的故事板也一起读进来了');
      return;
    }

    finishChartImport();
  }

  function finishChartImport() {
    S.sceneId = S.doc.scenes.length ? S.doc.scenes[0].id : 0;
    S.selKind = 'scene';
    S.selId = S.sceneId;
    syncTimes();
    S.view.start = 0;
    S.view.span = clamp(S.total, 1, 60);
    syncZoomSlider();
    refreshAll();
    seek(0);
    checkChartMatch();
    hint('谱面已导入（只读）：' + (S.chart.meta.title || S.chartName) + ' · ' + S.chart.notes.length + ' 个音符');
  }

  function applyChartText(text, name, bytes) {
    var raw;
    try { raw = JSON.parse(text); } catch (err) {
      throw new Error('谱面不是合法 JSON：' + err.message);
    }
    var res = RC.normalize(raw);
    if (!res.chart) throw new Error('谱面读不进来：' + res.warnings.join('；'));

    S.chart = res.chart;
    S.chartName = name;
    S.chartRaw = { name: 'chart.json', bytes: bytes };
    S.chartHash = SB.hashText(text);

    S.doc.chart = SB.chartDigest(S.chart, { file: name, hash: S.chartHash });
    S.doc.timing.bpm = SB.round3(S.chart.timing.bpm);
    S.doc.timing.beat_offset = SB.round3(S.chart.timing.beat_offset);

    // 没有谱面场就补一个（放在最后），这样谱面才有地方放
    if (!chartSpan()) {
      var sc = SB.addScene(S.doc, 'chart', { index: S.doc.scenes.length });
      S.sceneId = sc.id;
    }
    syncTimes();
    if (res.warnings.length) hint('谱面读入时有 ' + res.warnings.length + ' 条容错提示');
  }

  function checkChartMatch() {
    var want = S.doc.chart.hash;
    if (!want || !S.chart) {
      if (!S.chart) hint('工程打开了，但要「导入谱面」才能看到谱面场里的音符（谱面不进工程文件）');
      return;
    }
    if (want !== S.chartHash) {
      hint('⚠ 工程记录的谱面指纹（#' + want + '）和现在导入的（#' + S.chartHash + '）不一致 —— 演出可能对不上');
    }
  }

  /* ==========================================================================
   * 导出
   * ======================================================================== */

  function download(blob, name) {
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = name;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function () { URL.revokeObjectURL(url); }, 4000);
  }

  function safeName() {
    var base = (S.doc.chart.title || S.doc.chart.file || 'storyboard')
      .replace(/\.[^.]+$/, '')
      .replace(/[\\/:*?"<>|]/g, '_');
    return base || 'storyboard';
  }

  function saveProject() {
    var text = JSON.stringify(SB.serializeDoc(S.doc), null, '\t');
    var name = safeName() + '.rstory.json';
    download(new Blob([text], { type: 'application/json' }), name);
    S.fileName = name;
    syncStatus();
    hint('工程已保存：' + name + '（只含演出，不含谱面内容）');
  }

  /** dataURL → 字节（导出时把资源落成独立文件用） */
  function dataUrlToBytes(url) {
    var s = String(url || '');
    var comma = s.indexOf(',');
    if (s.indexOf('data:') !== 0 || comma < 0) return null;
    var head = s.slice(0, comma);
    if (head.indexOf('base64') < 0) return null;
    try {
      var bin = atob(s.slice(comma + 1));
      var out = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i) & 255;
      return out;
    } catch (err) {
      return null;
    }
  }

  /** 字节 → dataURL（打开 zip 整包时把 assets/ 还原成内存里的资源） */
  function bytesToDataUrl(bytes, name) {
    var ext = String(name || '').split('.').pop().toLowerCase();
    var mime = {
      mp4: 'video/mp4', webm: 'video/webm', mov: 'video/quicktime', m4v: 'video/x-m4v', ogv: 'video/ogg',
      png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', webp: 'image/webp', gif: 'image/gif',
      wav: 'audio/wav', mp3: 'audio/mpeg', ogg: 'audio/ogg'
    }[ext] || 'application/octet-stream';
    var bin = '';
    var chunk = 0x8000;
    for (var i = 0; i < bytes.length; i += chunk) {
      bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
    }
    return 'data:' + mime + ';base64,' + btoa(bin);
  }

  /** 把一份工程对象装进编辑器（json 和 zip 两条路共用） */
  function applyLoadedDoc(raw, fileName) {
    var res = SB.normalizeDoc(raw);
    pause();
    S.doc = res.doc;
    S.undo.length = 0;
    S.redo.length = 0;
    S.editOpen = false;
    S.sceneId = S.doc.scenes.length ? S.doc.scenes[0].id : 0;
    S.selKind = 'scene';
    S.selId = S.sceneId;
    S.fileName = fileName || S.fileName;
    syncTimes();
    S.view.start = 0;
    S.view.span = clamp(S.total, 1, 60);
    syncZoomSlider();
    loadDocAssets();
    applyVolume();
    refreshAll();
    seek(0);
    if (res.warnings.length) {
      window.alert('工程已打开，有这些情况：\n\n· ' + res.warnings.join('\n· '));
    } else {
      hint('已打开工程 ' + (fileName || ''));
    }
    checkChartMatch();
  }

  function exportBundle() {
    var title = safeName();
    var files = [];

    // 资源（视频 / 图片）单独成文件放进 assets/，json 里只留相对路径 ——
    var assetPaths = {};
    var assetNames = Object.keys(S.doc.assets || {});
    for (var ai = 0; ai < assetNames.length; ai++) {
      var an = assetNames[ai];
      var bytes = dataUrlToBytes(S.doc.assets[an]);
      if (!bytes || !bytes.length) continue;
      var rel = 'assets/' + an;
      files.push({ name: rel, data: bytes });
      assetPaths[an] = rel;
    }

    var plain = SB.serializeDoc(S.doc);
    plain.assets = assetPaths;
    var json = JSON.stringify(plain, null, '\t');

    if (S.chartRaw) {
      files.push({ name: 'chart.json', data: S.chartRaw.bytes });   // 原始谱面，一字节不改
      files.push({ name: 'storyboard.json', data: new TextEncoder().encode(json) });
    } else {
      files.push({ name: 'storyboard.json', data: new TextEncoder().encode(json) });
    }
    if (S.audioBytes) files.push({ name: S.audioBytes.name, data: S.audioBytes.bytes });
    if (S.coverBytes) files.push({ name: S.coverBytes.name, data: S.coverBytes.bytes });

    try {
      var bytes = RC.zipStore(files);
      download(new Blob([bytes], { type: 'application/zip' }), title + '.zip');
      var brief = files.slice(0, 5).map(function (f) { return f.name; }).join(' + ');
      if (files.length > 5) brief += ' 等 ' + files.length + ' 个文件';
      hint('已导出 ' + title + '.zip（' + brief + '）');
    } catch (err) {
      window.alert('打包失败：' + (err && err.message ? err.message : err));
    }
  }

  function exportShot() {
    drawStage();
    var url = S.renderer.shot();
    var name = safeName() + '_' + fmt(S.time).replace(/[:.]/g, '-') + '.png';
    download(dataUrlToBlob(url), name);
    hint('已截图：' + name);
  }

  function dataUrlToBlob(url) {
    var parts = String(url).split(',');
    var mime = /data:([^;]+)/.exec(parts[0]);
    var bin = atob(parts[1]);
    var arr = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
    return new Blob([arr], { type: mime ? mime[1] : 'image/png' });
  }

  function recordMime() {
    var list = ['video/webm;codecs=vp9', 'video/webm;codecs=vp8', 'video/webm'];
    for (var i = 0; i < list.length; i++) {
      if (window.MediaRecorder && MediaRecorder.isTypeSupported && MediaRecorder.isTypeSupported(list[i])) return list[i];
    }
    return '';
  }

  function startRecord() {
    if (!window.MediaRecorder || !S.renderer.canvas.captureStream) {
      window.alert('这个浏览器不支持 canvas 录制（需要 MediaRecorder / captureStream）');
      return;
    }
    var stream = S.renderer.canvas.captureStream(60);

    if (S.audioEl) {
      try {
        var audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        var dest = audioCtx.createMediaStreamDestination();
        if (!S.audioNodeMade) {
          var src = audioCtx.createMediaElementSource(S.audioEl);
          src.connect(audioCtx.destination);
          S.audioSrcNode = src;
          S.audioNodeMade = true;
        }
        if (S.audioSrcNode) S.audioSrcNode.connect(dest);
        dest.stream.getAudioTracks().forEach(function (track) { stream.addTrack(track); });
        S.recordCtx = audioCtx;
      } catch (err) {
        hint('音频混不进录制（浏览器限制），这次只录画面');
      }
    }

    var mime = recordMime();
    var options = mime ? { mimeType: mime, videoBitsPerSecond: 12000000 } : undefined;
    var rec = new MediaRecorder(stream, options);
    var chunks = [];
    rec.ondataavailable = function (ev) { if (ev.data && ev.data.size) chunks.push(ev.data); };
    rec.onstop = function () {
      var blob = new Blob(chunks, { type: mime || 'video/webm' });
      download(blob, safeName() + '.webm');
      hint('录制完成：' + safeName() + '.webm');
      if (S.recordCtx) { try { S.recordCtx.close(); } catch (err) { /* 忽略 */ } }
      S.recordCtx = null;
      S.recorder = null;
      $('btn-record').textContent = '录制';
      stopAllTracks(stream);
    };

    S.recorder = rec;
    S.recordStream = stream;
    rec.start();
    $('btn-record').textContent = '■ 停止录制';
    seek(0);
    play();
    hint('录制中……到结尾会自动停（再点一次也能停）');
  }

  function stopAllTracks(stream) {
    if (!stream) return;
    stream.getTracks().forEach(function (t) { try { t.stop(); } catch (err) { /* 忽略 */ } });
  }

  function stopRecord() {
    if (!S.recorder) return;
    try { S.recorder.stop(); } catch (err) { /* 忽略 */ }
    pause();
  }

  /* ==========================================================================
   * 示例工程
   * ======================================================================== */

  function loadDemo() {
    var chart = RC.createChart({ lane_count: 4 });
    chart.meta.title = 'Neon Pulse';
    chart.meta.artist = 'Synth Engine';
    chart.meta.charter = '示例';
    chart.meta.illustrator = 'Curtain';
    chart.meta.difficulty = 'HARD';
    chart.meta.level = 8;
    chart.timing.bpm = 150;

    var xs = [-60, -20, 20, 60];          // 谱面基准 380（同预渲染窗）下的 4 轨位置
    var zones = ['left', 'left', 'right', 'right'];
    for (var i = 0; i < chart.lanes.length; i++) {
      chart.lanes[i].x = xs[i];
      chart.lanes[i].alpha = 100;
      chart.lanes[i].speed = 10;
      chart.lanes[i].length = 10;
      chart.lanes[i].judge_zone = zones[i];
      chart.lanes[i].events = RC.emptyEvents();
    }

    var id = 1;
    var time = 1.0;
    var pattern = [0, 1, 2, 3, 3, 2, 1, 0];
    for (var n = 0; n < 120; n++) {
      var lane = pattern[n % pattern.length];
      var type = (n % 17 === 0) ? 'hold' : 'tap';
      chart.notes.push({
        id: id++,
        time: Math.round(time * 1000) / 1000,
        lane: lane,
        type: type,
        duration: type === 'hold' ? 0.6 : 0
      });
      time += (n % 8 === 7) ? 0.4 : 0.2;
    }
    RC.sortNotes(chart);

    S.chart = chart;
    S.chartName = '示例谱面（自动生成，只读）';
    S.chartHash = SB.hashText(JSON.stringify(RC.serialize(chart)));
    S.chartRaw = { name: 'chart.json', bytes: new TextEncoder().encode(JSON.stringify(RC.serialize(chart), null, '\t')) };
    S.audioEl = null;
    S.audioBytes = null;
    S.coverBytes = null;
    S.coverUrl = '';

    S.doc = SB.createStoryboard(SB.chartDigest(chart, { file: S.chartName, hash: S.chartHash }));
    S.doc.meta.author = '示例';
    S.doc.timing.bpm = 150;

    var unlockScene = S.doc.scenes[0];              // 解锁场（谱面之前）
    var chartScene = S.doc.scenes[1];               // 谱面场
    unlockScene.length = 2.6;

    S.doc.meta.coverArtist = 'Curtain（示例）';
    SB.applyTemplate(unlockScene, 'unlock', 0, {
      chart: S.doc.chart, meta: S.doc.meta, fit: unlockScene.length, limit: unlockScene.length
    });
    // 谱面场里放一张标题卡 / 保留谱面本身
    SB.addShader(chartScene, 'bloom', { start: 0, end: Math.min(6, chartScene.length || 6), amount: 40, ramp: 0.35 });

    // 片尾场
    var outro = SB.addScene(S.doc, 'free', { name: '片尾', length: 3.6 });
    SB.applyTemplate(outro, 'result', 0, {
      chart: S.doc.chart, meta: S.doc.meta, fit: outro.length, limit: outro.length
    });
    // 片尾补一行曲绘作者（谱面格式里没有这一栏，写在故事板的 meta 里）
    var ill = SB.addLayer(outro, 'text', { start: 1.2, end: outro.length, name: '曲绘作者' });
    ill.text = SB.fillText('ILLUSTRATION  {illust}', S.doc.chart, S.doc.meta);
    ill.y = 0.66;
    ill.style.size = 20;
    ill.style.weight = 500;
    ill.style.letter = 0.28;
    ill.style.effect = 'plain';
    ill.style.color = '#9fb3cc';
    ill.style.glow = 0;
    ill.in = { preset: 'fade', dur: 0.5, ease: 'outCubic' };
    ill.out = { preset: 'fade', dur: 0.4, ease: 'inCubic' };

    S.sceneId = unlockScene.id;
    S.selKind = 'layer';
    S.selId = unlockScene.layers.length ? unlockScene.layers[unlockScene.layers.length - 1].id : 0;
    syncTimes();
    S.view.start = 0;
    S.view.span = clamp(S.total, 6, 60);
    syncZoomSlider();
    S.undo.length = 0;
    S.redo.length = 0;
    S.fileName = '示例故事板';
    refreshAll();
    seek(0);
    hint('示例已载入：先演【解锁演出】→ 再进【谱面】→ 最后【片尾】。空格播放。');
  }

  /* ==========================================================================
   * 启动
   * ======================================================================== */

  function resizeAll() { drawTimeline(); }

  function boot() {
    S.renderer = SBR.create($('stage'));

    bindToolbar();
    bindLayerList();
    bindInspector();
    bindShaderList();
    bindTimeline();
    bindTlScrollbar();
    bindKeys();

    var ro = window.ResizeObserver ? new ResizeObserver(resizeAll) : null;
    if (ro) ro.observe($('timeline').parentNode);
    window.addEventListener('resize', resizeAll);

    var q = new URLSearchParams(location.search);
    if (q.get('demo') === '1') {
      loadDemo();
      var unl = q.get('unlock');
      if (unl && SB.UNLOCK_PRESETS.some(function (p) { return p.id === unl; })) {
        for (var si = 0; si < S.doc.scenes.length; si++) {
          var sc = S.doc.scenes[si];
          for (var li = 0; li < sc.layers.length; li++) {
            if (sc.layers[li].type === 'unlock') sc.layers[li].unlock.preset = unl;
          }
        }
        refreshAll();
      }
      if (q.get('t')) seek(parseFloat(q.get('t')) || 0);
      if (q.get('snap')) $('snap-div').value = q.get('snap');
    } else {
      refreshAll();
      seek(0);
      hint('先「导入谱面」，或者点左边「载入示例」看看效果');
    }

    requestAnimationFrame(function () { drawTimeline(); S.draw(true); });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();

  /* 给自动测试 / 调试控制台留的只读钩子（不参与任何业务逻辑） */
  window.__RHYTHM_SB__ = {
    state: S,
    doc: function () { return SB.serializeDoc(S.doc); },
    scene: function () { return curScene(); },
    spans: function () { return spans().map(function (s) {
      return { id: s.scene.id, kind: s.kind, name: s.scene.name, start: s.start, end: s.end, len: s.len };
    }); },
    hitAt: function (mx, my) { return tlHit(mx, my); },
    layout: function () {
      var L = tlLayout();
      return {
        x0: L.x0, x1: L.x1, rowsY: L.rowsY, rowH: L.rowH,
        maxScroll: L.maxScroll, contentH: L.contentH, scroll: S.tlScroll,
        bandY: L.bandY, bandH: L.bandH,
        rows: L.rows.map(function (r) { return { kind: r.kind, id: r.id, ids: r.ids ? r.ids.slice() : null, y: r.y, h: r.h, label: r.label, empty: !!r.empty, lane: r.lane }; })
      };
    },
    redraw: function () { S.draw(true); },
    refresh: function () { refreshAll(); },
    loadVideo: function (name, url) { return loadVideo(name, url); }
  };
})();
