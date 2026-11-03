/* 浏览器端冒烟：真开一个 Chrome，用 CDP 驱动编辑器，验预览 / 解析 / 导出。
 * node web/test/editor.browser.js
 * 没有装 Chrome / Edge 时自动跳过（exit 0）。
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const ROOT = path.join(__dirname, '..');
const PAGE = pathToFileURL(path.join(ROOT, 'vn-editor.html'));
const PORT = 9400 + Math.floor(Math.random() * 200);

const CANDIDATES = [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
];

function pathToFileURL(p) {
  const u = p.replace(/\\/g, '/');
  return 'file:///' + (u.startsWith('/') ? u.slice(1) : u);
}

function findBrowser() {
  for (const c of CANDIDATES) {
    try { if (fs.existsSync(c)) return c; } catch (e) { /* 忽略 */ }
  }
  return null;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function getJson(url) {
  const res = await fetch(url);
  return res.json();
}

async function waitForBrowser() {
  for (let i = 0; i < 80; i++) {
    try {
      const v = await getJson('http://127.0.0.1:' + PORT + '/json/version');
      if (v && v.webSocketDebuggerUrl) return v;
    } catch (e) { /* 还没起来 */ }
    await sleep(250);
  }
  throw new Error('Chrome 调试端口没起来');
}

async function findPage() {
  for (let i = 0; i < 60; i++) {
    const list = await getJson('http://127.0.0.1:' + PORT + '/json/list');
    const page = list.find((t) => t.type === 'page' && /vn-editor\.html/.test(t.url));
    if (page && page.webSocketDebuggerUrl) return page;
    await sleep(250);
  }
  throw new Error('没找到编辑器页面');
}

/* 在页面里跑的主检查：返回一个可以 JSON 化的结果对象 */
function pageScript() {
  return '(' + pageFunc.toString() + ')()';
}

