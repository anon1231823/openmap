--------------------------------------------------------------------------------
-- The map window: drag its title bar to move it, drag either bottom corner's grip to make it
-- any width and height (the stitched map has no edges to keep a shape for); both are
-- remembered, and a size slider scales the whole window. Only the windowed map: the maximized map is left to
-- Blizzard. Blizzard's panel layout tables are left alone (writing to them can
-- taint): the saved place is put back each time Blizzard lays the map out.
-- With Move Any, its position and scale remain authoritative. OpenMap supplies
-- only the viewport resize grips and saved width/height, without a competing mover.
--------------------------------------------------------------------------------

local _, ns = ...
local mod = ns:GetModule("worldmap")
local L = ns.L

local d = mod.defaults
d.window = false                -- { point, relPoint, x, y } once moved
d.windowScale = 1
d.windowSize = false            -- { width, height } once resized
d.fullWidth = true              -- the maximized map fills the screen's width (the stitched map has no edges to keep)
d.chatOverMap = false           -- the chat windows over the full-screen map, to keep talking while it's open
local MIN_SCALE, MAX_SCALE = 0.5, 1.6
local MIN_W, MIN_H = 480, 320
local TOP_OFF = 0                -- px of the window's top that may go above the screen (68, its title and the bar
                                 --  under it, until 0.7.5: the title went off and the window couldn't be dragged back)

