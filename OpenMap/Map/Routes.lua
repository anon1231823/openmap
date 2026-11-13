--------------------------------------------------------------------------------
-- Boat and zeppelin routes (off until turned on): dots along the way each vessel
-- really sails (ns.MapPlaces.sailings, from the game's tables), like the routes on
-- the loading screens. Alliance routes are blue, the rest red.
--   spacing  the dots sit at even steps along the whole way (sea crossings between
--            the two continents' maps bridged by a bowed arc). Finer steps fill in
--            between as you close in, so they stay evenly spaced on screen.
--   hover    quiet until the cursor comes near a route: then that route lights up
--            and says where it runs.
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")
local L = ns.L

local DOT = { atlas = "WhiteCircle-RaidBlips", texture = "Interface\\Buttons\\WHITE8X8" }
local LEVELS = 4                -- densities: each halves the step of the one before
local STEP = 0.016              -- the sparsest step (world units, normalized across)
local SHOW_PX = { 10, 16 }      -- a finer level fades in as its step grows from / to this on screen
local SIZE, QUIET, LIT = 5, 0.45, 0.75   -- dot size (px), alpha at rest, alpha hovered (from afar)
local LIT_FADE = { 3, 12 }      -- zoom over which the hover's lift fades away (up close it's barely there)
local EASE = 8                  -- how fast a route eases to its new alpha (per second)
local HOVER_PX = 8              -- how near the cursor must come
local BLUE, RED = { 0.20, 0.42, 0.88 }, { 0.72, 0.13, 0.10 }
-- goblin ports: Booty Bay and Ratchet have a flight master for each faction (TaxiNodes 18 / 19, 80),
-- Powderfuse Port none yet (its nodes 3274 / 3275 have no flight master in game); every other boat is the Alliance's
local NEUTRAL = { ["Booty Bay - Ratchet"] = true, ["Steamwheedle Port - Powderfuse Port"] = true }
-- the kinds drawn (Zephras Isle's airships wait for its map: its continent can't be placed yet)
local KINDS = { boat = true, zeppelin = true }

local routes = {}               -- { frame, levels = { frames }, way = { { u, v } }, kind, name, faction, ends }
local lit
local KIND_OPTION = { boat = "boats", zeppelin = "zeppelins" }   -- (a route shows while its kind's icons do)

local function KindOn(route)
	local key = KIND_OPTION[route.kind]
	return not key or mod.db[key] ~= false
end

local function Smooth(x, r)
	local t = math.max(0, math.min(1, (x - r[1]) / (r[2] - r[1])))
	return t * t * (3 - 2 * t)
end

local function Faction(sail)
	if sail[1] == "zeppelin" then return "Horde" end
	if NEUTRAL[sail[2]] then return "Neutral" end
	return "Alliance"
end

-- the whole way as world points, a sea crossing between pieces bridged by a bowed arc;
-- none if a piece's continent can't be placed (half a route would stop out at sea)
local function Way(sail)
	local way = {}
	for _, piece in ipairs(sail[3]) do
		local cont, pts = piece[1], piece[2]
		local first = #way + 1
		for k = 1, #pts - 1, 2 do
			local u, v = S.FromYards(cont, pts[k], pts[k + 1])
			if u then way[#way + 1] = { u, v } end
		end
		if #way < first then return {} end
		if first > 1 and way[first] then
			local p0, p2 = way[first - 1], way[first]
			local du, dv = p2[1] - p0[1], p2[2] - p0[2]
			local len = math.sqrt(du * du + (dv * 1.5) ^ 2)
			if len > 0 then
				local side = ((p0[2] + p2[2]) / 2 < 0.5) and -1 or 1
				local nu, nv = -dv * 1.5 / len, du / len / 1.5
				if nv * side < 0 then nu, nv = -nu, -nv end
				local cu, cv = (p0[1] + p2[1]) / 2 + nu * 0.12 * len, (p0[2] + p2[2]) / 2 + nv * 0.12 * len
				for k = 23, 1, -1 do
					local t = k / 24
					tinsert(way, first, { (1 - t) ^ 2 * p0[1] + 2 * (1 - t) * t * cu + t * t * p2[1],
						(1 - t) ^ 2 * p0[2] + 2 * (1 - t) * t * cv + t * t * p2[2] })
				end
			end
		end
	end
	return way
end

-- the level (1 = sparsest) a dot at index i of the finest step belongs to
local function LevelOf(i)
	local level = LEVELS
	while level > 1 and i % 2 == 0 do
		i, level = i / 2, level - 1
	end
	return level
end

-- every dot of every route; where two routes share water (out of Menethil, Grom'gol),
-- the second skips the dots the first already put there, so the spacing stays even. Only
-- a route of the same kind's: boats and zeppelins are shown and hidden apart (KindOn)
local function Build(set)
	local P = ns.MapPlaces or {}
	local fine = STEP / 2 ^ (LEVELS - 1)
	local takenBy, taken = {}, nil  -- kind -> grid cell -> { { u, v, level } }
	local function Taken(u, v, level)
		local cx, cy = math.floor(u / STEP), math.floor(v * 1.5 / STEP)
		local reach = (STEP / 2 ^ (level - 1)) * 0.6
		for x = cx - 1, cx + 1 do
			for y = cy - 1, cy + 1 do
				for _, d in ipairs(taken[x .. ":" .. y] or {}) do
					if d[3] <= level and math.sqrt((d[1] - u) ^ 2 + ((d[2] - v) * 1.5) ^ 2) < reach then return true end
				end
			end
		end
		local key = cx .. ":" .. cy
		taken[key] = taken[key] or {}
		tinsert(taken[key], { u, v, level })
	end
	for _, sail in ipairs(P.sailings or {}) do
		local way = KINDS[sail[1]] and Way(sail) or {}
		if #way > 1 then
			takenBy[sail[1]] = takenBy[sail[1]] or {}
			taken = takenBy[sail[1]]
			local route = { way = way, kind = sail[1], name = sail[2], faction = Faction(sail), levels = {} }
			route.frame = CreateFrame("Frame", nil, set.frame)
			route.frame:SetAllPoints(set.frame)
			route.frame:SetAlpha(QUIET)
			for level = 1, LEVELS do
				local f = CreateFrame("Frame", nil, route.frame)
				f:SetAllPoints(route.frame)
				route.levels[level] = f
			end
			local c = route.faction == "Alliance" and BLUE or RED
			local i, carry = 0, 0
			for k = 1, #way - 1 do
				local u0, v0, u1, v1 = way[k][1], way[k][2], way[k + 1][1], way[k + 1][2]
				local seg = math.sqrt((u1 - u0) ^ 2 + ((v1 - v0) * 1.5) ^ 2)
				local t = carry
				while t <= seg do
					local f = seg > 0 and t / seg or 0
					local u, v = u0 + (u1 - u0) * f, v0 + (v1 - v0) * f
					local level = LevelOf(i)
					if not Taken(u, v, level) then
						S.AddDot(set, u, v, SIZE, DOT, c[1], c[2], c[3], 1, route.levels[level])
					end
					i = i + 1
					t = t + fine
				end
				carry = t - seg
			end
			-- where it runs: the zones at its two ends
			local ends = {}
			for _, p in ipairs({ way[1], way[#way] }) do
				local chain = S.ChainAt(p[1], p[2])
				local info = C_Map.GetMapInfo(chain[#chain])
				ends[#ends + 1] = info and info.name or "?"
			end
			route.ends = ends
			route.frame:SetShown(KindOn(route))
			routes[#routes + 1] = route
		end
	end
end

-- the finer levels by the zoom (u per view px)
local function ApplyLevels()
	local _, _, pu = mod.CursorWorld()
	if not pu or pu <= 0 then return end
	for _, route in ipairs(routes) do
		for level = 1, LEVELS do
			local px = STEP / 2 ^ (level - 1) / pu
			route.levels[level]:SetAlpha(level == 1 and 1 or Smooth(px, SHOW_PX))
		end
	end
end

-- each route eases toward its alpha (no snapping on and off); the hovered one's lift
-- shrinks as you zoom in
local function Ease(elapsed)
	local _, _, zoom = mod.ViewNow()
	local t = math.max(0, math.min(1, ((zoom or 1) - LIT_FADE[1]) / (LIT_FADE[2] - LIT_FADE[1])))
	local up = QUIET + (LIT - QUIET) * (1 - t * t * (3 - 2 * t))
	local k = math.min(1, elapsed * EASE)
	for _, route in ipairs(routes) do
		local target = route == lit and up or QUIET
		local a = route.alpha or QUIET
		if math.abs(a - target) > 0.002 then
			a = a + (target - a) * k
			route.alpha = a
			route.frame:SetAlpha(a)
		end
	end
end

local function Light(route)
	if route == lit then return end
	lit = route
	local owner = S.GetPinSet("routes").frame
	if route then
		local px, py = mod.PadCursor()
		if px then
			-- (by the gamepad's cursor: the mouse's is hidden, somewhere else)
			local es = UIParent:GetEffectiveScale()
			GameTooltip:SetOwner(owner, "ANCHOR_NONE")
			GameTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", px / es + 16, py / es + 16)
		else
			GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
		end
		GameTooltip:AddLine(route.kind == "zeppelin" and L["Zeppelin"] or L["Boat"], 1, 0.82, 0)
		GameTooltip:AddLine(route.ends[1] .. "  -  " .. route.ends[2], 1, 1, 1)
		local c = route.faction == "Alliance" and BLUE or route.faction == "Horde" and RED or nil
		if c then
			GameTooltip:AddLine(route.faction == "Alliance" and (FACTION_ALLIANCE or "Alliance") or (FACTION_HORDE or "Horde"), c[1] + 0.25, c[2] + 0.25, c[3] + 0.25)
		else
			GameTooltip:AddLine(L["Neutral"], 1, 0.82, 0)
		end
		GameTooltip:Show()
	elseif GameTooltip:IsOwned(owner) then
		GameTooltip:Hide()
	end
end

-- the route nearest the cursor, within HOVER_PX
local function Hover()
	local u, v, pu, pv = mod.CursorWorld()
	local map = WorldMapFrame
	if not u or not pu or (map and map.IsCanvasMouseFocus and not map:IsCanvasMouseFocus() and not mod.PadCursor()) then return Light(nil) end
	local best, bestD = nil, HOVER_PX
	for _, route in ipairs(routes) do
		local way = route.way
		for k = 1, route.frame:IsShown() and #way - 1 or 0 do   -- (a hidden kind's routes aren't hovered)
			local ax, ay = (way[k][1] - u) / pu, (way[k][2] - v) / pv
			local bx, by = (way[k + 1][1] - u) / pu, (way[k + 1][2] - v) / pv
			local dx, dy = bx - ax, by - ay
			local len2 = dx * dx + dy * dy
			local t = len2 > 0 and math.max(0, math.min(1, -(ax * dx + ay * dy) / len2)) or 0
			local d = math.sqrt((ax + dx * t) ^ 2 + (ay + dy * t) ^ 2)
			if d < bestD then best, bestD = route, d end
		end
	end
	Light(best)
end

-- the routes' pin set, from Stitch's BuildPins (the dots themselves wait until shown)
function S.BuildRoutes()
	local set = S.PinSet("routes", 0, 0)
	set.on = false
	set.build = function(s)                 -- the first time routes are shown
		Build(s)
		ApplyLevels()
		local wait = 0
		s.frame:SetScript("OnUpdate", function(_, elapsed)
			Ease(elapsed)
			wait = wait - elapsed
			if wait > 0 then return end
			wait = 0.05
			Hover()
		end)
		s.frame:SetScript("OnHide", function() Light(nil) end)
	end
end

-- the boats' and zeppelins' switches (mod:Refresh)
function S.RefreshRoutes()
	for _, route in ipairs(routes) do
		local on = KindOn(route)
		route.frame:SetShown(on)
		if not on and route == lit then Light(nil) end
	end
end

tinsert(S.viewHooks, function() if #routes > 0 then ApplyLevels() end end)
