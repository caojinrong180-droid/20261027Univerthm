/* 核心逻辑单元测试：node web/test/core.test.js */
'use strict';

const RC = require('../js/core.js');

let pass = 0;
const fails = [];

function ok(cond, name) {
  if (cond) { pass++; } else { fails.push(name); }
}

function eq(a, b, name) {
  const good = JSON.stringify(a) === JSON.stringify(b);
  if (!good) {
    fails.push(name + '  →  实际 ' + JSON.stringify(a) + ' / 期望 ' + JSON.stringify(b));
  } else {
    pass++;
  }
}

function near(a, b, eps, name) {
  const good = Math.abs(a - b) <= (eps === undefined ? 1e-6 : eps);
  if (!good) fails.push(name + '  →  实际 ' + a + ' / 期望 ' + b);
  else pass++;
}

/* ---------------- 时间换算 ---------------- */

const timing = { bpm: 120, beat_offset: 0 };

eq(RC.formTime(0), '00:00.000', 'formTime(0)');
eq(RC.formTime(64.4), '01:04.400', 'formTime(64.4)');
eq(RC.formTime(6.4), '00:06.400', 'formTime(6.4)');
eq(RC.formTime(-1.5), '-00:01.500', 'formTime 负数');

near(RC.secPerBeat(timing), 0.5, 1e-9, '120BPM 一拍 0.5s');
near(RC.beatToSec(4, timing), 2, 1e-9, '第4拍 = 2s');
near(RC.secToBeat(2, timing), 4, 1e-9, '2s = 第4拍');

const timing2 = { bpm: 150, beat_offset: 1.25 };
near(RC.beatToSec(RC.secToBeat(7.7, timing2), timing2), 7.7, 1e-9, '拍秒往返');

// 吸附：150BPM，1/4 拍 = 0.1s
const timing3 = { bpm: 150, beat_offset: 0 };
near(RC.snapSec(0.93, timing3, 4), 0.9, 1e-9, '吸到 1/4 拍');
near(RC.snapSec(0.12, timing3, 4), 0.1, 1e-9, '吸到 1/4 拍(2)');
near(RC.snapSec(0.35, timing3, 3), 0.4, 1e-9, '吸到 1/3 拍');
near(RC.snapSec(0.93, timing3, 0), 0.9, 1e-9, 'div=0 兜底成 1/4');

/* ---------------- 建谱面 ---------------- */

const c = RC.createChart({});
eq(c.lanes.length, 4, '默认 4 轨');
eq(c.timing.bpm, 150, '默认 BPM');
eq(c.notes.length, 0, '默认没音符');
eq(c.lanes[0].color, '#ffffff', '第一轨默认白色');
eq(c.lanes[0].judge_zone, 'none', '第一轨默认判定区 none');
eq(c.lanes[3].color, '#ffffff', '第四轨也是白色');
eq(c.lanes[3].judge_zone, 'none', '第四轨默认判定区 none');
eq(RC.createChart({ lane_count: 99 }).lanes.length, 16, '轨道数上限 16');
eq(RC.createChart({ lane_count: 0 }).lanes.length, 1, '轨道数下限 1');

/* ---------------- 判定区 ---------------- */

eq(RC.displayColor({ judge_zone: 'none' }), '#ffffff', 'none → 白');
eq(RC.displayColor({ judge_zone: 'left' }), '#b06bff', 'left → 紫');
eq(RC.displayColor({ judge_zone: 'right' }), '#ffd166', 'right → 黄');
eq(RC.displayColor({ judge_zone: 'bogus' }), '#ffffff', '乱写判定区 → 白');
eq(RC.displayColor({}), '#ffffff', '没有判定区字段 → 白');
eq(RC.displayColor({ judge_zone: 'none', color: '#123456' }), '#123456', 'none 时用轨道自己的颜色');
eq(RC.displayColor({ judge_zone: 'left', color: '#123456' }), '#b06bff', 'left 时压过轨道颜色');

eq(RC.laneKeys({ judge_zone: 'none' }).join(''), 'ASDFJKL;', 'none 用 A S D F J K L ;');
eq(RC.laneKeys({ judge_zone: 'left' }).join(''), 'ASDF', 'left 用 A S D F');
eq(RC.laneKeys({ judge_zone: 'right' }).join(''), 'JKL;', 'right 用 J K L ;');
eq(RC.laneKeys({ judge_zone: 'left' }).length, 4, 'left 四个键');
eq(RC.normalizeZone('LEFT'), 'none', '判定区区分大小写，乱写退回 none');
eq(RC.normalizeZone('left'), 'left', '合法值原样返回');

