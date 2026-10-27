"""Renders the app icon: a camera lens in camwatch's teal with a small shield.

Run from the repository root with Pillow installed:
    python tool/make_icon.py
It writes the Android mipmaps (legacy and adaptive) and the Windows .ico.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ANDROID_RES = ROOT / "apps/camwatch/android/app/src/main/res"
WINDOWS_ICO = ROOT / "apps/camwatch/windows/runner/resources/app_icon.ico"

TEAL = (0, 121, 107)        # the app's seed colour, Material teal 700
TEAL_DARK = (0, 77, 64)
WHITE = (255, 255, 255)
SCALE = 4                   # supersampling for smooth edges


def lens(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float) -> None:
    """A lens: white ring, dark pupil, a highlight."""
    ring = r * 0.16
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=WHITE)
    draw.ellipse((cx - r + ring, cy - r + ring, cx + r - ring, cy + r - ring), fill=TEAL_DARK)
    pupil = r * 0.42
    draw.ellipse((cx - pupil, cy - pupil, cx + pupil, cy + pupil), fill=(10, 30, 28))
    h = r * 0.14
    draw.ellipse((cx - r * 0.36 - h, cy - r * 0.36 - h, cx - r * 0.36 + h, cy - r * 0.36 + h), fill=WHITE)


def shield(draw: ImageDraw.ImageDraw, cx: float, cy: float, s: float) -> None:
    """A shield with a tick, bottom right of the lens."""
    w, h = s, s * 1.15
    top = cy - h / 2
    outline = [
        (cx - w / 2, top),
        (cx + w / 2, top),
        (cx + w / 2, top + h * 0.55),
        (cx, top + h),
        (cx - w / 2, top + h * 0.55),
    ]
    draw.polygon(outline, fill=TEAL)
    inset = s * 0.11
    inner = [
        (cx - w / 2 + inset, top + inset),
        (cx + w / 2 - inset, top + inset),
        (cx + w / 2 - inset, top + h * 0.55 - inset * 0.4),
        (cx, top + h - inset * 1.3),
        (cx - w / 2 + inset, top + h * 0.55 - inset * 0.4),
    ]
    draw.polygon(inner, fill=WHITE)
    stroke = max(2, int(s * 0.12))
    draw.line(
        [(cx - w * 0.22, cy - h * 0.02), (cx - w * 0.05, cy + h * 0.16), (cx + w * 0.25, cy - h * 0.2)],
        fill=TEAL,
        width=stroke,
        joint="curve",
    )


def render(size: int, *, background: bool, pad: float = 0.0) -> Image.Image:
    """The icon at [size] px; [pad] is the fraction of the canvas kept clear
    around the artwork (adaptive icons are masked to the inner 2/3)."""
    big = size * SCALE
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    if background:
        radius = big * 0.22
        draw.rounded_rectangle((0, 0, big - 1, big - 1), radius=radius, fill=TEAL)
    usable = big * (1 - 2 * pad)
    cx = cy = big / 2
    r = usable * 0.30
    lens(draw, cx - usable * 0.04, cy - usable * 0.04, r)
    shield(draw, cx + usable * 0.22, cy + usable * 0.22, usable * 0.26)
    return image.resize((size, size), Image.LANCZOS)


def main() -> None:
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, factor in densities.items():
        folder = ANDROID_RES / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        render(int(48 * factor), background=True).save(folder / "ic_launcher.png")
        # Adaptive foreground: 108 dp canvas, artwork inside the safe 66 dp circle.
        render(int(108 * factor), background=False, pad=0.18).save(folder / "ic_launcher_foreground.png")
    anydpi = ANDROID_RES / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )
    values = ANDROID_RES / "values"
    (values / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        '    <color name="ic_launcher_background">#00796B</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )
    sizes = [16, 24, 32, 48, 64, 128, 256]
    frames = [render(s, background=True) for s in sizes]
    frames[-1].save(WINDOWS_ICO, format="ICO", sizes=[(s, s) for s in sizes], append_images=frames[:-1])
    print("icons written")


if __name__ == "__main__":
    main()
