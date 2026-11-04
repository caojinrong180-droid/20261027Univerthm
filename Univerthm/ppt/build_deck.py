# -*- coding: utf-8 -*-
"""Build the Univerthm defence deck: 16:9, 14 slides, dark-space theme."""
import os
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE

from deck_kit import (HERE, W, H, ML, MR, BG, BG2, PANEL, PANEL2, INK, BODY, MUTED, DIM,
                      PURPLE, LILAC, CYAN, PINK, YELLOW, MINT, FCN, FMONO,
                      slide_bg, rect, hline, vline, arrow, gradient, text,
                      eyebrow, title, footer, picture, shot, panel, chip, kpi,
                      table, notes, fix_slide_type)

DARK = RGBColor(0x05, 0x05, 0x09)
TOTAL = 14


def new_slide(prs, bg=BG):
    s = prs.slides.add_slide(prs.slide_layouts[6])
    slide_bg(s, bg)
    return s


def pill(s, x, y, w, label, color=MINT, h=0.26):
    rect(s, x, y, w, h, fill=color, alpha=14, line=color, lw=0.6, line_alpha=45,
         shape=MSO_SHAPE.ROUNDED_RECTANGLE, adj=0.5)
    text(s, x, y, w, h, label, size=8.5, color=color, bold=True, font=FMONO,
         align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE, ls=1.0)


def sec_label(s, x, y, label, color=PURPLE, w=4.0):
    text(s, x, y, w, 0.24, [[(label, {"spc": 2.0})]], size=8.5, color=color, font=FMONO)


def bullets(s, x, y, w, items, size=10, gap=0.52, color=BODY):
    for i, it in enumerate(items):
        text(s, x, y + i * gap, w, gap, [[("· ", {"color": PURPLE}), (it, {})]],
             size=size, color=color, ls=1.5)


# --------------------------------------------------------------------------- #
prs = Presentation()
prs.slide_width = Inches(W)
prs.slide_height = Inches(H)

# ============================ 01 · cover ==================================== #
s = new_slide(prs)
picture(s, "bg_main_menu.jpg", 0, 0, W, H, crop_left=0.34)
gradient(s, 0, 0, W, H, [(0, DARK, 97), (0.42, DARK, 88), (0.70, DARK, 42), (1, DARK, 14)], angle=0)
gradient(s, 0, H * 0.58, W, H * 0.42, [(0, BG, 0), (1, BG, 94)], angle=90)

text(s, ML, 0.84, 8.0, 0.26,
     [[("南京邮电大学 · 新柚科创营 · “智创经典”设计竞赛", {"spc": 2.2})]],
     size=9.5, color=PURPLE, font=FCN)
text(s, ML, 1.14, 8.0, 0.26, [[("参赛赛道：经典游戏重构与机制创新", {"spc": 1.6})]],
     size=8.5, color=MUTED, font=FCN)

picture(s, "logo.png", 0.78, 1.52, 5.5)
text(s, ML, 3.60, 7.0, 0.4, "《Univerthm 以太微浮》", size=21, color=INK, bold=True, ls=1.2)
text(s, ML, 4.06, 7.0, 0.4, "用节奏对抗静默 —— 一款 Windows 平台的键盘剧情音游",
     size=12.5, color=BODY, ls=1.35)

hline(s, ML, 4.66, 3.4, PURPLE, 55, h=0.014)
text(s, ML, 4.86, 7.6, 1.2, [
    {"runs": "小　队　曹瑾容 · 宋云舒 · 赵琛鑫", "ls": 1.85, "bold": True},
    {"runs": "2026 年 10 月 · α 可玩版：序章 3 曲 + 全系统骨架", "ls": 1.85, "color": MUTED},
    {"runs": "陈述约 5 分钟，之后是实机演示", "ls": 1.85, "color": DIM},
], size=10.5, color=BODY)
notes(s, "各位评委老师好，我们是《Univerthm 以太微浮》项目组，成员是曹瑾容、宋云舒和赵琛鑫。"
         "我们的作品是一款 Windows 平台的键盘剧情音游，申报的是“智创经典”赛道。")

# ============================ 02 · what it is =============================== #
s = new_slide(prs)
eyebrow(s, "01", "WHAT IT IS")
title(s, "先说清楚：这是一款什么样的作品")
text(s, ML, 1.95, 6.5, 0.7, "《Univerthm 以太微浮》是一款 Windows 平台的键盘剧情音游。",
     size=15, color=INK, bold=True, ls=1.5)
bullets(s, ML, 2.78, 6.3, [
    "玩法参照 osu!mania 的轨道音符演奏：音符从上方落向判定线，按键命中。",
    "借鉴 Phigros 的动态判定线：判定线本身可以位移、旋转、淡出。",
    "完成从选曲、演奏、暂停到结算的完整流程，三首正式谱面组成序章。",
], size=10, gap=0.62)
text(s, ML, 4.86, 6.4, 0.8,
     "在此基础上，我们把「父子判定线」和「动态判定区」做成了谱面机制 —— 这是申报的新机制。",
     size=10.5, color=PURPLE, bold=True, ls=1.55)

panel(s, 7.62, 1.95, 4.9, 3.26)
sec_label(s, 7.90, 2.12, "项 目 档 案")
rows = [("平 台", "Windows · Godot 4.7.2 + GDScript"),
        ("内 容", "序章 3 首正式谱 + 剧情档案"),
        ("输 入", "键盘 A S D F / J K L ;"),
        ("小 队", "3 人 · 视觉与框架 / 手感与制谱 / 剧情"),
        ("状 态", "α 可玩版，规则与流程已跑通")]
