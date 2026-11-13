--------------------------------------------------------------------------------
-- The gamepad (Forever's gamepad mode). On the map Blizzard moves a cursor of its own
-- (SoftCursor) with the left stick and zooms with the right; WorldMap.lua zooms the stitched
-- map about that cursor and makes its A and X zoom in and out as clicks do. That cursor has
-- no mouse-over: here, what's under it (OpenMap's buttons and menu, its map icons) is entered
-- and left as the mouse would (tooltips, highlights), and A presses it.
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")

local REACH = 12                -- px from the cursor that an icon counts as under it (Blizzard's for its own)
local EVERY = 0.05              -- seconds between looks at what's under the cursor
local roots = {}                -- OpenMap's controls on the map (Panel, Paint, Report add theirs)
mod.padRoots = roots
local hovered                   -- what's under the cursor, entered
local found, foundLevel, blocked

local function Inside(f, x, y)
	local l, b, w, h = f:GetRect()
	if not l then return false end
	local es = f:GetEffectiveScale()
	local il, ir, it, ib = f:GetHitRectInsets()
	x, y = x / es, y / es
	return x >= l + il and x <= l + w - ir and y >= b + ib and y <= b + h - it
end

local function Pressable(f)
	return f:IsObjectType("Button") or f:IsObjectType("Slider") or f:IsObjectType("EditBox")
end

-- a frame's place in the stacking, as the game draws it: its strata, then its level (a DIALOG window
-- over the map is over a menu at a higher level in a lower strata)
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local function Height(f) return (STRATA[f:GetFrameStrata()] or 3) * 100000 + f:GetFrameLevel() end

-- the topmost pressable frame at (x, y) in f and its children (found); blocked: a frame
-- that takes the mouse is there (the menu's background), so the map under it isn't
local Find
local function FindIn(x, y, ...)
	for i = 1, select("#", ...) do Find((select(i, ...)), x, y) end
end
function Find(f, x, y)
	if not f:IsVisible() then return end
	if f:IsMouseEnabled() and Inside(f, x, y) then
		blocked = true
		if Pressable(f) and (not found or Height(f) >= foundLevel) then found, foundLevel = f, Height(f) end
	end
	FindIn(x, y, f:GetChildren())
end

-- OpenMap's control under (x, y), or its map icon (not with `noPins`); and whether a control is in the way
local function Under(x, y, noPins)
	found, foundLevel, blocked = nil, nil, false
	for _, root in ipairs(roots) do Find(root, x, y) end
	if found or blocked then return found, blocked end
	local pin = not noPins and S.IsBuilt() and mod.IsStitched() and S.PinAt(x, y, REACH)
	if pin then return pin, true end
	return nil, false
end

-- for PadView.lua: OpenMap's control under (x, y) (its dungeon's map, its windows), and whether one is in the way
function mod.PadControlAt(x, y) return Under(x, y, true) end

-- for PadView.lua: the topmost of OpenMap's frames under (x, y) that takes the mouse wheel (the menu's list ...),
-- for the right stick to scroll it
local wheel, wheelLevel
local function FindWheel(f, x, y)
	if not f:IsVisible() then return end
	if f:IsMouseWheelEnabled() and f:GetScript("OnMouseWheel") and Inside(f, x, y)
		and (not wheel or Height(f) >= wheelLevel) then wheel, wheelLevel = f, Height(f) end
	for _, child in ipairs({ f:GetChildren() }) do FindWheel(child, x, y) end
end
function mod.PadWheelAt(x, y)
	wheel, wheelLevel = nil, nil
	for _, root in ipairs(roots) do FindWheel(root, x, y) end
	return wheel
end

local function Enter(f)
	if f == hovered then return end
	local was = hovered
	hovered = f
	if was then
		if was.UnlockHighlight then was:UnlockHighlight() end
		local leave = was:GetScript("OnLeave")
		if leave then leave(was, false) end
	end
	if f then
		if f.LockHighlight then f:LockHighlight() end
		local enter = f:GetScript("OnEnter")
		if enter then enter(f, false) end
	end
end

