"""Build the main menu assets from the approved drafts (art/drafts/menu/, 2026-10-09).

    python3 art/objects/ui/main_menu/main_menu_assets.py

Godot StyleBoxTexture draws nine-slice corners at texture size (no scale), so buttons are saved
at their on-screen height (logical 1080p): gold 140 px, dark 120 px. Logo and sound icons too.
"""
import math
import struct
import wave
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
DRAFTS = ROOT / "art/drafts/menu"
OUT = ROOT / "art/objects/ui/main_menu"
DRONE = ROOT / "art/objects/units/drone"

SRC_BTN_H = 212           # source button height (btn_*.png from the 2x2 kit sheet)
SRC_MARGIN = (150, 60)    # nine-slice margins in the source: left/right, top/bottom
BUTTONS = {"btn_gold": 140, "btn_dark": 120}
LOGO_W = 640
SOUND_H = 120
DRONE_W = 300


def scaled(img: Image.Image, w: int | None = None, h: int | None = None) -> Image.Image:
    if w is None:
        w = round(img.width * h / img.height)
    if h is None:
        h = round(img.height * w / img.width)
    return img.resize((w, h), Image.LANCZOS)


def click_wav(path: Path) -> None:
    """Short triangle blip, 440 Hz, 0.12 s fade out (like the HTML draft's WebAudio click)."""
    rate, dur, freq = 44100, 0.12, 440.0
    frames = bytearray()
    for i in range(int(rate * dur)):
        t = i / rate
        tri = 2 * abs(2 * (t * freq - math.floor(t * freq + 0.5))) - 1
        env = 0.18 * math.exp(-t / dur * 6.9)          # ≈ 0.18 → 0.001, as the draft
        frames += struct.pack("<h", int(tri * env * 32767))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))


def main() -> None:
    Image.open(DRAFTS / "bg_nodrones.png").convert("RGB").save(OUT / "menu_bg.webp", quality=90)
    for name, h in BUTTONS.items():
        img = scaled(Image.open(DRAFTS / f"{name}.png").convert("RGBA"), h=h)
        img.save(OUT / f"{name}.png")
        k = h / SRC_BTN_H
        print(f"{name}: {img.size}, margins left/right {SRC_MARGIN[0] * k:.0f}, top/bottom {SRC_MARGIN[1] * k:.0f}")
    scaled(Image.open(DRAFTS / "logo.png").convert("RGBA"), w=LOGO_W).save(OUT / "logo.png")
    for name in ("sound_on", "sound_off"):
        scaled(Image.open(DRAFTS / f"{name}.png").convert("RGBA"), h=SOUND_H).save(OUT / f"{name}.png")
    scaled(Image.open(DRAFTS / "drone.png").convert("RGBA"), w=DRONE_W).save(DRONE / "drone.png")
    click_wav(OUT / "ui_click.wav")


if __name__ == "__main__":
    main()
