-- Fallback copies of the cave and dungeon maps from OpenMap's own folder (Media/Textures/Forever/MapTile).
-- WoW Forever doesn't list them for every language, so some clients (esMX, ruRU, itIT) draw them as
-- solid green squares. Dungeon maps first try the client's native localized paths in Map/Dungeons.lua;
-- this swaps each remaining file ID in Caves.lua's and DungeonMaps.lua's tile lists for its copy
-- (tools/map-tiles/build.py copies them; RADD95's OpenMap TextureFix found it).
-- Written by hand (not generated); loads after Caves.lua and DungeonMaps.lua.

local _, ns = ...

local P = ns.Media.tex .. "MapTile\\"

local function Swap(tiles)
	for k, fid in ipairs(tiles) do
		if type(fid) == "number" then tiles[k] = P .. fid end
	end
end

for _, cave in pairs(ns.MapCaves or {}) do
	if cave[11] then Swap(cave[11]) end
end
for _, floors in pairs(ns.MapDungeonMaps or {}) do
	for _, floor in ipairs(floors) do
		if floor.tiles then Swap(floor.tiles) end
	end
end