/* ---------------- 音符增删 ---------------- */

const nc = RC.createChart({ lane_count: 4 });
const n1 = RC.addNote(nc, { time: 1.0, lane: 1, type: 'tap' });
const n2 = RC.addNote(nc, { time: 0.5, lane: 2, type: 'hold', duration: 0.75 });
const n3 = RC.addNote(nc, { time: 2.0, lane: 9, type: 'tap' });

eq(nc.notes.length, 3, '加了 3 个音符');
eq(nc.notes.map(n => n.time), [0.5, 1.0, 2.0], '按时间排好序');
eq(n1.id, 1, '第一个 id = 1');
eq(n3.lane, 3, '越界轨道夹到最后一条');
eq(RC.noteEnd(n2), 1.25, 'hold 结束时间');
eq(RC.noteEnd(n1), 1.0, 'tap 结束时间');
near(nc.notes[0].time, 0.5, 1e-9, '时间没被改动');

eq(RC.findNote(nc, n2.id), n2, 'findNote 找得到');
eq(RC.findNote(nc, 999), null, 'findNote 找不到返回 null');
eq(RC.findAt(nc, 1, 1.00001) !== null, true, 'findAt 容差命中');
eq(RC.findAt(nc, 1, 1.2), null, 'findAt 不误命中');

eq(RC.removeNote(nc, n1.id), true, '删除成功');
eq(nc.notes.length, 2, '删完剩 2 个');
eq(RC.removeNote(nc, n1.id), false, '重复删除返回 false');

/* ---------------- 统计 ---------------- */

const st = RC.createChart({ lane_count: 4 });
RC.addNote(st, { time: 0.0, lane: 0, type: 'tap' });
RC.addNote(st, { time: 0.5, lane: 0, type: 'tap' });
RC.addNote(st, { time: 1.0, lane: 1, type: 'hold', duration: 0.5 });
RC.addNote(st, { time: 2.0, lane: 2, type: 'flick' });
RC.addNote(st, { time: 3.0, lane: 3, type: 'mine' });
const counts = RC.countNotes(st);
eq([counts.total, counts.tap, counts.hold, counts.flick, counts.mine], [5, 2, 1, 1, 1], '音符统计');
near(RC.chartDuration(st), 3.0, 1e-9, '谱面时长');
near(RC.chartDuration(RC.createChart()), 0, 1e-9, '空谱面时长 0');

/* ---------------- 轨道数变化 ---------------- */

const lc = RC.createChart({ lane_count: 4 });
RC.addNote(lc, { time: 0, lane: 3, type: 'tap' });
RC.addNote(lc, { time: 0.5, lane: 0, type: 'tap' });
const res = RC.setLaneCount(lc, 2);
eq(res.laneCount, 2, '轨道数改成 2');
eq(res.moved, 1, '有 1 个音符被挪');
eq(lc.notes.map(n => n.lane), [1, 0], '挪到最后一轨（按时间排序）');
eq(lc.lanes.length, 2, '轨道数组跟着变短');
eq(lc.lanes[0].name, 'Lane 1', '改名沿用旧轨道');

// 改轨道数不能把判定区弄丢
const lz = RC.createChart({ lane_count: 2 });
lz.lanes[0].judge_zone = 'left';
lz.lanes[1].judge_zone = 'right';
RC.setLaneCount(lz, 4);
eq(lz.lanes.map(l => l.judge_zone), ['left', 'right', 'none', 'none'], '改轨道数后判定区保留，新轨道是 none');
RC.setLaneCount(lz, 1);
eq(lz.lanes[0].judge_zone, 'left', '轨道减回来判定区还在');

/* ---------------- 判定区读入 / 写出 ---------------- */

const zc = RC.normalize({
  stage: { lane_count: 3 },
  lanes: [
    { name: 'A', judge_zone: 'left' },
    { name: 'B', judge_zone: 'right' },
    { name: 'C', judge_zone: 'BOGUS', color: '#123456' }
  ]
});
eq(zc.chart.lanes.map(l => l.judge_zone), ['left', 'right', 'none'], '读入判定区，乱写退回 none');
eq(zc.chart.lanes.map(l => l.color), ['#ffffff', '#ffffff', '#123456'], '读入颜色');
eq(zc.chart.lanes.map(l => RC.displayColor(l)), ['#b06bff', '#ffd166', '#123456'], '显示色跟着判定区走');

