"""Friends and guild on the map (Friends.lua) in Lua 5.1: python -P tools/offline-test/friends.py.

What's heard (from whom, on which channel) and what's sent (when, to whom), against a stubbed client:
the guild roster, a friends list, the map's pins, the addon-message channel.
"""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[2] / "OpenMap"

STUB = r"""
NOW, sent, events, frames, pins, badges = 1000, {}, {}, {}, {}, {}
inInstance, inGuild, here, secretText = false, true, { 1429, 0.5, 0.5 }, nil
guild = { { "Guildie-Forever", 30, "Elwynn Forest", true, "MAGE" }, { "Offline-Forever", 20, "Duskwood", false, "ROGUE" } }
friendList = { { name = "Pal", connected = true, level = 40, area = "Westfall", className = "Hunter" },
	{ name = "Far-OtherRealm", connected = true, level = 30, area = "Duskwood", className = "Mage" },
	{ name = "Gone", connected = false, level = 10, area = "Westfall", className = "Hunter" } }

local function Frame()
	local f = { scripts = {}, shown = true }
	function f:SetScript(k, fn) self.scripts[k] = fn end
	function f:HookScript(k, fn) self.scripts[k] = fn end
	function f:Hide() self.shown = false end
	function f:Show() self.shown = true end
	function f:IsShown() return self.shown end
	function f:CreateFontString() return setmetatable({ SetText = function(s, t) s.text = t end }, NOOP) end
	function f:SetText(t) self.text = t end
	frames[#frames + 1] = f
	return setmetatable(f, NOOP)
end
NOOP = { __index = function(_, k) if k ~= "Count" then return function() end end end }
CreateFrame = function() return Frame() end
InCombatLockdown = function() return false end
function Run(seconds)
	-- every frame's OnUpdate, a tenth of a second at a time, and the timers due
	for _ = 1, seconds * 10 do
		NOW = NOW + 0.1
		for _, f in ipairs(frames) do if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.1) end end
		for _, t in ipairs(timers) do
			if not t.done and NOW >= t.at then
				t.fn()
				if t.every then t.at = NOW + t.every else t.done = true end
			end
		end
	end
end
timers = {}
C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = NOW + d, fn = fn } end,
	NewTicker = function(d, fn) timers[#timers + 1] = { at = NOW + d, fn = fn, every = d } end }
GetTime = function() return NOW end
geterrorhandler = function() return error end
strsplit = function(sep, s, n)
	local out = {}
	for piece in (s .. sep):gmatch("([^" .. sep .. "]*)" .. sep) do out[#out + 1] = piece end
	return unpack(out)
end
tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
GetNormalizedRealmName = function() return "Forever" end
UnitName = function() return "Me" end
UnitGUID = function() return "Player-1-0001" end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitLevel = function() return 25 end
IsInGroup = function() return false end
IsInInstance = function() return inInstance, inInstance and "party" or "none" end
IsInGuild = function() return inGuild end
GetNumGuildMembers = function() return #guild end
GetGuildRosterInfo = function(i)
	local g = guild[i]
	return g[1], "", 0, g[2], "", g[3], "", "", g[4], 0, g[5], 0, false, 0, false, 0, g[6]
end
C_FriendList = { GetNumFriends = function() return #friendList end, GetFriendInfoByIndex = function(i) return friendList[i] end }
LOCALIZED_CLASS_NAMES_MALE = { HUNTER = "Hunter", MAGE = "Mage" }
C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
	SendAddonMessage = function(prefix, text, channel, target) sent[#sent + 1] = { prefix = prefix, text = text, channel = channel, target = target } end }
Enum = { UIMapType = { Zone = 3 } }
local zones = { [1429] = "Elwynn Forest", [1436] = "Westfall", [1431] = "Duskwood" }
C_Map = {
	GetBestMapForUnit = function() return here and here[1] end,
	GetPlayerMapPosition = function() if here then return { x = here[2], y = here[3] } end end,
	GetMapInfo = function(id) return { name = zones[id] } end,
	GetMapChildrenInfo = function()
		local t = {}
		for id, name in pairs(zones) do t[#t + 1] = { mapID = id, name = name } end
		return t
	end,
}
GameTooltip_Hide = function() end
issecretvalue = function(v) return v == secretText and v ~= nil end

S = { WORLD = 947 }
function S.Rect(id) if id == 1429 or id == 1436 or id == 1431 then return 0.1, 0.2, 0.1, 0.2 end end
function S.IsBuilt() return true end
function S.PinSet(key) return { key = key } end
function S.ClearPinSet(set) if set.key == "friends" then wipe(pins) else wipe(badges) end end
function S.AddPin(set, u, v, look, data)
	local pin = Frame()
	pin.data = data
	if set.key == "friends" then pins[#pins + 1] = data else badges[#badges + 1] = data end
	return pin
end
mod = { defaults = {}, db = {} }
function mod.IsStitched() return true end
function mod.ToWorld(id, x, y) return x, y end
ns = { MapStitch = S, L = setmetatable({}, { __index = function(_, k) return k end }) }
ns.Look = { Window = function(_, f) askFrame = f return 20, nil, Frame() end }
function ns:GetModule() return mod end
function ns.RegisterEvent(_, event, fn) events[event] = fn end
ns.Safe = {
	IsSecret = function(v) return issecretvalue(v) end,
	Value = function(v) if issecretvalue(v) then return nil end return v end,
	XY = function(p) return p.x, p.y end,
	Call = function(fn, ...) if type(fn) ~= "function" then return nil end local ok, v = pcall(fn, ...) if ok then return v end end,
}
function Fire(event, ...) if events[event] then events[event](nil, event, ...) end end
function Sent(channel, text, target)
	local n = 0
	for _, m in ipairs(sent) do
		if m.channel == channel and (not text or m.text:sub(1, #text) == text) and (not target or m.target == target) then n = n + 1 end
	end
	return n
end
"""


class FriendsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(STUB)
        src = (ROOT / "Map" / "Friends.lua").read_text(encoding="utf-8")
        self.lua.execute("local f = assert(loadstring(...)) f('OpenMap', ns)", src)
        self.lua.execute("""
            for k, v in pairs(mod.defaults) do mod.db[k] = v end
            worldMap = CreateFrame()
            mod:SetupFriends(worldMap)
        """)

    def run_(self, seconds):
        self.lua.eval("Run")(seconds)

    def test_sharing_is_off_unless_turned_on(self):
        self.run_(30)
        self.assertEqual(self.lua.eval("Sent('GUILD')"), 0)

    def test_sharing_sends_to_the_guild_and_stops_with_a_goodbye(self):
        self.lua.execute("mod.db.friendsShare = true mod.RefreshFriends()")
        self.run_(1)
        self.assertEqual(self.lua.eval("Sent('GUILD', 'L1\\t1429\\t0.5000\\t0.5000\\tWARRIOR\\t25')"), 1)
        # standing still: not again for a minute; moving: after ten seconds
        self.run_(20)
        self.assertEqual(self.lua.eval("Sent('GUILD', 'L1')"), 1)
        self.lua.execute("here = { 1429, 0.6, 0.5 }")
        self.run_(3)
        self.assertEqual(self.lua.eval("Sent('GUILD', 'L1')"), 2)
        self.lua.execute("mod.db.friendsShare = false mod.RefreshFriends()")
        self.run_(1)
        self.assertEqual(self.lua.eval("Sent('GUILD', 'L0')"), 1)

    def test_nothing_from_an_instance(self):
        self.lua.execute("mod.db.friendsShare = true mod.RefreshFriends()")
        self.run_(1)
        self.lua.execute("inInstance = true")
        self.run_(5)
        self.assertEqual(self.lua.eval("Sent('GUILD', 'L0')"), 1)
        self.lua.execute("here = { 1429, 0.9, 0.9 }")
        self.run_(30)
        self.assertEqual(self.lua.eval("Sent('GUILD', 'L1')"), 1)

    def test_online_friends_get_a_hello_and_known_ones_the_place(self):
        self.run_(8)                                        # (the first scan, five seconds in)
        self.assertEqual(self.lua.eval("Sent('WHISPER', 'H1', 'Pal')"), 1)
        self.assertEqual(self.lua.eval("Sent('WHISPER', 'H1', 'Gone')"), 0)
        self.lua.execute("mod.db.friendsShare = true mod.RefreshFriends()")
        self.run_(2)
        self.assertEqual(self.lua.eval("Sent('WHISPER', 'L1', 'Pal')"), 0)   # (not known to use OpenMap yet)
        self.lua.execute("Fire('CHAT_MSG_ADDON', 'OpenMapLoc', 'H2', 'WHISPER', 'Pal')")
        self.lua.execute("here = { 1429, 0.7, 0.5 }")
        self.run_(12)
        self.assertEqual(self.lua.eval("Sent('WHISPER', 'L1', 'Pal')"), 1)

    def test_a_friend_on_another_realm_isnt_on_the_map(self):
        self.run_(8)
        self.assertEqual(self.lua.eval("Sent('WHISPER', 'H1', 'Far-OtherRealm')"), 0)
        self.lua.execute("Fire('CHAT_MSG_ADDON', 'OpenMapLoc', 'L1\\t1431\\t0.5\\t0.5\\tMAGE\\t30', 'WHISPER', 'Far-OtherRealm')")
        self.run_(12)
        self.assertEqual(self.lua.eval("#pins"), 0)

    def test_heard_places_and_badges(self):
        self.run_(8)
        self.lua.execute("""
            Fire('CHAT_MSG_ADDON', 'OpenMapLoc', 'L1\\t1429\\t0.3\\t0.4\\tMAGE\\t30', 'GUILD', 'Guildie-Forever')
            Fire('CHAT_MSG_ADDON', 'OpenMapLoc', 'L1\\t1436\\t0.3\\t0.4\\tMAGE\\t30', 'WHISPER', 'Stranger')
            Fire('CHAT_MSG_ADDON', 'OpenMapLoc', 'L1\\t9999\\t0.3\\t0.4', 'GUILD', 'Nowhere-Forever')
            Fire('CHAT_MSG_ADDON', 'OpenMapLoc', 'L1\\t1429\\t3\\t0.4', 'GUILD', 'Far-Forever')
            Fire('CHAT_MSG_ADDON', 'OpenMapLoc', 'L1\\t1429\\t0.3\\t0.4', 'GUILD', 'Me')
            worldMap:Show()
        """)
        self.lua.execute("secretText = 'L1\\t1429\\t0.1\\t0.1' Fire('CHAT_MSG_ADDON', 'OpenMapLoc', secretText, 'GUILD', 'Hidden-Forever')")
        self.run_(2)
        dots = self.lua.eval("(function() local t = {} for _, d in ipairs(pins) do t[#t + 1] = d.full end return table.concat(t, ',') end)()")
        self.assertEqual(dots, "Guildie-Forever")
        # the guildie has a dot: no badge for them; the friend in Westfall has one
        zones = self.lua.eval("(function() local t = {} for _, d in ipairs(badges) do t[#t + 1] = d.map .. ':' .. #d.people end return table.concat(t, ',') end)()")
        self.assertEqual(zones, "1436:1")
        # a dot unheard from goes; the guildie's badge comes back
        self.run_(160)
        self.assertEqual(self.lua.eval("#pins"), 0)
        self.assertIn("1429:1", self.lua.eval("(function() local t = {} for _, d in ipairs(badges) do t[#t + 1] = d.map .. ':' .. #d.people end return table.concat(t, ',') end)()"))

    def test_grouped_guildmates_are_hidden_by_guid(self):
        self.lua.execute("""
            ns.Client = 'Forever'
            FOREIGN_SERVER_LABEL = ''
            GetNormalizedRealmName = function() return 'CAMWOWEU5Realm12PvP' end
            guild = {
                { 'Mara Stonefist-CAMWOWEU5Realm12PvP', 30, 'Elwynn Forest', true, 'MAGE', 'Player-1-0002' },
                { 'Mara Emberfall-CAMWOWEU5Realm12PvP', 30, 'Elwynn Forest', true, 'MAGE', 'Player-1-0003' },
                { 'Edda Silverleaf-CAMWOWEU5Realm12PvP', 30, 'Elwynn Forest', true, 'MAGE', 'Player-1-0004' },
            }
            IsInGroup = function() return group ~= nil end
            UnitInParty = function(unit) return group == 'party' and unit == 'party1' end
            UnitInRaid = function(unit) if group == 'raid' and unit == 'raid1' then return 1 end end
            C_PartyInfo = { IsGUIDInGroup = function(guid)
                return group ~= nil and (guid == 'Player-1-0002' or guid == 'Player-1-0004')
            end }
            function SetGroup(kind)
                group = kind
                Fire('GROUP_ROSTER_UPDATE')
            end
            function BadgeNames()
                local names = {}
                for _, badge in ipairs(badges) do
                    for _, person in ipairs(badge.people) do
                        if person.guild then names[#names + 1] = person.name end
                    end
                end
                table.sort(names)
                return table.concat(names, ',')
            end
            Fire('GUILD_ROSTER_UPDATE')
            Fire('CHAT_MSG_ADDON', 'OpenMapLoc', 'L1\\t1429\\t0.3\\t0.4\\tMAGE\\t30', 'GUILD', 'Mara-Stonefist-CAMWOWEU5Realm4PvP')
        """)
        self.run_(3)
        sender = "Mara-Stonefist-CAMWOWEU5Realm4PvP"
        self.assertEqual(self.lua.eval("pins[1].full"), sender)
        self.assertIn("Edda Silverleaf", self.lua.eval("BadgeNames()").split(","))

        for kind in ("party", "raid"):
            with self.subTest(group=kind):
                self.lua.eval("SetGroup")(kind)
                self.run_(3)
                self.assertEqual((self.lua.eval("#pins"), self.lua.eval("BadgeNames()")), (0, "Mara Emberfall"))

                self.lua.eval("SetGroup")(None)
                self.run_(3)
                self.assertEqual(self.lua.eval("pins[1].full"), sender)
                self.assertIn("Edda Silverleaf", self.lua.eval("BadgeNames()").split(","))

        self.lua.eval("SetGroup")("party")
        self.run_(3)
        self.lua.execute("guild[1][4] = false Fire('GUILD_ROSTER_UPDATE')")
        self.run_(3)
        self.assertEqual((self.lua.eval("#pins"), self.lua.eval("BadgeNames()")), (0, "Mara Emberfall"))

        self.lua.eval("Fire")("CHAT_MSG_ADDON", "OpenMapLoc", "L1\t1429\t0.7\t0.4\tMAGE\t30", "GUILD", sender)
        self.run_(3)
        self.assertEqual(self.lua.eval("#pins"), 0)

        self.lua.eval("SetGroup")(None)
        self.run_(3)
        self.assertEqual(self.lua.eval("pins[1].full"), sender)
        self.assertEqual(self.lua.eval("pins[1].p.x"), 0.7)

    def test_a_battle_net_sender_keeps_their_own_identity(self):
        self.lua.execute("""
            ns.Client = 'Forever'
            GetNormalizedRealmName = function() return 'CAMWOWEU5Realm12PvP' end
            guild = {
                { 'Mara Stonefist-CAMWOWEU5Realm12PvP', 30, 'Elwynn Forest', true, 'MAGE', 'Player-1-0002' },
            }
            IsInGroup = function() return true end
            groupedGUID = 'Player-1-0002'
            C_PartyInfo = { IsGUIDInGroup = function(guid) return guid == groupedGUID end }
            C_BattleNet = { GetGameAccountInfoByID = function()
                return {
                    characterName = 'Mara Stonefist', realmName = 'CAMWOWUS1Realm4PvP',
                    playerGuid = 'Player-2-0003', isInCurrentRegion = false,
                }
            end }
            Fire('GUILD_ROSTER_UPDATE')
        """)
        self.run_(3)
        self.lua.execute("Fire('BN_CHAT_MSG_ADDON', 'OpenMapLoc', 'L1\\t1429\\t0.3\\t0.4\\tMAGE\\t30', 'WHISPER', 42)")
        self.run_(3)
        self.assertEqual(self.lua.eval("pins[1] and pins[1].full"), "Mara Stonefist-CAMWOWUS1Realm4PvP")

        self.lua.execute("groupedGUID = 'Player-2-0003' mod.RefreshFriends()")
        self.assertEqual(self.lua.eval("#pins"), 0)

    def test_no_dot_or_badge_for_yourself_however_your_realm_is_written(self):
        # the guild writes your realm its own way (WoW Forever: "CAMWOWUS1Realm2PvP"); your entry has your GUID
        self.lua.execute("""
            table.insert(guild, { "Me-CAMWOWUS1Realm2PvP", 25, "Elwynn Forest", true, "WARRIOR", "Player-1-0001" })
            Fire('GUILD_ROSTER_UPDATE')
        """)
        self.run_(8)
        self.lua.execute("""
            Fire('CHAT_MSG_ADDON', 'OpenMapLoc', 'L1\\t1429\\t0.5\\t0.5\\tWARRIOR\\t25', 'GUILD', 'Me-CAMWOWUS1Realm2PvP')
            Fire('CHAT_MSG_ADDON', 'OpenMapLoc', 'L1\\t1429\\t0.5\\t0.5\\tWARRIOR\\t25', 'GUILD', 'Me-forever')
            Fire('CHAT_MSG_ADDON', 'OpenMapLoc', 'L1\\t1429\\t0.3\\t0.4\\tMAGE\\t30', 'GUILD', 'Guildie-Forever')
            worldMap:Show()
        """)
        self.run_(2)
        dots = self.lua.eval("(function() local t = {} for _, d in ipairs(pins) do t[#t + 1] = d.full end return table.concat(t, ',') end)()")
        self.assertEqual(dots, "Guildie-Forever")
        people = self.lua.eval("(function() local t = {} for _, d in ipairs(badges) do for _, r in ipairs(d.people) do t[#t + 1] = r.name end end return table.concat(t, ',') end)()")
        self.assertNotIn("Me", people.split(","))

    def ask(self):
        # the open question's buttons: label -> click
        return self.lua.eval("""(function()
            local t = {}
            for _, f in ipairs(frames) do if f.text and f.scripts.OnClick then t[f.text] = f.scripts.OnClick end end
            return t
        end)()""")

    def test_asked_once_whether_to_share(self):
        self.lua.execute("mod.enabled, mod.db.presetAsked = true, true worldMap.scripts.OnShow()")
        self.run_(1)
        buttons = self.ask()
        self.assertIn("Share where I am", buttons)
        buttons["Share where I am"]()
        self.assertTrue(self.lua.eval("mod.db.friendsShare and mod.db.shareAsked"))
        self.run_(1)
        self.assertEqual(self.lua.eval("Sent('GUILD', 'L1')"), 1)

    def test_not_asked_before_the_first_question_or_again(self):
        self.lua.execute("mod.enabled, mod.db.presetAsked = true, false worldMap.scripts.OnShow()")
        self.run_(1)
        self.assertFalse(self.lua.eval("askFrame and askFrame.shown"))   # (the new install's own question first)
        self.lua.execute("mod.db.presetAsked = true worldMap.scripts.OnShow()")
        self.run_(1)
        self.ask()["Not now"]()
        self.assertFalse(self.lua.eval("mod.db.friendsShare"))
        self.assertFalse(self.lua.eval("askFrame.shown"))
        self.lua.execute("worldMap.scripts.OnShow()")
        self.run_(1)
        self.assertFalse(self.lua.eval("askFrame.shown"))   # (asked once)

    def test_turned_off_nothing_on_the_map(self):
        self.run_(8)
        self.lua.execute("mod.db.friends, mod.db.guild = false, false worldMap:Show() mod.RefreshFriends()")
        self.run_(2)
        self.assertEqual(self.lua.eval("#badges"), 0)

    def zone_badges(self):
        return self.lua.eval("(function() local t = {} for _, d in ipairs(badges) do t[#t + 1] = d.map .. ':' .. #d.people end return table.concat(t, ',') end)()")

    def test_guild_off_keeps_friends(self):
        self.run_(8)
        self.lua.execute("mod.db.guild = false worldMap:Show() mod.RefreshFriends()")
        self.run_(2)
        self.assertEqual(self.zone_badges(), "1436:1")

    def test_friends_off_keeps_the_guild(self):
        self.run_(8)
        self.lua.execute("mod.db.friends = false worldMap:Show() mod.RefreshFriends()")
        self.run_(2)
        self.assertEqual(self.zone_badges(), "1429:1")

    def test_guild_off_hides_guild_dots(self):
        self.run_(8)
        self.lua.execute("""
            Fire('CHAT_MSG_ADDON', 'OpenMapLoc', 'L1\\t1429\\t0.3\\t0.4\\tMAGE\\t30', 'GUILD', 'Guildie-Forever')
            worldMap:Show()
        """)
        self.run_(2)
        self.assertEqual(self.lua.eval("#pins"), 1)
        self.lua.execute("mod.db.guild = false mod.RefreshFriends()")
        self.run_(2)
        self.assertEqual(self.lua.eval("#pins"), 0)

    def same_guild_friend(self):
        # The same character comes back under two Forever realm labels.
        self.lua.execute("""
            ns.Client = "Forever"
            GetNormalizedRealmName = function() return "CAMWOWEU5Realm4PvP" end
            memberGuid = "Player-1-0002"
            guild = { { "Guildie Oak-CAMWOWEU5Realm4PvP", 30, "Elwynn Forest", true, "MAGE", memberGuid } }
            friendList = { { name = "Guildie Oak-CAMWOWEU5Realm12PvP", guid = memberGuid,
                connected = true, level = 30, area = "Elwynn Forest", className = "Mage" } }
            local account = { characterName = "Guildie Oak", realmName = "CAMWOWEU5Realm12PvP", playerGuid = memberGuid,
                isOnline = true, clientProgram = "WoW", characterLevel = 30, areaName = "Elwynn Forest",
                className = "Mage", gameAccountID = 17 }
            BNGetNumFriends = function() return 1 end
            C_BattleNet = { GetFriendAccountInfo = function() return { gameAccountInfo = account } end,
                GetGameAccountInfoByID = function(id) if id == 17 then return account end end }
            IsInGroup = function() return grouped == true end
            C_PartyInfo = { IsGUIDInGroup = function(guid) return IsInGroup() and guid == memberGuid end }
        """)
        self.run_(8)

    def test_same_guild_friend_has_one_badge_with_either_switch(self):
        self.same_guild_friend()
        self.assertEqual(self.zone_badges(), "1429:1")
        self.lua.execute("mod.db.guild = false mod.RefreshFriends()")
        self.assertEqual(self.zone_badges(), "1429:1")
        self.lua.execute("mod.db.guild, mod.db.friends = true, false mod.RefreshFriends()")
        self.assertEqual(self.zone_badges(), "1429:1")

    def test_same_display_name_does_not_merge_distinct_guids(self):
        self.same_guild_friend()
        self.lua.execute("""
            guild[1][1] = "Guildie Oak-CAMWOWEU5Realm18PvP"
            friendList[2] = { name = "Guildie Oak-CAMWOWEU5Realm6PvP", guid = "Player-1-0003",
                connected = true, level = 30, area = "Elwynn Forest", className = "Mage" }
            Fire("GUILD_ROSTER_UPDATE")
        """)
        self.run_(3)
        self.assertEqual(self.zone_badges(), "1429:2")

    def test_same_guild_friend_badge_is_hidden_in_group(self):
        self.same_guild_friend()
        self.lua.execute("""
            mod.db.guild = false
            grouped = true
            Fire("GROUP_ROSTER_UPDATE")
        """)
        self.run_(3)
        self.assertEqual(self.zone_badges(), "")
        self.lua.execute('grouped = false Fire("GROUP_ROSTER_UPDATE")')
        self.run_(3)
        self.assertEqual(self.zone_badges(), "1429:1")

    def test_shared_guild_location_replaces_friend_alias_badge(self):
        self.same_guild_friend()
        self.lua.execute("""
            mod.db.guild = false
            Fire("CHAT_MSG_ADDON", "OpenMapLoc", "L1\\t1429\\t0.3\\t0.4\\tMAGE\\t30", "GUILD",
                "Guildie Oak-CAMWOWEU5Realm4PvP")
        """)
        self.run_(2)
        self.assertEqual((self.lua.eval("#pins"), self.zone_badges()), (1, ""))

    def test_cached_location_guid_survives_a_missing_roster_guid(self):
        self.same_guild_friend()
        self.lua.execute('Fire("BN_CHAT_MSG_ADDON", "OpenMapLoc", "L1\\t1429\\t0.7\\t0.8\\tMAGE\\t30", nil, 17)')
        self.run_(2)
        self.lua.execute("""
            friendList = {}
            C_BattleNet.GetGameAccountInfoByID(17).playerGuid = nil
            Fire("BN_FRIEND_INFO_CHANGED")
        """)
        self.run_(3)
        self.assertEqual((self.lua.eval("#pins"), self.zone_badges()), (1, ""))

        self.lua.execute('grouped = true Fire("GROUP_ROSTER_UPDATE")')
        self.run_(3)
        self.assertEqual((self.lua.eval("#pins"), self.zone_badges()), (0, ""))

    def test_same_guild_friend_uses_latest_shared_location_once(self):
        self.same_guild_friend()
        self.lua.execute("""
            Fire("CHAT_MSG_ADDON", "OpenMapLoc", "L1\\t1429\\t0.3\\t0.4\\tMAGE\\t30", "GUILD",
                "Guildie Oak-CAMWOWEU5Realm4PvP")
        """)
        self.run_(2)
        self.lua.execute('Fire("BN_CHAT_MSG_ADDON", "OpenMapLoc", "L1\\t1429\\t0.7\\t0.8\\tMAGE\\t30", nil, 17)')
        self.run_(2)
        self.assertEqual(self.lua.eval("#pins"), 1)
        self.assertEqual(self.lua.eval("pins[1].p.x"), 0.7)
        self.assertEqual(self.lua.eval("pins[1].p.y"), 0.8)
        self.assertEqual(self.zone_badges(), "")

        self.lua.execute('Fire("BN_CHAT_MSG_ADDON", "OpenMapLoc", "L0", nil, 17)')
        self.run_(2)
        self.assertEqual((self.lua.eval("#pins"), self.zone_badges()), (0, "1429:1"))


if __name__ == "__main__":
    unittest.main()
