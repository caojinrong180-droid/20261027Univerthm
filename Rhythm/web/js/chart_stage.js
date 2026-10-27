/* =============================================================================
 * chart_stage.js —— 谱面舞台渲染（1:1 对齐 Godot 游戏的 stage_view.gd）
 *
 * 逻辑舞台固定 **350 × 196.875（16:9）**，也就是游戏里的 STAGE_W / STAGE_H：
 *   judgeY      = round(196.875 * 0.85) = 167
 *   laneWidth   = min(350*0.05, 350*0.43/N) * PV_SCALE(1.75)
 *   halfW       = max(2, laneWidth/2 - 0.5)
 *   noteHalfW   = max(2, halfW - 1)
 *   音符半厚 NOTE_TH = 2.0，圆角 NOTE_RADIUS = 2.4
 *   判定线 = 底部一条 halfW*2 宽、halfW*0.36 厚的圆角实心条
 *
 * 谱面里的 x / y 像素值就是按这套逻辑尺寸定的；如果谱面是照别的画幅调的，
 * 调用方传 xyScale = 350 / 基准宽度 把它缩进来即可。
 *
 * 逐函数对照 stage_view.gd：
 *   _draw()            → draw()
 *   _lane_geom()       → laneGeom()
 *   _band_quad()       → bandQuad()（判定线/长条都用 _lane_shape 的圆角版本）
 *   _draw_lane_body()  → drawLaneBody()
 *   _draw_notes()      → drawNotes()
 *   _draw_lane_judge() → drawLaneJudge()
 *   _draw_chord_glow() → drawChordGlow()
 *   _rounded_rect()    → roundedRect()
 *   _lane_shape()      → laneShape()
 *
 * 不含：判定环/屏震/HUD（游戏里是「玩法反馈」，故事板用不到）。
 * ========================================================================== */
