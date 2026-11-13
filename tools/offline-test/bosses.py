"""Boss pins' data (Data/Forever/DungeonBosses.lua) against the maps and boss lists it's for:
python -P tools/offline-test/bosses.py

Each boss's place must be on one of its instance's floors (Data/DungeonMaps.lua's, else
Data/DungeonDrawn.lua's, as Map/Dungeons.lua's FloorsOf picks them), inside the picture (0..1),
and a boss the game lists for it (Places.lua) or one placed by hand (tools/map-dungeons/bosses.json).
(The pins themselves, on the dungeon's map, and the placer need the game: the stub has no world map.)
"""
from pathlib import Path
import json
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "OpenMap" / "Data" / "Forever"


def load():
    lua = LuaRuntime(unpack_returned_tuples=True)
    ns = lua.eval("{ Media = { tex = '' } }")
    for name in ("Places.lua", "DungeonMaps.lua", "DungeonDrawn.lua", "DungeonMinimap.lua", "DungeonBosses.lua"):
        fn = lua.eval("function(src, ns) return assert(loadstring(src))('OpenMap', ns) end")
        fn((DATA / name).read_text(encoding="utf-8"), ns)
    return ns


class Bosses(unittest.TestCase):
    def test_places(self):
        ns = load()
        places = ns.MapPlaces
        placed = json.loads((ROOT / "tools" / "map-dungeons" / "bosses.json").read_text(encoding="utf-8")) \
            if (ROOT / "tools" / "map-dungeons" / "bosses.json").exists() else {}
        n = 0
        for key, bosses in ns.MapDungeonBosses.items():
            base = int(key[8:]) if isinstance(key, str) and key.startswith("minimap:") else key
            floors = ns.MapDungeonMinimap[base] if base != key else (ns.MapDungeonMaps[key] or ns.MapDungeonDrawn[key])
            self.assertTrue(floors, "%s: bosses for a dungeon with no map" % key)
            listed = set((places.bosses[base] or {}).values()) if isinstance(base, int) else set()
            listed |= set(placed.get(str(key), {}))
            for name, p in bosses.items():
                n += 1
                self.assertIn(name, listed, "%s: %s isn't one of its bosses" % (key, name))
                self.assertTrue(1 <= p[1] <= len(floors), "%s: %s on floor %s of %d" % (key, name, p[1], len(floors)))
                self.assertTrue(0 <= p[2] <= 1 and 0 <= p[3] <= 1, "%s: %s off its picture" % (key, name))
        self.assertGreater(n, 100, "fewer bosses placed than the journals alone give")


class InstanceHereTests(unittest.TestCase):
    """the map opened inside a dungeon finds it (Dungeons.lua's InstanceHere, against Places.lua), by its
    mapID: WoW Forever's own too, which the tables of Places.lua's build had none for (The Drowned City's
    drawn map didn't open inside it; #149 takes theirs from the live build's)"""

    def setUp(self):
        import re
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("ns = { Media = { tex = '' } }")
        run = self.lua.eval("function(src) return assert(loadstring(src))('OpenMap', ns) end")
        run((DATA / "Places.lua").read_text(encoding="utf-8"))
        src = (ROOT / "OpenMap" / "Map" / "Dungeons.lua").read_text(encoding="utf-8")
        m = re.search(r"\nlocal function InstanceHere\(\).*?\nend\n", src, re.S)
        self.assertIsNotNone(m, "InstanceHere in Dungeons.lua")
        self.lua.execute("""
            local ns = ns
            here = nil
            function IsInInstance() return here ~= nil end
            function GetInstanceInfo() return "x", "party", 1, "", 5, 0, false, here end
            local function Places() return ns.MapPlaces end
        """ + m.group(0) + """
            function Find(id) here = id local inst = InstanceHere() return inst and inst[2] end
        """)

    def test_by_map_id(self):
        self.assertEqual(self.lua.eval("Find(36)"), "Deadmines")

    def test_forevers_own(self):
        self.assertEqual(self.lua.eval("Find(2970)"), "The Drowned City")
        self.assertEqual(self.lua.eval("Find(3039)"), "Krol'dok Stronghold")
        self.assertEqual(self.lua.eval("Find(3001)"), "Shaper's Terrace")

    def test_not_in_one(self):
        self.assertIsNone(self.lua.eval("Find(nil)"))
        self.assertIsNone(self.lua.eval("Find(0)"))                              # (0: never one, not even a 0 left in the data)

    def test_every_drawn_map_is_found_inside_its_dungeon(self):
        ns = load()
        for key in ns.MapDungeonDrawn.keys():
            self.assertIsInstance(key, int, "%s: a drawn map by name: the map opened inside it can't find it" % key)
            self.assertIsNotNone(self.lua.eval("Find(%d)" % key), "%s: a drawn map no dungeon in Places.lua has" % key)


class ByMapIDTests(unittest.TestCase):
    """what was kept per dungeon by name (the quill's drawings, the bosses placed) for WoW Forever's own
    goes to its mapID once they have one (Dungeons.lua's ByMapID, #149), never over what's there already"""

    def setUp(self):
        import re
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        src = (ROOT / "OpenMap" / "Map" / "Dungeons.lua").read_text(encoding="utf-8")
        m = re.search(r"\nlocal function ByMapID\(all, inst\).*?\nend\n", src, re.S)
        self.assertIsNotNone(m, "ByMapID in Dungeons.lua")
        self.lua.execute(m.group(0) + "\n Move = ByMapID")

    def test_moved_once(self):
        self.lua.execute("""
            all = { ["The Drowned City"] = { "lines" } }
            Move(all, { 2970, "The Drowned City" })
            assert(all[2970][1] == "lines" and all["The Drowned City"] == nil)
            Move(all, { 2970, "The Drowned City" })
            assert(all[2970][1] == "lines")
        """)

    def test_never_over_whats_there(self):
        self.lua.execute("""
            all = { ["The Drowned City"] = { "old" }, [2970] = { "new" } }
            Move(all, { 2970, "The Drowned City" })
            assert(all[2970][1] == "new" and all["The Drowned City"][1] == "old")
            Move(nil, { 2970, "x" })                    -- (nothing kept yet)
            local none = {}
            Move(none, { 0, "Somewhere" })              -- (no mapID: stays by name)
            assert(next(none) == nil)
        """)

if __name__ == "__main__":
    unittest.main()
