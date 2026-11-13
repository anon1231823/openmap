"""Unexplored land hidden up close in Lua 5.1 (Stitch.lua's Shade.Hide.Rects: the rectangles a zone
hides, its unexplored pieces less its explored ones), against every pixel of random piece sets; and
the places a painted gap shows that no zone map draws (Shade.Places, Data/GapPlaces.lua): found by the
zone maps' pieces under their middle, as a city is, and hidden or darkened until then:
python -P tools/offline-test/explored.py."""
from pathlib import Path
import random
import re
import unittest

from lupa.lua51 import LuaRuntime


ADDON = Path(__file__).resolve().parents[2] / "OpenMap"
STITCH = ADDON / "Map" / "Stitch.lua"


def chunk(name):
    """a function of Stitch.lua's, its source alone (the file needs the whole map to load)"""
    m = re.search(r"\nfunction %s\(.*?\nend\n" % re.escape(name), STITCH.read_text(encoding="utf-8"), re.S)
    assert m, name + " in Stitch.lua"
    return m.group(0)


class HiddenTests(unittest.TestCase):
    def setUp(self):
        # (the function alone, with the two tables it reads: Stitch.lua needs the whole map to load)
        m = re.search(r"\nfunction Shade\.Hide\.Rects\(mapID\)\n.*?\nend\n", STITCH.read_text(encoding="utf-8"), re.S)
        self.assertIsNotNone(m, "Shade.Hide.Rects in Stitch.lua")
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            pieces = {}
            Shade = { Hide = { rects = {} } }
            function strsplit(sep, s)
                local out = {}
                for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
                return unpack(out)
            end
        """)
        self.lua.execute(m.group(0))

    def pieces(self, specs):
        self.lua.execute("pieces[1] = {} Shade.Hide.rects = {}")
        for (w, h, x, y), un in specs:
            self.lua.execute('pieces[1]["%d:%d:%d:%d"] = { unexplored = %s }' % (w, h, x, y, "true" if un else "false"))
        rects, count = self.lua.eval("Shade.Hide.Rects")(1)
        covered = set()
        for i in range(1, len(rects) + 1 if rects else 1):
            r = rects[i]
            covered |= {(x, y) for y in range(int(r[2]), int(r[4])) for x in range(int(r[1]), int(r[3]))}
        return covered, count

    def test_random_pieces_against_every_pixel(self):
        rng = random.Random(7)
        W, H = 120, 90
        for _ in range(200):
            specs = []
            for _ in range(rng.randint(1, 9)):
                w, h = rng.randint(5, 60), rng.randint(5, 50)
                specs.append(((w, h, rng.randint(0, W - w), rng.randint(0, H - h)), rng.random() < 0.5))
            covered, count = self.pieces(specs)
            def inside(un, x, y):
                return any(u == un and px < x < px + w and py < y < py + h for (w, h, px, py), u in specs)
            want = {(x, y) for y in range(H) for x in range(W) if inside(True, x + .5, y + .5) and not inside(False, x + .5, y + .5)}
            self.assertEqual(covered, want)
            self.assertEqual(count, sum(1 for _, un in specs if un))

    def test_all_explored_hides_nothing(self):
        covered, count = self.pieces([((40, 30, 0, 0), False), ((20, 20, 10, 10), False)])
        self.assertEqual((covered, count), (set(), 0))

    def test_worked_out_again_once_explored(self):
        self.pieces([((40, 30, 0, 0), True)])
        self.lua.execute('pieces[1]["40:30:0:0"].unexplored = false')
        rects, count = self.lua.eval("Shade.Hide.Rects")(1)
        self.assertEqual(count, 0)
        self.assertIsNone(rects)


class PlaceTests(unittest.TestCase):
    """Data/GapPlaces.lua as the game loads it, with Stitch.lua's Shade.Under, Shade.Found and
    Shade.Places (its covers stand-ins that remember being shown)"""

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            W, H, NONE, root = 1002, 668, {}, {}
            pieces, cullBox = {}, nil
            places = {}                                  -- zoneID -> its placement (Place's left, top, sx, sy)
            function Place(zoneID) return places[zoneID] end
            Shade = { Hide = { mode = false } }
            whole = {}                                   -- zoneID -> true: not found at all (Shade.Unexplored "all")
            function Shade.Unexplored(zoneID) return whole[zoneID] and "all" or "some" end
            function strsplit(sep, s)
                local out = {}
                for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
                return unpack(out)
            end
            ns = {}
        """)
        data =(ADDON / "Data" / "Forever" / "GapPlaces.lua").read_text(encoding="utf-8")
        self.lua.eval("function(src) local fn = assert(loadstring(src)); fn('OpenMap', ns) end")(data)
        for name in ("Shade.Under", "Shade.Found", "Shade.Places.Build", "Shade.Places.Refresh",
                     "Shade.Places.Show", "Shade.Places.At"):
            src = chunk(name)
            if name == "Shade.Places.Build":
                src = "Shade.Places = { list = false }\n" + src
            self.lua.execute(src)
        self.lua.execute("""
            function Shade.Places.Frame(e, how)          -- (a frame that remembers being shown)
                local f = { how = how, shown = false }
                function f.IsShown(self) return self.shown end
                function f.SetShown(self, v) self.shown = v and true or false end
                return f
            end
        """)
        self.places = list(self.lua.eval("ns.MapGapPlaces").values())

    def zone_under(self, place, unexplored, also=None):
        """a zone whose one piece's rectangle holds the place's middle (and `also`: one that doesn't)"""
        mid = place[4]
        self.lua.execute("places[1] = { left = 0, top = 0, sx = 1, sy = 1 } pieces[1] = {}")
        x, y = int(mid[1] * 1002), int(mid[2] * 668)
        self.lua.execute('pieces[1]["40:40:%d:%d"] = { unexplored = %s }' % (x - 20, y - 20, "true" if unexplored else "false"))
        if also is not None:
            self.lua.execute('pieces[1]["10:10:%d:%d"] = { unexplored = %s }' % (x + 30, y + 30, "true" if also else "false"))
        self.lua.execute("Shade.Places.list = false")

    def show(self, mode):
        self.lua.execute('Shade.Hide.mode = %s Shade.Places.Show()' % ("false" if not mode else '"%s"' % mode))
        e = self.lua.eval("Shade.Places.list[1]")
        return (bool(e.hide and e.hide.shown), bool(e.dim and e.dim.shown))

    def middle_hidden(self, place):
        mid = place[4]
        return bool(self.lua.eval("Shade.Places.At")(mid[1], mid[2]))

    def test_the_data(self):
        self.assertTrue(self.places, "Data/GapPlaces.lua lists a place")
        notice = (ADDON / "Media" / "Textures" / "Forever" / "NOTICE.md").read_text(encoding="utf-8")
        self.assertIn("MapGapPlace/", notice)
        for p in self.places:
            area, box, mid, cells = p[1], list(p[3].values()), list(p[4].values()), p[5]
            self.assertTrue(0 <= box[0] < box[2] <= 1 and 0 <= box[1] < box[3] <= 1, box)
            self.assertTrue(box[0] < mid[0] < box[2] and box[1] < mid[1] < box[3], (box, mid))
            self.assertRegex(cells, r"^[0-9a-f]{256}$")
            # its mask: a plain 32-bit TGA (no RLE), a power of two a side
            tga = (ADDON / "Media" / "Textures" / "Forever" / "MapGapPlace" / ("%d.tga" % area)).read_bytes()
            w, h = int.from_bytes(tga[12:14], "little"), int.from_bytes(tga[14:16], "little")
            self.assertEqual((tga[2], tga[16]), (2, 32), "uncompressed 32-bit")
            self.assertTrue(w & (w - 1) == 0 and h & (h - 1) == 0, (w, h))

    def test_hidden_until_a_piece_over_it_is_explored(self):
        for p in self.places:
            self.zone_under(p, unexplored=True, also=False)  # (an explored piece elsewhere doesn't find it)
            self.assertEqual(self.show("hide"), (True, False))
            self.assertTrue(self.middle_hidden(p))
            self.assertEqual(self.show("dim"), (False, True))
            self.assertEqual(self.show(False), (False, False))
            self.lua.execute('pieces[1]["40:40:%d:%d"].unexplored = false Shade.Places.Refresh()'
                             % (int(p[4][1] * 1002) - 20, int(p[4][2] * 668) - 20))
            self.assertEqual(self.show("hide"), (False, False))
            self.assertFalse(self.middle_hidden(p))
            self.assertEqual(self.show("dim"), (False, False))

    def test_no_pieces_under_it_is_found(self):
        for p in self.places:
            self.lua.execute("pieces = {} Shade.Places.list = false")
            self.assertEqual(self.show("hide"), (False, False))
            self.assertFalse(self.middle_hidden(p))

    def test_darkened_with_its_zone_when_that_isnt_found_at_all(self):
        for p in self.places:
            self.zone_under(p, unexplored=True)
            self.lua.execute("whole[1] = true")
            self.assertEqual(self.show("dim"), (False, False))   # (its zone's shade has it)
            self.assertEqual(self.show("hide"), (True, False))
            self.lua.execute("whole[1] = nil")

    def test_off_the_view(self):
        for p in self.places:
            self.zone_under(p, unexplored=True)
            box = list(p[3].values())
            self.lua.execute("cullBox = { %f, %f, %f, %f }" % (box[2] + 0.01, box[3] + 0.01, box[2] + 0.1, box[3] + 0.1))
            self.assertEqual(self.show("hide"), (False, False))
            self.lua.execute("cullBox = nil")

    def test_cells_against_the_box(self):
        for p in self.places:
            self.zone_under(p, unexplored=True)
            self.show("hide")
            box, cells = list(p[3].values()), p[5]
            At = self.lua.eval("Shade.Places.At")
            for j in range(16):
                for i in range(16):
                    u = box[0] + (i + 0.5) / 16 * (box[2] - box[0])
                    v = box[1] + (j + 0.5) / 16 * (box[3] - box[1])
                    self.assertEqual(bool(At(u, v)), int(cells[j * 16 + i], 16) >= 8, (i, j))
            self.assertFalse(At(box[0] - 0.01, box[1]))
            self.assertFalse(At(box[2] + 0.01, box[3]))


