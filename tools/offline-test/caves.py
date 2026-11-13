"""Caves underground in Lua 5.1 (Close.lua with Data/Caves.lua and Data/CaveMinimap.lua), and the
underground cities' own minimap (Ironforge's): python -P tools/offline-test/caves.py."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[2] / "OpenMap"


class CaveTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
            tContains = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
            tremove = table.remove
            GetTime = function() return 0 end
            errors = {}
            geterrorhandler = function() return function(e) table.insert(errors, e) end end
            -- frames and textures that remember what was done to them
            local function Region(kind, parent)
                local r = { kind = kind, parent = parent, calls = {}, shown = true, alpha = 1, level = 1, children = {} }
                if parent then table.insert(parent.children, r) end
                return setmetatable(r, { __index = function(t, k)
                    return function(self, ...) self.calls[k] = { ... } end
                end })
            end
            local F = {}
            function F.Show(self) self.shown = true end
            function F.Hide(self) self.shown = false end
            function F.SetShown(self, v) self.shown = v and true or false end
            function F.SetAlpha(self, a) self.alpha = a end
            function F.GetAlpha(self) return self.alpha end
            function F.GetFrameLevel(self) return self.level end
            function F.SetFrameLevel(self, l) self.level = l end
            function F.CreateTexture(self, _, layer, _, sub) local t = Region("Texture", self) t.layer, t.sub = layer, sub return t end
            function F.CreateMaskTexture(self) return Region("MaskTexture", self) end
            local function New(kind, parent)
                local r = Region(kind, parent)
                for k, fn in pairs(F) do rawset(r, k, fn) end
                return r
            end
            function CreateFrame(kind, _, parent) return New(kind, parent) end

            -- the world: an even projection of yards (Stitch.lua's S.FromYards), 44700 yards across
            local O = 32 * 1600 / 3
            S = { viewHooks = {} }
            function S.Size() return 1.5, 1 end
            S.CaveMasks = "MapCave/"
            function S.FromYards(cont, x, y)
                local du = cont == 0 and 0.55 or 0.04
                return du + (8000 - y) / 44700, 0.1 + (6933 - x) / 29800
            end
            function S.ChainAt() return { 947, contMap } end
            function S.PlaceWorld(region, u0, v0, u1, v1) region.place = { u0, v0, u1, v1 } end
            function S.SetUnderground(t) underground = t end
            contMap = 1415
            setmetatable(S, { __index = function() return function() end end })

            mod = { defaults = {}, db = { underground = true } }
            ns = { MapStitch = S, Media = { path = "Interface\\\\AddOns\\\\OpenMap\\\\Media\\\\", tex = "Interface\\\\AddOns\\\\OpenMap\\\\Media\\\\Textures\\\\Forever\\\\" }, Client = "Forever",
                L = setmetatable({}, { __index = function(_, k) return k end }) }
            function ns:GetModule() return mod end
        """)
        g = self.lua.globals()
        for rel in ("Data/Forever/Caves.lua", "Data/Forever/CaveMinimap.lua", "Data/Forever/Tiles.lua", "Map/Close.lua"):
            fn = self.lua.execute("return function(src, name, ns) local f = assert(loadstring(src, '@' .. name)) return f('OpenMap', ns) end")
            fn((ROOT / rel).read_text(encoding="utf-8"), rel, g.ns)
        self.lua.execute("""
            under = CreateFrame("Frame")
            S.closeLayers = { under = under, minimap = CreateFrame("Frame"), grain = CreateFrame("Frame") }
            -- a cave from the minimap's list: the first a few hundred yards across, and its middle
            function Pick(cont, least, most)
                for i, c in ipairs(ns.MapCaveMinimap) do
                    local w = math.max(c[4] - c[2], c[5] - c[3])
                    if c[1] == cont and w >= least and w <= most then return i, c end
                end
            end
            function Middle(c)
                contMap = c[1] == 0 and 1415 or 1414    -- (the view over its continent)
                return S.FromYards(c[1], (c[2] + c[4]) / 2, (c[3] + c[5]) / 2)
            end
            -- the view on a world point, `across` normalized wide (3:2), at zoom `steps`
            function Look(u, v, across, steps)
                S.SetView(u, v, across / 2, across / 3, steps, steps)
            end
            function Shown()
                local out = {}
                for _, f in ipairs(under.children) do
                    if f.kind == "Frame" and f.shown then table.insert(out, f) end
                end
                return out
            end
            -- the frame showing a picture file, if one is up
            function Up(fid)
                for _, f in ipairs(Shown()) do
                    for _, t in ipairs(f.children) do
                        if t.kind == "Texture" and t.calls.SetTexture and t.calls.SetTexture[1] == fid then return f end
                    end
                end
            end
        """)

    def test_minimap_cave_surfaces_as_it_fills_the_view(self):
        self.lua.execute("""
            local i, c = Pick(0, 150, 300)
            assert(i, 'a cave of a few hundred yards')
            local u, v = Middle(c)
            local u0, v0, u1, v1 = S.CaveRectAt(u, v)
            assert(u0 and u0 < u and u < u1 and v0 < v and v < v1, 'its box round its middle')
            local w = u1 - u0
            local p = c[6]
            Look(u, v, w * 20, 120)                -- a speck: not yet
            assert(not Up(p[1]), 'surfaced as a speck')
            Look(u, v, w * 1.2, 120)               -- it fills the view
            local shown = { Up(p[1]) }
            assert(shown[1], 'up')
            assert(shown[1].alpha > 0.95, 'all the way up: ' .. shown[1].alpha)
            assert(underground > 0.9, 'the surface dims round it')
            -- each picture: the game's file, clamped to nothing past it, turned as the data says,
            -- a square of its side round its centre
            local textures = 0
            for _, t in ipairs(shown[1].children) do
                if t.kind == "Texture" then textures = textures + 1 end
            end
            assert(textures == #c[6] / 7, 'every picture: ' .. textures)
            local t = shown[1].children[1]
            assert(t.calls.SetTexture[1] == p[1] and t.calls.SetTexture[2] == "CLAMPTOBLACKADDITIVE")
            assert(t.calls.SetRotation[1] == p[5])
            local tc = t.calls.SetTexCoord
            assert(tc[1] == 0 and tc[2] == p[6] and tc[3] == p[7] and tc[4] == 1)
            local cu, cv = S.FromYards(c[1], p[2], p[3])
            local pl = t.place
            assert(math.abs((pl[1] + pl[3]) / 2 - cu) < 1e-9 and math.abs((pl[2] + pl[4]) / 2 - cv) < 1e-9, 'centred')
            assert(math.abs((pl[3] - pl[1]) - p[4] / 44700) < 1e-9 and math.abs((pl[4] - pl[2]) - p[4] / 29800) < 1e-9, 'its side')
            -- lowest floor first: draw sublevels never fall
            local last = -9
            for _, tx in ipairs(shown[1].children) do
                if tx.kind == "Texture" then assert(tx.sub >= last and tx.sub <= 7) last = tx.sub end
            end
            Look(u, v, w * 20, 120)                -- back out: it sinks
            assert(not Up(p[1]))
        """)

    def test_a_cave_waits_for_the_zoom(self):
        self.lua.execute("""
            local _, c = Pick(1, 400, 900)
            local u, v = Middle(c)
            local u0, _, u1 = S.CaveRectAt(u, v)
            Look(u, v, (u1 - u0) * 1.2, 20)        -- it would fill the view, but the zoom's a zone's
            assert(not Up(c[6][1]))
            Look(u, v, (u1 - u0) * 1.2, 60)
            assert(Up(c[6][1]))
        """)

    def test_blizzards_cave_map_surfaces_too(self):
        self.lua.execute("""
            local c = ns.MapCaves[38]            -- Fargodeep Mine
            local u, v = S.FromYards(c[2], (c[3] + c[5]) / 2, (c[4] + c[6]) / 2)
            local u0, v0, u1, v1 = S.CaveRectAt(u, v)
            assert(u0, 'its box')
            Look(u, v, (u1 - u0) * 1.2, 120)
            -- (drawn from OpenMap's copy of the tile: Data/Forever/Tiles.lua; the game's is green on other languages' clients)
            assert(c[11][1] == ns.Media.tex .. "MapTile\\\\603267", c[11][1])
            assert(Up(c[11][1]))
        """)

    def test_nothing_round_open_ground_and_the_option_off(self):
        self.lua.execute("""
            assert(S.CaveRectAt(0.02, 0.98) == nil, 'a cave out at sea')
            local _, c = Pick(0, 150, 300)
            local u, v = Middle(c)
            mod.db.underground = false
            assert(S.CaveRectAt(u, v) == nil, 'the zoom goes on with caves off')
            Look(u, v, 0.001, 120)
            assert(#Shown() == 0)
        """)

    def test_the_cave_at_an_entrance(self):
        self.lua.execute("""
            local i, c = Pick(1, 100, 900)
            local key, u0 = S.CaveAt(c[1], (c[2] + c[4]) / 2, (c[3] + c[5]) / 2)
            assert(u0, 'found')
            assert(key == -i or ns.MapCaves[key], 'a cave of either list')
        """)

    # Ironforge's map (uiMap 1455): its box in yards (UiMapAssignment, build 1.60.1.70245), and places on
    # it by its art's pixels (1002 x 668): the Mystic Ward, the Forlorn Cavern, the Hall of Explorers, the
    # Gates, the Great Forge
    IRONFORGE = """
        CITY = { [1455] = { 0, -5096.85, -1504.22, -4569.24, -713.59 } }
        function S.Rect(mapID)
            local c = CITY[mapID]
            if not c then return end
            local u0, v0 = S.FromYards(c[1], c[4], c[5])
            local u1, v1 = S.FromYards(c[1], c[2], c[3])
            return math.min(u0, u1), math.max(u0, u1), math.min(v0, v1), math.max(v0, v1)
        end
        function OnIronforge(px, py)            -- (yards)
            local c = CITY[1455]
            return c[4] - py / 668 * (c[4] - c[2]), c[5] - px / 1002 * (c[5] - c[3])
        end
        PLACES = { { 260, 140 }, { 480, 90 }, { 700, 120 }, { 180, 545 }, { 500, 300 } }
        contMap = 1415
    """

    def test_mended_pictures_are_ours_and_there(self):
        """a picture mended where the game's own has a fault baked in (tools/map-caves/minimap.py's MEND:
        215101's white block, #114) is OpenMap's copy, under Media, and the file is there"""
        files = self.lua.eval("""(function()
            local out = {}
            for _, c in ipairs(ns.MapCaveMinimap) do
                local p = c[6]
                for j = 1, #p, 7 do if type(p[j]) == "string" then out[#out + 1] = p[j] end end
            end
            return out
        end)()""")
        files = list(files.values())
        self.assertGreater(len(files), 0, "a mended picture (MEND) in the data")
        prefix = "Interface\AddOns\OpenMap\Media\Textures\Forever\\"
        for f in files:
            self.assertTrue(f.startswith(prefix), f)
            path = ROOT / "Media" / "Textures" / "Forever" / (f[len(prefix):].replace("\\", "/") + ".tga")
            self.assertTrue(path.exists(), "%s: %s isn't there" % (f, path))

    def test_ironforge_is_no_cave(self):
        # no cave map nor cave from the minimap at Ironforge's wards: nothing surfaces there, nothing
        # dims the city's own map round it
        self.lua.execute(self.IRONFORGE + """
            for _, p in ipairs(PLACES) do
                local x, y = OnIronforge(p[1], p[2])
                assert(S.CaveAt(0, x, y) == nil, 'a cave at ' .. p[1] .. ', ' .. p[2])
                local u, v = S.FromYards(0, x, y)
                assert(S.CaveRectAt(u, v) == nil, 'the zoom held for a cave at ' .. p[1] .. ', ' .. p[2])
                for _, across in ipairs({ 0.0005, 0.002, 0.008 }) do
                    Look(u, v, across, 120)
                    assert(#Shown() == 0, 'a cave up at ' .. p[1] .. ', ' .. p[2])
                    assert(underground == 0, 'the surface dimmed at ' .. p[1] .. ', ' .. p[2])
                end
            end
            -- and none anywhere in the city's box
            local c = CITY[1455]
            for i = 0, 10 do
                for j = 0, 10 do
                    local x, y = c[2] + (c[4] - c[2]) * i / 10, c[3] + (c[5] - c[3]) * j / 10
                    assert(S.CaveAt(0, x, y) == nil, 'a cave in Ironforge at ' .. x .. ', ' .. y)
                end
            end
        """)

    def test_ironforge_has_the_game_minimap_of_it(self):
        self.lua.execute(self.IRONFORGE + """
            local c = ns.MapCityMinimap and ns.MapCityMinimap[1455]
            assert(c and c[1] == 0, 'Ironforge in MapCityMinimap')
            local box, p = CITY[1455], c[6]
            assert(#p / 7 >= 50, 'its pictures: ' .. #p / 7)
            for i = 1, #p, 7 do                  -- (each in the city, give or take a picture's side)
                assert(p[i + 1] > box[2] - 64 and p[i + 1] < box[4] + 64 and p[i + 2] > box[3] - 64 and p[i + 2] < box[5] + 64,
                    'a picture off the city: ' .. p[i])
            end
            -- the city's own frame (Stitch.lua's), unfound or not
            city = CreateFrame("Frame")
            function S.UndergroundCity(mapID) if mapID == 1455 then return city, cityHidden, cityDark end end
            function S.CityCover() return 1 end    -- (the view on the city: the surface's minimap kept off)
            mod.db.minimap, mod.db.minimapMix, mod.db.minimapDeep, mod.db.minimapFrom = true, 0.45, 0.85, 20
            local function Pics()
                local out = {}
                for _, t in ipairs(city.children) do if t.kind == "Texture" then table.insert(out, t) end end
                return out
            end
            -- (shown: anchored where it lies; hidden: let go)
            local function Alpha(t)
                if not (t.calls.SetShown and t.calls.SetShown[1]) then return 0 end
                assert(t.place == placed[t], 'shown and not placed')
                return t.calls.SetAlpha[1]
            end
            placed = setmetatable({}, { __mode = "k" })
            function S.PlaceWorld(region, u0, v0, u1, v1) region.place = { u0, v0, u1, v1 } placed[region] = region.place end
            function S.UnplaceWorld(region) placed[region] = nil end
            local u, v = S.FromYards(0, OnIronforge(500, 300))
            Look(u, v, 0.05, 5)                  -- (from far out: no minimap yet, none made)
            assert(#Pics() == 0, 'made from far out')
            Look(u, v, 0.002, 60)                -- the deepest: the minimap's most over a city
            local pics = Pics()
            assert(#pics == #p / 7, 'every picture: ' .. #pics)
            assert(S.closeView.mix == 0, 'the surface minimap over it')
            for _, t in ipairs(pics) do
                assert(t.layer == "OVERLAY", 'over the city map: ' .. tostring(t.layer))
                assert(math.abs(Alpha(t) - 0.5) < 1e-9, 'as strong as over a city: ' .. Alpha(t))
                assert(t.calls.SetTexture[2] == "CLAMPTOBLACKADDITIVE")
            end
            local t = pics[1]
            assert(t.calls.SetTexture[1] == p[1] and t.calls.SetRotation[1] == p[5])
            local cu, cv = S.FromYards(0, p[2], p[3])
            assert(math.abs((t.place[1] + t.place[3]) / 2 - cu) < 1e-9 and math.abs((t.place[2] + t.place[4]) / 2 - cv) < 1e-9, 'centred')
            Look(u, v, 0.003, 25)                -- coming in: weaker
            assert(Alpha(t) > 0 and Alpha(t) < 0.5, 'coming in: ' .. Alpha(t))
            Look(u, v, 0.05, 5)                  -- back out: gone
            assert(Alpha(t) == 0 and placed[t] == nil, 'gone, and let go of its anchor')
            city:SetAlpha(0)                     -- the city's own map not in yet: none of it either
            Look(u, v, 0.002, 60)
            assert(Alpha(t) == 0)
            city:SetAlpha(1)
            local x, y = OnIronforge(500, 300)
            local fu, fv = S.FromYards(0, x + 3000, y)
            Look(fu, fv, 0.002, 60)              -- elsewhere: gone
            assert(Alpha(t) == 0)
            cityHidden = true                    -- an unfound city, unexplored areas hidden: gone with its map
            Look(u, v, 0.002, 60)
            assert(Alpha(t) == 0)
            cityHidden, cityDark = false, { 0.38, 0.39, 0.43, 0.25 }   -- ... darkened: darkened with it
            Look(u, v, 0.002, 60)
            assert(Alpha(t) == 0.5)
            local r, g, b = unpack(t.calls.SetVertexColor)
            assert(r < 0.5 and g < 0.5 and b < 0.5, 'darkened')
            cityDark = nil
            Look(u, v, 0.002, 60)
            assert(t.calls.SetVertexColor[1] > 0.9, 'and back')
            mod.db.minimap = false               -- the minimap's detail off: the city's too
            Look(u, v, 0.002, 60)
            assert(Alpha(t) == 0)
        """)

    def tearDown(self):
        errs = list(self.lua.globals().errors.values())
        failed = dict(self.lua.globals().S.closeFailed.items())
        self.assertNotIn("underground", failed, failed.get("underground"))
        self.assertNotIn("underground cities' minimap", failed, failed.get("underground cities' minimap"))
        self.assertFalse([e for e in errs if "underground" in str(e)], errs)


if __name__ == "__main__":
    unittest.main()
