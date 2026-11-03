/* 视觉小说剧本单元测试：node web/test/vn.test.js */
'use strict';

const VN = require('../js/vn.js');

let pass = 0;
const fails = [];

function ok(cond, name) {
  if (cond) pass++;
  else fails.push(name);
}

function eq(actual, expect, name) {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expect);
  if (a === b) pass++;
  else fails.push(name + '  -> actual ' + a + ' / expect ' + b);
}

function near(a, b, eps, name) {
  if (Math.abs(a - b) <= (eps === undefined ? 1e-9 : eps)) pass++;
  else fails.push(name + '  -> actual ' + a + ' / expect ' + b);
}

/* ---------------- 台词 / 旁白判定 ---------------- */

eq(VN.dialogueSplit('Stra：你听见了吗？'), { who: 'Stra', text: '你听见了吗？' }, '普通台词');
eq(VN.dialogueSplit('穹: 走吧'), { who: '穹', text: '走吧' }, '半角冒号');
eq(VN.dialogueSplit('场景：'), null, '没有正文不算台词');
eq(VN.dialogueSplit('她只说了一句话，然后走了：走吧'), null, '名字里不允许标点');
eq(VN.dialogueSplit('这是一句普通的旁白，没有任何冒号'), null, '旁白');
// 冒号前面没有标点的旁白会被误判成说话人，所以留了反斜杠：编辑器里也会给出提示
eq(VN.dialogueSplit('她只说了一句话：走吧').who, '她只说了一句话', '短句 + 冒号会被当成说话人');
eq(VN.parse('\\ 她只说了一句话：走吧').steps[0].op, 'narr', '反斜杠可以强制旁白');

/* ---------------- token / 参数 ---------------- */

eq(VN.splitTokens('"夜晚 的星图" fade=0.8'), ['夜晚 的星图', 'fade=0.8'], '引号保留空格');
eq(VN.readArgs(['x', 'fade=0.5']).pos, ['x'], '位置参数');
eq(VN.readArgs(['x', 'fade=0.5']).kv, { fade: '0.5' }, '键值参数');

/* ---------------- 指令解析 ---------------- */

const SRC = [
  '# 注释行',
  '@bg 黑洞 fade=0.8',
  '@show Stra right scale=90 flip fade=0.5',
  '@move Stra left t=0.6',
  '@hide Stra fade=0.2',
  '@chapter 序章丨一切的开端',
  '* 开篇',
  'Stra：你好。',
  '这是一句旁白',
  '\\ 这里有冒号：但它是旁白',
  '@wait 0.5',
  '@bgm Diffusion volume=60 once',
  '@sfx 点击 volume=30',
  '@shake 8 0.5',
  '@flash #ff0000 0.2',
  '@choice 你怎么想？',
  '- 走近 -> 靠近',
  '- 走开',
  '* 靠近',
  '@jump 收束',
  '@label 收束',
  '@clear fade=0.4',
  '@bgmstop fade=0.5',
  '@end 本章完'
].join('\n');

const p = VN.parse(SRC);

eq(p.errors, [], '样例剧本没有错误');
eq(p.steps.map(s => s.op), [
  'bg', 'show', 'move', 'hide', 'chapter', 'say', 'narr', 'narr',
  'wait', 'bgm', 'sfx', 'shake', 'flash', 'choice', 'jump', 'clear', 'bgmstop', 'end'
], '指令流顺序');

const bg = p.steps[0];
eq(bg.asset, '黑洞', 'bg 素材');
near(bg.fade, 0.8, 1e-9, 'bg 淡化时长');

const show = p.steps[1];
eq(show.pos, 'right', 'show 位置');
near(show.scale, 90, 1e-9, 'show 缩放');
eq(show.flip, true, 'show 镜像');

const hide = p.steps[3];
eq(hide.asset, 'Stra', 'hide 素材');
near(hide.fade, 0.2, 1e-9, 'hide 淡化');

eq(p.steps[4].text, '序章丨一切的开端', '章节标题');

eq(p.steps[5].who, 'Stra', '台词说话人');
eq(p.steps[5].text, '你好。', '台词正文');

eq(p.steps[6].text, '这是一句旁白', '旁白正文');
eq(p.steps[7].text, '这里有冒号：但它是旁白', '反斜杠强制旁白');

const bgm = p.steps[9];
eq(bgm.asset, 'Diffusion', 'bgm 素材');
near(bgm.volume, 0.6, 1e-9, 'bgm 音量');
eq(bgm.loop, false, 'bgm once');

const choice = p.steps[13];
eq(choice.prompt, '你怎么想？', '选择提示语');
eq(choice.options.map(o => o.text), ['走近', '走开'], '选项文本');
eq(choice.options[0].index, p.labelMap['靠近'], '选项指向标签');
eq(choice.options[1].index, 14, '无目标选项 = 接着往下');