-- A, with the gamepad's cursor at (x, y): true if it was OpenMap's to take (`noPins`: Blizzard's own
-- icon there has just taken it, so OpenMap's map icons don't too: only its windows over the map)
function mod.PadPress(x, y, noPins)
	local f, taken = Under(x, y, noPins)
	if not f then return taken end
	if f:IsObjectType("Slider") then
		-- to the value at the cursor
		local lo, hi = f:GetMinMaxValues()
		local l, _, w = f:GetRect()
		if l and w > 0 and hi > lo then
			local v = lo + (hi - lo) * math.max(0, math.min(1, (x / f:GetEffectiveScale() - l) / w))
			local step = f:GetValueStep()
			if step and step > 0 then v = lo + math.floor((v - lo) / step + 0.5) * step end
			f:SetValue(v)
		end
	elseif f:IsObjectType("EditBox") then
		f:SetFocus()
	elseif f.OnClick and not f:GetScript("OnClick") then
		f:OnClick()             -- (a map icon: its click, as WorldMap.lua's OnPinMouseUp gives it)
	else
		f:Click()
	end
	return true
end

--------------------------------------------------------------------------------
-- The controller's B and full-screen buttons on OpenMap's map with the Gamepad UI (Options' padMap).
-- Blizzard binds them to its map footer's actions, made again on every map change; on OpenMap's map
-- that change runs OpenMap's code too (its zoom and view), so the actions are made as OpenMap's, and
-- the game blocks what B does (closing the map hands the gamepad cursor back: Blizzard's code only).
-- While the footer shows they're bound instead to secure buttons that click the map's own buttons, as
-- Blizzard's B does (SmartNavigation:AttemptClose clicks the close button): B the close button (full
-- screen: the minimize button, as Blizzard's goes back to the window first; a quest's details open:
-- Blizzard's own, which goes back to the list), the D-pad's down and up the maximize and minimize
-- buttons. (Bindings can't change in combat: set or cleared after it.)
--------------------------------------------------------------------------------

local keyOwner = CreateFrame("Frame")
local clickers, waiting = {}, false

local function Clicker(name)
	local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	b:SetAttribute("type", "click")
	b:RegisterForClicks("AnyUp", "AnyDown")   -- (the template acts on the one the game's key-down setting asks for)
	return b
end

local function Bind(key, name, target)
	if not (key and target) then return end
	local b = clickers[name] or Clicker(name)
	clickers[name] = b
	b:SetAttribute("clickbutton", target)
	SetOverrideBindingClick(keyOwner, true, key, name, "LeftButton")
end

local padMap
local function PadKeys()
	if InCombatLockdown() then waiting = true return end
	waiting = false
	ClearOverrideBindings(keyOwner)
	local footer = padMap and padMap.worldMapFooter
	if not (footer and footer.isShown and padMap:IsShown() and mod.enabled and mod.db.padMap and mod.PadUI()) then return end
	local border = padMap.BorderFrame
	local sizes = border and border.MaximizeMinimizeFrame
	local full = padMap.IsMaximized and padMap:IsMaximized()
	local details = QuestMapFrame and QuestMapFrame.DetailsFrame and QuestMapFrame.DetailsFrame:IsShown()
	if not details then   -- (Blizzard's own B then: back to the quest list, nothing blocked)
		Bind(GAMEPAD_FACE_RIGHT, "OpenMapPadBack", full and sizes and sizes.MinimizeButton or border and border.CloseButton)
	end
	if sizes then
		if full then
			Bind(GAMEPAD_DPAD_TOP, "OpenMapPadSmall", sizes.MinimizeButton)
		else
			Bind(GAMEPAD_DPAD_BOTTOM, "OpenMapPadFull", sizes.MaximizeButton)
		end
	end
end
mod.PadKeys = PadKeys

local function SetupPadKeys(worldMap)
	padMap = worldMap
	local footer = worldMap.worldMapFooter
	if footer then   -- (after Blizzard's own binding, each time it binds or unbinds them)
		for _, name in ipairs({ "ShowAndActivateBindings", "HideAndDeactivateBindings", "Refresh" }) do
			if type(footer[name]) == "function" then hooksecurefunc(footer, name, PadKeys) end
		end
	end
	for _, name in ipairs({ "Maximize", "Minimize" }) do
		if type(worldMap[name]) == "function" then hooksecurefunc(worldMap, name, PadKeys) end
	end
	worldMap:HookScript("OnHide", PadKeys)
	-- a quest's details opening or closing changes whose B it is (PadKeys: Blizzard's own while they're
	-- open), and the footer doesn't always say so
	local details = QuestMapFrame and QuestMapFrame.DetailsFrame
	if details and details.HookScript then
		details:HookScript("OnShow", PadKeys)
		details:HookScript("OnHide", PadKeys)
	end
	ns.RegisterEvent(keyOwner, "PLAYER_REGEN_ENABLED", function() if waiting then PadKeys() end end)
	ns.RegisterEvent(keyOwner, "INPUT_DEVICE_INTERFACE_TRANSITION", PadKeys)
end

function mod:SetupGamepad(worldMap)
	SetupPadKeys(worldMap)
	local driver = CreateFrame("Frame", nil, worldMap)
	local wait = 0
	driver:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = EVERY
		local x, y = mod.PadCursor()
		Enter(x and (Under(x, y)) or nil)
	end)
	driver:SetScript("OnHide", function() Enter(nil) end)
end