const zout = RC.serialize(zc.chart);
eq(zout.lanes.map(l => l.judge_zone), ['left', 'right', 'none'], '导出带判定区');
eq(RC.normalize(JSON.parse(JSON.stringify(zout))).chart.lanes.map(l => l.judge_zone),
  ['left', 'right', 'none'], '判定区往返不丢');

/* ---------------- 读入容错 ---------------- */

eq(RC.normalize(null).chart, null, 'null 打不开');
eq(RC.normalize([]).chart, null, '数组打不开');
eq(RC.normalize('x').chart, null, '字符串打不开');

const empty = RC.normalize({});
ok(empty.chart !== null, '空对象能读成默认谱面');
eq(empty.chart.lanes.length, 4, '空对象默认 4 轨');
eq(empty.chart.notes.length, 0, '空对象没有音符');

const min = RC.normalize({
  timing: { bpm: 120 },
  stage: { lane_count: 4 },
  notes: [
    { time: 0.0, lane: 0 },
    { time: 0.5, lane: 1 },
    { time: 1.0, lane: 2 },
    { time: 1.5, lane: 3 }
  ]
});
eq(min.chart.notes.length, 4, '最小谱面读出 4 个音符');
eq(min.chart.notes[0].type, 'tap', '缺 type 默认 tap');
eq(min.warnings.length, 0, '最小谱面没有告警');

const messy = RC.normalize({
  timing: { bpm: 120, bpm_events: [{ beat: 0, bpm: 100 }, { beat: 8, bpm: 200 }] },
  stage: { lane_count: 2 },
  notes: [
    { time: -3, lane: 7, type: 'nope' },
    { time: 1, lane: 0, type: 'hold', duration: 0 },
    { time: 2, lane: 1, type: 'hold', duration: -5 },
    'garbage',
    { time: 3, lane: 1, type: 'tap', id: 42 }
  ]
});
eq(messy.chart.notes.length, 4, '脏数据丢掉 1 条');
eq(messy.chart.notes[0].time, 0, '负时间夹到 0');
eq(messy.chart.notes[0].lane, 1, '越界轨道夹住');
eq(messy.chart.notes[0].type, 'tap', '乱写类型当 tap');
eq(messy.chart.notes[1].type, 'tap', 'duration<=0 的 hold 当 tap');
eq(messy.chart.notes[3].id, 42, '合法 id 保留');
ok(messy.warnings.length >= 3, '脏数据给出告警');
eq(messy.chart.timing.bpm, 100, '变速谱面按第一个 BPM 读');

const dup = RC.normalize({
  notes: [
    { time: 1, lane: 0 }, { time: 1, lane: 0 }, { time: 1, lane: 0 }
  ]
});
eq(dup.chart.notes.length, 3, '重复音符都保留');
eq(new Set(dup.chart.notes.map(n => n.id)).size, 3, 'id 自动去重');

/* ---------------- 存读往返 ---------------- */

const rt = RC.createChart({ lane_count: 6 });
rt.meta.title = '往返测试';
rt.meta.artist = '测试';
rt.meta.level = 12;
rt.timing.bpm = 174.5;
rt.timing.beat_offset = 0.37;
rt.audio.offset = -0.05;
rt.lanes[0].judge_zone = 'left';
rt.lanes[1].judge_zone = 'left';
rt.lanes[5].judge_zone = 'right';
rt.lanes[2].x = -33.5;
rt.lanes[2].y = 14;
rt.lanes[2].alpha = 25;
rt.lanes[2].speed = 1.5;
rt.lanes[2].length = -0.5;
rt.lanes[2].rotation = 27.5;
RC.addNote(rt, { time: 0.137, lane: 0, type: 'tap' });
RC.addNote(rt, { time: 1.234, lane: 5, type: 'hold', duration: 0.866 });
RC.addNote(rt, { time: 2.001, lane: 3, type: 'flick' });
RC.addNote(rt, { time: 3.5, lane: 1, type: 'mine' });

const dumped = RC.serialize(rt);
eq(dumped.lanes.length, 6, '导出 6 轨');
eq(dumped.stage.lane_count, 6, '导出 stage 轨道数');

const back = RC.normalize(JSON.parse(JSON.stringify(dumped)));
ok(back.chart !== null, '导出能读回来');

const again = RC.serialize(back.chart);
eq(again, dumped, '序列化往返完全一致');
eq(back.warnings.length, 0, '往返没有告警');

// id 稳定
eq(back.chart.notes.map(n => n.id), rt.notes.map(n => n.id), 'id 往返不变');

