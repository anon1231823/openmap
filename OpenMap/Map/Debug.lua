--------------------------------------------------------------------------------
-- The debug overlay, for chasing lag: a small panel in the map's top-right corner with the
-- frame rate, each frame's time as a moving graph (a hitch shows as a spike), the worst
-- frame of the last two seconds, what OpenMap's own updates cost (the zoom update, the
-- close-up update), how many of the art's textures are drawn, and what could pile up over a
-- session: the UI's Lua memory and how fast it grows, the map's pins (all addons', and which
-- kind there's most of), how much zone art is loaded, how many regions are placed live, and
-- which parts make the most Lua garbage (WorldMap.lua measures them while this is on; "pins
-- rescaled" is every addon's pins, OpenMap's zoom update with them), and which addons hold and grow
-- the memory. /openmap debug, or the menu's Tools. Its own cost is small (one bar a frame, the
-- text twice a second, the counts once a second, every addon's memory every 10 seconds).
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")
local L = ns.L

mod.defaults.debugOverlay = false

local BARS = 120                -- frames in the graph
local GRAPH_MS = 50             -- the graph's height, in ms (a taller frame is clipped, and red)
local W, H = 400, 40            -- the graph (and the text lines' width)
local WORST_WINDOW = 2          -- seconds the "worst" covers

local map, sc, panel
local bars, stamps, spans = {}, {}, {}   -- the graph; each frame's time (and when), a ring of BARS
local cursor = 0
local textAt, countAt, drawn = 0, 0, 0
local counts = {}               -- once a second: memory, pins, art (Counts)
local memFrom                   -- { KB, time } when the overlay was turned on: memory's growth since
local garbageAt, garbageWas = 0, {}   -- WorldMap.lua's garbage counts, a second ago
local lastKB, madeKB, madeWas = nil, 0, 0   -- the whole UI's garbage: memory's rises frame to frame, added up

-- the parts making the most Lua garbage over the last second (WorldMap.lua's mod.garbage, KB)
local function Garbage(now)
	local dt = now - garbageAt
	local list = {}
	for name, kb in pairs(mod.garbage or {}) do
		local rate = dt > 0 and garbageAt > 0 and (kb - (garbageWas[name] or 0)) / dt or 0
		if rate > 1 then list[#list + 1] = { name, rate } end
		garbageWas[name] = kb
	end
	garbageAt = now
	table.sort(list, function(a, b) return a[2] > b[2] end)
	for i = 1, #list do list[i] = ("%s %.1f MB"):format(list[i][1], list[i][2] / 1024) end
	return #list > 0 and table.concat(list, ", ", 1, math.min(3, #list)) or L["none to speak of"]
end

-- the map's pins, every addon's: how many, and the kind there's most of
local function Pins()
	local total, top, topN = 0, nil, 0
	for template, pool in pairs(map.pinPools or {}) do
		local ok, n = pcall(pool.GetNumActive, pool)
		n = ok and tonumber(n) or 0
		total = total + n
		if n > topN then top, topN = template, n end
	end
	if top then top = top:gsub("HereBeDragonsPinsTemplateQuestie", "Questie"):gsub("HereBeDragonsPins%-Questie%-WorldMapPin", "Questie"):gsub("PinTemplate$", ""):gsub("Template$", "") end
	return total, top, topN
end

local function Counts(now)
	local ok, kb = pcall(collectgarbage, "count")
	kb = ok and kb or 0
	if not memFrom then memFrom = { kb, now } end
	counts.mb = kb / 1024
	counts.rate = now > memFrom[2] + 5 and (kb - memFrom[1]) / 1024 / (now - memFrom[2]) * 60 or 0
	counts.pins, counts.top, counts.topN = Pins()
	if S.ArtStats then counts.loaded, counts.total, counts.live, counts.queue = S.ArtStats() end
	counts.made = garbageAt > 0 and (madeKB - madeWas) / 1024 / math.max(0.001, now - garbageAt) or 0
	madeWas = madeKB
	counts.garbage = Garbage(now)
end

-- which addons hold the Lua memory, and which grow it: every ADDON_EVERY seconds (asking the
-- game for every addon's memory takes a moment itself), each addon's size and growth a minute
-- since the overlay was turned on
local ADDON_EVERY = 10
local addonAt, addonFrom, addonText = 0, nil, nil
local function Addons(now)
	if now < addonAt then return end
	addonAt = now + ADDON_EVERY
	local A = C_AddOns or {}
	local num = A.GetNumAddOns or GetNumAddOns
	local info = A.GetAddOnInfo or GetAddOnInfo
	if not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage and num and info) then addonText = nil return end
	if not pcall(UpdateAddOnMemoryUsage) then return end
	local first = not addonFrom
	addonFrom = addonFrom or { at = now }
	local list = {}
	for i = 1, num() do
		local kb = GetAddOnMemoryUsage(i) or 0
		if kb > 0 then
			local name = info(i)
			if first then addonFrom[name] = kb end
			local dt = now - addonFrom.at
			local rate = (not first and dt > 5 and addonFrom[name]) and (kb - addonFrom[name]) / 1024 / dt * 60 or 0
			list[#list + 1] = { name = name, mb = kb / 1024, rate = rate }
		end
	end
	-- the biggest growers first (until there's growth to see: the biggest)
	table.sort(list, function(a, b)
		if math.abs(a.rate - b.rate) > 0.05 then return a.rate > b.rate end
		return a.mb > b.mb
	end)
	local parts = {}
	for i = 1, math.min(3, #list) do
		local e = list[i]
		parts[i] = ("%s %.0f MB%s"):format(e.name, e.mb, math.abs(e.rate) >= 0.05 and (" (%+.1f/min)"):format(e.rate) or "")
	end
	addonText = table.concat(parts, ", ")
end

local function Color(ms)
	if ms <= 1000 / 55 then return 0.3, 0.85, 0.35 end   -- (60 fps, near enough)
	if ms <= 1000 / 30 then return 1, 0.8, 0.25 end
	return 1, 0.3, 0.25
end

-- the sum of the zoom update's parts (S.SetZoom, smoothed per part)
local function ZoomMs()
	local total = 0
	for _, st in pairs(S.zoomSteps or {}) do total = total + (st.ms or 0) end
	return total
end

local function Update(_, elapsed)
	local now = GetTime()
	local ms = elapsed * 1000
	cursor = cursor % BARS + 1
	stamps[cursor], spans[cursor] = now, ms
	-- what the whole UI made this frame (a collection makes memory fall: then nothing's counted)
	local kb = collectgarbage("count")
	if lastKB and kb > lastKB then madeKB = madeKB + (kb - lastKB) end
	lastKB = kb
	local bar = bars[cursor]
	bar:SetHeight(math.max(1, math.min(H, ms / GRAPH_MS * H)))
	bar:SetColorTexture(Color(ms))
	-- the newest bar's neighbour is the oldest: a gap shows where the graph wraps
	bars[cursor % BARS + 1]:SetColorTexture(0, 0, 0, 0)
	if now < textAt then return end
	textAt = now + 0.5
	local worst = 0
	for i = 1, BARS do
		if stamps[i] and now - stamps[i] <= WORST_WINDOW and spans[i] > worst then worst = spans[i] end
	end
	if now >= countAt then
		countAt = now + 1
		drawn = mod.IsStitched() and S.DrawnCount and S.DrawnCount() or 0
		Counts(now)
		Addons(now)
	end
	local fps = GetFramerate()
	local cv = S.closeView or {}
	local _, _, zoom = mod.ViewNow()
	panel.fps:SetFormattedText("|cff%s%.0f fps|r  %.1f ms   worst %.0f ms", fps >= 55 and "4cd959" or fps >= 30 and "ffcc40" or "ff4d40",
		fps, fps > 0 and 1000 / fps or 0, worst)
	panel.ours:SetFormattedText(L["OpenMap: zoom update %.1f ms, close-up %.1f ms (worst %.1f)"], ZoomMs(), cv.ms or 0, cv.worst or 0)
	panel.art:SetFormattedText(L["zoom %.1f, %d textures drawn, %d minimap tiles"], zoom or 0, drawn, cv.tiles or 0)
	panel.mem:SetFormattedText(L["Lua memory %.0f MB (%+.1f MB a minute), map pins %d (most: %s %d)"], counts.mb or 0, counts.rate or 0,
		counts.pins or 0, counts.top or "-", counts.topN or 0)
	panel.load:SetFormattedText(L["zone art loaded %d of %d, %d regions placed live, %d to load"], counts.loaded or 0, counts.total or 0,
		counts.live or 0, counts.queue or 0)
	panel.trash:SetFormattedText(L["garbage a second: %.1f MB in all, of which %s"], counts.made or 0, counts.garbage or "-")
	panel.addons:SetFormattedText(L["addons' memory: %s"], addonText or L["counting ..."])
end

local function Build()
	panel = CreateFrame("Frame", nil, map)
	panel:SetSize(W + 16, H + 110)
	panel:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -8, -36)   -- (under Blizzard's buttons in that corner)
	panel:SetFrameLevel(math.min(sc:GetFrameLevel() + 9450, 9970))
	ns.Look:Panel(panel, { alpha = 0.8 })
	local function Line(y, template)
		local fs = panel:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", 8, y)
		fs:SetWidth(W)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)       -- (cut short, not run over the next line)
		ns.Look:Font(fs, 11)
		return fs
	end
	panel.fps = Line(-6)
	ns.Look:Font(panel.fps, 12, "OUTLINE")
	panel.ours = Line(-22)
	panel.art = Line(-35)
	panel.mem = Line(-48)
	panel.load = Line(-61)
	panel.trash = Line(-74)
	panel.addons = Line(-87)
	local graph = CreateFrame("Frame", nil, panel)
	graph:SetSize(W, H)
	graph:SetPoint("BOTTOMLEFT", 8, 6)
	local bg = graph:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.35)
	-- 60 fps and 30 fps lines
	for _, ms in ipairs({ 1000 / 60, 1000 / 30 }) do
		local line = graph:CreateTexture(nil, "ARTWORK", nil, 1)
		line:SetColorTexture(1, 1, 1, 0.18)
		line:SetSize(W, 1)
		line:SetPoint("BOTTOMLEFT", 0, ms / GRAPH_MS * H)
	end
	local bw = W / BARS
	for i = 1, BARS do
		local t = graph:CreateTexture(nil, "ARTWORK")
		t:SetWidth(math.max(1, bw - 0.3))
		t:SetHeight(1)
		t:SetPoint("BOTTOMLEFT", (i - 1) * bw, 0)
		t:SetColorTexture(0, 0, 0, 0)
		bars[i] = t
	end
	panel:SetScript("OnUpdate", Update)
	panel:Hide()
end

function mod:IsDebugOverlay() return mod.db.debugOverlay and true or false end

function mod:ToggleDebugOverlay(on)
	if on == nil then on = not mod.db.debugOverlay end
	mod.db.debugOverlay = on and true or false
	if panel then
		wipe(stamps) wipe(spans)
		memFrom, garbageAt, lastKB = nil, 0, nil
		addonFrom, addonAt, addonText = nil, 0, nil
		panel:SetShown(mod.db.debugOverlay)
	end
	if mod.RefreshPanel then mod:RefreshPanel() end
end

function mod:SetupDebug(worldMap)
	map, sc = worldMap, worldMap.ScrollContainer
	Build()
	panel:SetShown(mod.db.debugOverlay)
end

--------------------------------------------------------------------------------
-- /openmap highlights: where the game draws each zone's highlight on its continent's map (the glow on
-- the zone under the cursor, C_Map.GetMapHighlightInfoAtPosition: its texture, the part of it used and
-- its rectangle on the continent), for tools/map-preview/territory.py: a zone's whole area, as its
-- continent's map draws it. A client with a world of its own only (ns.MapWorld). A grid of points over
-- each stitched continent, a few rows a frame; each different highlight once, as a line, kept in
-- OpenMapDB (worldmap, highlights) once you /reload or log out: tools/map-preview/highlights.py reads it
--------------------------------------------------------------------------------

local HIGHLIGHT_GRID = 160      -- points across and down each continent
function mod:Highlights()
	local conts = ns.MapWorld and ns.MapWorld.continents
	local at = C_Map.GetMapHighlightInfoAtPosition
	if not conts or not at then
		ns:Print(L["Nothing to record here: this client's map has no world of its own."])
		return
	end
	local out, seen, jobs = {}, {}, {}
	mod.db.highlights = out
	for _, c in ipairs(conts) do
		for j = 0, HIGHLIGHT_GRID - 1 do jobs[#jobs + 1] = { c, j } end
	end
	ns:Print(L["Recording the zones' highlights: a few seconds."])
	local i, ticker = 0, nil
	ticker = C_Timer.NewTicker(0, function()
		for _ = 1, 4 do
			i = i + 1
			local job = jobs[i]
			if not job then
				ticker:Cancel()
				ns:Print((L["%d highlights recorded: saved (OpenMapDB: worldmap, highlights) once you /reload or log out."]):format(#out))
				return
			end
			local c, j = job[1], job[2]
			for k = 0, HIGHLIGHT_GRID - 1 do
				local x, y = (k + 0.5) / HIGHLIGHT_GRID, (j + 0.5) / HIGHLIGHT_GRID
				local ok, fid, atlas, px, py, tx, ty, sx, sy = pcall(at, c, x, y)
				fid, atlas = ok and ns.Safe.Value(fid), ok and ns.Safe.Value(atlas)
				if (fid and fid ~= 0) or atlas then
					local key = c .. ":" .. tostring(fid) .. ":" .. tostring(atlas)
					if not seen[key] then
						seen[key] = true
						local info = C_Map.GetMapInfoAtPosition(c, x, y)
						out[#out + 1] = ("%d %d %s %s %s %s %s %s %s %s"):format(c, info and info.mapID or 0, tostring(fid or 0),
							tostring(atlas or 0), tostring(ns.Safe.Value(px)), tostring(ns.Safe.Value(py)), tostring(ns.Safe.Value(tx)),
							tostring(ns.Safe.Value(ty)), tostring(ns.Safe.Value(sx)), tostring(ns.Safe.Value(sy)))
					end
				end
			end
		end
	end)
end
