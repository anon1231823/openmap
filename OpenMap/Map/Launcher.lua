--------------------------------------------------------------------------------
-- Ways into OpenMap's menu besides its button on the map (which can be hidden:
-- Panel.lua's mapButtons): the game's addon compartment (the minimap's AddOns
-- list) and, when turned on, a button on the minimap's edge, dragged round it.
-- Click: the map with its menu open; right-click: the options window.
--------------------------------------------------------------------------------

local _, ns = ...
local mod = ns:GetModule("worldmap")
local L = ns.L

local d = mod.defaults
d.minimapButton = false         -- a button on the minimap's edge
d.minimapAngle = 200            -- where round the minimap it sits (degrees, counter-clockwise from east)

local ICON = "Interface\\AddOns\\OpenMap\\Media\\Textures\\OpenMapIconRound"   -- (OpenMap's own, by zloyeb, cut to its gold ring: tools/icon/build.py)
local button

local function OpenMenu()
	if ns.OpenOptions then ns.OpenOptions() end
end

local function OpenWindow()
	local ACD = LibStub("AceConfigDialog-3.0", true)
	if ACD then ACD:Open("OpenMap") end
end

local function Click(mouse)
	if mouse == "RightButton" then OpenWindow() else OpenMenu() end
end

local function Tip(owner)
	-- Titan/LDB hands us its own tooltip, already positioned and shown by the display.
	-- For the minimap button and addon compartment, we still own GameTooltip.
	local brokerTooltip = owner and owner.AddLine
	local tooltip = brokerTooltip and owner or GameTooltip
	if not brokerTooltip then tooltip:SetOwner(owner, "ANCHOR_LEFT") end
	tooltip:AddLine("|cff" .. ns.ACCENT .. "Open|rMap")
	tooltip:AddLine(L["Click: the map and its menu"], 1, 1, 1)
	tooltip:AddLine(L["Right-click: the options window"], 1, 1, 1)
	if owner == button then tooltip:AddLine(L["Drag: move it round the minimap"], 0.6, 0.6, 0.6) end
	if not brokerTooltip then tooltip:Show() end
end

-- the addon compartment (the toc's AddonCompartmentFunc*): globals, as the game looks them up by name
_G.OpenMap_OnAddonCompartmentClick = function(_, mouse) Click(mouse) end
_G.OpenMap_OnAddonCompartmentEnter = function(_, owner) Tip(owner) end
_G.OpenMap_OnAddonCompartmentLeave = function() GameTooltip:Hide() end

local function Place()
	local a = math.rad(mod.db.minimapAngle or 200)
	local r = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

-- Blizzard's own minimap button: the tracking button's border round the icon
local function Make()
	button = CreateFrame("Button", "OpenMapMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnClick", function(_, mouse) Click(mouse) end)
	button:SetScript("OnEnter", Tip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local s = Minimap:GetEffectiveScale()
			if mx then mod.db.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx)) end
			Place()
		end)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
end

function mod.RefreshLauncher()
	if mod.db.minimapButton and Minimap then
		if not button then Make() end
		Place()
		button:Show()
	elseif button then
		button:Hide()
	end
end

-- Titan Panel and other LibDataBroker displays can use this launcher without
-- OpenMap depending on either addon. Libraries from other addons are ready at
-- PLAYER_LOGIN; if no broker is installed, the minimap launcher still works.
local function RegisterBroker()
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	if not ldb then return end
	ldb:NewDataObject("OpenMap", {
		type = "launcher",
		label = "OpenMap",
		icon = ICON,
		tocname = ns.name,
		OnClick = function(_, mouse) Click(mouse) end,
		OnTooltipShow = Tip,
	})
end

function mod:LauncherOptions(opts, get, off)
	local function set(info, v) mod.db[info[#info]] = v mod.RefreshLauncher() end
	opts.minimapButton = { type = "toggle", name = L["Minimap button"], order = 28.5, get = get, set = set, disabled = off,
		desc = L["A button on the minimap's edge that opens the map and its menu (right-click: this window). Drag it round the minimap. OpenMap is in the minimap's AddOns list too."] }
	opts.mapButtons = { type = "toggle", name = L["OpenMap button on the map"], order = 28.6, get = get, disabled = off,
		set = function(_, v) mod.db.mapButtons = v mod:Refresh() end,
		desc = L["The OpenMap button and your favourites on the map. Off, the menu opens with /openmap, the minimap button or the minimap's AddOns list."] }
end

-- (at login, before the map is first opened: the button doesn't wait for the map)
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	if mod.db and mod.db.enabled then
		mod.RefreshLauncher()
		RegisterBroker()
	end
end)
