--------------------------------------------------------------------------------
-- Who has made OpenMap: What's new's Credits page (News.lua). Each group is a heading and its
-- people: { name, what they made (through L: it's translated) }. A contribution adds its line here,
-- under the name you go by on GitHub or CurseForge (never a real name you haven't given us), in the
-- same change that brings it.
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

ns.Credits = {
	{ L["Made by"], {
		{ "Ji" },
	} },
	{ L["Maps painted by hand"], {
		{ "Santiago Reyes", L["Hand painted custom art for OpenMap including the sea elements, blank land between zones, and his maps of WoW Forever dungeons."] },
	} },
	{ L["Programming"], {   -- (not "Code": that's the Pins code button's word)
		{ "daxtron2", L["the map's hitches while panning, found and measured with /openmap bench"] },
		{ "Ironship", L["the map in combat, RareScanner's icons over the map and other map addons' pins"] },
		{ "C-Clymer", L["how the map reopens, and middle-click to center on you"] },
		{ "RADD95", L["dungeon and cave maps in every language (they showed green on some languages' clients)"] },
		{ "Peendars", L["zooming about four times smoother, found and measured"] },
		{ "Loukky", L["flight masters named in your client's language"] },
		{ "diegodiaz1256", L["a dungeon's map opening when you open the map inside it, and one icon for townsfolk who walk about"] },
		{ "Naladdar", L["the resizable settings menu, resizing the map with Move Any, and the Titan Panel launcher"] },
		{ "ZiiMs", L["the switch for dungeon maps, and separate switches for friends and guild"] },
		{ "forcedroidbrain", L["map brightness"] },
		{ "TheRayoX", L["friends on other numbered realms on the map"] },
		{ "KonigTX", L["gold-bordered dots for your party and raid"] },
		{ "Luquatic", L["the yellow ping hidden with your arrow"] },
		{ "puschie286", L["one marker per friend or guildmate, none left over when they join your group, and the newest dungeons' entrances"] },
		{ "k4m1", L["the controller map option turned on in combat, and B by a quest's details"] },
		{ "FlyingPenguin98", L["OpenMap's map with a controller (the Gamepad UI)"] },
		{ "bv101rj", L["Questie 12.8's icons found on the map"] },
	} },
	{ L["Map art"], {
		{ "Blizzard Entertainment", L["the map art is the game's own"] },
	} },
	{ L["Libraries"], {
		{ "Ace3", "AceConfig-3.0, AceGUI-3.0" },
		{ "CallbackHandler-1.0, LibStub" },
	} },
	{ L["Translations"], {
		{ L["If a word reads wrong in your language, say so on CurseForge: it's fixed for the next version."] },
	} },
	{ L["Reports and ideas"], {
		{ L["Everyone who reports problems and ideas on CurseForge."] },
	} },
}
