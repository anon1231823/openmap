# Builds dungeon maps from the game's own minimap pictures: what the minimap draws inside a dungeon
# (its rooms' pictures, WMOMinimapTexture), laid out where the rooms are, a picture per floor, in the
# layout Map/Dungeons.lua draws (1002 x 668 in 4 x 3 tiles of 256 px). For dungeons the game has no
# map of; the floors are set by hand in minimap.json (the editor, editor.py, sets them up).
#   OpenMap/Media/Textures/Forever/MapDungeonMinimap/<mapID>_<floor>_<n>.tga
#   OpenMap/Data/Forever/DungeonMinimap.lua   per instance: its floors' tiles, names, and where each
#                                             floor's picture lies in the world
#
# The rooms (as tools/map-caves/wmo.py places the caves', each step checked there): the instance's
# WDT places its WMOs (MODF: the global one, or the map tiles' object files for a dungeon with
# terrain); a WMO's root lists its groups (MOGI: flags, box); a group inside (flag 0x2000) has its
# pictures in WMOMinimapTexture, 2 px a yard, 128-yard blocks from its box's corner. A dungeon with
# terrain has its tiles' minimap pictures too (the WDT's MAID), 533 1/3 yards each.
#
# minimap.json: { "<mapID>": { "name": "...", "floors": [ { "name": "...", "groups": "all" or
#   ["<uid>:<group>", ...], "z": [low, high] (optional: only rooms whose floor is that high),
#   "terrain": false, "rect": [east0, south0, east1, south1] (yards, optional: else the rooms'
#   extent) } ] } }. A group is "<placement uid>:<group index>" (--survey lists them, with heights).
#
# usage: python -P tools/map-dungeons/minimap.py <cache dir> <World of Warcraft folder> [--preview <dir>]
#        python -P tools/map-dungeons/minimap.py <cache dir> <World of Warcraft folder> --survey <mapID>
import csv, io, json, math, os, struct, sys, time, urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(ROOT, "tools", "casc"))
import clients
from casc import Casc

CONFIG = os.path.join(HERE, "minimap.json")
OUT = os.path.join(clients.tex("forever"), "MapDungeonMinimap")
BUILD = clients.CLIENTS["forever"]["build"]
UA = {"User-Agent": "openmap-tools/1"}
PIC_W, PIC_H = 1002, 668
O = 32 * 1600 / 3               # world yards from the map's corner to its middle
TILE = 1600 / 3
INTERIOR = 0x2000
DRAW_PX = 2                     # px a yard the pictures are laid at (their own), then fitted to the page
PAD = 6                         # yards round a floor's rooms
BACK = (13, 10, 8)              # the dungeon view's own dark (Dungeons.lua's background)


