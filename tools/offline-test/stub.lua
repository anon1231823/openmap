-- Minimal WoW API stub for OpenMap's offline load tests (tools/offline-test/run.py).
-- Unknown globals resolve to "magic" proxies: indexable, callable (returning
-- nil), so Blizzard frames and APIs the client has behave as no-ops.

ERRORS = {}
LOG = {}
local function record(err)
	ERRORS[#ERRORS + 1] = tostring(err) .. "\n" .. debug.traceback("", 2)
end

local magicMT = {}
local function Magic(name)
	return setmetatable({ __magic = name }, magicMT)
end
magicMT.__index = function(t, k)
	if k == "__magic" then return nil end
	local m = Magic((rawget(t, "__magic") or "?") .. "." .. tostring(k))
	rawset(t, k, m)
	return m
end
-- obj:Method() on a proxy returns a proxy (frames chain); plain calls return nil
magicMT.__call = function(self, first)
	if type(first) == "table" and getmetatable(first) == magicMT then
		return Magic((rawget(self, "__magic") or "?") .. "()")
	end
	return nil
end

setmetatable(_G, { __index = function(t, k)
	-- names that must stay nil so feature checks behave like a client without them
	if NIL_GLOBALS[k] then return nil end
	-- Blizzard frames by name: real mock frames
	if type(k) == "string" and (k:match("Frame%d*$") or k:match("Bar%d*$") or k:match("Button%d*$") or k:match("Tooltip%d*$")
		or k:match("Cluster$") or k:match("Container$") or k:match("^Minimap") or k:match("^ChatFrame%d") or k:match("^MultiBar")
		or k:match("Manager$") or k:match("Tab$")) and CreateFrame then
		local f = CreateFrame("Frame", k, UIParent)
		rawset(f, "__blizz", true)
		return f
	end
	-- Blizzard's global strings: nil keeps `X or "fallback"` honest
	if type(k) == "string" and k:match("^[A-Z0-9_]+$") then return nil end
	local m = Magic(k)
	rawset(t, k, m)
	return m
end })

NIL_GLOBALS = {
	issecretvalue = true, canaccessvalue = true, canaccessallvalues = true, hasanysecretvalues = true,
	LibStub = true, OpenMapDB = true, OpenMapCharDB = true, ChatFrameUtil = true,
}

-- Lua / WoW utility globals -----------------------------------------------
strtrim = function(s, chars) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strsplit = function(sep, s, n)
	local out, pattern = {}, "([^" .. sep .. "]*)"
	for piece in (s .. sep):gmatch(pattern .. sep) do out[#out + 1] = piece end
	return unpack(out)
end
strjoin = function(sep, ...) return table.concat({ ... }, sep) end
strmatch, strfind, strsub, strlen, strlower, strupper, strrep, strbyte, strchar = string.match, string.find, string.sub, string.len, string.lower, string.upper, string.rep, string.byte, string.char
gsub, format, tinsert, tremove, sort, floor, ceil, abs, max, min = string.gsub, string.format, table.insert, table.remove, table.sort, math.floor, math.ceil, math.abs, math.max, math.min
mod = math.fmod
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tContains = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
tIndexOf = function(t, v) for i, x in ipairs(t) do if x == v then return i end end end
CopyTable = function(t, seen)
	local out = {}
	for k, v in pairs(t) do out[k] = type(v) == "table" and CopyTable(v) or v end
	return out
end
Mixin = function(o, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end return o end
CreateFromMixins = function(...) return Mixin({}, ...) end
geterrorhandler = function() return record end
seterrorhandler = function() end
securecall = function(fn, ...) if type(fn) == "string" then fn = _G[fn] end return pcall(fn, ...) end
issecure = function() return false end
debugstack = function() return debug.traceback() end
debugprofilestop = function() return os.clock() * 1000 end
print = function(...) LOG[#LOG + 1] = table.concat({ tostringall(...) }, " ") end
tostringall = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end return unpack(t) end
date = os.date
time = os.time
GetTime = function() return NOW end
NOW = 1000
GetServerTime = os.time
InCombatLockdown = function() return IN_COMBAT end
IN_COMBAT = false
GetLocale = function() return "enUS" end
GetCurrentRegion = function() return 1 end
GetRealmName = function() return "Forever" end
UnitName = function(u) if u == "player" then return "Tester" end end
UnitClass = function(u) return "Warrior", "WARRIOR", 1 end
UnitRace = function() return "Human", "Human" end
UnitFactionGroup = function() return "Alliance", "Alliance" end
UnitGUID = function(u) if u == "player" then return "Player-1-0001" end end
UnitLevel = function() return 25 end
UnitExists = function(u) return u == "player" end
UnitHealth = function() return 500 end
UnitHealthMax = function() return 800 end
UnitIsDeadOrGhost = function() return false end
UnitAffectingCombat = function() return IN_COMBAT end
IsInGroup = function() return false end
IsInInstance = function() return false, "none" end
IsMounted = function() return false end
IsResting = function() return false end
UnitOnTaxi = function() return false end
GetCVar = function() return "0" end
GetCVarBool = function() return false end
SetCVar = function() end
GetBindingKey = function() return nil end
GetNumGroupMembers = function() return 0 end
GetFramerate = function() return 60 end
GetScreenWidth = function() return 1920 end
GetScreenHeight = function() return 1080 end
IsShiftKeyDown = function() return false end
IsAltKeyDown = function() return false end
IsControlKeyDown = function() return false end
UnitIsPlayer = function() return false end
UnitReaction = function() return 4 end
GetAddOnMetadata = function() return "0.1.0" end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UNIT_NAME_FONT = STANDARD_TEXT_FONT
DAMAGE_TEXT_FONT = STANDARD_TEXT_FONT
NUM_CHAT_WINDOWS = 10
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" } }
setmetatable(RAID_CLASS_COLORS, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
Enum = setmetatable({}, { __index = function(t, k) local m = Magic("Enum." .. k) rawset(t, k, m) return m end })
C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end, IsAddOnLoaded = function() return false end, LoadAddOn = function() end }
C_Timer = {}
TIMERS = {}
C_Timer.After = function(d, fn) TIMERS[#TIMERS + 1] = { at = NOW + (d or 0), fn = fn } end
C_Timer.NewTimer = function(d, fn)
	local t = { at = NOW + d, fn = fn }
	t.Cancel = function() t.cancelled = true end
	t.IsCancelled = function() return t.cancelled end
	TIMERS[#TIMERS + 1] = t
	return t
end
C_Timer.NewTicker = function(d, fn, n)
	local t = { at = NOW + d, fn = fn, every = d, n = n }
	t.Cancel = function() t.cancelled = true end
	t.IsCancelled = function() return t.cancelled end
	TIMERS[#TIMERS + 1] = t
	return t
end

function RunTimers(seconds)
	local stop = NOW + seconds
	while true do
		local nextT
		for _, t in ipairs(TIMERS) do
			if not t.cancelled and not t.done and (not nextT or t.at < nextT.at) then nextT = t end
		end
		if not nextT or nextT.at > stop then break end
		NOW = math.max(NOW, nextT.at)
		local ok, err = pcall(nextT.fn, nextT)
		if not ok then record("timer: " .. tostring(err)) end
		if nextT.every and not nextT.cancelled then
			nextT.at = NOW + nextT.every
			if nextT.n then nextT.n = nextT.n - 1 if nextT.n <= 0 then nextT.done = true end end
		else
			nextT.done = true
		end
	end
	NOW = stop
	RunOnUpdate(0.016)
end

-- hooks ----------------------------------------------------------------------
hooksecurefunc = function(a, b, c)
	local tbl, name, fn = a, b, c
	if type(a) == "string" then tbl, name, fn = _G, a, b end
	local orig = tbl[name]
	if orig == nil then error("hooksecurefunc: " .. tostring(name) .. " does not exist", 2) end
	rawset(tbl, name, function(...) local r = { orig(...) } pcall(fn, ...) return unpack(r) end)
end

-- frames ---------------------------------------------------------------------
FRAMES = {}
local ONUPDATE = {}

local regionMT = {}
local function NewRegion(kind, name, parent)
	local r = setmetatable({ __kind = kind, __scripts = {}, __events = {}, __shown = true, __alpha = 1,
		__w = 32, __h = 32, __parent = parent, __children = {}, __points = {} }, regionMT)
	if name then _G[name] = r r.__name = name end
	if parent and type(parent) == "table" and rawget(parent, "__children") then
		table.insert(parent.__children, r)
	end
	FRAMES[#FRAMES + 1] = r
	return r
end

local M = {}
NOOP = function() return nil end
VERBS = { "Set", "Get", "Is", "Can", "Has", "Clear", "Enable", "Disable", "Register", "Unregister", "Create", "Show", "Hide",
	"Start", "Stop", "Play", "Add", "Remove", "Update", "Lock", "Unlock", "Raise", "Lower", "Adjust", "Release", "Acquire",
	"Refresh", "Reset", "Toggle", "Click", "Save", "Load", "Restore", "Notify", "Insert", "Apply", "Init" }
regionMT.__index = function(t, k)
	if M[k] then return M[k] end
	if type(k) == "string" and k:match("^Get.*Texture$") then
		return function(self)
			local key = "__" .. k
			if not rawget(self, key) then rawset(self, key, NewRegion("Texture", nil, self)) end
			return rawget(self, key)
		end
	end
	if type(k) ~= "string" then return nil end
	-- unknown widget methods (verb-prefixed) are no-ops
	for _, verb in ipairs(VERBS) do
		local nxt = k:sub(#verb + 1, #verb + 1)
		if k:sub(1, #verb) == verb and (nxt == "" or nxt:match("[A-Z]")) then
			return NOOP
		end
	end
	-- a Blizzard frame's unknown sub-object (MinimapCluster.Tracking...): a child mock frame
	if rawget(t, "__blizz") and k:match("^[A-Z]") then
		local child = NewRegion("Frame", nil, t)
		rawset(child, "__blizz", true)
		rawset(t, k, child)
		return child
	end
	return nil
end

function M:GetName() return self.__name end
function M:GetObjectType() return self.__kind end
function M:IsObjectType(k) return self.__kind == k end
function M:GetParent() return self.__parent end
function M:SetParent(p) self.__parent = p end
function M:SetScript(s, fn) self.__scripts[s] = fn if s == "OnUpdate" then ONUPDATE[self] = fn end end
function M:GetScript(s) return self.__scripts[s] end
function M:HookScript(s, fn)
	local old = self.__scripts[s]
	self.__scripts[s] = old and function(...) old(...) fn(...) end or fn
	if s == "OnUpdate" then ONUPDATE[self] = self.__scripts[s] end
end
function M:HasScript() return true end
function M:RegisterEvent(e) self.__events[e] = true end
function M:RegisterUnitEvent(e) self.__events[e] = true end
function M:UnregisterEvent(e) self.__events[e] = nil end
function M:UnregisterAllEvents() self.__events = {} end
function M:IsEventRegistered(e) return self.__events[e] or false end
function M:Show() self.__shown = true local f = self.__scripts.OnShow if f then f(self) end end
function M:Hide() self.__shown = false local f = self.__scripts.OnHide if f then f(self) end end
function M:SetShown(v) if v then self:Show() else self:Hide() end end
function M:IsShown() return self.__shown end
function M:IsVisible() return self.__shown end
function M:SetAlpha(a) self.__alpha = a end
function M:GetAlpha() return self.__alpha end
function M:GetEffectiveAlpha() return self.__alpha end
function M:SetSize(w, h) self.__w, self.__h = w, h end
function M:SetWidth(w) self.__w = w end
function M:SetHeight(h) self.__h = h end
function M:GetWidth() return self.__w end
function M:GetHeight() return self.__h end
function M:GetVerticalScroll() return self.__vscroll or 0 end   -- (a scroll frame's: the menu's list, Panel.lua)
function M:SetVerticalScroll(v) self.__vscroll = v end
function M:GetSize() return self.__w, self.__h end
function M:GetRect() return 0, 0, self.__w, self.__h end
function M:GetLeft() return 0 end
function M:GetRight() return self.__w end
function M:GetTop() return self.__h end
function M:GetBottom() return 0 end
function M:GetCenter() return 100, 100 end
function M:GetScale() return 1 end
function M:GetEffectiveScale() return 1 end
function M:GetFrameLevel() return self.__level or 1 end
function M:SetFrameLevel(l) self.__level = l end
function M:GetFrameStrata() return "MEDIUM" end
function M:SetPoint(...) table.insert(self.__points, { ... }) end
function M:ClearAllPoints() self.__points = {} end
function M:GetNumPoints() return #self.__points end
function M:GetPoint(i) local p = self.__points[i or 1] if p then return unpack(p) end end
function M:GetChildren() return unpack(self.__children) end
function M:GetNumChildren() return #self.__children end
function M:GetRegions() return end
function M:IsMouseOver() return false end
function M:IsMouseEnabled() return false end
function M:IsProtected() return false end
function M:IsForbidden() return false end
function M:CanChangeProtectedState() return true end
function M:GetAttribute(k) return self.__attr and self.__attr[k] end
function M:SetAttribute(k, v) self.__attr = self.__attr or {} self.__attr[k] = v end
function M:CreateTexture(name) return NewRegion("Texture", name, self) end
function M:CreateMaskTexture(name) return NewRegion("MaskTexture", name, self) end
function M:CreateLine(name) return NewRegion("Line", name, self) end
function M:CreateFontString(name, layer, template)
	local fs = NewRegion("FontString", name, self)
	fs.__text = ""
	fs.__font = template ~= nil   -- the client refuses SetText until a font is set
	return fs
end
function M:CreateAnimationGroup() return NewRegion("AnimationGroup", nil, self) end
function M:CreateAnimation(kind) return NewRegion("Animation", nil, self) end
function M:IsPlaying() return false end
function M:SetTexture() return true end
function M:SetFont() self.__font = true return true end
function M:SetFontObject() self.__font = true end
function M:GetFont() return STANDARD_TEXT_FONT, 12, "" end
function M:SetText(t)
	if self.__kind == "FontString" and not self.__font then error("FontString:SetText(): Font not set", 2) end
	self.__text = t
end
function M:SetFormattedText(f, ...)
	if self.__kind == "FontString" and not self.__font then error("FontString:SetFormattedText(): Font not set", 2) end
	self.__text = format(f, ...)
end
function M:GetText() return self.__text end
function M:GetStringWidth() return 50 end
function M:GetStringHeight() return 12 end
function M:GetUnboundedStringWidth() return 50 end
function M:GetNumLines() return 1 end
function M:GetMinMaxValues() return 0, 1 end
function M:GetValue() return 0 end
function M:GetStatusBarTexture() return self.__sbt or (function() self.__sbt = NewRegion("Texture", nil, self) return self.__sbt end)() end
function M:GetBackdrop() return self.__backdrop end
function M:SetBackdrop(b) self.__backdrop = b end
function M:GetTexture() return "tex" end
function M:GetAtlas() return nil end
function M:GetDrawLayer() return "ARTWORK", 0 end
function M:GetVertexColor() return 1, 1, 1, 1 end
function M:GetTextColor() return 1, 1, 1, 1 end
function M:GetShadowOffset() return 0, 0 end
function M:GetShadowColor() return 0, 0, 0, 1 end
function M:GetJustifyH() return "CENTER" end
function M:GetCursorPosition() return 0 end
function M:GetNumMessages() return 0 end
function M:GetMaxLines() return 128 end
function M:GetScrollOffset() return 0 end
function M:AtBottom() return true end
function M:GetNumRegions() return 0 end
function M:GetID() return self.__id or 0 end
function M:SetID(i) self.__id = i end
function M:IsMovable() return true end
function M:GetZoom() return 0 end
function M:GetZoomLevels() return 5 end
function M:GetHitRectInsets() return 0, 0, 0, 0 end

CreateFrame = function(kind, name, parent, template)
	local f = NewRegion(kind or "Frame", name, parent)
	if template and template:find("BackdropTemplate") then f.SetBackdrop = M.SetBackdrop end
	return f
end

function FireEvent(event, ...)
	for _, f in ipairs(FRAMES) do
		if f.__events[event] and f.__scripts.OnEvent then
			local ok, err = pcall(f.__scripts.OnEvent, f, event, ...)
			if not ok then record(event .. ": " .. tostring(err)) end
		end
	end
end

function RunOnUpdate(elapsed)
	for f, fn in pairs(ONUPDATE) do
		if f.__shown and f.__scripts.OnUpdate == fn then
			local ok, err = pcall(fn, f, elapsed)
			if not ok then record("OnUpdate: " .. tostring(err)) end
		end
	end
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent.__w, UIParent.__h = 1920, 1080
WorldFrame = CreateFrame("Frame", "WorldFrame")
DEFAULT_CHAT_FRAME = CreateFrame("Frame", "ChatFrame1")
DEFAULT_CHAT_FRAME.AddMessage = function(_, msg) LOG[#LOG + 1] = msg end
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
StaticPopupDialogs = {}
SlashCmdList = {}
EventRegistry = { RegisterCallback = function() end, TriggerEvent = function() end }
Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }

GetBuildInfo = function() return "1.60.1", "70205", "Sep 1 2026", 16001 end

Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }
FONT_COLOR_CODE_CLOSE = "|r"
NORMAL_FONT_COLOR_CODE = "|cffffd100"
HIGHLIGHT_FONT_COLOR_CODE = "|cffffffff"

-- secret values ---------------------------------------------------------------
SECRET_MODE = false
local secretMT = {}
local function boom() error("attempt to use a secret value", 2) end
for _, mm in ipairs({ "__lt", "__le", "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat", "__len", "__call", "__tostring" }) do
	secretMT[mm] = boom
end
secretMT.__index = function() error("attempt to index a secret value", 2) end
function Secret(v) if not SECRET_MODE then return v end return setmetatable({ v = v }, secretMT) end
function ENABLE_SECRETS()
	SECRET_MODE = true
	NIL_GLOBALS.issecretvalue, NIL_GLOBALS.canaccessvalue = nil, nil
	issecretvalue = function(v) return type(v) == "table" and getmetatable(v) == secretMT end
	canaccessvalue = function(v) return not issecretvalue(v) end
	canaccessallvalues = function(...) for i = 1, select("#", ...) do if issecretvalue((select(i, ...))) then return false end end return true end
	UnitHealth = function() return Secret(500) end
	UnitHealthMax = function() return Secret(800) end
end