// 时间精度：3 位小数
eq(dumped.notes[0].time, 0.137, '时间保留 3 位');

/* ---------------- 轨道参数（坐标 / 透明度 / 流速 / 长度 / 旋转） ---------------- */

const KEYS = ['x', 'y', 'alpha', 'speed', 'length', 'rotation'];

const DEF = [0, 0, 0, 0, 10, 0];   // speed / length 的默认值是 10
const DEF_VALS = [0, 0, 0, 10, 10, 0];

const lp = RC.createChart({ lane_count: 2 });
eq(RC.LANE_NUMS.map(f => f.key), KEYS, '6 个数值字段（坐标算一组 → 5 组）');
eq(KEYS.map(k => lp.lanes[0][k]), DEF_VALS, '新建轨道默认值（流速 10、长度 10）');
eq(KEYS.map(k => lp.lanes[1][k]), DEF_VALS, '第二条轨道也一样');
eq(KEYS.map(k => RC.laneDefaults()[k]), DEF_VALS, 'laneDefaults 跟上');

eq(RC.laneAlpha({ alpha: 0 }), 0, '透明度 0 = 完全隐藏');
eq(RC.laneAlpha({ alpha: 20 }), 0.2, '透明度 20 = 只剩 20%');
eq(RC.laneAlpha({ alpha: 50 }), 0.5, '透明度 50 = 半透明');
eq(RC.laneAlpha({ alpha: 100 }), 1, '透明度 100 = 完全不透明');
eq(RC.laneSpeed({ speed: 0 }), 0, '流速 0 = 停住');
eq(RC.laneSpeed({ speed: 5 }), 0.25, '流速 5 = 0.25×');
eq(RC.laneSpeed({ speed: 10 }), 1, '流速 10 = 1.00×');
eq(RC.laneSpeed({ speed: 15 }), 2.25, '流速 15 = 2.25×');
eq(RC.laneSpeed({ speed: 20 }), 4, '流速 20 = 4.00×');
eq(RC.laneSpeed({ speed: 50 }), 25, '流速 50 = 25.00×');
eq(RC.laneSpeed({ speed: 100 }), 100, '流速 100 = 100.00×');
eq(RC.laneSpeed({ speed: 500 }), 100, '流速超过 100 按 100 算');
eq(RC.laneSpeed({}), 1, '没有 speed 字段按 10 算');
eq(RC.laneLength({ length: 0 }), 0, '长度 0 = 只剩判定线');
eq(RC.laneLength({ length: 10 }), 1, '长度 10 = 标准全长（1.00×）');
eq(RC.laneLength({ length: 50 }), 5, '长度 50 = 5.00×');
eq(RC.laneLength({ length: 100 }), 10, '长度 100 = 10.00×');
eq(RC.laneLength({}), 1, '没有 length 字段按 10 算');
eq(RC.hasLaneParams({ x: 0, y: 0, alpha: 0, speed: 10, length: 10, rotation: 0 }), false, '全默认 = 没改过');
eq(RC.hasLaneParams({ x: 0, y: 0, alpha: 0, speed: 0, length: 10, rotation: 0 }), true, '流速改成 0 也算改过');
eq(RC.hasLaneParams({ x: 1, y: 0 }), true, '有一个不是默认就算改过');

eq(RC.clampLaneNum('alpha', 500), 100, '透明度上限 100');
eq(RC.clampLaneNum('alpha', -5), 0, '透明度下限 0');
eq(RC.clampLaneNum('x', 'abc'), 0, '乱填退回默认 0');
eq(RC.clampLaneNum('x', '12.5'), 12.5, '字符串数字能认');
eq(RC.clampLaneNum('rotation', 999), 999, '旋转 999° 原样保留');
eq(RC.clampLaneNum('rotation', 3600), 3600, '旋转上限 3600°（10 圈）');
eq(RC.clampLaneNum('rotation', 9999), 3600, '旋转超过 3600° 夹住');
eq(RC.clampLaneNum('rotation', -9999), -3600, '旋转下限 -3600°');
eq(RC.clampLaneNum('speed', -9), 0, '流速下限 0');
eq(RC.clampLaneNum('speed', 500), 100, '流速上限 100');
eq(RC.clampLaneNum('speed', 'abc'), 10, '流速的默认值是 10');
eq(RC.clampLaneNum('length', -9), 0, '长度下限 0');
eq(RC.clampLaneNum('length', 500), 100, '长度上限 100');
eq(RC.clampLaneNum('length', 'abc'), 10, '长度的默认值是 10');
eq(RC.clampLaneNum('nope', 5), 0, '不认识的字段返回 0');