function pageFunc() {
  return (async function () {
    function g(id) { return document.getElementById(id); }
    function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
    function click(el) {
      el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
    }
    function lines(el) { return (el && el.textContent) ? el.textContent : ''; }

    var out = { errors: [], notes: [] };
    var errs = [];
    window.addEventListener('error', function (e) { errs.push(String(e.message)); });
    window.addEventListener('unhandledrejection', function (e) { errs.push('reject:' + String(e.reason)); });

    /* --- 1. 启动 --- */
    if (document.readyState !== 'complete') {
      await new Promise(function (r) { window.addEventListener('load', r, { once: true }); });
    }
    for (var i = 0; i < 150; i++) {
      var ta0 = document.getElementById('script');
      if (ta0 && ta0.value.length > 50) break;
      await sleep(100);
    }
    await sleep(300);
    out.gutterRows = g('gutter').children.length;
    out.assetTiles = g('assetGrid').children.length;
    out.labels = document.querySelectorAll('#outlineList .olabel').length;
    out.issues = document.querySelectorAll('#issueList .issue').length;
    out.chars = document.querySelectorAll('#charList .charrow').length;
    out.helpCmds = document.querySelectorAll('#helpCmds .cmdrow').length;
    out.statusLeft = lines(g('statusLeft'));
    out.scriptValue = g('script').value;
    out.scriptLines = g('script').value.split('\n').length;
    out.sayRows = document.querySelectorAll('#gutter .gl.t-say').length;
    out.saveText = lines(g('statusSave'));

    /* --- 2. 预览：从本行开始 --- */
    click(g('btnFromLine'));
    await sleep(3400);
    out.prev1 = {
      dlgHidden: g('dialog').hidden,
      who: lines(g('who')),
      line: lines(g('dline')),
      sprites: g('sprites').children.length,
      bg: (g('bgA').style.backgroundImage || g('bgB').style.backgroundImage).slice(0, 60),
      left: g('sprites').children[0] ? g('sprites').children[0].style.left : '',
      status: lines(g('pvStatus'))
    };

    /* --- 3. 一路点下去，直到出现选项 --- */
    var hops = [];
    for (var k = 0; k < 10; k++) {
      click(g('stage'));
      await sleep(850);
      var sp = g('sprites').children[0];
      hops.push({
        line: lines(g('dline')).slice(0, 14),
        who: lines(g('who')),
        left: sp ? sp.style.left : '',
        choices: !g('choices').hidden,
        bg: (g('bgA').style.backgroundImage || g('bgB').style.backgroundImage).slice(-24)
      });
      if (!g('choices').hidden) break;
    }
    out.hops = hops;
    out.choiceCount = g('choices').children.length;
    out.choiceTexts = Array.prototype.map.call(g('choices').children, function (b) { return b.textContent; });
    out.choicePrompt = g('choices').children[0] ? g('choices').children[0].textContent : '';

    /* --- 4. 选第一个分支 --- */
    var opts = Array.prototype.filter.call(g('choices').children, function (b) { return b.className === 'choice'; });
    if (opts[0]) click(opts[0]);
    await sleep(900);
    out.branchLine = lines(g('dline'));
    out.branchWho = lines(g('who'));

    /* --- 5. 解析错误提示 --- */
    var keep = g('script').value;
    g('script').value = keep + '\n@nope 123\n';
    g('script').dispatchEvent(new Event('input', { bubbles: true }));
    await sleep(500);
    out.badIssues = Array.prototype.map.call(document.querySelectorAll('#issueList .issue'), function (b) { return b.textContent; });
    out.badGutterErr = document.querySelectorAll('#gutter .gl.t-err').length;

    /* --- 6. 插入工具条 --- */
    g('script').value = keep;
    g('script').dispatchEvent(new Event('input', { bubbles: true }));
    await sleep(300);
    g('script').selectionStart = g('script').selectionEnd = 0;
    var chip = document.querySelector('[data-insert="bg"]');
    click(chip);
    var inserted = g('script').value.split('\n')[0];
    out.insertedFirstLine = inserted;
    out.insertHasBg = /^@bg .+ fade=/.test(inserted);

    /* --- 7. 导出（拦 blob，不真下载） --- */
    var blobs = [];
    var origCreate = URL.createObjectURL;
    URL.createObjectURL = function (b) { blobs.push(b); return origCreate.call(URL, b); };
    HTMLAnchorElement.prototype.click = function () {};

    g('script').value = keep;
    g('script').dispatchEvent(new Event('input', { bubbles: true }));
    await sleep(400);

    click(document.querySelector('[data-export="project"]'));
    await sleep(150);
    click(document.querySelector('[data-export="runtime"]'));
    await sleep(150);
    click(document.querySelector('[data-export="player"]'));
    await sleep(900);

    out.blobCount = blobs.length;
    if (blobs[0]) {
      var pj = JSON.parse(await blobs[0].text());
      out.projectExport = { name: pj.name, assets: pj.assets.length, hasScript: pj.script.indexOf('@bg') >= 0 };
    }
    if (blobs[1]) {
      var rt = JSON.parse(await blobs[1].text());
      out.runtimeExport = {
        format: rt.format,
        steps: rt.script.length,
        assetFiles: rt.assets.slice(0, 3).map(function (a) { return a.file; }),
        jumpIndex: (rt.script.filter(function (s) { return s.op === 'jump'; })[0] || {}).index,
        labels: rt.labels.length,
        firstOp: rt.script[0].op
      };
    }
    if (blobs[2]) {
      var html = await blobs[2].text();
      out.playerExport = {
        doctype: html.slice(0, 15),
        hasData: html.indexOf('var VN = {"title"') >= 0,
        noPlaceholder: html.indexOf('__VN_DATA__') < 0,
        hasStageCss: html.indexOf('.frame') >= 0,
        bytes: html.length
      };
    }

    /* --- 8. 导入素材（造一个真 PNG 塞进 file input） --- */
    function feed(input, name, bytes, mime) {
      var dt = new DataTransfer();
      dt.items.add(new File([bytes], name, { type: mime }));
      input.files = dt.files;
      input.dispatchEvent(new Event('change', { bubbles: true }));
    }
    var png = Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='), function (c) { return c.charCodeAt(0); });
    feed(g('fileInput'), 'bg_test.png', png, 'image/png');
    await sleep(1200);
    var tiles = g('assetGrid').children;
    out.importCount = tiles.length;
    out.importNames = Array.prototype.map.call(tiles, function (n) {
      var el = n.querySelector('.aname');
      return el ? el.textContent : '';
    });

    /* --- 9. 改名（剧本引用跟着改） --- */
    window.prompt = function () { return '测试背景'; };
    window.confirm = function () { return true; };
    var last = g('assetGrid').children[g('assetGrid').children.length - 1];
    click(last);
    await sleep(200);
    var renameBtn = Array.prototype.find.call(g('assetDetail').querySelectorAll('button'), function (b) {
      return b.textContent === '改名';
    });
    if (renameBtn) click(renameBtn);
    await sleep(300);
    out.renamed = Array.prototype.map.call(g('assetGrid').children, function (n) {
      var el = n.querySelector('.aname');
      return el ? el.textContent : '';
    });

    /* --- 10. 删除刚导入的素材（它仍然处于选中态） --- */
    await sleep(200);
    var delBtn = Array.prototype.find.call(g('assetDetail').querySelectorAll('button'), function (b) {
      return b.textContent === '删除';
    });
    if (delBtn) click(delBtn);
    await sleep(400);
    out.afterDelete = g('assetGrid').children.length;

    /* --- 11. 打开导出的工程（拖回来自动读） --- */
    if (blobs[0]) {
      var text = await blobs[0].text();
      feed(g('projInput'), 'back.vnproj.json', text, 'application/json');
      await sleep(1200);
      out.reopened = {
        scriptHasBg: g('script').value.indexOf('@bg 黑洞') >= 0,
        name: g('projName').value,
        tiles: g('assetGrid').children.length,
        steps: g('statusLeft').textContent
      };
    }

    out.errors = errs;
    return out;
  })();
}

