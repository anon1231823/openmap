--------------------------------------------------------------------------------
-- The quests in your log on the stitched map, from every zone and at any zoom. Blizzard's map
-- shows a zone's quests only on that zone's own map (its QuestDataProvider: MapUtil.
-- ShouldMapTypeShowQuests), so zoomed out, or over the next zone, there were none until the map
-- underneath became theirs. Here every stitched map's quests (C_QuestLog.GetQuestsOnMap) are
-- OpenMap's own icons, in the look of Blizzard's (its map legend's); the map underneath keeps
-- Blizzard's own pins for its quests (and a continent its super-tracked quest's).
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")
local L = ns.L
-- (the quest log's functions: the game's, looked up as they're used)
local function G(name) return _G[name] end

mod.defaults.allQuests = true   -- the quests in your log from every zone (off: Blizzard's, the zone's own map only)

local BADGE = { atlas = "UI-QuestPoi-QuestNumber", texture = "Interface\\GossipFrame\\ActiveQuestIcon", size = 22 }
local IN_PROGRESS = { atlas = "Quest-In-Progress-Icon-yellow", texture = "Interface\\GossipFrame\\IncompleteQuestIcon" }
local TURN_IN = { atlas = "UI-QuestPoi-QuestBangTurnIn", texture = "Interface\\GossipFrame\\ActiveQuestIcon" }
local SAME = 0.002              -- world (normalized): one quest's icons this close are one
local EVERY = 0.5               -- seconds: the quest log changes in bursts
local NONE = {}
local set, map, maps
local dirty = false

-- the maps the quests are read from: the stitched zones and cities (a city's quests are its zone's
-- too, at the same place: one icon, SAME)
local function Maps()
	if maps then return maps end
	maps = {}
	for _, info in ipairs(C_Map.GetMapChildrenInfo(S.WORLD, Enum.UIMapType.Zone, true) or NONE) do
		if S.Rect(info.mapID) then maps[#maps + 1] = info.mapID end
	end
	return maps
end

local function Enter(pin)
	local q = pin.data
	if not q then return end
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q.id)
	GameTooltip:SetText(title or "?", 1, 0.82, 0)
	local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(q.id)
	if q.complete then
		GameTooltip:AddLine(_G.QUEST_WATCH_QUEST_READY or L["Completed"], 0.5, 0.95, 0.4)
	elseif index and G("GetNumQuestLeaderBoards") and G("GetQuestLogLeaderBoard") then
		for i = 1, G("GetNumQuestLeaderBoards")(index) or 0 do
			local text, _, finished = G("GetQuestLogLeaderBoard")(i, index)
			if text and not finished then GameTooltip:AddLine((_G.QUEST_DASH or "- ") .. text, 1, 1, 1, true) end
		end
	end
	GameTooltip:AddLine((map and map.IsMaximized and map:IsMaximized()) and L["Click: track this quest and zoom to it"]
		or L["Click: track this quest, zoom to it and show it in the quest log"], 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

-- a click: the quest tracked (as Blizzard's own quest icons do), the view in on it, and on the windowed
-- map its details in the quest log beside it, opened if it was closed. Not full screen: Blizzard's
-- details call takes the map out of full screen into the windowed map with its log. Never in combat:
-- opening the log lays the window out again
local ZOOM_TO = 6
local function Click(pin)
	local q = pin.data
	if not q then return end
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
		if C_QuestLog.AddQuestWatch and not (C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(q.id)) then
			pcall(C_QuestLog.AddQuestWatch, q.id)
		end
		C_SuperTrack.SetSuperTrackedQuestID(q.id)
	end
	if S.GlideToWorld then S.GlideToWorld(pin.u, pin.v, ZOOM_TO) end
	-- (in combat with the gamepad's UI, Blizzard's quest details would set the pad's buttons from
	-- OpenMap's code, which combat blocks: they wait, as a dungeon's map does)
	if mod.PadWaits and mod.PadWaits() then return end
	local log = map and map.QuestLog
	local details = G("QuestMapFrame_ShowQuestDetails")
	if not log or not details or (map.IsMaximized and map:IsMaximized()) then return end
	if not log:IsShown() and not InCombatLockdown() and map.HandleUserActionOpenSidePanel then
		map:HandleUserActionOpenSidePanel()
		if map.SidePanelToggle and map.SidePanelToggle.Refresh then map.SidePanelToggle:Refresh() end
	end
	if log:IsShown() then details(q.id) end
end

-- the state mark over a pin's badge (made once: pins are pooled, and this set's are only ever quests)
local function Mark(pin, complete)
	if not pin.questMark then
		pin.questMark = pin:CreateTexture(nil, "OVERLAY")
		pin.questMark:SetPoint("CENTER")
	end
	local m, size = pin.questMark, BADGE.size * 0.6
	m:SetSize(size, size)
	S.Look(m, complete and TURN_IN or IN_PROGRESS)
	m:Show()
end

function mod:RefreshQuests()
	dirty = false
	if not set and S.IsBuilt() then set = S.PinSet("quests", 1, 5) end   -- (built as the map first opens)
	if not set then return end
	S.ClearPinSet(set)
	-- (and as Blizzard's own quests: not with the map's Quest Objectives off, its questPOI)
	local on = mod.db.allQuests ~= false and mod.IsStitched() and C_QuestLog.GetQuestsOnMap ~= nil
		and not (GetCVarBool and not GetCVarBool("questPOI"))
	S.SetPinSetOn(set, on)
	if not on then return end
	-- the map underneath: Blizzard draws its quests (a continent, only the super-tracked one)
	local host = mod.HostMap()
	local hostInfo = host and C_Map.GetMapInfo(host)
	local continent = hostInfo and hostInfo.mapType == Enum.UIMapType.Continent
	local tracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
	local hostQuests = {}
	if host and not continent then
		for _, q in ipairs(C_QuestLog.GetQuestsOnMap(host) or NONE) do hostQuests[q.questID] = true end
	end
	local hl, hr, ht, hb
	if host then hl, hr, ht, hb = S.Rect(host) end
	local seen = {}
	for _, mapID in ipairs(Maps()) do
		if mapID ~= host then
			for _, q in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or NONE) do
				local id = q.questID
				if id and q.x and q.y and not q.isMapIndicatorQuest and (not G("HaveQuestData") or G("HaveQuestData")(id))
					and not (continent and id == tracked) then
					local u, v = mod.ToWorld(mapID, q.x, q.y)
					local key = u and (id .. ":" .. math.floor(u / SAME) .. ":" .. math.floor(v / SAME))
					local onHost = u and hostQuests[id] and hl and u >= hl and u <= hr and v >= ht and v <= hb
					if key and not seen[key] and not onHost then
						seen[key] = true
						local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) or false
						local pin = S.AddPin(set, u, v, BADGE, { id = id, complete = complete })
						Mark(pin, complete)
						pin:SetScript("OnEnter", Enter)
						pin:SetScript("OnLeave", GameTooltip_Hide)
						pin.OnClick = Click
					end
				end
			end
		end
	end
end

-- (a burst of quest log updates: one refresh)
local function Soon()
	if dirty then return end
	dirty = true
	C_Timer.After(EVERY, function() if dirty then mod:RefreshQuests() end end)
end

function mod:SetupQuests(worldMap)
	map = worldMap
	local events = CreateFrame("Frame")
	for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "CVAR_UPDATE" }) do
		pcall(events.RegisterEvent, events, e)
	end
	events:SetScript("OnEvent", function(_, event, cvar)
		if event == "CVAR_UPDATE" and cvar ~= "questPOI" then return end
		if map:IsShown() then Soon() end
	end)
	hooksecurefunc(map, "OnMapChanged", Soon)
	map:HookScript("OnShow", Soon)
end
