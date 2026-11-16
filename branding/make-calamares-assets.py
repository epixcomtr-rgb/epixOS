#!/usr/bin/env python3
"""epixOS — Calamares marka görsellerini üretir.

Gerçek logodan örneklenmiş palet kullanılır (tahmin değil):
    lime  #e2ff5e   navy #16404b   deep #0e2a31

Çıktı: iso/config/includes.chroot/etc/calamares/branding/epixos/
    logo.png      ürün logosu (şeffaf)
    icon.png      pencere ikonu
    welcome.png   karşılama ekranı görseli
    slide1..3.png slayt gösterisi görselleri

Kullanım: python3 branding/make-calamares-assets.py
"""
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "iso/config/includes.chroot/etc/calamares/branding/epixos"
LOGO_SRC = ROOT / "site/assets/img/logo.png"

LIME = (226, 255, 94)
NAVY = (22, 64, 75)
DEEP = (14, 42, 49)
WHITE = (255, 255, 255)
MUTED = (168, 191, 196)

FONT_DIR = pathlib.Path("/usr/share/fonts/truetype/dejavu")
F_BOLD = FONT_DIR / "DejaVuSans-Bold.ttf"
F_REG = FONT_DIR / "DejaVuSans.ttf"


def font(path, size):
    return ImageFont.truetype(str(path), size)


def glow(size, cx, cy, radius, color, alpha=42, steps=26):
    """Yumuşak radyal hale katmanı döndürür (RGBA)."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(steps, 0, -1):
        r = int(radius * i / steps)
        a = int(alpha * (1 - i / steps) ** 1.6)
        if r > 0 and a > 0:
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (a,))
    return layer


def background(size, with_grid=True):
    """Koyu zemin + hafif ızgara + vinyet."""
    w, h = size
    img = Image.new("RGB", size, DEEP)

    # navy'ye doğru dikey geçiş
    grad = Image.new("RGB", (1, h))
    gd = ImageDraw.Draw(grad)
    for y in range(h):
        t = y / max(1, h - 1)
        gd.point((0, y), tuple(
            int(DEEP[i] + (NAVY[i] - DEEP[i]) * (t * 0.55)) for i in range(3)))
    img = grad.resize(size)

    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    if with_grid:
        step = 48
        for x in range(0, w, step):
            d.line([(x, 0), (x, h)], fill=LIME + (8,), width=1)
        for y in range(0, h, step):
            d.line([(0, y), (w, y)], fill=LIME + (8,), width=1)

    img = Image.alpha_composite(img.convert("RGBA"), layer)

    # köşe vinyeti — radyal karartma (dikdörtgen DEĞİL:
    # iç içe dikdörtgen çizmek görünür bir kutu kenarı bırakıyordu)
    small = (w // 12, h // 12)
    vig = Image.new("L", small, 0)
    vd = ImageDraw.Draw(vig)
    maxr = (small[0] ** 2 + small[1] ** 2) ** 0.5 / 2
    for r in range(int(maxr), 0, -1):
        a = int(150 * (1 - r / maxr) ** 0.75)
        vd.ellipse([small[0] / 2 - r, small[1] / 2 - r,
                    small[0] / 2 + r, small[1] / 2 + r], fill=a)
    dark = Image.new("RGBA", size, (0, 0, 0, 255))
    dark.putalpha(Image.eval(
        vig.resize(size, Image.BILINEAR), lambda v: 255 - v))
    return Image.alpha_composite(img, dark)


def x_motif(size, cx, cy, span, color=LIME, width=14):
    """Logodaki 'X' motifi: iki çapraz ışın."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    h = span // 2
    off = int(h * 0.42)
    d.line([(cx - h, cy - h + off), (cx + h, cy + h + off)],
           fill=color + (255,), width=width)
    d.line([(cx - h, cy + h + off), (cx + h, cy - h + off)],
           fill=color + (255,), width=width)
    return layer