async function main() {
  const browser = findBrowser();
  if (!browser) {
    console.log('SKIP 没找到 Chrome / Edge，跳过浏览器冒烟');
    return 0;
  }

  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'vn-smoke-'));
  const args = [
    '--headless=new',
    '--disable-gpu',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-extensions',
    '--autoplay-policy=no-user-gesture-required',
    '--window-size=1600,1000',
    '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + profile,
    PAGE
  ];
  const child = spawn(browser, args, { stdio: 'ignore', windowsHide: true });

  let code = 0;
  try {
    const version = await waitForBrowser();
    const page = await findPage();
    const ws = new WebSocket(page.webSocketDebuggerUrl);
    await new Promise((res, rej) => {
      ws.addEventListener('open', res, { once: true });
      ws.addEventListener('error', rej, { once: true });
    });

    let seq = 0;
    const waiting = new Map();
    const exceptions = [];
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.id && waiting.has(msg.id)) {
        waiting.get(msg.id)(msg);
        waiting.delete(msg.id);
        return;
      }
      if (msg.method === 'Runtime.exceptionThrown') {
        exceptions.push(msg.params.exceptionDetails.text + ' ' +
          (msg.params.exceptionDetails.exception && msg.params.exceptionDetails.exception.description || ''));
      }
    });

    function send(method, params) {
      return new Promise((resolve) => {
        const id = ++seq;
        waiting.set(id, resolve);
        ws.send(JSON.stringify({ id, method, params: params || {} }));
      });
    }

    await send('Runtime.enable');
    await send('Log.enable');

    // 刚连上时页面可能还在导航，执行上下文会被销毁 —— 先等它 load 完
    for (let i = 0; i < 120; i++) {
      const probe = await send('Runtime.evaluate', {
        expression: 'document.readyState + "|" + location.href',
        returnByValue: true
      });
      const val = probe.result && probe.result.result && probe.result.result.value;
      if (val && /^complete\|.*vn-editor\.html/.test(val)) break;
      await sleep(150);
    }

    let res = null;
    for (let attempt = 0; attempt < 3; attempt++) {
      res = await send('Runtime.evaluate', {
        expression: pageScript(),
        awaitPromise: true,
        returnByValue: true,
        timeout: 45000
      });
      const err = res.error && res.error.message;
      if (!err || !/context was destroyed/i.test(err)) break;
      await sleep(400);
    }

    const outcome = res.result || {};
    if (outcome.exceptionDetails) {
      console.log('FAIL 页面脚本抛异常：', JSON.stringify(outcome.exceptionDetails).slice(0, 600));
      code = 1;
    } else if (!outcome.result) {
      console.log('FAIL evaluate 返回异常：', JSON.stringify(res).slice(0, 600));
      code = 1;
    } else {
      const out = outcome.result.value || {};
      code = report(out, exceptions);
    }
    ws.close();
    void version;
  } catch (err) {
    console.log('FAIL ' + (err && err.message || err));
    code = 1;
  } finally {
    try { child.kill(); } catch (e) { /* 忽略 */ }
    await sleep(300);
    try { fs.rmSync(profile, { recursive: true, force: true }); } catch (e) { /* 忽略 */ }
  }
  process.exitCode = code;
}

let pass = 0;
const fails = [];

function ok(cond, name, extra) {
  if (cond) pass++;
  else fails.push(name + (extra === undefined ? '' : '  -> ' + JSON.stringify(extra)));
}

