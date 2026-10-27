// 验证：放大抖动预设（真浏览器截图，开/关对比）
const fs = require('fs');
const { spawn } = require('child_process');
const path = require('path');
const os = require('os');
const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const PORT = 9421;
const profile = path.join(os.tmpdir(), 'cdp-zoom-' + Date.now());
const page = 'file:///C:/Users/Dy/Desktop/Rhythm/web/storyboard.html?demo=1&t=6';
const child = spawn(CHROME, ['--headless=new', '--remote-debugging-port=' + PORT, '--disable-gpu', '--no-first-run', '--user-data-dir=' + profile, '--window-size=1680,1000', page], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function wsUrl() { for (let i = 0; i < 60; i++) { try { const res = await fetch('http://127.0.0.1:' + PORT + '/json/list'); const l = await res.json(); const t = l.find((x) => x.type === 'page'); if (t) return t.webSocketDebuggerUrl; } catch (e) {} await sleep(300); } throw new Error('no cdp'); }
function connect(url) { return new Promise((resolve, reject) => { const ws = new WebSocket(url); let id = 0; const pending = new Map(); ws.onopen = () => resolve({ ws, send }); ws.onerror = () => reject(new Error('ws')); ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { const p = pending.get(m.id); pending.delete(m.id); m.error ? p.rej(new Error(JSON.stringify(m.error))) : p.res(m.result); } }; function send(method, params) { const mid = ++id; return new Promise((res, rej) => { pending.set(mid, { res, rej }); ws.send(JSON.stringify({ id: mid, method, params: params || {} })); }); } }); }
async function ev(c, expr) { const r = await c.send('Runtime.evaluate', { expression: expr, returnByValue: true }); return r.exceptionDetails ? { err: (r.exceptionDetails.exception && r.exceptionDetails.exception.description) || r.exceptionDetails.text } : r.result.value; }
(async () => {
  try {
    const c = await connect(await wsUrl());
    await c.send('Runtime.enable'); await c.send('Page.enable');
    for (let i = 0; i < 40; i++) { await sleep(250); if (await ev(c, 'typeof window.__RHYTHM_SB__') === 'object') break; }
    await sleep(700);
    const setup = await ev(c, `(function(){
      var API = window.__RHYTHM_SB__, S = API.state;
      var spans = API.spans(), chart = null;
      for (var i = 0; i < spans.length; i++) if (spans[i].kind === 'chart') chart = spans[i];
      S.sceneId = chart.id;
      var sc = API.scene();
      sc.shaders.length = 0;
      var p = window.SB.shaderPreset('zoomShake');
      var okPreset = !!p && !!p.weights && p.weights.zoom === 1 && p.weights.shake === 1;
      window.SB.addShader(sc, 'zoomShake', { start: 0, end: 30, amount: 100, ramp: 0 });
      S.time = chart.start + 3.0;
      S.selKind = 'none'; S.selId = 0;
      API.refresh();
      var stack = window.SB.activeShaders(sc, 3.0);
      return JSON.stringify({ okPreset: okPreset, stack: stack.map(function (s) { return s.preset + ':' + Object.keys(s.weights || {}).join('+'); }) });
    })()`);
    console.log('setup:', setup);
    await sleep(400);
    const rect = JSON.parse(await ev(c, `(function(){ var r = document.getElementById('stage').getBoundingClientRect(); return JSON.stringify({x:r.left,y:r.top,w:r.width,h:r.height}); })()`));
    const shotOn = await c.send('Page.captureScreenshot', { format: 'png', clip: { x: rect.x, y: rect.y, width: rect.w, height: rect.h, scale: 1 } });
    fs.writeFileSync('C:\\Users\\Dy\\Desktop\\Rhythm\\web\\test\\_zoom_on.png', Buffer.from(shotOn.data, 'base64'));
    // 关掉再看
    await ev(c, `(function(){ window.__RHYTHM_SB__.scene().shaders.length = 0; window.__RHYTHM_SB__.refresh(); })()`);
    await sleep(400);
    const shotOff = await c.send('Page.captureScreenshot', { format: 'png', clip: { x: rect.x, y: rect.y, width: rect.w, height: rect.h, scale: 1 } });
    fs.writeFileSync('C:\\Users\\Dy\\Desktop\\Rhythm\\web\\test\\_zoom_off.png', Buffer.from(shotOff.data, 'base64'));
    console.log('shots saved');
    c.ws.close();
  } catch (e) { console.log('FAILED', e.message); }
  finally { child.kill(); await sleep(300); try { fs.rmSync(profile, { recursive: true, force: true }); } catch (e) {} }
})();
