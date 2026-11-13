"""Out-of-game brightness comparison from bundled zone tiles, without DB2 downloads.

Usage: python -P tools/map-preview/brightness.py <output directory>
This previews the art only, without pins, zoom fades or the live close-up layers.
"""
from pathlib import Path
import sys

from PIL import Image, ImageEnhance, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "OpenMap/Media/Textures/Forever/MapZones"
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
tiles = [(tuple(map(int, path.stem.split("_"))), path) for path in SOURCE.glob("*.blp")]
if not tiles:
    raise SystemExit("No bundled Forever zone tiles found")
left, right = min(p[0][0] for p in tiles), max(p[0][0] for p in tiles)
top, bottom = min(p[0][1] for p in tiles), max(p[0][1] for p in tiles)
size = 64
# render.py's sea colour; tiles are the game's art, already composited by --bake-zones.
art = Image.new("RGBA", ((right - left + 1) * size, (bottom - top + 1) * size), (128, 125, 105, 255))
for (x, y), path in tiles:
    with Image.open(path) as image:
        tile = image.convert("RGBA").crop((0, 0, 510, 510)).resize((size, size), Image.Resampling.LANCZOS)
    art.alpha_composite(tile, ((x - left) * size, (y - top) * size))
art = art.convert("RGB")
art.thumbnail((1200, 900))
font = ImageFont.load_default(size=18)
for value in (1.0, 0.6):
    picture = Image.new("RGB", (art.width, art.height + 64), (24, 24, 24))
    picture.paste(ImageEnhance.Brightness(art).enhance(value), (0, 64))
    draw = ImageDraw.Draw(picture)
    draw.text((12, 8), "Out of game: bundled zone art - brightness %d%%" % (value * 100), fill="white", font=font)
    draw.text((12, 34), "No pins, live zoom layers or in-game UI", fill=(190, 190, 190), font=font)
    path = out / ("map-brightness-%d.png" % (value * 100))
    picture.save(path, optimize=True)
    print(path)
