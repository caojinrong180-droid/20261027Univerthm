# -*- coding: utf-8 -*-
"""Shared visual kit for the Univerthm defence deck."""
import os
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.oxml.ns import qn
from lxml import etree

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "assets")

# ---- palette ---------------------------------------------------------------
BG      = RGBColor(0x07, 0x08, 0x0C)
BG2     = RGBColor(0x0B, 0x0C, 0x12)
PANEL   = RGBColor(0x11, 0x13, 0x1C)
PANEL2  = RGBColor(0x16, 0x18, 0x24)
INK     = RGBColor(0xF2, 0xF3, 0xF7)
BODY    = RGBColor(0xC3, 0xC7, 0xD4)
MUTED   = RGBColor(0x82, 0x87, 0x9B)
DIM     = RGBColor(0x5A, 0x5F, 0x72)
PURPLE  = RGBColor(0xB0, 0x6B, 0xFF)
LILAC   = RGBColor(0xD9, 0xB3, 0xFF)
CYAN    = RGBColor(0x4C, 0xC9, 0xF0)
PINK    = RGBColor(0xF7, 0x25, 0x85)
YELLOW  = RGBColor(0xFF, 0xD1, 0x66)
MINT    = RGBColor(0x7C, 0xF5, 0xC1)

FCN  = "Microsoft YaHei"
FMONO = "Consolas"

W, H = 13.333, 7.5
ML = 0.82
MR = 12.51
BODY_TOP = 1.95


# ---- low level -------------------------------------------------------------
def _alpha(color_el, pct):
    a = etree.SubElement(color_el, qn("a:alpha"))
    a.set("val", str(int(pct * 1000)))


def _srgb(parent):
    sf = etree.SubElement(parent, qn("a:solidFill"))
    clr = etree.SubElement(sf, qn("a:srgbClr"))
    return clr


def slide_bg(slide, color=BG):
    fill = slide.background.fill
    fill.solid()
    fill.fore_color.rgb = color


def rect(slide, x, y, w, h, fill=None, alpha=100, line=None, lw=0.75,
         shape=MSO_SHAPE.RECTANGLE, line_alpha=100, dash=None, adj=None):
    shp = slide.shapes.add_shape(shape, Inches(x), Inches(y), Inches(w), Inches(h))
    shp.shadow.inherit = False
    if adj is not None:
        try:
            shp.adjustments[0] = adj
        except Exception:
            pass
    if fill is None:
        shp.fill.background()
    else:
        shp.fill.solid()
        shp.fill.fore_color.rgb = fill
        if alpha < 100:
            spPr = shp.fill._xPr
            clr = spPr.find(qn("a:solidFill"))[0]
            _alpha(clr, alpha)
    if line is None:
        shp.line.fill.background()
    else:
        shp.line.color.rgb = line
        shp.line.width = Pt(lw)
        if line_alpha < 100 or dash:
            ln = shp.line._get_or_add_ln()
            if line_alpha < 100:
                clr = ln.find(qn("a:solidFill"))[0]
                _alpha(clr, line_alpha)
            if dash:
                d = etree.SubElement(ln, qn("a:prstDash"))
                d.set("val", dash)
    shp.text_frame.word_wrap = True
    return shp


def hline(slide, x, y, w, color=DIM, alpha=45, h=0.012):
    return rect(slide, x, y, w, h, fill=color, alpha=alpha)


def vline(slide, x, y, h, color=DIM, alpha=40, w=0.012):
    return rect(slide, x, y, w, h, fill=color, alpha=alpha)


def arrow(slide, x1, y1, x2, y2, color=PURPLE, alpha=100, lw=1.0, dash=None):
    conn = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT,
                                      Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    conn.line.color.rgb = color
    conn.line.width = Pt(lw)
    ln = conn.line._get_or_add_ln()
    if alpha < 100:
        clr = ln.find(qn("a:solidFill"))[0]
        _alpha(clr, alpha)
    if dash:
        d = etree.SubElement(ln, qn("a:prstDash"))
        d.set("val", dash)
    tail = etree.SubElement(ln, qn("a:tailEnd"))
    tail.set("type", "triangle")
    tail.set("w", "med")
    tail.set("len", "med")
    return conn