local map, handle, grip         -- (grip: both corners' grips)
local FillScreen, SetupQuestLog, TurnArrows
local blizzardSize              -- the windowed map's own size, for a reset
local ours = false              -- OpenMap is moving / sizing the window itself (not to be undone)
local sizing = false            -- a grip is being dragged: the drag sizes the window, nothing puts it back
local moveAny = false           -- Move Any owns position and scale, OpenMap owns viewport dimensions

-- At PLAYER_LOGIN, enabled addons have finished loading. An installed but disabled
-- Move Any must not affect OpenMap's layout (GetAddOnEnableState can misreport it).
local function MoveAnyOn()
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	if not loaded then return false end
	local ok, on = pcall(loaded, "MoveAny")
	return ok and on and true or false
end
mod.MoveAnyOn = MoveAnyOn

local function Refit()
	local sc = map.ScrollContainer
	if sc and sc.OnCanvasSizeChanged then
		if mod.KeepPadCursor then mod.KeepPadCursor(sc.OnCanvasSizeChanged, sc) else sc:OnCanvasSizeChanged() end
	end
end

local function Maximized()
	return map.IsMaximized and map:IsMaximized()
end

local function Apply()
	if not map or Maximized() or ours or sizing then return end
	ours = true
	if not moveAny then
		local w = mod.db.window
		if w then
			local point, rel, relPoint, x, y = map:GetPoint(1)
			if map:GetNumPoints() ~= 1 or point ~= w[1] or rel ~= UIParent or relPoint ~= w[2]
				or math.abs((x or 0) - w[3]) > 0.5 or math.abs((y or 0) - w[4]) > 0.5 then
				map:ClearAllPoints()
				map:SetPoint(w[1], UIParent, w[2], w[3], w[4])
			end
		end
		if math.abs((map:GetScale() or 1) - mod.db.windowScale) > 0.001 then map:SetScale(mod.db.windowScale) end
	end
	local size = mod.db.windowSize
	if size and not InCombatLockdown() and (math.abs(map:GetWidth() - size[1]) > 0.5 or math.abs(map:GetHeight() - size[2]) > 0.5) then
		map:SetSize(size[1], size[2])
		Refit()
	end
	ours = false
end

-- maximized: Blizzard keeps the map art's shape (black bars at the sides on a wide
-- screen); the stitched map is the whole world, so it takes the screen's full width
FillScreen = function()
	if not map or not Maximized() or InCombatLockdown() then return end
	if not moveAny and math.abs((map:GetScale() or 1) - 1) > 0.001 then map:SetScale(1) end   -- (the windowed size is the window's)
	if not mod.db.fullWidth then return end
	local w = math.floor(UIParent:GetWidth())
	if math.abs(map:GetWidth() - w) < 1 then return end
	map:SetWidth(w)
	Refit()
end

local function Save()
	local point, _, relPoint, x, y = map:GetPoint(1)
	if point then mod.db.window = { point, relPoint, x, y } end
end

function mod:ResetWindow()
	mod.db.window = false
	mod.db.windowScale = 1
	mod.db.windowSize = false
	if map and not moveAny then
		ours = true
		map:SetScale(1)
		if blizzardSize and not Maximized() then map:SetSize(blizzardSize[1], blizzardSize[2]) Refit() end
		ours = false
		if map:IsShown() and not InCombatLockdown() then HideUIPanel(map) ShowUIPanel(map) end
	end
end

-- over the map's icons and what OpenMap lays over them (the dungeon view), under OpenMap's menu
local function OverIcons()
	return math.min(map.ScrollContainer:GetFrameLevel() + 9000, 9900)
end

-- a resize grip in one of the window's bottom corners: any width and height, the top edge and
-- the far side staying put. In the window's outer corner (clear of Blizzard's quest log button
-- just inside the right one), over everything there; its catch reaches well past the window's
-- edge, and only a little in over the map
local GRIP, GRIP_OUT, GRIP_IN = 20, 10, 4
-- the right one, while the quest log is beside the map: bigger, and over the quest log (Blizzard's HIGH
-- strata, over the map's own), whose scroll bar's bottom arrow was in that corner and took the clicks
-- (the arrows are lifted clear: SetupQuestLog). Without it the map's own corner is there, with
-- Blizzard's quest log button: the grip as it was, under that
local GRIP_RIGHT, GRIP_RIGHT_IN = 30, 10
local function FitRightGrip()
	local g = grip and grip[1]
	if not g then return end
	local log = map.QuestLog and map.QuestLog:IsShown()
	local size, inside = log and GRIP_RIGHT or GRIP, log and GRIP_RIGHT_IN or GRIP_IN
	g:SetSize(size, size)
	g:SetHitRectInsets(-inside, -GRIP_OUT, -inside, -GRIP_OUT)
	g:SetFrameStrata(log and "HIGH" or map:GetFrameStrata())
	g:SetFrameLevel(log and 9990 or OverIcons() + 1)
end

local function Grip(corner)
	local left = corner == "BOTTOMLEFT"
	local g = CreateFrame("Button", nil, map)
	g:SetSize(GRIP, GRIP)
	g:SetPoint(corner, map, corner, left and -1 or 1, -1)
	g:SetFrameLevel(math.min(map.ScrollContainer:GetFrameLevel() + 9500, 9990))
	if left then g:SetHitRectInsets(-GRIP_OUT, -GRIP_IN, -GRIP_IN, -GRIP_OUT)
	else g:SetHitRectInsets(-GRIP_IN, -GRIP_OUT, -GRIP_IN, -GRIP_OUT) end
	g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	if left then   -- (the chat frame's grabber points right: mirrored)
		for _, tex in ipairs({ g:GetNormalTexture(), g:GetHighlightTexture(), g:GetPushedTexture() }) do tex:SetTexCoord(1, 0, 0, 1) end
	end
	local start
	g:SetScript("OnMouseDown", function()
		if Maximized() then return end
		local x, y = GetCursorPosition()
		start = { x = x, y = y, w = map:GetWidth(), h = map:GetHeight(), left = map:GetLeft(), right = map:GetRight(), top = map:GetTop() }
		sizing = true
		if mod.BeginResize then mod.BeginResize() end
	end)
	local function Finish()
		if not start then return end
		local was = start
		start = nil
		sizing = false
		-- (a click, no drag: nothing; a refit at the same size puts the whole map up again)
		if math.abs(map:GetWidth() - was.w) < 0.5 and math.abs(map:GetHeight() - was.h) < 0.5 then
			if mod.EndResize then mod.EndResize() end
			return
		end
		mod.db.windowSize = { math.floor(map:GetWidth() + 0.5), math.floor(map:GetHeight() + 0.5) }
		if not moveAny then Save() end
		if map:IsShown() then Refit() end   -- (laid out at the scale the drag showed: WorldMap.lua)
		if mod.EndResize then mod.EndResize() end
	end
	g:SetScript("OnMouseUp", Finish)
	-- (the map closed mid-drag: the mouse-up never comes here, so the drag ends with the map, or
	-- the moment the button turns out not to be held)
	g:SetScript("OnHide", Finish)
	g:SetScript("OnUpdate", function()
		if not start then return end
		if not IsMouseButtonDown("LeftButton") then Finish() return end
		local x, y = GetCursorPosition()
		local s = map:GetEffectiveScale()
		local dx = (x - start.x) / s
		local w = math.max(MIN_W, start.w + (left and -dx or dx))
		local h = math.max(MIN_H, start.h - (y - start.y) / s)
		ours = true
		if not moveAny then
			map:ClearAllPoints()
			-- (offsets in the map's own units, as GetLeft gives)
			map:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left and start.right - w or start.left, start.top)
		end
		-- Move Any owns the frame anchor; change dimensions only to avoid a mover fight.
		map:SetSize(w, h)
		ours = false
		if mod.FollowResize then mod.FollowResize() end
	end)
	g:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, left and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["Drag to resize the map"], 1, 1, 1)
		GameTooltip:Show()
	end)
	g:SetScript("OnLeave", GameTooltip_Hide)
	return g
