#!/usr/bin/env python3
"""Generate the Mi 9T Plymouth theme into bootsplash/theme/.

    python3 bootsplash/make-splash.py

Needs Pillow. The shipped assets were rendered with Segoe UI (Regular and
Semibold); on a machine without it, set SPLASH_FONT and SPLASH_FONT_BOLD to
any TrueType files, or DejaVu Sans is used. Also writes splash-preview.png at
the panel's aspect ratio.
"""
from pathlib import Path
import os
from PIL import Image, ImageDraw, ImageFont

BASE = Path(__file__).resolve().parent
theme = BASE / "theme"
theme.mkdir(exist_ok=True)


def pick(env, *candidates):
    for c in (os.environ.get(env), *candidates):
        if c and Path(c).is_file():
            return c
    raise SystemExit(f"no font found; set {env}")


font = pick("SPLASH_FONT", "C:/Windows/Fonts/segoeui.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
font_semibold = pick("SPLASH_FONT_BOLD", "C:/Windows/Fonts/seguisb.ttf",
                     "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")

def label(text, size, color, name, bold=False):
    f = ImageFont.truetype(font_semibold if bold else font, size)
    bounds = f.getbbox(text)
    canvas = Image.new("RGBA", (bounds[2]-bounds[0]+12, bounds[3]-bounds[1]+12))
    ImageDraw.Draw(canvas).text((6-bounds[0], 6-bounds[1]), text, font=f, fill=color)
    canvas.save(theme / name)

for i in range(24):
    canvas = Image.new("RGBA", (360, 360))
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((14, 14, 346, 346), outline=(45, 49, 57, 255), width=7)
    for seg in range(14):
        alpha = int(30 + 225 * seg / 13)
        angle = i * 15 + seg * 7
        draw.arc((14, 14, 346, 346), angle, angle + 7, fill=(240, 107, 55, alpha), width=9)
    canvas.resize((180, 180), Image.Resampling.LANCZOS).save(theme / f"ring-{i}.png")
for i in range(101):
    label(f"{i}%", 30, (240, 241, 244), f"percent-{i}.png", True)
label("Ubuntu", 32, (245, 245, 247), "title.png", True)
label("XIAOMI MI 9T", 13, (131, 137, 148), "device.png")
label("Starting", 14, (153, 159, 169), "starting.png")
label("Shutting down", 14, (153, 159, 169), "stopping.png")
(theme / "mi9t.plymouth").write_text("""[Plymouth Theme]
Name=Mi 9T
Description=Ubuntu start animation for Xiaomi Mi 9T
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/mi9t
ScriptFile=/usr/share/plymouth/themes/mi9t/mi9t.script
""", newline="\n")
(theme / "mi9t.script").write_text("""Window.SetBackgroundTopColor(0.043, 0.051, 0.067);
Window.SetBackgroundBottomColor(0.043, 0.051, 0.067);
width = Window.GetWidth();
height = Window.GetHeight();
scale = width / 540;
if (scale > 2) scale = 2;
if (scale < 0.5) scale = 0.5;
center_x = width / 2;
center_y = height * 0.44;
for (i = 0; i < 24; i++) ring[i] = Image("ring-" + i + ".png").Scale(180 * scale, 180 * scale);
for (i = 0; i < 101; i++) {
    img = Image("percent-" + i + ".png");
    percentage[i] = img.Scale(img.GetWidth() * scale, img.GetHeight() * scale);
}
spinner = Sprite(ring[0]);
spinner.SetPosition(center_x - 90 * scale, center_y - 90 * scale, 1);
percent = Sprite();
fun show_percent(value) {
    img = percentage[value];
    percent.SetImage(img);
    percent.SetPosition(center_x - img.GetWidth() / 2, center_y - img.GetHeight() / 2, 2);
}
show_percent(0);
fun centered_label(filename, offset) {
    image = Image(filename);
    image = image.Scale(image.GetWidth() * scale, image.GetHeight() * scale);
    sprite = Sprite(image);
    sprite.SetPosition(center_x - image.GetWidth() / 2, center_y + offset * scale, 2);
    return sprite;
}
title = centered_label("title.png", 127);
device = centered_label("device.png", 178);
if (Plymouth.GetMode() == "shutdown" || Plymouth.GetMode() == "reboot") {
    starting = centered_label("stopping.png", 238);
    percent.SetOpacity(0);
} else {
    starting = centered_label("starting.png", 238);
}
frame = 0;
tick = 0;
progress_percent = 0;
fun refresh() {
    global.tick++;
    if (tick >= 3) {
        global.tick = 0;
        global.frame++;
        if (frame >= 24) global.frame = 0;
        spinner.SetImage(ring[frame]);
    }
}
fun progress(duration, fraction) {
    value = Math.Int(fraction * 100);
    if (value > 99) value = 99;
    if (value > progress_percent) {
        global.progress_percent = value;
        show_percent(value);
    }
}
fun quit() { show_percent(100); }
Plymouth.SetRefreshFunction(refresh);
Plymouth.SetBootProgressFunction(progress);
Plymouth.SetQuitFunction(quit);
""", newline="\n")
# Preview the same generated assets at the physical panel aspect ratio.
preview = Image.new("RGB", (540, 1170), (11, 13, 17))
cy = int(1170 * .44)
for name, y in [("ring-8.png",cy-90),("percent-64.png",cy-20),("title.png",cy+127),("device.png",cy+178),("starting.png",cy+238)]:
    image = Image.open(theme/name)
    preview.paste(image, ((540-image.width)//2,y), image)
preview.save(BASE / "splash-preview.png")
print("Splash assets generated.")