def get(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 50:
        return path
    for attempt in range(3):
        try:
            print("  fetching", url, flush=True)
            data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
            open(path, "wb").write(data)
            time.sleep(0.3)
            return path
        except Exception as e:
            print("  failed:", e, flush=True)
            time.sleep(2)
    sys.exit("couldn't fetch " + url)


def table(cache, name):
    p = get("https://wago.tools/db2/%s/csv?build=%s" % (name, BUILD), os.path.join(cache, "%s-%s.csv" % (name, BUILD)))
    return list(csv.DictReader(open(p, encoding="utf-8")))


def chunks(data):
    out, i = [], 0
    while i + 8 <= len(data):
        tag = data[i:i + 4][::-1].decode("latin-1")
        size = struct.unpack_from("<I", data, i + 4)[0]
        out.append((tag, data[i + 8:i + 8 + size]))
        i += 8 + size
    return out


def modf(d):
    out = []
    for k in range(len(d) // 64):
        fid, uid = struct.unpack_from("<II", d, k * 64)
        pos = struct.unpack_from("<3f", d, k * 64 + 8)
        rot = struct.unpack_from("<3f", d, k * 64 + 20)
        scale = struct.unpack_from("<H", d, k * 64 + 62)[0]
        out.append({"fid": fid, "uid": uid, "pos": pos, "yaw": rot[1], "scale": (scale or 1024) / 1024})
    return out


def blp(data):
    try:
        return Image.open(io.BytesIO(data)).convert("RGBA")
    except Exception:              # (uncompressed BGRA, which PIL's reader doesn't take)
        w, h = struct.unpack("<II", data[12:20])
        off = struct.unpack("<16I", data[20:84])[0]
        return Image.frombytes("RGBA", (w, h), data[off:off + w * h * 4], "raw", "BGRA")


class Dungeon:
    """an instance map's rooms (interior groups with pictures) and terrain tiles, read from the install"""

    def __init__(self, casc, mid, wdt, blocks):
        self.casc, self.mid = casc, mid
        cd = dict(chunks(casc.read(wdt)))
        placed, self.tiles = [], []
        if "MODF" in cd:
            placed += modf(cd["MODF"])
        if "MAIN" in cd and "MAID" in cd:
            seen = set()
            for n in range(64 * 64):
                if not struct.unpack_from("<I", cd["MAIN"], n * 8)[0] & 1: continue
                ids = struct.unpack_from("<8I", cd["MAID"], n * 32)
                ty, tx = divmod(n, 64)
                if ids[7]: self.tiles.append((tx, ty, ids[7]))
                if not ids[1]: continue
                try: obj = casc.read(ids[1])
                except KeyError: continue
                for tag, d in chunks(obj):
                    if tag != "MODF": continue
                    for p in modf(d):
                        if p["uid"] not in seen:
                            seen.add(p["uid"])
                            placed.append(p)
        self.groups = []                # {id, p, g, z0, z1, pics: [(fid, w, h, lx0, ly0)]}
        roots = {}
        for p in placed:
            if p["fid"] not in roots:
                try:
                    rc = dict(chunks(casc.read(p["fid"])))
                    ng = struct.unpack_from("<I", rc["MOHD"], 4)[0]
                    roots[p["fid"]] = (struct.unpack_from("<I", rc["MOHD"], 32)[0],
                                       [(struct.unpack_from("<I", rc["MOGI"], g * 32)[0],
                                         struct.unpack_from("<6f", rc["MOGI"], g * 32 + 4)) for g in range(ng)])
                except Exception:
                    roots[p["fid"]] = None
            root = roots[p["fid"]]
            if not root: continue
            wid, groups = root
            for g, rows in sorted(blocks.get(wid, {}).items()):
                if g >= len(groups) or not groups[g][0] & INTERIOR: continue
                box = groups[g][1]
                pics = []
                for bx, by, fid in rows:
                    try: data = casc.read(fid)
                    except KeyError: continue
                    if data[:4] != b"BLP2": continue
                    w, h = struct.unpack("<II", data[12:20])
                    pics.append((fid, w, h, box[0] + bx * 128, box[1] + by * 128))
                if pics:
                    self.groups.append({"id": "%d:%d" % (p["uid"], g), "p": p, "g": g, "pics": pics,
                                        "z0": p["pos"][1] + box[2] * p["scale"], "z1": p["pos"][1] + box[5] * p["scale"]})

    @staticmethod
    def world(p, lx, ly):
        """a WMO's local (x, y) -> page yards (east, south) on the instance's map"""
        a = math.radians(p["yaw"] + 180)
        s = p["scale"]
        X = O - p["pos"][2] + (lx * math.cos(a) - ly * math.sin(a)) * s
        Y = O - p["pos"][0] + (lx * math.sin(a) + ly * math.cos(a)) * s
        return O - Y, O - X

    def corners(self, grp):
        for _, w, h, lx0, ly0 in grp["pics"]:
            for c, r in ((0, 0), (w, 0), (0, h), (w, h)):
                yield self.world(grp["p"], lx0 + c / 2, ly0 + (h - r) / 2)

    def extent(self, groups):
        pts = [pt for g in groups for pt in self.corners(g)]
        if not pts: return None
        return (min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts))

    def survey(self):
        out = []
        for grp in sorted(self.groups, key=lambda g: g["z0"]):
            e = self.extent([grp])
            out.append({"id": grp["id"], "z0": round(grp["z0"], 1), "z1": round(grp["z1"], 1), "pictures": len(grp["pics"]),
                        "rect": [round(v, 1) for v in e]})
        return out

    def rooms(self, floor):
        want = floor.get("groups", "all")
        groups = self.groups if want == "all" else [g for g in self.groups if g["id"] in set(want)]
        if floor.get("z"):
            lo, hi = floor["z"]
            groups = [g for g in groups if lo <= g["z0"] <= hi]
        return groups

    def draw(self, floor, px=DRAW_PX):
        """a floor's picture at `px` a yard, and the rect it covers (east0, south0, east1, south1)"""
        groups = self.rooms(floor)
        rect = floor.get("rect") or self.extent(groups)
        if not rect: raise SystemExit("map %d: a floor with no rooms and no rect" % self.mid)
        if not floor.get("rect"):
            rect = (rect[0] - PAD, rect[1] - PAD, rect[2] + PAD, rect[3] + PAD)
        W, H = max(1, int((rect[2] - rect[0]) * px)), max(1, int((rect[3] - rect[1]) * px))
        canvas = Image.new("RGBA", (W, H), BACK + (255,))
        if floor.get("terrain"):
            for tx, ty, fid in self.tiles:
                e0, s0 = tx * TILE, ty * TILE
                if e0 > rect[2] or s0 > rect[3] or e0 + TILE < rect[0] or s0 + TILE < rect[1]: continue
                try: img = blp(self.casc.read(fid))
                except KeyError: continue
                size = int(round(TILE * px))
                canvas.alpha_composite(img.resize((size, size), Image.BILINEAR),
                                       (int(round((e0 - rect[0]) * px)), int(round((s0 - rect[1]) * px))))
        for grp in sorted(groups, key=lambda g: g["z0"]):   # (higher rooms over lower ones)
            for fid, w, h, lx0, ly0 in grp["pics"]:
                img = blp(self.casc.read(fid))
                f = lambda c, r: self.world(grp["p"], lx0 + c / 2, ly0 + (h - r) / 2)
                o, cx, cy = [((e - rect[0]) * px, (s - rect[1]) * px) for e, s in (f(0, 0), f(1, 0), f(0, 1))]
                a, b, c_, d = cx[0] - o[0], cy[0] - o[0], cx[1] - o[1], cy[1] - o[1]
                det = a * d - b * c_
                ia, ib, ic, id_ = d / det, -b / det, -c_ / det, a / det
                t = img.transform((W, H), Image.AFFINE, (ia, ib, -(ia * o[0] + ib * o[1]), ic, id_, -(ic * o[0] + id_ * o[1])),
                                  resample=Image.BILINEAR)
                canvas.alpha_composite(t)
        return canvas.convert("RGB"), rect


def page_of(img, rect):
    """the floor fitted into the dungeon map's picture, in the middle; and where the page's corner and
    width lie in yards (east0, south0, yards across the page)"""
    W, H = img.size
    k = min(PIC_W / W, PIC_H / H)
    w, h = max(1, int(round(W * k))), max(1, int(round(H * k)))
    page = Image.new("RGB", (1024, 768), BACK)
    x0, y0 = (PIC_W - w) // 2, (PIC_H - h) // 2
    page.paste(img.resize((w, h), Image.LANCZOS), (x0, y0))
    ypp = (rect[2] - rect[0]) * PIC_W / w          # yards across the page's 1002 px
    return page, (rect[0] - x0 * ypp / PIC_W, rect[1] - y0 * ypp / PIC_W, ypp)


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def open_install(cache, wow):
    casc = Casc(wow, clients.CLIENTS["forever"]["product"])
    blocks = {}
    for r in table(cache, "WMOMinimapTexture"):
        blocks.setdefault(int(r["WMOID"]), {}).setdefault(int(r["GroupNum"]), []).append(
            (int(r["BlockX"]), int(r["BlockY"]), int(r["FileDataID"])))
    wdts = {int(r["ID"]): int(r["WdtFileDataID"] or 0) for r in table(cache, "Map")}
    return casc, blocks, wdts


def load(cache, wow, mid, cached={}):
    if "install" not in cached: cached["install"] = open_install(cache, wow)
    casc, blocks, wdts = cached["install"]
    if not wdts.get(mid): raise SystemExit("map %d: no WDT in the Map table" % mid)
    try:
        return Dungeon(casc, mid, wdts[mid], blocks)
    except KeyError:
        raise SystemExit("map %d: its WDT isn't readable in this install (encrypted, or not there)" % mid)


def main():
    args = sys.argv[1:]
    preview = None
    if "--preview" in args:
        i = args.index("--preview")
        preview = args[i + 1]
        del args[i:i + 2]
    if len(args) < 2:
        sys.exit("usage: python -P tools/map-dungeons/minimap.py <cache dir> <World of Warcraft folder> [--preview <dir>] [--survey <mapID>]")
    cache, wow = args[0], args[1]
    os.makedirs(cache, exist_ok=True)
    if "--survey" in args:
        d = load(cache, wow, int(args[args.index("--survey") + 1]))
        print(json.dumps({"terrain_tiles": len(d.tiles), "groups": d.survey()}, indent=1))
        return
    config = json.load(open(CONFIG, encoding="utf-8")) if os.path.exists(CONFIG) else {}
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):                       # (a floor taken out: its tiles go too)
        if f.endswith(".tga"): os.remove(os.path.join(OUT, f))
    if preview: os.makedirs(preview, exist_ok=True)
    lines = [
        "-- Dungeon maps built from the game's own minimap pictures (what the minimap draws inside),",
        "-- for dungeons the game has no map of; floors set by hand (tools/map-dungeons/minimap.json).",
        "--   [instance mapID] = { { tiles = { 12 textures, row-major }, name = the floor's name,",
        "--     yards = { east, south, across } (where the picture's top-left corner lies on the instance's",
        "--     map, and how many yards its 1002 px span: world X = %.2f - south, Y = %.2f - east) }, ... }" % (O, O),
        "-- Generated by tools/map-dungeons/minimap.py from build %s's tables and the install's files;" % BUILD,
        "-- regenerate rather than edit.",
        "",
        "local _, ns = ...",
        "",
        "local P = ns.Media.tex .. \"MapDungeonMinimap\\\\\"",
        "",
        "ns.MapDungeonMinimap = {",
    ]
    for key in sorted(config, key=int):
        mid = int(key)
        d = load(cache, wow, mid)
        entry = config[key]
        lines.append("\t[%d] = { -- %s" % (mid, entry.get("name", "")))
        for fi, floor in enumerate(entry["floors"], 1):
            img, rect = d.draw(floor)
            page, (e0, s0, ypp) = page_of(img, rect)
            tiles = []
            for n in range(12):
                col, row = n % 4, n // 4
                f = "%d_%d_%d" % (mid, fi, n + 1)
                page.crop((col * 256, row * 256, col * 256 + 256, row * 256 + 256)).save(os.path.join(OUT, f + ".tga"))
                tiles.append("P .. " + lua_str(f))
            if preview: page.crop((0, 0, PIC_W, PIC_H)).save(os.path.join(preview, "%d_%d.png" % (mid, fi)))
            name = (", name = " + lua_str(floor["name"])) if floor.get("name") else ""
            lines.append("\t\t{ tiles = { %s }%s, yards = { %.1f, %.1f, %.1f } }," % (", ".join(tiles), name, e0, s0, ypp))
            print("%d floor %d: %d rooms, %.0f x %.0f yards" % (mid, fi, len(d.rooms(floor)), rect[2] - rect[0], rect[3] - rect[1]))
        lines.append("\t},")
    lines.append("}")
    with open(os.path.join(clients.data("forever"), "DungeonMinimap.lua"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