eq(p.steps[14].index, p.labelMap['收束'], 'jump 目标下标');
eq(p.labelMap['开篇'], 5, '标签下标');
eq(p.labels.map(l => l.name), ['开篇', '靠近', '收束'], '标签顺序');
eq(p.characters.map(c => c.name), ['Stra'], '角色表');
eq(p.characters[0].count, 1, '角色台词数');

/* ---------------- 中文指令别名 ---------------- */

const A = VN.parse('@背景 教室\n@立绘 穹 左\n@等待 1\n@选择\n- 好\n- 不');
eq(A.errors, [], '中文指令可用');
eq(A.steps.map(s => s.op), ['bg', 'show', 'wait', 'choice'], '中文指令映射');
eq(A.steps[1].pos, 'left', '左 = left');
eq(A.steps[3].options.length, 2, '中文选项');

/* ---------------- 错误 ---------------- */

const E1 = VN.parse('@nope 123');
ok(E1.errors.length === 1 && /不认识的指令/.test(E1.errors[0].message), '未知指令报错');

const E2 = VN.parse('@bg');
ok(E2.errors.length === 1 && /素材名/.test(E2.errors[0].message), '缺参数报错');

const E3 = VN.parse('@jump 不存在');
ok(E3.errors.length === 1 && /不存在/.test(E3.errors[0].message), '未知标签报错');

const E4 = VN.parse('- 孤立选项');
ok(E4.errors.length === 1 && /没有 @choice/.test(E4.errors[0].message), '孤立选项报错');

const E5 = VN.parse('@choice\n\nStra：只有台词');
ok(E5.errors.length === 1 && /没有选项/.test(E5.errors[0].message), '空选择报错');

const E6 = VN.parse('* 重复\n* 重复');
ok(E6.errors.some(e => /重复/.test(e.message)), '重复标签报错');

/* ---------------- 从某一行开始 ---------------- */

eq(VN.indexAtLine(p, 1), 0, '第一行从第 0 步开始');
eq(VN.indexAtLine(p, 8), 5, '第 8 行是台词');
eq(VN.indexAtLine(p, 999), p.steps.length, '越界返回末尾');

/* ---------------- 素材引用次数 ---------------- */

eq(VN.assetUsage(p), { '黑洞': 1, 'Stra': 3, 'Diffusion': 1, '点击': 1 }, '素材引用计数');

/* ---------------- 工程 ---------------- */

const proj = VN.newProject('测试剧情');
proj.script = SRC;
proj.assets = [
  { id: 'a1', name: '黑洞', kind: 'bg', src: 'data:image/png;base64,AA', mime: 'image/png' },
  { id: 'a2', name: 'Stra', kind: 'char', src: 'data:image/png;base64,BB', mime: 'image/png' },
  { id: 'a3', name: 'Diffusion', kind: 'audio', src: 'data:audio/mpeg;base64,CC', mime: 'audio/mpeg' }
];

eq(VN.fileNameOf(proj.assets[0]), '黑洞.png', '素材文件名补扩展名');
eq(VN.fileNameOf({ name: 'bg.jpg', src: 'x', mime: '' }), 'bg.jpg', '已有扩展名不重复加');

const rt = VN.toRuntime(proj, p);
eq(rt.format, 'vnscript', '运行脚本格式标记');
eq(rt.stage, { width: 1280, height: 720 }, '舞台尺寸');
eq(rt.assets.map(a => a.file), ['黑洞.png', 'Stra.png', 'Diffusion.mp3'], '素材清单文件名');
eq(rt.characters[0].name, 'Stra', '导出的角色');
ok(/^#[0-9a-f]{6}$/i.test(rt.characters[0].color), '角色有默认颜色');
eq(rt.script[14].index, p.labelMap['收束'], '导出 jump 下标');
eq(rt.script[13].options[0].index, p.labelMap['靠近'], '导出选项下标');

eq(VN.charColor({ chars: { Stra: { color: '#123456' } } }, 'Stra'), '#123456', '角色自定义颜色');
eq(VN.charColor({ chars: {} }, 'Stra'), VN.charColor({ chars: {} }, 'Stra'), '默认颜色稳定');

const norm = VN.normalizeProject({ name: '  ', script: 5, assets: [null, { name: 'x' }, { name: 'ok', src: 'y', kind: 'zzz' }] });
eq(norm.name, '未命名剧情', '空名字补默认');
eq(norm.script, '', '非法剧本字段清空');
eq(norm.assets.length, 1, '过滤非法素材');
eq(norm.assets[0].kind, 'bg', '未知素材类型回退背景');
eq(norm.settings.textSpeed, 40, '默认打字速度');

const round = VN.parseProject(VN.serializeProject(proj));
eq(round.script, proj.script, '工程序列化往返');
eq(round.assets.length, 3, '素材往返');

eq(VN.wordCount(p), 3 + 6 + 11 + 4, '字数统计（台词+旁白+选项）');

/* ---------------- 结果 ---------------- */

if (fails.length) {
  console.log('FAIL ' + fails.length + ' / ' + (pass + fails.length));
  fails.forEach(f => console.log('  - ' + f));
  process.exit(1);
}
console.log('OK ' + pass + ' checks');
