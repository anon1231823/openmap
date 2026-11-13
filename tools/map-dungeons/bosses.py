# Builds where each boss is on WoW Forever's dungeon maps, for Map/Dungeons.lua's boss pins.
#   OpenMap/Data/Forever/DungeonBosses.lua   per instance: each boss's floor and place on it
#
# A boss's place is a spot on its floor's picture, 0..1 across and down the 1002 x 668 of it (the
# view's own measure, Dungeons.lua's PageAt), on the floor at that index of the instance's floors
# (Data/DungeonMaps.lua's, else Data/DungeonDrawn.lua's). A map built from the minimap pictures
# (Data/DungeonMinimap.lua) has floors of its own, so its places are its own too, under "minimap:<mapID>".
# The bosses are Places.lua's (the game's DungeonEncounter list), by name. Where each comes from, first found:
#   1. bosses.json beside this script: places set by hand, each with where it came from: the in-game
#      placer (/openmap bosses, saved in OpenMapDB; brought in with --import) or the editor
#      (editor.py). They win over the journal, so a wrong journal spot can be put right.
#   2. Mists of Pandaria Classic's journal (JournalEncounter: Map_0 / Map_1 on its UiMapID), the build
#      whose UiMap tables Forever's dungeon floors come from (build.py's TABLES), where the boss has
#      the same name and its UiMap is one of the instance's floors.
#   3. retail's journal, the same way (only for floors the instance has: some of retail's maps of
#      the old dungeons are newer ones).
# A boss with neither is left out (its pin isn't drawn; the Bosses tab still lists it), and listed.
#
# usage: python -P tools/map-dungeons/bosses.py <cache dir> [--import <OpenMap.lua SavedVariables>]
#   (tables are fetched from wago.tools into the cache; --import adds the places made with the
#   in-game placer to bosses.json first, then builds)
import csv, json, os, re, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import clients

TABLES = "5.5.4.70268"          # Mists of Pandaria Classic (build.py's)
RETAIL = "12.1.5.70391"
UA = {"User-Agent": "openmap-tools/1"}
PLACED = os.path.join(HERE, "bosses.json")
DATA = clients.data("forever")


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


