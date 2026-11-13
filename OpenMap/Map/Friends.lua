--------------------------------------------------------------------------------
-- Friends and guild on the map, each with its own switch (Options: Friends on the map,
-- Guild members on the map). Everyone online on your friends list (Battle.net friends playing
-- this game too) and in your guild shows by zone, as the game's own lists give it: a badge on the
-- zone, with who's there. Those who use OpenMap and share where they are show as a class-coloured
-- dot where they stand instead. Your party and raid are left to Nav.lua's bordered dots, which ask
-- mod.FriendPlace for what's known here of those the game won't place.
-- Sharing (asked once as the map opens; the menu's and Options' Share where you are; off unless turned on): your place as an addon message
-- (prefix OpenMapLoc) every few seconds while you move, each minute while you stand still, to your
-- guild and to your friends who use OpenMap; never from inside a dungeon, raid or battleground.
-- Friends who use OpenMap are found by a hello to each as they come online (H1, answered H2).
-- The messages: "L1 map x y class level" (tab-separated; a uiMapID, x and y on it 0..1),
-- "L0" (stopped sharing), "H1", "H2". Nothing here runs per frame while the map is closed: what
-- arrives is noted, and drawn when the map opens.
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")
local Safe, L = ns.Safe, ns.L
-- timed for /openmap status after an opening (WorldMap.lua's mod.TimeAfter; plain, without it)
local function Timed(name, fn, ...)
	if mod.TimeAfter then return mod.TimeAfter(name, fn, ...) end
	return fn(...)
end

mod.defaults.friends = true         -- friends on the map
mod.defaults.guild = true           -- guild members on the map
mod.defaults.friendsShare = false   -- your place sent to your guild and your friends who use OpenMap

local PREFIX = "OpenMapLoc"         -- (its own: the game holds back a burst per prefix, Pins.lua's apart)
local TICK = 2                      -- seconds between looks at where you are
local SEND_EVERY = 10               -- seconds between places sent while you move
local STILL_EVERY = 60              -- ... and while you stand still (a dot that's heard from stays)
local GONE_AFTER = 150              -- seconds without word before someone's dot goes
local MOVED = 0.002                 -- (a move this small on a zone's map isn't one)
local SEND_GAP = 0.5                -- seconds between messages sent
local ROSTER_EVERY = 30             -- seconds between asking for the guild roster while the map is open
local REDRAW_EVERY = 10             -- seconds between redraws while the map is open (dots gone stale, the group changed)
local LIST_MAX = 25                 -- names in a zone's tooltip
local DOT = { atlas = "WhiteCircle-RaidBlips", texture = "Interface\\Minimap\\PartyRaidBlips" }
local BADGE = { atlas = "socialqueuing-icon-group", texture = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", size = 18 }

local me = {}                       -- (this file's events' owner: Pins.lua has the module's CHAT_MSG_ADDON)
local map
local dotSet, zoneSet
local roster = {}                   -- full name -> { name, class, level, area, guild, friend, guid }: online now
local guildGuids = {}                -- Forever character name -> guild GUID, or false if ambiguous
local friends = {}                  -- full name -> { whisper = name } or { bn = gameAccountID }: online now
local known = {}                    -- full name -> true: friends who use OpenMap
local live = {}                     -- full name -> { map, x, y, class, level, guild, guid, at }: those sharing
local looks = {}                    -- class -> a dot's look
local dirty = false
local zoneByName, classByName, realm
local last = { at = -math.huge }    -- your place as last sent: map, x, y, at, text
local sharing = false               -- (a place sent since sharing began: they're told when it stops)

--------------------------------------------------------------------------------
-- Names
--------------------------------------------------------------------------------

-- your realm as UnitFullName gives it
local function ApiRealm()
	if not UnitFullName then return end
	local ok, _, r = pcall(UnitFullName, "player")
	if ok and not Safe.IsSecret(r) and type(r) == "string" and r ~= "" then return r end
end

local function Realm()
	if not realm then
		local r = Safe.Call(GetNormalizedRealmName)
		if type(r) ~= "string" or r == "" then r = ApiRealm() end
		if type(r) ~= "string" or r == "" then r = (Safe.Call(GetRealmName) or ""):gsub("[%s%-]", "") end
		if r == "" then return "" end   -- (not known yet, early in a login: asked again later)
		realm = r
	end
	return realm
end

-- a realm as compared: no spaces, hyphens or apostrophes, any case
local function Plain(rlm) return (rlm:gsub("[%s%-']", "")):lower() end

-- Forever's numbered realms share a ruleset map. Compare the pool, not its shard number:
-- CAMWOWEU5Realm4PvP and CAMWOWEU5Realm12PvP both become camwoweu5realmpvp.
local function RealmPool(rlm)
	local key = Plain(rlm)
	if ns.Client == "Forever" then key = key:gsub("realm%d+", "realm") end
	return key
end

local function SamePool(full)
	local _, rlm = full:match("^([^%-]+)%-(.+)$")
	local mine = Realm()
	return rlm and mine ~= "" and RealmPool(rlm) == RealmPool(mine) or false
end

-- "Name-Realm" for a name as the game gives it (on your own realm it comes without one)
local function Full(name, rlm)
	if Safe.IsSecret(name) or type(name) ~= "string" or name == "" then return end
	if name:find("-", 1, true) then return name end
	if type(rlm) == "string" and rlm ~= "" then return name .. "-" .. rlm:gsub("[%s%-]", "") end
	return name .. "-" .. Realm()
end

-- the name to show: without the realm when it's yours
local function Short(full)
	local name, rlm = full:match("^([^%-]+)%-(.+)$")
	if rlm and Realm() ~= "" and Plain(rlm) == Plain(Realm()) then return name end
	return full
end

-- the name shown on the map: never the realm (WoW Forever's realm names read "CAMWOWUS1Realm2PvP"),
-- one from another realm marked " (*)" as the game's own lists do
local function Shown(full)
	local name = full:match("^[^%-]+") or full
	if Short(full) ~= full then name = name .. (FOREIGN_SERVER_LABEL or " (*)") end
	return name
end

local function Me() return Full(Safe.Call(UnitName, "player")) end

-- you, however the game writes your realm (a guild message or roster name may not match your own API's
-- spelling of it): your name and a realm the game calls yours, or the roster entry with your GUID
local selfFull
local function IsMe(full)
	if type(full) ~= "string" then return false end
	if full == selfFull or full == Me() then return true end
	local me = Safe.Call(UnitName, "player")
	if Safe.IsSecret(me) or type(me) ~= "string" then return false end
	local name, rlm = full:match("^([^%-]+)%-?(.*)$")
	if name ~= me then return false end
	if rlm == "" then return true end
	rlm = Plain(rlm)
	for _, mine in ipairs({ Realm(), Safe.Call(GetNormalizedRealmName) or "", Safe.Call(GetRealmName) or "", ApiRealm() or "" }) do
		if type(mine) == "string" and not Safe.IsSecret(mine) and mine ~= "" and Plain(mine) == rlm then return true end
	end
	return false
end

-- Addon messages carry a name without a GUID. Match both parts of a Forever
-- name when the sender and guild roster use different separators or realm labels.
local function GuildNameKey(name)
	if ns.Client ~= "Forever" then return end
	local character, suffix = name:match("^(.+)%-([^%-]+)$")
	if suffix then
		local label = Plain(suffix)
		local ownRealm = Safe.Call(GetNormalizedRealmName) or Safe.Call(GetRealmName)
		if label:match("^camwow%a+%d+realm%d+%a+$") or (type(ownRealm) == "string" and label == Plain(ownRealm)) then
			name = character
		end
	end
	local first, surname = name:match("^([^%s%-]+)[%s%-]+([^%s%-]+)$")
	if first then return (first .. "-" .. surname):lower() end
end

local function CharacterGUID(guid)
	guid = Safe.Value(guid)
	if type(guid) == "string" and guid ~= "" then return guid end
end

local function InGroup(full, guid)
	if not IsInGroup() then return false end
	if not guid then
		local r = roster[full]
		guid = r and r.guid
	end
	if guid then
		local grouped = Safe.Call(C_PartyInfo and C_PartyInfo.IsGUIDInGroup, guid)
		if grouped ~= nil then return grouped end
	end
	local short = Short(full)
	return (Safe.Call(UnitInParty, short) or Safe.Call(UnitInRaid, short)) and true or false
end

-- a class's file name (MAGE) from its name in the client's language (the friends list has only that)
local function ClassFile(name)
	if type(name) ~= "string" then return end
	if not classByName then
		classByName = {}
		for file, n in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do classByName[n] = file end
		for file, n in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do classByName[n] = file end
	end
	return classByName[name]
end

local function ClassColor(class)
	local c = type(class) == "string" and ((C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function ZoneName(id)
	local info = id and C_Map.GetMapInfo(id)
	return info and info.name or "?"
end

-- a zone's uiMapID from its name, as the guild roster and friends list give it (a dungeon's
-- name, or a place not on the world map: none)
local function ZoneMap(area)
	if Safe.IsSecret(area) or type(area) ~= "string" or area == "" then return end
	if not zoneByName then
		local t = {}
		local ok, kids = pcall(C_Map.GetMapChildrenInfo, S.WORLD, Enum.UIMapType.Zone, true)
		if ok and type(kids) == "table" then
			for _, info in ipairs(kids) do
				if info.name and not t[info.name] and S.Rect(info.mapID) then t[info.name] = info.mapID end
			end
		end
		if not next(t) then return end          -- (asked again next time)
		zoneByName = t
	end
	return zoneByName[area]
end

--------------------------------------------------------------------------------
-- Sending: one message a SEND_GAP, one waiting for each place it goes (a newer one replaces it)
--------------------------------------------------------------------------------

local outbox, order = {}, {}        -- key -> { text, channel, target, bn }; the keys in turn
local sender = CreateFrame("Frame")
sender:Hide()
local wait = 0
sender:SetScript("OnUpdate", function(self, elapsed)
	wait = wait - elapsed
	if wait > 0 then return end
	local key = tremove(order, 1)
	if not key then self:Hide() return end
	local m = outbox[key]
	outbox[key] = nil
	wait = SEND_GAP
	if m.bn then
		if BNSendGameData then pcall(BNSendGameData, m.bn, PREFIX, m.text) end
	elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.SendAddonMessage, PREFIX, m.text, m.channel, m.target)
	end
end)

local function Send(key, text, channel, target, bn)
	if not outbox[key] then order[#order + 1] = key end
	outbox[key] = { text = text, channel = channel, target = target, bn = bn }
	sender:Show()
end

local function ToFriend(full, text)
	local f = friends[full]
	if not f then return end
	if f.bn then Send(full, text, nil, nil, f.bn) else Send(full, text, "WHISPER", f.whisper) end
end

-- to your guild and every friend online who uses OpenMap (a friend in your guild has it from the guild's)
local function Broadcast(text)
	local guild = IsInGuild()
	if guild then Send("GUILD", text, "GUILD") end
	for full in pairs(known) do
		if friends[full] and not (guild and roster[full] and roster[full].guild) then ToFriend(full, text) end
	end
end

-- where you are: a zone's uiMapID and x, y on it; nil in an instance, or when the game won't say
local function Here()
	if Safe.Value(IsInInstance()) then return end
	local best = Safe.Call(C_Map.GetBestMapForUnit, "player")
	if type(best) ~= "number" or not S.Rect(best) then return end
	local p = Safe.Call(C_Map.GetPlayerMapPosition, best, "player")
	if not p then return end
	local x, y = Safe.XY(p)
	if Safe.IsSecret(x) or Safe.IsSecret(y) or type(x) ~= "number" or type(y) ~= "number" then return end
	if x <= 0 and y <= 0 then return end        -- (0, 0: the game doesn't know)
	return best, x, y
end

local function Tick()
	if not mod.db.friendsShare then
		if sharing then sharing = false last.at, last.text = -math.huge, nil Broadcast("L0") end
		return
	end
	local m, x, y = Here()
	if not m then
		if sharing then sharing = false last.at, last.text = -math.huge, nil Broadcast("L0") end
		return
	end
	local moved = m ~= last.map or math.abs(x - last.x) > MOVED or math.abs(y - last.y) > MOVED
	if GetTime() - last.at < (moved and SEND_EVERY or STILL_EVERY) then return end
	local _, class = UnitClass("player")
	class = Safe.Value(class)
	last.map, last.x, last.y, last.at = m, x, y, GetTime()
	last.text = ("L1\t%d\t%.4f\t%.4f\t%s\t%d"):format(m, x, y, type(class) == "string" and class or "",
		tonumber(Safe.Value(UnitLevel("player"))) or 0)
	sharing = true
	Broadcast(last.text)
end

--------------------------------------------------------------------------------
-- Who's online, from the guild roster and the friends lists
--------------------------------------------------------------------------------

local function ScanGuild()
	if not IsInGuild() or not GetGuildRosterInfo then return end
	for i = 1, tonumber(Safe.Value(GetNumGuildMembers())) or 0 do
		local name, _, _, level, _, area, _, _, online, _, class, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		local full = Safe.Value(online) and Full(name)
		guid = CharacterGUID(guid)
		if full and guid and guid == Safe.Call(UnitGUID, "player") then
			selfFull = full   -- (you, as the guild writes you: your realm spelled that way from now on)
			realm = full:match("%-(.+)$") or realm
		elseif full and not IsMe(full) then
			roster[full] = { name = Shown(full), class = Safe.Value(class), level = tonumber(Safe.Value(level)),
				area = Safe.Value(area), guild = true, guid = guid }
			local key = guid and GuildNameKey(name)
			if key then
				local previous = guildGuids[key]
				guildGuids[key] = (previous == nil or previous == guid) and guid or false
			end
		end
	end
end

local function Friend(full, level, area, className, how, guid)
	guid = CharacterGUID(guid)
	local r = roster[full]
	if r and r.guid and guid and r.guid ~= guid then return end
	if not SamePool(full) and not r then return end   -- (a friend outside your realm pool isn't on your map; a guild member is)
	r = r or { name = Shown(full), level = tonumber(Safe.Value(level)), area = Safe.Value(area),
		class = ClassFile(Safe.Value(className)) }
	r.friend = true
	r.guid = r.guid or guid
	roster[full] = r
	-- (Battle.net reaches any realm, a whisper not every one: it's used when both are there)
	if how.bn or not friends[full] then friends[full] = how end
end

local function ScanFriends()
	if not (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex) then return end
	for i = 1, tonumber(Safe.Value(C_FriendList.GetNumFriends())) or 0 do
		local f = C_FriendList.GetFriendInfoByIndex(i)
		local full = type(f) == "table" and Safe.Value(f.connected) and Full(f.name)
		if full then Friend(full, f.level, f.area, f.className, { whisper = f.name }, f.guid) end
	end
end

-- Battle.net friends playing this same game (another game's zones aren't this map's)
local function ScanBattleNet()
	if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return end
	for i = 1, tonumber(Safe.Value(BNGetNumFriends())) or 0 do
		local a = C_BattleNet.GetFriendAccountInfo(i)
		local g = type(a) == "table" and a.gameAccountInfo
		if type(g) == "table" and Safe.Value(g.isOnline) and g.clientProgram == (BNET_CLIENT_WOW or "WoW")
			and (not WOW_PROJECT_ID or g.wowProjectID == WOW_PROJECT_ID) then
			local full = Full(g.characterName, g.realmName)
			if full then Friend(full, g.characterLevel, g.areaName, g.className, { bn = g.gameAccountID }, g.playerGuid) end
		end
	end
end

local function Scan()
	local before = {}
	for full in pairs(friends) do before[full] = true end
	wipe(roster) wipe(guildGuids) wipe(friends)
	for _, scan in ipairs({ ScanGuild, ScanFriends, ScanBattleNet }) do
		local ok, err = pcall(scan)
		if not ok then geterrorhandler()(err) end
	end
	for _, t in ipairs({ roster, friends, live }) do
		for full in pairs(t) do if IsMe(full) then t[full] = nil end end
	end
	-- a friend just online: a hello, to learn whether they use OpenMap (they learn you do)
	if mod.db.friends or mod.db.guild or mod.db.friendsShare then
		for full in pairs(friends) do
			if not before[full] then ToFriend(full, "H1") end
		end
	end
	dirty = true
end

local scanning = false
local function QueueScan()
	if scanning then return end
	scanning = true
	C_Timer.After(1, function() scanning = false Timed("friends and guild scanned", Scan) end)
end

local function AskRosters()
	if IsInGuild() then
		if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
	end
	if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

local function LocationGUID(full, place)
	if place and place.guid then return place.guid end
	local row = roster[full]
	if row and row.guid then return row.guid end
	-- (a guild message names its sender without a GUID: #107's name key finds it in the guild roster)
	local key = place and place.guildKey
	return key and guildGuids[key] or nil
end

local function StopLocation(full, guid)
	guid = guid or LocationGUID(full, live[full])
	if not guid then
		if live[full] then live[full] = nil dirty = true end
		return
	end
	-- A stop applies to the character's position on every channel.
	for sender, place in pairs(live) do
		local senderGUID = LocationGUID(sender, place)
		if senderGUID == guid or (sender == full and not senderGUID) then
			live[sender] = nil
			dirty = true
		end
	end
end

local function Heard(full, text, guild, guid, sender)
	local kind, m, x, y, class, level = strsplit("\t", text, 6)
	if friends[full] then known[full] = true end
	if kind == "H1" or kind == "H2" then
		-- (a hello: answered with your place when you share it, so they know you use OpenMap either way)
		if kind == "H1" and friends[full] then ToFriend(full, sharing and last.text or "H2") end
		return
	end
	if not guild and not friends[full] then return end   -- (a whisper only from a friend)
	if kind == "L0" then
		StopLocation(full, guid)
	elseif kind == "L1" then
		m, x, y = tonumber(m), tonumber(x), tonumber(y)
		if not (m and x and y) or x < 0 or x > 1 or y < 0 or y > 1 or not S.Rect(m) then return end
		local row = roster[full]
		if guid and row and row.guid and guid ~= row.guid then row = nil end
		local previous = live[full]
		live[full] = { map = m, x = x, y = y, class = class and class:match("^%u+$"), level = tonumber(level),
			guild = guild or (row and row.guild) or false, guildKey = sender and GuildNameKey(sender),
			guid = guid or (row and row.guid) or (previous and previous.guid), at = GetTime() }
		dirty = true
	end
end

local function OnAddonMessage(_, _, prefix, text, channel, from)
	if prefix ~= PREFIX then return end
	if Safe.IsSecret(text) or Safe.IsSecret(from) or Safe.IsSecret(channel) or type(text) ~= "string" then return end
	if channel ~= "GUILD" and channel ~= "WHISPER" then return end
	local full = Full(from)
	if not full or IsMe(full) then return end   -- (your own, sent to your guild)
	Heard(full, text, channel == "GUILD", nil, from)
end

local function OnBattleNetMessage(_, _, prefix, text, _, id)
	if prefix ~= PREFIX then return end
	if Safe.IsSecret(text) or Safe.IsSecret(id) or type(text) ~= "string" or type(id) ~= "number" then return end
	local g = C_BattleNet and C_BattleNet.GetGameAccountInfoByID and C_BattleNet.GetGameAccountInfoByID(id)
	local full = type(g) == "table" and Full(g.characterName, g.realmName)
	if not full or IsMe(full) then return end
	local guid = CharacterGUID(g.playerGuid)
	if guid and guid == Safe.Call(UnitGUID, "player") then return end
	friends[full] = friends[full] or { bn = id }     -- (a Battle.net friend, whatever the last scan saw)
	Heard(full, text, false, guid, g.characterName)
end

--------------------------------------------------------------------------------
-- On the map
--------------------------------------------------------------------------------

local function DotLook(class)
	class = class or "PRIEST"
	local look = looks[class]
	if not look then
		local r, g, b = ClassColor(class)
		look = { atlas = DOT.atlas, texture = DOT.texture, size = 12, color = { r, g, b, 1 } }
		looks[class] = look
	end
	return look
end

local function Tag(guild) return guild and L["Guild"] or L["Friend"] end

local function DotEnter(pin)
	local d = pin.data
	local r = d.roster
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:AddLine(Shown(d.full), ClassColor(d.p.class or (r and r.class)))
	local level = d.p.level or (r and r.level)
	if level and level > 0 then GameTooltip:AddLine((LEVEL or "Level") .. " " .. level, 1, 1, 1) end
	GameTooltip:AddLine(("%s  %.1f, %.1f"):format(ZoneName(d.p.map), d.p.x * 100, d.p.y * 100), 1, 1, 1)
	GameTooltip:AddLine(Tag(d.p.guild), 0.6, 0.8, 1)
	local ago = GetTime() - d.p.at
	if ago >= 20 then GameTooltip:AddLine(L["Updated %d s ago"]:format(ago), 0.6, 0.6, 0.6) end
	GameTooltip:Show()
end

local function ZoneEnter(pin)
	local d = pin.data
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:AddLine(ZoneName(d.map), 1, 0.82, 0)
	for i, r in ipairs(d.people) do
		if i > LIST_MAX then
			GameTooltip:AddLine(L["... and %d more"]:format(#d.people - LIST_MAX), 0.6, 0.6, 0.6)
			break
		end
		local cr, cg, cb = ClassColor(r.class)
		GameTooltip:AddDoubleLine(r.level and r.level > 0 and ("%s  %d"):format(r.name, r.level) or r.name, Tag(r.guild),
			cr, cg, cb, 0.6, 0.8, 1)
	end
	GameTooltip:Show()
end

local function ByName(a, b) return a.name < b.name end

-- Merge identities for drawing while the roster and messages keep their sender keys.
local function PersonFor(people, full, guid)
	local key = guid or full
	if not people[key] then people[key] = { full = full, guid = guid } end
	return people[key]
end

local function Redraw()
	dirty = false
	if not S.IsBuilt() then return end
	dotSet = dotSet or S.PinSet("friends", 0, 4)
	zoneSet = zoneSet or S.PinSet("friendzones", 0, 3)
	S.ClearPinSet(dotSet)
	S.ClearPinSet(zoneSet)
	if not (mod.db.friends or mod.db.guild) or not mod.IsStitched() then return end
	local now, people, zones = GetTime(), {}, {}
	for full, r in pairs(roster) do
		local place = live[full]
		local guid = r.guid or (place and now - place.at <= GONE_AFTER and place.guid)
		local person = PersonFor(people, full, guid)
		person.friend = person.friend or r.friend
		person.guild = person.guild or r.guild
		local zone = ZoneMap(r.area)
		-- Prefer a known zone, then guild roster data when both sources have a zone.
		local rank = (zone and 2 or 0) + (r.guild and 1 or 0)
		if not person.roster or rank > person.rank or (rank == person.rank and full < person.full) then
			person.roster, person.full, person.zone, person.rank = r, full, zone, rank
		end
	end
	for full, p in pairs(live) do
		if now - p.at > GONE_AFTER or IsMe(full) then
			live[full] = nil
		else
			p.guid = LocationGUID(full, p)
			local person = PersonFor(people, full, p.guid)
			person.friend = person.friend or friends[full]
			person.guild = person.guild or p.guild
			local u, v = mod.ToWorld(p.map, p.x, p.y)
			local current = person.location
			if u and (not current or p.at > current.at or (p.at == current.at and full < person.sender)) then
				person.location, person.sender, person.u, person.v = p, full, u, v
			end
		end
	end
	for _, person in pairs(people) do
		local visible = (person.friend and mod.db.friends) or (person.guild and mod.db.guild)
		if visible and not InGroup(person.full, person.guid) then
			local p, id = person.location, person.zone
			if p then
				local pin = S.AddPin(dotSet, person.u, person.v, DotLook(p.class),
					{ full = person.sender, p = p, roster = person.roster })
				pin:SetScript("OnEnter", DotEnter)
				pin:SetScript("OnLeave", GameTooltip_Hide)
			elseif id then
				zones[id] = zones[id] or {}
				tinsert(zones[id], person.roster)
			end
		end
	end
	for id, people in pairs(zones) do
		local l, rr, t, b = S.Rect(id)
		table.sort(people, ByName)
		local pin = S.AddPin(zoneSet, (l + rr) / 2, (t + b) / 2, BADGE, { map = id, people = people })
		if not pin.Count then
			pin.Count = pin:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
			pin.Count:SetPoint("BOTTOMRIGHT", 4, -2)
		end
		pin.Count:SetText(#people > 1 and tostring(#people) or "")
		pin:SetScript("OnEnter", ZoneEnter)
		pin:SetScript("OnLeave", GameTooltip_Hide)
	end
end

-- what's known here of a player by name (Nav.lua's group dots, which this file leaves out of its
-- own): u, v on the world from the place they share; else nil, nil and their zone's uiMapID from
-- the guild roster or friends list; nothing if neither has them
function mod.FriendPlace(name, rlm)
	local full = Full(name, rlm)
	if not full then return end
	local p = live[full]
	if p and GetTime() - p.at <= GONE_AFTER then return mod.ToWorld(p.map, p.x, p.y) end
	local r = roster[full]
	return nil, nil, r and ZoneMap(r.area)
end

function mod.RefreshFriends()
	dirty = true
	if map and map:IsShown() then Redraw() end
	if mod.db.friendsShare or sharing then Tick() end   -- (turned on: sent at once; off: they're told)
end

--------------------------------------------------------------------------------
-- Asked once, the first time the map opens with this version (after the new install's own
-- question, Welcome.lua, has had its turn): whether to share where you are. Off until then, and
-- after Not now; the menu's Share where you are changes it any time. (shareAsked: per account)
--------------------------------------------------------------------------------

local ask

local function Answer(share)
	mod.db.shareAsked = true
	if share then
		mod.db.friendsShare = true
		mod.RefreshFriends()
		if ns.NotifyOptions then ns.NotifyOptions() end
		if mod.RefreshPanel then mod:RefreshPanel() end
	end
	ask:Hide()
end

local function BuildAsk(worldMap)
	ask = CreateFrame("Frame", nil, worldMap)
	ask:SetSize(460, 186)
	ask:SetPoint("CENTER", worldMap.ScrollContainer or worldMap, "CENTER")
	ask:SetFrameStrata("DIALOG")
	ask:EnableMouse(true)
	if mod.padRoots then mod.padRoots[#mod.padRoots + 1] = ask end   -- (the gamepad's cursor presses its buttons: Gamepad.lua)
	local top, _, close = ns.Look:Window(ask, L["Friends and guild"])
	close:Hide()                    -- (an answer is wanted: closing the map asks again next time)
	local text = ask:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOP", 0, -top - 12)
	text:SetWidth(420)
	text:SetText(L["Your friends and guild members who use OpenMap can show on your map as a dot where they stand. Share where you are, so they see you on theirs?"])
	local function Button(x, label, share)
		local b = CreateFrame("Button", nil, ask, "UIPanelButtonTemplate")
		b:SetSize(170, 26)
		b:SetPoint("BOTTOM", ask, "BOTTOM", x, 40)
		b:SetText(label)
		b:SetScript("OnClick", function() Answer(share) end)
	end
	Button(-92, L["Share where I am"], true)
	Button(92, L["Not now"], false)
	local note = ask:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("BOTTOM", 0, 16)
	note:SetWidth(420)
	note:SetText(L["Only your guild and friends, never from a dungeon, raid or battleground. OpenMap's menu: More, Sharing."])
	ask:Hide()
end

local function MaybeAsk(worldMap)
	if mod.db.shareAsked or mod.db.friendsShare or not mod.enabled or mod.db.presetAsked == false then return end
	if InCombatLockdown() then return end
	if not ask then BuildAsk(worldMap) end
	ask:Show()
end

--------------------------------------------------------------------------------

function mod:SetupFriends(worldMap)
	map = worldMap
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
	ns.RegisterEvent(me, "CHAT_MSG_ADDON", OnAddonMessage)
	ns.RegisterEvent(me, "BN_CHAT_MSG_ADDON", OnBattleNetMessage)
	for _, e in ipairs({ "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED",
		"BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "GROUP_ROSTER_UPDATE" }) do
		ns.RegisterEvent(me, e, QueueScan)
	end
	C_Timer.NewTicker(TICK, Tick)
	C_Timer.After(5, function() AskRosters() QueueScan() end)
	-- while the map is open: what arrived drawn each second, the rosters asked for now and then
	local wait, redrawIn, rosterIn = 0, REDRAW_EVERY, 0
	local stitched
	local ticker = CreateFrame("Frame", nil, worldMap)
	ticker:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 1
		redrawIn, rosterIn = redrawIn - 1, rosterIn - 1
		if rosterIn <= 0 then rosterIn = ROSTER_EVERY Timed("friends and guild asked", AskRosters) end
		if redrawIn <= 0 or mod.IsStitched() ~= stitched then dirty = true end
		if dirty then redrawIn, stitched = REDRAW_EVERY, mod.IsStitched() Timed("friends and guild drawn", Redraw) end
	end)
	worldMap:HookScript("OnShow", function()
		wait, rosterIn, dirty = 0, 0, true
		C_Timer.After(0.2, function() if worldMap:IsShown() then MaybeAsk(worldMap) end end)
	end)
end

function mod:FriendsOptions(opts, get, set, off)
	opts.friends = { type = "toggle", name = L["Friends on the map"], order = 35.45, get = get, set = set, disabled = off,
		desc = L["Your friends who are online: a badge on the zone each is in, with who's there (as the friends list shows it), or a class-coloured dot where they stand for those who use OpenMap and share where they are."] }
	opts.guild = { type = "toggle", name = L["Guild members on the map"], order = 35.5, get = get, set = set, disabled = off,
		desc = L["Your guild members who are online: a badge on the zone each is in, with who's there (as the guild roster shows it), or a class-coloured dot where they stand for those who use OpenMap and share where they are."] }
	opts.friendsShare = { type = "toggle", name = L["Share where you are"], order = 35.6, get = get, set = set, disabled = off,
		desc = L["Your guild, and your friends who use OpenMap, see you as a dot where you stand on their map, sent every few seconds while you move. Never from inside a dungeon, raid or battleground. Off, they see only your zone, as the friends list and guild roster show it."] }
end