yy = 2.46
for lab, val in rows:
    text(s, 7.90, yy, 0.60, 0.3, lab, size=8.5, color=DIM, font=FCN, ls=1.2)
    text(s, 8.54, yy - 0.03, 3.70, 0.5, val, size=9, color=BODY, ls=1.35)
    yy += 0.52

hline(s, ML, 5.62, MR - ML, INK, 10)
kpis = [("3", "首正式谱面（序章）", PURPLE),
        ("5", "档判定 · 理论满分 1,010,000", CYAN),
        ("463", "项自动化测试全部通过", MINT),
        ("16,559", "行 GDScript（64 个脚本）", YELLOW)]
for i, (v, lab, c) in enumerate(kpis):
    x = ML + i * ((MR - ML) / 4)
    kpi(s, x, 5.78, 2.75, v, lab, color=c, vsize=23)
    if i:
        vline(s, x - 0.28, 5.80, 0.86, INK, 12)
footer(s, 2)
notes(s, "一句话：以 osu!mania 的轨道演奏为经典玩法参照，借鉴 Phigros 的动态判定线表现，"
         "做完整了选曲、演奏到结算的流程，并在谱面里加入父子判定线和动态判定区。")

# ============================ 03 · scoring map ============================== #
s = new_slide(prs)
eyebrow(s, "02", "SCORING MAP")
title(s, "评分表上的三项，作品分别落在哪")
cards = [
    ("40", "经典游戏核心逻辑复现", CYAN,
     ["轨道音符演奏：短音符 tap、长音符 hold", "五档判定 + 计分：分数只由准确率决定",
      "计时、暂停、重试、结算、逐首解锁"], "P 04 – 06"),
    ("30", "至少一项新机制", PURPLE,
     ["父子判定线：子线继承父线位移与旋转", "动态判定区：左右可行按键随事件切换",
      "两项由同一份谱面事件驱动，画面与判定一致"], "P 07 – 08"),
    ("30", "完整美术风格", PINK,
     ["深空 / 黑洞 / 紫色霓虹 / 切角面板统一四个界面", "立绘、曲绘、过场动效支撑世界观",
      "装饰效果避开正常读谱时段，不干扰操作"], "P 11"),
]
cw = 3.80
for i, (score, head, col, lines, ref) in enumerate(cards):
    x = ML + i * (cw + 0.14)
    rect(s, x, 1.92, cw, 3.62, fill=PANEL, alpha=88, line=col, lw=0.9, line_alpha=32)
    text(s, x + 0.28, 2.06, 1.4, 0.9, score, size=46, color=col, bold=True, font=FMONO, ls=1.0)
    text(s, x + 1.62, 2.28, 1.8, 0.3, "分 / 100", size=9, color=DIM, font=FMONO)
    text(s, x + 0.28, 3.06, cw - 0.5, 0.34, head, size=13, color=INK, bold=True, ls=1.2)
    hline(s, x + 0.28, 3.50, cw - 0.56, col, 40)
    for j, line in enumerate(lines):
        text(s, x + 0.28, 3.66 + j * 0.52, cw - 0.52, 0.52, line, size=8.8, color=BODY, ls=1.45)
    text(s, x + 0.28, 5.10, 2.6, 0.26, [[("详见 " + ref, {"color": col, "size": 8})]],
         size=8, font=FMONO)

text(s, ML, 5.78, MR - ML, 0.7,
     "下面的顺序就按这三块走：先把经典玩法讲清楚，再讲新机制，最后讲美术与技术怎么支撑它。",
     size=10, color=MUTED, ls=1.5)
footer(s, 3)
notes(s, "评分表有三项：经典核心逻辑复现 40 分、至少一项新机制 30 分、完整美术风格 30 分。"
         "后面的顺序就按这三块走，方便老师对表。")

# ============================ 04 · core loop ================================ #
s = new_slide(prs)
eyebrow(s, "03", "CORE LOOP")
title(s, "玩家的一轮循环：选曲 → 演奏 → 结算 → 解锁")
steps = [("选曲", "列表或序章地图，切歌自动试听"),
         ("演奏", "4 轨、五档判定，纯几何舞台"),
         ("结算", "评级 S/A/B/C/D，带 Early / Late"),
         ("解锁", "逐首解锁下一曲"),
         ("掉落", "Stra 的笔记与曲绘进收藏")]
cw, ch, cy = 2.38, 0.60, 1.92
step = (MR - ML - cw) / 4
for i, (name, desc) in enumerate(steps):
    x = ML + i * step
    col = PINK if i == 4 else PURPLE
    rect(s, x, cy, cw, ch, fill=PANEL2, alpha=95, line=col, lw=0.9, line_alpha=40,
         shape=MSO_SHAPE.CHEVRON)
    text(s, x + 0.30, cy, cw - 0.42, ch, name, size=11, color=INK, bold=True,
         anchor=MSO_ANCHOR.MIDDLE, ls=1.1)
    text(s, x + 0.22, cy + 0.72, cw - 0.28, 0.5, desc, size=8.4, color=MUTED, ls=1.4)