class FoundTests(unittest.TestCase):
    """Only places you've found (Stitch.lua's places.Found): an entrance in a city is found with the city,
    whose own map has no pieces to explore (Ragefire Chasm in Orgrimmar, #113); one in a zone, when the
    zone's land there is explored"""

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            places, S = {}, {}
            cities = { { mapID = 85, piece = { unexplored = true } } }
            rects = { [85] = { 0.10, 0.20, 0.30, 0.40 }, [1411] = { 0.0, 1.0, 0.0, 1.0 } }
            S.Rect = function(id) local r = rects[id] if r then return r[1], r[2], r[3], r[4] end end
            S.ChainAt = function() return { 947, 12, 1411 } end
            explored = false
            CreateVector2D = function(x, y) return { x = x, y = y } end
            C_MapExplorationInfo = { GetExploredAreaIDsAtPosition = function() return explored and { 1 } or {} end }
        """)
        self.lua.execute(chunk("places.Found"))
        self.found = self.lua.eval("function(u, v) return places.Found(u, v) end")

    def test_in_a_city_found_with_the_city(self):
        self.assertFalse(self.found(0.15, 0.35), "the city not found yet")
        self.lua.execute("cities[1].piece.unexplored = false")
        self.assertTrue(self.found(0.15, 0.35), "found with the city, whatever its own map's pieces say")

    def test_in_a_zone_by_its_explored_land(self):
        self.assertFalse(self.found(0.6, 0.6))
        self.lua.execute("explored = true")
        self.assertTrue(self.found(0.6, 0.6))


class DimTilesTests(unittest.TestCase):
    """Darkened up close (Stitch.lua's Shade.Hide.Tiles): the shade drawn through each unexplored piece's
    own art (its alpha the shade's shape, soft-edged as at normal zoom: in rectangles it was hard-edged,
    #101, #129), only the unexplored pieces', each tile where Shade.Pieces draws it, its whole file the mask"""

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            Shade = { Hide = {} }
            function Pow2(n) local p = 1 while p < n do p = p * 2 end return p end
            list = {
                { files = { 11, 12, 13, 14 }, x = 10, y = 20, w = 300, h = 200, piece = { unexplored = true } },
                { files = { 21 }, x = 400, y = 50, w = 100, h = 100, piece = { unexplored = false } },
            }
            function ForEachPiece(mapID, fn)
                for _, e in ipairs(list) do fn(e.files, e.x, e.y, e.w, e.h, 0, e.piece) end
            end
        """)
        self.lua.execute(chunk("Shade.Hide.Tiles"))
        self.tiles = self.lua.eval("""function()
            local p = { left = 1000, top = 2000, sx = 2, sy = 3, layer = { tileWidth = 256, tileHeight = 256 } }
            return Shade.Hide.Tiles(1421, p)
        end""")()

    def test_only_the_unexplored_pieces_tiles(self):
        files = sorted(t.file for t in self.tiles.values())
        self.assertEqual(files, [11, 12])        # (300 x 200: two tiles across, one down; 21 explored)

    def test_placed_as_the_pieces_copies_are(self):
        t = {t.file: t for t in self.tiles.values()}
        self.assertEqual((t[11].x, t[11].y, t[11].w, t[11].h), (1000 + 10 * 2, 2000 + 20 * 3, 256 * 2, 200 * 3))
        self.assertEqual((t[12].x, t[12].w), (1000 + (10 + 256) * 2, 44 * 2))
        # (its mask the whole file: the next power of two at the edge, not the part shown)
        self.assertEqual((t[12].fw, t[12].fh), (64 * 2, 256 * 3))
        self.assertEqual((t[11].fw, t[11].fh), (256 * 2, 256 * 3))


if __name__ == "__main__":
    unittest.main()
