"""Whole-map brightness in Lua 5.1; run with python -P tools/offline-test/brightness.py."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[2] / "OpenMap"


class BrightnessTests(unittest.TestCase):
    def test_brightness_controls_and_map_lifecycle(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
        local function noop() end
        created = 0
        function CreateFrame(kind, name, parent)
            created = created + 1
            local f = { parent = parent, scripts = {} }
            function f:Hide() self.shown = false end
            function f:Show() self.shown = true end
            function f:SetShown(v) self.shown = v and true or false end
            function f:SetScript(k, v) self.scripts[k] = v end
            function f:SetAllPoints(target) self.points = target end
            function f:EnableMouse(v) self.mouse = v end
            function f:SetFrameLevel(v) self.level = v end
            function f:CreateTexture(_, layer)
                local t = { layer = layer }
                function t:SetAllPoints(target) self.points = target end
                function t:SetColorTexture(r, g, b, a) self.colour = {r, g, b, a} end
                function t:SetAlpha(a) self.alpha = a end
                return t
            end
            return f
        end
        ns = { L = setmetatable({}, {__index = function(_, k) return k end}) }
        function ns:NewModule(_, m) self.mod = m; return m end
        function ns.Desc() return {} end
        function ns.Header() return {} end
        function ns.Bind(getTable, refresh)
            return function(info) return getTable()[info[#info]] end,
                function(info, value) getTable()[info[#info]] = value; refresh() end
        end
        function GetLocale() return "ruRU" end
        Enum = { UIMapType = {Continent = 2, Zone = 3} }
        C_Map = {GetMapInfo = function(id) return {mapType = id == 1 and 3 or 4} end}
        local S = {WORLD = 947, artTop = 180, built = true}
        ns.MapStitch = S
        function S.IsBuilt() return S.built end
        function S.Rect() return 0, 1, 0, 1 end
        function S.ArtSize() return 1024 end
        function S.Size() return 1024, 768 end
        function S.Layout() return true end
        function S.Stitched() return true end
        function S.SetShown(shown) S.shown = shown end
        function S.GetPinSet() end
        S.SetPlayer = noop
        S.SetPlayerHidden = noop
        S.SetPlacesFrom = noop
        S.SetFoundOnly = noop
        S.SetIconScale = noop
        S.SetGapFillsShown = noop
        S.ApplyGrade = noop
        S.SetZoom = noop
        MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE = 0
        ''')
        source = (ROOT / 'Map/WorldMap.lua').read_text(encoding='utf-8')
        mod, set_context, attach = lua.execute(source + '\nreturn mod, function(c, m) sc, map = c, m end, Attach', 'OpenMap', lua.globals().ns)
        lua.globals().mod = mod
        lua.globals().setContext = set_context
        lua.globals().attach = attach
        lua.execute((ROOT / 'Locales/ruRU.lua').read_text(encoding='utf-8'), 'OpenMap', lua.globals().ns)
        lua.execute('''
        local S = ns.MapStitch
        local viewport = {width = 1024, height = 768}
        function viewport:SetMouseWheelZoomMode(v) self.wheel = v end
        function viewport:SetScalingMode(v) self.scaling = v end
        function viewport:GetCanvasScale() return 1 end
        function viewport:GetWidth() return self.width end
        function viewport:GetHeight() return self.height end
        function viewport:GetCurrentScrollX() return 0.5 end
        function viewport:GetCurrentScrollY() return 0.5 end
        local map = {id = 947}
        function map:EnumeratePinsByTemplate() return function() end end
        function map:GetMapID() return self.id end
        function map:IsShown() return false end
        mod.db, mod.enabled = {}, true
        for key, value in pairs(mod.defaults) do mod.db[key] = value end
        assert(mod.db.brightness == 1)
        setContext(viewport, map)
        attach(947)
        assert(not mod.brightnessShade, "default brightness must not allocate a shade")
        mod.db.brightness = 0.6
        setContext(nil, nil)
        mod:UpdateBrightness()
        assert(not mod.brightnessShade, "must wait for map setup")
        setContext(viewport, map)
        S.built = false
        mod:UpdateBrightness()
        assert(not mod.brightnessShade, "must wait for art setup")
        S.built = true
        attach(947)
        local shade = mod.brightnessShade
        assert(shade.shown and math.abs(shade.texture.alpha - 0.4) < 0.000001)
        assert(shade.parent == viewport and shade.points == viewport)
        assert(shade.mouse == false and shade.scripts.OnUpdate == nil)
        assert(shade.level == S.artTop, "above all stitched art, under pins")
        local count = created
        local options = mod:Options()
        assert(options.brightness.name == "Яркость карты")
        assert(options.brightness.min == 0.25 and options.brightness.max == 1)
        options.brightness.set({"brightness"}, 0.25)
        assert(shade.shown and shade.texture.alpha == 0.75 and mod.db.brightness == 0.25)
        options.brightness.set({"brightness"}, 1)
        assert(not shade.shown and shade.texture.alpha == 0)
        options.brightness.set({"brightness"}, 0.5)
        assert(shade.shown and shade.texture.alpha == 0.5)
        map.id = 1
        attach(1)
        assert(shade.shown, "zone changes retain brightness")
        map.id = 2
        attach(2)
        assert(not shade.shown, "non-stitched dungeon map must not be darkened")
        map.id = 947
        attach(947)
        assert(shade.shown, "returning to world map restores brightness")
        viewport.width, viewport.height = 1600, 900
        mod:UpdateBrightness()
        assert(shade.points == viewport, "shade follows viewport resizing, not canvas zoom")
        mod.db.brightness = -1
        mod:UpdateBrightness()
        assert(shade.texture.alpha == 0.75)
        mod.db.brightness = 2
        mod:UpdateBrightness()
        assert(shade.texture.alpha == 0 and not shade.shown)
        mod.db.brightness = "invalid"
        mod:UpdateBrightness()
        assert(shade.texture.alpha == 0 and not shade.shown)
        mod.db.brightness = 0.25
        mod:ResetSliders()
        assert(mod.db.brightness == 1 and not shade.shown and shade.texture.alpha == 0)
        mod.enabled = false
        attach(947)
        assert(not shade.shown)
        assert(created == count, "refreshes must reuse one frame and texture")
        ''')


if __name__ == "__main__":
    unittest.main()