def draw_logo(size):
    """Logoyu hedef boyuta ölçekle (şeffaflık korunur)."""
    im = Image.open(LOGO_SRC).convert("RGBA")
    im.thumbnail(size, Image.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.paste(im, ((size[0] - im.width) // 2,
                      (size[1] - im.height) // 2), im)
    return canvas


def make_icon(size=256):
    """Pencere ikonu: şeffaf zeminde logo."""
    return draw_logo((size, size))


def make_logo(size=(320, 175)):
    return draw_logo(size)


def make_welcome(size=(1200, 700)):
    """Karşılama ekranı: marka, X motifi, sürüm."""
    img = background(size)
    w, h = size

    cx, cy = w // 2, int(h * 0.40)
    img = Image.alpha_composite(img, glow(size, cx, cy, int(h * 0.34), LIME, 34))
    img = Image.alpha_composite(img, x_motif(size, cx, cy, int(h * 0.30),
                                             LIME, 18))

    d = ImageDraw.Draw(img)
    title = "epixOS"
    tf = font(F_BOLD, 104)
    tw = d.textlength(title, font=tf)
    d.text((cx - tw / 2, int(h * 0.62)), title, font=tf, fill=WHITE)

    sub = "Hafif · Hızlı · AI ile yönetilen Linux"
    sf = font(F_REG, 30)
    sw = d.textlength(sub, font=sf)
    d.text((cx - sw / 2, int(h * 0.79)), sub, font=sf, fill=MUTED)

    return img.convert("RGB")


def make_slide(number, total, title, lines, size=(900, 540)):
    """Slayt: sol metin, sağda X motifi ve numara."""
    img = background(size)
    w, h = size

    cx, cy = int(w * 0.76), int(h * 0.44)
    img = Image.alpha_composite(img, glow(size, cx, cy, int(h * 0.30), LIME, 30))
    img = Image.alpha_composite(img, x_motif(size, cx, cy, int(h * 0.26),
                                             LIME, 12))

    d = ImageDraw.Draw(img)

    # Marka etiketi
    d.text((72, 58), "epixOS", font=font(F_BOLD, 30), fill=LIME)

    # Başlık
    d.text((72, 130), title, font=font(F_BOLD, 52), fill=WHITE)

    # Ayırıcı çizgi
    d.line([(74, 212), (74 + 96, 212)], fill=LIME + (255,), width=4)

    # Metin satırları
    lf = font(F_REG, 24)
    y = 250
    for ln in lines:
        d.text((72, y), ln, font=lf, fill=MUTED)
        y += 42

    # Sayfa göstergesi
    d.text((72, h - 74), f"{number} / {total}",
           font=font(F_REG, 20), fill=(120, 145, 150))

    return img.convert("RGB")


def main():
    if not LOGO_SRC.exists():
        sys.exit(f"logo bulunamadı: {LOGO_SRC}")
    OUT.mkdir(parents=True, exist_ok=True)

    make_logo().save(OUT / "logo.png")
    make_icon().save(OUT / "icon.png")
    make_welcome().save(OUT / "welcome.png")

    slides = [
        ("Kuruluma hazır", [
            "Bu kurulum diske yazacak; canlı oturum",
            "değişmeden kalır.",
            "",
            "Devam etmeden önce yedek almanı öneririz.",
        ]),
        ("Hafif ve hızlı", [
            "GNOME masaüstü, 2 GB RAM'de akıcı.",
            "Boşta ~650 MB bellek kullanır.",
            "",
            "Snap yok, gereksiz servis yok.",
        ]),
        ("İlk açılışta hazır", [
            "SSH açık, Türkçe dil ve klavye ayarlı.",
            "Eski Intel ekran kartları için vga=791",
            "zaten GRUB'a yazılır.",
            "",
            "Kurulumdan sonra epix-update ile güncelle.",
        ]),
    ]
    total = len(slides)
    for i, (title, lines) in enumerate(slides, 1):
        make_slide(i, total, title, lines).save(OUT / f"slide{i}.png")

    for f in sorted(OUT.glob("*.png")):
        with Image.open(f) as im:
            print(f"  {f.name:14s} {im.size[0]}x{im.size[1]}  "
                  f"{f.stat().st_size:,} B")


if __name__ == "__main__":
    main()
