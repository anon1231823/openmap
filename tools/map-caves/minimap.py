# Builds OpenMap/Data/Forever/CaveMinimap.lua: every cave and underground area on the two continents, as
# the game's own minimap draws it inside (its WMOs' minimap textures, WMOMinimapTexture). Blizzard
# made world-map art (micro maps, build.py) for only some of them; the rest have only this.
# Which WMOs are caves, and how they're placed: wmo.py.
#
# Left out: what a city's map shows (Stormwind's canals, Undercity, Ironforge) and what Blizzard's
# cave maps cover a third of or more (Data/Caves.lua: build.py first); pieces next to each other
# are one cave.
#
# And the underground cities (Ironforge, Undercity: Stitch.lua's UNDERGROUND_CITIES), whose minimap
# outside is the surface over them (the mountain, the ruins): the city's own WMO as the minimap
# draws it inside, for Close.lua to lay over the city's map up close. Not a cave by wmo.py's names
# (Forever's own files, numbered): the WMO placed in the city's box with rooms under the terrain.
#
#   OpenMap/Data/Forever/CaveMinimap.lua
#     MapCaveMinimap, per cave: continent, its box (yards), its pieces lowest floor first, each a
#     square (the block's picture and the transparent rest): file, centre (yards), side (yards),
#     rotation (radians, counter-clockwise on the map), and the picture's share of the square
#     (u1, v0: texcoords 0..u1, v0..1)
#     MapCityMinimap, [city uiMapID] = the same, for its WMO: every inside group, above ground or
#     under it (the Undercity's ways up to the ruins and its lifts are the city too)
#   OpenMap/Media/Textures/Forever/MapCaveMend/<file ID>.tga
#     a picture mended where the game's own has a fault baked in (MEND), drawn instead of it
#
# usage: python -P tools/map-caves/minimap.py <cache dir> [contact sheet.png]
#   (OPENMAP_WOW: the game's folder, to read its files there; see wmo.py)
import math, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "OpenMap")
sys.path.insert(0, HERE)
from wmo import World, BUILD, cave_kind

NEAR = 8                        # yards between pieces that make one cave
# pictures with a fault baked into the game's own file, made clear (alpha 0) in a box of its pixels
# (x0, y0, x1, y1, from its top left): md_mushroomcave08's 215101 has an opaque white block over its
# tunnel's mouth, which showed as a white diamond at both of that cave's mouths in the Hinterlands (#114)
MEND = {215101: (28, 190, 118, 256)}
MEND_DIR = os.path.join(ROOT, "Media", "Textures", "Forever", "MapCaveMend")
CITIES = ("1453", "1454", "1455", "1456", "1457", "1458")   # (their own maps show what's under them)
UNDERGROUND = {"1455": "Ironforge", "1458": "Undercity"}    # (Stitch.lua's UNDERGROUND_CITIES)
CITY_SHARE = 2 / 3              # how much of a WMO's box lies in an underground city's box for it to be the city

world = World(sys.argv[1])
print(len(world.placed), "WMOs placed,", len(world.roots), "kinds")

def overlap(a, b):
    """the area two boxes (minX, minY, maxX, maxY) share"""
    return max(0, min(a[2], b[2]) - max(a[0], b[0])) * max(0, min(a[3], b[3]) - max(a[1], b[1]))

def pictures(p, groups):
    """a placed WMO's groups' minimap pictures, and the box round the groups: ([(floor, file, centre X, Y,
    side, rotation, u1, v0)], [minX, minY, maxX, maxY])"""
    out, xs, ys = [], [], []
    for g, box in groups:
        for fid, w, h, lx0, ly0 in world.pictures(p, g, box):
            side = max(w, h)                                       # (px: the square holding it)
            cx, cy = world.world(p, lx0 + side / 4, ly0 + side / 4)
            # (screen rotation: the picture's x runs along R(yaw + 180) x, north up on the map)
            out.append((p["pos"][1] + box[2] * p["scale"], fid, cx, cy, side / 2 * p["scale"],
                        math.radians(p["yaw"] - 90), side / w, 1 - side / h))
        for lx in (box[0], box[3]):
            for ly in (box[1], box[4]):
                X, Y = world.world(p, lx, ly)
                xs.append(X); ys.append(Y)
    return out, xs and [min(xs), min(ys), max(xs), max(ys)]

