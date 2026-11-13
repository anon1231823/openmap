"""Player arrow and location ping visibility in Lua 5.1: python -P tools/offline-test/player.py."""
from pathlib import Path
import re
import unittest

from lupa.lua51 import LuaRuntime


SOURCE = (Path(__file__).resolve().parents[2] / 'OpenMap/Map/WorldMap.lua').read_text(encoding='utf-8')


class PlayerTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            combat, active, PLAYER_ABOVE = false, true, 8500
            mod = { db = { playerArrow = false } }
            S = setmetatable({}, { __index = function() return function() end end })
            sc = { GetFrameLevel = function() return 10 end }
            SET_OPTION = {}
            function ApplyChart() end
            function ApplyZoom() end
            function mod:UpdateBrightness() end
            function mod.Unexplored() return 'show' end
            function InCombatLockdown() return combat end
            function hooksecurefunc(pin, key, callback)
                local original = pin[key]
                assert(type(original) == 'function')
                pin.hooks[key] = (pin.hooks[key] or 0) + 1
                pin[key] = function(...)
                    original(...)
                    callback(...)
                end
            end
            function NewPin()
                local pin = { hooks = {}, sizes = { player = 27, party = 11, raid = 8.25 }, level = 0 }
                function pin:IsProtected() return self.protected or false end
                function pin:GetFrameLevel() return self.level end
                function pin:SetFrameLevel(level)
                    assert(not (self.protected and combat), 'protected frame level')
                    self.level = level
                end
                function pin:SetPinSize(unit, size)
                    assert(not (self.protected and combat), 'protected pin size')
                    self.sizes[unit] = size
                end
                function pin:StartPlayerPing(duration, scale)
                    self.pinging = true
                    self.duration, self.pingScale = duration, scale
                end
                function pin:StopPlayerPing()
                    assert(not (self.protected and combat), 'protected ping')
                    self.pinging = false
                    self.stops = (self.stops or 0) + 1
                end
                pin.dataProvider = { GetUnitPinSizesTable = function()
                    return { player = 27, party = 11, raid = 8.25 }
                end }
                function pin:SynchronizePinSizes() self:SetPinSize('player', 13.5) end
                return pin
            end
            pin = NewPin()
            pins = { pin }
            map = { GetCanvasScale = function() return 2 end, IsShown = function() return true end }
            function map:EnumeratePinsByTemplate(template)
                assert(template == 'GroupMembersPinTemplate')
                local i = 0
                return function() i = i + 1 return pins[i] end
            end
        """)
        # The real visibility helpers and refresh, isolated from the rest of the map's setup.
        helpers = SOURCE[SOURCE.index('local BLIP_GONE'):SOURCE.index('local ticker =')]
        refresh = re.search(r'function mod:Refresh\(\).*?\nend\n', SOURCE, re.S)
        self.assertIsNotNone(refresh)
        self.lua.execute(helpers + '\nfunction Tick() RaisePlayer() end\n' + refresh.group(0))

    def test_disabled_stops_existing_ping(self):
        self.lua.execute("""
            pin:StartPlayerPing(2, .25)
            Tick()
            assert(not pin.pinging, 'existing location ping still visible')
            assert(pin.sizes.player < 1)
            assert(pin.sizes.party == 11 and pin.sizes.raid == 8.25)
        """)

    def test_disabled_stops_new_pings_after_open_and_map_change(self):
        self.lua.execute("""
            Tick()
            for i = 1, 3 do
                pin:StartPlayerPing(2, .25)
                assert(not pin.pinging, 'new location ping still visible')
            end
        """)

    def test_enabled_preserves_normal_pings_and_arrow_size(self):
        self.lua.execute("""
            Tick()
            mod.db.playerArrow = true
            Tick()
            pin:StartPlayerPing(2, .25)
            assert(pin.pinging and pin.duration == 2 and pin.pingScale == .25)
            assert(pin.sizes.player == 13.5)
            mod.db.playerArrow = false
            Tick()
            assert(not pin.pinging)
        """)

    def test_hook_once_and_handle_replacement_pin(self):
        self.lua.execute("""
            for i = 1, 5 do Tick() end
            assert(pin.hooks.StartPlayerPing == 1, 'missing or duplicate ping hook')
            pin = NewPin()
            pins = { pin }
            Tick()
            pin:StartPlayerPing(2, .25)
            assert(not pin.pinging)
            assert(pin.hooks.StartPlayerPing == 1)
        """)

    def test_missing_ping_methods_do_not_break_arrow_visibility(self):
        self.lua.execute("""
            pin.StartPlayerPing = nil
            Tick()
            assert(pin.sizes.player < 1)
            pin = NewPin()
            pin.StopPlayerPing = nil
            pins = { pin }
            Tick()
            assert(pin.sizes.player < 1)
        """)

    def test_group_off_hides_party_and_raid_blips(self):
        self.lua.execute("""
            mod.db.playerArrow, mod.db.group = true, false
            Tick()
            assert(pin.sizes.party < 1 and pin.sizes.raid < 1, 'group blips still drawn (#77)')
            assert(pin.sizes.player == 27)
            pin:SynchronizePinSizes()
            assert(pin.sizes.party < 1 and pin.sizes.raid < 1, 'a zoom step brought group blips back')
            mod.db.group = true
            Tick()
            assert(pin.sizes.party == 5.5 and pin.sizes.raid == 4.125, 'group blips not restored at the canvas scale')
        """)

    def test_ping_without_size_method(self):
        self.lua.execute("""
            pin.SetPinSize = nil
            Tick()
            pin:StartPlayerPing(2, .25)
            assert(not pin.pinging, 'ping handling depends on arrow sizing')
        """)

    def test_protected_pin_waits_until_after_combat(self):
        self.lua.execute("""
            pin.protected, combat = true, true
            pin:StartPlayerPing(2, .25)
            Tick()
            assert(pin.pinging and pin.sizes.player == 27)
            combat = false
            Tick()
            assert(not pin.pinging and pin.sizes.player < 1)
            combat = true
            pin:StartPlayerPing(2, .25)
            assert(pin.pinging)
            Tick()
            combat = false
            Tick()
            assert(not pin.pinging)
        """)

    def test_unprotected_pin_suppresses_pings_in_combat(self):
        self.lua.execute("""
            combat = true
            Tick()
            pin:StartPlayerPing(2, .25)
            assert(not pin.pinging)
        """)

    def test_refresh_immediately_applies_setting(self):
        self.lua.execute("""
            mod.db.playerArrow = true
            Tick()
            pin:StartPlayerPing(2, .25)
            mod.db.playerArrow = false
            mod:Refresh()
            assert(not pin.pinging and pin.sizes.player < 1, 'refresh waits for ticker')
            mod.db.playerArrow = true
            mod:Refresh()
            assert(pin.sizes.player == 13.5)
        """)

    def test_refresh_leaves_inactive_map_alone(self):
        self.lua.execute("""
            active = false
            pin:StartPlayerPing(2, .25)
            mod:Refresh()
            assert(pin.pinging and pin.sizes.player == 27)
        """)

    def test_zoom_keeps_arrow_hidden(self):
        self.lua.execute("""
            Tick()
            pin:SynchronizePinSizes()
            assert(pin.sizes.player < 1)
        """)


if __name__ == '__main__':
    unittest.main()
