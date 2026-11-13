--------------------------------------------------------------------------------
-- World map extras:
--   coordinates   two labels in the bottom-right corner: your position,
--                 and the zone and position under the cursor (any zone, not just the one shown)
--   zone levels   the hover label adds a zone's level range (coloured by your
--                 level; Data/Levels.lua)
--   moving fade   how far the map fades while you move (0: not at all); ours, not the
--                 game's (its mapFade CVar is held off): smooth, never under the mouse
-- And other addons' pins through HereBeDragons (Questie's, TomTom's, gatherers' ...): on a zone
-- map they only show that zone's own; the stitched map shows the neighbours too, so theirs come along.
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")

local d = mod.defaults
d.coords = true
d.zoneLevels = true
d.moveFade = 0                  -- how much the map fades while you move (0 to 0.9)
d.mapFpsCap = 0                 -- the frame rate at most while the map shows (the game's maxFPS, held then; 0: off)
d.zoomHidePins = false          -- other addons' icons (Questie's ...) hidden while the map zooms (off from v0.8.6)

local map, sc, bar
local labelProvider                     -- Blizzard's area label

local function SetCVarSafe(name, value)
	if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, name, value) elseif SetCVar then pcall(SetCVar, name, value) end
end

-- Game settings OpenMap holds while it runs: Blizzard's map coordinates while OpenMap's own show (they'd
-- double them), and the game's map fade (OpenMap's is the one that runs). The player's own values are
-- kept (mod.char.cvars: name -> value) and put back when OpenMap lets go, and at logout, so the game
-- saves the player's values (OpenMap takes the settings again at the next login)
local COORDS = { "worldMapShowPlayerCoords", "worldMapShowCursorCoords" }
local loggingOut = false
local cvarOwner = {}            -- (the logout handler's key)

local function DefaultCVar(name)
	local get = C_CVar and C_CVar.GetCVarDefault or _G.GetCVarDefault
	local ok, v = pcall(get or nop, name)
	return ok and v or "1"
end

local function Kept()
	if not mod.char.cvars then
		local kept = {}
		-- (from before they were kept: the fade was kept on its own; the coordinates were turned off
		-- unkept, so they go back to the game's default)
		if mod.char.mapFade ~= nil then
			kept.mapFade = mod.char.mapFade
			if mod.db.coords then
				for _, name in ipairs(COORDS) do
					if GetCVar(name) == "0" then kept[name] = DefaultCVar(name) end
				end
			end
		end
		mod.char.mapFade = nil
		mod.char.cvars = kept
	end
	return mod.char.cvars
end

local function HoldCVar(name, value)
	local kept = Kept()
	if kept[name] == nil then
		local ok, was = pcall(GetCVar, name)
		if ok and was and was ~= value then kept[name] = was end
	end
	SetCVarSafe(name, value)
end

local function LetGoCVar(name)
	local kept = Kept()
	local was = kept[name]
	if was == nil then return end
	kept[name] = nil
	SetCVarSafe(name, was)
end

-- the zone (or continent) under the cursor, the cursor's point in it, and its
-- point in the map shown. Stitched, from the cursor itself: Blizzard's cursor
-- position is clamped to the shown map's rectangle.
local lastU, lastV, lastId
local function PlaceAt()
	local mapID = map:GetMapID()
	if mod.IsStitched() then
		local u, v, pu = mod.CursorWorld()
		local id = lastId
		if not lastU or math.abs(u - lastU) > (pu or 0) * 2 or math.abs(v - lastV) > (pu or 0) * 2 then
			local chain = S.ChainAt(u, v)
			id, lastU, lastV, lastId = chain[#chain], u, v, chain[#chain]
		end
		local l, r, t, b = S.Rect(id)
		local hx, hy = mod.FromWorld(mapID, u, v)
		return id, (u - l) / (r - l), (v - t) / (b - t), hx, hy
	end
	local x, y
	if mod.PadCursor() and map.GetNormalizedGamepadCursorPosition then x, y = map:GetNormalizedGamepadCursorPosition()
	else x, y = map:GetNormalizedCursorPosition() end
	local info = C_Map.GetMapInfoAtPosition(mapID, x, y)
	if info and info.mapID ~= mapID then
		local l, r, t, b = C_Map.GetMapRectOnMap(info.mapID, mapID)
		if l and r > l and b > t then return info.mapID, (x - l) / (r - l), (y - t) / (b - t), x, y end
	end
	return mapID, x, y, x, y
end

local function MapName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name
end

--------------------------------------------------------------------------------
-- Coordinates
--------------------------------------------------------------------------------

local NUMBERS = 74              -- px: the numbers' own box, right-aligned (wide enough for "100.0, 100.0")
local function Coord(x, y)
	if not x or x < 0 or x > 1 or y < 0 or y > 1 then return "|cff808080--|r" end
	return ("%.1f, %.1f"):format(x * 100, y * 100)
end

local throttle = 0
local function UpdateCoords(_, elapsed)
	throttle = throttle + elapsed
	if throttle < 0.05 then return end
	throttle = 0

	local best = C_Map.GetBestMapForUnit("player")
	local pos = best and C_Map.GetPlayerMapPosition(best, "player")
	local px, py
	if pos then px, py = ns.Safe.XY(pos) end
	if ns.Safe.IsSecret(px) or ns.Safe.IsSecret(py) then px, py = nil, nil end
	bar.player.at:SetText(Coord(px, py))

	if sc:IsMouseOver() or mod.PadCursor() then
		local id, zx, zy = PlaceAt()
		local name = MapName(id)
		bar.cursor:SetText(name or "")
		bar.cursor.at:SetText(Coord(zx, zy))
		bar.cursor:GetParent():Show()
	else
		bar.cursor:GetParent():Hide()
	end
	-- a pill's width changes with its name only, never with the numbers (they sit in a box of their own)
	for _, fs in ipairs({ bar.player, bar.cursor }) do
		local w = math.floor(fs:GetStringWidth() + NUMBERS + 30.5)
		local pill = fs:GetParent()
		if pill.omWidth ~= w then pill.omWidth = w pill:SetWidth(w) end
	end
end

-- a label: black, a thin bronze edge; its name in gold, then its numbers in a box of their own
-- (right-aligned, a fixed width: moving the mouse changes the numbers, never the pill's size)
local function Pill(parent, label)
	local pill = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	pill:SetHeight(24)
	pill:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	pill:SetBackdropColor(0, 0, 0, 0.78)
	pill:SetBackdropBorderColor(0.55, 0.42, 0.25, 0.8)
	local fs = pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("LEFT", 10, 0)
	ns.Look:Font(fs, 12)
	fs:SetTextColor(1, 0.82, 0)
	fs:SetText(label or "")
	fs.at = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs.at:SetPoint("RIGHT", -10, 0)
	fs.at:SetWidth(NUMBERS)
	fs.at:SetJustifyH("RIGHT")
	ns.Look:Font(fs.at, 12)
	return pill, fs
end

-- the labels' place: the bottom-right corner, left of whatever Blizzard keeps there (the quest log's
-- button; Window.lua's, full screen)
local function PlaceCoords()
	if not bar then return end
	local right, bottom = sc:GetRight(), sc:GetBottom()
	local x = 8
	local frames = { mod.maxLogToggle }
	for _, f in ipairs(map.overlayFrames or {}) do frames[#frames + 1] = f end
	for _, f in ipairs(frames) do
		local fl, fb, fr = f:IsShown() and f:GetLeft(), f:GetBottom(), f:GetRight()
		if fl and right and fb and fr and bottom and right - fr < 40 and fb - bottom < 40 and fr - fl < 220 then
			x = math.max(x, right - fl + 6)
		end
	end
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", -x, 8)
end
mod.PlaceCoords = PlaceCoords

-- the labels' left edge (Panel.lua's favourites stop short of it), nil while they're hidden
function mod.CoordsLeft()
	if not bar or not bar:IsShown() then return end
	local left
	for _, pill in ipairs({ bar:GetChildren() }) do
		if pill:IsShown() and pill:GetLeft() then left = math.min(left or math.huge, pill:GetLeft()) end
	end
	return left
end

local function SetUpCoords()
	if not bar then
		bar = CreateFrame("Frame", nil, sc)
		bar:SetSize(1, 22)
		bar:SetFrameLevel(math.min(sc:GetFrameLevel() + 9000, 9900))   -- above every map pin
		-- (yours at the right, steady; the cursor's comes in to its left while over the map)
		local playerPill, cursorPill
		playerPill, bar.player = Pill(bar, PLAYER)
		playerPill:SetPoint("RIGHT")
		cursorPill, bar.cursor = Pill(bar)
		cursorPill:SetPoint("RIGHT", playerPill, "LEFT", -6, 0)
		bar:SetScript("OnUpdate", UpdateCoords)
		PlaceCoords()
		map:HookScript("OnShow", function() PlaceCoords() C_Timer.After(0, PlaceCoords) end)
		sc:HookScript("OnSizeChanged", PlaceCoords)
		if map.RefreshOverlayFrames then hooksecurefunc(map, "RefreshOverlayFrames", PlaceCoords) end
	end
	bar:SetShown(mod.db.coords)
	-- Blizzard's own coordinates (another addon may have turned them on) would double ours; ours off,
	-- the player's own setting for them comes back
	for _, name in ipairs(COORDS) do
		if mod.db.coords then HoldCVar(name, "0") else LetGoCVar(name) end
	end
end

--------------------------------------------------------------------------------
-- Zone levels on the hover label
--------------------------------------------------------------------------------

-- a level range in the game's quest colours for you: above you red / orange, yours orange, below you
-- green, grey (zones, dungeons: Dungeons.lua); as a colour code and the range
function mod.LevelColor(lo, hi)
	local level = ns.Safe.Value(UnitLevel("player")) or 1
	local color
	if level < lo then
		color = GetQuestDifficultyColor(lo)
	elseif level > hi then
		color = GetQuestDifficultyColor(hi - 2)   -- wholly below you goes grey/green, not yellow
	end
	color = color or QuestDifficultyColors and QuestDifficultyColors.difficult or { r = 1, g = 0.5, b = 0.25 }
	return ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255), lo == hi and tostring(hi) or (lo .. "-" .. hi)
end

-- (a client without a level list of its own, retail: the game's, as its own map's label shows them)
local function LevelText(mapID)
	if not mod.db.zoneLevels then return "" end
	local lv = ns.MapLevels and ns.MapLevels[mapID]
	if not ns.MapLevels and C_Map.GetMapLevels then
		local ok, lo, hi = pcall(C_Map.GetMapLevels, mapID)
		lo, hi = ok and ns.Safe.Value(lo), ok and ns.Safe.Value(hi)
		if lo and hi and lo > 0 and hi >= lo then lv = { lo, hi } end
	end
	if not lv or not lv[1] or not lv[2] then return "" end
	local code, range = mod.LevelColor(lv[1], lv[2])
	return (" %s(%s)|r"):format(code, range)
end

-- Fishing (the skill's name in the game's language) and the player's rank in it, looked up again
-- every few seconds at most (the hover label runs every frame); nil without Fishing
local FISHING_SPELL = 7620
local FISHING_SKILL = 356         -- (its skill line)
local fishing = { at = -10 }
local function FishingRank()
	local now = GetTime()
	if now - fishing.at < 3 then return fishing.name, fishing.rank end
	fishing.at, fishing.rank = now, nil
	-- (WoW Forever: the skill by its ID, C_SkillInfo; the older clients' skill lines by name else)
	local byID = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
	local ok, info = false, nil
	if byID then ok, info = pcall(byID, FISHING_SKILL) end
	if ok and type(info) == "table" and type(info.rank) == "number" and info.rank > 0 then
		fishing.name, fishing.rank = info.name, info.rank
		return fishing.name, fishing.rank
	end
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(FISHING_SPELL)
		or GetSpellInfo and GetSpellInfo(FISHING_SPELL)
	fishing.name = name
	if name and GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local skill, header, _, rank = GetSkillLineInfo(i)
			if not header and skill == name then fishing.rank = rank break end
		end
	end
	return fishing.name, fishing.rank
end

-- the zone's fishing, for a player with Fishing: the skill where every cast lands (ns.MapFishing:
-- base + 95), green from there, yellow from half of them, red below
local function FishingText(mapID)
	local base = mod.db.zoneLevels and ns.MapFishing and ns.MapFishing[mapID]
	if not base then return nil end
	local name, rank = FishingRank()
	if not name or not rank then return nil end
	local color = rank >= base + 95 and "ff40ff40" or rank >= base + 45 and "ffffd100" or "ffff4040"
	return ("|c%s%s %d|r"):format(color, name, math.max(1, base + 95))
end

-- replaces AreaLabelFrameMixin's OnUpdate: the place under the cursor, with its levels. The stitched
-- map is on the zone you're looking at, so that zone is the map's own: where the game names no
-- area in it, its own name (Blizzard's label showed none there: its title went missing, #25)
local function AreaLabelOnUpdate(self)
	self:ClearLabel(MAP_AREA_LABEL_TYPE.AREA_NAME)
	local m = self.dataProvider:GetMap()
	if m:IsCanvasMouseFocus() or mod.PadCursor() then
		local mapID = m:GetMapID()
		local id, _, _, x, y = PlaceAt()
		local name, fish
		if id ~= mapID and id ~= S.WORLD then
			name = MapName(id)
			if name then name, fish = name .. LevelText(id), FishingText(id) end
		elseif x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			name = MapUtil.FindBestAreaNameAtMouse(mapID, x, y)
			if not name and id == mapID and mod.IsStitched() then
				name = MapName(id)
				if name then name = name .. LevelText(id) end
			end
			if name and id == mapID then fish = FishingText(id) end
		end
		if name then self:SetLabel(MAP_AREA_LABEL_TYPE.AREA_NAME, name, fish) end
	end
	self:EvaluateLabels()
end

local function SetUpZoneLevels()
	if not labelProvider then
		for provider in pairs(map.dataProviders or {}) do
			if provider.Label and provider.Label.SetLabel then labelProvider = provider break end
		end
		if not labelProvider then return end
	end
	labelProvider.Label:SetScript("OnUpdate", AreaLabelOnUpdate)   -- (the levels only with zoneLevels: LevelText)
end

--------------------------------------------------------------------------------
-- Fading
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Questie's pins on the stitched map. HereBeDragons (Questie's copy) places a pin from
-- its world coordinates; on Forever that's only right on the world map, where Questie
-- converts it through the client's own map rectangles. On a zone or continent map (the
-- stitched map switches to the one you're looking at) it either drops the pin or puts it
-- in the wrong place, and it never shows a neighbouring zone's pins on a zone. So there,
-- every pin is placed (or moved) here, from the map it belongs to (`uiMapID`, `mapX`,
-- `mapY`) through the same rectangles, following Questie's own rules for where it may show.
--------------------------------------------------------------------------------

local SHOW_CURRENT = 0                  -- HBD_PINS_WORLDMAP_SHOW_CURRENT: only on its own map
local SHOW_CONTINENT = 2                -- HBD_PINS_WORLDMAP_SHOW_CONTINENT: on its continent's map too
local QUESTIE_BASE = 2015               -- the fixed frame level Questie's map icons and lines start from

-- Questie fixes its icons' frame levels from QUESTIE_BASE up (it expects Blizzard's map canvas
-- near 2000), which is under the stitched map's upper art layers: lift them above the art,
-- keeping their order among themselves (quest finishers in front ...)
-- (questie: Questie's own order kept, from QUESTIE_BASE; another copy's icon just over the art)
local function Lift(icon, questie)
	local top = S.artTop
	if not top or not icon.GetFrameLevel or not icon.SetFixedFrameLevel then return end
	local level = icon:GetFrameLevel()
	if level > top then return end
	icon:SetFixedFrameLevel(false)
	icon:SetFrameLevel(questie and level - QUESTIE_BASE + top + 1 or top + 1)
	icon:SetFixedFrameLevel(true)
end
local NEAR = 0.5                        -- how far round the map underneath (its widths) pins are placed (each pin
                                        --  on the map is laid out again on every frame of a pan or zoom: /openmap bench)
local VIEW_NEAR = 1.5                   -- ... and wherever the view is, out to this many times its half-size (zoomed
                                        --  out over a zone, its neighbours' quests too, not only the next zone's)

-- a world point (normalized) in the view, or near it
local function InView(wu, wv)
	if not mod.PinView then return false end
	local u, v, hu, hv = mod.PinView()
	if not u then return false end
	return math.abs(wu - u) <= hu * VIEW_NEAR and math.abs(wv - v) <= hv * VIEW_NEAR
end

-- Other addons' icons hidden while the map zooms (the menu's option, on by default): every pin on the
-- canvas is laid out again on each frame of a zoom, and with Questie's hundreds that costs the frame
-- rate; back as soon as the zoom stops (ZOOM_REST). Pins only: Blizzard's own icons stay
local ZOOM_REST = 0.15
local ZOOM_MOST = 1.5                   -- (never hidden longer than this at a time, zooming or not)
local FADE_OUT, FADE_IN = 0.12, 0.3     -- seconds they fade out as a zoom starts, and back in after it (not at once)
local pinTemplates = {}                 -- the pin templates of the copies set up (SetUpPins)
local zoomHid = {}                      -- pin -> { when it began fading out, its alpha then }: resting for a zoom
local fadingIn = {}                     -- pin -> when it began fading back in
local zoomAt, zoomFirst = 0, nil
local zoomWatch = CreateFrame("Frame")
zoomWatch:Hide()
zoomWatch:SetScript("OnUpdate", function(self)
	local now = GetTime()
	if now - zoomAt < ZOOM_REST and now - (zoomFirst or now) < ZOOM_MOST then
		-- resting: each fades out, then goes (hidden, it isn't laid out again on every frame)
		for pin, h in pairs(zoomHid) do
			if pin:IsShown() then
				local a = h[2] * (1 - (now - h[1]) / FADE_OUT)
				if a <= 0 then pin:Hide() pin:SetAlpha(1) h[3] = true else pin:SetAlpha(a) end
			end
		end
		return
	end
	if zoomFirst then
		zoomFirst = nil
		-- back, fading in (only the pins still on the map: one let go meanwhile is the pool's again, at
		-- full alpha for whoever takes it next)
		local back = {}
		for template in pairs(pinTemplates) do
			for pin in map:EnumeratePinsByTemplate(template) do
				if zoomHid[pin] then back[pin] = true end
			end
		end
		for pin, h in pairs(zoomHid) do
			if back[pin] and (h[3] or pin:IsShown()) then   -- (ours to bring back: one its addon hid stays so)
				fadingIn[pin] = now
				pin:SetAlpha(0)
				pin:Show()
			else
				pin:SetAlpha(1)
			end
		end
		wipe(zoomHid)
	end
	local any = false
	for pin, t in pairs(fadingIn) do
		local a = (now - t) / FADE_IN
		if a >= 1 or not pin:IsShown() then pin:SetAlpha(1) fadingIn[pin] = nil else pin:SetAlpha(a) any = true end
	end
	if not any then self:Hide() end
end)
local function OnZoomStep()
	if mod.db.zoomHidePins == false or not mod.IsStitched() or not map:IsShown() then return end
	-- (only the user's own zooming: a view put back, a map switch or the window laid out again rescale
	-- the canvas too, and some of those come over and over, which kept other addons' icons away)
	if not (mod.Zooming and mod.Zooming()) then return end
	local now = GetTime()
	zoomAt = now
	zoomFirst = zoomFirst or now
	if now - zoomFirst >= ZOOM_MOST then return end
	for template in pairs(pinTemplates) do
		for pin in map:EnumeratePinsByTemplate(template) do
			if pin:IsShown() and not zoomHid[pin] then
				zoomHid[pin] = { now, pin:GetAlpha() }   -- (from where it is: it may be fading in still)
				fadingIn[pin] = nil
			end
		end
	end
	zoomWatch:Show()
end

local questie = { placed = 0, ours = 0, moved = 0 }   -- for /openmap status: since the map last changed

-- The same for every addon's copy of HereBeDragons' pins (TomTom, gatherers, notes ... each may bring
-- its own): a pin placed from a map point (`uiMapID`, `mapX`, `mapY`: AddWorldMapIconMap) goes where it
-- belongs on the stitched map, a neighbouring zone's too. Questie's copy has its own pin template and
-- frame levels; the others use HereBeDragons' own template.
local PIN_LIBS = {
	["HereBeDragonsQuestie-Pins-2.0"] = { template = "HereBeDragonsPinsTemplateQuestie", questie = true },
	-- Zygor's renamed copy (#20); its waypoint lifted over the art, as Questie's icons are
	["HereBeDragons-Pins-ZGV"] = { template = "HereBeDragonsPinsTemplateZGV", lift = true },
}
local DEFAULT_TEMPLATE = "HereBeDragonsPinsTemplate"

-- Questie 12.8 and later: its copy is one of its own modules (QuestieLoader's HBDPins), not in LibStub,
-- with a template of its own (pins.worldmapPinTemplate); read from Questie's module list, so an older
-- Questie isn't given an empty one (ImportModule makes what it doesn't find)
local QUESTIE_MODULE = "Questie's HBDPins"
local function QuestieModule()
	local loader = _G.QuestieLoader
	local modules = type(loader) == "table" and rawget(loader, "_modules")
	local pins = type(modules) == "table" and rawget(modules, "HBDPins")
	if type(pins) == "table" and type(pins.worldmapProvider) == "table" then return pins end
end
mod.QuestieModule = QuestieModule   -- (PadView.lua's too)
mod.QUESTIE_MODULE = QUESTIE_MODULE

-- what a copy is: PIN_LIBS' entry, Questie's module's (its template its own), else HereBeDragons' own
local function PinSpec(name, pins)
	if name == QUESTIE_MODULE then
		local t = pins and pins.worldmapPinTemplate
		return { template = type(t) == "string" and t or "HereBeDragonsPins-Questie-WorldMapPin", questie = true }
	end
	return PIN_LIBS[name] or { template = DEFAULT_TEMPLATE }
end

-- the pin template a copy registered: its own, or (a copy whose template's name this doesn't know) the
-- one pool here that looks like HereBeDragons', Questie's or not as the copy is (PR #22, Ironship's)
local function PoolTemplate(spec)
	local pools = map.pinPools
	if not pools then return end
	if pools[spec.template] then return spec.template end
	local wantQuestie = spec.questie and true or false
	for template in pairs(pools) do
		if type(template) == "string" and template:find("HereBeDragons", 1, true)
			and (template:find("Questie", 1, true) ~= nil) == wantQuestie then
			return template
		end
	end
end

-- each copy's icons' map points as they were added: [pins] = { [icon] = { uiMapID, x, y } } (the
-- library keeps only an icon's world position and uiMapID; Questie's copy no mapX, mapY either).
-- Noted from the moment the copy is seen, before its pool is there to take it over: Questie draws
-- its icons at login, before the map first opens (#10)
local atOf = setmetatable({}, { __mode = "k" })
local function NoteAdds(pins)
	if atOf[pins] then return atOf[pins] end
	local at = setmetatable({}, { __mode = "k" })
	atOf[pins] = at
	-- (noted before the library places it: it may place the icon straight away)
	local add = pins.AddWorldMapIconMap
	if type(add) == "function" then
		pins.AddWorldMapIconMap = function(lib, ref, icon, uiMapID, x, y, ...)
			if icon and type(uiMapID) == "number" and type(x) == "number" and type(y) == "number" then at[icon] = { uiMapID, x, y } end
			return add(lib, ref, icon, uiMapID, x, y, ...)
		end
	end
	return at
end

-- Questie sets an icon's frame level again (QuestieMap.utils.SetDrawOrder: from QUESTIE_BASE) right after
-- handing it to the library, so after OpenMap lifted it: the icons placed sank under the art one by one as
-- Questie redrew them (Questie 12.8, #18). Lifted again each time, while on the map's pin
local function HookQuestieOrder()
	if questie.orderHooked then return end
	local loader = _G.QuestieLoader
	local modules = type(loader) == "table" and rawget(loader, "_modules")
	local qmap = type(modules) == "table" and rawget(modules, "QuestieMap")
	local utils = type(qmap) == "table" and qmap.utils
	if type(utils) ~= "table" or type(utils.SetDrawOrder) ~= "function" then return end
	questie.orderHooked = true
	hooksecurefunc(utils, "SetDrawOrder", function(frame)
		local pin = type(frame) == "table" and frame.GetParent and frame:GetParent()
		if pin and pin.icon == frame and pin.owningMap == map and mod.IsStitched() then Lift(frame, true) end
	end)
end

-- Questie's icons on the map's pins now, lifted over the art: those it placed before there was art to
-- lift them over (at login, before the map first opens: Questie 12.8 places them then, and redraws them
-- only when the map changes, so a map opened on the same zone kept them under the art until a continent
-- had been seen, #194), or while the map wasn't stitched
local function LiftQuestie()
	if not (questie.pins and S.artTop and mod.IsStitched() and map:IsShown()) then return end
	for pin in map:EnumeratePinsByTemplate(questie.template or "HereBeDragonsPinsTemplateQuestie") do
		local icon = pin.icon
		if icon and icon.GetParent and icon:GetParent() == pin then Lift(icon, true) end
	end
end
mod.LiftQuestie = LiftQuestie

-- a copy taken over: "done"; its pool not there yet: "waiting" (tried again, PinRetry); a copy of a
-- shape this can't take over: "unknown"
local function SetUpPins(name, pins)
	local spec = PinSpec(name, pins)
	local provider = pins and pins.worldmapProvider
	if type(provider) ~= "table" or type(provider.HandlePin) ~= "function" then return "unknown" end
	if provider.openmapPins then return "done" end
	local at = NoteAdds(pins)
	local template = PoolTemplate(spec)
	if not template then return "waiting" end
	provider.openmapPins = true
	pinTemplates[template] = true
	local count = spec.questie and questie or { placed = 0, ours = 0, moved = 0 }
	if spec.questie then questie.pins, questie.template = pins, template HookQuestieOrder() end
	local HandlePin = provider.HandlePin
	provider.HandlePin = function(self, icon, data, ...)
		-- (an older Questie's path stretch: not put on the stitched map at all, OpenMap draws the paths
		-- there, as Questie's would be out of place and size; DrawQuestiePaths)
		if spec.questie and icon.type == "line" and mod.IsStitched() then return end
		HandlePin(self, icon, data, ...)
		local holder = icon:GetParent()
		local placed = holder and holder.icon == icon and holder.SetPosition and holder
		if placed then count.placed = count.placed + 1 end
		if placed and (spec.questie or spec.lift) and mod.IsStitched() then Lift(icon, spec.questie) end
		if not mod.IsStitched() then return end
		local uiMapID, mx, my = data.uiMapID, data.mapX, data.mapY
		if not (mx and my) and at[icon] and at[icon][1] == uiMapID then uiMapID, mx, my = at[icon][1], at[icon][2], at[icon][3] end
		-- (a Questie icon added before anything noted it: Questie keeps its map point on the icon, in percent)
		if not (mx and my) and spec.questie and icon.UiMapID == uiMapID and type(icon.x) == "number" and type(icon.y) == "number" then
			mx, my = icon.x / 100, icon.y / 100
		end
		local mapID = self:GetMap():GetMapID()
		if mapID == S.WORLD and spec.questie then return end   -- (Questie's own Forever path: right there)
		local wu, wv
		if uiMapID and mx and my then
			local l, r, t, b = S.Rect(uiMapID)
			if not l then return end
			wu, wv = l + mx * (r - l), t + my * (b - t)
		elseif not uiMapID and type(data.instanceID) == "number" and type(data.x) == "number" and type(data.y) == "number" then
			-- placed by world position (AddWorldMapIconWorld: Zygor's waypoint, #20): the library's x, y are
			-- the game's world Y, X (HereBeDragons reads a map's corner as top, left)
			wu, wv = S.FromYards(data.instanceID, data.y, data.x)
			if not wu then return end
		else
			return
		end
		local x, y = mod.FromWorld(mapID, wu, wv)
		if placed then                                      -- placed, but from coordinates that are off here
			placed:SetPosition(x, y)
			count.moved = count.moved + 1
			return
		end
		if mapID == S.WORLD then return end                -- (on the whole world, only what the library itself shows)
		if uiMapID and (data.worldMapShowFlag or SHOW_CURRENT) == SHOW_CURRENT and uiMapID ~= mapID then return end
		local info = C_Map.GetMapInfo(mapID)
		if not info then return end
		-- (one placed by world position on a continent only as the library would: shown on continents)
		if not uiMapID and info.mapType == Enum.UIMapType.Continent and (data.worldMapShowFlag or SHOW_CURRENT) < SHOW_CONTINENT then return end
		local profile = spec.questie and _G.Questie and Questie.db and Questie.db.profile
		if profile and profile.hideIconsOnContinents and info.mapType == Enum.UIMapType.Continent then return end
		if (x < -NEAR or x > 1 + NEAR or y < -NEAR or y > 1 + NEAR) and not InView(wu, wv) then return end
		self:GetMap():AcquirePin(template, icon, x, y, data.frameLevelType)
		if spec.questie or spec.lift then Lift(icon, spec.questie) end
		count.ours = count.ours + 1
	end
	-- (counted afresh each time the map changes: HereBeDragons rebuilds its pins then)
	local Refresh = provider.RefreshAllData
	if type(Refresh) == "function" then        -- (a copy without it: nothing calls it, nothing to wrap)
		provider.RefreshAllData = function(self, ...)
			local before = self:GetMap() and self:GetMap():GetMapID()
			if before ~= count.mapID then count.placed, count.ours, count.moved, count.mapID = 0, 0, 0, before end
			local a, b, c = mod.TimeAfter(spec.questie and "Questie's icons placed" or "map pins placed", Refresh, self, ...)
			if spec.questie then LiftQuestie() end   -- (the ones it kept from before: not handled again)
			return a, b, c
		end
	end
	-- (taken over with the map open, after the library placed its icons the game's way: again, ours)
	if map:IsShown() and type(provider.RefreshAllData) == "function" then provider:RefreshAllData() end
	return "done"
end

-- one this can't take over keeps the game's own placement of its pins, and is said once (after a few
-- map opens, for one whose pool never comes), not passed over in silence
local OPEN_TRIES = 3
local pending, told = {}, {}    -- library name -> map opens tried; -> said
local function Tell(name)
	if told[name] then return end
	told[name] = true
	ns:Print(ns.L["A map addon brings its own HereBeDragons (%s), which OpenMap doesn't know: its pins keep the game's own placement."], name)
end

-- every copy of the pins library loaded so far (an addon loaded later: as it loads, or as the map opens).
-- opening: a map opening, counted for one whose pool never comes (OPEN_TRIES)
local function SetUpAllPins(opening)
	local function One(name, lib)
		local state = SetUpPins(name, lib)
		if state == "unknown" then
			Tell(name)
		elseif state == "waiting" then
			pending[name] = (pending[name] or 0) + (opening == true and 1 or 0)
			if pending[name] > OPEN_TRIES then Tell(name) end
		else
			pending[name] = nil
		end
	end
	if LibStub and LibStub.IterateLibraries then
		for name, lib in LibStub:IterateLibraries() do
			if type(name) == "string" and (name:match("^HereBeDragons.*%-Pins%-2%.0$") or PIN_LIBS[name]) then One(name, lib) end
		end
	end
	local q = QuestieModule()
	if q then One(QUESTIE_MODULE, q) end
end

-- a copy still waiting for its pool (Questie still setting up as the map first opened after a login,
-- #7): tried again every half second while the map is open, not only at the next opening
local PinRetry = CreateFrame("Frame")
PinRetry.at = 0
PinRetry:Hide()
PinRetry:SetScript("OnUpdate", function(self)
	local now = GetTime()
	if now - self.at < 0.5 then return end
	self.at = now
	if not map or not map:IsShown() or not next(pending) then self:Hide() return end
	mod.TimeAfter("pin libraries, again", SetUpAllPins)
end)
local function SetUpAllPinsAndWait()
	SetUpAllPins(true)
	if next(pending) then PinRetry.at = GetTime() PinRetry:Show() end
end

-- for /openmap status: Questie's pins, and how many are on the map now
function mod.QuestieStatus()
	if not questie.pins then return nil end
	local registered, shown = 0, 0
	for _ in pairs(questie.pins.worldmapPins or {}) do registered = registered + 1 end
	for _ in map:EnumeratePinsByTemplate(questie.template or "HereBeDragonsPinsTemplateQuestie") do shown = shown + 1 end
	return registered, shown, questie.placed, questie.ours, questie.moved
end

-- for /openmap status: Questie's icons by kind (its data's Type: available, complete, monster, item,
-- object ...), all it has and those on the map now, as "kind all/on map"
function mod.QuestieKinds()
	if not questie.pins then return nil end
	local all, on = {}, {}
	for icon in pairs(questie.pins.worldmapPins or {}) do
		local t = type(icon) == "table" and type(icon.data) == "table" and tostring(icon.data.Type or "?") or "?"
		all[t] = (all[t] or 0) + 1
	end
	for pin in map:EnumeratePinsByTemplate(questie.template or "HereBeDragonsPinsTemplateQuestie") do
		local icon = pin.icon
		local t = type(icon) == "table" and type(icon.data) == "table" and tostring(icon.data.Type or "?") or "?"
		on[t] = (on[t] or 0) + 1
	end
	local out = {}
	for t, n in pairs(all) do out[#out + 1] = ("%s %d/%d"):format(t, n, on[t] or 0) end
	table.sort(out)
	return table.concat(out, ", ")
end

-- for /openmap status: what became of Questie's icons on the map's pins (an icon placed, then gone):
-- pins with no icon, an icon taken off its pin (parented elsewhere), hidden, see-through, or under the art
function mod.QuestieLost()
	if not questie.pins then return nil end
	local n = { pins = 0, pinHidden = 0, noIcon = 0, offPin = 0, hidden = 0, faint = 0, under = 0, visible = 0,
		size = 0, scale = 0, pinScale = 0, level = 0 }
	local top = S.artTop or 0
	for pin in map:EnumeratePinsByTemplate(questie.template or "HereBeDragonsPinsTemplateQuestie") do
		n.pins = n.pins + 1
		local icon = pin.icon
		if not pin:IsShown() then n.pinHidden = n.pinHidden + 1 end
		if not icon then
			n.noIcon = n.noIcon + 1
		else
			if icon:GetParent() ~= pin then n.offPin = n.offPin + 1 end
			if not icon:IsShown() then n.hidden = n.hidden + 1 end
			if (icon:GetEffectiveAlpha() or 1) < 0.1 then n.faint = n.faint + 1 end
			if icon.GetFrameLevel and icon:GetFrameLevel() <= top then n.under = n.under + 1 end
			if icon:IsVisible() then n.visible = n.visible + 1 end
			-- (sizes on screen: the icon's width times its effective scale over UIParent's)
			n.size = n.size + (icon:GetWidth() or 0) * (icon:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
			n.scale = n.scale + (icon:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
			n.pinScale = n.pinScale + (pin:GetScale() or 1)
			n.level = math.max(n.level, icon:GetFrameLevel() or 0)
		end
	end
	return n
end

--------------------------------------------------------------------------------
-- Fading while you move
--------------------------------------------------------------------------------

local FADE_RATE = 6             -- the fade's approach, per second
local fader = CreateFrame("Frame")
fader:Hide()
local faded, ours = 1, false
local function SetFade(a)
	ours = true
	map:SetAlpha(a)
	ours = false
end
fader:SetScript("OnUpdate", function(_, elapsed)
	local moving = false
	if GetUnitSpeed then
		local speed = GetUnitSpeed("player")
		moving = not ns.Safe.IsSecret(speed) and (speed or 0) > 0
	end
	local want = (moving and not (map:IsMouseOver() or mod.PadCursor())) and 1 - (mod.db.moveFade or 0) or 1
	if math.abs(faded - want) < 0.005 then
		faded = want
	else
		faded = faded + (want - faded) * math.min(1, elapsed * FADE_RATE)
	end
	if math.abs(map:GetAlpha() - faded) > 0.001 then SetFade(faded) end
end)
-- Blizzard's own movement fader (PlayerMovementFrameFader) sets the map's alpha every frame while you move,
-- toward full (the game's fade is held off while ours runs): it faded for a moment, then came back. Ours is
-- put straight back over it
local function KeepFade(self, a)
	if ours or not fader:IsShown() or math.abs((a or 1) - faded) <= 0.001 then return end
	SetFade(faded)
end

-- the frame rate capped while the map shows (Map frame rate cap): a big map is many layers over the
-- whole screen, every frame, and a still map needn't be drawn 120 times a second. The game's own
-- maxFPS is held then (lower already: left as it is), and put back as the map goes and at logout.
-- (Not set in combat: what the game blocks then isn't worth the risk)
local function ApplyFpsCap()
	if not map or loggingOut then return end
	local cap = mod.db.mapFpsCap or 0
	if map:IsShown() and cap > 0 then
		if InCombatLockdown() then return end
		local ok, now = pcall(GetCVar, "maxFPS")
		now = ok and tonumber(now) or 0
		if Kept().maxFPS ~= nil or now == 0 or now > cap then HoldCVar("maxFPS", tostring(cap)) end
	else
		LetGoCVar("maxFPS")
	end
end

local function ApplyExtras()
	if not map or loggingOut then return end
	ApplyFpsCap()
	SetUpCoords()
	SetUpZoneLevels()
	-- (from the old on / off setting: fading back on was the game's half-fade)
	if mod.db.noFade ~= nil then
		if mod.db.noFade == false and (mod.db.moveFade or 0) == 0 then mod.db.moveFade = 0.5 end
		mod.db.noFade = nil
	end
	-- the game's own fade off while ours runs (the player's setting kept, and put back at logout)
	HoldCVar("mapFade", "0")
	fader:SetShown(map:IsShown() and (mod.db.moveFade or 0) > 0)
	if (mod.db.moveFade or 0) == 0 then map:SetAlpha(1) end
end

--------------------------------------------------------------------------------
-- Keep the map's art warm: the game lets go of the files of a map that's closed, and every opening
-- read them again (blank parchment, the minimap fading in, a moment each time). As the map closes,
-- each file shown on it is drawn on a frame that stays shown, a pixel across at almost no alpha, out
-- of sight, till the map opens again (/openmap warm turns it off and on)
--------------------------------------------------------------------------------

local WARM_MOST = 1200          -- files kept at the most (the view's: a few hundred)
local warmFrame, warmTex, warmN = nil, {}, 0
local function WarmCollect(f, files, seen)
	for _, r in ipairs({ f:GetRegions() }) do
		if #files >= WARM_MOST then return end
		if r:IsObjectType("Texture") and r:IsShown() and (r:GetAlpha() or 0) > 0 then
			local file = r:GetTexture()
			if file and not seen[file] then seen[file] = true files[#files + 1] = file end
		end
	end
	for _, c in ipairs({ f:GetChildren() }) do
		if #files >= WARM_MOST then return end
		if c:IsShown() and (c:GetAlpha() or 0) > 0 then WarmCollect(c, files, seen) end
	end
end
local function WarmHold()
	if mod.db.keepWarm == false or not ns.MapStitch.IsBuilt() then return end
	local root = ns.MapStitch.Root()
	if not root then return end
	local files = {}
	local ok, err = pcall(WarmCollect, root, files, {})
	if not ok then geterrorhandler()(err) return end
	if not warmFrame then
		warmFrame = CreateFrame("Frame")
		warmFrame:SetFrameStrata("BACKGROUND")
		warmFrame:SetSize(1, 1)
		warmFrame:SetPoint("BOTTOMLEFT", 0, 0)
	end
	for i, file in ipairs(files) do
		local t = warmTex[i]
		if not t then
			t = warmFrame:CreateTexture(nil, "BACKGROUND")
			t:SetAllPoints(warmFrame)
			t:SetAlpha(0.01)
			-- (drawn, so the file stays loaded, but added as black: hundreds stacked on one pixel
			-- showed as a white dot in the screen's corner, #45)
			t:SetBlendMode("ADD")
			t:SetVertexColor(0, 0, 0)
			warmTex[i] = t
		end
		t:SetTexture(file)
		t:Show()
	end
	for i = #files + 1, warmN do warmTex[i]:SetTexture(nil) warmTex[i]:Hide() end
	warmN = #files
	warmFrame:Show()
end
-- Let go a few files a frame (WARM_STEP), from a moment into the opening (the map's own textures
-- drawn by then, holding the files themselves): all in one frame, the game unloaded the rest at once,
-- a stall of about a second each time the map opened. The map closing stops it (WarmHold holds again)
local WARM_STEP = 15            -- files let go a frame: 1,200 over about 1.5 s
local warmRelease = CreateFrame("Frame")
warmRelease:Hide()
warmRelease:SetScript("OnUpdate", function(self)
	if not map:IsShown() or not warmFrame then self:Hide() return end
	mod.TimeAfter("warm art let go (a frame's worth)", function()
		for _ = 1, WARM_STEP do
			if warmN == 0 then break end
			warmTex[warmN]:SetTexture(nil)
			warmTex[warmN]:Hide()
			warmN = warmN - 1
		end
	end)
	if warmN == 0 then warmFrame:Hide() self:Hide() end
end)
local function WarmLetGo()
	if not warmFrame then return end
	warmRelease:Hide()
	C_Timer.After(1, function()
		if map:IsShown() and warmFrame then warmRelease:Show() end
	end)
end
local function WarmStop() warmRelease:Hide() end
function mod:ToggleWarm()
	mod.db.keepWarm = mod.db.keepWarm == false
	if not mod.db.keepWarm and warmFrame then
		warmRelease:Hide()
		for i = 1, warmN do warmTex[i]:SetTexture(nil) warmTex[i]:Hide() end
		warmN = 0
		warmFrame:Hide()
	end
	if mod.HoldDungeonHere then mod.HoldDungeonHere() end   -- (the dungeon you're in: Dungeons.lua)
	ns:Print(("Keep the map's art warm: %s"):format(mod.db.keepWarm and "on" or "off"))
end

--------------------------------------------------------------------------------
-- Questie's mob paths (its WaypointMap, since Questie 12.2): Questie draws them on the map's canvas
-- itself, only on the path's own zone map and scaled to that map's size, under OpenMap's art (its
-- fixed frame level). On the stitched map they're drawn here instead, each through its zone's
-- rectangle, over the art, in Questie's colours, as Questie picks them (a route once: its
-- highlighted copy, else its most visible), redrawn whenever Questie redraws its own
--------------------------------------------------------------------------------

local QPATH = { width = 2.5, zones = {}, key = "", dirty = true, at = 0 }   -- set: OpenMap's pin set for them
local QPATH_MOST_ZONES = 4      -- drawn only zoomed in this far: no more zones than this in view (Questie draws one)
local QPATH_EVERY = 0.5         -- seconds between redraws at the most (Questie changes its icons in bursts)
local function QuestiePaths()
	local Q = _G.QuestieLoader
	if type(Q) ~= "table" or type(Q.ImportModule) ~= "function" then return end
	local ok, W = pcall(Q.ImportModule, Q, "QuestieWaypoints")
	if not ok or type(W) ~= "table" or type(W.paths) ~= "table" or type(W.WorldMapAlpha) ~= "function" then return end
	return W
end
-- the zones near the view (S.Rect over the view, a little round it): a path is drawn only in one of these
local function QuestieZonesNear(u, v, hu, hv)
	local zones, n = QPATH.zones, 0
	wipe(zones)
	local l0, r0, t0, b0 = u - hu * 1.2, u + hu * 1.2, v - hv * 1.2, v + hv * 1.2
	local seen = QPATH.seenZones or {}
	for uiMapID in pairs(seen) do
		local l, r, t, b = S.Rect(uiMapID)
		if l and r > l0 and l < r0 and b > t0 and t < b0 then zones[uiMapID] = true n = n + 1 end
	end
	return n
end
local function DrawQuestiePaths()
	local W = QuestiePaths()
	if not (W or QPATH.lines) or not S.IsBuilt() then return end
	QPATH.set = QPATH.set or S.PinSet("questiepaths", 0, 1)
	S.ClearPinSet(QPATH.set)
	QPATH.dirty, QPATH.at = false, GetTime()
	if not (mod.IsStitched() or (mod.PadViewOn and mod.PadViewOn())) or not QPATH.near then return end
	local zones = QPATH.zones
	if W then
		local routes = {}
		for path in pairs(W.paths) do
			if path.uiMapId and zones[path.uiMapId] and type(path.points) == "table" then
				local okA, alpha = pcall(W.WorldMapAlpha, path)
				if okA and alpha then
					local rank = alpha + ((W.IsHighlighted and W.IsHighlighted(path)) and 2 or 0)
					local key = path.route or path
					if not routes[key] or rank > routes[key].rank then routes[key] = { path = path, alpha = alpha, rank = rank } end
				end
			end
		end
		for _, shown in pairs(routes) do
			local path = shown.path
			local l, r, t, b = S.Rect(path.uiMapId)
			local okC, c = pcall(W.Color, path)
			c = okC and type(c) == "table" and c or { 1, 0.8, 0, 1 }
			local pts = {}
			for _, p in ipairs(path.points) do
				if type(p.x) == "number" and type(p.y) == "number" then
					pts[#pts + 1] = l + p.x / 100 * (r - l)
					pts[#pts + 1] = t + p.y / 100 * (b - t)
				end
			end
			if #pts >= 4 then S.AddPath(QPATH.set, pts, QPATH.width, c[1], c[2], c[3], (c[4] or 1) * shown.alpha) end
		end
		return
	end
	for f, d in pairs(QPATH.lines) do
		local icon = f.iconFrame
		if d.map and zones[d.map] and icon and not f.hidden and not icon.hidden then
			local l, r, t, b = S.Rect(d.map)
			local c = type(d[5]) == "table" and d[5] or { 1, 0.8, 0, 1 }
			local u1, v1 = l + d[1] / 100 * (r - l), t + d[2] / 100 * (b - t)
			local u2, v2 = l + d[3] / 100 * (r - l), t + d[4] / 100 * (b - t)
			S.AddLine(QPATH.set, u1, v1, u2, v2, QPATH.width, c[1], c[2], c[3], c[4] or 1)
		end
	end
end
mod.DrawQuestiePaths = function() QPATH.dirty = true end   -- (stitched or not: Compat.lua; drawn on the next tick)
-- a zone a path is in, known to the culling
local function SeenZone(uiMapID)
	QPATH.seenZones = QPATH.seenZones or {}
	if uiMapID and not QPATH.seenZones[uiMapID] then QPATH.seenZones[uiMapID] = true QPATH.moved = true end
end
-- Questie before 12.2 draws each stretch of a path as a frame of its own (QuestieFramePool:CreateLine),
-- sized in pixels for Blizzard's map of its zone and pinned there by its middle: its ends are kept here
-- as it's made, to be drawn through the zone's rectangle like the newer paths
local function HookOldQuestieLines(Q)
	local ok, FP = pcall(Q.ImportModule, Q, "QuestieFramePool")
	if not ok or type(FP) ~= "table" or type(FP.CreateLine) ~= "function" then return end
	local okZ, zdb = pcall(Q.ImportModule, Q, "ZoneDB")
	zdb = okZ and type(zdb) == "table" and type(zdb.GetUiMapIdByAreaId) == "function" and zdb or nil
	QPATH.lines = setmetatable({}, { __mode = "k" })
	local create = FP.CreateLine
	FP.CreateLine = function(self, iconFrame, sx, sy, ex, ey, width, color, areaId, ...)
		local f = create(self, iconFrame, sx, sy, ex, ey, width, color, areaId, ...)
		if type(f) == "table" and type(sx) == "number" and type(ey) == "number" and zdb then
			local area = areaId or (iconFrame and iconFrame.AreaID)
			local okM, uiMapID = pcall(zdb.GetUiMapIdByAreaId, zdb, area)
			local d = { sx, sy, ex, ey, color, map = okM and S.Rect(uiMapID or 0) and uiMapID or nil }
			QPATH.lines[f] = d
			SeenZone(d.map)
			if d.map and QPATH.zones[d.map] then QPATH.dirty = true end
		end
		return f
	end
	return true
end
local function HookQuestiePaths()
	if QPATH.hooked then return end
	local Q = _G.QuestieLoader
	if type(Q) ~= "table" or type(Q.ImportModule) ~= "function" then return end
	if QuestiePaths() then
		local ok, M = pcall(Q.ImportModule, Q, "WaypointMap")
		if not ok or type(M) ~= "table" or type(M.Invalidate) ~= "function" then return end
		QPATH.hooked = true
		hooksecurefunc(M, "Invalidate", function() QPATH.dirty = true end)
	elseif HookOldQuestieLines(Q) then
		QPATH.hooked = true
	end
end
-- each pan / zoom only notes the view: which zones are near is worked out, and the paths redrawn,
-- once the map has stopped (QPATH_SETTLE), not on every frame of a zoom. A light tick while the map
-- is open draws what changed, at most every QPATH_EVERY, and everything again every QPATH_REFRESH
-- while it's still (an icon Questie hid without saying: gone by then)
local QPATH_SETTLE = 0.2        -- seconds the view is still before the paths are looked at again
local QPATH_REFRESH = 5
QPATH.view, QPATH.movedAt, QPATH.spare = {}, -10, {}
tinsert(S.viewHooks, function(u, v, hu, hv)
	if not QPATH.hooked then return end
	local w = QPATH.view
	w[1], w[2], w[3], w[4] = u, v, hu, hv
	QPATH.moved, QPATH.movedAt = true, GetTime()
end)
-- the zones near the view now: a different set (or near / far) redraws
local function QuestieNearNow()
	local w = QPATH.view
	if not w[1] then return end
	local W = QuestiePaths()
	if W then                                       -- (the newer paths: their zones as they come)
		for path in pairs(W.paths) do SeenZone(path.uiMapId) end
	end
	QPATH.moved = false
	local was = QPATH.zones
	QPATH.zones, QPATH.spare = QPATH.spare, was
	local n = QuestieZonesNear(w[1], w[2], w[3], w[4])
	local near = n > 0 and n <= QPATH_MOST_ZONES
	local same = near == QPATH.near and n == (QPATH.count or -1)
	if same and near then
		for id in pairs(QPATH.zones) do
			if not was[id] then same = false break end
		end
	end
	QPATH.count = n
	if not same then QPATH.near, QPATH.dirty = near, true end
end
QPATH.tick = CreateFrame("Frame")
QPATH.tick:Hide()
QPATH.tick:SetScript("OnUpdate", function()
	local now = GetTime()
	if now - QPATH.movedAt < QPATH_SETTLE or (mod.Zooming and mod.Zooming()) then return end
	if QPATH.moved then mod.TimeAfter("Questie paths, zones near", QuestieNearNow) end
	if now - QPATH.at < QPATH_EVERY then return end
	if QPATH.dirty or now - QPATH.at > QPATH_REFRESH then mod.TimeAfter("Questie paths drawn", DrawQuestiePaths) end
end)

-- for PadView.lua: the paths drawn on its view while it shows (it has no SetupExtras: nothing of
-- Blizzard's map hooked)
function mod.PadQuestiePaths(on)
	if on then
		HookQuestiePaths()
		if QPATH.hooked then QPATH.dirty = true QPATH.tick:Show() end
	else
		QPATH.tick:Hide()
	end
end

function mod:SetupExtras(worldMap)
	map, sc = worldMap, worldMap.ScrollContainer
	map:HookScript("OnShow", function() fader:SetShown((mod.db.moveFade or 0) > 0) ApplyFpsCap() end)
	map:HookScript("OnHide", function() fader:Hide() faded = 1 SetFade(1) ApplyFpsCap() end)
	map:HookScript("OnHide", function() WarmStop() mod.TimeClose("warm art held", WarmHold) end)
	map:HookScript("OnShow", WarmLetGo)
	hooksecurefunc(map, "SetAlpha", KeepFade)
	SetUpAllPins()
	map:HookScript("OnShow", function() mod.TimeAfter("pin libraries", SetUpAllPinsAndWait) end)
	-- (Questie's icons placed before the map's art was built, or while it was closed: lifted once it's laid out)
	map:HookScript("OnShow", function() C_Timer.After(0, LiftQuestie) C_Timer.After(0.5, LiftQuestie) end)     -- (a copy an addon loaded since brought)
	ns.RegisterEvent(PinRetry, "ADDON_LOADED", function() SetUpAllPins() end)
	HookQuestiePaths()                               -- (now: an older Questie's path stretches are kept as they're made)
	map:HookScript("OnShow", function() HookQuestiePaths() if QPATH.hooked then QPATH.dirty = true QPATH.tick:Show() end end)
	map:HookScript("OnHide", function() QPATH.tick:Hide() end)
	if type(map.OnCanvasScaleChanged) == "function" then hooksecurefunc(map, "OnCanvasScaleChanged", OnZoomStep) end
	ApplyExtras()
	-- (before the game saves its settings: the player's own back; Compat.lua's reassertion stands down)
	ns.RegisterEvent(cvarOwner, "PLAYER_LOGOUT", function()
		loggingOut = true
		for name in pairs(Kept()) do LetGoCVar(name) end
	end)
end

mod.RefreshExtras = ApplyExtras

function mod:ExtraOptions(opts, get, set, off)
	local function setApply(info, v) set(info, v) ApplyExtras() end
	opts.extrasHeader = ns.Header(ns.L["On the map"], 40)
	opts.coords = { type = "toggle", name = ns.L["Coordinates"], order = 41, get = get, set = setApply, disabled = off,
		desc = ns.L["A bar along the map's foot: your position, and the zone and position under the cursor."] }
	opts.zoneLevels = { type = "toggle", name = ns.L["Zone levels"], order = 42, get = get, set = setApply, disabled = off,
		desc = ns.L["Hovering a zone shows its level range, coloured for your level, and if you know Fishing, the skill at which every cast there lands."] }
	opts.zoomHidePins = { type = "toggle", name = ns.L["Other addons' icons rest while zooming"], order = 43, width = "full",
		get = get, set = set, disabled = off,
		desc = ns.L["Questie's icons (and other addons' map icons) are hidden while the map zooms and back as soon as it stops. Each one is laid out again on every frame of a zoom, and with Questie's hundreds that costs a lot of frame rate."] }
	opts.mapFpsCap = { type = "range", name = ns.L["Map frame rate cap"], order = 44.5, min = 0, max = 144, step = 6,
		get = get, set = setApply, disabled = off,
		desc = ns.L["The frame rate at most while the map is open (0: off). A big map draws many layers over the whole screen every frame; 60 halves the graphics card's work at 120 fps, for a smooth enough map. The game's own frame rate setting comes back as the map closes."] }
	opts.moveFade = { type = "range", name = ns.L["Fade while moving"], order = 44, min = 0, max = 0.9, step = 0.05, isPercent = true,
		get = get, set = setApply, disabled = off,
		desc = ns.L["How much the map fades while you walk or ride, so you can see where you're going. 0% keeps it solid. It never fades while the mouse is over it."] }
end
