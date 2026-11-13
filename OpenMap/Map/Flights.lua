--------------------------------------------------------------------------------
-- Flight paths on the world map (ns.MapFlights, the game's flight network):
--   * every flight master of your faction: learned ones in colour, the rest grey
--     (learned = seen as known at a flight master; remembered per character)
--   * click one, then another: the route you'd fly is drawn along the real
--     flight paths, with the stops and a time estimate
--   * times: measured from your own flights once you've flown a leg, otherwise
--     the path's length at SPEED yards a second
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")
local F = ns.MapFlights

mod.defaults.flightTimes = {}   -- "from|to" -> seconds, measured (account-wide)

local SPEED = 30                -- yards a second (classic flights, roughly)
local ROUTE_COLOR = { 0.95, 0.78, 0.35 }
local KNOWN_ATLAS = { "TaxiNode_Alliance", "TaxiNode_Horde" }

local nodeAt = {}               -- node id -> { u, v } on the world (normalized)
local edges = {}                -- node id -> { { to, path }, ... }
local pins = {}                 -- node id -> pin
local set, routeSet
local selected                  -- the first node clicked
local factionBit

--------------------------------------------------------------------------------
-- Known flight masters (per character) and measured times
--------------------------------------------------------------------------------

-- the flight masters the game says you've found (C_TaxiMap.GetTaxiNodesForMap: isUndiscovered false),
-- read afresh as the map opens: every one learned, before OpenMap was installed too. The same list
-- names them in the client's own language, so the tables' English is replaced by it here (once the
-- map opens: the tooltips, the route's caption, the search, the learned names and the measured times
-- all read a node's name off this table, and in a client not in English the English ones matched
-- none of the game's). Only Alterac Valley's pair, on neither continent's list, keeps the English.
local found = {}
local function ReadFound()
	wipe(found)
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return end
	local seen, hidden = {}, 0
	local continents = ns.MapWorld and ns.MapWorld.continents or { 1414, 1415 }   -- (Kalimdor, the Eastern Kingdoms; a client's own)
	for _, mapID in ipairs(continents) do
		local ok, list = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
		if ok and type(list) == "table" then
			for _, info in ipairs(list) do
				if type(info) == "table" and info.nodeID then
					if info.isUndiscovered == false then seen[info.nodeID] = true
					elseif info.isUndiscovered == true then hidden = hidden + 1 end
					local n = F.nodes[info.nodeID]
					if n and type(info.name) == "string" and info.name ~= "" then n[1] = info.name end
				end
			end
		end
	end
	-- (none of them undiscovered: the game isn't saying. WoW Forever lists all 74 as found, learned or
	-- not, and every flight master showed as learned. Then only the ones seen at a flight master count)
	if hidden == 0 then return end
	for id in pairs(seen) do found[id] = true end
end

local function Known(id)
	if found[id] then return true end
	local n = F.nodes[id]
	return n and mod.char.flightsKnown and mod.char.flightsKnown[n[1]]
end

-- learned ones in their colour, the rest grey; both a size up from the map's other icons and outlined
-- in dark, as the boot alone was lost on the parchment (a grey one at 14 and half see-through above all)
local SIZE_KNOWN, SIZE_NOT = 22, 18

local function RefreshLook()
	ReadFound()
	for id, pin in pairs(pins) do
		local known = Known(id)
		pin:SetShown(known or not mod.db.foundOnly)   -- (Only places you've found: learned ones only)
		pin.Icon:SetDesaturated(not known)
		pin.Icon:SetAlpha(known and 1 or 0.9)
		if pin.shadow then pin.shadow:SetAlpha(known and 0.8 or 0.65) end
		local size = known and SIZE_KNOWN or SIZE_NOT
		pin:SetSize(size, size)
	end
end

local taxi = {}                 -- the flight in progress: from, to, start

-- the kinds of node a flight master lists that you've learned. DISTANT is one a flight passes through
-- that you haven't (the game's own flight map shows it only on a route through it); 0.7.5 and before
-- counted it, and every flight master showed as learned (players' reports)
local LEARNED = { CURRENT = true, REACHABLE = true, UNREACHABLE = true }

local function OnTaxiMap()
	mod.char.flightsKnown = mod.char.flightsKnown or {}
	local current
	for i = 1, NumTaxiNodes() do
		local name, kind = TaxiNodeName(i), TaxiNodeGetType(i)
		if LEARNED[kind] then mod.char.flightsKnown[name] = true end
		if kind == "CURRENT" then current = name end
	end
	taxi.here = current
	RefreshLook()
end

local watch = 0                 -- the flight being watched (a newer one stops older watchers)

local function WatchFlight(token)
	if token ~= watch then return end
	if UnitOnTaxi("player") then
		taxi.flying = taxi.flying or GetTime()
	elseif taxi.flying then
		local secs = GetTime() - taxi.flying
		-- only direct flights: a leg's time is read back as that leg's
		if taxi.from and taxi.to and taxi.direct and secs > 5 then
			mod.db.flightTimes[taxi.from .. "|" .. taxi.to] = math.floor(secs + 0.5)
		end
		wipe(taxi)
		return
	elseif GetTime() - taxi.asked > 10 then
		wipe(taxi)                  -- never took off
		return
	end
	C_Timer.After(0.5, function() WatchFlight(token) end)
end

local function OnTakeTaxi(index)
	watch = watch + 1
	local hops = GetNumRoutes and GetNumRoutes(index)
	taxi.from, taxi.to, taxi.flying, taxi.asked = taxi.here, TaxiNodeName(index), nil, GetTime()
	taxi.direct = hops == 1
	local token = watch
	C_Timer.After(0.5, function() WatchFlight(token) end)
end

--------------------------------------------------------------------------------
-- Routes
--------------------------------------------------------------------------------

local function Usable(id)
	local n = F.nodes[id]
	return n and bit.band(n[5], factionBit) ~= 0
end

-- cheapest route by flight length; `knownOnly` keeps to learned flight masters
local function Route(from, to, knownOnly)
	local dist, prev, via, done = { [from] = 0 }, {}, {}, {}
	while true do
		local best, bd
		for id, d in pairs(dist) do
			if not done[id] and (not bd or d < bd) then best, bd = id, d end
		end
		if not best then return end
		if best == to then break end
		done[best] = true
		for _, e in ipairs(edges[best] or {}) do
			local nxt, path = e[1], e[2]
			if Usable(nxt) and (not knownOnly or Known(nxt) or nxt == to) then
				local nd = bd + path[3]
				if not dist[nxt] or nd < dist[nxt] then dist[nxt], prev[nxt], via[nxt] = nd, best, path end
			end
		end
	end
	local legs = {}
	local id = to
	while id ~= from do
		tinsert(legs, 1, via[id])
		id = prev[id]
	end
	return legs
end

local function Clock(secs)
	return ("%d:%02d"):format(math.floor(secs / 60), math.floor(secs % 60))
end

-- a node's name without its zone: "Stormwind, Elwynn", the client's own "暴风城，艾尔文森林" too.
-- The full-width comma is searched as plain text: Lua patterns work on bytes, so a class holding it
-- would cut at one of its three UTF-8 bytes, in the middle of a neighbouring character.
local function Short(name)
	local s = name:match("^[^,]+") or name
	local i = s:find("，", 1, true)
	return i and s:sub(1, i - 1) or s
end

-- each leg's time: measured, or estimated from its length
local function LegTime(path)
	local a, b = F.nodes[path[1]], F.nodes[path[2]]
	local t = mod.db.flightTimes[a[1] .. "|" .. b[1]]
	return t or path[3] / SPEED, t ~= nil
end

local label                     -- the route's caption (a pin with no icon)

local function ClearRoute()
	if routeSet then S.ClearPinSet(routeSet) end
	if selected and pins[selected] then pins[selected].ring:Hide() end
	selected = nil
end

local function ShowRoute(from, to)
	S.ClearPinSet(routeSet)
	local legs, knownOnly = Route(from, to, true), true
	if not legs then legs, knownOnly = Route(from, to, false), false end
	if not legs then
		ns:Print(ns.L["No flight route from %s to %s."], F.nodes[from][1], F.nodes[to][1])
		return
	end
	-- (the learned-only search lets the ends through unlearned, to keep to learned stops between
	-- them: a route that starts or ends at one you haven't learned still needs it)
	knownOnly = knownOnly and Known(from) and Known(to) and true or false
	local total, measured, cont = 0, true, F.nodes[from][2]
	local r, g, b = unpack(ROUTE_COLOR)
	local alpha = knownOnly and 0.95 or 0.5
	for _, path in ipairs(legs) do
		local t, m = LegTime(path)
		total = total + t
		measured = measured and m
		local p = path[5]
		local pu, pv = S.FromYards(cont, p[1], p[2])
		for k = 3, #p, 2 do
			local u, v = S.FromYards(cont, p[k], p[k + 1])
			if pu and u then
				local line = S.AddLine(routeSet, pu, pv, u, v, 3, 0.25, 0.16, 0.05, alpha * 0.8)   -- dark edge
				local core = S.AddLine(routeSet, pu, pv, u, v, 1.6, r, g, b, alpha)
				line:SetDrawLayer("ARTWORK", 0)
				core:SetDrawLayer("ARTWORK", 1)
			end
			pu, pv = u, v
		end
	end

	-- the caption, beside the destination
	local du, dv = unpack(nodeAt[to])
	label = S.AddPin(routeSet, du, dv, { texture = "", size = 1 })
	label:EnableMouse(false)
	if not label.caption then           -- pins are pooled: the caption is made once
		label.caption = label:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label.caption:SetPoint("LEFT", label, "CENTER", 14, 0)
		ns.Look:Font(label.caption, 13, "OUTLINE")
	end
	local fs = label.caption
	local stops = #legs - 1
	local L = ns.L
	fs:SetText(("%s > %s  |cffffffff%s|r%s"):format(
		Short(F.nodes[from][1]), Short(F.nodes[to][1]),
		measured and Clock(total) or L["about %s"]:format(Clock(total)),
		stops > 0 and ("  |cffaaaaaa(" .. (stops == 1 and L["1 stop"] or L["%d stops"]:format(stops)) .. ")|r") or "")
		.. (knownOnly and "" or ("\n|cffff8060" .. L["needs flight masters you haven't learned"] .. "|r")))
end

local function NodeClick(pin)
	local id = pin.node
	if not selected or selected == id then
		ClearRoute()
		selected = id
		pin.ring:Show()
	else
		local from = selected
		pins[from].ring:Hide()
		selected = nil
		ShowRoute(from, id)
	end
end

local function NodeEnter(pin)
	local n = F.nodes[pin.node]
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:AddLine(n[1], 1, 0.82, 0)
	GameTooltip:AddLine(Known(pin.node) and ns.L["Learned"] or ns.L["Not learned"], 0.8, 0.8, 0.8)
	if selected and selected ~= pin.node then
		local legs = Route(selected, pin.node, true) or Route(selected, pin.node, false)
		if legs then
			local total = 0
			for _, path in ipairs(legs) do total = total + LegTime(path) end
			GameTooltip:AddLine(ns.L["From %s: about %s"]:format(Short(F.nodes[selected][1]), Clock(total)), 1, 1, 1)
		end
		GameTooltip:AddLine(ns.L["Click: show the route"], 0.6, 0.6, 0.6)
	else
		GameTooltip:AddLine(ns.L["Click, then click another flight master: the route and its time"], 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Build (once the stitched map exists)
--------------------------------------------------------------------------------

function mod:BuildFlights()
	if set or not F or not S.IsBuilt() then return end
	local faction = UnitFactionGroup("player")
	factionBit = faction == "Horde" and 2 or 1
	set = S.PinSet("flight", 2.5, 2)
	routeSet = S.PinSet("route", 1, 1)
	for _, path in ipairs(F.paths) do
		edges[path[1]] = edges[path[1]] or {}
		tinsert(edges[path[1]], { path[2], path })
	end
	for id, n in pairs(F.nodes) do
		if Usable(id) then
			local u, v = S.FromYards(n[2], n[3], n[4])
			if u then
				nodeAt[id] = { u, v }
				local look = { atlas = KNOWN_ATLAS[factionBit], size = SIZE_KNOWN }
				local pin = S.AddPin(set, u, v, look)
				pin.node = id
				-- (a dark outline: the boot again, in black, a little bigger, under it)
				pin.shadow = pin.shadow or pin:CreateTexture(nil, "BACKGROUND")
				pin.shadow:ClearAllPoints()
				pin.shadow:SetPoint("TOPLEFT", -3, 3)
				pin.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
				S.Look(pin.shadow, look)
				pin.shadow:SetVertexColor(0, 0, 0)
				pin.shadow:Show()
				pin.ring = pin:CreateTexture(nil, "OVERLAY")
				pin.ring:SetPoint("CENTER")
				pin.ring:SetSize(30, 30)
				S.Look(pin.ring, { atlas = "Waypoint-MapPin-Untracked", texture = "Interface\\Minimap\\Ping\\ping5" })
				pin.ring:SetVertexColor(1, 0.85, 0.3)
				pin.ring:Hide()
				pin:SetScript("OnEnter", NodeEnter)
				pin:SetScript("OnLeave", GameTooltip_Hide)
				pin.OnClick = NodeClick
				pins[id] = pin
			end
		end
	end
	RefreshLook()
end

function mod:ClearFlightRoute() ClearRoute() end

-- /openmap forgetflights: the flight masters remembered as learned, forgotten for this character (one
-- wrongly counted stays learned otherwise, and route planners use the list: #153); the next flight
-- master's map learns the real ones again. (What the game itself reports as found isn't stored: kept)
function mod:ForgetFlights()
	if mod.char then mod.char.flightsKnown = {} end
	if set then RefreshLook() end
	ns:Print(ns.L["Learned flight paths forgotten for this character: talk to a flight master to learn the ones you have again."])
end
function mod.RefreshFlightsFound() if set then RefreshLook() end end

function mod:SetupFlights()
	-- (those remembered by 0.7.5 and before had DISTANT's unlearned ones in: forgotten once, and counted again at
	-- the next flight master)
	local c = mod.char
	if c and c.flightsKnownV ~= 2 then c.flightsKnown, c.flightsKnownV = nil, 2 end
	ns.RegisterEvent(mod, "TAXIMAP_OPENED", OnTaxiMap)
	ns.RegisterEvent(mod, "TAXI_NODE_STATUS_CHANGED", function() if set then RefreshLook() end end)
	if WorldMapFrame then WorldMapFrame:HookScript("OnShow", function() if set then RefreshLook() end end) end
	if TakeTaxiNode then hooksecurefunc("TakeTaxiNode", OnTakeTaxi) end
end
