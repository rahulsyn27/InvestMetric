"""Renders the Android launcher icons and the in-app logo from
docs/logo/investmetric-icon.svg.

Needs Google Chrome (to draw the SVG) and Pillow. Run from the repo root:

    python3 tool/make_icons.py
"""

import pathlib
import re
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SVG = ROOT / "docs/logo/investmetric-icon.svg"
RES = ROOT / "android/app/src/main/res"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Legacy icons are 48dp; adaptive icon layers are 108dp.
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

# Adaptive icons are masked to a shape; only the middle 66dp of 108dp is
# always visible, so the mark is shrunk to fit that circle.
FOREGROUND_SCALE = 0.78


def variants(svg: str) -> dict[str, str]:
    background = re.search(r'<g id="background">.*?</g>', svg, re.S).group(0)
    mark = re.search(r'<g id="mark".*?</g>', svg, re.S).group(0)
    offset = re.search(r'<g id="mark" transform="(translate\([^)]*\))"', svg).group(1)
    no_bg = svg.replace(background, "")
    fg = no_bg.replace(
        f'transform="{offset}"',
        f'transform="translate(512 512) scale({FOREGROUND_SCALE}) '
        f'translate(-512 -512) {offset}"',
    )
    # Themed icons (Android 13+) use only the shape: everything in white,
    # keeping any opacity.
    mono = re.sub(r'(fill|stroke)="(url\(#gold\)|#[0-9A-Fa-f]{6})"', r'\1="#FFFFFF"', fg)
    bg = svg.replace(mark, "").replace('rx="230"', 'rx="0"')
    return {"full": svg, "foreground": fg, "monochrome": mono, "background": bg}


def render(svg: str, out: pathlib.Path) -> Image.Image:
    src = out.with_suffix(".svg")
    src.write_text(svg)
    subprocess.run(
        [
            CHROME,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--force-device-scale-factor=1",
            "--default-background-color=00000000",
            "--window-size=1024,1024",
            f"--screenshot={out}",
            src.as_uri(),
        ],
        check=True,
        capture_output=True,
    )
    return Image.open(out).convert("RGBA")


def save(img: Image.Image, size: int, path: pathlib.Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path, optimize=True)


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        images = {
            name: render(svg, pathlib.Path(tmp) / f"{name}.png")
            for name, svg in variants(SVG.read_text()).items()
        }
    for d, k in DENSITIES.items():
        folder = RES / f"mipmap-{d}"
        save(images["full"], round(48 * k), folder / "ic_launcher.png")
        for layer in ("foreground", "background", "monochrome"):
            save(images[layer], round(108 * k), folder / f"ic_launcher_{layer}.png")
        # Launch screen logo (96dp). A plain bitmap: on Android 8+ the
        # launcher icon is an adaptive-icon XML, which <bitmap> can't show.
        save(images["full"], round(96 * k), RES / f"drawable-{d}" / "splash_logo.png")
    save(images["full"], 512, ROOT / "assets/logo/logo.png")
    print("Icons written.", file=sys.stderr)


if __name__ == "__main__":
    main()