(function (global) {
  'use strict';

  var RC = global.RChart;

  var STAGE_W = 350;
  var STAGE_H = 350 * 9 / 16;      // 196.875
  var PV_SCALE = 1.75;
  var NOTE_TH = 2.0;
  var NOTE_RADIUS = 2.4;
  var JUDGE_LINE_RATIO = 0.36;
  var CHORD_EPS = 0.02;
  var CHORD_GLOW = '#57c8ff';
  var BG_DEEP = '#080a0e';

  function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }
  function num(v, d) {
    var n = typeof v === 'number' ? v : parseFloat(v);
    return isFinite(n) ? n : d;
  }

  /** '#rrggbb' + alpha → 'rgba(...)' */
  function rgba(hex, a) {
    var s = String(hex || '#ffffff').replace('#', '');
    if (s.length === 3) s = s[0] + s[0] + s[1] + s[1] + s[2] + s[2];
    var r = parseInt(s.slice(0, 2), 16) || 0;
    var g = parseInt(s.slice(2, 4), 16) || 0;
    var b = parseInt(s.slice(4, 6), 16) || 0;
    return 'rgba(' + r + ',' + g + ',' + b + ',' + clamp(a, 0, 1).toFixed(3) + ')';
  }

  function judgeY() { return Math.round(STAGE_H * 0.85); }
  function laneWidthOf(laneCount) {
    return Math.min(STAGE_W * 0.05, (STAGE_W * 0.43) / Math.max(1, laneCount)) * PV_SCALE;
  }
  function halfWidthOf(laneCount) { return Math.max(2, laneWidthOf(laneCount) / 2 - 0.5); }

  /* ------------------------------------------------------------------ 几何 */

  /** 本地圆角矩形（中心原点，x 横 / y 竖）→ 顺时针点列；和 stage_view._rounded_rect 一致 */
  function roundedRect(w, h, r, segs) {
    segs = segs || 8;
    var hw = w * 0.5, hh = h * 0.5;
    var rr = clamp(r, 0, Math.min(hw, hh));
    if (rr <= 0.01) {
      return [{ x: -hw, y: -hh }, { x: hw, y: -hh }, { x: hw, y: hh }, { x: -hw, y: hh }];
    }
    var pts = [];
    var corners = [
      { c: { x: hw - rr, y: -hh + rr }, a: -Math.PI * 0.5 },   // 右上
      { c: { x: hw - rr, y: hh - rr }, a: 0 },                 // 右下
      { c: { x: -hw + rr, y: hh - rr }, a: Math.PI * 0.5 },    // 左下
      { c: { x: -hw + rr, y: -hh + rr }, a: Math.PI }          // 左上
    ];
    for (var k = 0; k < corners.length; k++) {
      var cc = corners[k].c, start = corners[k].a;
      for (var i = 0; i <= segs; i++) {
        var ang = start + (Math.PI * 0.5) * (i / segs);
        pts.push({ x: cc.x + Math.cos(ang) * rr, y: cc.y + Math.sin(ang) * rr });
      }
    }
    return pts;
  }

  /** 一条轨道在 t 时刻的几何（同 stage_view._lane_geom） */
  function laneGeom(lane, index, t, halfW, xyScale) {
    var p = RC.laneParamsAt(lane, t);
    var rad = num(p.rotation, 0) * Math.PI / 180;
    var xy = xyScale === undefined ? 1 : xyScale;
    return {
      lane: lane,
      index: index,
      alpha: clamp(num(p.alpha, 0) / 100, 0, 1),
      speed: RC.laneSpeed(p),
      half: halfW,
      len: judgeY() * RC.laneLength(p),
      cx: STAGE_W * 0.5 + num(p.x, 0) * xy,
      cy: judgeY() - num(p.y, 0) * xy,
      dx: Math.sin(rad),
      dy: -Math.cos(rad),
      sx: Math.cos(rad),
      sy: Math.sin(rad),
      color: RC.displayColorAt(lane, t),
      zone: RC.laneZoneAt ? RC.laneZoneAt(lane, t) : ''
    };
  }

  function lanePoint(info, d) {
    return { x: info.cx + info.dx * d, y: info.cy + info.dy * d };
  }

  /** 本地坐标 (x 沿轨道横向, y 沿轨道方向) → 舞台坐标 */
  function laneLocalPoint(info, d, x, y) {
    var c = lanePoint(info, d);
    return { x: c.x + info.sx * x + info.dx * y, y: c.y + info.sy * x + info.dy * y };
  }

  /** 把本地圆角矩形贴到轨道坐标系：中心在「距判定线 d」处 */
  function laneShape(info, d, w, h, r) {
    var local = roundedRect(w, h, r);
    var out = [];
    for (var i = 0; i < local.length; i++) {
      out.push(laneLocalPoint(info, d, local[i].x, local[i].y));
    }
    return out;
  }

  function pathPoly(ctx, pts) {
    if (!pts.length) return;
    ctx.beginPath();
    ctx.moveTo(pts[0].x, pts[0].y);
    for (var i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y);
    ctx.closePath();
  }

  /** 长条身体：靠尾一端圆角 + 渐变透明，靠头一端默认直角（rHead>0 时也带圆角帽） */
  function drawHoldBody(ctx, info, d0, d1, half, rTail, rHead, color, alphaMul, fadeScale) {
    var h = Math.max(0, d1 - d0);
    if (h <= 0.01) return;
    fadeScale = fadeScale === undefined ? 1 : fadeScale;
    var rt = clamp(rTail, 0, Math.min(half, h * 0.5));
    var rh = clamp(rHead, 0, Math.min(half, h * 0.5));
    if (rt + rh > h) rh = Math.max(0, h - rt);

    var pts = [];
    var segs = 8;
    var i, a, dd;

    // 靠头那端（d0）
    if (rh > 0.01) {
      for (i = 0; i <= segs; i++) {
        a = Math.PI + (Math.PI * 0.5) * (i / segs);
        dd = d0 + rh + Math.sin(a) * rh;
        pts.push(laneLocalPoint(info, dd, -half + rh + Math.cos(a) * rh, 0));
      }
    } else {
      pts.push(laneLocalPoint(info, d0, -half, 0));
    }
    pts.push(laneLocalPoint(info, d0, half - rh, 0));
    if (rh > 0.01) {
      for (i = 0; i <= segs; i++) {
        a = Math.PI * 1.5 + (Math.PI * 0.5) * (i / segs);
        dd = d0 + rh + Math.sin(a) * rh;
        pts.push(laneLocalPoint(info, dd, half - rh + Math.cos(a) * rh, 0));
      }
    }
    // 右侧往上
    pts.push(laneLocalPoint(info, d0 + h - rt, half, 0));
    // 靠尾那端（d1）
    if (rt > 0.01) {
      for (i = 0; i <= segs; i++) {
        a = (Math.PI * 0.5) * (i / segs);
        dd = d0 + h - rt + Math.sin(a) * rt;
        pts.push(laneLocalPoint(info, dd, half - rt + Math.cos(a) * rt, 0));
      }
    }
    pts.push(laneLocalPoint(info, d0 + h, -half + rt, 0));
    if (rt > 0.01) {
      for (i = 0; i <= segs; i++) {
        a = Math.PI * 0.5 + (Math.PI * 0.5) * (i / segs);
        dd = d0 + h - rt + Math.sin(a) * rt;
        pts.push(laneLocalPoint(info, dd, -half + rt + Math.cos(a) * rt, 0));
      }
    }
    pts.push(laneLocalPoint(info, d0 + rh, -half, 0));

    // 尾端渐隐：从"头"到"尾"一段 fade 长度内透明度 1 → 0
    var fade = Math.max(0.001, clamp(h * 0.45, 5, 34) * (alphaMul >= 0.99 ? 1 : 0.45) * fadeScale);
    var headPt = lanePoint(info, d0);
    var tailPt = lanePoint(info, d1);
    var grad = ctx.createLinearGradient(headPt.x, headPt.y, tailPt.x, tailPt.y);
    var solidStop = clamp(1 - fade / h, 0, 1);
    grad.addColorStop(0, rgba(color, alphaMul));
    grad.addColorStop(solidStop, rgba(color, alphaMul));
    grad.addColorStop(1, rgba(color, 0));

    pathPoly(ctx, pts);
    ctx.fillStyle = grad;
    ctx.fill();
  }

  /* ------------------------------------------------------------- 绘制入口 */

  var chordCache = (typeof WeakMap === 'function') ? new WeakMap() : null;
  var notesCache = (typeof WeakMap === 'function') ? new WeakMap() : null;

  /** 标出多押（同一时刻 ±20ms 有 ≥2 个可判定音符），同 stage_view._mark_chords */
  function chordMap(chart) {
    if (chordCache && chordCache.has(chart)) return chordCache.get(chart);
    var map = {};
    var notes = (chart.notes || []).slice();
    var i = 0;
    while (i < notes.length) {
      var t = num(notes[i].time, 0);
      var j = i;
      var group = [];
      while (j < notes.length && Math.abs(num(notes[j].time, 0) - t) <= CHORD_EPS) {
        if (String(notes[j].type || 'tap') !== 'mine') group.push(notes[j]);
        j++;
      }
      if (group.length >= 2) {
        for (var k = 0; k < group.length; k++) map[String(group[k].lane) + ':' + group[k].time] = group.length;
      }
      i = j;
    }
    if (chordCache) chordCache.set(chart, map);
    return map;
  }

  /** 每轨的音符（按时间升序），同 stage_view.setup 的 _notes_by_lane */
  function notesByLane(chart) {
    if (notesCache && notesCache.has(chart)) return notesCache.get(chart);
    var out = [];
    var lanes = chart.lanes || [];
    for (var i = 0; i < lanes.length; i++) out.push([]);
    var notes = chart.notes || [];
    for (var n = 0; n < notes.length; n++) {
      var li = Math.floor(num(notes[n].lane, 0));
      if (li >= 0 && li < out.length) out[li].push(notes[n]);
    }
    for (var j = 0; j < out.length; j++) {
      out[j].sort(function (a, b) { return num(a.time, 0) - num(b.time, 0); });
    }
    if (notesCache) notesCache.set(chart, out);
    return out;
  }

  /** 绘制回看窗口：max(最长春条 × 最大流速, 4)，上限 60（同 stage_view.setup） */
  function holdLookback(chart) {
    var maxSpeed = 1;
    var lanes = chart.lanes || [];
    for (var i = 0; i < lanes.length; i++) {
      var evs = lanes[i].events || {};
      var sp = evs.speed || [];
      for (var j = 0; j < sp.length; j++) {
        maxSpeed = Math.max(maxSpeed, Math.abs(num(sp[j].from, 1)), Math.abs(num(sp[j].to, 1)));
      }
    }
    var back = 4;
    var notes = chart.notes || [];
    for (var n = 0; n < notes.length; n++) {
      if (String(notes[n].type || '') === 'hold') {
        back = Math.max(back, num(notes[n].duration, 0) * maxSpeed);
      }
    }
    return Math.min(back, 60);
  }

  /** 轨道本体：只画两侧 1px 描边（和游戏一致） */
  function drawLaneBody(ctx, info, alphaMul) {
    if (info.alpha <= 0.001 || info.len < 0.5) return;
    var col = info.color;
    ctx.lineWidth = 1;
    ctx.strokeStyle = rgba(col, 0.16 * info.alpha * alphaMul);
    var a = laneLocalPoint(info, 0, -info.half, 0);
    var b = laneLocalPoint(info, info.len, -info.half, 0);
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.stroke();
    var c = laneLocalPoint(info, 0, info.half, 0);
    var d = laneLocalPoint(info, info.len, info.half, 0);
    ctx.beginPath();
    ctx.moveTo(c.x, c.y);
    ctx.lineTo(d.x, d.y);
    ctx.stroke();
  }

  /** 判定线：底部加粗圆角横条 */
  function drawLaneJudge(ctx, info, alphaMul) {
    if (info.alpha <= 0.001) return;
    var lineW = Math.max(2.2, info.half * JUDGE_LINE_RATIO);
    var pts = laneShape(info, 0, info.half * 2, lineW, lineW * 0.5);
    pathPoly(ctx, pts);
    ctx.fillStyle = rgba(info.color, info.alpha * alphaMul);
    ctx.fill();
  }

  /** 多押外圈柔光（6 层低透明度圆角块） */
  function drawChordGlow(ctx, info, d, halfW, t, alphaMul) {
    var pulse = 0.9 + 0.1 * Math.sin(t * 7);
    for (var i = 0; i < 6; i++) {
      var k = i / 5;
      var grow = 6 * (1 - k) + 0.4;
      var a = (0.030 + 0.055 * k) * pulse * alphaMul;
      pathPoly(ctx, laneShape(info, d, (halfW + grow) * 2, (NOTE_TH + grow) * 2, NOTE_RADIUS + grow));
      ctx.fillStyle = rgba(CHORD_GLOW, a);
      ctx.fill();
    }
  }

  /** 音符（同 stage_view._draw_notes，去掉判定态的淡出/消失逻辑） */
  function drawNotes(ctx, laneIndex, info, allNotes, chords, t, basePps, noteHalfW, lookback, alphaMul) {
    var notes = allNotes;
    if (!notes || !notes.length) return;

    var lane = info.lane;
    var laneLen = info.len;
    var col = info.color;
    var pps = basePps * info.speed;

    var maxTime = Infinity;
    if (pps > 0.0001) maxTime = t + (laneLen + 40) / pps;
    var startIdx = lowerBound(notes, t - lookback);

    for (var idx = startIdx; idx < notes.length; idx++) {
      var note = notes[idx];
      var ntime = num(note.time, 0);
      if (ntime > maxTime) break;
      var kind = String(note.type || 'tap');

      var head = (ntime - t) * pps;
      var dur = kind === 'hold' ? Math.max(0, num(note.duration, 0)) : 0;
      var isHold = dur > 0.001;
      var bodyMul = info.speed;
      if (bodyMul <= 0.001) bodyMul = RC.holdSpeed(lane, t);
      var tail = head + dur * basePps * bodyMul;

      if (isHold) {
        if (tail < -10) continue;                 // 整条过线
      } else if (head < -0.5) {
        continue;                                 // 普通音符过线就消失
      }
      if (head > laneLen + 40) break;             // 还没进视野

      var headD = Math.max(0, head);
      var chordN = chords[String(note.lane) + ':' + note.time] || 0;
      var isChord = chordN >= 2 && kind !== 'mine';

      if (isChord) drawChordGlow(ctx, info, headD, noteHalfW, t, alphaMul);

      if (isHold && tail > 0) {
        var d0 = Math.max(0, head);
        var d1 = Math.min(tail, laneLen);
        if (d1 > d0) {
          var cut = tail > laneLen + 0.01;
          var headCap = head <= 0.01 ? NOTE_RADIUS : 0;
          drawHoldBody(ctx, info, d0, d1, noteHalfW,
            cut ? 0 : NOTE_RADIUS, headCap, col, alphaMul, cut ? 0 : 1);
        }
      }

      // 音符头：贴线时下半截裁掉，不探到判定线下面
      var headBottom = Math.max(0, headD - NOTE_TH);
      var headTop = headD + NOTE_TH;
      var headH = Math.max(0.5, headTop - headBottom);
      var headR = Math.min(NOTE_RADIUS, Math.min(noteHalfW, headH * 0.5));
      var headPts = laneShape(info, (headBottom + headTop) * 0.5, noteHalfW * 2, headH, headR);

      if (kind === 'mine') {
        pathPoly(ctx, headPts);
        ctx.fillStyle = '#1b1f28';
        ctx.fill();
        ctx.lineWidth = 1.5;
        ctx.strokeStyle = rgba('#ef476f', alphaMul);
        ctx.stroke();
      } else if (kind === 'flick') {
        pathPoly(ctx, headPts);
        ctx.fillStyle = rgba(col, alphaMul);
        ctx.fill();
        var c = lanePoint(info, headD);
        ctx.lineWidth = 1.5;
        ctx.strokeStyle = rgba(BG_DEEP, alphaMul);
        ctx.beginPath();
        ctx.moveTo(c.x - info.dx * 2, c.y - info.dy * 2);
        ctx.lineTo(c.x + info.dx * 2, c.y + info.dy * 2);
        ctx.stroke();
      } else {
        pathPoly(ctx, headPts);
        ctx.fillStyle = rgba(col, 0.92 * alphaMul);
        ctx.fill();
      }
    }
  }

  function lowerBound(arr, t) {
    var lo = 0, hi = arr.length;
    while (lo < hi) {
      var mid = (lo + hi) >> 1;
      if (num(arr[mid].time, 0) < t) lo = mid + 1;
      else hi = mid;
    }
    return lo;
  }

  /**
   * 画一整套谱面舞台。
   * opts: { chart, t, alpha, xyScale }
   * 调用方负责把 ctx 变换到 350×196.875 的逻辑空间（缩放/居中）。
   */
  function draw(ctx, opts) {
    var chart = opts && opts.chart;
    if (!chart) return;
    var t = num(opts.t, 0);
    var alpha = opts.alpha === undefined ? 1 : clamp(opts.alpha, 0, 1);
    if (alpha <= 0.001) return;
    var xy = opts.xyScale === undefined ? 1 : opts.xyScale;

    var lanes = chart.lanes || [];
    if (!lanes.length) return;

    var n = lanes.length;
    var jy = judgeY();
    var halfW = halfWidthOf(n);
    var noteHalfW = Math.max(2, halfW - 1);
    var highway = num(chart.stage && chart.stage.highway_length, 2);
    // visibleSec：制谱器「预览秒数」；不传就用谱面的 highway_length（= 游戏里的一致）
    var visibleSec = num(opts.visibleSec, 0) > 0.05 ? num(opts.visibleSec, 2) : Math.max(0.05, highway || 2);
    var basePps = jy / Math.max(0.05, visibleSec);

    var chords = chordMap(chart);
    var byLane = notesByLane(chart);
    var lookback = holdLookback(chart);

    var geo = [];
    for (var i = 0; i < n; i++) geo.push(laneGeom(lanes[i], i, t, halfW, xy));

    ctx.save();
    for (i = 0; i < n; i++) drawLaneBody(ctx, geo[i], alpha);
    for (i = 0; i < n; i++) {
      drawNotes(ctx, i, geo[i], byLane[i] || [], chords, t, basePps, noteHalfW, lookback, alpha);
    }
    for (i = 0; i < n; i++) drawLaneJudge(ctx, geo[i], alpha);
    ctx.restore();
  }

  var API = {
    STAGE_W: STAGE_W,
    STAGE_H: STAGE_H,
    PV_SCALE: PV_SCALE,
    NOTE_TH: NOTE_TH,
    NOTE_RADIUS: NOTE_RADIUS,
    JUDGE_LINE_RATIO: JUDGE_LINE_RATIO,
    BG: BG_DEEP,
    judgeY: judgeY,
    laneWidth: laneWidthOf,
    halfWidth: halfWidthOf,
    laneGeom: laneGeom,
    laneShape: laneShape,
    draw: draw
  };
  global.ChartStage = API;
  if (typeof globalThis !== 'undefined' && globalThis !== global) globalThis.ChartStage = API;
  // node 测试里 require() 也能直接拿到
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
})(typeof window !== 'undefined' ? window : globalThis);