def gradient(slide, x, y, w, h, stops, angle=0):
    """stops: [(pos0..1, RGBColor, alpha0..100), ...]"""
    shp = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    shp.shadow.inherit = False
    shp.line.fill.background()
    spPr = shp._element.spPr
    for tag in ("a:solidFill", "a:noFill", "a:gradFill", "a:pattFill", "a:blipFill"):
        el = spPr.find(qn(tag))
        if el is not None:
            spPr.remove(el)
    grad = etree.Element(qn("a:gradFill"))
    grad.set("rotWithShape", "1")
    gsLst = etree.SubElement(grad, qn("a:gsLst"))
    for pos, color, a in stops:
        gs = etree.SubElement(gsLst, qn("a:gs"))
        gs.set("pos", str(int(pos * 100000)))
        # a gradient stop holds the colour element directly, not inside a:solidFill
        clr = etree.SubElement(gs, qn("a:srgbClr"))
        clr.set("val", "%02X%02X%02X" % (color[0], color[1], color[2]))
        if a < 100:
            _alpha(clr, a)
    lin = etree.SubElement(grad, qn("a:lin"))
    lin.set("ang", str(int(angle * 60000)))
    lin.set("scaled", "0")
    # fill must sit before a:ln in spPr, otherwise strict consumers drop the shape
    ln = spPr.find(qn("a:ln"))
    if ln is not None:
        ln.addprevious(grad)
    else:
        spPr.append(grad)
    return shp


def fix_slide_type(prs, kind="screen16x9"):
    """python-pptx leaves type='screen4x3' on p:sldSz; some renderers trust it."""
    sldSz = prs._element.find(qn("p:sldSz"))
    if sldSz is not None:
        sldSz.set("type", kind)


# ---- text ------------------------------------------------------------------
def _run(p, text, size, color, bold, font, spc, italic=False):
    r = p.add_run()
    r.text = text
    f = r.font
    f.size = Pt(size)
    f.bold = bold
    f.italic = italic
    f.color.rgb = color
    f.name = font
    rPr = r._r.get_or_add_rPr()
    for tag in ("a:ea", "a:cs"):
        el = rPr.find(qn(tag))
        if el is None:
            el = etree.SubElement(rPr, qn(tag))
        el.set("typeface", font)
    if spc:
        rPr.set("spc", str(int(spc * 100)))
    return r


def text(slide, x, y, w, h, paras, size=12, color=BODY, bold=False, font=FCN,
         align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, ls=1.3, wrap=True):
    """paras: str | list of str | list of dict(runs=..., size=, color=, bold=, font=,
    space_before=, space_after=, ls=, align=, spc=)"""
    box = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = box.text_frame
    tf.word_wrap = wrap
    tf.margin_left = 0
    tf.margin_right = 0
    tf.margin_top = 0
    tf.margin_bottom = 0
    tf.vertical_anchor = anchor
    if isinstance(paras, str):
        paras = [paras]
    first = True
    for item in paras:
        d = item if isinstance(item, dict) else {"runs": item}
        p = tf.paragraphs[0] if first else tf.add_paragraph()
        first = False
        p.alignment = d.get("align", align)
        p.line_spacing = d.get("ls", ls)
        if d.get("space_before"):
            p.space_before = Pt(d["space_before"])
        if d.get("space_after"):
            p.space_after = Pt(d["space_after"])
        runs = d.get("runs", "")
        if isinstance(runs, str):
            runs = [(runs, {})]
        for txt, sty in runs:
            _run(p, txt,
                 sty.get("size", d.get("size", size)),
                 sty.get("color", d.get("color", color)),
                 sty.get("bold", d.get("bold", bold)),
                 sty.get("font", d.get("font", font)),
                 sty.get("spc", d.get("spc", 0)),
                 sty.get("italic", False))
    return box


# ---- composite pieces ------------------------------------------------------
def eyebrow(slide, no, label, color=PURPLE):
    text(slide, ML, 0.53, 7.0, 0.26,
         [[(no + "   ", {"color": color, "bold": True, "spc": 2.2}),
           (label, {"color": color, "spc": 2.2})]],
         size=9.5, color=color, font=FMONO)


def title(slide, txt, sub=None, size=29):
    text(slide, ML - 0.02, 0.80, 11.6, 0.66, txt, size=size, color=INK, bold=True, ls=1.12)
    hline(slide, ML, 1.62, MR - ML, INK, 10)
    if sub:
        text(slide, ML, 1.66, 11.0, 0.3, sub, size=10, color=MUTED, ls=1.2)