function report(out, exceptions) {
  ok((out.gutterRows || 0) >= 30, '行号渲染', out.gutterRows);
  ok(out.gutterRows === out.scriptLines, '行号数量 = 剧本行数', [out.gutterRows, out.scriptLines]);
  ok(out.assetTiles === 11, '示例素材 11 个', out.assetTiles);
  ok(out.labels === 4, '标签 4 个', out.labels);
  ok(out.chars === 1, '角色 1 个', out.chars);
  ok(out.helpCmds >= 18, '语法表有内容', out.helpCmds);
  ok(/指令 24/.test(out.statusLeft || ''), '状态栏统计', out.statusLeft);
  ok((out.sayRows || 0) >= 4, '台词行有标记', out.sayRows);

  const p1 = out.prev1 || {};
  ok(p1.dlgHidden === false, '预览：对话框出现', p1);
  ok(p1.who === 'Stra', '预览：说话人', p1.who);
  ok(/你听见了吗/.test(p1.line || ''), '预览：第一句台词', p1.line);
  ok(p1.sprites === 1, '预览：立绘出现', p1.sprites);
  ok(/menu_black_hole/.test(p1.bg || ''), '预览：背景换上', p1.bg);
  ok(p1.left === '50%', '预览：立绘在中间', p1.left);

  const hops = out.hops || [];
  const moved = hops.find((h) => h.left === '77%');
  ok(!!moved, '预览：@move 把立绘挪到右边', hops.map((h) => h.left));
  ok(hops.some((h) => /menu_deep_space/.test(h.bg || '')), '预览：中间换了背景', hops.map((h) => h.bg));
  ok(out.choiceCount >= 3, '预览：选项出现（含提示语）', out.choiceCount);
  ok((out.choiceTexts || []).some((t) => /那就弹给我们听/.test(t)), '预览：选项文本', out.choiceTexts);
  ok(/跟紧我/.test(out.branchLine || ''), '预览：选项跳转生效', out.branchLine);
  ok(out.branchWho === 'Stra', '预览：分支里名字板还在', out.branchWho);

  ok((out.badIssues || []).some((t) => /不认识的指令/.test(t)), '解析：坏指令有提示', out.badIssues);
  ok((out.badGutterErr || 0) >= 1, '解析：错误行有红点', out.badGutterErr);

  ok(out.insertHasBg === true, '插入：@bg 片段', out.insertedFirstLine);

  ok(out.blobCount === 3, '导出：三个文件', out.blobCount);
  const pe = out.projectExport || {};
  ok(pe.assets === 11 && pe.hasScript, '导出工程可回读', pe);
  const re = out.runtimeExport || {};
  ok(re.format === 'vnscript' && re.steps === 24, '导出运行脚本', re);
  ok((re.assetFiles || []).every((f) => /\.[a-z0-9]+$/.test(f)), '导出素材文件名带扩展名', re.assetFiles);
  ok(typeof re.jumpIndex === 'number' && re.jumpIndex > 0, '导出跳转下标已解析', re.jumpIndex);
  ok(re.labels === 4, '导出标签', re.labels);
  const ple = out.playerExport || {};
  ok(/<!DOCTYPE html>/.test(ple.doctype || ''), '播放器：DOCTYPE', ple.doctype);
  ok(ple.hasData === true && ple.noPlaceholder === true, '播放器：数据已注入', ple);
  ok(ple.bytes > 4000, '播放器：体积正常', ple.bytes);

  ok(out.importCount === 12, '导入素材进了素材库', out.importCount);
  ok((out.importNames || []).indexOf('bg_test') >= 0, '导入后素材名正确', (out.importNames || []).slice(-2));
  ok((out.renamed || []).indexOf('测试背景') >= 0, '素材改名生效', (out.renamed || []).slice(-2));
  ok(out.afterDelete === 11, '删除素材生效', out.afterDelete);
  const ro = out.reopened || {};
  ok(ro.scriptHasBg === true && ro.tiles === 11, '导出的工程能重新打开', ro);
  ok(/指令 24/.test(ro.steps || ''), '重新打开的剧本解析正确', ro.steps);

  ok((out.errors || []).length === 0, '页面无 JS 错误', out.errors);
  ok((exceptions || []).length === 0, 'CDP 无未捕获异常', exceptions);

  if (fails.length) {
    console.log('FAIL ' + fails.length + ' / ' + (pass + fails.length));
    fails.forEach((f) => console.log('  - ' + f));
    return 1;
  }
  console.log('OK ' + pass + ' checks');
  return 0;
}

main().catch((e) => {
  console.log('FAIL ' + (e && e.stack || e));
  process.exitCode = 1;
});
