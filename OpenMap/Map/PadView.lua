--------------------------------------------------------------------------------
-- The controller view (Options' padView, on by default): with the game's Gamepad UI on, OpenMap's
-- stitched map drawn over Blizzard's world map on a frame of its own, Blizzard's map left as it is.
--
-- Why a frame of its own: on OpenMap's usual map (WorldMap.lua) the view is Blizzard's scroll
-- container, driven by OpenMap: its zoom and scroll written by OpenMap's code, its ResetZoom and
-- scroll extents OpenMap's. The Gamepad UI reads that same state each time the map changes, and the
-- controller's bindings it then makes (the map footer's, the binding stack's) carry OpenMap's taint:
-- closing the map then has the game block SetPreferredGamepadInteractTarget, and the taint stays in
-- the binding stack until a reload. Here nothing of Blizzard's map is written or replaced: its canvas
-- is only made see-through while this view covers it, and its gamepad functions only hooked
-- (hooksecurefunc), so the Gamepad UI's own code (the cursor, B, the D-pad, the focus) stays secure.
-- What would change Blizzard's map or its quest log from OpenMap's code isn't done while the view is
-- on (mod.PadViewOn: Dungeons.lua, Panel.lua, Report.lua ...), nor anything put on Escape's list
-- (UISpecialFrames, which the Gamepad UI's own closing of windows reads).
--
-- The controller, read rather than bound: the cursor is Blizzard's (SoftCursor, its left stick; drawn
-- again over the art), the right stick is read from the controller (mod.PadStickTilt) and zooms about
-- the cursor, or is the mouse wheel of the OpenMap window under it; the cursor at the view's edge pans
-- as Blizzard's map does (its gamepadScrollSpeed, read). A presses OpenMap's control or icon under the
-- cursor, else zooms into the zone there; X closes OpenMap's window that's up (a dungeon's map, the
-- menu, the quill), else zooms out a level (both after Blizzard's own, on its map underneath, unseen);
-- the left stick pressed puts the waypoint where the cursor is. The quill: A puts the pen down, A lifts it.
--
-- On it: the art and names, your arrow, your party, dungeons, boats, flight masters and routes, your
-- map pins and the waypoint, Questie's townsfolk, every addon's HereBeDragons icons (Questie's with its
-- own tooltips) and Questie's mob paths, a dungeon's map in OpenMap's own view of it (floors and side
-- panel), OpenMap's menu, the pins' list and cards, the quill, and Report a problem (without its note
-- step: the game's popups run the Gamepad UI's own code). Not yet: the quest log's quest areas.
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")
local WORLD = S.WORLD

local ART_RANGE = 80            -- frame levels the stitched art takes (as WorldMap.lua's)
local GLIDE_TIME = 0.4          -- A and X's zoom, as a click's on the usual map
local PAD_ZOOM_RATE = 1.8       -- the right stick at full tilt, per second in log zoom (as WorldMap.lua's)
local CITY_ZOOM = 1.5           -- deeper over a city (as WorldMap.lua's)
local PLAYER_EVERY = 0.1        -- seconds between moves of your arrow
local GROUP_EVERY = 0.5         -- ... and of your party's and raid's dots (Nav.lua's)
local REACH = 12                -- px from the cursor that an icon counts as under it (Gamepad.lua's)
local HOVER_EVERY = 0.05        -- seconds between looks at what's under the cursor
local QUESTIE_LIB = "HereBeDragonsQuestie-Pins-2.0"
local QUESTIE_FROM = 2.5        -- the zoom Questie's icons come in at (a continent's worth of quests is too many)
local QUESTIE_EVERY = 0.5       -- seconds between looks at which icons Questie has on the map
local QUESTIE_CLUSTER = 20      -- view px round a hovered Questie icon whose quests its tooltip lists too
local ARROW_ABOVE = 8500        -- your arrow: this many levels over the view, over Questie's icons (their levels are
local POINTER_LEVEL = 9990      --  fixed, from 2015: Extras.lua) ... and the pad's cursor over everything (a dungeon's
                                --  map, Dungeons.lua's, goes to 9840)

local map, sc, view, canvas
local pointer                   -- the pad's cursor, drawn again over the art (Blizzard's is under it)
local built, failed = false, false
local u, v, zoom                -- the view: world centre (normalized) and zoom (1: the whole world fits)
local glide                     -- A or X's zoom under way
local lastX, lastY              -- the pad's cursor on the last frame (screen px): Blizzard re-centres it
                                --  as A or X changes its map, before the hooks below run
local dirty = false
local playerWait, hoverWait, groupWait = 0, 0, 0
local hovered                   -- the icon under the pad's cursor, entered as the mouse would
local questieLayer              -- Questie's icons, on this view
local questieAt = setmetatable({}, { __mode = "k" })   -- icon -> { u, v }: Questie's icons on the map, in world units
local questieShown = {}         -- icon -> true: placed on this view now
local questieWait = 0
local PlaceQuestie, QuestieTip -- (below: Apply calls the one, the other the other)
local ownWaypointAt = -10       -- when this view last set or cleared the waypoint itself (GetTime)
local overWindow, wheelFrame    -- the pad's cursor over one of OpenMap's windows (its menu ...), and what scrolls there
local wheelWait = 0
local stickZoomAt = -10         -- when the right stick last zoomed the view (GetTime)
local WHEEL_EVERY = 0.12        -- seconds between the right stick's wheel notches at full tilt
local diag = { started = 0, setup = "not yet", shows = 0, why = "not tried yet" }   -- (/openmap padview)

local function Clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

local function On()
	return mod.db and mod.db.padView and not mod.enabled and mod.PadUI and mod.PadUI() or false
end

--------------------------------------------------------------------------------
-- Geometry (WorldMap.lua's, on this view)
--------------------------------------------------------------------------------

local function FitPx()
	local W, H = S.Size()
	return math.min(view:GetWidth() / W, view:GetHeight() / H)
end

local function DetailK()
	local W, H = S.Size()
	local w, h = view:GetWidth(), view:GetHeight()
	local k = ns.ClientMaps and ns.ClientMaps.zoom or 1
	if not W or w <= 0 or h <= 0 then return 1 / k end
	return math.min(w / W, h / H) / math.sqrt(w * h / (W * H)) / k
end

local function Stitchable(mapID)
	if not mapID or mapID == WORLD then return mapID == WORLD end
	local info = C_Map.GetMapInfo(mapID)
	if not info or (info.mapType ~= Enum.UIMapType.Continent and info.mapType ~= Enum.UIMapType.Zone) then return false end
	return S.Rect(mapID) ~= nil and S.ArtSize(mapID) ~= nil and S.Stitched(mapID, true)
end

local function FitZoom(mapID)
	local W, H = S.Size()
	local l, r, t, b = S.Rect(mapID)
	return math.min(view:GetWidth() / ((r - l) * W), view:GetHeight() / ((b - t) * H)) / FitPx()
end

local function MostAt(cu, cv)
	return (mod.db.maxZoom or 64) * ((cu and S.InCity and S.InCity(cu, cv)) and CITY_ZOOM or 1)
end

-- a screen point (px, as GetCursorPosition) -> its offset from the view's centre (view px, y down)
local function Offset(x, y)
	local l, b, w, h = view:GetRect()
	if not l then return 0, 0 end
	local es = view:GetEffectiveScale()
	return x / es - (l + w / 2), (b + h / 2) - y / es
end

-- the world point at a view offset
local function WorldAt(sx, sy)
	local W, H = S.Size()
	local px = FitPx() * zoom
	return u + sx / (W * px), v + sy / (H * px)
end

-- the pad's cursor (screen px), while the map has the pad
local function Cursor()
	local soft = _G.SoftCursor
	if not (soft and soft:IsShown()) then return end
	if map.IsCanvasGamepadFocus and not map:IsCanvasGamepadFocus() then return end
	local l, b, w, h = soft:GetRect()
	if not l then return end
	local es = soft:GetEffectiveScale()
	return (l + w / 2) * es, (b + h / 2) * es
end

--------------------------------------------------------------------------------
-- The view
--------------------------------------------------------------------------------

local function Apply()
	dirty = false
	local W, H = S.Size()
	local px = FitPx() * zoom
	if not W or px <= 0 then return end
	zoom = Clamp(zoom, 1, math.max(1, MostAt(u, v), zoom))
	u, v = Clamp(u, 0, 1), Clamp(v, 0, 1)
	canvas:SetScale(px)
	canvas:ClearAllPoints()
	canvas:SetPoint("TOPLEFT", view, "CENTER", -u * W, v * H)     -- (offsets in the canvas's own units)
	local dk = DetailK()
	S.SetZoom(zoom * dk, px)
	local hu, hv = view:GetWidth() / 2 / (W * px), view:GetHeight() / 2 / (H * px)
	S.SetView(u, v, hu, hv, zoom * dk, zoom / (ns.ClientMaps and ns.ClientMaps.zoom or 1))
	S.PlacePlayer()
	PlaceQuestie()
end

-- to zoom `to`, the world point under the view offset (sx, sy) kept there
local function ZoomAbout(sx, sy, to)
	local W, H = S.Size()
	local cu, cv = WorldAt(sx, sy)
	local most = MostAt(cu, cv)
	if to > zoom then most = math.max(most, zoom) end
	to = Clamp(to, 1, most)
	local px = FitPx() * to
	u, v, zoom = cu - sx / (W * px), cv - sy / (H * px), to
	dirty = true
end

local function GlideTo(tu, tv, tz)
	glide = { u0 = u, v0 = v, z0 = zoom, u1 = tu, v1 = tv, z1 = Clamp(tz, 1, MostAt(tu, tv)), t = 0 }
end

local function Glide(elapsed)
	local a = glide
	a.t = math.min(1, a.t + elapsed / GLIDE_TIME)
	local e = a.t * a.t * (3 - 2 * a.t)
	zoom = math.exp(math.log(a.z0) + (math.log(a.z1) - math.log(a.z0)) * e)
	-- (the centre moves with 1/zoom: one zoom about a fixed point, as WorldMap.lua's)
	local w = math.abs(a.z1 - a.z0) < 1e-6 and e or (1 / a.z0 - 1 / zoom) / (1 / a.z0 - 1 / a.z1)
	u, v = a.u0 + (a.u1 - a.u0) * w, a.v0 + (a.v1 - a.v0) * w
	if a.t >= 1 then glide = nil end
	dirty = true
end

local Press
-- A: into the zone (or continent) under the cursor, or the icon under it pressed; X: out a level (as a
-- click and right-click)
local function Step(inward)
	local dungeon = mod.DungeonViewShown and mod.DungeonViewShown()
	-- (OpenMap's windows over the map first, a dungeon's map's buttons: Gamepad.lua's presses)
	if inward and lastX and mod.PadPress and mod.PadPress(lastX, lastY, true) then return end
	if dungeon then
		if not inward and mod.CloseDungeonView then mod.CloseDungeonView() end   -- (X: out of it)
		return
	end
	-- the quill out: A puts the pen down or lifts it; X puts the quill down
	if mod.IsSketching and mod:IsSketching() then
		if inward then
			if mod.PadSketchPress then mod.PadSketchPress() end
		else
			mod:ToggleSketch(false)
		end
		return
	end
	-- Drop a pin (the menu's): A puts it where the cursor is, its note open
	if inward and mod.PinMode and mod.PinMode() and lastX and mod.DropWaypoint then
		local cu, cv = WorldAt(Offset(lastX, lastY))
		mod.SetPinMode(false)
		ownWaypointAt = GetTime()
		mod.DropWaypoint(cu, cv)
		return
	end
	-- (X with OpenMap's menu open: the menu closed, the map left as it is)
	if not inward and mod.MenuShown and mod.MenuShown() then
		mod.CloseMenu()
		return
	end
	if inward and hovered and hovered:IsVisible() then return Press(hovered) end
	local cu, cv
	if lastX then cu, cv = WorldAt(Offset(lastX, lastY)) else cu, cv = u, v end
	local chain = S.ChainAt(cu, cv)
	if inward then
		for _, id in ipairs(chain) do
			if id ~= WORLD and Stitchable(id) and FitZoom(id) > zoom * 1.05 then
				local l, r, t, b = S.Rect(id)
				GlideTo((l + r) / 2, (t + b) / 2, FitZoom(id))
				return
			end
		end
	else
		local target = WORLD
		for _, id in ipairs(chain) do
			if id ~= WORLD and Stitchable(id) and FitZoom(id) < zoom * 0.95 then target = id end
		end
		local l, r, t, b = S.Rect(target)
		GlideTo((l + r) / 2, (t + b) / 2, FitZoom(target))
	end
end

local function UpdatePlayer()
	local best = C_Map.GetBestMapForUnit("player")
	local pos = best and S.Rect(best) and C_Map.GetPlayerMapPosition(best, "player")
	local x, y
	if pos then x, y = ns.Safe.XY(pos) end
	if ns.Safe.IsSecret(x) or ns.Safe.IsSecret(y) or not (x and y) then S.SetPlayer(nil) return end
	local l, r, t, b = S.Rect(best)
	S.SetPlayer(l + x * (r - l), t + y * (b - t), ns.Safe.Call(GetPlayerFacing))
end

-- the pad's cursor over the art, as Blizzard draws it (its diamond, and lines out to the view's edges):
-- Blizzard's own is under this view, and it's left as it is (moving it would be OpenMap's doing)
local function Pointer(x, y)
	if not pointer then return end
	if not x then pointer:Hide() return end
	local sx, sy = Offset(x, y)
	local w, h = view:GetWidth(), view:GetHeight()
	local d, gap = pointer.diamond, 16
	d:ClearAllPoints()
	d:SetPoint("CENTER", view, "CENTER", sx, -sy)
	local L = pointer.lines
	L[1]:ClearAllPoints() L[1]:SetSize(w, 2) L[1]:SetPoint("RIGHT", view, "CENTER", sx - gap, -sy)
	L[2]:ClearAllPoints() L[2]:SetSize(w, 2) L[2]:SetPoint("LEFT", view, "CENTER", sx + gap, -sy)
	L[3]:ClearAllPoints() L[3]:SetSize(2, h) L[3]:SetPoint("BOTTOM", view, "CENTER", sx, -sy + gap)
	L[4]:ClearAllPoints() L[4]:SetSize(2, h) L[4]:SetPoint("TOP", view, "CENTER", sx, -sy - gap)
	pointer:Show()
end

local function MakePointer(level)
	-- (on Blizzard's map, not in the view: the view clips its children, so all of it, the cursor too, is
	-- drawn as one, at its own level, under a dungeon's map in Blizzard's scroll frame, which clips too)
	pointer = CreateFrame("Frame", nil, map)
	pointer:SetAllPoints(view)
	pointer:SetFrameLevel(level)
	pointer:Hide()
	local shade = pointer:CreateTexture(nil, "OVERLAY", nil, 6)
	local d = pointer:CreateTexture(nil, "OVERLAY", nil, 7)
	for i, t in ipairs({ shade, d }) do
		if not pcall(t.SetAtlas, t, "gamepad-mapquestlog-cursor-diamond-gold") then
			t:SetTexture("Interface\\Minimap\\Ping\\ping5")   -- (an atlas this client lacks)
		end
		t:SetSize(i == 1 and 38 or 35, i == 1 and 38 or 35)
	end
	shade:SetVertexColor(0, 0, 0)
	shade:SetPoint("CENTER", d, "CENTER")
	pointer.diamond = d
	local c = NORMAL_FONT_COLOR
	pointer.lines = {}
	for i = 1, 4 do
		local line = pointer:CreateTexture(nil, "ARTWORK")
		if c then line:SetColorTexture(c.r, c.g, c.b, 0.6) else line:SetColorTexture(1, 0.82, 0, 0.6) end
		pointer.lines[i] = line
	end
end

--------------------------------------------------------------------------------
-- Other addons' icons: Questie's, TomTom's, gatherers' ... HereBeDragons (each addon's copy of its pins
-- library) puts each on Blizzard's map, under this view and unseen; there, each map change places every
-- one of them again (the stall X had with Questie). While the view is on, the libraries place none on
-- Blizzard's map (each provider's HandlePin, wrapped: the library's own table, not Blizzard's), and their
-- icons are put on this view instead, where they are in the world: from the map point Questie gave (the
-- client's map rectangles, as Extras.lua places them), else the library's world position. Questie's
-- path stretches (its older lines) aren't icons: its paths are Extras.lua's, drawn on the art
--------------------------------------------------------------------------------

local SHOW_CONTINENT = 2        -- HBD_PINS_WORLDMAP_SHOW_CONTINENT: an icon its addon shows from a continent's map

-- every copy of the pins library loaded: name -> library
local function PinLibs()
	local out = {}
	local q = mod.QuestieModule and mod.QuestieModule()   -- (Questie 12.8 and later: Extras.lua)
	if q then out[mod.QUESTIE_MODULE] = q end
	if not LibStub then return out end
	if LibStub.IterateLibraries then
		for name, lib in LibStub:IterateLibraries() do
			if type(name) == "string" and type(lib) == "table"
				and (name:match("^HereBeDragons.*%-Pins%-2%.0$") or name == "HereBeDragons-Pins-ZGV") then
				out[name] = lib
			end
		end
	else
		out[QUESTIE_LIB] = LibStub(QUESTIE_LIB, true)
	end
	return out
end

-- each library's provider wrapped once: nothing put on Blizzard's map while the view is on
local function HoldPins()
	for _, lib in pairs(PinLibs()) do
		local provider = lib.worldmapProvider
		if type(provider) == "table" and type(provider.HandlePin) == "function" and not provider.openmapPadView then
			provider.openmapPadView = true
			local HandlePin = provider.HandlePin
			provider.HandlePin = function(self, ...)
				if built and On() then return end
				return HandlePin(self, ...)
			end
			-- (the ones already on Blizzard's map: taken off, as the library does on a map change)
			if map:IsShown() and type(provider.RemoveAllData) == "function" then pcall(provider.RemoveAllData, provider) end
		end
	end
end

-- an icon's place in the world
local function IconWorld(icon, data)
	local uiMapID = data.uiMapID
	if uiMapID and icon.UiMapID == uiMapID and type(icon.x) == "number" and type(icon.y) == "number" then
		local l, r, t, b = S.Rect(uiMapID)
		if l then return l + icon.x / 100 * (r - l), t + icon.y / 100 * (b - t) end
	end
	-- (the library's x, y are the game's world Y, X: Extras.lua)
	if type(data.instanceID) == "number" and type(data.x) == "number" and type(data.y) == "number" and S.FromYards then
		return S.FromYards(data.instanceID, data.y, data.x)
	end
end

-- which icons the addons have on the map now, and where: icon -> { u, v, Questie's, its show flag }
local function ScanQuestie()
	wipe(questieAt)
	for name, lib in pairs(PinLibs()) do
		local pins = lib.worldmapPins
		local questie = name == QUESTIE_LIB or name == mod.QUESTIE_MODULE
		if type(pins) == "table" then
			for icon, data in pairs(pins) do
				if type(icon) == "table" and type(data) == "table" and icon.SetPoint and not (questie and icon.type == "line") then
					local ok, wu, wv = pcall(IconWorld, icon, data)
					if ok and wu and wv then questieAt[icon] = { wu, wv, questie, tonumber(data.worldMapShowFlag) or 0 } end
				end
			end
		end
	end
end

-- the icons in view put on it (at their size: the view isn't scaled), the rest hidden. Questie's from
-- QUESTIE_FROM in; another addon's from there too, or from further out where it asks to be on a
-- continent's map (TomTom's waypoint)
function PlaceQuestie()
	if not questieLayer then return end
	local seen = {}
	local profile = _G.Questie and Questie.db and Questie.db.profile
	local questieOn = zoom >= QUESTIE_FROM and not (profile and profile.enabled == false)
	do
		local W, H = S.Size()
		local px = FitPx() * zoom
		local hw, hh = view:GetWidth() / 2 + 16, view:GetHeight() / 2 + 16
		for icon, at in pairs(questieAt) do
			local x, y = (at[1] - u) * W * px, (at[2] - v) * H * px
			local on
			if at[3] then on = questieOn else on = zoom >= QUESTIE_FROM or at[4] >= SHOW_CONTINENT end
			if on and x > -hw and x < hw and y > -hh and y < hh then
				if icon:GetParent() ~= questieLayer then icon:SetParent(questieLayer) end
				icon:ClearAllPoints()
				icon:SetPoint("CENTER", questieLayer, "CENTER", x, -y)
				icon:Show()
				seen[icon] = true
				if at[3] and not icon.openmapPadTip then   -- (the mouse over Questie's: its tooltip, from this view: QuestieTip)
					icon.openmapPadTip = true
					icon:HookScript("OnEnter", function(self) if questieShown[self] then QuestieTip(self, GameTooltip) end end)
				end
			end
		end
	end
	for icon in pairs(questieShown) do
		if not seen[icon] and icon:GetParent() == questieLayer then icon:Hide() end
	end
	questieShown = seen
end

-- A Questie icon's tooltip. Questie's lists the quests of every icon round the hovered one on Blizzard's
-- map (its pins there), where there are none now: it's given the icons round it on this view instead
-- (MapIconTooltip.ShowOnTooltip's own `icons`). On `tooltip`: the pad's on Questie's own tooltip, as
-- Questie does for the pad (GamepadMapHover: GameTooltip from there taints the Gamepad UI)
function QuestieTip(icon, tooltip)
	local loader = _G.QuestieLoader
	local ok, tips = pcall(function() return loader:ImportModule("MapIconTooltip") end)
	if not ok or type(tips) ~= "table" or type(tips.ShowOnTooltip) ~= "function" or not tooltip then return end
	local near = {}
	local cx, cy = icon:GetCenter()
	if cx then
		for other in pairs(questieShown) do
			local ox, oy
			if questieAt[other] and questieAt[other][3] then ox, oy = other:GetCenter() end
			if ox and (ox - cx) ^ 2 + (oy - cy) ^ 2 <= QUESTIE_CLUSTER ^ 2 then near[#near + 1] = other end
		end
	end
	tooltip:Hide()                                  -- (an empty one up already would hold it off: its 0.05 s guard)
	pcall(tips.ShowOnTooltip, icon, tooltip, nil, near)
	if tooltip ~= GameTooltip and tooltip:IsShown() and tooltip.SetAnchorType then
		pcall(tooltip.SetAnchorType, tooltip, "ANCHOR_RIGHT")
	end
end

-- the Questie icon nearest the cursor, if it's within reach
local function QuestieAt(x, y)
	local best, bestD = nil, REACH * REACH
	for icon in pairs(questieShown) do
		if icon:IsVisible() then
			local cx, cy = icon:GetCenter()
			if cx then
				local es = icon:GetEffectiveScale()
				local dx, dy = cx * es - x, cy * es - y
				local d = dx * dx + dy * dy
				if d < bestD then best, bestD = icon, d end
			end
		end
	end
	return best
end

-- the icon under the cursor gets the mouse's enter and leave (its tooltip, its highlight), as on the
-- usual map (Gamepad.lua)
local function Enter(pin)
	if pin == hovered then return end
	local was = hovered
	hovered = pin
	if was then
		if was.UnlockHighlight then was:UnlockHighlight() end
		local leave = was:GetScript("OnLeave")
		if leave then pcall(leave, was, false) end
		local own = _G.QuestieGamepadMapTooltip
		if questieShown[was] and own and own ~= GameTooltip then own:Hide() end
	end
	if pin then
		if pin.LockHighlight then pin:LockHighlight() end
		if questieShown[pin] and questieAt[pin] and questieAt[pin][3] then   -- (Questie's: its tooltip from this view)
			QuestieTip(pin, _G.QuestieGamepadMapTooltip or GameTooltip)
		else
			local enter = pin:GetScript("OnEnter")
			if enter then pcall(enter, pin, false) end
		end
	end
end

-- an icon pressed (A, or a click): its own click, but for what would change Blizzard's map (a
-- dungeon's map, Zephras Isle's): that's OpenMap's doing then, which taints the Gamepad UI. A
-- dungeon's entrance is zoomed to instead, its tooltip kept up
function Press(pin)
	-- your map pin: its card, as a click opens it (its note, colour, Follow, Share ...)
	local p = pin.data
	if type(p) == "table" and p.id and p.map and p.x and pin.OnClick and mod.SetupPins then
		ownWaypointAt = GetTime()
		pcall(pin.OnClick, pin)
		return
	end
	if type(p) == "table" and p.id and p.map and p.x and mod.TrackPoint then
		local m, x, y = mod.WaypointPoint()
		ownWaypointAt = GetTime()
		if m == p.map and x and math.abs(x - p.x) < 1e-3 and math.abs(y - p.y) < 1e-3 then
			mod.ClearPin()
		else
			mod.TrackPoint(p.map, p.x, p.y, p.note ~= "" and p.note or nil)
		end
		local enter = pin:GetScript("OnEnter")
		if hovered == pin and enter then pcall(enter, pin, false) end
		return
	end
	if pin.instances and pin.OnClick and mod.DungeonMapsOn and mod.DungeonMapsOn() then
		pcall(pin.OnClick, pin)                     -- (Dungeons.lua: OpenMap's own view of its map, PadView())
		return
	end
	if pin.instances then
		local u1, v1 = pin.u, pin.v
		if u1 then GlideTo(u1, v1, math.max(zoom, 12)) end
		return
	end
	if pin.away then
		if pin.to then GlideTo(pin.to[1], pin.to[2], math.max(zoom, 6)) end
		return
	end
	if pin.OnClick then pcall(pin.OnClick, pin) end
	-- (its tooltip again: the click changes what it says, a flight master's route)
	if hovered == pin then
		local enter = pin:GetScript("OnEnter")
		if enter then pcall(enter, pin, false) end
	end
end

local function OnUpdate(_, elapsed)
	local x, y = Cursor()
	local dungeon = mod.DungeonViewShown and mod.DungeonViewShown()
	local stick = x and mod.PadStickTilt and mod.PadStickTilt() or 0
	-- over one of OpenMap's windows (its menu, a dungeon's map): the right stick is its mouse wheel
	if overWindow and x then
		wheelWait = wheelWait - elapsed
		if stick ~= 0 and wheelFrame and wheelWait <= 0 then
			wheelWait = WHEEL_EVERY / math.max(0.3, math.abs(stick))
			local fn = wheelFrame:GetScript("OnMouseWheel")
			if fn then pcall(fn, wheelFrame, stick > 0 and 1 or -1) end
		elseif stick == 0 then
			wheelWait = 0
		end
	end
	local tilt = (dungeon or overWindow) and 0 or stick
	if tilt ~= 0 then
		stickZoomAt = GetTime()
		glide = nil
		local sx, sy = Offset(x, y)
		ZoomAbout(sx, sy, zoom * math.exp(tilt * PAD_ZOOM_RATE * elapsed))
	end
	-- the cursor at the view's edge: Blizzard's pan speed for its map (view px a second), ours too
	local speed = x and not dungeon and not overWindow and sc.gamepadScrollSpeed
	local sxs, sys = speed and tonumber(speed.X) or 0, speed and tonumber(speed.Y) or 0
	if sxs ~= 0 or sys ~= 0 then
		glide = nil
		local W, H = S.Size()
		local px = FitPx() * zoom
		u, v = u + sxs * elapsed / (W * px), v - sys * elapsed / (H * px)
		dirty = true
	end
	if glide then Glide(elapsed) end
	if x then lastX, lastY = x, y end
	playerWait = playerWait - elapsed
	if playerWait <= 0 then
		playerWait = PLAYER_EVERY
		UpdatePlayer()
	end
	groupWait = groupWait - elapsed
	if groupWait <= 0 then
		groupWait = GROUP_EVERY
		if mod.RefreshGroup then pcall(mod.RefreshGroup) end
	end
	if dirty then Apply() end
	Pointer(x, y)
	questieWait = questieWait - elapsed
	if questieWait <= 0 then
		questieWait = QUESTIE_EVERY
		ScanQuestie()
		PlaceQuestie()
	end
	hoverWait = hoverWait - elapsed
	if hoverWait <= 0 then
		hoverWait = HOVER_EVERY
		local ctl, blocked
		if x and mod.PadControlAt then ctl, blocked = mod.PadControlAt(x, y) end
		overWindow = (ctl or blocked) and true or false
		wheelFrame = overWindow and mod.PadWheelAt and mod.PadWheelAt(x, y) or nil
		if ctl or blocked or dungeon then Enter(ctl)
		else Enter(x and (S.PinAt(x, y, REACH) or QuestieAt(x, y)) or nil) end
	end
end

--------------------------------------------------------------------------------
-- Building it, showing it
--------------------------------------------------------------------------------

-- OpenMap's look, as its Options have it (WorldMap.lua's Refresh, the parts that are the art's)
local function Look()
	local db = mod.db
	S.SetPlayerHidden(db.playerArrow == false)
	S.SetPlacesFrom(db.iconsFrom)
	S.SetFoundOnly(db.foundOnly)
	S.SetIconScale(db.iconScale or 1)
	S.SetGapFillsShown(db.gapFills ~= false)
	if S.SetDarkening then S.SetDarkening(db.darkening or 1, db.darkenColor or nil) end
	S.ApplyGrade(db.colorMatch, db.desaturate, mod.Unexplored())
	-- each kind of icon on or off as Options have it (WorldMap.lua's SET_OPTION)
	for key, opt in pairs({ dungeons = "icons", boats = "boats", zeppelins = "zeppelins", flight = "flight" }) do
		local set = S.GetPinSet(key)
		if set then S.SetPinSetOn(set, db[opt]) end
	end
	if mod.RefreshFlightsFound then pcall(mod.RefreshFlightsFound) end
	-- Questie's townsfolk and rares (Townsfolk.lua's: the kinds Options have on, built the first time)
	if mod.RefreshTownsfolk then pcall(mod.RefreshTownsfolk, mod) end
end

local function Fail(why)
	failed, diag.why = true, why
	return false
end

local function Build()
	if built or failed then return built end
	if S.IsBuilt() then return Fail("the art is on Blizzard's map already (OpenMap's usual map)") end
	local base = sc.Child:GetFrameLevel() + 2
	view:SetFrameLevel(base)
	canvas:SetFrameLevel(base)
	local ok, err = pcall(S.Build, canvas, base + 1, ART_RANGE, base + ART_RANGE + 4)
	if not ok then return Fail("building the art: " .. tostring(err)) end
	local W, H = S.Size()
	if not S.IsBuilt() then return Fail("the art wasn't built (the world map's size: " .. tostring(W) .. ")") end
	ok, err = pcall(S.Layout, WORLD)
	if not ok or not err then return Fail("laying out the art: " .. tostring(err)) end
	canvas:SetSize(W, H)
	S.RaiseArrow(math.min(9900, base + ARROW_ABOVE))
	MakePointer(POINTER_LEVEL)
	questieLayer = CreateFrame("Frame", nil, view)
	questieLayer:SetAllPoints(view)
	questieLayer:SetFrameLevel(base + ART_RANGE + 10)
	-- what the other files ask of the map, here this view's: a glide (a dock's other end), an icon
	-- clicked with the mouse; and no map of Blizzard's opened (Dungeons.lua's, Zephras Isle's)
	S.GlideToWorld = S.GlideToWorld or function(tu, tv, tz) GlideTo(tu, tv, math.max(tz or 1, zoom)) end
	S.GlideToRect = S.GlideToRect or function(u0, v0, u1, v1, fill)
		local W, H = S.Size()
		local z = math.min(view:GetWidth() / ((u1 - u0) * W), view:GetHeight() / ((v1 - v0) * H)) / FitPx() / (fill or 1)
		GlideTo((u0 + u1) / 2, (v0 + v1) / 2, z)
	end
	S.OnPinMouseUp = S.OnPinMouseUp or function(pin, button) if button == "LeftButton" then Press(pin) end end
	-- the flight masters (Flights.lua's), your map pins (Pins.lua's) and the waypoint (Nav.lua's)
	if mod.BuildFlights then pcall(mod.BuildFlights, mod) end
	if mod.BuildMapPins then pcall(mod.BuildMapPins, mod) end
	if mod.BuildNav then pcall(mod.BuildNav, mod) end
	S.SetShown(true)
	-- what the other files ask of the view (Nav.lua's Find me and search, Close.lua's resting while it
	-- zooms ...): this view's, OpenMap's usual map not being set up while it's on
	mod.Glide = function(tu, tv, tz) GlideTo(tu, tv, tz or zoom) end
	mod.ViewNow = function() return u, v, zoom end
	mod.FitZoom = function(id) return FitZoom(id) end
	mod.ShowNow = function(tu, tv, tz)
		glide = nil
		u, v, zoom = tu, tv, Clamp(tz or zoom, 1, MostAt(tu, tv))
		dirty = true
	end
	mod.Animating = function() return glide ~= nil end
	mod.Zooming = function() return glide ~= nil or GetTime() - stickZoomAt < 0.2 end
	-- (as WorldMap.lua's: the world point, and world units per view px, which the quill measures by)
	mod.CursorWorld = function()
		local x, y = Cursor()
		if not x then x, y = lastX, lastY end
		if not x then return end
		local W, H = S.Size()
		local px = FitPx() * zoom
		local cu, cv = WorldAt(Offset(x, y))
		return cu, cv, 1 / (W * px), 1 / (H * px)
	end
	mod.PadCursorXY = function() return Cursor() end
	mod.WheelZoom = function(delta)
		local sx, sy = 0, 0
		if lastX then sx, sy = Offset(lastX, lastY) end
		ZoomAbout(sx, sy, zoom * (delta > 0 and 1.25 or 0.8))
	end
	-- the pins' list and card (Pins.lua) and the quill (Sketch.lua), on this view
	if mod.SetupPins then
		local okS, errS = pcall(mod.SetupPins, mod, map)
		if not okS then diag.panel = "pins: " .. tostring(errS) end
	end
	if mod.SetupSketch and mod.BuildSketch then
		local okS, errS = pcall(function() mod:SetupSketch(map) mod:BuildSketch() end)
		if not okS then diag.panel = "quill: " .. tostring(errS) end
	end
	-- Report a problem (Report.lua): drawn with the quill here, its code in the view
	if mod.SetupReport then
		local okR, errR = pcall(mod.SetupReport, mod, map)
		if not okR then diag.panel = "report: " .. tostring(errR) end
	end
	-- OpenMap's menu (Panel.lua: what changes Blizzard's map or quest log left out), over this view
	if mod.SetupPanel and not (mod.PanelBuilt and mod.PanelBuilt()) then
		local okP, errP = pcall(mod.SetupPanel, mod, map)
		if not okP then diag.panel = tostring(errP) end
	end
	ok, err = pcall(Look)
	if not ok then diag.why = "the look (carried on): " .. tostring(err) end
	built = true
	if ok then diag.why = "built" end
	return true
end

-- the view to open on: where it was, else around you, your zone filling it
local function FirstView()
	UpdatePlayer()
	local best = C_Map.GetBestMapForUnit("player")
	local l, r, t, b
	if best then l, r, t, b = S.Rect(best) end
	local pos = best and C_Map.GetPlayerMapPosition(best, "player")
	local x, y
	if pos then x, y = ns.Safe.XY(pos) end
	if l and x and y and not ns.Safe.IsSecret(x) and not ns.Safe.IsSecret(y) then
		u, v = l + x * (r - l), t + y * (b - t)
		local zone = best
		while zone and not Stitchable(zone) do
			local info = C_Map.GetMapInfo(zone)
			zone = info and info.parentMapID and info.parentMapID > 0 and info.parentMapID or nil
		end
		zoom = zone and FitZoom(zone) or 4
	else
		u, v, zoom = 0.5, 0.5, 1
	end
end

local function Show()
	diag.shows = diag.shows + 1
	if not On() then diag.why = "off when the map opened (padView, the Gamepad UI, or OpenMap's usual map on)" end
	if not On() or not Build() then
		view:Hide()
		if built then sc.Child:SetAlpha(1) end
		return
	end
	if not u then FirstView() end
	HoldPins()
	ScanQuestie()
	if mod.PadQuestiePaths then pcall(mod.PadQuestiePaths, true) end   -- (Questie's mob paths: Extras.lua's)
	glide = nil
	sc.Child:SetAlpha(0)      -- (Blizzard's map underneath: there, unseen; nothing of it written)
	view:Show()
	dirty = true
end

local function Hide()
	Enter(nil)
	if mod.PadQuestiePaths then pcall(mod.PadQuestiePaths, false) end
	if mod.DungeonViewShown and mod.DungeonViewShown() and mod.CloseDungeonView then pcall(mod.CloseDungeonView) end
	for icon in pairs(questieShown) do if icon:GetParent() == questieLayer then icon:Hide() end end
	wipe(questieShown)
	view:Hide()
	if pointer then pointer:Hide() end
	glide, lastX, lastY = nil, nil, nil
	if sc and sc.Child then sc.Child:SetAlpha(1) end
end

-- for WorldMap.lua: built here, OpenMap's usual map can't be (its art is on this view): a reload then
function mod.PadViewBuilt() return built end
-- for Dungeons.lua: this view is the map now (Blizzard's left as it is)
function mod.PadViewOn() return built and On() end

-- /openmap padview: how the controller view is getting on
function mod.PadViewDiag()
	ns:Print("Controller view: on %s, started %d, set up: %s, map opened %d times, %s; showing %s, size %s; menu %s.",
		tostring(On()), diag.started, diag.setup, diag.shows, diag.why, tostring(view and view:IsShown() or false),
		view and ("%.0f x %.0f"):format(view:GetWidth(), view:GetHeight()) or "-",
		diag.panel or tostring(mod.PanelBuilt and mod.PanelBuilt() or false))
end

-- The waypoint changed. Blizzard's own, the left stick pressed (GamepadTryPlaceWaypoint), goes where its
-- cursor is on its map underneath, not on this view: put again where the cursor is here, on the zone
-- there (as WorldMap.lua does on the usual map). Then the waypoint's icon here
local function OnWaypoint()
	if not built then return end
	if view:IsShown() and GetTime() - ownWaypointAt > 0.5 and lastX and C_Map.HasUserWaypoint
		and C_Map.GetUserWaypoint and C_Map.HasUserWaypoint() then
		local point = C_Map.GetUserWaypoint()
		if point and point.uiMapID == map:GetMapID() then           -- (put on Blizzard's map underneath)
			local cu, cv = WorldAt(Offset(lastX, lastY))
			local chain = S.ChainAt(cu, cv)
			local zone = chain[#chain]
			if zone and zone ~= WORLD and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(zone)) then
				local l, r, t, b = S.Rect(zone)
				ownWaypointAt = GetTime()
				pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(zone, (cu - l) / (r - l), (cv - t) / (b - t)))
			end
		end
	end
	if mod.RefreshWaypoint then pcall(mod.RefreshWaypoint) end
end

local function Setup()
	map = _G.WorldMapFrame
	sc = map and map.ScrollContainer
	if view then return end
	if not (sc and sc.Child and map.GetCanvas) then
		diag.setup = "Blizzard's map isn't the expected kind"
		return
	end
	diag.setup = "done"
	if mod.PadDungeonHost then mod.PadDungeonHost(map) end

	view = CreateFrame("Frame", nil, map)
	view:SetAllPoints(sc)
	view:SetClipsChildren(true)
	view:Hide()
	canvas = CreateFrame("Frame", nil, view)
	canvas:SetSize(1, 1)
	view:SetScript("OnUpdate", OnUpdate)
	view:SetScript("OnSizeChanged", function() dirty = true end)
	map:HookScript("OnShow", Show)
	map:HookScript("OnHide", Hide)
	-- A and X: after Blizzard's own (GamepadMapClick, GamepadMapUp) on its map underneath
	if map.NavigateToGamepadCursor then
		hooksecurefunc(map, "NavigateToGamepadCursor", function() if view:IsShown() then Step(true) end end)
	end
	if map.NavigateToParentMap then
		hooksecurefunc(map, "NavigateToParentMap", function() if view:IsShown() then Step(false) end end)
	end
	-- a setting changed (the menu's checklist, Options): the view's look again
	hooksecurefunc(mod, "Refresh", function()
		if built and On() then
			pcall(Look)
			dirty = true
		end
	end)
	local owner = {}
	ns.RegisterEvent(owner, "USER_WAYPOINT_UPDATED", OnWaypoint)
	ns.RegisterEvent(owner, "SUPER_TRACKING_CHANGED", function() if built and mod.RefreshWaypoint then pcall(mod.RefreshWaypoint) end end)
	ns.RegisterEvent(owner, "INPUT_DEVICE_INTERFACE_TRANSITION", function()
		if map:IsShown() then if On() then Show() else Hide() end end
	end)
	if map:IsShown() then Show() end
end

-- WorldMap.lua's OnEnable, with the Gamepad UI on and padView chosen (OpenMap's usual map waiting)
function mod.StartPadView()
	diag.started = diag.started + 1
	if _G.WorldMapFrame then
		Setup()
	elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
		diag.setup = "waiting for Blizzard's map to load"
		EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Setup)
	else
		diag.setup = "no Blizzard map, and no way to wait for it"
	end
end