shots = [("s_list.jpg", "选曲 · 曲绘 / 难度 / BEST"),
         ("s_fx.jpg", "演奏 · 透明轨道与判定环"),
         ("s_results.jpg", "结算 · 评级与判定统计"),
         ("s_collection.jpg", "解锁 · 收藏品与剧情")]
iw, gap = 2.72, 0.18
for i, (f, cap) in enumerate(shots):
    shot(s, f, ML + i * (iw + gap), 3.34, iw, label=cap, cap_size=8)

panel(s, ML, 5.62, MR - ML, 0.84, fill=PANEL, alpha=85)
text(s, ML + 0.26, 5.62, 11.2, 0.84,
     [[("闭环　", {"color": PURPLE, "bold": True}),
       ("官方成绩只在「正式通关」时写入：自动演示不计成绩、也不掉收藏。所以看别人打，代替不了自己打。",
        {"color": BODY})]],
     size=10, anchor=MSO_ANCHOR.MIDDLE, ls=1.45)
footer(s, 4)
notes(s, "玩家的一轮循环就是这五步。最后一步是我们想强调的：解锁和掉落都只认正式通关，自动演示不算，"
         "所以流程是有推进感的，不是随便看看。")

# ============================ 05 · input & notes ============================ #
s = new_slide(prs)
eyebrow(s, "04", "CLASSIC CORE 1 / 3")
title(s, "经典玩法怎么落地：4 轨、两组按键、两种音符",
      sub="谱面读的是 rchart v3 格式，也支持导入自制谱面（zip 拖进窗口即可）。")
text(s, ML, 2.34, 5.0, 0.24, "左手 A S D F  →  左判定区", size=8.5, color=CYAN, font=FCN)
text(s, 3.62, 2.34, 3.0, 0.24, "右手 J K L ;  →  右判定区", size=8.5, color=YELLOW, font=FCN)
keys = ["A", "S", "D", "F", "J", "K", "L", ";"]
for i, k in enumerate(keys):
    x = ML + i * 0.60 + (0.36 if i >= 4 else 0)
    rect(s, x, 2.64, 0.50, 0.50, fill=PANEL2, alpha=100, line=INK, lw=0.7, line_alpha=22,
         shape=MSO_SHAPE.ROUNDED_RECTANGLE, adj=0.16)
    text(s, x, 2.64, 0.50, 0.50, k, size=13, color=INK, bold=True, font=FMONO,
         align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE, ls=1.0)
    if i == 3:
        vline(s, x + 0.55 + 0.18, 2.60, 0.58, INK, 16)

notes_txt = [("tap · 短音符", "落到判定线时按下就判，一次判定。"),
             ("hold · 长音符", "头判命中后，只要还有任意键按着就算保持；全松才算断。"),
             ("判定区", "通用区任意键都能命中；左区只吃左手键，右区只吃右手键。")]
yy = 3.52
for head, body in notes_txt:
    text(s, ML, yy, 1.6, 0.26, head, size=10, color=INK, bold=True, ls=1.2)
    text(s, ML + 1.66, yy, 4.55, 0.6, body, size=9, color=MUTED, ls=1.5)
    yy += 0.78

text(s, ML, 6.02, 5.7, 0.5,
     [[("HUD　", {"color": PURPLE, "bold": True}),
       ("顶栏进度条 · 左上 Combo · 右上分数与 ACC · 左下曲名 · 右下等级", {"color": MUTED})]],
     size=8.5, ls=1.5)

shot(s, "s_stage.jpg", 6.68, 1.92, 5.82,
     label="实机：轨道背景透明、只画两侧描边；判定线在画面高度 85% 处", cap_size=8)
text(s, 6.68, 5.58, 5.82, 0.7,
     "音符位置按 d = (note.time − t) × base_pps × speedMult 换算，判定与画面读的是同一个 t。",
     size=9, color=MUTED, font=FMONO, ls=1.5)
footer(s, 5)
notes(s, "音游最关键的是按下按键之后，系统给出稳定、看得懂的反馈。"
         "谱面有两种音符：tap 按到就判；hold 头判之后，只要还有任意一个键按着就算保持，全松才算断。")

# ============================ 06 · judgement ================================ #
s = new_slide(prs)
eyebrow(s, "05", "CLASSIC CORE 2 / 3")
title(s, "判定与计分：五个窗口，一条不会骗人的线",
      sub="以音符时刻为 0，单位毫秒；判定窗口可由设置整体缩放（默认 1.0×）。")
x0, axw, ay = 0.95, 6.35, 2.10
ms2x = lambda ms: x0 + (ms + 125) * axw / 250.0
segs = [(-125, -110, PINK), (-110, -70, CYAN), (-70, -40, PURPLE), (-40, 0, LILAC),
        (0, 40, LILAC), (40, 70, PURPLE), (70, 110, CYAN), (110, 125, PINK)]
for a, b, c in segs:
    rect(s, ms2x(a), ay, ms2x(b) - ms2x(a) - 0.006, 0.11, fill=c, alpha=95)
hline(s, x0, ay + 0.13, axw, INK, 18, h=0.012)
for t in (-125, -110, -70, -40, 0, 40, 70, 110, 125):
    vline(s, ms2x(t) - 0.005, ay - 0.04, 0.21, INK, 28)
    text(s, ms2x(t) - 0.35, ay + 0.19, 0.7, 0.2, ("%+d" % t) if t else "0",
         size=8, color=DIM, font=FMONO, align=PP_ALIGN.CENTER, ls=1.0)