boxes, under = [], {}            # Blizzard's cave maps and the cities: (continent, minX, minY, maxX, maxY)
for m in re.finditer(r"\[\d+\] = \{ \"[^\"]+\", (\d), ([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+)",
                     open(os.path.join(ROOT, "Data", "Forever", "Caves.lua"), encoding="utf-8").read()):
    boxes.append((int(m.group(1)), *map(float, m.group(2, 3, 4, 5))))
for r in world.table("UiMapAssignment"):
    if r["UiMapID"] in CITIES and r["OrderIndex"] == "0":
        b = (int(r["MapID"]), float(r["Region_0"]), float(r["Region_1"]), float(r["Region_3"]), float(r["Region_4"]))
        boxes.append(b)
        if r["UiMapID"] in UNDERGROUND: under[int(r["UiMapID"])] = b

pieces = []                      # each placed WMO that's a cave: its pieces and box
for (cont, uid), p in sorted(world.placed.items()):
    out, b = pictures(p, world.cave_groups(p))
    if not out: continue
    area = max(1, (b[2] - b[0]) * (b[3] - b[1]))
    # (left out where a cave map or a city's map has a third of it already)
    if any(c == cont and overlap(b, (x0, y0, x1, y1)) >= area / 3 for c, x0, y0, x1, y1 in boxes): continue
    pieces.append(dict(cont=cont, box=b, out=out, path=world.paths[p["fid"]]))

# the underground cities: the WMO in the city's box (most of its own box) whose inside lies under the
# terrain, not a cave there (Ironforge's troll den, the tunnels round it)
cities = {}
for mid, (cont, *cb) in sorted(under.items()):
    for (c, uid), p in sorted(world.placed.items()):
        if c != cont or cave_kind(world.paths.get(p["fid"])): continue
        groups = world.inside(p)
        if not any(world.underground(p, box) for _, box in groups): continue
        out, b = pictures(p, groups)
        if not out or overlap(b, cb) < CITY_SHARE * (b[2] - b[0]) * (b[3] - b[1]): continue
        if mid in cities: sys.exit("two WMOs for %s: %s, %s" % (UNDERGROUND[str(mid)], cities[mid]["path"], world.paths.get(p["fid"])))
        cities[mid] = dict(cont=cont, box=b, out=out, path=world.paths.get(p["fid"], str(p["fid"])))
    if mid not in cities: sys.exit("no WMO for " + UNDERGROUND[str(mid)])
    print(UNDERGROUND[str(mid)], cities[mid]["path"], len(cities[mid]["out"]), "pictures")

# pieces next to each other are one cave (a tunnel's segments, a mine and its shaft)
caves = []
for pc in pieces:
    for cv in caves:
        b, q = cv["box"], pc["box"]
        if cv["cont"] == pc["cont"] and q[0] <= b[2] + NEAR and q[2] >= b[0] - NEAR and q[1] <= b[3] + NEAR and q[3] >= b[1] - NEAR:
            cv["out"] += pc["out"]
            cv["box"] = [min(b[0], q[0]), min(b[1], q[1]), max(b[2], q[2]), max(b[3], q[3])]
            cv["paths"].add(pc["path"])
            break
    else:
        caves.append(dict(cont=pc["cont"], box=list(pc["box"]), out=list(pc["out"]), paths={pc["path"]}))
caves.sort(key=lambda c: (c["cont"], -c["box"][2], -c["box"][3]))
print(len(pieces), "underground WMOs,", len(caves), "caves,", sum(len(c["out"]) for c in caves), "pictures")

def mend(fid):
    """the mended copy of a picture (MEND), written once: its texture's path in the file"""
    path = os.path.join(MEND_DIR, "%d.tga" % fid)
    if not os.path.exists(path):
        img = world.picture(fid)
        x0, y0, x1, y1 = MEND[fid]
        alpha = img.getchannel("A")
        a = alpha.load()
        for y in range(y0, min(y1, img.height)):
            for x in range(x0, min(x1, img.width)):
                a[x, y] = 0
        img.putalpha(alpha)
        img.save(path)
    return 'M .. "%d"' % fid