const lpr = RC.normalize({
  stage: { lane_count: 2 },
  lanes: [
    { x: 12, y: -8, alpha: 30, speed: 35, length: 65, rotation: 45 },
    {}
  ]
});
eq(KEYS.map(k => lpr.chart.lanes[0][k]), [12, -8, 30, 35, 65, 45], '读入轨道参数');
eq(KEYS.map(k => lpr.chart.lanes[1][k]), DEF_VALS, '缺的字段补默认值');
eq(KEYS.map(k => RC.serialize(lpr.chart).lanes[0][k]), [12, -8, 30, 35, 65, 45], '导出轨道参数');

// 改轨道数不能把参数弄丢
const lpp = RC.createChart({ lane_count: 2 });
lpp.lanes[0].rotation = 30;
lpp.lanes[0].alpha = 40;
RC.setLaneCount(lpp, 5);
eq(lpp.lanes[0].rotation, 30, '改轨道数后旋转保留');
eq(lpp.lanes[0].alpha, 40, '改轨道数后透明度保留');
eq(KEYS.map(k => lpp.lanes[4][k]), DEF_VALS, '新加的轨道是默认值');

/* ---------------- 缓动（PhiEdit 那套） ---------------- */

near(RC.easeAt('linear', 0.5), 0.5, 1e-9, 'linear 0.5');
near(RC.easeAt('inQuad', 0.5), 0.25, 1e-9, 'inQuad 0.5');
near(RC.easeAt('outQuad', 0.5), 0.75, 1e-9, 'outQuad 0.5');
near(RC.easeAt('inOutCubic', 0.5), 0.5, 1e-9, 'inOutCubic 0.5');
near(RC.easeAt('inOutSine', 0.5), 0.5, 1e-9, 'inOutSine 0.5');
near(RC.easeAt('linear', -1), 0, 1e-9, '进度小于 0 夹到 0');
near(RC.easeAt('linear', 2), 1, 1e-9, '进度大于 1 夹到 1');
ok(RC.easeAt('outBack', 0.5) > 1, 'outBack 中途会冲过头');
eq(RC.easeAt('step', 0.5), 0, 'step 中途还是起点值');
eq(RC.easeAt('step', 1), 1, 'step 到终点才跳过去');
near(RC.easeAt('bezier(0.25, 0.1, 0.25, 1)', 0.5), 0.8024, 0.01, 'bezier 自定义曲线');
eq(RC.easeAt('不认识的名字', 0.5), 0.5, '不认识的缓动退回线性');
eq(RC.EASE_NAMES.indexOf('inOutQuad') >= 0, true, '内置缓动表里有 inOutQuad');


/* ---------------- 事件（6 条独立通道） ---------------- */

const ec = RC.createChart({ lane_count: 2 });
const evLane = ec.lanes[0];
eq(RC.EVENT_KEYS.join(','), 'x,y,alpha,rotation,speed,length', '6 条独立参数通道');
eq(RC.ALL_KEYS.join(','), 'x,y,alpha,rotation,speed,length,zone', '事件区一共 7 列（6 个参数 + 判定区）');
eq(Object.keys(evLane.events).length, 7, '新轨道 7 条通道都在');
eq(evLane.events.zone.length, 0, '判定区默认不铺事件（用静态值）');

// 新轨道在起点自带 6 条默认事件（侧栏那套参数输入框就是被它替代的）
eq(RC.hasEvents(evLane), true, '新轨道自带默认事件');
eq(evLane.events.x.length, 1, '每个通道 1 条默认事件');
eq(evLane.events.x[0].start, 0, '默认事件从 0 开始');
eq(evLane.events.speed[0].from, 10, '默认事件的头值 = 轨道默认值（流速 10）');
eq(evLane.events.speed[0].to, 10, '默认事件的尾值也一样，所以画出来不动');
near(RC.laneParamsAt(evLane, 0.2).speed, 10, 1e-9, '默认事件区间的参数还是默认值');
eq(evLane.events.x.length, 1, '每个通道只铺一条');

// 清掉默认事件，后面测纯事件逻辑
for (const k of RC.EVENT_KEYS) evLane.events[k].length = 0;
eq(RC.hasEvents(evLane), false, '清空后没事件');