for i, (name, wgt, c) in enumerate([("P⁺ / P", "100%", PURPLE),
                                   ("GOOD", "75%", CYAN), ("BAD", "0%", PINK),
                                   ("MISS", "0%", DIM)]):
    lx = x0 + i * 1.60
    rect(s, lx, 2.62, 0.10, 0.10, fill=c, alpha=100)
    text(s, lx + 0.18, 2.54, 1.40, 0.24,
         [[(name, {"color": BODY, "size": 8.4}), ("  " + wgt, {"color": c, "size": 8.4})]],
         size=8, font=FMONO, ls=1.1)

cols = [(0, 1.38, PP_ALIGN.LEFT), (1.42, 1.28, PP_ALIGN.LEFT),
        (2.78, 0.80, PP_ALIGN.LEFT), (3.66, 2.65, PP_ALIGN.LEFT)]
rows = [["判定", "时间窗", "权重", "反馈"],
        ["PERFECT+", "≤ 40 ms", "100%", "紫色判定环"],
        ["PERFECT", "≤ 70 ms", "100%", "紫色判定环"],
        ["GOOD", "70 – 110 ms", "75%", "蓝色判定环"],
        ["BAD", "110 – 125 ms", "0%", "判定线闪红；hold 降半透明"],
        ["MISS", "> 125 ms", "0%", "无特效，音符直接过线"]]
table(s, x0, 3.02, cols, rows, row_h=0.30, size=9.5)

panel(s, x0, 5.12, 6.90, 1.00, fill=PANEL, alpha=95)
text(s, x0 + 0.26, 5.22, 6.4, 0.36,
     [[("SCORE  =  1,000,000 × ΣW / N  +  10,000 × P⁺ / N", {"color": INK, "size": 12})]],
     size=12, font=FMONO, ls=1.1)
text(s, x0 + 0.26, 5.60, 6.4, 0.34,
     "理论满分 1,010,000 · 没有连击加成 · Bad 与 Miss 同样断连",
     size=8.5, color=MUTED, ls=1.2)

shot(s, "s_ring.jpg", 8.02, 1.95, 4.48, label="命中瞬间只在屏幕坐标上画一圈判定环", cap_size=8)
panel(s, 8.02, 4.80, 4.48, 1.32, fill=PANEL, alpha=85)
text(s, 8.20, 4.94, 4.1, 1.1, [
    {"runs": "· Early / Late 分开统计，结算界面单列一行", "ls": 1.55, "size": 8.5},
    {"runs": "· 多押（±20 ms 内 ≥2 颗）外圈叠一层蓝光，辅助读谱", "ls": 1.55, "size": 8.5},
    {"runs": "· 打击音与判定环都不改变轨道本身的亮度", "ls": 1.55, "size": 8.5},
], color=MUTED, size=8.5)
footer(s, 6)
notes(s, "判定分五档，主要时间窗是 40、70、110、125 毫秒。判定结果会更新连击、准确率、分数和 Early/Late。"
         "计分只由准确率决定，没有连击加成，所以分数是可以被解释的。")

# ============================ 07 · clock ==================================== #
s = new_slide(prs)
eyebrow(s, "06", "CLASSIC CORE 3 / 3")
title(s, "判定公平的前提：时间从音频来，不从帧数来")
panel(s, ML, 1.92, 6.15, 2.16, fill=RGBColor(0x09, 0x0A, 0x10), alpha=100, line=INK, line_alpha=14)
text(s, ML + 0.24, 2.00, 4.0, 0.22, "gameplay.gd", size=8.5, color=DIM, font=FMONO)
code = [("func _sample_audio_time() -> float:", INK),
        ("    var pos := player.get_playback_position()", BODY),
        ("    pos += AudioServer.get_time_since_last_mix()", BODY),
        ("    pos -= AudioServer.get_output_latency()", BODY),
        ("    return pos - _chart_offset()", MINT)]
yy = 2.28
for line, col in code:
    text(s, ML + 0.24, yy, 5.8, 0.26, line, size=9.2, color=col, font=FMONO, ls=1.1)
    yy += 0.30
text(s, ML + 0.24, 3.68, 5.7, 0.3, "谱面时间 = 音频时间 − 谱面 offset − 玩家音画偏移",
     size=8.5, color=MUTED, font=FCN, ls=1.2)

facts = [("不按帧计时", "读音频播放位置，再补最近混音时间、减输出延迟。"),
         ("判定与画面同源", "判定器和舞台读同一个 t，看到的和能按中的一致。"),
         ("设备差异可校准", "设置里打开节拍器测偏移，蓝牙耳机也能调到舒服。")]
yy = 4.30
for head, body in facts:
    text(s, ML, yy, 1.7, 0.26, head, size=10, color=INK, bold=True, ls=1.2)
    text(s, ML + 1.75, yy, 4.5, 0.5, body, size=9, color=MUTED, ls=1.5)
    yy += 0.72

shot(s, "s_calib.jpg", 7.00, 1.92, 5.55,
     label="辅助测量：100 BPM、三轻一重，打 5 次取平均写回偏移", cap_size=8)
panel(s, 7.00, 5.46, 5.55, 0.82, fill=PANEL, alpha=85)
text(s, 7.20, 5.56, 5.2, 0.7,
     "不同声卡、蓝牙设备仍会带来差异 —— 这部分我们不靠测试数据，靠玩家自己校准。",
     size=8.5, color=MUTED, ls=1.5)