def footer(slide, page, section="UNIVERTHM  ·  参赛答辩", total=14):
    text(slide, ML, 7.02, 6.0, 0.24,
         [[(section, {"color": DIM, "spc": 1.4})]], size=8, font=FMONO)
    text(slide, MR - 1.4, 7.02, 1.4, 0.24,
         [[(("%02d" % page) + " / %d" % total, {"color": DIM, "bold": True})]],
         size=8.5, font=FMONO, align=PP_ALIGN.RIGHT)


def picture(slide, name, x, y, w, h=None, crop_left=0.0, crop_right=0.0):
    path = name if os.path.isabs(name) else os.path.join(ASSETS, name)
    if h is None:
        from PIL import Image
        iw, ih = Image.open(path).size
        h = w * ih / iw
    pic = slide.shapes.add_picture(path, Inches(x), Inches(y), Inches(w), Inches(h))
    if crop_left:
        pic.crop_left = crop_left
    if crop_right:
        pic.crop_right = crop_right
    return pic


def shot(slide, name, x, y, w, h=None, label=None, frame=True, cap_color=MUTED, cap_size=8.5):
    """Screenshot panel with a hairline frame and an optional caption underneath."""
    pic = picture(slide, name, x, y, w, h)
    h = pic.height / 914400.0
    if frame:
        rect(slide, x, y, w, h, fill=None, line=INK, lw=0.75, line_alpha=22)
    if label:
        text(slide, x, y + h + 0.08, w, 0.22, label, size=cap_size, color=cap_color, ls=1.1)
    return pic


def panel(slide, x, y, w, h, fill=PANEL, alpha=100, line=INK, line_alpha=12, r=0.02):
    return rect(slide, x, y, w, h, fill=fill, alpha=alpha, line=line, lw=0.75,
                line_alpha=line_alpha, shape=MSO_SHAPE.ROUNDED_RECTANGLE, adj=r)


def chip(slide, x, y, w, h, label, color=INK, fill=PANEL2, size=9, line=None,
         align=PP_ALIGN.CENTER, bold=False, font=FMONO, pad=0.08):
    rect(slide, x, y, w, h, fill=fill, alpha=100, line=line or color, lw=0.6, line_alpha=28)
    text(slide, x + pad, y, w - 2 * pad, h, label, size=size, color=color, bold=bold,
         font=font, align=align, anchor=MSO_ANCHOR.MIDDLE, ls=1.0)


def kpi(slide, x, y, w, value, label, color=INK, vsize=25):
    text(slide, x, y, w, 0.5, value, size=vsize, color=color, bold=True, font=FMONO, ls=1.0)
    text(slide, x, y + 0.46, w, 0.3, label, size=9, color=MUTED, ls=1.1)


def table(slide, x, y, cols, rows, row_h=0.33, size=10, head_color=MUTED,
          head_size=8.5, rule=INK, rule_alpha=9, split=None, mono_cols=()):
    """cols: [(dx, width, align)] ; rows: list of list of (str|dict)"""
    cy = y
    for i, row in enumerate(rows):
        for j, cell in enumerate(row):
            dx, cw, al = cols[j]
            if isinstance(cell, dict):
                txt = cell.get("text", "")
                col = cell.get("color", INK if i == 0 else BODY)
                bold = cell.get("bold", i == 0)
                fnt = cell.get("font", FMONO if (i == 0 or j in mono_cols) else FCN)
                csz = cell.get("size", head_size if i == 0 else size)
            else:
                txt, col = cell, (head_color if i == 0 else BODY)
                bold = i == 0
                fnt = FMONO if (i == 0 or j in mono_cols) else FCN
                csz = head_size if i == 0 else size
            text(slide, x + dx, cy, cw, row_h, txt, size=csz, color=col, bold=bold,
                 font=fnt, align=al, anchor=MSO_ANCHOR.MIDDLE, ls=1.05)
        cy += row_h
        if i == 0 or split == "all":
            hline(slide, x, cy - 0.01, cols[-1][0] + cols[-1][1], rule, 22)
        else:
            hline(slide, x, cy - 0.01, cols[-1][0] + cols[-1][1], rule, rule_alpha)
    return cy


def notes(slide, txt):
    slide.notes_slide.notes_text_frame.text = txt