const e1 = RC.addEvent(evLane, 'x', { start: 1, end: 3, from: 0, to: 100, ease: 'linear' });
eq(e1.id, 1, '清空后 id 从 1 开始发');
eq(evLane.events.x.length, 1, '事件进了 x 通道');
eq(RC.hasEvents(evLane), true, 'hasEvents 判定有事件');
near(RC.laneParamsAt(evLane, 0.5).x, 0, 1e-9, '事件开始前用静态值');
near(RC.laneParamsAt(evLane, 2).x, 50, 1e-9, '事件中点线性插值');
near(RC.laneParamsAt(evLane, 3).x, 100, 1e-9, '事件末尾取尾值');
near(RC.laneParamsAt(evLane, 99).x, 100, 1e-9, '过完事件保持尾值（不回弹）');

// 通道之间互不干涉
RC.addEvent(evLane, 'alpha', { start: 2, end: 4, from: 0, to: 100 });
near(RC.laneParamsAt(evLane, 2).x, 50, 1e-9, 'x 通道不受 alpha 事件影响');
near(RC.laneParamsAt(evLane, 2).alpha, 0, 1e-9, 'alpha 事件刚开始');
near(RC.laneParamsAt(evLane, 3).alpha, 50, 1e-9, 'alpha 在 3s 处走到一半');
near(RC.laneParamsAt(evLane, 3).speed, 10, 1e-9, '没建事件的通道保持静态值');

e1.ease = 'step';
near(RC.laneParamsAt(evLane, 2).x, 0, 1e-9, '换成 step 后中途还是起点值');
e1.ease = 'linear';

eq(RC.findEvent(evLane, 'x', 1), e1, 'findEvent 按通道找得到');
eq(RC.findEvent(evLane, 'y', 1), null, 'id 只在所属通道里有效');
eq(RC.removeEvent(evLane, 'x', 1), true, '删事件成功');
near(RC.laneParamsAt(evLane, 2).x, 0, 1e-9, '删完回到静态值');
eq(RC.removeEvent(evLane, 'x', 1), false, '重复删事件返回 false');

// 同一通道里多条事件按时间排，后面的覆盖前面的
RC.addEvent(evLane, 'y', { start: 5, end: 6, from: 10, to: 20 });
RC.addEvent(evLane, 'y', { start: 2, end: 3, from: 1, to: 2 });
eq(evLane.events.y.map(e => e.start), [2, 5], '同通道按开始时间排好');
near(RC.laneParamsAt(evLane, 2.5).y, 1.5, 1e-9, '取起点最晚的那条事件');
eq(RC.eventAt(evLane, 'y', 1), null, '还没到第一条事件');
eq(RC.eventAt(evLane, 'y', 5.5).start, 5, 'eventAt 找得到当前生效的那条');

// 存读往返带事件
const evd = RC.serialize(ec);
eq(evd.lanes[0].events.y.length, 2, '导出带事件');
eq(evd.lanes[0].events.alpha.length, 1, '每个通道单独存');
eq(evd.lanes[0].events.x, undefined, '空通道不写进 JSON');
const evb = RC.normalize(JSON.parse(JSON.stringify(evd)));
eq(evb.chart.lanes[0].events.y[0].from, 1, '事件头值保住了');
eq(evb.chart.lanes[0].events.y[0].to, 2, '事件尾值保住了');
eq(RC.serialize(evb.chart), evd, '带事件也能完全往返');

// 改轨道数不丢事件
RC.setLaneCount(ec, 4);
eq(ec.lanes[0].events.y.length, 2, '改轨道数后事件还在');
eq(ec.lanes[0].events.alpha.length, 1, '其它通道也在');
eq(ec.lanes[3].events.y.length, 1, '新加的轨道自动铺了默认事件');
eq(ec.lanes[3].events.y[0].start, 0, '新轨道的默认事件也从 0 开始');
eq(ec.lanes[3].events.y[0].from, 0, '新轨道默认事件的头值 = 默认值');

/* ---------------- 判定区（zone 通道） ---------------- */

const ezt = RC.createChart({ lane_count: 2 });
const eztLane = ezt.lanes[0];
eq(RC.zoneAt(eztLane, 0), 'none', '没有 zone 事件时用静态判定区');
eq(RC.displayColorAt(eztLane, 0), '#ffffff', 'none 时用轨道自己的颜色');
eq(eztLane.events.zone.length, 0, '新轨道不会自动铺 zone 事件');