footer(s, 7)
notes(s, "音游的命门是时钟。我们不按帧计时，而是读音频播放位置，加上最近一次混音到现在的时长，"
         "再减掉输出延迟，最后减掉谱面偏移和玩家自己的音画偏移。")

# ============================ 08 · parent lanes ============================= #
s = new_slide(prs)
eyebrow(s, "07", "NEW MECHANISM 1 / 2")
title(s, "新机制一：父子判定线，轨道能挂到轨道上")
bullets(s, ML, 1.96, 6.0, [
    "子线继承父线的位移与旋转，同时仍能控制自己的透明度、速度、长度。",
    "谱面事件按时间改这些参数，再走缓动过渡，所以运动是连续的、可编排的。",
    "音符位置、长条形状、实际判定位置跟着同一套轨道状态一起变。",
], size=9.8, gap=0.64)
text(s, ML, 3.94, 6.1, 0.9,
     "父链最多 8 层、自动防环。读谱难度是谱师用缓动写给玩家的，不是靠贴图堆出来的演出。",
     size=9.5, color=MUTED, ls=1.55)
panel(s, ML, 4.82, 6.05, 0.84, fill=PANEL, alpha=85)
text(s, ML + 0.22, 4.82, 5.7, 0.84,
     [[("已写进正式谱面　", {"color": MINT, "bold": True}),
       ("第一首《dream of utopia》就含父线关系，现场可以直接演示。", {"color": BODY})]],
     size=9, anchor=MSO_ANCHOR.MIDDLE, ls=1.4)
text(s, ML, 5.86, 5.9, 0.7,
     "演示位：第一首的 30–50 秒段可以先看轨道怎么转，再看左右区怎么换。",
     size=9, color=MUTED, ls=1.5)

shot(s, "s_rot.jpg", 6.92, 1.92, 5.58, label="实机：整条轨道在转，音符与判定线一起跟过去", cap_size=8)
shot(s, "s_speed.jpg", 6.92, 5.14, 2.62, frame=True)
text(s, 9.78, 5.14, 2.75, 1.2,
     "同一张谱里还能同时变速：子线的 speed 与父线的运动互不干扰。",
     size=8.5, color=MUTED, ls=1.5)
footer(s, 8)
notes(s, "第一项新机制：判定线有父子关系。子线继承父线的位移和旋转，但自己的透明度、速度、长度还能单独控制。"
         "这样音符的位置、长条的形状和真正能按中的位置，都跟着同一套轨道状态走。")

# ============================ 09 · dynamic zone ============================= #
s = new_slide(prs)
eyebrow(s, "08", "NEW MECHANISM 2 / 2")
title(s, "新机制二：动态判定区，能按的键也会变")
zones = [("通用区", "任意一组有效键都能命中", INK),
         ("左区", "只有左手 A S D F 能命中", CYAN),
         ("右区", "只有右手 J K L ; 能命中", YELLOW)]
yy = 1.96
for name, body, col in zones:
    panel(s, ML, yy, 6.0, 0.78, fill=PANEL, alpha=88)
    vline(s, ML, yy, 0.78, col, 75, w=0.03)
    text(s, ML + 0.22, yy + 0.10, 1.2, 0.26, name, size=10.5, color=col, bold=True, ls=1.2)
    text(s, ML + 1.55, yy + 0.10, 4.3, 0.26, body, size=9, color=BODY, ls=1.3)
    yy += 0.92

text(s, ML, 4.74, 5.95, 0.6,
     "除了听准节奏，还要看清判定线在哪、哪一组键才有效 —— 读谱之外多了一层挑战。",
     size=9.5, color=MUTED, ls=1.55)
text(s, ML, 5.52, 5.95, 0.6,
     "判定器与画面读同一份事件数据，避免「看到的位置」和「真正能按中的区域」不一致。",
     size=9.5, color=INK, ls=1.55)

shot(s, "s_alpha.jpg", 7.02, 1.92, 5.48,
     label="实机：左区紫、右区金，轨道颜色与可用按键同时切换", cap_size=8)
panel(s, 7.02, 5.34, 5.48, 1.34, fill=RGBColor(0x10, 0x08, 0x16), alpha=95,
      line=PURPLE, line_alpha=40)
text(s, 7.24, 5.44, 5.05, 1.14, [
    {"runs": "我们不说「首创会动的判定线」。", "color": INK, "bold": True, "size": 9.5, "ls": 1.5},
    {"runs": "创新在于把「线的层级运动」和「按键目标的变化」组合成可编排的谱面机制，"
             "两者由同一份事件数据驱动。", "color": MUTED, "size": 8.5, "ls": 1.5},
])
footer(s, 9)
notes(s, "第二项：判定区会换。通用区任意键都能打，左区必须左手、右区必须右手。"
         "我们不声称首创「会动的判定线」，创新点是把线的运动和按键目标的变化组合起来，做成可编排的机制。")

# ============================ 10 · isomorphic =============================== #
s = new_slide(prs)
eyebrow(s, "09", "ENGINEERING DETAIL")
title(s, "谱面在制谱器和实机上是同一套几何")
text(s, ML, 1.90, 5.6, 0.26,
     [[("web/js/editor.js", {"color": CYAN}), ("   →   ", {"color": DIM}),
       ("game/src/game/stage_view.gd", {"color": PURPLE})]], size=9.5, font=FMONO)
