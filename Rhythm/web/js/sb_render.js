/* =============================================================================
 * Rhythm 故事板制作器 · 渲染层
 * -----------------------------------------------------------------------------
 * 一张 1280×720 的虚拟舞台，分三段画：
 *   1. 舞台底：谱面轨道 / 音符（严格照 docs/GAME_INTEGRATION.md §2 的公式，只读）
 *   2. 图层：文字（9 种特效）/ 图片 / 形状 / 解锁动画（7 种预设）
 *   3. 后处理：把 1 + 2 的离屏画布当纹理，过一个 WebGL 着色器
 *
 * 后处理用「一个主着色器 + 一组权重 uniform」：每个 Shader 预设只是往某几个
 * 权重里加数，所以多条 shader 事件能同时叠着生效，不需要多趟离屏。
 * 没有 WebGL 时自动退化：直接把离屏画布贴到显示画布上（只丢后处理，别的照常）。
 * ========================================================================== */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory(require('./sb_core.js'), require('./core.js'));
  } else {
    root.SBRender = factory(root.SB, root.RChart);
  }
})(typeof self !== 'undefined' ? self : this, function (SB, RC) {
  'use strict';

  var NOTE_TH = 1.25;

  /* ==========================================================================
   * 小工具
   * ======================================================================== */

  function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

  function rgba(hex, a) { return SB.hexA(hex, a); }

  /** 伪随机（同一下标永远同一结果），解锁动画里的碎片/刻度用它，避免每帧乱跳 */
  function rnd(i, seed) {
    var x = Math.sin((i + 1) * 127.1 + (seed || 0) * 311.7) * 43758.5453;
    return x - Math.floor(x);
  }

  function roundRect(g, x, y, w, h, r) {
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

  function corner(g, x, y, w, h, len, lw, color, a) {
    g.save();
    g.strokeStyle = rgba(color, a);
    g.lineWidth = lw;
    g.beginPath();
    g.moveTo(x, y + len); g.lineTo(x, y); g.lineTo(x + len, y);
    g.moveTo(x + w - len, y); g.lineTo(x + w, y); g.lineTo(x + w, y + len);
    g.moveTo(x + w, y + h - len); g.lineTo(x + w, y + h); g.lineTo(x + w - len, y + h);
    g.moveTo(x + len, y + h); g.lineTo(x, y + h); g.lineTo(x, y + h - len);
    g.stroke();
    g.restore();
  }

  /** 一行说明文字（解锁动画里的曲名 / 难度） */
  function caption(g, text, y, size, color, opts) {
    if (!text) return 0;
    var o = opts || {};
    g.save();
    g.font = (o.weight || 800) + ' ' + size + 'px ' + SB.fontStack(o.font || 'auto');
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    if (o.glow) {
      g.shadowColor = rgba(o.glowColor || color, 0.9);
      g.shadowBlur = size * o.glow;
    }
    g.fillStyle = color;
    g.globalAlpha = (o.alpha === undefined ? 1 : o.alpha) * (g.globalAlpha || 1);
    g.fillText(text, 0, y);
    g.restore();
    return size;
  }

  /* ==========================================================================
   * WebGL 后处理
   * ======================================================================== */

  var VERT = [
    'attribute vec2 aPos;',
    'varying vec2 vUv;',
    'void main() {',
    '  vUv = aPos * 0.5 + 0.5;',
    '  gl_Position = vec4(aPos, 0.0, 1.0);',
    '}'
  ].join('\n');

  var FRAG = [
    'precision highp float;',
    'varying vec2 vUv;',
    'uniform sampler2D uTex;',
    'uniform vec2 uRes;',
    'uniform float uTime;',
    'uniform float uPunchT0;',
    'uniform float uBloom, uRgb, uScan, uWave, uGlitch, uHeat, uPixel, uPoster, uGrain, uVignette, uInvert, uStretch, uZoom, uShake;',
    '',
    'float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }',
    '',
    'vec3 sample3(vec2 uv, vec2 off) {',
    '  return vec3(',
    '    texture2D(uTex, clamp(uv + off, 0.0, 1.0)).r,',
    '    texture2D(uTex, clamp(uv, 0.0, 1.0)).g,',
    '    texture2D(uTex, clamp(uv - off, 0.0, 1.0)).b);',
    '}',
    '',
    'void main() {',
    '  vec2 uv = vUv;',
    '  float t = uTime;',
    '',
    '  if (uWave > 0.001) {',
    '    uv.x += sin(uv.y * 24.0 + t * 3.0) * 0.0045 * uWave;',
    '    uv.y += cos(uv.x * 18.0 + t * 2.4) * 0.0032 * uWave;',
    '  }',
    '',
    '  if (uHeat > 0.001) {',
    '    uv.x += sin(uv.y * 92.0 + t * 9.0) * 0.0032 * uHeat;',
    '    uv.y += sin(uv.x * 61.0 - t * 7.0) * 0.0024 * uHeat;',
    '  }',
    '',
    '  if (uGlitch > 0.001) {',
    '    float band = floor(uv.y * 26.0);',
    '    float r = hash(vec2(band, floor(t * 14.0)));',
    '    if (r > 0.72) uv.x += (r - 0.86) * 0.10 * uGlitch;',
    '    float r2 = hash(vec2(floor(uv.x * 16.0), floor(t * 9.0) + 3.0));',
    '    if (r2 > 0.93) uv.y += (r2 - 0.965) * 0.14 * uGlitch;',
    '  }',
    '',
    '  if (uPixel > 0.001) {',
    '    vec2 cells = mix(uRes, vec2(28.0, 16.0), 0.82 * uPixel);',
    '    uv = (floor(uv * cells) + 0.5) / cells;',
    '  }',
    '',
    '  if (uStretch > 0.001) {',
    '    // 四角拉伸：角上的采样点往中心收（=角落内容被拉出去），边和中心几乎不动',
    '    vec2 sp = uv - 0.5;',
    '    vec2 sa = abs(sp) * 2.0;',
    '    float corner = pow(sa.x * sa.y, 1.3);          // 角=1，边/中心=0',
    '    float edge = max(sa.x, sa.y);',
    '    float k = uStretch * (0.16 * corner + 0.03 * edge * edge * edge);',
    '    uv = 0.5 + sp * (1.0 - clamp(k, 0.0, 0.35));',
    '  }',
    '',
    '  float punch = 0.0;',
    '  if (uZoom > 0.001) {',
    '    // 冲击放大：进区间那一下「砰」地放大，0.22s 内回弹到原样（末尾略小于 1 = 过冲抖一下）',
    '    float k = clamp((t - uPunchT0) / 0.22, 0.0, 1.0);',
    '    punch = pow(1.0 - k, 2.5);',
    '    float over = -0.05 * sin(3.14159 * k) * (1.0 - k);',
    '    float z = 1.0 + (0.18 * punch + over) * uZoom;',
    '    uv = 0.5 + (uv - 0.5) / z;',
    '  }',
    '',
    '  if (uShake > 0.001) {',
    '    // 抖动只在冲击那一下：幅度跟着 punch 走，放大瞬间抖得最厉害',
    '    float amp = 0.0075 * uShake * punch;',
    '    float sx = sin(t * 41.0) * 0.6 + sin(t * 97.0 + 1.7) * 0.4;',
    '    float sy = cos(t * 37.0 + 0.5) * 0.6 + cos(t * 89.0 + 2.3) * 0.4;',
    '    uv += vec2(sx, sy) * amp;',
    '  }',
    '',
    '  uv = clamp(uv, 0.0, 1.0);',
    '  vec2 off = vec2(uRgb * 0.006 + uHeat * 0.0015, 0.0);',
    '  vec3 col = sample3(uv, off);',
    '',
    '  if (uBloom > 0.001) {',
    '    float rad = 0.0042 * uBloom + 0.0012;',
    '    vec3 sum = vec3(0.0);',
    '    float wsum = 0.0;',
    '    for (int i = 0; i < 8; i++) {',
    '      float a = float(i) * 0.7853981;',
    '      vec2 dir = vec2(cos(a), sin(a));',
    '      sum += texture2D(uTex, clamp(uv + dir * rad, 0.0, 1.0)).rgb;',
    '      sum += texture2D(uTex, clamp(uv + dir * rad * 2.6, 0.0, 1.0)).rgb * 0.55;',
    '      wsum += 1.55;',
    '    }',
    '    vec3 bl = sum / wsum;',
    '    // 平方加权：只把亮部晕开，不打硬边，也不会复制出一份"重影"',
    '    col += bl * bl * uBloom * 1.4;',
    '  }',
    '',
    '  if (uPoster > 0.001) {',
    '    float levels = mix(64.0, 4.0, uPoster);',
    '    col = floor(col * levels + 0.5) / levels;',
    '  }',
    '',
    '  if (uScan > 0.001) {',
    '    float s = sin(uv.y * uRes.y * 1.7 + t * 8.0) * 0.5 + 0.5;',
    '    col *= 1.0 - uScan * 0.26 * s;',
    '    col *= 1.0 - uScan * 0.08 * (sin(uv.y * uRes.y * 26.0) * 0.5 + 0.5);',
    '  }',
    '',
    '  if (uGrain > 0.001) {',
    '    col += (hash(uv * uRes + t * 60.0) - 0.5) * uGrain * 0.17;',
    '  }',
    '',
    '  if (uVignette > 0.001) {',
    '    vec2 d = uv - 0.5;',
    '    float v = smoothstep(0.86, 0.24, length(d) * 1.36);',
    '    col *= mix(1.0, v, uVignette);',
    '  }',
    '',
    '  col = mix(col, vec3(1.0) - col, clamp(uInvert, 0.0, 1.0) * 0.9);',
    '  gl_FragColor = vec4(col, 1.0);',
    '}'
  ].join('\n');

  var WEIGHT_UNIFORMS = {
    bloom: 'uBloom',
    rgb: 'uRgb',
    scan: 'uScan',
    wave: 'uWave',
    glitch: 'uGlitch',
    heat: 'uHeat',
    pixel: 'uPixel',
    poster: 'uPoster',
    grain: 'uGrain',
    vignette: 'uVignette',
    invert: 'uInvert',
    stretch: 'uStretch',
    zoom: 'uZoom',
    shake: 'uShake'
  };

  function compile(gl, type, src) {
    var sh = gl.createShader(type);
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
      var log = gl.getShaderInfoLog(sh);
      gl.deleteShader(sh);
      throw new Error('shader 编译失败: ' + log);
    }
    return sh;
  }

  /* ==========================================================================
   * 渲染器
   * ======================================================================== */

  function Renderer(canvas) {
    this.canvas = canvas || document.createElement('canvas');
    this.W = SB.STAGE_W;
    this.H = SB.STAGE_H;
    this.canvas.width = this.W;
    this.canvas.height = this.H;

    this.base = document.createElement('canvas');
    this.base.width = this.W;
    this.base.height = this.H;
    this.g = this.base.getContext('2d');

    this.gl = null;
    this.ctx2d = null;
    this.uniforms = {};
    this.lastWeights = null;
    this.glError = '';

    this.initGL();

    // 显存吃紧 / 驱动重置时 Chrome 会丢掉 WebGL 上下文：接住它，别让整页崩掉
    var self = this;
    if (canvas && canvas.addEventListener) {
      canvas.addEventListener('webglcontextlost', function (e) {
        e.preventDefault();
        self.glError = '显存被系统回收，先按 2D 显示；浏览器恢复后会自动接回去';
        self.gl = null;
        self._tg = null;
      }, false);
      canvas.addEventListener('webglcontextrestored', function () {
        try {
          self.initGL();
          self.glError = '';
        } catch (err) {
          self.gl = null;
        }
      }, false);
    }
  }

  Renderer.prototype.initGL = function () {
    var gl = null;
    try {
      gl = this.canvas.getContext('webgl', {
        alpha: false, antialias: false, depth: false, stencil: false,
        preserveDrawingBuffer: true, premultipliedAlpha: false
      });
    } catch (err) {
      gl = null;
    }

    if (!gl) {
      this.glError = '这个浏览器没给 WebGL，后处理已关闭（其余照常）';
      this.ctx2d = this.canvas.getContext('2d');
      return;
    }

    try {
      var prog = gl.createProgram();
      gl.attachShader(prog, compile(gl, gl.VERTEX_SHADER, VERT));
      gl.attachShader(prog, compile(gl, gl.FRAGMENT_SHADER, FRAG));
      gl.linkProgram(prog);
      if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
        throw new Error('program 链接失败: ' + gl.getProgramInfoLog(prog));
      }
      gl.useProgram(prog);

      var buf = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, buf);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([
        -1, -1, 1, -1, -1, 1,
        -1, 1, 1, -1, 1, 1
      ]), gl.STATIC_DRAW);
      var loc = gl.getAttribLocation(prog, 'aPos');
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);

      var tex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);

      var u = {
        uTex: gl.getUniformLocation(prog, 'uTex'),
        uRes: gl.getUniformLocation(prog, 'uRes'),
        uTime: gl.getUniformLocation(prog, 'uTime'),
      uPunchT0: gl.getUniformLocation(prog, 'uPunchT0')
      };
      for (var key in WEIGHT_UNIFORMS) {
        if (Object.prototype.hasOwnProperty.call(WEIGHT_UNIFORMS, key)) {
          u[WEIGHT_UNIFORMS[key]] = gl.getUniformLocation(prog, WEIGHT_UNIFORMS[key]);
        }
      }

      gl.uniform1i(u.uTex, 0);
      gl.uniform2f(u.uRes, this.W, this.H);

      this.gl = gl;
      this.prog = prog;
      this.tex = tex;
      this.uniforms = u;
    } catch (err) {
      this.glError = '后处理初始化失败：' + (err && err.message ? err.message : err);
      this.gl = null;
      this.ctx2d = this.canvas.getContext('2d');
    }
  };

  Renderer.prototype.glOk = function () { return !!this.gl; };

  /* ---------- 主入口 ---------- */

  /**
   * 画一帧。
   * frame = { t, doc, chart, images, phase }
   *   t      故事板**全局**时间（秒）：先按场景拆成「哪一场 + 场内本地时间」
   *   doc    故事板工程（场景 → 图层 / 后处理）
   *   chart  RChart.normalize 出来的谱面，可以没有（只有谱面场会画它）
   *   images { 资源名: HTMLImageElement }
   *   phase  一个 0~1 的连续值（给 shader 的噪声用，默认 = t）
   */
  Renderer.prototype.render = function (frame) {
    var doc = frame.doc;
    var g = this.g;
    var W = this.W, H = this.H;

    g.setTransform(1, 0, 0, 1, 0, 0);
    g.globalAlpha = 1;
    g.globalCompositeOperation = 'source-over';
    g.filter = 'none';
    g.clearRect(0, 0, W, H);
    g.fillStyle = (doc.stage && doc.stage.bg) || '#05070c';
    g.fillRect(0, 0, W, H);

    var at = SB.sceneAt(doc, frame.t);
    var scene = at ? at.span.scene : null;
    var local = at ? at.local : 0;
    this.lastScene = at ? { index: at.index, kind: at.span.kind, local: local } : null;

    // 只有谱面场画谱面：解锁场 / 演出场就是纯演出
    if (scene && at.span.kind === 'chart') {
      this.drawChartStage(g, doc, frame.chart, local);
    }

    var list = scene ? SB.activeLayers(scene, local) : [];
    for (var i = 0; i < list.length; i++) {
      this.drawLayer(g, list[i].layer, list[i].state, frame, local);
    }

    g.globalAlpha = 1;
    g.globalCompositeOperation = 'source-over';
    g.filter = 'none';

    // 后处理：一条 shader = 一层，逐层叠加（不是把权重合并成一个着色器）
    var stack = scene ? SB.activeShaders(scene, local) : [];
    this.lastStack = stack;
    this.lastWeights = scene ? SB.combineShaderWeights(scene, local) : SB.emptyWeights();
    var globalT = frame.phase === undefined ? frame.t : frame.phase;
    // 冲击放大用的 punchT0 是「场景内时间」，而 uTime 是全局时间 → 这里算差值
    this.postStack(stack, globalT, globalT - local);
  };

  /** 只重画后处理（UI 里拖 shader 强度时不用整帧重画） */
  Renderer.prototype.post = function (weights, time) {
    if (this.gl) {
      var gl = this.gl;
      gl.viewport(0, 0, this.W, this.H);
      gl.bindTexture(gl.TEXTURE_2D, this.tex);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, this.base);
      gl.uniform1f(this.uniforms.uTime, time || 0);
      for (var key in WEIGHT_UNIFORMS) {
        if (!Object.prototype.hasOwnProperty.call(WEIGHT_UNIFORMS, key)) continue;
        var loc = this.uniforms[WEIGHT_UNIFORMS[key]];
        if (loc) gl.uniform1f(loc, weights[key] || 0);
      }
      gl.drawArrays(gl.TRIANGLES, 0, 6);
    } else if (this.ctx2d) {
      this.ctx2d.setTransform(1, 0, 0, 1, 0, 0);
      this.ctx2d.globalAlpha = 1;
      this.ctx2d.globalCompositeOperation = 'source-over';
      this.ctx2d.clearRect(0, 0, this.W, this.H);
      this.ctx2d.drawImage(this.base, 0, 0);
    }
  };

  /**
   * 两层离屏目标（A/B 轮转）。每层后处理各跑一遍全屏 pass，结果喂给下一层。
   * 拿不到 FBO 的环境（假 WebGL / 老浏览器）返回 false，调用方退回「一次画完」。
   */
  Renderer.prototype.ensureTargets = function () {
    var gl = this.gl;
    if (!gl) return false;
    if (typeof gl.createFramebuffer !== 'function' || typeof gl.framebufferTexture2D !== 'function') return false;
    if (this._tg && this._tg.w === this.W && this._tg.h === this.H) return true;
    try {
      if (this._tg) {
        for (var d = 0; d < 2; d++) {
          try { gl.deleteFramebuffer(this._tg.fb[d]); } catch (e) { /* 忽略 */ }
          try { gl.deleteTexture(this._tg.tex[d]); } catch (e) { /* 忽略 */ }
        }
      }
      var tex = [], fb = [];
      for (var i = 0; i < 2; i++) {
        var t = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, t);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, this.W, this.H, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        var f = gl.createFramebuffer();
        if (!f) throw new Error('createFramebuffer 返回空');
        gl.bindFramebuffer(gl.FRAMEBUFFER, f);
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
        tex.push(t);
        fb.push(f);
      }
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      this._tg = { w: this.W, h: this.H, tex: tex, fb: fb };
      return true;
    } catch (e) {
      this._tg = null;
      gl.bindFramebuffer && gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      return false;
    }
  };

  /** 设一遍权重 uniform（没列到的键一律 0） */
  Renderer.prototype.setWeights = function (weights) {
    var gl = this.gl;
    for (var key in WEIGHT_UNIFORMS) {
      if (!Object.prototype.hasOwnProperty.call(WEIGHT_UNIFORMS, key)) continue;
      var loc = this.uniforms[WEIGHT_UNIFORMS[key]];
      if (!loc) continue;
      var v = (weights && weights[key]) || 0;
      gl.uniform1f(loc, clamp(v, 0, 4));
    }
  };

  /** 逐层叠加：层 1 → 层 2 → … → 屏幕 */
  Renderer.prototype.postStack = function (stack, time, shift) {
    var gl = this.gl;
    var t = time || 0;
    if (!gl) {
      this.post(SB.emptyWeights(), t);      // 2D 回退：不跑后处理
      return;
    }
    if (!stack || !stack.length) {
      this.post(SB.emptyWeights(), t);      // 没有后处理：一次纯拷贝
      return;
    }
    if (!this.ensureTargets()) {
      // 拿不到离屏目标：退回老做法（合并成一次），至少不出错
      var merged = {};
      for (var i0 = 0; i0 < stack.length; i0++) {
        for (var k0 in stack[i0].weights) {
          if (!Object.prototype.hasOwnProperty.call(stack[i0].weights, k0)) continue;
          merged[k0] = clamp((merged[k0] || 0) + stack[i0].weights[k0], 0, 1.5);
        }
      }
      this.post(merged, t);
      return;
    }

    var tg = this._tg;
    var W = this.W, H = this.H;
    var cur = 0;

    gl.viewport(0, 0, W, H);
    gl.activeTexture(gl.TEXTURE0);
    gl.uniform1i(this.uniforms.uTex, 0);
    gl.uniform2f(this.uniforms.uRes, W, H);
    gl.uniform1f(this.uniforms.uTime, t);

    // 底图 → tex[0]
    gl.bindTexture(gl.TEXTURE_2D, tg.tex[cur]);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, this.base);

    // 一层一层叠
    for (var i = 0; i < stack.length; i++) {
      var next = 1 - cur;
      gl.bindFramebuffer(gl.FRAMEBUFFER, tg.fb[next]);
      gl.viewport(0, 0, W, H);
      gl.bindTexture(gl.TEXTURE_2D, tg.tex[cur]);
      this.setWeights(stack[i].weights);
      if (this.uniforms.uPunchT0) {
        var t0 = stack[i].punchT0 === undefined ? 0 : stack[i].punchT0;
        gl.uniform1f(this.uniforms.uPunchT0, t0 + (shift || 0));
      }
      gl.drawArrays(gl.TRIANGLES, 0, 6);
      cur = next;
    }

    // 结果贴回屏幕（纯拷贝）
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, W, H);
    gl.bindTexture(gl.TEXTURE_2D, tg.tex[cur]);
    this.setWeights(null);
    gl.uniform1f(this.uniforms.uTime, t);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
  };

  /** 当前画面（PNG dataURL），导出关键帧用 */
  Renderer.prototype.shot = function () {
    return this.canvas.toDataURL('image/png');
  };

  /* ==========================================================================
   * 1. 谱面舞台（只读）
   * ======================================================================== */

  /**
   * 谱面图层的基准尺寸。
   * 谱面里的 x / y 是**绝对像素**，制谱器的预渲染窗只有约 380×214，
   * 同一个 y=70 在 214 高的窗里等于 33%，在 720 高的舞台上只有 10% —— 所以故事板
   * 必须按「预渲染窗」的尺寸把谱面画一遍，再整体放大到舞台，构图才对得上。
   */
  Renderer.prototype.chartBase = function (doc) {
    var w = clamp(SB.num(doc && doc.stage && doc.stage.chartBase, 350), 120, 2560);
    return { w: w, h: w * 9 / 16 };
  };

  Renderer.prototype.drawChartStage = function (g, doc, chart, t) {
    if (!chart) return;
    // 谱面从 0 秒开始：前置段（t < 0）只演图层，不画轨道和音符
    if (t < -1e-6) return;
    var alpha = clamp(SB.num(doc.stage && doc.stage.chartAlpha, 100) / 100, 0, 1);
    if (alpha <= 0.001) return;

    // 和 Godot 的 stage_view.gd 完全一致：逻辑舞台 350×196.875，整体放大到舞台
    var CS = chartStageAPI();
    if (!CS) return;
    var base = this.chartBase(doc);
    var xyScale = CS.STAGE_W / base.w;             // 谱面 x/y 若按别的画幅调的，缩回逻辑空间
    var scale = this.W / CS.STAGE_W;
    g.save();
    g.scale(scale, scale);
    CS.draw(g, { chart: chart, t: t, alpha: alpha, xyScale: xyScale });
    g.restore();
  };

  /** 拿 ChartStage（浏览器里是 window 上的全局，node 测试里可能是 globalThis） */
  function chartStageAPI() {
    if (typeof ChartStage !== 'undefined') return ChartStage;
    if (typeof globalThis !== 'undefined' && globalThis.ChartStage) return globalThis.ChartStage;
    if (typeof window !== 'undefined' && window.ChartStage) return window.ChartStage;
    return null;
  }

  /** core 的 laneParamsAt（轨道 6 个参数 + 事件动画），只读 */
  function SB_layerParams(lane, t) {
    return RC.laneParamsAt(lane, t);
  }


  Renderer.prototype.drawLayer = function (g, layer, st, frame, local) {
    if (!st.active || st.alpha <= 0.002) return;
    var W = this.W, H = this.H;
    var ctx = {
      t: local === undefined ? frame.t : local,
      time: frame.phase === undefined ? (local === undefined ? frame.t : local) : frame.phase,
      doc: frame.doc,
      chart: frame.chart,
      images: frame.images || {},
      videos: frame.videos || {}
    };

    g.save();
    g.globalAlpha = clamp(st.alpha, 0, 1);
    g.globalCompositeOperation = SB.BLEND_CANVAS[layer.blend] || 'source-over';
    g.translate(st.x * W, st.y * H);
    if (st.rot) g.rotate(st.rot * Math.PI / 180);
    if (st.scale !== 1) g.scale(st.scale, st.scale);
    if (st.blur > 0.01) g.filter = 'blur(' + (st.blur * 10).toFixed(1) + 'px)';

    if (layer.type === 'text') this.drawText(g, layer, st, ctx);
    else if (layer.type === 'shape') this.drawShape(g, layer, st);
    else if (layer.type === 'image') this.drawImage(g, layer, st, ctx);
    else if (layer.type === 'video') this.drawVideo(g, layer, st, ctx);
    else if (layer.type === 'unlock') this.drawUnlock(g, layer, st, ctx);

    g.restore();
  };

  /* ---------- 文字 ---------- */

  Renderer.prototype.drawText = function (g, layer, st, ctx) {
    var s = layer.style;
    var text = String(layer.text === undefined || layer.text === null ? '' : layer.text);
    if (!text) return;

    var size = s.size;
    var fontStr = s.weight + ' ' + size + 'px ' + SB.fontStack(s.font);
    g.font = fontStr;
    g.textBaseline = 'middle';
    g.textAlign = 'center';

    var letter = s.letter * size;
    var lines = text.split('\n');
    var rows = [];
    var maxW = 0;
    var total = 0;

    for (var i = 0; i < lines.length; i++) {
      var chars = Array.from(lines[i]);
      var widths = [];
      var w = 0;
      for (var c = 0; c < chars.length; c++) {
        var cw = g.measureText(chars[c]).width;
        widths.push(cw);
        w += cw;
      }
      w += letter * Math.max(0, chars.length - 1);
      if (w > maxW) maxW = w;
      total += chars.length;
      rows.push({ chars: chars, widths: widths, w: w });
    }

    var lineH = size * s.lineH;
    var boxW = maxW + size * 0.4;
    var boxH = lineH * rows.length + size * 0.2;

    if (st.wipe < 0.999) {
      g.save();
      g.beginPath();
      g.rect(-boxW / 2, -boxH / 2, boxW * clamp(st.wipe, 0, 1), boxH);
      g.clip();
    }

    var gradient = null;
    if (s.effect === 'gradient') {
      gradient = g.createLinearGradient(-maxW / 2, -boxH / 2, maxW / 2, boxH / 2);
      gradient.addColorStop(0, s.c1);
      gradient.addColorStop(1, s.c2);
    }

    var reveal = s.effect === 'type' ? Math.max(0, st.elapsed) * s.speed : Infinity;
    var gi = 0;
    var lastX = 0, lastY = 0;

    for (var li = 0; li < rows.length; li++) {
      var row = rows[li];
      var y = -boxH / 2 + lineH * (li + 0.5) + size * 0.1;
      var startX;
      if (s.align === 'left') startX = -maxW / 2;
      else if (s.align === 'right') startX = maxW / 2 - row.w;
      else startX = -row.w / 2;

      var cursor = startX;
      for (var ci = 0; ci < row.chars.length; ci++) {
        var ch = row.chars[ci];
        var cw = row.widths[ci];
        var x = cursor + cw / 2;
        cursor += cw + letter;
        gi++;

        if (gi > reveal) continue;

        var dx = 0, dy = 0, sc = 1, rot = 0, ca = 1;

        if (s.effect === 'perchar') {
          var tin = st.elapsed - (gi - 1) * 0.045;
          if (tin < 0) continue;
          var kk = clamp(tin / 0.34, 0, 1);
          var e = SB.ease('outBack', kk);
          sc = 0.55 + 0.45 * e;
          ca = clamp(kk * 1.6, 0, 1);
          dy = (1 - kk) * size * 0.32;
        } else if (s.effect === 'wave') {
          dy = Math.sin(ctx.time * 4.2 + gi * 0.62) * size * 0.09;
          rot = Math.cos(ctx.time * 3.1 + gi * 0.5) * 0.10;
        } else if (s.effect === 'shake') {
          dx = Math.sin(ctx.time * 43 + gi * 1.7) * size * 0.018;
          dy = Math.cos(ctx.time * 37 + gi * 1.3) * size * 0.014;
        } else if (s.effect === 'glitch') {
          var burst = (Math.sin(ctx.time * 9.1 + gi) > 0.45) ? 1 : 0.25;
          dx = (rnd(Math.floor(ctx.time * 24) + gi * 7, 3) - 0.5) * size * 0.16 * burst;
          dy = (rnd(Math.floor(ctx.time * 18) + gi * 3, 7) - 0.5) * size * 0.07 * burst;
        }

        g.save();
        g.globalAlpha = clamp(g.globalAlpha * ca, 0, 1);
        g.translate(x + dx, y + dy);
        if (rot) g.rotate(rot);
        if (sc !== 1) g.scale(sc, sc);

        if (s.effect === 'glitch') {
          g.save();
          g.globalCompositeOperation = 'lighter';
          g.fillStyle = rgba('#ff2d55', 0.72);
          g.fillText(ch, -size * 0.05, 0);
          g.fillStyle = rgba('#4cf0ff', 0.72);
          g.fillText(ch, size * 0.05, 0);
          g.restore();
        }

        if (s.effect === 'glow') {
          // 先画一圈光晕，再画一层不带模糊的实心字，字才不会糊成一团
          g.shadowColor = rgba(s.color, 0.95);
          g.shadowBlur = size * 0.55 * clamp(s.glow, 0, 1) + 4;
          g.fillStyle = s.color;
          g.fillText(ch, 0, 0);
          g.shadowBlur = 0;
          g.fillText(ch, 0, 0);
        } else if (s.effect === 'outline') {
          if (s.strokeW > 0) {
            g.strokeStyle = s.stroke;
            g.lineWidth = s.strokeW;
            g.lineJoin = 'round';
            g.strokeText(ch, 0, 0);
          }
          g.fillStyle = s.color;
          g.fillText(ch, 0, 0);
        } else {
          g.fillStyle = gradient || s.color;
          g.fillText(ch, 0, 0);
        }

        g.restore();
        lastX = x + cw / 2 + letter;
        lastY = y;
      }
    }

    // 打字机的光标
    if (s.effect === 'type' && rows.length) {
      var blink = Math.sin(ctx.time * 9) > 0;
      if (blink && gi <= reveal) {
        g.fillStyle = rgba(s.color, 0.9);
        g.fillRect(lastX + 2, lastY - size * 0.42, Math.max(2, size * 0.07), size * 0.84);
      }
    }

    if (st.wipe < 0.999) g.restore();

    // 描边特效额外给整行描一圈淡边
    if (s.effect === 'outline' && s.strokeW <= 0) {
      g.strokeStyle = rgba(s.stroke, 0.85);
      g.lineWidth = 2;
      g.font = fontStr;
      for (var r2 = 0; r2 < rows.length; r2++) {
        var yy = -boxH / 2 + lineH * (r2 + 0.5) + size * 0.1;
        var xx = s.align === 'left' ? -maxW / 2 + rows[r2].w / 2
          : s.align === 'right' ? maxW / 2 - rows[r2].w / 2 : 0;
        g.strokeText(rows[r2].chars.join(''), xx, yy);
      }
    }
  };

  /* ---------- 形状 ---------- */

  Renderer.prototype.drawShape = function (g, layer, st) {
    var sp = layer.shape;
    var W = this.W, H = this.H;
    var w = sp.w * W;
    var h = sp.h * H;

    if (st.wipe < 0.999) {
      g.save();
      g.beginPath();
      g.rect(-w / 2, -Math.max(h, 4) / 2 - 2, w * clamp(st.wipe, 0, 1), Math.max(h, 4) + 4);
      g.clip();
    }

    g.fillStyle = layer.color;
    g.strokeStyle = layer.color;

    if (sp.kind === 'rect') {
      if (sp.fill) {
        roundRect(g, -w / 2, -h / 2, w, h, sp.radius);
        g.fill();
      }
      if (sp.line > 0) {
        roundRect(g, -w / 2, -h / 2, w, h, sp.radius);
        g.lineWidth = sp.line;
        g.stroke();
      }
    } else if (sp.kind === 'line') {
      var lw = Math.max(1, sp.line || Math.max(1, h));
      g.fillRect(-w / 2, -lw / 2, w, lw);
    } else if (sp.kind === 'circle' || sp.kind === 'ring') {
      var r = Math.min(Math.abs(w), Math.abs(h)) / 2;
      g.beginPath();
      g.arc(0, 0, r, 0, Math.PI * 2);
      if (sp.kind === 'circle') g.fill();
      else { g.lineWidth = Math.max(1, sp.line || 3); g.stroke(); }
    } else if (sp.kind === 'grid') {
      var n = Math.max(2, sp.count);
      g.lineWidth = Math.max(1, sp.line || 1);
      g.globalAlpha *= 0.7;
      g.beginPath();
      for (var i = 1; i < n; i++) {
        var x = -w / 2 + (w / n) * i;
        g.moveTo(x, -h / 2); g.lineTo(x, h / 2);
      }
      for (var j = 1; j < n; j++) {
        var y = -h / 2 + (h / n) * j;
        g.moveTo(-w / 2, y); g.lineTo(w / 2, y);
      }
      g.stroke();
    }

    if (st.wipe < 0.999) g.restore();
  };

  /* ---------- 视频 ---------- */

  /** 视频图层：按 layer.video.w 铺在舞台上，cover/contain/stretch 三种适配 */
  Renderer.prototype.drawVideo = function (g, layer, st, ctx) {
    var W = this.W, H = this.H;
    var name = layer.video.name;
    var vid = name ? (ctx.videos || {})[name] : null;
    var vw = vid && vid.videoWidth ? vid.videoWidth : 16;
    var vh = vid && vid.videoHeight ? vid.videoHeight : 9;
    var fit = layer.video.fit || 'cover';

    var boxW = clamp(SB.num(layer.video.w, 1), 0.05, 4) * W;
    var boxH = fit === 'contain' ? Math.min(H, boxW * (vh / vw)) : H;

    var ready = !!(vid && vid.videoWidth && vid.readyState >= 2);

    if (st.wipe < 0.999) {
      g.save();
      g.beginPath();
      g.rect(-boxW / 2, -boxH / 2, boxW * clamp(st.wipe, 0, 1), boxH);
      g.clip();
    }

    if (ready) {
      g.save();
      g.beginPath();
      g.rect(-boxW / 2, -boxH / 2, boxW, boxH);
      g.clip();
      var dw, dh;
      if (fit === 'stretch') {
        dw = boxW; dh = boxH;
      } else {
        var k = (fit === 'contain') ? Math.min(boxW / vw, boxH / vh) : Math.max(boxW / vw, boxH / vh);
        dw = vw * k; dh = vh * k;
      }
      try { g.drawImage(vid, -dw / 2, -dh / 2, dw, dh); } catch (err) { /* 帧还没准备好，跳过这一帧 */ }
      g.restore();
    } else {
      // 没选 / 还在解码：画个虚线框占位
      g.setLineDash([10, 8]);
      g.strokeStyle = 'rgba(124,245,193,0.45)';
      g.lineWidth = 2;
      g.strokeRect(-boxW / 2, -boxH / 2, boxW, boxH);
      g.setLineDash([]);
      g.fillStyle = 'rgba(200,240,225,0.75)';
      g.font = '600 22px ' + SB.fontStack('sans');
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillText(name ? '视频解码中…' : '点属性里的「选视频」', 0, 0);
    }

    if (st.wipe < 0.999) g.restore();
  };

  /* ---------- 图片 ---------- */

  Renderer.prototype.drawImage = function (g, layer, st, ctx) {
    var name = layer.image.name;
    var img = name ? ctx.images[name] : null;
    var W = this.W, H = this.H;
    var w = layer.image.w * W;
    var h = w;

    if (img && img.width && img.height) {
      h = w * (img.height / img.width);
    } else {
      h = w * 0.6;
    }

    if (st.wipe < 0.999) {
      g.save();
      g.beginPath();
      g.rect(-w / 2, -h / 2, w * clamp(st.wipe, 0, 1), h);
      g.clip();
    }

    if (img) {
      g.drawImage(img, -w / 2, -h / 2, w, h);
    } else {
      g.setLineDash([8, 6]);
      g.strokeStyle = 'rgba(255,255,255,0.35)';
      g.lineWidth = 2;
      g.strokeRect(-w / 2, -h / 2, w, h);
      g.setLineDash([]);
      g.fillStyle = 'rgba(200,210,230,0.7)';
      g.font = '600 22px ' + SB.fontStack('sans');
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillText(name ? '图片缺失：' + name : '还没选图片', 0, 0);
    }

    if (st.wipe < 0.999) g.restore();
  };

  /* ==========================================================================
   * 3. 解锁动画（7 种）
   * ======================================================================== */

  Renderer.prototype.drawUnlock = function (g, layer, st, ctx) {
    var u = layer.unlock;
    var p = clamp(st.progress, 0, 1);
    var S = (Math.min(this.W, this.H) / 720) * clamp(SB.num(u.scale, 1), 0.2, 4);
    var label = u.label || (ctx.chart && ctx.chart.meta ? ctx.chart.meta.title : '') || 'UNLOCKED';
    var sub = u.sub || (ctx.chart && ctx.chart.meta
      ? (ctx.chart.meta.difficulty || '') + ' ' + (ctx.chart.meta.level || '')
      : '');

    var info = {
      p: p, S: S, t: ctx.time, elapsed: st.elapsed,
      label: label, sub: sub,
      color: u.color || '#4cc9f0',
      accent: u.accent || '#f72585'
    };

    g.save();
    if (st.wipe < 0.999) {
      var bw = 720 * S, bh = 420 * S;
      g.beginPath();
      g.rect(-bw / 2, -bh / 2, bw * clamp(st.wipe, 0, 1), bh);
      g.clip();
    }

    var fn = UNLOCK_DRAW[u.preset] || UNLOCK_DRAW.tape;
    fn.call(this, g, info);

    g.restore();
  };

  var UNLOCK_DRAW = {

    /* ---------- 磁带插入 ---------- */
    tape: function (g, o) {
      var S = o.S, p = o.p, c = o.color, a = o.accent;
      var inK = SB.ease('outCubic', clamp(p / 0.34, 0, 1));
      var press = clamp((p - 0.34) / 0.16, 0, 1);
      var spin = clamp((p - 0.42) / 0.5, 0, 1);
      var stamp = clamp((p - 0.8) / 0.2, 0, 1);

      var cw = 300 * S, chh = 186 * S;
      var slideX = (1 - inK) * -420 * S;
      var slideRot = (1 - inK) * -0.28;

      // 背后的光环
      g.save();
      g.globalCompositeOperation = 'lighter';
      var halo = g.createRadialGradient(0, 0, 0, 0, 0, 300 * S);
      halo.addColorStop(0, rgba(c, 0.22 * (0.4 + 0.6 * inK)));
      halo.addColorStop(1, rgba(c, 0));
      g.fillStyle = halo;
      g.beginPath();
      g.arc(0, 0, 300 * S, 0, Math.PI * 2);
      g.fill();
      g.restore();

      // 卡槽
      g.save();
      g.strokeStyle = rgba('#ffffff', 0.10);
      g.lineWidth = 2 * S;
      roundRect(g, -cw * 0.62, -chh * 0.62, cw * 1.24, chh * 1.26, 18 * S);
      g.stroke();
      g.restore();

      // 磁带本体
      g.save();
      g.translate(slideX, (1 - inK) * 26 * S - press * 6 * S);
      g.rotate(slideRot);

      g.fillStyle = '#101722';
      roundRect(g, -cw / 2, -chh / 2, cw, chh, 14 * S);
      g.fill();
      g.strokeStyle = rgba(c, 0.85);
      g.lineWidth = 2.5 * S;
      roundRect(g, -cw / 2, -chh / 2, cw, chh, 14 * S);
      g.stroke();

      // 顶部标题条
      g.fillStyle = rgba(c, 0.16);
      roundRect(g, -cw / 2 + 12 * S, -chh / 2 + 12 * S, cw - 24 * S, 40 * S, 6 * S);
      g.fill();
      g.save();
      g.font = '800 ' + (18 * S) + 'px ' + SB.fontStack('auto');
      g.textAlign = 'left';
      g.textBaseline = 'middle';
      g.fillStyle = rgba('#ffffff', 0.92);
      g.fillText(String(o.label).slice(0, 16), -cw / 2 + 24 * S, -chh / 2 + 32 * S);
      g.restore();

      // 两个卷轴
      var reelY = chh * 0.02;
      var reelR = 34 * S;
      for (var r = 0; r < 2; r++) {
        var rx = (r === 0 ? -1 : 1) * 70 * S;
        g.save();
        g.translate(rx, reelY);
        g.fillStyle = '#0a0f18';
        g.beginPath(); g.arc(0, 0, reelR, 0, Math.PI * 2); g.fill();
        g.strokeStyle = rgba(c, 0.75);
        g.lineWidth = 2 * S;
        g.beginPath(); g.arc(0, 0, reelR, 0, Math.PI * 2); g.stroke();
        g.rotate(spin * 9.5 + r * 0.7);
        g.strokeStyle = rgba('#ffffff', 0.55);
        g.lineWidth = 2.2 * S;
        for (var k = 0; k < 6; k++) {
          var ang = (k / 6) * Math.PI * 2;
          g.beginPath();
          g.moveTo(Math.cos(ang) * reelR * 0.28, Math.sin(ang) * reelR * 0.28);
          g.lineTo(Math.cos(ang) * reelR * 0.82, Math.sin(ang) * reelR * 0.82);
          g.stroke();
        }
        g.beginPath(); g.arc(0, 0, reelR * 0.2, 0, Math.PI * 2); g.fillStyle = rgba(c, 0.9); g.fill();
        g.restore();
      }

      // 底部插口 + 进度
      g.fillStyle = rgba('#000000', 0.5);
      roundRect(g, -cw * 0.34, chh * 0.28, cw * 0.68, 16 * S, 8 * S);
      g.fill();
      g.fillStyle = rgba(c, 0.95);
      roundRect(g, -cw * 0.34, chh * 0.28, cw * 0.68 * clamp(p / 0.7, 0, 1), 16 * S, 8 * S);
      g.fill();

      g.restore();

      // 卡扣闪光
      if (press > 0.02 && press < 0.98) {
        g.save();
        g.globalCompositeOperation = 'lighter';
        var fr = (0.35 + press * 0.9) * 170 * S;
        g.strokeStyle = rgba(a, (1 - press) * (1 - press) * 0.7);
        g.lineWidth = 2.4 * S;
        g.beginPath(); g.arc(0, 10 * S, fr, 0, Math.PI * 2); g.stroke();
        g.restore();
      }

      // 曲名 / 难度
      caption(g, o.label, 150 * S, 40 * S, '#ffffff', { glow: 0.6, glowColor: c });
      caption(g, o.sub, 196 * S, 22 * S, rgba('#c9d3e6', 0.9));

      // UNLOCKED 盖章
      if (stamp > 0.001) {
        var k = SB.ease('outBack', stamp);
        g.save();
        g.translate(0, -132 * S);
        g.rotate(-0.12);
        g.scale(k, k);
        g.globalAlpha = clamp(stamp * 2, 0, 1) * (g.globalAlpha || 1);
        g.strokeStyle = a;
        g.lineWidth = 3 * S;
        roundRect(g, -96 * S, -24 * S, 192 * S, 48 * S, 8 * S);
        g.stroke();
        g.font = '900 ' + (26 * S) + 'px ' + SB.fontStack('auto');
        g.textAlign = 'center';
        g.textBaseline = 'middle';
        g.fillStyle = a;
        g.fillText('UNLOCKED', 0, 1 * S);
        g.restore();
      }
    },

    /* ---------- 扫描解锁 ---------- */
    scan: function (g, o) {
      var S = o.S, p = o.p, c = o.color;
      var boxW = 640 * S, boxH = 300 * S;
      var scanK = clamp((p - 0.08) / 0.62, 0, 1);
      var scanY = -boxH / 2 + boxH * SB.ease('inOutCubic', scanK);
      var done = clamp((p - 0.72) / 0.28, 0, 1);

      g.save();
      g.fillStyle = rgba('#050a12', 0.55);
      roundRect(g, -boxW / 2, -boxH / 2, boxW, boxH, 12 * S);
      g.fill();
      corner(g, -boxW / 2, -boxH / 2, boxW, boxH, 30 * S, 2.5 * S, c, 0.85);
      g.restore();

      // 底下一层暗字
      g.save();
      g.globalAlpha *= 0.22;
      caption(g, o.label, -8 * S, 46 * S, rgba('#ffffff', 0.8));
      g.restore();

      // 扫描线以上的部分（亮的）
      g.save();
      g.beginPath();
      g.rect(-boxW / 2, -boxH / 2, boxW, Math.max(0, scanY + boxH / 2));
      g.clip();
      caption(g, o.label, -8 * S, 46 * S, '#ffffff', { glow: 0.9, glowColor: c });
      caption(g, o.sub, 44 * S, 24 * S, rgba(c, 0.95));
      g.restore();

      // 扫描光带
      if (scanK > 0 && scanK < 1) {
        g.save();
        g.globalCompositeOperation = 'lighter';
        var grd = g.createLinearGradient(0, scanY - 26 * S, 0, scanY + 26 * S);
        grd.addColorStop(0, rgba(c, 0));
        grd.addColorStop(0.5, rgba(c, 0.85));
        grd.addColorStop(1, rgba(c, 0));
        g.fillStyle = grd;
        g.fillRect(-boxW / 2 - 20 * S, scanY - 26 * S, boxW + 40 * S, 52 * S);
        g.strokeStyle = rgba('#ffffff', 0.9);
        g.lineWidth = 1.6 * S;
        g.beginPath();
        g.moveTo(-boxW / 2 - 20 * S, scanY);
        g.lineTo(boxW / 2 + 20 * S, scanY);
        g.stroke();
        g.restore();
      }

      if (done > 0.01) {
        g.save();
        g.globalAlpha *= clamp(done * 1.4, 0, 1);
        g.font = '800 ' + (18 * S) + 'px ' + SB.fontStack('auto');
        g.textAlign = 'center';
        g.textBaseline = 'middle';
        g.fillStyle = o.accent;
        g.fillText('SCAN COMPLETE', 0, boxH / 2 - 26 * S);
        g.restore();
      }
    },

    /* ---------- 进度解锁 ---------- */
    progress: function (g, o) {
      var S = o.S, p = o.p, c = o.color, a = o.accent;
      var bw = 520 * S, bh = 14 * S;
      var k = SB.ease('outExpo', clamp(p / 0.86, 0, 1));
      var flash = clamp((p - 0.86) / 0.14, 0, 1);

      caption(g, o.label, -70 * S, 44 * S, '#ffffff', { glow: 0.7, glowColor: c });

      // 轨道槽
      g.save();
      g.fillStyle = rgba('#ffffff', 0.10);
      roundRect(g, -bw / 2, -bh / 2, bw, bh, bh / 2);
      g.fill();

      // 进度条
      g.globalCompositeOperation = 'lighter';
      g.fillStyle = c;
      roundRect(g, -bw / 2, -bh / 2, Math.max(bh, bw * k), bh, bh / 2);
      g.fill();
      g.shadowColor = c;
      g.shadowBlur = 22 * S;
      g.fill();
      g.restore();

      // 刻度
      g.save();
      g.strokeStyle = rgba('#ffffff', 0.18);
      g.lineWidth = 1 * S;
      for (var i = 0; i <= 10; i++) {
        var x = -bw / 2 + (bw / 10) * i;
        g.beginPath();
        g.moveTo(x, -bh * 1.4);
        g.lineTo(x, -bh * 2.1);
        g.stroke();
      }
      g.restore();

      // 百分比
      g.save();
      g.font = '800 ' + (22 * S) + 'px ' + SB.fontStack('mono');
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillStyle = rgba('#ffffff', 0.9);
      g.fillText(Math.round(k * 100) + '%', 0, 40 * S);
      g.restore();

      // 副标题 / 完成提示
      if (flash > 0.02) {
        g.save();
        g.globalCompositeOperation = 'lighter';
        g.globalAlpha *= (1 - flash) * 0.9;
        g.fillStyle = rgba('#ffffff', 0.85);
        g.fillRect(-960 * S, -540 * S, 1920 * S, 1080 * S);
        g.restore();

        var pk = SB.ease('outBack', flash);
        g.save();
        g.translate(0, 78 * S);
        g.scale(pk, pk);
        g.font = '900 ' + (26 * S) + 'px ' + SB.fontStack('auto');
        g.textAlign = 'center';
        g.textBaseline = 'middle';
        g.fillStyle = a;
        g.fillText('解锁完成 ' + (o.sub || ''), 0, 0);
        g.restore();
      }
    },

    /* ---------- 碎片汇聚 ---------- */
    shards: function (g, o) {
      var S = o.S, p = o.p, c = o.color, a = o.accent;
      var N = 34;
      var gather = clamp((p - 0.05) / 0.6, 0, 1);
      var frameK = clamp((p - 0.42) / 0.42, 0, 1);
      var boxW = 620 * S, boxH = 250 * S;

      for (var i = 0; i < N; i++) {
        var ang = rnd(i, 1) * Math.PI * 2;
        var dist = (0.55 + rnd(i, 2) * 0.75);
        var k = SB.ease('outCubic', clamp((gather - i * 0.012) / 0.55, 0, 1));
        var sx = Math.cos(ang) * dist * 780 * S;
        var sy = Math.sin(ang) * dist * 460 * S;
        var tx = (rnd(i, 3) - 0.5) * boxW * 0.9;
        var ty = (rnd(i, 4) - 0.5) * boxH * 0.85;
        var x = sx + (tx - sx) * k;
        var y = sy + (ty - sy) * k;
        var sz = (11 + rnd(i, 5) * 30) * S * (1 - 0.3 * k);
        var rot = k * (rnd(i, 6) - 0.5) * 6;

        g.save();
        g.translate(x, y);
        g.rotate(rot);
        g.globalAlpha *= (0.35 + 0.65 * k);
        g.fillStyle = i % 3 === 0 ? a : c;
        if (k < 0.9) {
          g.shadowColor = i % 3 === 0 ? a : c;
          g.shadowBlur = 12 * S;
        }
        g.fillRect(-sz / 2, -sz / 2, sz, sz * (0.4 + rnd(i, 7) * 0.8));
        g.restore();
      }

      if (frameK > 0.001) {
        g.save();
        g.globalAlpha *= frameK;
        corner(g, -boxW / 2, -boxH / 2, boxW, boxH, 34 * S, 2.5 * S, c, 0.9);
        caption(g, o.label, -6 * S, 44 * S, '#ffffff', { glow: 0.7, glowColor: c, alpha: frameK });
        caption(g, o.sub, 44 * S, 22 * S, rgba(c, 0.95), { alpha: frameK });
        g.restore();
      }
    },

    /* ---------- 锁链破碎 ---------- */
    chain: function (g, o) {
      var S = o.S, p = o.p, c = o.color, a = o.accent;
      var shake = (p < 0.52 ? Math.sin(o.t * 62) * 6 * S * clamp(p / 0.3, 0, 1) : 0);
      var breakK = clamp((p - 0.5) / 0.5, 0, 1);
      var bw = 150 * S, bh = 118 * S;

      if (breakK < 0.99) {
        g.save();
        g.translate(shake, 0);
        g.globalAlpha *= (1 - clamp(breakK * 1.6, 0, 1));

        // 锁环
        g.strokeStyle = rgba(c, 0.95);
        g.lineWidth = 13 * S;
        g.beginPath();
        g.arc(0, -bh * 0.55, 42 * S, Math.PI, Math.PI * 2);
        g.stroke();
        g.lineWidth = 9 * S;
        g.beginPath();
        g.moveTo(-42 * S, -bh * 0.55);
        g.lineTo(-42 * S, -bh * 0.32);
        g.moveTo(42 * S, -bh * 0.55);
        g.lineTo(42 * S, -bh * 0.32);
        g.stroke();

        // 锁体
        g.fillStyle = '#0d1420';
        roundRect(g, -bw / 2, -bh * 0.32, bw, bh, 14 * S);
        g.fill();
        g.strokeStyle = rgba(c, 0.9);
        g.lineWidth = 3 * S;
        roundRect(g, -bw / 2, -bh * 0.32, bw, bh, 14 * S);
        g.stroke();

        // 锁孔
        g.fillStyle = rgba(c, 0.95);
        g.beginPath();
        g.arc(0, bh * 0.03, 13 * S, 0, Math.PI * 2);
        g.fill();
        g.fillRect(-5 * S, bh * 0.03, 10 * S, 34 * S);

        // 裂纹
        if (p > 0.34) {
          g.strokeStyle = rgba(a, clamp((p - 0.34) / 0.16, 0, 1));
          g.lineWidth = 2.2 * S;
          g.beginPath();
          for (var ci = 0; ci < 5; ci++) {
            var cxx = -bw / 2 + rnd(ci, 11) * bw;
            var cyy = -bh * 0.32 + rnd(ci, 12) * bh;
            g.moveTo(cxx, cyy);
            g.lineTo(cxx + (rnd(ci, 13) - 0.5) * 40 * S, cyy + (rnd(ci, 14) - 0.5) * 40 * S);
            g.lineTo(cxx + (rnd(ci, 15) - 0.5) * 70 * S, cyy + (rnd(ci, 16) - 0.5) * 70 * S);
          }
          g.stroke();
        }
        g.restore();

        // 冲击波
        if (p > 0.46 && p < 0.7) {
          var t2 = (p - 0.46) / 0.24;
          g.save();
          g.globalCompositeOperation = 'lighter';
          g.strokeStyle = rgba(a, (1 - t2) * 0.9);
          g.lineWidth = 5 * S * (1 - t2) + 1;
          g.beginPath();
          g.arc(0, 0, 60 * S + t2 * 320 * S, 0, Math.PI * 2);
          g.stroke();
          g.restore();
        }
      }

      // 碎片飞散
      if (breakK > 0.001) {
        for (var i = 0; i < 12; i++) {
          var k = SB.ease('outQuad', clamp(breakK / 0.8, 0, 1));
          var ang = rnd(i, 21) * Math.PI * 2;
          var dist = (0.3 + rnd(i, 22)) * 520 * S * k;
          var x = Math.cos(ang) * dist;
          var y = Math.sin(ang) * dist + k * k * 120 * S;
          var sz = (8 + rnd(i, 23) * 26) * S * (1 - k * 0.5);
          g.save();
          g.translate(x, y);
          g.rotate(ang + k * (rnd(i, 24) - 0.5) * 9);
          g.globalAlpha *= (1 - k * 0.85);
          g.fillStyle = i % 4 === 0 ? a : c;
          g.fillRect(-sz / 2, -sz / 2, sz, sz * 0.7);
          g.restore();
        }

        var tk = clamp((breakK - 0.25) / 0.6, 0, 1);
        if (tk > 0.01) {
          caption(g, o.label, -10 * S, 44 * S, '#ffffff', { glow: 0.8, glowColor: c, alpha: tk });
          caption(g, o.sub, 40 * S, 22 * S, rgba(c, 0.95), { alpha: tk });
        }
      }
    },

    /* ---------- 快门开启 ---------- */
    shutter: function (g, o) {
      var S = o.S, p = o.p, c = o.color;
      var openK = SB.ease('inOutCubic', clamp(p / 0.62, 0, 1));
      var hw = 680 * S, hh = 420 * S;          // 比舞台大一圈，保证盖满
      var ax = openK * hw;                     // 光圈半宽
      var ay = openK * hh;                     // 光圈半高

      // 先画内容（被四片快门盖住，光圈打开才露出来）
      g.save();
      g.fillStyle = rgba('#000000', 0.35);
      g.fillRect(-hw, -hh, hw * 2, hh * 2);
      caption(g, o.label, -6 * S, 48 * S, '#ffffff', { glow: 0.9, glowColor: c });
      caption(g, o.sub, 46 * S, 24 * S, rgba(c, 0.95));
      g.restore();

      // 四片快门：从四边往里盖，光圈 = 中间那个矩形
      g.save();
      g.fillStyle = '#070b12';
      g.fillRect(-hw, -hh, hw * 2, Math.max(0, hh - ay));          // 上
      g.fillRect(-hw, ay, hw * 2, Math.max(0, hh - ay));           // 下
      g.fillRect(-hw, -hh, Math.max(0, hw - ax), hh * 2);          // 左
      g.fillRect(ax, -hh, Math.max(0, hw - ax), hh * 2);           // 右
      g.restore();

      // 光圈边缘的高光
      if (openK < 0.999 && openK > 0.001) {
        g.save();
        g.globalCompositeOperation = 'lighter';
        g.strokeStyle = rgba(c, 0.8);
        g.lineWidth = 3 * S;
        g.strokeRect(-ax, -ay, Math.max(1, ax * 2), Math.max(1, ay * 2));
        g.restore();
      }

      // 完全打开后的边框角标
      var doneK = clamp((p - 0.55) / 0.45, 0, 1);
      if (doneK > 0.01) {
        g.save();
        g.globalAlpha *= doneK;
        corner(g, -hw * 0.9, -hh * 0.78, hw * 1.8, hh * 1.56, 60 * S, 3 * S, c, 0.8);
        g.restore();
      }
    },

    /* ---------- 环印盖章 ---------- */
    ring: function (g, o) {
      var S = o.S, p = o.p, c = o.color, a = o.accent;
      var closeK = SB.ease('outCubic', clamp(p / 0.6, 0, 1));
      var stampK = clamp((p - 0.55) / 0.45, 0, 1);
      var r1 = (1.9 - 0.9 * closeK) * 120 * S;
      var r2 = (2.6 - 1.7 * closeK) * 120 * S;
      var spin = o.t * 0.7 * (1 - closeK) + closeK * 2.4;

      g.save();
      g.translate(0, 0);

      // 外环刻度
      g.save();
      g.rotate(spin);
      g.strokeStyle = rgba(c, 0.6);
      g.lineWidth = 2 * S;
      for (var i = 0; i < 48; i++) {
        var ang = (i / 48) * Math.PI * 2;
        var len = (i % 4 === 0 ? 16 : 8) * S;
        g.beginPath();
        g.moveTo(Math.cos(ang) * (r2 - len), Math.sin(ang) * (r2 - len));
        g.lineTo(Math.cos(ang) * r2, Math.sin(ang) * r2);
        g.stroke();
      }
      g.restore();

      // 双环
      g.save();
      g.rotate(-spin * 1.6);
      g.strokeStyle = rgba(c, 0.9);
      g.lineWidth = 3 * S;
      g.setLineDash([26 * S, 14 * S]);
      g.beginPath(); g.arc(0, 0, r2, 0, Math.PI * 2); g.stroke();
      g.setLineDash([]);
      g.restore();

      g.strokeStyle = rgba(c, 0.95);
      g.lineWidth = 4 * S;
      g.beginPath(); g.arc(0, 0, r1, 0, Math.PI * 2); g.stroke();

      // 中心徽章
      var bs = SB.ease('outBack', stampK);
      if (stampK > 0.001) {
        g.save();
        g.scale(Math.max(0.001, bs), Math.max(0.001, bs));
        g.fillStyle = rgba('#0b1220', 0.9);
        g.beginPath(); g.arc(0, 0, r1 * 0.82, 0, Math.PI * 2); g.fill();
        g.strokeStyle = rgba(a, 0.9);
        g.lineWidth = 2.5 * S;
        g.beginPath(); g.arc(0, 0, r1 * 0.82, 0, Math.PI * 2); g.stroke();

        if (o.sub) {
          caption(g, o.sub, 4 * S, 40 * S, '#ffffff', { glow: 0.5, glowColor: c });
        } else {
          var sp = String(o.label).split(' ');
          caption(g, sp[sp.length - 1], 4 * S, 40 * S, '#ffffff', { glow: 0.5, glowColor: c });
        }
        g.restore();
      }

      caption(g, o.label, r1 + 54 * S, 24 * S, rgba('#ffffff', 0.9), { alpha: clamp(p / 0.5, 0, 1) });
      g.restore();
    }
  };

  /* ---------- 覆盖层：没有谱面时的提示由 UI 负责，这里不画 ---------- */

  var api = {
    Renderer: Renderer,
    create: function (canvas) { return new Renderer(canvas); },
    NOTE_TH: NOTE_TH,
    GLSL: { vert: VERT, frag: FRAG },
    WEIGHT_UNIFORMS: WEIGHT_UNIFORMS
  };

  return api;
});