RC.addEvent(eztLane, 'zone', { start: 1, end: 2, from: 0, to: 2 });
eq(RC.zoneAt(eztLane, 0.5), 'none', '事件之前还是 none');
eq(RC.zoneAt(eztLane, 1.5), 'left', '线性插到一半 = left');
eq(RC.zoneAt(eztLane, 2), 'right', '事件末尾 = right');
eq(RC.zoneAt(eztLane, 9), 'right', '事件之后保持 right（不回弹）');
eq(RC.displayColorAt(eztLane, 2), '#ffd166', 'right 是黄色 #ffd166');
eq(RC.displayColorAt(eztLane, 1.5), '#b06bff', 'left 是紫色 #b06bff');
eq(RC.laneParamsAt(eztLane, 2).zone, 2, 'laneParamsAt 也带上 zone 序号');
eq(RC.clampLaneNum('zone', 9), 2, 'zone 值夹到 0~2');
eq(RC.clampLaneNum('zone', -3), 0, 'zone 不吃负数');

eztLane.judge_zone = 'left';
eq(RC.zoneAt(eztLane, 0.5), 'left', '静态值改了以后，没事件的时段跟着变');

const eztJson = JSON.parse(JSON.stringify(RC.serialize(ezt)));
eq((eztJson.lanes[0].events.zone || []).length, 1, 'zone 通道会写进 JSON');
eq(RC.normalize(eztJson).chart.lanes[0].events.zone[0].to, 2, 'zone 事件读得回来');

/* ---------------- 长条流速（holdSpeed） ---------------- */

const hsc = RC.createChart({ lane_count: 2 });
const hsLane = hsc.lanes[0];
eq(RC.holdSpeed(hsLane, 1), 1, '默认流速 10 → 1.00×');

RC.addEvent(hsLane, 'speed', { start: 2, end: 3, from: 10, to: 20 });
near(RC.holdSpeed(hsLane, 2.5), 2.25, 1e-9, '事件进行中：15 → 2.25×');
eq(RC.holdSpeed(hsLane, 3.5), 4, '事件结束后 20 → 4.00×');

// 流速掉到 0：回退到最近的非零流速，长条不会缩没
RC.addEvent(hsLane, 'speed', { start: 5, end: 6, from: 20, to: 0 });
eq(RC.holdSpeed(hsLane, 6.5), 4, '流速变 0 之后回退到上一个非零流速 4.00×');

// 当下是 0，但后面会变成非 0：也用后面那个
const hfc = RC.createChart({ lane_count: 1 });
const hfLane = hfc.lanes[0];
hfLane.speed = 0;
for (const k of RC.ALL_KEYS) hfLane.events[k].length = 0;   // 清掉默认事件
RC.addEvent(hfLane, 'speed', { start: 2, end: 3, from: 0, to: 20 });
eq(RC.holdSpeed(hfLane, 1), 4, '当下 0、后面才变 20 → 用 4.00×');

// 全篇都是 0：退回 1.00×
const hzc = RC.createChart({ lane_count: 1 });
hzc.lanes[0].speed = 0;
for (const k of RC.ALL_KEYS) hzc.lanes[0].events[k].length = 0;
eq(RC.holdSpeed(hzc.lanes[0], 1), 1, '从头到尾都是 0 流速 → 退回 1.00×');

/* ---------------- 曲绘字段 ---------------- */

const cov = RC.createChart({ lane_count: 2 });
eq(cov.meta.cover, '', '新建谱面曲绘为空');
cov.meta.cover = 'cover.png';
eq(RC.serialize(cov).meta.cover, 'cover.png', '导出带上曲绘文件名');
eq(RC.normalize(RC.serialize(cov)).chart.meta.cover, 'cover.png', '读回来曲绘文件名还在');
eq(RC.normalize({}).chart.meta.cover, '', '老谱面没有曲绘字段就补空');

/* 曲绘作者（画师） */
eq(RC.createChart({}).meta.illustrator, '', '新建谱面曲绘作者为空');
const illc = RC.createChart({});
illc.meta.illustrator = 'Yuki';
eq(RC.serialize(illc).meta.illustrator, 'Yuki', '导出带曲绘作者');
eq(RC.normalize(RC.serialize(illc)).chart.meta.illustrator, 'Yuki', '读回来曲绘作者还在');
eq(RC.normalize({}).chart.meta.illustrator, '', '老谱面没有曲绘作者就补空');
eq(RC.normalize({ meta: { illustrator: 123 } }).chart.meta.illustrator, '', '乱写的曲绘作者退回空串');

/* ---------------- CRC32 / ZIP 打包 ---------------- */

eq(RC.crc32(new TextEncoder().encode('123456789')), 0xCBF43926, 'crc32 标准测试向量');
eq(RC.crc32(new Uint8Array(0)), 0, '空数据 crc32 = 0');