pairs = [("computePreviewLayout()", "逻辑尺寸常量"),
         ("laneGeom()", "_lane_geom()"),
         ("drawPreviewNotes()", "_draw_notes()"),
         ("drawLaneJudge()", "_draw_lane_judge()"),
         ("noteQuad() / bandQuad()", "_note_quad()")]
yy = 2.30
for a, b in pairs:
    text(s, ML, yy, 2.45, 0.26, a, size=8.6, color=CYAN, font=FMONO, ls=1.1)
    text(s, ML + 2.52, yy, 0.3, 0.26, "→", size=8.6, color=DIM, font=FMONO, ls=1.1)
    text(s, ML + 2.80, yy, 2.65, 0.26, b, size=8.6, color=PURPLE, font=FMONO, ls=1.1)
    hline(s, ML, yy + 0.28, 5.45, INK, 7)
    yy += 0.38

sec_label(s, ML, 4.30, "硬 约 束")
specs = [("逻辑舞台", "350 × 196.875"), ("判定线 y", "round(H × 0.85) = 167"),
         ("4 轨 lane_w", "30.6（PV_SCALE 1.75）"), ("音符半宽 / 厚", "13.81 / 2.0")]
for i, (k, v) in enumerate(specs):
    xx = ML + (i % 2) * 2.85
    yy2 = 4.60 + (i // 2) * 0.50
    text(s, xx, yy2, 1.1, 0.22, k, size=8, color=DIM, ls=1.1)
    text(s, xx, yy2 + 0.20, 2.6, 0.24, v, size=10.5, color=INK, font=FMONO, ls=1.1)

text(s, ML, 5.78, 5.7, 0.8,
     "谱师在预览窗口里对齐的像素，实机就是同一个像素 —— 不需要「先预览、再实机调」两遍。",
     size=9.5, color=BODY, ls=1.55)

shot(s, "s_stageonly.jpg", 6.72, 1.92, 5.78,
     label="实机：轨道透明、判定线是一条实心圆角横条，和制谱器预览一致", cap_size=8)
text(s, 6.72, 5.56, 5.78, 0.7,
     "这条同构管线让「新增一首曲子」不需要重写判定逻辑，只需要做谱面。",
     size=9, color=MUTED, ls=1.5)
footer(s, 10)
notes(s, "我们把制谱器预览窗口的那套绘制函数逐个搬到了游戏里，同样的线宽、颜色、剔除规则。"
         "好处是谱师看到什么，玩家就看到什么，不用先预览再实机调两遍。")

# ============================ 11 · architecture ============================= #
s = new_slide(prs)
eyebrow(s, "10", "ARCHITECTURE")
title(s, "实现架构：三层分工 + 一条内容管线")
layers = [("界面层", CYAN, 1.88, ["palette", "theme_builder", "ui_kit", "screens ×11"]),
          ("表现层", PURPLE, 2.94, ["stage_view", "gameplay", "stage_post", "story_layers"]),
          ("数据层", MINT, 4.00, ["rhythm_chart", "judge", "chart_source", "story_source", "settings"])]
for name, col, y, mods in layers:
    rect(s, ML, y, 7.50, 0.90, fill=PANEL, alpha=90, line=col, lw=0.8, line_alpha=30)
    text(s, ML + 0.16, y, 1.30, 0.90, name, size=11.5, color=col, bold=True,
         anchor=MSO_ANCHOR.MIDDLE, ls=1.2)
    n = len(mods)
    cw2 = (5.85 - (n - 1) * 0.10) / n
    for i, m in enumerate(mods):
        chip(s, ML + 1.58 + i * (cw2 + 0.10), y + 0.27, cw2, 0.36, m,
             color=BODY, fill=PANEL2, size=8.6)
for i in range(2):
    yy = 2.84 - i * 1.06
    arrow(s, 4.10, yy + 0.05, 4.10, yy - 0.09, color=INK, alpha=35, lw=0.8)

panel(s, 8.60, 1.88, 3.91, 3.02, fill=PANEL, alpha=95, line=PURPLE, line_alpha=35)
text(s, 8.82, 2.02, 3.5, 0.28, "App · autoload", size=11, color=PURPLE, bold=True, font=FMONO)
text(s, 8.82, 2.32, 3.4, 0.24, "设置 · 谱面库 · 本次会话 · 结算数据",
     size=8.5, color=BODY, ls=1.3)
hline(s, 8.82, 2.64, 3.44, INK, 12)
sec_label(s, 8.82, 2.72, "存 档 三 分", color=MUTED, w=3.0)
for i, (f, d) in enumerate([("settings.cfg", "音量 / 偏移 / 玩家名"),
                            ("profile.cfg", "次数 / 平均分 / 通关 / BEST / 已踏入"),
                            ("collection.cfg", "剧情搜集")]):
    yy = 3.00 + i * 0.60
    text(s, 8.82, yy, 3.4, 0.22, f, size=9, color=INK, font=FMONO, bold=True, ls=1.1)
    text(s, 8.82, yy + 0.22, 3.4, 0.22, d, size=8, color=MUTED, ls=1.2)

panel(s, ML, 5.04, MR - ML, 1.42, fill=PANEL, alpha=85)
sec_label(s, ML + 0.22, 5.14, "谱 面 管 线", color=CYAN)
nodes = [("网页制谱器", "editor · core · storyboard"), ("rchart v3", "chart.json + 音频 + 曲绘"),
         ("zip 拖进窗口", "→ user://charts"), ("舞台渲染", "同一套几何公式")]
nw = 2.28
for i, (head, sub) in enumerate(nodes):
    x = ML + 0.22 + i * (nw + 0.42)
    chip(s, x, 5.48, nw, 0.70, "", color=BODY, fill=PANEL2, line=PURPLE)
    text(s, x, 5.58, nw, 0.24, head, size=9.5, color=INK, bold=True,
         align=PP_ALIGN.CENTER, ls=1.1)
    text(s, x, 5.84, nw, 0.22, sub, size=7.8, color=MUTED, font=FMONO,
         align=PP_ALIGN.CENTER, ls=1.1)
    if i < 3:
        arrow(s, x + nw + 0.06, 5.83, x + nw + 0.34, 5.83, color=PURPLE, alpha=80, lw=1.0)
footer(s, 11)
notes(s, "架构是三层：数据层管读谱和判定，表现层管舞台和流程，界面层管颜色和控件。"
         "跨界面状态统一放在 App 里，存档拆成三份，重置成绩不会碰设置。下面这条管线就是内容生产链。")

# ============================ 12 · art & story ============================== #
s = new_slide(prs)
eyebrow(s, "11", "ART & STORY")
title(s, "美术与叙事：深空霓虹统一四个界面")
sec_label(s, ML, 1.90, "色 板")
pal = [("深空底", "#080A0E", BG2), ("紫", "#B06BFF", PURPLE), ("青", "#4CC9F0", CYAN),
       ("粉", "#F72585", PINK), ("黄", "#FFD166", YELLOW), ("薄荷", "#7CF5C1", MINT)]
for i, (name, hexv, col) in enumerate(pal):
    x = ML + (i % 3) * 1.92
    y = 2.16 + (i // 3) * 0.58
    rect(s, x, y, 0.30, 0.30, fill=col, alpha=100, line=INK, lw=0.6, line_alpha=55)
    text(s, x + 0.40, y - 0.02, 1.4, 0.2, name, size=8.5, color=BODY, ls=1.1)
    text(s, x + 0.40, y + 0.16, 1.4, 0.2, hexv, size=7.8, color=DIM, font=FMONO, ls=1.1)

sec_label(s, ML, 3.46, "画 面 统 一")
text(s, ML, 3.74, 5.5, 0.9,
     "主菜单、选曲、结算、收藏共用一套切角面板与霓虹色；黑洞背景与磨砂全部由 shader 实时生成，不依赖 UI 切图。",
     size=9.2, color=MUTED, ls=1.55)
sec_label(s, ML, 4.62, "不 干 扰 读 谱", color=PINK)
text(s, ML, 4.90, 5.5, 0.9,
     "演奏时只保留音符、判定线与命中反馈；立绘、故障效果只出现在非演奏界面。",
     size=9.2, color=MUTED, ls=1.55)
sec_label(s, ML, 5.66, "叙 事 掉 落")
text(s, ML, 5.94, 5.5, 0.9,
     "通关第 N 首，掉第 N 篇 Stra 的笔记；没打通只显示 ???，系统自己防剧透。",
     size=9.2, color=MUTED, ls=1.55)

shot(s, "s_menu.jpg", 6.90, 1.90, 5.62, label="主界面 · 深空霓虹与切角面板", cap_size=8)
shot(s, "s_story.jpg", 6.90, 5.34, 2.70, frame=True)
text(s, 9.86, 5.34, 2.7, 1.1,
     "剧情阅读浮层：背景实时磨砂压暗，读完按 Esc 回地图。",
     size=8.5, color=MUTED, ls=1.5)
footer(s, 12)
notes(s, "美术上我们用深空、黑洞、紫色霓虹和切角面板，把主菜单、选曲、结算、收藏统一成一套。"
         "演奏时把音符和判定线放最前面，装饰效果全部避开正常读谱时段。")

# ============================ 13 · verification ============================= #
s = new_slide(prs)
eyebrow(s, "12", "VERIFICATION")
title(s, "怎么证明它能跑：自动化复核与实际边界")
sec_label(s, ML, 1.88, "2026-11-01 自动化复核")
for i, (v, lab, col) in enumerate([("249", "项核心逻辑测试通过 · 0 失败", CYAN),
                                   ("214", "项流程冒烟通过 · 0 失败", PURPLE),
                                   ("32 / 32", "合成谱面全 P⁺ · 1,010,000", MINT)]):
    x = ML + i * 2.22
    kpi(s, x, 2.12, 2.05, v, lab, color=col, vsize=25)

sec_label(s, ML, 3.06, "自动化测试")
cols = [(0, 2.05, PP_ALIGN.LEFT), (2.10, 4.20, PP_ALIGN.LEFT)]
rows = [("测试", "覆盖内容"),
        ("run_core_tests", "数据层 / 判定 / 读谱容错，headless 单测"),
        ("smoke.tscn", "自动演示通关、几何常量、准确率、失败路径"),
        ("realtime.tscn", "真实音频时钟自检（需窗口 + 声卡）"),
        ("calibration_check", "节拍器 / 早按晚按 / 取平均 / 写回偏移"),
        ("tutorial_check", "教程弹窗按钮、图载入、Esc、记成看过")]
table(s, ML, 3.34, cols, rows, row_h=0.33, size=9)

panel(s, ML, 5.42, 6.35, 1.22, fill=RGBColor(0x16, 0x08, 0x10), alpha=95, line=PINK, line_alpha=40)
text(s, ML + 0.22, 5.52, 5.9, 0.24, [[("测 试 不 能 代 替 什 么", {"color": PINK, "spc": 1.8})]],
     size=8, font=FMONO)
text(s, ML + 0.22, 5.76, 5.9, 0.8,
     "不同键盘、声卡、分辨率下的真实手感仍要人工检查 —— 所以我们保留音画偏移设置，"
     "也把「跨设备验证」写在待办里，而不是写在成果里。",
     size=8.5, color=MUTED, ls=1.5)

text(s, 7.55, 1.88, 4.9, 0.24, [[("截 图 回 归（81 张）", {"spc": 1.8})]],
     size=8.5, color=PURPLE, font=FMONO)
thumbs = ["s_chapter.jpg", "s_list.jpg", "s_results.jpg", "s_pause.jpg", "s_entry.jpg", "s_secret.jpg"]
for i, f in enumerate(thumbs):
    x = 7.55 + (i % 3) * 1.72
    y = 2.16 + (i // 3) * 1.02
    shot(s, f, x, y, 1.62)
text(s, 7.55, 4.32, 4.95, 1.0,
     "tests/shot.gd 会把每个界面自己走一遍并出图。改完 UI 直接看图，不用一张张手点 —— "
     "上面这六张就是它拍的。",
     size=9, color=MUTED, ls=1.55)
text(s, 7.55, 5.34, 4.95, 0.9,
     "还没做完：谱面格式文档、制谱器前端独立发布、BPM 变速。",
     size=9, color=YELLOW, ls=1.5)
footer(s, 13)
notes(s, "比赛报告里记录的是 11 月 1 日的复核：核心逻辑 249 项通过、流程冒烟 214 项通过，"
         "合成谱面 32 个音符全 PERFECT+，拿到理论满分。但这些只证明规则和流程，"
         "不同设备的手感还得人工测，所以我们保留偏移设置。")

# ============================ 14 · team & close ============================= #
s = new_slide(prs)
picture(s, "bg_space.jpg", 0, 0, W, H)
gradient(s, 0, 0, W, H, [(0, DARK, 94), (0.5, DARK, 88), (1, DARK, 94)], angle=0)
gradient(s, 0, H * 0.45, W, H * 0.55, [(0, BG, 0), (1, BG, 80)], angle=90)
eyebrow(s, "13", "TEAM")
title(s, "三块工作，一起交出来")
picture(s, "logo.png", 9.55, 0.80, 2.62)

packs = [("01", "视觉与框架", "深空霓虹界面、动效与过场；框架完善；主界面音乐《Diffusion》原创作曲编曲。", PURPLE),
         ("02", "玩法与内容", "判定手感与游玩流程调试；制谱器调试；三首正式谱面制作。", CYAN),
         ("03", "叙事与材料", "序章剧情与 Stra 的笔记；答辩材料、演示流程与现场准备。", MINT)]
cw = 3.78
for i, (no, head, work, col) in enumerate(packs):
    x = ML + i * (cw + 0.16)
    panel(s, x, 1.88, cw, 1.50, fill=PANEL, alpha=94, line=col, line_alpha=32)
    text(s, x + 0.24, 1.99, 0.6, 0.24, no, size=9, color=col, font=FMONO, bold=True)
    text(s, x + 0.72, 1.96, cw - 0.9, 0.30, head, size=12.5, color=INK, bold=True, ls=1.2)
    text(s, x + 0.24, 2.40, cw - 0.46, 0.86, work, size=8.8, color=MUTED, ls=1.55)

text(s, ML, 3.60, 8.4, 0.3,
     [[("小　队　", {"color": DIM, "size": 9}),
       ("曹瑾容 · 宋云舒 · 赵琛鑫", {"color": BODY, "size": 11, "bold": True}),
       ("　（与报名材料一致）", {"color": DIM, "size": 8.5})]], size=9, ls=1.2)

hline(s, ML, 4.14, MR - ML, INK, 12)
text(s, ML, 4.34, 10.4, 1.2, "听不见的世界里，还有一个拍子。",
     size=34, color=INK, bold=True, ls=1.3)
text(s, ML, 5.44, 9.0, 0.4, "《Univerthm 以太微浮》 α 可玩版 · 2026 年 10 月",
     size=11, color=BODY, ls=1.4)
text(s, ML, 5.96, 10.2, 0.9, [
    {"runs": "接下来的时间留给我们现场跑一遍：选曲、演奏、结算，以及收藏品里的剧情。", "ls": 1.7},
    {"runs": "谢谢各位评委。", "color": PURPLE, "bold": True, "ls": 1.7},
], size=9.8, color=MUTED)
footer(s, 14, "UNIVERTHM  ·  谢谢聆听")
notes(s, "团队三个人一起完成：视觉与框架、玩法与内容、叙事与材料这三块。"
         "作品的部分就讲到这里，下面展示实机运行，谢谢各位评委。")

fix_slide_type(prs)
out = os.path.join(HERE, "Univerthm-以太微浮-答辩.pptx")
prs.save(out)
print("saved", out, os.path.getsize(out))