def table(cache, name, build):
    p = get("https://wago.tools/db2/%s/csv?build=%s" % (name, build), os.path.join(cache, "%s-%s.csv" % (name, build)))
    return list(csv.DictReader(open(p, encoding="utf-8")))


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def squash(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


def lua_strings(body):
    return [s.replace('\\"', '"').replace("\\\\", "\\") for s in re.findall(r'"((?:[^"\\]|\\.)*)"', body)]


# ------------------------------------------------------------------ the addon's own data
def read_bosses():
    """Places.lua's bosses: {mapID: [name, ...]}, and its instances' names {mapID or name: title}"""
    src = open(os.path.join(DATA, "Places.lua"), encoding="utf-8").read()
    bosses = {}
    for m, body in re.findall(r"\[(\d+)\] = \{ (.*?) \},\n", src[src.index("bosses = {"):]):
        bosses[int(m)] = lua_strings(body)
    names = {}
    for mid, name in re.findall(r'\{ (\d+), "((?:[^"\\]|\\.)*)", (?:true|false)', src):
        key = int(mid) or name
        names.setdefault(key, name)
    return bosses, names


def read_floors():
    """{key: [first tile of each floor]} from DungeonMaps.lua (file IDs) and DungeonDrawn.lua (paths)"""
    floors = {}
    for fname, prefix in (("DungeonMaps.lua", ""), ("DungeonDrawn.lua", ""), ("DungeonMinimap.lua", "minimap:")):
        if not os.path.exists(os.path.join(DATA, fname)): continue
        src = open(os.path.join(DATA, fname), encoding="utf-8").read()
        for key, body in re.findall(r'\n\t\[(\d+|"(?:[^"\\]|\\.)*")\] = \{ --[^\n]*\n(.*?)\n\t\},', src, re.S):
            key = int(key) if key.isdigit() else lua_strings(key)[0]
            if prefix: key = prefix + str(key)
            if key in floors: continue          # (Blizzard's map first, as Dungeons.lua's FloorsOf)
            floors[key] = [t for t in re.findall(r"tiles = \{ ([^,]+),", body)]
    return floors


# ------------------------------------------------------------------ the in-game placer's places
def import_saved(path, placed):
    """OpenMapDB.worldmap.bossPlaced from a SavedVariables file into `placed`; returns how many"""
    try:
        import lupa
    except ImportError:
        sys.exit("--import needs lupa (pip install lupa), the offline tests' Lua")
    lua = lupa.LuaRuntime()
    lua.execute(open(path, encoding="utf-8", errors="replace").read())
    db = lua.globals().OpenMapDB
    got = db and db.worldmap and db.worldmap.bossPlaced
    if not got: return 0
    n = 0
    for key, list_ in got.items():
        key = int(key) if isinstance(key, (int, float)) else str(key)
        for name, p in list_.items():
            if not (p and p[1] and p[2] is not None and p[3] is not None): continue
            placed.setdefault(str(key), {})[str(name)] = {
                "floor": int(p[1]), "x": round(float(p[2]), 4), "y": round(float(p[3]), 4),
                "source": "placed in game (/openmap bosses)"}
            n += 1
    return n


def load_placed():
    if not os.path.exists(PLACED): return {}
    return json.load(open(PLACED, encoding="utf-8"))


def save_placed(placed):
    out = {k: dict(sorted(v.items())) for k, v in sorted(placed.items(), key=lambda kv: (not kv[0].isdigit(), int(kv[0]) if kv[0].isdigit() else 0, kv[0]))}
    with open(PLACED, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
        fh.write("\n")


# ------------------------------------------------------------------ the journals
def journal(cache, build, ui_of_tile):
    """{uiMapID: {squashed name: (x, y)}} from a build's JournalEncounter"""
    out = {}
    for r in table(cache, "JournalEncounter", build):
        u = r["UiMapID"]
        if u in ("", "0"): continue
        x, y = float(r["Map_0"] or 0), float(r["Map_1"] or 0)
        if not (0 < x < 1 and 0 < y < 1): continue
        out.setdefault(int(u), {})[squash(r["Name_lang"])] = (x, y)
    return out


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit("usage: python -P tools/map-dungeons/bosses.py <cache dir> [--import <OpenMap.lua SavedVariables>]")
    cache = args[0]
    os.makedirs(cache, exist_ok=True)
    placed = load_placed()
    if "--import" in args:
        n = import_saved(args[args.index("--import") + 1], placed)
        save_placed(placed)
        print("imported", n, "places from the in-game placer into bosses.json")

    bosses, names = read_bosses()
    floors = read_floors()

    # each floor's UiMap (Blizzard's maps: their first tile's art, in the tables build.py read)
    art_of = {}
    for r in table(cache, "UiMapArtTile", TABLES):
        if r["RowIndex"] == "0" and r["ColIndex"] == "0" and r["LayerIndex"] == "0":
            art_of[r["FileDataID"]] = r["UiMapArtID"]
    ui_of_art = {}
    for r in table(cache, "UiMapXMapArt", TABLES):
        if r["PhaseID"] == "0":
            ui_of_art.setdefault(r["UiMapArtID"], int(r["UiMapID"]))
    sources = [("MoP Classic's journal", journal(cache, TABLES, None)), ("retail's journal", journal(cache, RETAIL, None))]

    out, report, counts = {}, [], {"placed": 0, "MoP Classic's journal": 0, "retail's journal": 0, "none": 0}
    keys = sorted(set(bosses) | {k for k in floors if isinstance(k, str)} | {int(k) if k.isdigit() else k for k in placed},
                  key=lambda k: (isinstance(k, str), k))
    for key in keys:
        fl = floors.get(key)
        if not fl: continue                     # (no map: no place to pin a boss on)
        uis = [ui_of_art.get(art_of.get(t.strip())) for t in fl]
        base = int(key[8:]) if isinstance(key, str) and key.startswith("minimap:") else key
        list_ = bosses.get(base, []) if isinstance(base, int) else []
        hand = placed.get(str(key), {})
        for name in hand:
            if name not in list_: list_ = list_ + [name]   # (one the game's list doesn't have: kept, so it's seen)
        got, missing = [], []
        for name in list_:
            p = hand.get(name)
            if p:
                if not 1 <= p["floor"] <= len(fl):
                    report.append("  %s: %s's floor %d isn't one of its %d" % (names.get(key, key), name, p["floor"], len(fl)))
                    continue
                got.append((name, p["floor"], p["x"], p["y"], p.get("source", "placed by hand")))
                counts["placed"] += 1
                continue
            found = None
            for label, j in sources:
                for i, u in enumerate(uis):
                    xy = u and j.get(u, {}).get(squash(name))
                    if xy:
                        found = (name, i + 1, round(xy[0], 4), round(xy[1], 4), label)
                        break
                if found: break
            if found:
                got.append(found)
                counts[found[4]] += 1
            else:
                missing.append(name)
                counts["none"] += 1
        if got: out[key] = got
        title = str(names.get(base, key)) + (" (minimap)" if base != key else "")
        report.append("  %-28s %2d of %2d placed%s" % (title[:28], len(got), len(list_),
                      ("; not yet: " + ", ".join(missing)) if missing else ""))

    lines = [
        "-- Where each boss is on its dungeon's map: its floor (the index of the instance's floors in",
        "-- Data/DungeonMaps.lua, else Data/DungeonDrawn.lua) and its place on that floor's picture, 0..1",
        "-- across and down (Map/Dungeons.lua's boss pins).",
        "--   [instance mapID, or name for one the tables have no mapID for] = { [boss] = { floor, x, y }, ... }",
        "--   [\"minimap:<mapID>\"] = the same, on its map built from the minimap pictures (Data/DungeonMinimap.lua)",
        "-- Generated by tools/map-dungeons/bosses.py from tools/map-dungeons/bosses.json (places set in",
        "-- game or in its editor) and the journals of builds %s and %s (JournalEncounter);" % (TABLES, RETAIL),
        "-- regenerate rather than edit.",
        "",
        "local _, ns = ...",
        "",
        "ns.MapDungeonBosses = {",
    ]
    for key in sorted(out, key=lambda k: (isinstance(k, str), k)):
        base = int(key[8:]) if isinstance(key, str) and key.startswith("minimap:") else key
        lines.append("\t[%s] = { -- %s" % (key if isinstance(key, int) else lua_str(key), names.get(base, key)))
        for name, floor, x, y, src in out[key]:
            lines.append("\t\t[%s] = { %d, %.4f, %.4f }, -- %s" % (lua_str(name), floor, x, y, src))
        lines.append("\t},")
    lines.append("}")
    with open(os.path.join(DATA, "DungeonBosses.lua"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\n".join(report))
    print("bosses placed: %d by hand, %d from MoP Classic's journal, %d from retail's; %d not yet" % (
        counts["placed"], counts["MoP Classic's journal"], counts["retail's journal"], counts["none"]))


if __name__ == "__main__":
    main()