const zipBytes = RC.zipStore([
  { name: 'a.txt', data: new TextEncoder().encode('hello') },
  { name: 'b.bin', data: new Uint8Array([1, 2, 3]) }
]);
eq(zipBytes[0], 0x50, 'zip 以 PK 开头');
eq(zipBytes[1], 0x4B, 'zip 以 PK 开头（第二个字节）');

const zlen = zipBytes.length;
const eocd = (zipBytes[zlen - 22] | (zipBytes[zlen - 21] << 8) |
  (zipBytes[zlen - 20] << 16) | (zipBytes[zlen - 19] << 24)) >>> 0;
eq(eocd, 0x06054b50, '末尾是 EOCD 签名');
eq(zipBytes[zlen - 12] | (zipBytes[zlen - 11] << 8), 2, 'EOCD 记录 2 个条目');

const zipText = Buffer.from(zipBytes).toString('latin1');
ok(zipText.indexOf('a.txt') >= 0 && zipText.indexOf('b.bin') >= 0, '两个文件名都写进去了');
ok(zipText.indexOf('hello') >= 0, '文件内容在 zip 里');
ok(zipText.indexOf('PK\u0001\u0002') >= 0, '有中央目录');
ok(RC.zipStore([]).length === 22, '空 zip 只有 22 字节的 EOCD');

/* ---------------- 校验 ---------------- */

const bad = RC.createChart({ lane_count: 4 });
eq(RC.validate(bad).length, 1, '空谱面给一条提示');

const bad2 = RC.createChart({ lane_count: 4 });
RC.addNote(bad2, { time: 1, lane: 0, type: 'tap' });
RC.addNote(bad2, { time: 1, lane: 0, type: 'tap' });
const issues = RC.validate(bad2);
eq(issues.length, 1, '重复音符被校验抓出来');
ok(/重复/.test(issues[0].text), '告警文案提到重复');

const okChart = RC.createChart({ lane_count: 4 });
RC.addNote(okChart, { time: 0, lane: 0, type: 'tap' });
RC.addNote(okChart, { time: 1, lane: 1, type: 'hold', duration: 0.5 });
eq(RC.validate(okChart).length, 0, '正常谱面校验通过');

/* ---------------- zip 读回来（异步） ---------------- */

const enc2 = new TextEncoder();

function runAsyncChecks() {
  return Promise.all([
    RC.zipRead(zipBytes).then((files) => {
      eq(Object.keys(files).length, 2, 'zipRead 读出 2 个文件');
      eq(Buffer.from(files['a.txt']).toString(), 'hello', 'a.txt 内容一致');
      eq(Array.from(files['b.bin']), [1, 2, 3], 'b.bin 内容一致');
    })
  ]).then(() => {
    // 存 → 读 → 再存，跑一遍完整往返
    const chart2 = RC.createChart({ lane_count: 3 });
    chart2.meta.title = '往返';
    chart2.meta.cover = 'c.png';
    chart2.audio.file = 'a.wav';
    RC.addNote(chart2, { time: 1.5, lane: 2, type: 'tap' });
    RC.addEvent(chart2.lanes[1], 'alpha', { start: 1, end: 2, from: 0, to: 100 });

    const jb = enc2.encode(JSON.stringify(RC.serialize(chart2)));
    const zip2 = RC.zipStore([
      { name: 'chart.json', data: jb },
      { name: 'a.wav', data: new Uint8Array([1, 2]) },
      { name: 'c.png', data: new Uint8Array([3, 4]) }
    ]);
    return RC.zipRead(zip2).then((files) => {
      const back = RC.normalize(JSON.parse(Buffer.from(files['chart.json']).toString())).chart;
      eq(back.meta.title, '往返', '谱面从 zip 里读回来标题对');
      eq(back.meta.cover, 'c.png', '曲绘名带回来了');
      eq(back.audio.file, 'a.wav', '音频名带回来了');
      eq(back.notes.length, 1, '音符还在');
      eq(Object.keys(files).length, 3, 'zip 里 3 个文件都在');
    });
  }).then(() => {
    ok(true, 'zipRead 全流程没抛异常');
  }).catch((err) => {
    fails.push('zipRead 抛异常：' + err.message);
  });
}

/* ---------------- 收尾 ---------------- */

runAsyncChecks().then(() => {
  console.log('--- core.test.js ---');
  console.log('pass = ' + pass + ', fail = ' + fails.length);
  if (fails.length) {
    for (const f of fails) console.log('  FAIL: ' + f);
    process.exit(1);
  }
});