def entry(cv):
    """a cave's or a city's line: continent, box, its pictures lowest floor first"""
    cv["out"].sort(key=lambda o: o[0])
    flat = ", ".join("%s, %.1f, %.1f, %.1f, %.3f, %.3f, %.3f" % (mend(o[1]) if o[1] in MEND else "%d" % o[1], *o[2:])
                     for o in cv["out"])
    return "{ %d, %.0f, %.0f, %.0f, %.0f, { %s } }" % (cv["cont"], *cv["box"], flat)

os.makedirs(MEND_DIR, exist_ok=True)
for name in os.listdir(MEND_DIR):              # (one no longer mended: its copy goes)
    if name.endswith(".tga") and int(name[:-4]) not in MEND: os.remove(os.path.join(MEND_DIR, name))
with open(os.path.join(ROOT, "Data", "Forever", "CaveMinimap.lua"), "w", encoding="utf-8", newline="\n") as f:
    f.write("-- Caves and underground areas as the game's minimap draws them inside (their WMOs' minimap pictures).\n")
    f.write("--   { continent, minX, minY, maxX, maxY (world yards), { per picture, lowest floor first: file, centre X, Y,\n")
    f.write("--     side (yards), rotation (radians), u1, v0 (texcoords 0..u1, v0..1 of the square) ... } }\n")
    f.write("-- Generated by tools/map-caves/minimap.py (build %s); regenerate rather than edit.\n\n" % BUILD)
    f.write("local _, ns = ...\n\nlocal M = ns.Media.tex .. \"MapCaveMend\\\\\"   -- (pictures mended: MEND)\n\nns.MapCaveMinimap = {\n")
    for cv in caves:
        name = ", ".join(sorted(p.rsplit("/", 1)[-1].replace(".wmo", "") for p in cv["paths"]))
        f.write("\t%s,   -- %s\n" % (entry(cv), name))
    f.write("}\n\n")
    f.write("-- The underground cities, whose minimap outside is the surface over them: the city's own WMO, the same way.\n")
    f.write("--   [city uiMapID] = { continent, minX, minY, maxX, maxY, { pictures } }\n")
    f.write("ns.MapCityMinimap = {\n")
    for mid, cv in sorted(cities.items()):
        f.write("\t[%d] = %s,   -- %s (%s)\n" % (mid, entry(cv), UNDERGROUND[str(mid)], cv["path"].rsplit("/", 1)[-1].replace(".wmo", "")))
    f.write("}\n")

# ------------------------------------------------------------------ an optional contact sheet
if len(sys.argv) > 2:
    from PIL import Image

    cells, CELL = [], 220
    for cv in caves + [cities[m] for m in sorted(cities)]:
        x0, y0, x1, y1 = cv["box"]
        k = (CELL - 10) / max(x1 - x0, y1 - y0, 1)                  # px a yard on the sheet
        cell = Image.new("RGBA", (CELL, CELL), (40, 30, 20, 255))
        for _, fid, cx, cy, side, rot, u1, v0 in cv["out"]:
            im = world.picture(fid)
            w, h = im.size
            sq = Image.new("RGBA", (max(w, h), max(w, h)), (0, 0, 0, 0))   # (the square: the picture at its bottom left)
            sq.paste(im, (0, max(w, h) - h))
            n = max(2, int(side * k))
            sq = sq.resize((n, n), Image.BILINEAR).rotate(math.degrees(rot), expand=True, resample=Image.BILINEAR)
            # (the map: east right = -Y, south down = -X)
            px, py = (y1 - cy) * k + 5, (x1 - cx) * k + 5
            cell.alpha_composite(sq, (int(px - sq.width / 2), int(py - sq.height / 2)))
        cells.append(cell)
    cols = 12
    sheet = Image.new("RGB", (cols * CELL, ((len(cells) + cols - 1) // cols) * CELL), (15, 15, 15))
    for i, cell in enumerate(cells):
        sheet.paste(cell, ((i % cols) * CELL, (i // cols) * CELL))
    sheet.save(sys.argv[2])