end

function mod:SetupWindow(worldMap)
	map = worldMap
	moveAny = MoveAnyOn()
	-- Enhance QoL's Mover (World Map) sizes and places the map too, and the two fight over its scale (a
	-- player's report). Its setting can't be read from here, so with Enhance QoL on it's said once
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	if loaded and not mod.db.eqolNoted then
		local on = false
		for _, name in ipairs({ "EnhanceQoL", "EnhanceQoLMover", "EnhanceQoL_Mover" }) do
			if loaded(name) then on = true end
		end
		if on then
			mod.db.eqolNoted = true
			ns:Print(L["Enhance QoL: if its Mover > World Map is on, turn it off. It and OpenMap both size the map, and the map's scale goes wrong."])
		end
	end
	grip = {}
	-- With Move Any, leave position, scale and title bar to it; resizing is set up below.
	if not moveAny then
		map:SetClampedToScreen(true)
		-- partly off the screen: sideways and down while some of it stays on, never up (its title bar is
		-- what moves it; /openmap reset or the Look tab's Reset size and place bring it back)
		local function Clamp()
			local w, h = map:GetWidth(), map:GetHeight()
			if not (w and h) or w <= 0 or InCombatLockdown() then return end
			local side = math.max(0, w - 160)
			map:SetClampRectInsets(side, -side, -TOP_OFF, math.max(0, h - TOP_OFF - 80))
		end
		Clamp()
		map:HookScript("OnSizeChanged", Clamp)
		if not Maximized() then blizzardSize = { map:GetWidth(), map:GetHeight() } end

		-- the title bar: a strip along the top, clear of the corner buttons
		handle = CreateFrame("Frame", nil, map)
		handle:SetPoint("TOPLEFT", map, "TOPLEFT", 70, 0)
		handle:SetPoint("TOPRIGHT", map, "TOPRIGHT", -70, 0)
		handle:SetHeight(22)
		handle:SetFrameLevel(map:GetFrameLevel() + 5)
		handle:EnableMouse(true)
		handle:RegisterForDrag("LeftButton")
		handle:SetScript("OnDragStart", function()
			if Maximized() then return end
			map:SetMovable(true)
			map:StartMoving()
		end)
		handle:SetScript("OnDragStop", function()
			map:StopMovingOrSizing()
			map:SetUserPlaced(false)            -- (ours to remember, not the layout cache's)
			Save()
		end)
		handle:SetScript("OnEnter", function(self)
			if Maximized() then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(L["Drag to move the map"], 1, 1, 1)
			GameTooltip:Show()
		end)
		handle:SetScript("OnLeave", GameTooltip_Hide)

		-- put the saved place back whenever Blizzard lays the map out: opening shows the map first and
		-- places it after (inside ShowUIPanel), so it's put back once that's done, not a moment later
		map:HookScript("OnShow", Apply)
		if ShowUIPanel then hooksecurefunc("ShowUIPanel", function(frame) if frame == map then Apply() end end) end
		if UpdateUIPanelPositions then hooksecurefunc("UpdateUIPanelPositions", function() if map:IsShown() then Apply() end end) end
		-- ... and the moment anything else sizes, scales or places the windowed map (Blizzard's
		-- layout, its quest log widening it, its minimize ...), so it never shows elsewhere first.
		-- (Not while it's being dragged: the drag places it, and the drop saves where it went.)
		local dragging = false
		local function Hold()
			if ours or dragging or not map:IsShown() then return end
			Apply()
		end
		for _, method in ipairs({ "SetSize", "SetWidth", "SetHeight", "SetScale", "SetPoint" }) do
			if map[method] then hooksecurefunc(map, method, Hold) end
		end
		handle:HookScript("OnDragStart", function() dragging = true end)
		handle:HookScript("OnDragStop", function() dragging = false end)
		-- (the map closed mid-move: no drag stop comes, so the move ends with the map)
		handle:HookScript("OnHide", function()
			if not dragging then return end
			dragging = false
			map:StopMovingOrSizing()
			map:SetUserPlaced(false)
			Save()
		end)
	else
		-- Preserve only OpenMap's saved width/height. Move Any still controls
		-- the window's position and scale, including any subsequent adjustments.
		map:HookScript("OnShow", Apply)
		if ShowUIPanel then hooksecurefunc("ShowUIPanel", function(frame) if frame == map then Apply() end end) end
		if UpdateUIPanelPositions then hooksecurefunc("UpdateUIPanelPositions", function() if map:IsShown() then Apply() end end) end
		local function RestoreSize()
			if not ours and not sizing and map:IsShown() then Apply() end
		end
		for _, method in ipairs({ "SetSize", "SetWidth", "SetHeight" }) do
			if map[method] then hooksecurefunc(map, method, RestoreSize) end
		end
	end
	-- Both clients use the same corner grips; only their resize anchoring differs.
	grip = { Grip("BOTTOMRIGHT"), Grip("BOTTOMLEFT") }
	local function Mode()
		local max = Maximized()
		mod.ChatOverMap()
		if handle then handle:SetShown(not max) end
		for _, g in ipairs(grip) do g:SetShown(not max) end
		if max then FillScreen() else Apply() end
	end
	if map.Maximize then hooksecurefunc(map, "Maximize", Mode) end
	if map.Minimize then hooksecurefunc(map, "Minimize", Mode) end
	-- Full screen or windowed, and the quest log beside it, kept for next time: Blizzard opens the map as
	-- its CVars say (miniWorldMap, questLogOpen), and on this client its buttons don't always write them, so
	-- the map went back to the window each time it was closed (a player's report). Only the CVars: Blizzard's
	-- own code, opening the map, does the rest
	local function Keep(cvar, value)
		local ok, now = pcall(GetCVar, cvar)
		if ok and now ~= nil and now ~= value then pcall(SetCVar, cvar, value) end
	end
	if map.HandleUserActionMaximizeSelf then
		hooksecurefunc(map, "HandleUserActionMaximizeSelf", function() Keep("miniWorldMap", "0") end)
	end
	if map.HandleUserActionMinimizeSelf then
		hooksecurefunc(map, "HandleUserActionMinimizeSelf", function() Keep("miniWorldMap", "1") end)
	end
	for _, name in ipairs({ "HandleUserActionToggleSidePanel", "HandleUserActionOpenSidePanel", "HandleUserActionCloseSidePanel" }) do
		if map[name] then
			hooksecurefunc(map, name, function()
				if Maximized() then return end      -- (full screen hides it: OpenMap's maxQuestLog keeps that one)
				local log = map.QuestLog
				if log then Keep("questLogOpen", log:IsShown() and "1" or "0") end
			end)
		end
	end
	-- The map is left a UI panel of the game's, opened and closed by its own panel code. (0.7.0 to 0.7.5
	-- marked the windowed map `editModeManuallyShown` and put it in UISpecialFrames, to keep it open beside
	-- an NPC's window. Both are read by the game's code that closes it (HideUIPanel, CloseSpecialWindows),
	-- and a value OpenMap wrote taints that code: the map holds protected frames (the group members' pin),
	-- so in combat its Hide was blocked and neither Escape nor M closed it, players' reports)
	map:HookScript("OnShow", function() mod.ChatOverMap() end)
	map:HookScript("OnHide", function() mod.ChatOverMap() end)
	-- Blizzard re-sizes the maximized map when the screen or UI scale changes
	if map.UpdateMaximizedSize then hooksecurefunc(map, "UpdateMaximizedSize", function() if Maximized() then FillScreen() end end) end
	map:HookScript("OnShow", Mode)
	for _, g in ipairs(grip) do g:SetFrameLevel(OverIcons() + 1) end
	FitRightGrip()
	SetupQuestLog()
	if moveAny then
		-- Keep the resize grip in the bottom-right corner: put the quest toggle at
		-- the bottom of the right-hand tab rail, above the coordinate labels.
		local function PlaceQuestToggle()
			local toggle = map.SidePanelToggle
			local canvas = map.GetCanvasContainer and map:GetCanvasContainer()
			if not toggle or not canvas or InCombatLockdown() then return end
			local windowed = not Maximized()
			local x, y = -2, windowed and 46 or 1
			local p, rel, rp, ox, oy = toggle:GetPoint(1)
			if toggle:GetNumPoints() == 1 and p == "BOTTOMRIGHT" and rel == canvas
				and rp == "BOTTOMRIGHT" and ox == x and oy == y then return end
			toggle:ClearAllPoints()
			toggle:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", x, y)
			if mod.PlaceCoords then mod.PlaceCoords() end
		end
		map:HookScript("OnShow", PlaceQuestToggle)
		if map.RefreshOverlayFrames then hooksecurefunc(map, "RefreshOverlayFrames", PlaceQuestToggle) end
		if map.SetDisplayState then hooksecurefunc(map, "SetDisplayState", PlaceQuestToggle) end
		if map.Maximize then hooksecurefunc(map, "Maximize", PlaceQuestToggle) end
		if map.Minimize then hooksecurefunc(map, "Minimize", PlaceQuestToggle) end
		if map.QuestLog then
			map.QuestLog:HookScript("OnShow", PlaceQuestToggle)
			map.QuestLog:HookScript("OnHide", PlaceQuestToggle)
		end
		PlaceQuestToggle()
	end
	-- Blizzard's buttons on the map over its icons and the dungeon view (the quest log's button among
	-- them); and that button's arrows turned (Blizzard's point the other way): the log comes in from
	-- the right, so in is ◀ and away is ▶
	local function Buttons()
		local over = OverIcons() + 2
		for _, f in ipairs(map.overlayFrames or {}) do
			if f.GetFrameLevel and f:GetFrameLevel() < over then f:SetFrameLevel(over) end
		end
		TurnArrows(map.SidePanelToggle)
		TurnArrows(mod.maxLogToggle)
	end
	Buttons()
	if map.RefreshOverlayFrames then hooksecurefunc(map, "RefreshOverlayFrames", Buttons) end
	map:HookScript("OnShow", Buttons)
end

--------------------------------------------------------------------------------
-- The quest log: its list's background is an atlas at its own size, anchored at the top only,
-- so a window taller than Blizzard's ends it in a line: it's stretched to the list's foot.
-- Blizzard's full-screen map always hides the quest log (and its side-panel toggle leaves full
-- screen first); while it's full screen, OpenMap shows it over the map's right edge when asked
-- (maxQuestLog), as Blizzard anchors it, and takes it away again just before the map leaves full
-- screen, so Blizzard's own layout for the window comes back as it was. Never in combat.
--------------------------------------------------------------------------------

d.maxQuestLog = false           -- the quest log on the full-screen map

local function Log() return map.QuestLog end

-- a quest log button's arrows the other way round: its open button ◀ (Blizzard's "hide" art), its
-- close button ▶ ("show"); once each (kept here, not on Blizzard's frame)
local turned = setmetatable({}, { __mode = "k" })
TurnArrows = function(toggle)
	if not toggle or turned[toggle] or not toggle.OpenButton or not toggle.CloseButton then return end
	turned[toggle] = true
	local function Art(b, name)
		if b.SetNormalAtlas then
			b:SetNormalAtlas(name .. "-Up")
			b:SetPushedAtlas(name .. "-Down")
		end
	end
	Art(toggle.OpenButton, "QuestCollapse-Hide")
	Art(toggle.CloseButton, "QuestCollapse-Show")
end

local function ShowMaxLog(on)
	local log = Log()
	if not log or not Maximized() or InCombatLockdown() or on == log:IsShown() then return end
	log:SetShown(on)
	if map.UpdateSpacerFrameAnchoring then map:UpdateSpacerFrameAnchoring() end   -- (the canvas makes room for it)
end

-- the menu's Quest log button while the map is full screen
function mod.MaxQuestLog() return Maximized() and true or false end
function mod.ToggleMaxQuestLog()
	if InCombatLockdown() then
		ns:Print(L["The quest log can't be opened or closed in combat."])
		return
	end
	mod.db.maxQuestLog = not (Log() and Log():IsShown())
	ShowMaxLog(mod.db.maxQuestLog)
	if mod.maxLogToggle then mod.maxLogToggle:Refresh() end
end

-- A quest's details: Blizzard's are a fixed 502 high, anchored at the top, sized for its own
-- window (534 high), so a taller window leaves a gap under them. They reach the quest log's foot
-- instead (as far below the list as Blizzard's do in its window: 502 there), the text with them;
-- the parchment behind the text runs down to the rewards (Blizzard's 440 in its 502), cut from
-- its art as Blizzard cuts it, or stretched once it's taller than the art
local DETAILS_BELOW, TEXT_FOOT, PAPER_FOOT = 6, 29, 62
local function FitDetailsPaper(details)
	local bg = details.Bg
	local atlas = bg and bg.GetAtlas and bg:GetAtlas()
	local info = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	local w, h = details:GetWidth(), details:GetHeight()
	if not info or not info.width or info.width <= 0 or not w or not h or h <= PAPER_FOOT then return end
	local natural = info.height * w / info.width
	local want = h - PAPER_FOOT
	bg:SetWidth(w)
	bg:SetTexCoord(0, 1, 0, math.min(1, want / natural))
	bg:SetHeight(want)
end

local function StretchDetails()
	local quests = Log() and Log().QuestsFrame
	local details = quests and quests.DetailsFrame
	if not details or not details.ScrollFrame or details.omStretched then return end
	details.omStretched = true
	details:SetPoint("BOTTOMRIGHT", quests, "BOTTOMRIGHT", 0, -DETAILS_BELOW)
	details.ScrollFrame:SetPoint("BOTTOMLEFT", details, "BOTTOMLEFT", 5, TEXT_FOOT)
	-- (after Blizzard sizes it for its own height, each time the details show)
	details:HookScript("OnShow", FitDetailsPaper)
	details:HookScript("OnSizeChanged", FitDetailsPaper)
end

-- the quest log's scroll bars end this much higher, clear of the window's resize grip in the corner
local BAR_LIFT = 26
local function LiftBar(bar)
	if not bar or bar.omLifted or not bar.GetNumPoints then return end
	bar.omLifted = true
	local points = {}
	for i = 1, bar:GetNumPoints() do points[i] = { bar:GetPoint(i) } end
	bar:ClearAllPoints()
	for _, pt in ipairs(points) do
		local point, rel, relPoint, x, y = pt[1], pt[2], pt[3], pt[4], pt[5]
		if point:find("^BOTTOM") then y = (y or 0) + BAR_LIFT end
		bar:SetPoint(point, rel, relPoint, x, y)
	end
end

SetupQuestLog = function()
	local scroll = _G.QuestScrollFrame
	LiftBar(scroll and scroll.ScrollBar)
	LiftBar(_G.QuestMapDetailsScrollFrame and _G.QuestMapDetailsScrollFrame.ScrollBar)
	local bg = scroll and scroll.Background
	if bg and bg.SetPoint then bg:SetPoint("BOTTOMLEFT", scroll, "BOTTOMLEFT", 0, 0) end
	if not Log() then return end
	StretchDetails()
	-- Blizzard's collapse / expand button for it, in the view's bottom-right corner, hidden while
	-- full screen: a copy of it (its own template, so it looks and turns the same) there instead
	local toggle
	if map.GetCanvasContainer and pcall(function() toggle = CreateFrame("Frame", nil, map, "WorldMapSidePanelToggleTemplate") end) and toggle and toggle.Refresh then
		toggle:SetPoint("BOTTOMRIGHT", map:GetCanvasContainer(), "BOTTOMRIGHT", -2, 1)
		toggle:SetFrameLevel(math.min(map.ScrollContainer:GetFrameLevel() + 9300, 9950))
		toggle.OnClick = function(self) mod.ToggleMaxQuestLog() self:Refresh() end   -- (its buttons call this)
		-- (open or not: the log OpenMap shows over the map, not Blizzard's side panel, which is never open here)
		toggle.Refresh = function(self)
			local open = Log() and Log():IsShown() or false
			self.OpenButton:SetShown(not open)
			self.CloseButton:SetShown(open)
		end
		toggle:Hide()
		mod.maxLogToggle = toggle
	end
	local function ShowToggle()
		if not toggle then return end
		toggle:SetShown(Maximized() and true or false)
		if toggle:IsShown() then toggle:Refresh() end
	end
	-- after Blizzard settles the map's state (opening, maximizing): put it back if it's wanted
	if map.SetDisplayState then
		hooksecurefunc(map, "SetDisplayState", function()
			if Maximized() and mod.db.maxQuestLog then ShowMaxLog(true) end
			ShowToggle()
		end)
	end
	if map.Maximize then hooksecurefunc(map, "Maximize", ShowToggle) end
	if map.Minimize then hooksecurefunc(map, "Minimize", ShowToggle) end
	Log():HookScript("OnShow", function() if toggle and toggle:IsShown() then toggle:Refresh() end FitRightGrip() end)
	Log():HookScript("OnHide", function() if toggle and toggle:IsShown() then toggle:Refresh() end FitRightGrip() end)
	-- leaving full screen: hidden first (Blizzard only widens the window for a quest log it shows itself)
	local mm = map.BorderFrame and map.BorderFrame.MaximizeMinimizeFrame
	local minimize = mm and mm.MinimizeButton
	if minimize then minimize:HookScript("OnMouseDown", function() ShowMaxLog(false) end) end
	map:HookScript("OnHide", function() ShowMaxLog(false) end)
end

--------------------------------------------------------------------------------
-- The chat over the full-screen map (chatOverMap; a player's request: keep talking while the map is
-- open): the chat windows, their tabs and their buttons a strata over the map's while it's full screen,
-- and back as they were when it isn't. Only their strata (they're not protected: no taint)
--------------------------------------------------------------------------------

local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local raised = {}               -- frame -> its own strata, while raised

local function ChatFrames()
	local list = {}
	local function add(f) if type(f) == "table" and f.SetFrameStrata then list[#list + 1] = f end end
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		add(_G["ChatFrame" .. i])
		add(_G["ChatFrame" .. i .. "Tab"])
		add(_G["ChatFrame" .. i .. "EditBox"])
	end
	for _, name in ipairs({ "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton",
		"ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "ChatAlertFrame" }) do
		add(_G[name])
	end
	return list
end

function mod.ChatOverMap()
	local want = map and mod.db.chatOverMap and map:IsShown() and Maximized()
	if want then
		local above = "FULLSCREEN_DIALOG"
		local own = map:GetFrameStrata()
		for i, s in ipairs(STRATA) do
			if s == own then above = STRATA[math.min(i + 1, #STRATA - 1)] end
		end
		for _, f in ipairs(ChatFrames()) do
			if not raised[f] then raised[f] = f:GetFrameStrata() end
			if f:GetFrameStrata() ~= above then f:SetFrameStrata(above) end
		end
	elseif next(raised) then
		for f, s in pairs(raised) do f:SetFrameStrata(s) end
		wipe(raised)
	end
end

function mod:WindowOptions(opts, get, set, off)
	local function moved() return off() or moveAny end   -- (Move Any's to size and place)
	opts.windowScale = { type = "range", name = L["Map size"], order = 25, min = MIN_SCALE, max = MAX_SCALE, step = 0.05, isPercent = true,
		get = get, set = function(info, v) set(info, v) Apply() end, disabled = moved,
		desc = L["Scales the whole windowed map. Drag either of its bottom corners to change its width and height, and its title bar to move it."] }
	opts.fullWidth = { type = "toggle", name = L["Full-screen map fills the width"], order = 27, get = get,
		set = function(info, v)
			set(info, v)
			if not map or not Maximized() then return end
			if map.UpdateMaximizedSize then map:UpdateMaximizedSize() else FillScreen() end   -- (off: Blizzard's size again on the next maximize)
		end, disabled = off,
		desc = L["When maximized, the map takes the screen's whole width instead of keeping Blizzard's shape with bars at the sides."] }
	opts.chatOverMap = { type = "toggle", name = L["Chat over the full-screen map"], order = 27.5, get = get,
		set = function(info, v) set(info, v) mod.ChatOverMap() end, disabled = off,
		desc = L["Keeps the chat windows on show over the map while it's full screen, to keep talking while you look."] }
	opts.resetWindow = { type = "execute", name = L["Reset size and place"], order = 26, disabled = moved,
		func = function() mod:ResetWindow() end }
end
