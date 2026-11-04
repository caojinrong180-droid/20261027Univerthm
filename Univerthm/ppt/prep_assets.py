# -*- coding: utf-8 -*-
"""Prepare image assets for the Univerthm defence deck."""
import os
from PIL import Image

SRC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(SRC, "game", "tests", "_shots")
ASSETS = os.path.join(SRC, "game", "assets")
OUT = os.path.join(SRC, "ppt", "assets")
os.makedirs(OUT, exist_ok=True)

BG = (11, 12, 18)

def fade_bottom(img, px=110, color=BG):
    """Soft ramp of the bottom strip towards the deck background (hides dev hint bars)."""
    w, h = img.size
    img = img.convert("RGB")
    px = min(px, h // 3)
    overlay = Image.new("RGB", (w, px), color)
    mask = Image.new("L", (w, px))
    mpx = mask.load()
    for y in range(px):
        t = (y / (px - 1)) ** 1.6
        v = int(255 * t)
        for x in range(w):
            mpx[x, y] = v
    img.paste(overlay, (0, h - px), mask)
    return img

def shot(name, wide=1600, quality=86, fade=False, out=None):
    p = os.path.join(SHOTS, name)
    im = Image.open(p)
    im = im.convert("RGB")
    if im.width > wide:
        im = im.resize((wide, round(im.height * wide / im.width)), Image.LANCZOS)
    if fade:
        im = fade_bottom(im)
    out = out or (os.path.splitext(name)[0] + ".jpg")
    im.save(os.path.join(OUT, out), "JPEG", quality=quality, optimize=True, progressive=True)
    print("shot", out, im.size)

def trim_png(src, out, pad=6):
    im = Image.open(os.path.join(ASSETS, src)).convert("RGBA")
    bbox = im.split()[-1].getbbox()
    if bbox:
        l, t, r, b = bbox
        l = max(0, l - pad); t = max(0, t - pad)
        r = min(im.width, r + pad); b = min(im.height, b + pad)
        im = im.crop((l, t, r, b))
    if im.width > 1100:
        im = im.resize((1100, round(im.height * 1100 / im.width)), Image.LANCZOS)
    im.save(os.path.join(OUT, out), "PNG", optimize=True)
    print("png", out, im.size)

# ---- full-bleed backgrounds -------------------------------------------------
shot("00b_main_menu.png", wide=1920, quality=88, out="bg_main_menu.jpg")
shot("00c_collection.png", wide=1600, quality=86, out="bg_collection.jpg")

# ---- UI / flow screenshots -------------------------------------------------
shot("00e_chapter_select.png", fade=True, out="s_chapter.jpg")
shot("21_song_map_sheet.png", fade=True, out="s_map.jpg")
shot("19_song_list.png", fade=True, out="s_list.jpg")
shot("03_results.png", out="s_results.jpg")
shot("00c_collection.png", out="s_collection.jpg")
shot("10_secret_song.png", fade=True, out="s_secret.jpg")
shot("11_secret_revealed.png", fade=True, out="s_reveal.jpg")
shot("05_entry_intro.png", out="s_entry.jpg")
shot("story_overlay_blur.png", out="s_story.jpg")
shot("02f_pause.png", out="s_pause.jpg")
shot("00a_splash.png", fade=True, out="s_splash.jpg")

# ---- stage / gameplay ------------------------------------------------------
shot("02b_gameplay.png", out="s_stage.jpg")
shot("02_gameplay_fx.png", out="s_fx.jpg")
shot("02c_gameplay_rotate.png", out="s_rot.jpg")
shot("02d_gameplay_alpha.png", out="s_alpha.jpg")
shot("02e_gameplay_speed.png", out="s_speed.jpg")

# ---- logo + characters -----------------------------------------------------
logo = Image.open(os.path.join(ASSETS, "title_main_visual.png")).convert("RGB")
# the logo source sits on a flat black plate: luminance becomes the alpha channel
lum = logo.convert("L")
alpha = lum.point(lambda v: min(255, int(v * 1.15)))
logo = logo.convert("RGBA")
logo.putalpha(alpha)
bbox = alpha.getbbox()
logo = logo.crop(bbox)
logo.save(os.path.join(OUT, "logo.png"), "PNG", optimize=True)
print("logo", logo.size)

trim_png("banners/stra1.png", "stra.png")
trim_png("banners/Kisai1.png", "kisai.png")
