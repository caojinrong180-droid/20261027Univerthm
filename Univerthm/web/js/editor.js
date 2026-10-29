/* =============================================================================
 * Rhythm 制谱器 · 界面层
 * 时间轴（canvas 自绘）+ 鼠标键盘交互 + 音频播放 + JSON 存读 + 撤销
 * 只依赖 core.js（window.RChart）
 * ========================================================================== */
(function () {
  'use strict';

  var RC = window.RChart;
  var $ = function (id) { return document.getElementById(id); };
  var canvas = $('canvas');
  var g = canvas.getContext('2d');
  var previewCanvas = $('preview');
  var pg = previewCanvas.getContext('2d');

  var NOTE_H = 12;       // 时间轴里普通音符厚度（像素）
  var NOTE_TH = 2.0;     // 预渲染里音符的半厚（像素）
  var PV_SCALE = 1.6;    // 预渲染里轨道/音符的整体放大倍数
  var MIN_HOLD = 0.05;   // 最短 hold（秒）
  var HINT = '左键空白=放 tap · 拖=移动 · 右键=删除 · 右键空白上下拖=画 hold · 双击=换类型';

  /* ---------- 状态 ---------- */

  var S = {
    chart: RC.createChart({ lane_count: 4 }),
    viewTime: 0,
    highwaySec: 2.0,
    pvSec: 2.0,          // 预渲染里「判定线到画面顶」是几秒（和可视秒数无关）
    snapDiv: 4,
    selectedId: 0,
    selectedIds: [],
    selectedLane: 0,
    selectedEventId: 0,
    selectedEventKey: 'x',
    laneScroll: 0,
    selectedEvs: [],
    eventClip: null,
    noteClip: null,
    extraFiles: [],          // 打开 zip 时原样留着的其它文件（storyboard.json / assets/…）
    storyboardName: '',
    lastArea: 'note',
    playRate: 1,
    playing: false,
    drag: null,
    undo: [],
    redo: [],
    fileName: '',
    dirty: false,
    audio: null,
    audioName: '',
    audioFile: null,
    coverFile: null,
    coverUrl: '',
    playWall: 0,
    playBase: 0,
    hitSound: true,
    hintTimer: 0
  };

  var L = null;          // 布局（每次绘制 / 每次鼠标事件前重算）

  /* ---------- 布局与坐标换算 ---------- */

  function computeLayout() {
    var W = Math.max(1, canvas.clientWidth);
    var H = Math.max(1, canvas.clientHeight);
    var dpr = Math.min(2, window.devicePixelRatio || 1);
    var pw = Math.round(W * dpr), ph = Math.round(H * dpr);
    if (canvas.width !== pw || canvas.height !== ph) {
      canvas.width = pw;
      canvas.height = ph;
    }
    var gutter = 56;
    var judgeY = Math.round(H * 0.84);
    var laneCount = Math.max(1, S.chart.lanes.length);
    var pad = 10;
    var divider = 14;

    var miniW = W >= 720 ? 52 : 0;
    var notesLeft = gutter + pad + (miniW ? miniW + 10 : 0);
    var avail = Math.max(140, W - notesLeft - pad);
    var half = Math.max(60, (avail - divider) / 2);

    // 左边最多同时显示 6 条轨道，多了用下面的滚动条翻
    var visCount = Math.min(MAX_VISIBLE_LANES, laneCount);
    var laneW = Math.max(14, Math.min(120, half / visCount));
    var innerGap = Math.max(0, (half - laneW * visCount) / 2);
    var noteX0 = notesLeft + innerGap;
    var eventX0 = notesLeft + half + divider;
    var evColW = half / RC.ALL_KEYS.length;

    // 滚动位置夹住
    var maxScroll = Math.max(0, laneCount - visCount);
    if (!(S.laneScroll >= 0)) S.laneScroll = 0;
    S.laneScroll = RC.clamp(Math.round(S.laneScroll), 0, maxScroll);

    // 事件区底部的轨道切换按钮
    var btnH = 19;
    var btnW = Math.max(18, Math.min(38, (half - 8) / laneCount - 4));
    var btnTotal = laneCount * (btnW + 4) - 4;
    var btnX = eventX0 + (half - btnTotal) / 2;
    var btnY = judgeY + 40;
    var btns = [];
    for (var b = 0; b < laneCount; b++) {
      btns.push({ x: btnX + b * (btnW + 4), y: btnY, w: btnW, h: btnH, idx: b });
    }

    L = {
      W: W, H: H, dpr: dpr, gutter: gutter, judgeY: judgeY,
      laneCount: laneCount, visCount: visCount, laneScroll: S.laneScroll,
      laneW: laneW, laneX0: noteX0, noteX0: noteX0, eventX0: eventX0,
      half: half, evColW: evColW, laneBtns: btns, maxLaneScroll: maxScroll,
      mini: miniW ? { x: gutter + pad, w: miniW } : null,
      pps: judgeY / Math.max(0.05, S.pvSec)
    };
  }

  /** 谱面时间 → 画布 y（未来在上方） */
  function timeToY(t) { return L.judgeY - (t - S.viewTime) * L.pps; }
  /** 画布 y → 谱面时间 */
  function yToTime(y) { return S.viewTime + (L.judgeY - y) / L.pps; }

  function laneAt(x) {
    if (x < L.laneX0) return -1;
    var i = Math.floor((x - L.laneX0) / L.laneW);
    if (i < 0 || i > L.visCount - 1) return -1;
    return i + L.laneScroll;      // 换成整条谱面的轨道序号
  }

  /** 画布上的横向位置：可见的第 i 条轨道（0 起） */
  function laneXOf(localIdx) { return L.laneX0 + localIdx * L.laneW; }

  /** 让某条轨道出现在可见范围里 */
  function ensureLaneVisible(laneIdx) {
    var vis = Math.min(MAX_VISIBLE_LANES, S.chart.lanes.length);
    var maxScroll = Math.max(0, S.chart.lanes.length - vis);
    var cur = RC.clamp(S.laneScroll, 0, maxScroll);
    if (laneIdx < cur) cur = laneIdx;
    else if (laneIdx >= cur + vis) cur = laneIdx - vis + 1;
    S.laneScroll = RC.clamp(cur, 0, maxScroll);
  }

  function snapT(t) { return RC.snapSec(t, S.chart.timing, S.snapDiv); }

  /* ---------- 选中 ---------- */

  function isSelected(n) { return S.selectedIds.indexOf(n.id) >= 0; }

  function selectOnly(id) {
    S.selectedId = id || 0;
    S.selectedIds = id ? [id] : [];
  }

  function selectedNotes() {
    var out = [];
    for (var i = 0; i < S.selectedIds.length; i++) {
      var n = RC.findNote(S.chart, S.selectedIds[i]);
      if (n) out.push(n);
    }
    return out;
  }

  function setPlayhead(t) {
    S.viewTime = Math.max(0, t);
  }

  /* ---------- 绘制 ---------- */

  function roundRect(ctx, x, y, w, h, r) {
    r = Math.min(r, Math.abs(w) / 2, Math.abs(h) / 2);
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + w - r, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + r);
    ctx.lineTo(x + w, y + h - r);
    ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    ctx.lineTo(x + r, y + h);
    ctx.quadraticCurveTo(x, y + h, x, y + h - r);
    ctx.lineTo(x, y + r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.closePath();
  }

  function rr(x, y, w, h, r) { roundRect(g, x, y, w, h, r); }

  function hexA(hex, a) {
    var h = String(hex).replace('#', '');
    var r = parseInt(h.slice(0, 2), 16) || 0;
    var gg = parseInt(h.slice(2, 4), 16) || 0;
    var b = parseInt(h.slice(4, 6), 16) || 0;
    return 'rgba(' + r + ',' + gg + ',' + b + ',' + a + ')';
  }

  function noteRect(n) {
    var local = n.lane - L.laneScroll;
    if (local < 0 || local >= L.visCount) return null;   // 滚动出去了
    var x = L.laneX0 + local * L.laneW + 6;
    var w = Math.max(4, L.laneW - 12);
    if (n.type === 'hold' && n.duration > 0.001) {
      // 时间轴始终按「时间」画，不受流速影响（流速只作用于预渲染窗口）
      var yTop = timeToY(n.time + n.duration);
      var yBot = timeToY(n.time);
      return { x: x, y: yTop, w: w, h: Math.max(4, yBot - yTop), hold: true };
    }
    var y = timeToY(n.time);
    return { x: x, y: y - NOTE_H / 2, w: w, h: NOTE_H, hold: false };
  }

  function draw() {
    computeLayout();
    g.setTransform(L.dpr, 0, 0, L.dpr, 0, 0);
    g.clearRect(0, 0, L.W, L.H);

    g.fillStyle = '#0e1016';
    g.fillRect(0, 0, L.W, L.H);
    g.fillStyle = '#090b10';
    g.fillRect(0, L.judgeY, L.W, L.H - L.judgeY);
    g.fillStyle = '#12151d';
    g.fillRect(0, 0, L.gutter, L.H);

    drawLanes();
    drawEventLanes();
    drawGrid();
    drawEvents();
    drawNotes();
    drawDupMarks();
    drawBox();
    drawJudgeLine();
    drawMinimap();
    drawGhost();
  }

  function drawLanes() {
    var lanes = S.chart.lanes;
    var scroll = L.laneScroll;
    var n = Math.min(L.visCount, Math.max(0, lanes.length - scroll));
    var x1 = L.laneX0 + L.laneW * n;

    for (var i = 0; i < n; i++) {
      var lane = lanes[scroll + i];
      var x = L.laneX0 + i * L.laneW;
      g.fillStyle = (i % 2) ? '#141821' : '#11151d';
      g.fillRect(x, 0, L.laneW, L.judgeY);

      g.strokeStyle = '#202634';
      g.lineWidth = 1;
      g.beginPath();
      g.moveTo(Math.round(x) + 0.5, 0);
      g.lineTo(Math.round(x) + 0.5, L.judgeY);
      g.stroke();

      g.fillStyle = RC.displayColor(lane);
      g.globalAlpha = 0.85;
      g.font = '12px ui-sans-serif, system-ui, "Microsoft YaHei", sans-serif';
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillText(lane.name, x + L.laneW / 2, L.judgeY + 16);
      g.globalAlpha = 1;
    }

    g.strokeStyle = '#202634';
    g.beginPath();
    g.moveTo(Math.round(x1) + 0.5, 0);
    g.lineTo(Math.round(x1) + 0.5, L.judgeY);
    g.stroke();
  }

  /** 右半边：事件区，6 列 = 6 个参数通道 */
  var KEY_LABEL = {
    x: 'X', y: 'Y', alpha: '透明度', rotation: '旋转', speed: '流速', length: '长度',
    zone: '判定区', parent: '父线'
  };

  /** 左边一屏最多显示几条轨道（多了用下面的滚动条翻） */
  var MAX_VISIBLE_LANES = 6;

  function drawEventLanes() {
    var n = RC.ALL_KEYS.length;
    var x1 = L.eventX0 + L.evColW * n;
    var lane = S.chart.lanes[S.selectedLane];
    var col = lane ? RC.displayColor(lane) : '#4cc9f0';

    g.fillStyle = '#0c0f15';
    g.fillRect(L.eventX0, 0, L.evColW * n, L.judgeY);

    for (var i = 0; i < n; i++) {
      var x = L.eventX0 + i * L.evColW;
      g.strokeStyle = '#1b2130';
      g.lineWidth = 1;
      g.beginPath();
      g.moveTo(Math.round(x) + 0.5, 0);
      g.lineTo(Math.round(x) + 0.5, L.judgeY);
      g.stroke();

      g.fillStyle = '#5f6d8a';
      g.font = '11px ui-sans-serif, system-ui, "Microsoft YaHei", sans-serif';
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillText(KEY_LABEL[RC.ALL_KEYS[i]] || RC.ALL_KEYS[i], x + L.evColW / 2, L.judgeY + 16);
    }

    g.strokeStyle = '#1b2130';
    g.beginPath();
    g.moveTo(Math.round(x1) + 0.5, 0);
    g.lineTo(Math.round(x1) + 0.5, L.judgeY);
    g.stroke();

    // 中间分隔线
    var dx = Math.round(L.noteX0 + L.laneW * L.visCount + (L.eventX0 - (L.noteX0 + L.laneW * L.visCount)) / 2) + 0.5;
    g.strokeStyle = '#232936';
    g.setLineDash([3, 4]);
    g.beginPath();
    g.moveTo(dx, 0);
    g.lineTo(dx, L.judgeY);
    g.stroke();
    g.setLineDash([]);

    // 底部的轨道切换按钮
    for (var b = 0; b < L.laneBtns.length; b++) {
      var r = L.laneBtns[b];
      var on = (b === S.selectedLane);
      g.fillStyle = on ? hexA(col, 0.85) : '#1b2029';
      g.fillRect(r.x, r.y, r.w, r.h);
      g.strokeStyle = on ? col : '#2a3242';
      g.lineWidth = 1;
      g.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1);

      g.fillStyle = on ? '#0b0d12' : '#8a93a6';
      g.font = '11px ui-sans-serif, system-ui, sans-serif';
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillText(String(b + 1), r.x + r.w / 2, r.y + r.h / 2);
    }

    g.fillStyle = '#39425a';
    g.font = '10px ui-sans-serif, system-ui, "Microsoft YaHei", sans-serif';
    g.textAlign = 'right';
    g.fillText('编辑轨道', L.laneBtns.length ? L.laneBtns[0].x - 6 : L.eventX0, L.judgeY + 50);
  }

  function drawGrid() {
    var timing = S.chart.timing;
    var div = S.snapDiv > 0 ? S.snapDiv : 4;
    var bBot = RC.secToBeat(S.viewTime, timing);
    var bTop = RC.secToBeat(yToTime(0), timing);
    if (!isFinite(bBot) || !isFinite(bTop)) return;

    var k0 = Math.floor(bBot * div);
    var k1 = Math.ceil(bTop * div);
    if (k1 - k0 > 4000) return;

    var beatPx = L.pps * RC.secPerBeat(timing);
    var subPx = beatPx / div;
    var drawSub = subPx >= 10;
    var xa = L.laneX0;
    var xb = L.laneX0 + L.laneW * L.visCount;
    var xc = L.eventX0;
    var xd = L.eventX0 + L.laneW * L.visCount;

    g.font = '11px ui-monospace, Consolas, monospace';
    g.textAlign = 'right';
    g.textBaseline = 'middle';

    for (var k = k0; k <= k1; k++) {
      var isBeat = (k % div) === 0;
      if (!isBeat && !drawSub) continue;
      var isMeasure = (k % (div * 4)) === 0;

      var y = timeToY(RC.beatToSec(k / div, timing));
      if (y < -1 || y > L.judgeY + 1) continue;

      if (isMeasure) {
        g.strokeStyle = '#2f394f';
        g.lineWidth = 1.5;
      } else if (isBeat) {
        g.strokeStyle = '#1e2432';
        g.lineWidth = 1;
      } else {
        g.strokeStyle = '#171c26';
        g.lineWidth = 1;
      }

      g.beginPath();
      g.moveTo(xa, Math.round(y) + 0.5);
      g.lineTo(xb, Math.round(y) + 0.5);
      g.stroke();

      g.beginPath();
      g.moveTo(xc, Math.round(y) + 0.5);
      g.lineTo(xd, Math.round(y) + 0.5);
      g.stroke();

      if (isMeasure) {
        g.fillStyle = '#5f6d8a';
        g.fillText(String(Math.round(k / div)), L.gutter - 8, y);
      }
    }
  }

  function drawEvents() {
    var lane = S.chart.lanes[S.selectedLane];
    if (!lane) return;
    var col = RC.displayColor(lane);

    for (var c = 0; c < RC.ALL_KEYS.length; c++) {
      var key = RC.ALL_KEYS[c];
      var arr = (lane.events && lane.events[key]) || [];
      var colX = L.eventX0 + c * L.evColW;
      var inner = Math.max(4, L.evColW - 12);

      for (var j = 0; j < arr.length; j++) {
        var ev = arr[j];
        var yTop = timeToY(ev.end);
        var yBot = timeToY(ev.start);
        if (yBot < -30 || yTop > L.judgeY + 30) continue;

        var h = Math.max(6, yBot - yTop);
        var ax = colX + 6 + evT(key, ev.from) * inner;   // 头：起点值
        var bx = colX + 6 + evT(key, ev.to) * inner;     // 尾：终点值
        var sel = isEvSelected(key, ev.id);
        var bandW = Math.min(13, Math.max(6, L.evColW * 0.3));

        // 没里子、先画一条淡的列内导引，方便看清值在哪
        g.strokeStyle = 'rgba(255,255,255,0.05)';
        g.lineWidth = 1;
        g.beginPath();
        g.moveTo(ax + 0.5, yBot);
        g.lineTo(bx + 0.5, yTop);
        g.stroke();

        // 值→时间的斜条
        g.lineCap = 'round';
        g.strokeStyle = sel ? hexA(col, 0.95) : hexA(col, 0.6);
        g.lineWidth = bandW;
        g.beginPath();
        g.moveTo(ax, yBot);
        g.lineTo(bx, yTop);
        g.stroke();

        // 头尾端点
        g.fillStyle = sel ? '#ffffff' : col;
        g.beginPath();
        g.arc(ax, yBot, sel ? 4 : 3, 0, Math.PI * 2);
        g.fill();
        g.beginPath();
        g.arc(bx, yTop, sel ? 4 : 3, 0, Math.PI * 2);
        g.fill();
        g.lineCap = 'butt';

        if (h > 22) {
          g.fillStyle = 'rgba(255,255,255,0.72)';
          g.font = '9px ui-sans-serif, system-ui, sans-serif';
          g.textAlign = 'center';
          g.textBaseline = 'middle';
          g.fillText(ev.ease, (ax + bx) / 2, (yTop + yBot) / 2);
        }

        if (sel) {
          g.strokeStyle = 'rgba(255,255,255,0.85)';
          g.lineWidth = 1;
          g.beginPath();
          g.arc(ax, yBot, 6, 0, Math.PI * 2);
          g.stroke();
          g.beginPath();
          g.arc(bx, yTop, 6, 0, Math.PI * 2);
          g.stroke();
        }
      }
    }
  }

  function drawNotes() {
    var lanes = S.chart.lanes;
    var notes = S.chart.notes;

    for (var i = 0; i < notes.length; i++) {
      var n = notes[i];
      var lane = lanes[n.lane];
      if (!lane) continue;
      var r = noteRect(n);
      if (!r) continue;                                  // 滚出可见范围了
      if (r.y + r.h < -10 || r.y > L.judgeY + 10) continue;

      var col = RC.displayColor(lane);
      var sel = isSelected(n);

      if (n.type === 'hold') {
        g.fillStyle = hexA(col, 0.28);
        g.fillRect(r.x + 4, r.y, r.w - 8, r.h);
        g.fillStyle = hexA(col, 0.55);
        g.fillRect(r.x, r.y, r.w, Math.max(3, Math.min(NOTE_H, r.h)));
        rr(r.x, r.y + r.h - NOTE_H, r.w, NOTE_H, 4);
        g.fillStyle = col;
        g.fill();
      } else {
        rr(r.x, r.y, r.w, NOTE_H, 5);
        g.fillStyle = col;
        g.fill();
      }

      if (sel) {
        g.strokeStyle = '#ffffff';
        g.lineWidth = 2;
        var pad = 2;
        rr(r.x - pad, r.y - pad, r.w + pad * 2, Math.max(NOTE_H, r.h) + pad * 2, 6);
        g.stroke();
      }
    }
  }

  function drawJudgeLine() {
    var y = L.judgeY;
    var xa = L.laneX0 - 12;
    var xb = L.laneX0 + L.laneW * L.visCount + 12;

    g.fillStyle = 'rgba(247,37,133,0.10)';
    g.fillRect(L.laneX0, y - 7, L.laneW * L.visCount, 14);

    g.strokeStyle = '#f72585';
    g.lineWidth = 2;
    g.beginPath();
    g.moveTo(xa, y + 0.5);
    g.lineTo(xb, y + 0.5);
    g.stroke();

    g.fillStyle = '#f72585';
    g.font = '11px ui-monospace, Consolas, monospace';
    g.textAlign = 'right';
    g.textBaseline = 'middle';
    g.fillText(RC.formTime(S.viewTime), L.gutter - 8, y);
  }

  function drawGhost() {
    var d = S.drag;
    if (!d || d.mode !== 'draw-hold') return;
    var t0 = Math.min(d.t0, d.t1);
    var t1 = Math.max(d.t0, d.t1);
    var x = L.laneX0 + d.lane * L.laneW + 6;
    var w = Math.max(4, L.laneW - 12);
    var y0 = timeToY(t1);
    var y1 = timeToY(t0);
    var h = Math.max(3, y1 - y0);

    g.fillStyle = 'rgba(124,245,193,0.18)';
    g.fillRect(x, y0, w, h);
    g.strokeStyle = '#7cf5c1';
    g.lineWidth = 1;
    g.setLineDash([4, 3]);
    g.strokeRect(x + 0.5, y0 + 0.5, w - 1, h - 1);
    g.setLineDash([]);
  }

  /* ---------- 预渲染窗口（4:3 舞台预览） ---------- */

  var PV = null;

  function computePreviewLayout() {
    var W = Math.max(1, previewCanvas.clientWidth || 0);
    var H = Math.max(1, previewCanvas.clientHeight || 0);
    var dpr = Math.min(2, window.devicePixelRatio || 1);
    var pw = Math.round(W * dpr), ph = Math.round(H * dpr);
    if (previewCanvas.width !== pw || previewCanvas.height !== ph) {
      previewCanvas.width = pw;
      previewCanvas.height = ph;
    }
    var laneCount = Math.max(1, S.chart.lanes.length);
    var judgeY = Math.round(H * 0.85);
    PV = {
      W: W, H: H, dpr: dpr, judgeY: judgeY, laneCount: laneCount,
      laneWidth: Math.min(W * 0.05, (W * 0.43) / laneCount) * PV_SCALE,
      pps: judgeY / Math.max(0.05, S.pvSec)
    };
  }

  /* ---------- 重叠音符标记 ---------- */

  var dupCache = null;

  function dups() {
    if (!dupCache) dupCache = RC.duplicateGroups(S.chart);
    return dupCache;
  }

  function dropDupCache() { dupCache = null; issueCache = null; }

  /** 跳到下一处重叠（找不到就绕回第一处），并选中那一组 */
  function nextDupGroup() {
    var list = dups();
    if (!list.length) {
      setHint('没有重叠的音符');
      return;
    }
    var pick = null;
    for (var i = 0; i < list.length; i++) {
      if (list[i].time > S.viewTime + 1e-4) { pick = list[i]; break; }
    }
    if (!pick) pick = list[0];
    if (S.playing) pause();
    setPlayhead(pick.time);
    S.selectedIds = pick.notes.map(function (n) { return n.id; });
    S.selectedId = S.selectedIds[0];
    var idx = list.indexOf(pick) + 1;
    setHint('第 ' + idx + '/' + list.length + ' 组重叠：轨道 ' + (pick.lane + 1) +
      ' · ' + RC.formTime(pick.time) + ' · ' + pick.notes.length + ' 个');
    refreshStatus(true);
  }

  var issueCache = null;

  function issues() {
    if (!issueCache) issueCache = RC.chartIssues(S.chart);
    return issueCache;
  }

  /** 跳到下一处有问题的地方（找不到就绕回第一处） */
  function nextIssue() {
    var list = issues();
    if (!list.length) {
      setHint('没发现问题');
      return;
    }
    var pick = null;
    for (var i = 0; i < list.length; i++) {
      if (list[i].time > S.viewTime + 1e-4) { pick = list[i]; break; }
    }
    if (!pick) pick = list[0];
    if (S.playing) pause();
    setPlayhead(pick.time);
    S.selectedIds = pick.ids.slice();
    S.selectedId = S.selectedIds[0];
    var idx = list.indexOf(pick) + 1;
    setHint('第 ' + idx + '/' + list.length + ' 处问题：' + pick.text +
      '（轨道 ' + (pick.lane + 1) + ' · ' + RC.formTime(pick.time) + '）');
    refreshStatus(true);
  }

  /** 在时间轴里给重叠的音符描一圈 */
  function drawDupMarks() {
    var list = dups();
    if (!list.length) return;
    g.save();
    g.strokeStyle = '#f72585';
    g.lineWidth = 1.5;
    g.setLineDash([3, 2]);
    for (var i = 0; i < list.length; i++) {
      var grp = list[i];
      var local = grp.lane - L.laneScroll;
      if (local < 0 || local >= L.visCount) continue;
      var x = L.laneX0 + local * L.laneW;
      var y = timeToY(grp.time);
      if (y < -20 || y > L.judgeY + 20) continue;
      g.strokeRect(x + 1.5, y - NOTE_H / 2 - 4, Math.max(4, L.laneW - 3), NOTE_H + 8);
    }
    g.restore();
  }

  /**
   * 轨道在舞台上的几何。有父线时，x / y / 旋转 都是「在父线坐标系里的相对量」：
   * x 沿父线的横向、y 沿父线的轨道方向（向上为正），旋转是叠加的。
   * 所以父线一动，子线整条跟着动。父线是事件通道，可以随时间变、也可以设回 0 取消。
   */
  function laneGeom(i, depth, seen) {
    depth = depth || 0;
    seen = seen || {};
    var lane = S.chart.lanes[i];
    var p = RC.laneParamsAt(lane, S.viewTime);
    var rotDeg = RC.num(p.rotation, 0);
    var px = RC.num(p.x, 0);
    var py = RC.num(p.y, 0);

    var base;
    var parentIdx = RC.parentAt(lane, S.viewTime, S.chart.lanes.length);
    // 防环：父链上再遇到自己就当没有父线
    if (parentIdx >= 0 && parentIdx !== i && !seen[parentIdx] && depth < 8) {
      seen[i] = true;
      var pfg = laneGeom(parentIdx, depth + 1, seen);
      base = {
        cx: pfg.cx + pfg.sx * px + pfg.dx * py,
        cy: pfg.cy + pfg.sy * px + pfg.dy * py,
        rot: pfg.rotDeg + rotDeg
      };
    } else {
      parentIdx = -1;
      base = { cx: PV.W / 2 + px, cy: PV.judgeY - py, rot: rotDeg };   // Y 向上为正，所以减
    }

    var rad = base.rot * Math.PI / 180;
    return {
      lane: lane,
      index: i + 1,                      // 轨道编号（1 起）
      parent: parentIdx,
      rotDeg: base.rot,
      alpha: RC.laneAlpha(p),
      speed: RC.laneSpeed(p),
      halfW: Math.max(2, PV.laneWidth / 2 - 0.5),
      len: PV.judgeY * RC.laneLength(p),
      cx: base.cx,
      cy: base.cy,
      dx: Math.sin(rad),
      dy: -Math.cos(rad),
      sx: Math.cos(rad),
      sy: Math.sin(rad)
    };
  }

  function lanePointAt(g, d) {
    return { x: g.cx + g.dx * d, y: g.cy + g.dy * d };
  }

  /** 以「距判定线 d」为中心、宽 halfW、厚 th 的四边形（音符头） */
  function noteQuad(g, d, halfW, th) {
    var c = lanePointAt(g, d);
    return [
      { x: c.x - g.sx * halfW - g.dx * th, y: c.y - g.sy * halfW - g.dy * th },
      { x: c.x + g.sx * halfW - g.dx * th, y: c.y + g.sy * halfW - g.dy * th },
      { x: c.x + g.sx * halfW + g.dx * th, y: c.y + g.sy * halfW + g.dy * th },
      { x: c.x - g.sx * halfW + g.dx * th, y: c.y - g.sy * halfW + g.dy * th }
    ];
  }

  /** 从 d0 到 d1 的一段长条（hold 身体、轨道地面） */
  function bandQuad(g, d0, d1, halfW) {
    var a = lanePointAt(g, d0);
    var b = lanePointAt(g, d1);
    return [
      { x: a.x - g.sx * halfW, y: a.y - g.sy * halfW },
      { x: a.x + g.sx * halfW, y: a.y + g.sy * halfW },
      { x: b.x + g.sx * halfW, y: b.y + g.sy * halfW },
      { x: b.x - g.sx * halfW, y: b.y - g.sy * halfW }
    ];
  }

  function pathQuad(ctx, q) {
    ctx.beginPath();
    ctx.moveTo(q[0].x, q[0].y);
    ctx.lineTo(q[1].x, q[1].y);
    ctx.lineTo(q[2].x, q[2].y);
    ctx.lineTo(q[3].x, q[3].y);
    ctx.closePath();
  }

  function drawPreview() {
    computePreviewLayout();
    pg.setTransform(PV.dpr, 0, 0, PV.dpr, 0, 0);
    pg.clearRect(0, 0, PV.W, PV.H);
    pg.fillStyle = '#080a0e';
    pg.fillRect(0, 0, PV.W, PV.H);

    var n = S.chart.lanes.length;
    var geo = [];
    var i;
    for (i = 0; i < n; i++) geo.push(laneGeom(i));

    // 全部轨道都是 0 透明度、又还没音符时给一句说明，免得以为窗口坏了
    var anyVisible = false;
    for (i = 0; i < n; i++) {
      if (geo[i].alpha > 0.001) { anyVisible = true; break; }
    }
    var empty = $('pv-empty');
    if (empty) {
      empty.style.display = (!anyVisible && S.chart.notes.length === 0) ? 'flex' : 'none';
    }

    for (i = 0; i < n; i++) drawLaneBody(geo[i]);
    drawPreviewNotes(geo);
    for (i = 0; i < n; i++) drawLaneJudge(geo[i]);
    for (i = 0; i < n; i++) drawLaneNumber(geo[i]);
    pg.globalAlpha = 1;
  }
  /** 轨道编号：贴在判定线外面一点，跟着轨道一起转 */
  function drawLaneNumber(g) {
    var col = RC.displayColorAt(g.lane, S.viewTime);
    var at = lanePointAt(g, -11);            // 判定线往「玩家这边」退 11px
    var size = Math.max(8, Math.min(12, g.halfW * 0.95));
    pg.globalAlpha = 0.85;
    pg.fillStyle = hexA(col, 0.9);
    pg.font = '600 ' + size.toFixed(1) + 'px ui-monospace, Consolas, monospace';
    pg.textAlign = 'center';
    pg.textBaseline = 'middle';
    pg.fillText(String(g.index), at.x, at.y);
    pg.globalAlpha = 1;
  }

  function drawLaneBody(g) {
    if (g.alpha <= 0.001 || g.len < 0.5) return;   // 长度为 0 时只剩判定线
    var col = RC.displayColorAt(g.lane, S.viewTime);
    var q = bandQuad(g, 0, g.len, g.halfW);

    pathQuad(pg, q);
    pg.globalAlpha = g.alpha;
    pg.fillStyle = 'rgba(255,255,255,0.030)';
    pg.fill();

    pg.strokeStyle = hexA(col, 0.16);
    pg.lineWidth = 1;
    pg.beginPath();
    pg.moveTo(q[0].x, q[0].y); pg.lineTo(q[3].x, q[3].y);
    pg.moveTo(q[1].x, q[1].y); pg.lineTo(q[2].x, q[2].y);
    pg.stroke();
    pg.globalAlpha = 1;
  }

  function drawLaneJudge(g) {
    if (g.alpha <= 0.001) return;
    var col = RC.displayColorAt(g.lane, S.viewTime);

    pg.globalAlpha = g.alpha;
    pathQuad(pg, bandQuad(g, -3.2, 3.2, g.halfW));
    pg.fillStyle = hexA(col, 0.16);
    pg.fill();

    var q = bandQuad(g, 0, 0.0001, g.halfW);
    pg.strokeStyle = col;
    pg.lineWidth = 1.6;
    pg.beginPath();
    pg.moveTo(q[0].x, q[0].y);
    pg.lineTo(q[1].x, q[1].y);
    pg.stroke();
    pg.globalAlpha = 1;
  }

  function drawPreviewNotes(geo) {
    var notes = S.chart.notes;

    for (var k = 0; k < notes.length; k++) {
      var nt = notes[k];
      var g = geo[nt.lane];
      if (!g) continue;

      // 音符不受轨道透明度影响：轨道可以全透明，note 照常画
      var pps = PV.pps * g.speed;
      var head = (nt.time - S.viewTime) * pps;
      var dur = (nt.type === 'hold') ? Math.max(0, nt.duration) : 0;
      var isHold = dur > 0.001;
      // 长条长度必须和头用同一个流速基准，否则流速一变，
      // 头已经过线而「按旧流速算出来的尾巴」还在判定线上方 → 长条卡在那儿不消失。
      // 流速 0 时音符全压在判定线上、长条会缩没，所以回退到最近的非零流速。
      var bodyMul = g.speed > 0.001 ? g.speed : RC.holdSpeed(g.lane, S.viewTime);
      var tail = head + dur * PV.pps * bodyMul;

      // 剔除：长条要看「尾巴」是否过线，不能按头算 —— 否则头一过判定线 40px
      // 整条就被砍掉，明明身上还有一大截。
      if (isHold) {
        if (tail < -10) continue;                 // 整条都过判定线了
      } else if (head < -0.5) {
        continue;                                 // 普通音符落到判定线就直接消失，不做缓动
      }
      if (head > g.len + 40) continue;            // 还没进视野

      // 长条的头到线就定住（身体随尾巴缩进去）；普通音符走不到负数区间
      var headD = Math.max(0, head);

      var col = RC.displayColorAt(g.lane, S.viewTime);
      var halfW = Math.max(2, g.halfW - 1);
      pg.globalAlpha = 1;

      if (isHold && tail > 0) {
        var d0 = Math.max(0, head);
        var d1 = Math.min(tail, g.len);
        if (d1 > d0) {
          pathQuad(pg, bandQuad(g, d0, d1, halfW));
          pg.fillStyle = hexA(col, 0.30);
          pg.fill();
        }
      }

      // 长条的头贴在判定线上，身体随尾巴一起缩进去
      var q = noteQuad(g, headD, halfW, NOTE_TH);

      pathQuad(pg, q);
      pg.fillStyle = hexA(col, 0.92);
      pg.fill();
      pg.strokeStyle = 'rgba(255,255,255,0.55)';
      pg.lineWidth = 1.5;
      pg.beginPath();
      pg.moveTo(q[0].x, q[0].y);
      pg.lineTo(q[1].x, q[1].y);
      pg.stroke();

      pg.globalAlpha = 1;
    }
  }

  /* ---------- 音符密度条（时间轴左边那条窄带） ---------- */

  var miniBins = [];

  /** 密度条覆盖的时间跨度：有音频就按整首歌，没音频就按谱面时长 */
  function songSpan() {
    var span = RC.chartDuration(S.chart);
    if (S.audio && isFinite(S.audio.duration) && S.audio.duration > 0) {
      var end = S.audio.duration - RC.num(S.chart.audio.offset, 0);
      if (end > span) span = end;
    }
    return span;
  }

  /** 密度条在画布 y 处对应的时间（整首歌从判定线到顶部） */
  function minimapTime(y) {
    var dur = songSpan();
    if (dur <= 0) return 0;
    return RC.clamp((L.judgeY - y) / L.judgeY, 0, 1) * dur;
  }

  function inMinimap(x, y) {
    return !!L.mini && x >= L.mini.x && x <= L.mini.x + L.mini.w && y >= 0 && y <= L.judgeY;
  }

  function drawMinimap() {
    if (!L.mini) return;

    var x = L.mini.x;
    var w = L.mini.w;
    var h = L.judgeY;
    var notes = S.chart.notes;
    var dur = songSpan();

    g.fillStyle = '#0b0e14';
    g.fillRect(x, 0, w, h);
    g.strokeStyle = '#1b2130';
    g.lineWidth = 1;
    g.strokeRect(x + 0.5, 0.5, w - 1, h - 1);

    if (notes.length === 0 || dur <= 0) {
      g.fillStyle = '#39425a';
      g.font = '10px ui-sans-serif, system-ui, "Microsoft YaHei", sans-serif';
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillText('空', x + w / 2, h / 2);
      return;
    }

    var bins = Math.max(8, Math.floor(h / 3));
    if (miniBins.length !== bins) miniBins.length = bins;
    var i;
    for (i = 0; i < bins; i++) miniBins[i] = 0;

    var maxCount = 0;
    for (i = 0; i < notes.length; i++) {
      var y = h - (notes[i].time / dur) * h;
      var j = Math.floor(y / (h / bins));
      if (j < 0) j = 0;
      if (j > bins - 1) j = bins - 1;
      miniBins[j]++;
      if (miniBins[j] > maxCount) maxCount = miniBins[j];
    }

    var binH = h / bins;
    for (i = 0; i < bins; i++) {
      var c = miniBins[i];
      if (!c) continue;
      var ratio = c / maxCount;
      var bw = Math.max(2, ratio * (w - 4));
      g.fillStyle = ratio > 0.66 ? '#f72585' : (ratio > 0.33 ? '#b06bff' : '#4cc9f0');
      g.globalAlpha = 0.35 + ratio * 0.6;
      g.fillRect(x + w - 2 - bw, i * binH, bw, Math.max(1, binH - 1));
      g.globalAlpha = 1;
    }

    // 播放头位置
    var py = h - (S.viewTime / dur) * h;
    if (py >= 0 && py <= h) {
      g.strokeStyle = '#ffffff';
      g.lineWidth = 1;
      g.beginPath();
      g.moveTo(x, Math.round(py) + 0.5);
      g.lineTo(x + w, Math.round(py) + 0.5);
      g.stroke();
    }
  }

  /* ---------- 事件命中 ---------- */

  /** 各参数在事件列里「一列宽」代表的值域（画图和拖动都用它） */
  var EV_RANGE = {
    x: [-400, 400],
    y: [-400, 400],
    alpha: [0, 100],
    rotation: [-180, 180],
    speed: [0, 100],
    length: [0, 100],
    zone: [0, 2]
  };

  function evRange(key) {
    if (key === 'parent') return [0, Math.max(1, S.chart.lanes.length)];
    return EV_RANGE[key] || [0, 100];
  }

  /** 参数值 → 列内 0~1 的横向位置 */
  function evT(key, v) {
    var r = evRange(key);
    return RC.clamp((RC.num(v, 0) - r[0]) / (r[1] - r[0]), 0, 1);
  }

  /** 横向拖 1 像素代表多少参数值 */
  function evValuePerPixel(key) {
    var r = evRange(key);
    return (r[1] - r[0]) / Math.max(1, L.evColW);
  }

  function eventColAt(x) {
    if (x < L.eventX0) return -1;
    var i = Math.floor((x - L.eventX0) / L.evColW);
    if (i < 0 || i > RC.ALL_KEYS.length - 1) return -1;
    return i;
  }

  function eventRectAt(ev, col) {
    var x = L.eventX0 + col * L.evColW + 3;
    var w = Math.max(4, L.evColW - 6);
    var yTop = timeToY(ev.end);
    var yBot = timeToY(ev.start);
    return { x: x, y: yTop, w: w, h: Math.max(6, yBot - yTop) };
  }

  function laneBtnAt(x, y) {
    for (var i = 0; i < L.laneBtns.length; i++) {
      var r = L.laneBtns[i];
      if (x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h) return r.idx;
    }
    return -1;
  }

  function hitEvent(px, py) {
    var c = eventColAt(px);
    if (c < 0) return null;
    var key = RC.ALL_KEYS[c];
    var lane = S.chart.lanes[S.selectedLane];
    var arr = (lane && lane.events && lane.events[key]) || [];

    for (var i = arr.length - 1; i >= 0; i--) {
      var r = eventRectAt(arr[i], c);
      if (py >= r.y - 4 && py <= r.y + r.h + 4) {
        var part = 'body';
        if (Math.abs(py - r.y) <= 7) part = 'tail';
        else if (Math.abs(py - (r.y + r.h)) <= 7) part = 'head';
        return { key: key, col: c, event: arr[i], rect: r, part: part };
      }
    }
    return null;
  }

  /* ---------- 框选 ---------- */

  function applyBoxSelect(d) {
    var x1 = Math.min(d.x0, d.x1);
    var x2 = Math.max(d.x0, d.x1);
    var y1 = Math.min(d.y0, d.y1);
    var y2 = Math.max(d.y0, d.y1);

    // 几乎没拖动 = 当作点空白，清空选择
    if (x2 - x1 < 4 && y2 - y1 < 4) {
      selectOnly(0);
      refreshStatus(true);
      return;
    }

    var ids = [];
    var notes = S.chart.notes;
    for (var i = 0; i < notes.length; i++) {
      var r = noteRect(notes[i]);
      if (!r) continue;                                  // 不在可见轨道里
      if (r.x + r.w < x1 || r.x > x2) continue;
      if (r.y + r.h < y1 || r.y > y2) continue;
      ids.push(notes[i].id);
    }

    S.selectedIds = ids;
    S.selectedId = ids.length ? ids[0] : 0;
    setHint(ids.length
      ? '框选了 ' + ids.length + ' 个音符（Del 删除，拖任意一个整组一起动）'
      : '框选没选中东西');
    refreshStatus(true);
  }

  /** 事件区框选：列落在框内、且时间区间和框有重叠的都算选中 */
  function applyEvBoxSelect(d) {
    var x1 = Math.min(d.x0, d.x1);
    var x2 = Math.max(d.x0, d.x1);
    var y1 = Math.min(d.y0, d.y1);
    var y2 = Math.max(d.y0, d.y1);

    if (x2 - x1 < 4 && y2 - y1 < 4) {
      selectEvOnly('x', 0);
      refreshStatus(true);
      return;
    }

    var lane = S.chart.lanes[S.selectedLane];
    var picked = [];
    if (lane) {
      for (var c = 0; c < RC.ALL_KEYS.length; c++) {
        var colX = L.eventX0 + c * L.evColW;
        if (colX + L.evColW < x1 || colX > x2) continue;
        var key = RC.ALL_KEYS[c];
        var arr = (lane.events && lane.events[key]) || [];
        for (var i = 0; i < arr.length; i++) {
          var ev = arr[i];
          var yTop = timeToY(ev.end);
          var yBot = timeToY(ev.start);
          if (yBot < y1 || yTop > y2) continue;
          picked.push({ key: key, id: ev.id });
        }
      }
    }

    S.selectedEvs = picked;
    if (picked.length) {
      S.selectedEventKey = picked[0].key;
      S.selectedEventId = picked[0].id;
    } else {
      S.selectedEventId = 0;
    }
    syncEventPanel();
    setHint(picked.length
      ? '框选了 ' + picked.length + ' 个事件（Del 删除，Ctrl+C / Ctrl+V 复制粘贴，拖任意一个整组一起动）'
      : '框选没选中事件');
    refreshStatus(true);
  }

  function drawBox() {
    var d = S.drag;
    if (!d || (d.mode !== 'box' && d.mode !== 'evbox')) return;

    var x = Math.min(d.x0, d.x1);
    var y = Math.min(d.y0, d.y1);
    var w = Math.abs(d.x1 - d.x0);
    var h = Math.abs(d.y1 - d.y0);

    g.fillStyle = 'rgba(76,201,240,0.10)';
    g.fillRect(x, y, w, h);
    g.strokeStyle = '#4cc9f0';
    g.lineWidth = 1;
    g.setLineDash([4, 3]);
    g.strokeRect(x + 0.5, y + 0.5, w, h);
    g.setLineDash([]);
  }

  /* ---------- 轨道滚动条（DOM 控件，不画在 canvas 上） ---------- */

  function laneScrollMax() {
    return Math.max(0, S.chart.lanes.length - MAX_VISIBLE_LANES);
  }

  function syncLaneScrollUI() {
    var wrap = $('lane-scroll');
    if (!wrap) return;
    var max = laneScrollMax();
    var vis = Math.min(MAX_VISIBLE_LANES, S.chart.lanes.length);

    if (max <= 0) {
      wrap.hidden = true;
      return;
    }
    wrap.hidden = false;
    S.laneScroll = RC.clamp(S.laneScroll, 0, max);

    var range = $('ls-range');
    if (range) {
      range.max = String(max);
      range.value = String(S.laneScroll);
    }
    var info = $('ls-info');
    if (info) info.textContent = (S.laneScroll + 1) + '–' + (S.laneScroll + vis) + ' / ' + S.chart.lanes.length;

    var left = $('ls-left');
    var right = $('ls-right');
    if (left) left.disabled = S.laneScroll <= 0;
    if (right) right.disabled = S.laneScroll >= max;
  }

  function setLaneScroll(v) {
    S.laneScroll = RC.clamp(v, 0, laneScrollMax());
    syncLaneScrollUI();
    refreshStatus(true);
  }

  function bindLaneScroll() {
    var range = $('ls-range');
    if (range) {
      range.addEventListener('input', function () {
        setLaneScroll(RC.int(range.value, 0));
      });
    }
    var left = $('ls-left');
    if (left) left.addEventListener('click', function () { setLaneScroll(S.laneScroll - 1); });
    var right = $('ls-right');
    if (right) right.addEventListener('click', function () { setLaneScroll(S.laneScroll + 1); });
  }

  /* ---------- 命中测试 ---------- */
  /* ---------- 命中测试 ---------- */

  function hitTest(px, py) {
    var lane = laneAt(px);
    if (lane < 0) return null;

    var best = null;
    var notes = S.chart.notes;
    for (var i = 0; i < notes.length; i++) {
      var n = notes[i];
      if (n.lane !== lane) continue;
      var r = noteRect(n);
      if (!r) continue;
      if (py >= r.y - 3 && py <= r.y + r.h + 3) {
        best = { note: n, rect: r };
        if (isSelected(n)) break;
      }
    }
    if (!best) return null;

    var part = 'body';
    if (best.rect.hold && Math.abs(py - best.rect.y) <= 8) part = 'tail';
    return { note: best.note, rect: best.rect, part: part };
  }


  /* ---------- 撤销 ---------- */

  function snapshot() { return JSON.stringify(RC.serialize(S.chart)); }

  function syncButtons() {
    $('btn-undo').disabled = S.undo.length === 0;
    $('btn-redo').disabled = S.redo.length === 0;
  }

  function markDirty() {
    dropDupCache();
    S.dirty = true;
    updateTitle();
  }

  function sbTag() {
    return S.storyboardName ? ' · 含故事板' : '';
  }

  function updateTitle() {
    var name = S.fileName || '新谱面';
    $('file-name').textContent = (S.dirty ? '● ' : '') + name + sbTag();
  }

  function pushUndo(before) {
    var after = snapshot();
    if (before === after) return;
    S.undo.push(before);
    if (S.undo.length > 200) S.undo.shift();
    S.redo.length = 0;
    markDirty();
    syncButtons();
  }

  /** 一次完整操作 = 一个撤销步 */
  function act(fn) {
    var before = snapshot();
    fn();
    pushUndo(before);
    refreshStatus(true);
  }

  function restore(json) {
    dropDupCache();
    var res = RC.normalize(JSON.parse(json));
    if (!res.chart) return;
    S.chart = res.chart;
    S.selectedIds = S.selectedIds.filter(function (id) { return !!RC.findNote(S.chart, id); });
    if (!RC.findNote(S.chart, S.selectedId)) S.selectedId = S.selectedIds.length ? S.selectedIds[0] : 0;
    S.selectedEvs = S.selectedEvs.filter(function (s) { return !!RC.findEvent(S.chart.lanes[S.selectedLane], s.key, s.id); });
    if (!currentEvent()) selectEvOnly(S.selectedEventKey, S.selectedEvs.length ? S.selectedEvs[0].id : 0);
    syncInputs();
    refreshStatus(true);
    markDirty();
  }

  function undo() {
    if (!S.undo.length) return;
    var cur = snapshot();
    var prev = S.undo.pop();
    S.redo.push(cur);
    restore(prev);
    syncButtons();
  }

  function redo() {
    if (!S.redo.length) return;
    var cur = snapshot();
    var next = S.redo.pop();
    S.undo.push(cur);
    restore(next);
    syncButtons();
  }

  /* ---------- 状态栏 ---------- */

  var lastStatus = 0;

  function refreshStatus(force) {
    var now = performance.now();
    if (!force && now - lastStatus < 90) return;
    lastStatus = now;

    var c = RC.countNotes(S.chart);
    $('st-time').textContent = RC.formTime(S.viewTime);
    $('st-notes').textContent =
      '音符 ' + c.total + '（tap ' + c.tap + ' · hold ' + c.hold + '）';
    $('st-bpm').textContent = 'BPM ' + S.chart.timing.bpm;
    $('st-len').textContent = '谱面时长 ' + RC.formTime(RC.chartDuration(S.chart));
    var nd = $('st-dup');
    if (nd) {
      var dg = dups();
      nd.textContent = dg.length ? ('重叠 ' + dg.length + ' 组') : '';
    }
  }

  function setHint(text) {
    $('st-hint').textContent = text;
    if (S.hintTimer) clearTimeout(S.hintTimer);
    S.hintTimer = setTimeout(function () {
      $('st-hint').textContent = HINT;
    }, 6000);
  }

  /* ---------- 侧栏绑定 ---------- */

  function syncInputs() {
    $('f-title').value = S.chart.meta.title;
    $('f-artist').value = S.chart.meta.artist;
    $('f-charter').value = S.chart.meta.charter;
    $('f-difficulty').value = S.chart.meta.difficulty;
    $('f-level').value = S.chart.meta.level;
    $('f-illustrator').value = S.chart.meta.illustrator;
    $('f-offset').value = S.chart.audio.offset;
    syncVolumeUI();
    $('f-bpm').value = S.chart.timing.bpm;
    $('f-beatoffset').value = S.chart.timing.beat_offset;
    $('f-highway').value = S.highwaySec;
    $('f-pvsec').value = S.pvSec;
    $('f-lanecount').value = S.chart.lanes.length;
    $('snap').value = String(S.snapDiv);
    $('audio-name').textContent = S.audioName || (S.chart.audio.file ? S.chart.audio.file + '（未载入）' : '未载入');
    var cn = $('cover-name');
    if (cn) cn.textContent = S.coverFile ? S.coverFile.name : (S.chart.meta.cover ? S.chart.meta.cover + '（未载入）' : '未选择曲绘');
    clampSelectedLane();
    syncLaneScrollUI();
    syncEventPanel();
    syncButtons();
    updateTitle();
  }

  /** 文本类：输入即时生效，失焦/回车才记一个撤销步 */
  function bindText(id, apply) {
    var el = $(id);
    var before = null;
    el.addEventListener('focus', function () { before = snapshot(); });
    el.addEventListener('input', function () {
      apply(el.value);
      markDirty();
      refreshStatus(true);
    });
    el.addEventListener('change', function () {
      if (before !== null) pushUndo(before);
      before = null;
      refreshStatus(true);
    });
    el.addEventListener('blur', function () {
      if (before !== null) { pushUndo(before); before = null; }
    });
  }

  /** 数字/下拉：change 时一次性生效 */
  function bindValue(id, apply) {
    var el = $(id);
    el.addEventListener('change', function () {
      var before = snapshot();
      apply(el.value);
      pushUndo(before);
      refreshStatus(true);
    });
  }

  function flushInputs() {
    var el = document.activeElement;
    if (el && (el.tagName === 'INPUT' || el.tagName === 'SELECT')) el.blur();
  }

  /* ---------- 轨道判定区 ---------- */

  function esc(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  /* ---------- 轨道参数（坐标 / 透明度 / 流速 / 长度 / 旋转） ---------- */

  function currentLane() {
    var lanes = S.chart.lanes;
    if (!lanes.length) return null;
    S.selectedLane = RC.clamp(S.selectedLane, 0, lanes.length - 1);
    return lanes[S.selectedLane];
  }

  /* ---------- 事件的复制 / 粘贴 ---------- */

  function copyEvents() {
    var list = selectedEventList();
    if (!list.length) {
      setHint('先选中事件再复制');
      return;
    }

    var minStart = Infinity;
    var i;
    for (i = 0; i < list.length; i++) {
      if (list[i].ev.start < minStart) minStart = list[i].ev.start;
    }

    S.eventClip = {
      lane: S.selectedLane,
      items: list.map(function (g) {
        return {
          key: g.key,
          rel: RC.round3(g.ev.start - minStart),
          dur: Math.max(0.02, RC.round3(g.ev.end - g.ev.start)),
          ease: g.ev.ease,
          from: g.ev.from,
          to: g.ev.to
        };
      })
    };

    setHint('复制了 ' + S.eventClip.items.length + ' 个事件（Ctrl+V 贴到播放头）');
  }

  function pasteEvents() {
    if (!S.eventClip || !S.eventClip.items.length) {
      setHint('剪贴板里还没有事件');
      return;
    }
    var lane = S.chart.lanes[S.selectedLane];
    if (!lane) return;

    var base = snapT(S.viewTime);
    var src = S.eventClip.items;
    var made = [];

    act(function () {
      for (var i = 0; i < src.length; i++) {
        var it = src[i];
        var ev = RC.addEvent(lane, it.key, {
          start: Math.max(0, base + it.rel),
          end: Math.max(0, base + it.rel) + it.dur,
          ease: it.ease,
          from: it.from,
          to: it.to
        });
        made.push({ key: it.key, id: ev.id });
      }
    });

    if (made.length) {
      S.selectedEvs = made;
      S.selectedEventKey = made[0].key;
      S.selectedEventId = made[0].id;
      syncEventPanel();
    }
    setHint('把 ' + made.length + ' 个事件贴到了 ' + RC.formTime(base) +
      '（轨道 ' + (S.selectedLane + 1) + '）');
  }

  /* ---------- 缓动曲线预览 ---------- */

  var easeCanvas = $('ease-canvas');
  var easeCtx = easeCanvas ? easeCanvas.getContext('2d') : null;
  var easeLastDraw = 0;

  function drawEaseCurve() {
    if (!easeCtx || !easeCanvas) return;

    var W = Math.max(1, easeCanvas.clientWidth || 0);
    var H = Math.max(1, easeCanvas.clientHeight || 0);
    var dpr = Math.min(2, window.devicePixelRatio || 1);
    var pw = Math.round(W * dpr), ph = Math.round(H * dpr);
    if (easeCanvas.width !== pw || easeCanvas.height !== ph) {
      easeCanvas.width = pw;
      easeCanvas.height = ph;
    }

    var c = easeCtx;
    c.setTransform(dpr, 0, 0, dpr, 0, 0);
    c.clearRect(0, 0, W, H);
    c.fillStyle = '#0e1117';
    c.fillRect(0, 0, W, H);

    var pad = 8;
    var x0 = pad, y0 = pad;
    var w = Math.max(1, W - pad * 2);
    var h = Math.max(1, H - pad * 2);

    c.strokeStyle = '#1b2130';
    c.lineWidth = 1;
    for (var g = 1; g < 4; g++) {
      var gy = y0 + (h * g) / 4;
      c.beginPath();
      c.moveTo(x0, gy + 0.5);
      c.lineTo(x0 + w, gy + 0.5);
      c.stroke();
    }

    c.strokeStyle = '#2a3242';
    c.setLineDash([3, 3]);
    c.beginPath();
    c.moveTo(x0, y0 + h);
    c.lineTo(x0 + w, y0);
    c.stroke();
    c.setLineDash([]);

    var ev = currentEvent();
    var sel = $('ev-ease');
    var name = ev ? ev.ease : ((sel && sel.value) || 'linear');

    var N = 64;
    c.strokeStyle = ev ? '#4cc9f0' : '#3a4457';
    c.lineWidth = 2;
    c.beginPath();
    for (var i = 0; i <= N; i++) {
      var k = i / N;
      var px = x0 + w * k;
      var py = y0 + h * (1 - RC.easeAt(name, k));
      if (i === 0) c.moveTo(px, py);
      else c.lineTo(px, py);
    }
    c.stroke();

    // 播放头在曲线上的位置
    if (ev) {
      var span = ev.end - ev.start;
      var k0 = span > 1e-6 ? (S.viewTime - ev.start) / span : -1;
      if (k0 >= 0 && k0 <= 1) {
        var mx = x0 + w * k0;
        var my = y0 + h * (1 - RC.easeAt(name, k0));
        c.strokeStyle = 'rgba(247,37,133,0.45)';
        c.lineWidth = 1;
        c.beginPath();
        c.moveTo(mx, y0);
        c.lineTo(mx, y0 + h);
        c.stroke();

        c.fillStyle = '#f72585';
        c.beginPath();
        c.arc(mx, my, 3, 0, Math.PI * 2);
        c.fill();
      }
    }
  }

  /* ---------- 事件面板 ---------- */

  function isEvSelected(key, id) {
    for (var i = 0; i < S.selectedEvs.length; i++) {
      if (S.selectedEvs[i].key === key && S.selectedEvs[i].id === id) return true;
    }
    return false;
  }

  function selectEvOnly(key, id) {
    S.selectedEventKey = key;
    S.selectedEventId = id || 0;
    S.selectedEvs = id ? [{ key: key, id: id }] : [];
  }

  function toggleEv(key, id) {
    if (isEvSelected(key, id)) {
      S.selectedEvs = S.selectedEvs.filter(function (s) {
        return !(s.key === key && s.id === id);
      });
      if (S.selectedEventId === id && S.selectedEventKey === key) {
        var first = S.selectedEvs[0];
        S.selectedEventId = first ? first.id : 0;
        S.selectedEventKey = first ? first.key : 'x';
      }
    } else {
      S.selectedEvs.push({ key: key, id: id });
      S.selectedEventId = id;
      S.selectedEventKey = key;
    }
  }

  /** 当前选中的事件（连同通道名） */
  function selectedEventList() {
    var lane = currentLane();
    var out = [];
    if (!lane) return out;
    for (var i = 0; i < S.selectedEvs.length; i++) {
      var s = S.selectedEvs[i];
      var ev = RC.findEvent(lane, s.key, s.id);
      if (ev) out.push({ key: s.key, ev: ev });
    }
    return out;
  }

  function currentEvent() {
    var lane = currentLane();
    if (!lane) return null;
    return RC.findEvent(lane, S.selectedEventKey, S.selectedEventId);
  }

  function syncEventPanel() {
    var ev = currentEvent();
    var title = $('ev-title');
    var prop = $('ev-prop');
    var from = $('ev-from');
    var to = $('ev-to');
    var sel = $('ev-ease');

    if (from) { from.disabled = !ev; from.value = ev ? ev.from : ''; }
    if (to) { to.disabled = !ev; to.value = ev ? ev.to : ''; }
    if (sel) { sel.disabled = !ev; if (ev) sel.value = ev.ease; }

    if (prop) {
      var extra = S.selectedEvs.length > 1 ? '　（选中 ' + S.selectedEvs.length + ' 个）' : '';
      prop.textContent = ev
        ? '属性：' + (KEY_LABEL[S.selectedEventKey] || S.selectedEventKey) +
          '　轨道 ' + (S.selectedLane + 1) + extra
        : '属性：—';
    }

    if (title) {
      title.textContent = ev
        ? RC.formTime(ev.start) + ' → ' + RC.formTime(ev.end)
        : '右半边拖一下画事件';
    }

    drawEaseCurve();
  }

  function bindEventPanel() {
    var sel = $('ev-ease');
    if (sel) {
      var opts = '';
      for (var i = 0; i < RC.EASE_NAMES.length; i++) {
        opts += '<option value="' + RC.EASE_NAMES[i] + '">' + RC.EASE_NAMES[i] + '</option>';
      }
      sel.innerHTML = opts;
    }

    ['from', 'to'].forEach(function (which) {
      var el = $('ev-' + which);
      if (!el) return;
      el.addEventListener('change', function () {
        var ev = currentEvent();
        if (!ev) return;
        var before = snapshot();
        ev[which] = RC.clampLaneNum(S.selectedEventKey, el.value);
        el.value = ev[which];
        pushUndo(before);
        refreshStatus(true);
      });
    });

    if (sel) {
      sel.addEventListener('change', function () {
        var ev = currentEvent();
        if (!ev) return;
        var before = snapshot();
        ev.ease = sel.value;
        pushUndo(before);
        syncEventPanel();
        refreshStatus(true);
      });
    }
  }

  /** 轨道列表 UI 已经去掉，这里只保证「当前编辑的轨道」不越界 */
  function clampSelectedLane() {
    var n = S.chart.lanes.length;
    if (!n) { S.selectedLane = 0; return; }
    S.selectedLane = RC.clamp(S.selectedLane, 0, n - 1);
  }

  function bindSidebar() {
    bindText('f-title', function (v) { S.chart.meta.title = v; });
    bindText('f-artist', function (v) { S.chart.meta.artist = v; });
    bindText('f-charter', function (v) { S.chart.meta.charter = v; });
    bindText('f-illustrator', function (v) { S.chart.meta.illustrator = v; });

    bindValue('f-difficulty', function (v) { S.chart.meta.difficulty = v; });
    bindValue('f-level', function (v) {
      S.chart.meta.level = RC.clamp(RC.int(v, 1), 1, 99);
      $('f-level').value = S.chart.meta.level;
    });

    bindValue('f-offset', function (v) {
      S.chart.audio.offset = RC.round3(RC.num(v, 0));
      $('f-offset').value = S.chart.audio.offset;
    });

    bindValue('f-bpm', function (v) {
      S.chart.timing.bpm = RC.clamp(RC.round3(RC.num(v, 150)), 20, 1000);
      $('f-bpm').value = S.chart.timing.bpm;
      setHint('BPM 只影响网格和吸附，不会挪动已有音符');
    });

    bindValue('f-beatoffset', function (v) {
      S.chart.timing.beat_offset = RC.round3(RC.num(v, 0));
      $('f-beatoffset').value = S.chart.timing.beat_offset;
    });

    bindValue('f-highway', function (v) {
      S.highwaySec = RC.clamp(RC.num(v, 2), 0.3, 20);
      $('f-highway').value = S.highwaySec;
    $('f-pvsec').value = S.pvSec;
    });

    bindValue('f-pvsec', function (v) {
      S.pvSec = RC.clamp(RC.num(v, 2), 0.3, 20);
      $('f-pvsec').value = S.pvSec;
    });

    bindValue('f-lanecount', applyLaneCount);

    // 轨道数输入框：按回车就提交（不用非得点到别处）
    var lcEl = $('f-lanecount');
    if (lcEl) {
      lcEl.addEventListener('keydown', function (e) {
        if (e.key === 'Enter') {
          e.preventDefault();
          lcEl.blur();
        }
      });
    }
    if ($('btn-lane-add')) {
      $('btn-lane-add').addEventListener('click', function () {
        applyLaneCount(S.chart.lanes.length + 1);
      });
    }
    if ($('btn-lane-del')) {
      $('btn-lane-del').addEventListener('click', function () {
        if (S.chart.lanes.length <= 1) { setHint('至少要留一条轨道'); return; }
        applyLaneCount(S.chart.lanes.length - 1);
      });
    }

    $('snap').addEventListener('change', function () {
      S.snapDiv = RC.clamp(RC.int(this.value, 4), 1, 64);
    });

    var chk = $('chk-hit');
    if (chk) {
      chk.checked = S.hitSound;
      chk.addEventListener('change', function () {
        S.hitSound = !!chk.checked;
      });
    }

    bindEventPanel();
    bindLaneScroll();
    bindVolume();
    bindPlayRate();

    $('btn-undo').addEventListener('click', undo);
    $('btn-redo').addEventListener('click', redo);
  }

  /* ---------- 鼠标交互 ---------- */

  function pointerPos(e) {
    var r = canvas.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  }

  canvas.addEventListener('contextmenu', function (e) { e.preventDefault(); });

  canvas.addEventListener('pointerdown', function (e) {
    computeLayout();
    var p = pointerPos(e);

    if (e.button === 0) {
      // 密度条：点哪跳哪
      if (inMinimap(p.x, p.y)) {
        if (S.playing) pause();
        S.drag = { mode: 'mini' };
        setPlayhead(snapT(minimapTime(p.y)));
        canvas.setPointerCapture(e.pointerId);
        refreshStatus(true);
        return;
      }

      if (p.x < L.gutter) {
        S.drag = { mode: 'scrub' };
        setPlayhead(yToTime(p.y));
        canvas.setPointerCapture(e.pointerId);
        return;
      }

      // 事件区底部的轨道切换按钮
      var lb = laneBtnAt(p.x, p.y);
      if (lb >= 0) {
        S.selectedLane = lb;
        ensureLaneVisible(lb);        // 左边跟着滚过去
        syncLaneScrollUI();
            selectEvOnly('x', 0);
        syncInputs();
        refreshStatus(true);
        return;
      }

      // 右半边：事件区（6 列参数）
      if (eventColAt(p.x) >= 0) {
        S.lastArea = 'event';
        // 按住 Shift 在事件区拖 = 框选事件
        if (e.shiftKey) {
          S.drag = { mode: 'evbox', x0: p.x, y0: p.y, x1: p.x, y1: p.y };
          canvas.setPointerCapture(e.pointerId);
          return;
        }

        var evHit = hitEvent(p.x, p.y);
        if (evHit) {
          if (e.ctrlKey || e.metaKey) {
            toggleEv(evHit.key, evHit.event.id);
            syncEventPanel();
            canvas.setPointerCapture(e.pointerId);
            refreshStatus(true);
            return;
          }
          if (!isEvSelected(evHit.key, evHit.event.id)) {
            selectEvOnly(evHit.key, evHit.event.id);
          } else {
            S.selectedEventKey = evHit.key;
            S.selectedEventId = evHit.event.id;
          }

          if (evHit.part === 'body') {
            var group = selectedEventList();
            if (!group.length) group = [{ key: evHit.key, ev: evHit.event }];
            S.drag = {
              mode: 'ev-move',
              before: snapshot(),
              ev: evHit.event,
              key: evHit.key,
              grab: evHit.event.start - snapT(yToTime(p.y)),
              baseStart: evHit.event.start,
              group: group.map(function (g) {
                return { key: g.key, ev: g.ev, start0: g.ev.start, dur0: g.ev.end - g.ev.start };
              })
            };
          } else {
            S.drag = {
              mode: (evHit.part === 'head') ? 'ev-head' : 'ev-tail',
              before: snapshot(),
              ev: evHit.event,
              key: evHit.key,
              startX: p.x,
              startFrom: evHit.event.from,
              startTo: evHit.event.to
            };
          }
          syncEventPanel();
        } else {
          var et0 = Math.max(0, snapT(yToTime(p.y)));
          S.drag = {
            mode: 'ev-draw',
            key: RC.ALL_KEYS[eventColAt(p.x)],
            t0: et0,
            t1: et0
          };
        }
        canvas.setPointerCapture(e.pointerId);
        refreshStatus(true);
        return;
      }

      // 判定线下面那条空白带（轨道名 / 滚动条）不参与放音符
      if (laneAt(p.x) >= 0 && p.y > L.judgeY + 2) return;

      if (laneAt(p.x) >= 0) S.lastArea = 'note';

      // 按住 Shift 在音符区拖 = 框选
      if (e.shiftKey && laneAt(p.x) >= 0) {
        S.drag = { mode: 'box', x0: p.x, y0: p.y, x1: p.x, y1: p.y };
        canvas.setPointerCapture(e.pointerId);
        return;
      }

      var hit = hitTest(p.x, p.y);

      if (hit) {
        if (!isSelected(hit.note)) selectOnly(hit.note.id);
        var group = (hit.part === 'tail') ? [hit.note] : selectedNotes();
        if (!group.length) group = [hit.note];
        S.drag = {
          mode: (hit.part === 'tail') ? 'tail' : 'move',
          before: snapshot(),
          note: hit.note,
          grab: (hit.part === 'tail') ? 0 : (hit.note.time - yToTime(p.y)),
          startTime: hit.note.time,
          startLane: hit.note.lane,
          orig: group.map(function (n) { return { n: n, time: n.time, lane: n.lane }; })
        };
        S.selectedId = hit.note.id;
      } else {
        var lane = laneAt(p.x);
        if (lane < 0) return;
        var t = Math.max(0, snapT(yToTime(p.y)));
        var exist = RC.findAt(S.chart, lane, t);
        if (exist) {
          selectOnly(exist.id);
          S.drag = {
            mode: 'move', before: snapshot(), note: exist, grab: exist.time - yToTime(p.y),
            startTime: exist.time, startLane: exist.lane,
            orig: [{ n: exist, time: exist.time, lane: exist.lane }]
          };
        } else {
          if (S.playing) pause();
          var before = snapshot();
          var note = RC.addNote(S.chart, { time: t, lane: lane, type: 'tap' });
          selectOnly(note.id);
          pushUndo(before);
          playHit();
          S.drag = {
            mode: 'move', before: null, note: note, grab: 0,
            startTime: note.time, startLane: note.lane,
            orig: [{ n: note, time: note.time, lane: note.lane }]
          };
        }
      }
      canvas.setPointerCapture(e.pointerId);
      refreshStatus(true);
      return;
    }

    if (e.button === 2) {
      if (p.x < L.gutter) return;

      // 事件区：右键删事件
      if (eventColAt(p.x) >= 0) {
        var evHit2 = hitEvent(p.x, p.y);
        if (evHit2) {
          var evLane = S.chart.lanes[S.selectedLane];
          var evKey = evHit2.key;
          var evId = evHit2.event.id;
          act(function () {
            RC.removeEvent(evLane, evKey, evId);
            S.selectedEvs = S.selectedEvs.filter(function (s) { return !(s.key === evKey && s.id === evId); });
            if (S.selectedEventId === evId) selectEvOnly('x', 0);
          });
          syncEventPanel();
        }
        return;
      }

      var hit2 = hitTest(p.x, p.y);
      if (hit2) {
        var id = hit2.note.id;
        act(function () {
          RC.removeNote(S.chart, id);
          S.selectedIds = S.selectedIds.filter(function (x) { return x !== id; });
          if (S.selectedId === id) S.selectedId = S.selectedIds.length ? S.selectedIds[0] : 0;
        });
        return;
      }
      var lane2 = laneAt(p.x);
      if (lane2 < 0) return;
      var t2 = Math.max(0, snapT(yToTime(p.y)));
      S.drag = { mode: 'draw-hold', lane: lane2, t0: t2, t1: t2, before: snapshot() };
      canvas.setPointerCapture(e.pointerId);
    }
  });

  canvas.addEventListener('pointermove', function (e) {
    computeLayout();
    var p = pointerPos(e);
    var d = S.drag;

    if (!d) {
      var h = hitTest(p.x, p.y);
      var he = hitEvent(p.x, p.y);
      var cursor = 'crosshair';
      if (h) cursor = (h.part === 'tail' ? 'ns-resize' : 'grab');
      else if (he) cursor = (he.part === 'body' ? 'grab' : 'ns-resize');
      else if (inMinimap(p.x, p.y)) cursor = 'pointer';
      else if (laneBtnAt(p.x, p.y) >= 0) cursor = 'pointer';
      else if (eventColAt(p.x) >= 0) cursor = 'copy';
      else if (p.x < L.gutter) cursor = 'ew-resize';
      canvas.style.cursor = cursor;
      return;
    }

    if (d.mode === 'mini') {
      setPlayhead(snapT(minimapTime(p.y)));
      refreshStatus(true);
      return;
    }

    if (d.mode === 'ev-draw') {
      d.t1 = Math.max(0, snapT(yToTime(p.y)));
      return;
    }

    if (d.mode === 'evbox') {
      d.x1 = p.x;
      d.y1 = p.y;
      return;
    }

    if (d.mode === 'ev-move') {
      var nt = Math.max(0, snapT(yToTime(p.y) + d.grab));
      var dt = nt - d.baseStart;
      if (Math.abs(dt) > 1e-9) {
        var group = d.group || [];
        for (var gi = 0; gi < group.length; gi++) {
          var g = group[gi];
          var ns = Math.max(0, RC.round3(g.start0 + dt));
          g.ev.start = ns;
          g.ev.end = RC.round3(ns + Math.max(0.01, g.dur0));
        }
        RC.sortEvents(RC.laneEvents(S.chart.lanes[S.selectedLane], d.key));
        markDirty();
        syncEventPanel();
      }
      return;
    }

    if (d.mode === 'ev-head') {
      var hs = RC.clamp(snapT(yToTime(p.y)), 0, d.ev.end - 0.02);
      var nf = RC.clampLaneNum(d.key, d.startFrom + (p.x - d.startX) * evValuePerPixel(d.key));
      var changed = false;
      if (RC.round3(hs) !== d.ev.start) { d.ev.start = RC.round3(hs); changed = true; }
      if (nf !== d.ev.from) { d.ev.from = nf; changed = true; }
      if (changed) {
        markDirty();
        syncEventPanel();
      }
      return;
    }

    if (d.mode === 'ev-tail') {
      var te = Math.max(d.ev.start + 0.02, snapT(yToTime(p.y)));
      var nt = RC.clampLaneNum(d.key, d.startTo + (p.x - d.startX) * evValuePerPixel(d.key));
      var changed2 = false;
      if (RC.round3(te) !== d.ev.end) { d.ev.end = RC.round3(te); changed2 = true; }
      if (nt !== d.ev.to) { d.ev.to = nt; changed2 = true; }
      if (changed2) {
        markDirty();
        syncEventPanel();
      }
      return;
    }

    if (d.mode === 'box' || d.mode === 'evbox') {
      d.x1 = p.x;
      d.y1 = p.y;
      return;
    }

    if (d.mode === 'scrub') {
      setPlayhead(yToTime(p.y));
      if (S.playing) { syncAudioToPlayhead(); }
      return;
    }

    if (d.mode === 'move') {
      var t = snapT(yToTime(p.y) + d.grab);
      var lane = laneAt(p.x);
      if (lane < 0) lane = d.note.lane;
      t = Math.max(0, t);
      var dt = t - d.startTime;
      var dl = lane - d.startLane;

      if (dt !== 0 || dl !== 0) {
        var orig = d.orig || [];
        for (var gi = 0; gi < orig.length; gi++) {
          var o = orig[gi];
          o.n.time = Math.max(0, RC.round3(o.time + dt));
          o.n.lane = RC.clamp(o.lane + dl, 0, S.chart.lanes.length - 1);
        }
        RC.sortNotes(S.chart);
        markDirty();
      }
      return;
    }

    if (d.mode === 'tail') {
      var endT = snapT(yToTime(p.y));
      var dur = Math.max(MIN_HOLD, endT - d.note.time);
      if (dur !== d.note.duration) {
        d.note.duration = RC.round3(dur);
        markDirty();
      }
      return;
    }

    if (d.mode === 'draw-hold') {
      d.t1 = Math.max(0, snapT(yToTime(p.y)));
      return;
    }
  });

  function endDrag(e) {
    var d = S.drag;
    if (!d) return;
    S.drag = null;

    if (d.mode === 'draw-hold') {
      var t0 = Math.min(d.t0, d.t1);
      var t1 = Math.max(d.t0, d.t1);
      var dur = t1 - t0;
      if (dur >= MIN_HOLD) {
        var lane = d.lane;
        act(function () {
          var n = RC.addNote(S.chart, { time: t0, lane: lane, type: 'hold', duration: dur });
          selectOnly(n.id);
        });
      }
    } else if (d.mode === 'ev-draw') {
      var es = Math.min(d.t0, d.t1);
      var ee = Math.max(d.t0, d.t1);
      if (ee - es >= 0.04) {
        var evLane = S.chart.lanes[S.selectedLane];
        var key = d.key;
        var cur = RC.laneParamsAt(evLane, es)[key];
        act(function () {
          var ev = RC.addEvent(evLane, key, {
            start: es, end: ee, ease: 'linear',
            from: cur, to: cur
          });
          selectEvOnly(key, ev.id);
          syncEventPanel();
          setHint('画好一个事件了：把「尾」的值改掉它就会动起来');
        });
      }
    } else if (d.mode === 'box') {
      applyBoxSelect(d);
    } else if (d.mode === 'evbox') {
      applyEvBoxSelect(d);
    } else if (d.before) {
      pushUndo(d.before);
      if (d.mode.indexOf('ev-') === 0) syncEventPanel();
    }

    if (e && e.pointerId !== undefined) {
      try { canvas.releasePointerCapture(e.pointerId); } catch (err) { /* 忽略 */ }
    }
    refreshStatus(true);
  }

  canvas.addEventListener('pointerup', endDrag);
  canvas.addEventListener('pointercancel', endDrag);

  canvas.addEventListener('dblclick', function (e) {
    computeLayout();
    var p = pointerPos(e);
    var hit = hitTest(p.x, p.y);
    if (!hit) return;
    var n = hit.note;
    act(function () {
      var order = ['tap', 'hold'];
      var i = order.indexOf(n.type);
      n.type = order[(i + 1) % order.length];
      if (n.type === 'hold') {
        n.duration = Math.max(MIN_HOLD, RC.round3(RC.secPerBeat(S.chart.timing) / 2));
      } else {
        n.duration = 0;
      }
    });
  });

  canvas.addEventListener('wheel', function (e) {
    e.preventDefault();
    computeLayout();

    if (e.ctrlKey) {
      var k = e.deltaY > 0 ? 1.12 : 1 / 1.12;
      S.highwaySec = RC.clamp(S.highwaySec * k, 0.3, 20);
      $('f-highway').value = Math.round(S.highwaySec * 100) / 100;
      return;
    }

    // 滚轮向下 = 往回走（画面上的音符向上走，跟网页滚动同一手感）
    var beats = e.shiftKey ? 4 : 1;
    var dir = e.deltaY > 0 ? -1 : 1;
    var step = RC.secPerBeat(S.chart.timing) * beats;
    setPlayhead(snapT(S.viewTime + step * dir));
    if (S.playing) { pause(); }
    refreshStatus(true);
  }, { passive: false });

  /* ---------- 键盘 ---------- */

  window.addEventListener('keydown', function (e) {
    var tag = (e.target && e.target.tagName) || '';
    if (tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA') return;

    var mod = e.ctrlKey || e.metaKey;

    if (mod && e.key.toLowerCase() === 'z') {
      e.preventDefault();
      if (e.shiftKey) redo(); else undo();
      return;
    }
    if (mod && e.key.toLowerCase() === 'y') {
      e.preventDefault();
      redo();
      return;
    }
    if (mod && e.key.toLowerCase() === 's') {
      e.preventDefault();
      saveChart();
      return;
    }
    if (mod && e.key.toLowerCase() === 'o') {
      e.preventDefault();
      flushInputs();
      $('file-chart').click();
      return;
    }
    if (e.code === 'Space') {
      e.preventDefault();
      togglePlay();
      return;
    }
    if (e.key === 'Escape') {
      selectOnly(0);
      selectEvOnly('x', 0);
      syncEventPanel();
      refreshStatus(true);
      return;
    }
    if (e.key === 'Home') {
      setPlayhead(0);
      return;
    }
    if (e.key === 'End') {
      setPlayhead(RC.chartDuration(S.chart));
      return;
    }
    if (e.key === 'Delete' || e.key === 'Backspace') {
      e.preventDefault();

      // 事件优先：选中的事件批量删
      var evs = selectedEventList();
      if (evs.length) {
        var lane = currentLane();
        act(function () {
          for (var i = 0; i < evs.length; i++) {
            RC.removeEvent(lane, evs[i].key, evs[i].ev.id);
          }
          selectEvOnly('x', 0);
        });
        syncEventPanel();
        setHint('删掉了 ' + evs.length + ' 个事件');
        return;
      }

      var ids = S.selectedIds.slice();
      if (!ids.length) return;
      act(function () {
        for (var i = 0; i < ids.length; i++) RC.removeNote(S.chart, ids[i]);
        selectOnly(0);
      });
      return;
    }
    if (mod && e.key.toLowerCase() === 'c') {
      e.preventDefault();
      doCopy();
      return;
    }
    if (mod && e.key.toLowerCase() === 'v') {
      e.preventDefault();
      doPaste();
      return;
    }
    if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
      e.preventDefault();
      var notes = selectedNotes();
      if (!notes.length) return;
      var dir = e.key === 'ArrowRight' ? 1 : -1;
      act(function () {
        for (var i = 0; i < notes.length; i++) {
          notes[i].lane = RC.clamp(notes[i].lane + dir, 0, S.chart.lanes.length - 1);
        }
      });
      return;
    }
    if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
      e.preventDefault();
      var dir2 = e.key === 'ArrowDown' ? 1 : -1;
      var stepT = RC.secPerBeat(S.chart.timing) / S.snapDiv;
      setPlayhead(RC.clamp(snapT(S.viewTime + stepT * dir2), 0, 1e9));
      if (S.playing) pause();
      refreshStatus(true);
    }
  });

  /* ---------- 打击音 ---------- */

  var HIT_SRC = 'audio/hit.wav';
  var HIT_POOL_SIZE = 8;
  var hitPool = [];
  var hitIdx = 0;

  function initHitSound() {
    for (var i = 0; i < HIT_POOL_SIZE; i++) {
      var a = new Audio(HIT_SRC);
      a.preload = 'auto';
      a.volume = hitGain();
      hitPool.push(a);
    }
  }

  /** 响一声（轮着用池子里的实例，连打不会互相掐断） */
  function playHit() {
    if (!S.hitSound || !hitPool.length) return;
    var a = hitPool[hitIdx % hitPool.length];
    hitIdx++;
    try {
      a.volume = hitGain();
      a.currentTime = 0;
      var pr = a.play();
      if (pr && pr.catch) pr.catch(function () { });
    } catch (err) { /* 还没解码完就算了 */ }
  }

  /** 第一个 time > t 的音符下标（notes 已按时间排好） */
  function firstNoteAfter(t) {
    var notes = S.chart.notes;
    var lo = 0;
    var hi = notes.length;
    while (lo < hi) {
      var mid = (lo + hi) >> 1;
      if (notes[mid].time <= t) lo = mid + 1;
      else hi = mid;
    }
    return lo;
  }

  /** 播放时把 (prev, now] 区间里过线的音符一个个响出来 */
  function fireHits(prev, now) {
    if (!S.hitSound || now <= prev || now - prev > 0.5) return;
    var notes = S.chart.notes;
    var i = firstNoteAfter(prev);
    var count = 0;
    while (i < notes.length && notes[i].time <= now) {
      playHit();
      i++;
      if (++count >= 8) break;
    }
  }

  /* ---------- 音频与播放 ---------- */

  /** dB → 0~1 的增益 */
  function dbToGain(db) {
    return RC.clamp(Math.pow(10, RC.num(db, 0) / 20), 0, 1);
  }

  /** 0~100 的音量百分比 → dB（100% = 0dB，50% ≈ -6dB） */
  function pctToDb(pct) {
    var v = RC.clamp(RC.num(pct, 100), 0, 100) / 100;
    return v <= 0 ? -60 : RC.round3(20 * Math.log(v) / Math.LN10);
  }

  /** dB → 0~100 的百分比 */
  function dbToPct(db) {
    return RC.clamp(Math.round(dbToGain(db) * 100), 0, 100);
  }

  function audioGain() {
    return dbToGain(S.chart.audio.volume_db);
  }

  /* ---------- 播放倍速（慢放方便制谱） ---------- */

  /** 把当前倍速套到音频上；保调（preservesPitch），慢放时旋律还是原来的音高 */
  function applyPlayRate() {
    if (!S.audio) return;
    try {
      S.audio.playbackRate = S.playRate;
      S.audio.preservesPitch = true;
      if ('mozPreservesPitch' in S.audio) S.audio.mozPreservesPitch = true;
      if ('webkitPreservesPitch' in S.audio) S.audio.webkitPreservesPitch = true;
    } catch (err) { /* 有的浏览器不让改，忽略 */ }
  }

  function setPlayRate(v) {
    S.playRate = RC.clamp(RC.num(v, 1), 0.25, 1);
    applyPlayRate();
    var sel = $('f-rate');
    if (sel) sel.value = String(S.playRate);
    setHint(S.playRate < 1
      ? '播放倍速 ' + S.playRate + '×（只影响预览，不影响导出的谱面）'
      : '播放倍速恢复正常');
  }

  function hitGain() {
    return dbToGain(S.chart.audio.hit_volume_db);
  }

  /* ---------- 音量滑条 ---------- */

  function syncVolumeUI() {
    var m = $('vol-music');
    var h = $('vol-hit');
    var mt = $('vol-music-txt');
    var ht = $('vol-hit-txt');
    var mp = dbToPct(S.chart.audio.volume_db);
    var hp = dbToPct(S.chart.audio.hit_volume_db);
    if (m) m.value = String(mp);
    if (h) h.value = String(hp);
    if (mt) mt.textContent = mp + '%';
    if (ht) ht.textContent = hp + '%';
  }

  function setMusicVolume(pct) {
    S.chart.audio.volume_db = pctToDb(pct);
    syncVolumeUI();
    if (S.audio) S.audio.volume = audioGain();      // 立刻生效
    markDirty();
  }

  function setHitVolume(pct) {
    S.chart.audio.hit_volume_db = pctToDb(pct);
    syncVolumeUI();
    for (var i = 0; i < hitPool.length; i++) hitPool[i].volume = hitGain();
    markDirty();
  }

  function bindVolume() {
    var m = $('vol-music');
    var h = $('vol-hit');
    if (m) {
      m.addEventListener('input', function () { setMusicVolume(m.value); });
      m.addEventListener('change', function () { setMusicVolume(m.value); });
    }
    if (h) {
      h.addEventListener('input', function () { setHitVolume(h.value); });
      h.addEventListener('change', function () { setHitVolume(h.value); });
    }
  }

  /** 改轨道数（输入框和 ＋/－ 按钮共用） */
  function applyLaneCount(v) {
    var before = snapshot();
    var res = RC.setLaneCount(S.chart, v);
    $('f-lanecount').value = res.laneCount;
    clampSelectedLane();
    syncLaneScrollUI();
    pushUndo(before);
    markDirty();
    refreshStatus(true);
    if (S.chart.notes.length && res.moved) {
      setHint('轨道数改成 ' + res.laneCount + '，有 ' + res.moved + ' 个音符被挪到最后一轨');
    } else {
      setHint('轨道数：' + res.laneCount);
    }
  }

  /** 父线下拉（针对当前选中的轨道） */
  function bindPlayRate() {
    var sel = $('f-rate');
    if (!sel) return;
    sel.value = String(S.playRate);
    sel.addEventListener('change', function () { setPlayRate(sel.value); });
  }

  function chartTimeFromAudio() {
    return S.audio.currentTime - RC.num(S.chart.audio.offset, 0);
  }

  function syncAudioToPlayhead() {
    if (!S.audio) return;
    var at = S.viewTime + RC.num(S.chart.audio.offset, 0);
    try {
      S.audio.currentTime = Math.max(0, at);
    } catch (err) { /* 音频还没准备好 */ }
  }

  function play() {
    if (S.playing) return;
    S.playing = true;
    S.playWall = performance.now();
    S.playBase = S.viewTime;
    if (S.audio) {
      S.audio.volume = audioGain();
      applyPlayRate();
      syncAudioToPlayhead();
      var pr = S.audio.play();
      if (pr && pr.catch) pr.catch(function () { /* 浏览器拦了自动播放，不影响空放 */ });
    }
    $('btn-play').textContent = '❚❚ 暂停';
  }

  function pause() {
    if (!S.playing) return;
    S.playing = false;
    if (S.audio) S.audio.pause();
    $('btn-play').textContent = '▶ 播放';
  }

  function togglePlay() {
    flushInputs();
    if (S.playing) pause(); else play();
  }

  /* ---------- 音符的复制 / 粘贴 ---------- */

  function copyNotes() {
    var list = selectedNotes();
    if (!list.length) {
      setHint('先选中音符再复制');
      return;
    }
    var minT = Infinity;
    var i;
    for (i = 0; i < list.length; i++) {
      if (list[i].time < minT) minT = list[i].time;
    }
    S.noteClip = list.map(function (n) {
      return {
        rel: RC.round3(n.time - minT),
        lane: n.lane,
        type: n.type,
        duration: n.duration
      };
    });
    setHint('复制了 ' + S.noteClip.length + ' 个音符（Ctrl+V 贴到播放头）');
  }

  function pasteNotes() {
    if (!S.noteClip || !S.noteClip.length) {
      setHint('剪贴板里还没有音符');
      return;
    }
    var base = snapT(S.viewTime);
    var src = S.noteClip;
    var made = [];

    act(function () {
      for (var i = 0; i < src.length; i++) {
        var it = src[i];
        var n = RC.addNote(S.chart, {
          time: Math.max(0, RC.round3(base + it.rel)),
          lane: it.lane,
          type: it.type,
          duration: it.type === 'hold' ? it.duration : 0
        });
        made.push(n.id);
      }
    });

    if (made.length) {
      S.selectedIds = made;
      S.selectedId = made[0];
      setHint('把 ' + made.length + ' 个音符贴到了 ' + RC.formTime(base));
    }
  }

  /** Ctrl+C / Ctrl+V：按最后操作的那一半决定复制音符还是事件 */
  function doCopy() {
    if (S.lastArea === 'event' && selectedEventList().length) return copyEvents();
    if (S.lastArea === 'note' && S.selectedIds.length) return copyNotes();
    if (S.selectedIds.length) return copyNotes();
    if (selectedEventList().length) return copyEvents();
    setHint('先选中音符或事件再复制');
  }

  function doPaste() {
    if (S.lastArea === 'event') {
      if (S.eventClip) return pasteEvents();
      if (S.noteClip) return pasteNotes();
    } else {
      if (S.noteClip) return pasteNotes();
      if (S.eventClip) return pasteEvents();
    }
    setHint('剪贴板是空的');
  }

  /* ---------- 曲绘 ---------- */

  function mimeOf(name) {
    var ext = String(name).split('.').pop().toLowerCase();
    var table = {
      mp3: 'audio/mpeg', ogg: 'audio/ogg', wav: 'audio/wav',
      png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg',
      webp: 'image/webp', gif: 'image/gif'
    };
    return table[ext] || 'application/octet-stream';
  }

  /** 把一个「名字 + 字节」包成能读 arrayBuffer 的东西，方便再导出 */
  function virtualFile(name, bytes) {
    return {
      name: name,
      arrayBuffer: function () { return Promise.resolve(bytes.slice().buffer); }
    };
  }

  function showCover(name, url) {
    var img = $('cover-img');
    if (img) {
      if (url) {
        img.src = url;
        img.hidden = false;
      } else {
        img.src = '';
        img.hidden = true;
      }
    }
    var nm = $('cover-name');
    if (nm) nm.textContent = name || '未选择曲绘';
  }

  function setCover(file) {
    S.coverFile = file || null;

    if (S.coverUrl) {
      URL.revokeObjectURL(S.coverUrl);
      S.coverUrl = '';
    }

    if (file) {
      S.coverUrl = URL.createObjectURL(file);
      S.chart.meta.cover = file.name;
      showCover(file.name, S.coverUrl);
    } else {
      S.chart.meta.cover = '';
      showCover('', '');
    }

    markDirty();
  }

  /** 从 zip 里捡出来的曲绘 */
  function setCoverBytes(name, bytes) {
    S.coverFile = virtualFile(name, bytes);
    if (S.coverUrl) URL.revokeObjectURL(S.coverUrl);
    S.coverUrl = URL.createObjectURL(new Blob([bytes], { type: mimeOf(name) }));
    S.chart.meta.cover = name;
    showCover(name, S.coverUrl);
  }

  /* ---------- 文件 ---------- */

  function newChart() {
    if (S.dirty && !window.confirm('当前谱面还没保存，确定新建？')) return;
    pause();
    setChart(RC.createChart({ lane_count: S.chart.lanes.length }), '');
    setHint('新建了一份空谱面');
  }

  function setChart(chart, name) {
    pause();
    if (S.audio) {
      S.audio.pause();
      if (S.audio.src) URL.revokeObjectURL(S.audio.src);
    }
    S.audio = null;
    S.audioFile = null;
    S.audioName = '';
    $('audio-name').textContent = '未载入音频';
    if (S.coverUrl) URL.revokeObjectURL(S.coverUrl);
    S.coverUrl = '';
    S.coverFile = null;
    showCover('', '');
    dropDupCache();
    if (!name || !/\.zip$/i.test(name)) { S.extraFiles = []; S.storyboardName = ''; }
    S.chart = chart;
    selectOnly(0);
    selectEvOnly('x', 0);
    S.viewTime = 0;
    S.undo.length = 0;
    S.redo.length = 0;
    S.highwaySec = RC.clamp(RC.num(chart.stage.highway_length, 2), 0.3, 20);
    S.fileName = name || '';
    S.dirty = false;
    syncInputs();
    refreshStatus(true);
  }

  function fileEntry(file, name) {
    return file.arrayBuffer().then(function (buf) {
      return { name: name, data: new Uint8Array(buf) };
    });
  }

  /** 导出 zip：chart.json + 音频 + 曲绘 */
  function saveChart() {
    flushInputs();

    var base = (S.chart.meta.title || 'chart').replace(/[\\/:*?"<>|]/g, '_') || 'chart';
    var jsonText = JSON.stringify(RC.serialize(S.chart), null, '\t');
    var fixed = [{ name: 'chart.json', data: new TextEncoder().encode(jsonText) }];

    var jobs = [];
    if (S.audioFile) jobs.push(fileEntry(S.audioFile, S.chart.audio.file || S.audioFile.name));
    if (S.coverFile) jobs.push(fileEntry(S.coverFile, S.coverFile.name));

    function finish(extra) {
      var all = fixed.concat(extra);

      // 打开时带进来的其它文件（storyboard.json / assets/…）原样放回去，
      // 别让「打开 zip 再导出」把故事板和 Shader 弄丢
      var used = {};
      var i;
      for (i = 0; i < all.length; i++) used[all[i].name] = 1;
      for (i = 0; i < S.extraFiles.length; i++) {
        var ef = S.extraFiles[i];
        if (used[ef.name]) continue;
        used[ef.name] = 1;
        all.push({ name: ef.name, data: ef.data });
      }

      var bytes = RC.zipStore(all);
      var blob = new Blob([bytes], { type: 'application/zip' });
      var url = URL.createObjectURL(blob);
      var a = document.createElement('a');
      a.href = url;
      a.download = base + '.zip';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(function () { URL.revokeObjectURL(url); }, 4000);

      S.dirty = false;
      if (!S.fileName) S.fileName = a.download;
      updateTitle();
      setHint('已导出 ' + a.download + '（' +
        all.map(function (f) { return f.name; }).join(' + ') + '）');
    }

    if (!jobs.length) {
      finish([]);
      return;
    }
    Promise.all(jobs).then(finish).catch(function (err) {
      setHint('打包失败：' + (err && err.message ? err.message : err));
    });
  }

  function loadText(text, name) {
    var raw;
    try {
      raw = JSON.parse(text);
    } catch (err) {
      window.alert('这个文件不是合法 JSON：\n' + err.message);
      return false;
    }
    var res = RC.normalize(raw);
    if (!res.chart) {
      window.alert('打不开：' + res.warnings.join('；'));
      return false;
    }
    pause();
    setChart(res.chart, name);
    if (res.warnings.length) {
      window.alert('已读入，但有这些情况：\n\n· ' + res.warnings.join('\n· '));
    } else {
      setHint('已读入 ' + name);
    }
    return true;
  }

  /** 在 zip 的条目里挑一个：先按文件名，再按扩展名 */
  function pickEntry(files, wanted, extRe) {
    var keys = Object.keys(files);
    var i;
    if (wanted) {
      for (i = 0; i < keys.length; i++) {
        if (keys[i] === wanted) return keys[i];
      }
      for (i = 0; i < keys.length; i++) {
        var base = keys[i].split('/').pop();
        if (base === wanted) return keys[i];
      }
    }
    for (i = 0; i < keys.length; i++) {
      if (extRe.test(keys[i])) return keys[i];
    }
    return '';
  }

  /** 打开编辑器自己导出的 zip（chart.json + 音频 + 曲绘） */
  function openZipBytes(bytes, zipName) {
    return RC.zipRead(bytes).then(function (files) {
      var jsonName = pickEntry(files, 'chart.json', /\.json$/i);
      if (!jsonName) throw new Error('zip 里没有 .json 谱面');

      if (!loadText(new TextDecoder().decode(files[jsonName]), zipName)) return;

      // 音频
      var audioName = pickEntry(files, S.chart.audio.file, /\.(mp3|ogg|wav)$/i);
      if (audioName) {
        var audioBytes = files[audioName];
        pause();
        if (S.audio) {
          try { S.audio.pause(); } catch (err) { /* 忽略 */ }
          if (S.audio.src) URL.revokeObjectURL(S.audio.src);
        }
        S.audio = new Audio(URL.createObjectURL(new Blob([audioBytes], { type: mimeOf(audioName) })));
        S.audio.volume = audioGain();
        applyPlayRate();
        S.audioName = audioName;
        S.audioFile = virtualFile(audioName, audioBytes);
        S.chart.audio.file = audioName;
        $('audio-name').textContent = audioName;
      }

      // 曲绘
      var coverName = pickEntry(files, S.chart.meta.cover, /\.(png|jpe?g|webp|gif)$/i);
      if (coverName) setCoverBytes(coverName, files[coverName]);

      // 其余东西原样留着（storyboard.json、assets/ 里的视频图片…），导出时带回去
      S.extraFiles = [];
      var keep = {};
      keep[jsonName] = 1;
      if (audioName) keep[audioName] = 1;
      if (coverName) keep[coverName] = 1;
      for (var nm in files) {
        if (!Object.prototype.hasOwnProperty.call(files, nm)) continue;
        if (keep[nm]) continue;
        S.extraFiles.push({ name: nm, data: files[nm] });
      }
      var sbEntry = pickEntry(files, 'storyboard.json', /(?!)/);
      S.storyboardName = sbEntry || '';

      S.dirty = false;
      updateTitle();
      setHint('已打开 ' + zipName + '（' +
        [jsonName, audioName, coverName, sbEntry ? '故事板' : ''].filter(Boolean).join(' + ') + '）');
    });
  }

  function bindFiles() {
    $('btn-new').addEventListener('click', newChart);
    $('btn-save').addEventListener('click', saveChart);
    $('btn-open').addEventListener('click', function () {
      flushInputs();
      $('file-chart').click();
    });

    $('file-chart').addEventListener('change', function (e) {
      var f = e.target.files && e.target.files[0];
      if (!f) return;
      e.target.value = '';

      f.arrayBuffer().then(function (buf) {
        var bytes = new Uint8Array(buf);
        // 看魔数判断是不是 zip（PK\x03\x04）
        if (bytes.length > 4 && bytes[0] === 0x50 && bytes[1] === 0x4b &&
            bytes[2] === 0x03 && bytes[3] === 0x04) {
          return openZipBytes(bytes, f.name);
        }
        loadText(new TextDecoder().decode(bytes), f.name);
      }).catch(function (err) {
        window.alert('打不开这个文件：' + (err && err.message ? err.message : err));
      });
    });

    $('btn-audio').addEventListener('click', function () { $('file-audio').click(); });

    $('file-audio').addEventListener('change', function (e) {
      var f = e.target.files && e.target.files[0];
      if (!f) return;
      pause();
      if (S.audio) {
        try { S.audio.pause(); } catch (err) { /* 忽略 */ }
        if (S.audio.src) URL.revokeObjectURL(S.audio.src);
      }
      S.audio = new Audio(URL.createObjectURL(f));
      S.audio.volume = audioGain();
      applyPlayRate();
      S.audioName = f.name;
      S.audioFile = f;
      S.chart.audio.file = f.name;
      $('audio-name').textContent = f.name;
      markDirty();
      setHint('音频已载入：' + f.name + '（导出时会一起打进 zip）');
      e.target.value = '';
    });

    $('btn-cover').addEventListener('click', function () { $('file-cover').click(); });

    $('file-cover').addEventListener('change', function (e) {
      var f = e.target.files && e.target.files[0];
      if (!f) return;
      setCover(f);
      setHint('曲绘已选择：' + f.name + '（导出时会一起打进 zip）');
      e.target.value = '';
    });

    $('btn-play').addEventListener('click', togglePlay);
    if ($('btn-dup')) $('btn-dup').addEventListener('click', nextDupGroup);
    if ($('btn-issue')) $('btn-issue').addEventListener('click', nextIssue);
    $('btn-validate').addEventListener('click', function () {
      var issues = RC.validate(S.chart);
      if (!issues.length) {
        setHint('✓ 校验通过，没发现问题');
      } else {
        setHint('⚠ ' + issues.map(function (i) { return i.text; }).join(' · '));
      }
    });

    window.addEventListener('beforeunload', function (e) {
      if (!S.dirty) return;
      e.preventDefault();
      e.returnValue = '';
    });
  }

  /* ---------- 主循环 ---------- */

  function loop() {
    computeLayout();

    if (S.playing) {
      var prev = S.viewTime;
      if (S.audio && S.audio.readyState >= 1) {
        S.viewTime = chartTimeFromAudio();
      } else {
        S.viewTime = S.playBase + (performance.now() - S.playWall) / 1000 * S.playRate;
      }
      if (S.viewTime < 0) S.viewTime = 0;
      fireHits(prev, S.viewTime);
      if (S.audio && S.audio.duration && S.audio.currentTime >= S.audio.duration - 0.01) {
        pause();
      }
    }

    draw();
    drawPreview();
    var nowMs2 = performance.now();
    if (nowMs2 - easeLastDraw > 90) {
      easeLastDraw = nowMs2;
      drawEaseCurve();
    }
    refreshStatus(false);
    requestAnimationFrame(loop);
  }

  /* ---------- 启动 ---------- */

  function boot() {
    initHitSound();
    bindSidebar();
    bindFiles();
    syncInputs();
    refreshStatus(true);
    $('st-hint').textContent = HINT;
    requestAnimationFrame(loop);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
