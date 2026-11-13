# OpenMap changelog

## v0.8.7 (2026-11-12)

Nothing new for retail: v0.8.7 fixes Questie's icons on WoW Forever.

## v0.8.6 (2026-11-12)

### Improved

- **Icons stay shown while zooming**: "Fade icons while zooming" is now off for everyone, as zooming is
  smooth enough with them shown; turn it on again in the menu's On the map tab if you prefer it.

## v0.8.5 (2026-11-12)

### New

- **OpenMap's map with a controller** (the game's Gamepad UI; a test, off until you turn it on in
  Options: "OpenMap's map with the Gamepad UI (test)"): the seamless map with the Gamepad UI on, where
  OpenMap leaves the world map to Blizzard. OpenMap draws its map over Blizzard's, so the
  controller's buttons keep working and B closes the map. The left stick moves the cursor (at the
  edge it pans), the right stick zooms about it, A zooms in or presses what's under the cursor, X
  zooms out or closes what's open, and pressing the left stick puts the waypoint there. Off (the
  default): Blizzard's map with the Gamepad UI, as before. If you play with a controller, try it and
  tell us how it goes (#57). By FlyingPenguin98.

- **Reopen the map on your zone** (the menu's More tab, Reopen map: "Center on your zone"): the map
  opens on the whole zone you're in, in the middle, wherever you stand in it (#143).

### Fixed

- **"Darken unexplored areas" keeps its soft edges up close**: once the minimap's detail shows, the
  shade was hard-edged rectangles; it now has each unexplored area's own shape, as further out
  (#101, #129).

## v0.8.4 (2026-11-11)

### Improved

- **Your party and raid get a gold-bordered dot** on the stitched map, everywhere, so they can't be
  mistaken for a guild member's dot. Someone the game won't place is shown faintly in the middle of
  their zone, with "Somewhere in" on the tooltip. By KonigTX.

### Fixed

- **"Your arrow" off also hides the yellow location ping** when the world map opens or changes
  zones. Turning it on again restores the normal arrow and ping; party markers stay visible (#78). By Luquatic.

- **"Party and raid members" off means off**: Blizzard's own blips for your group are hidden too,
  not only OpenMap's dots (#77, found by Luquatic).

- **Dragging the map no longer zooms into a zone or city**: a drag that came back near where it
  started counted as a click and zoomed into what was under the cursor, Ironforge from parts of Dun
  Morogh most of all (#37, #64).

- **Guild markers clear when a guildmate joins your group**: their shared-location dot or zone
  badge entry could stay when the guild roster and the party spelled the character's name
  differently. By puschie286.

## v0.8.3 (2026-11-09)

### New

- **Turn off OpenMap's dungeon maps** (Options and the menu's On the map tab): off, clicking an
  entrance shows its card over the world map, and opening the map inside a dungeon shows the world
  map, so another dungeon map addon (NeedRoll, Dungeon Journal ...) can show its own. By ZiiMs.

- **Friends and guild each have their own switch**: keep your friends on the map and hide a big
  guild, or the other way round. A save with the old single switch off turns both off. By ZiiMs.

- **Map brightness** in the Look tab: dim the whole stitched map, including explored areas and the
  sea, while player and quest icons stay bright. 100% keeps the original look (the default). By
  forcedroidbrain.

- **A launcher for Titan Panel** and other LibDataBroker displays: it works like the minimap
  button (click: the map with its menu; right-click: the options window). By Naladdar.

### Improved

- **The settings menu can be resized**: drag its bottom-right corner to make it wider or shorter,
  double-click the corner to reset it. Long labels (German, the nearby zones settings) wrap
  instead of running into the next column, and the settings scroll when they don't fit the screen,
  instead of the whole menu shrinking. By Naladdar.

- **The map window can be resized with Move Any**: Move Any still places and scales the window,
  and OpenMap's corner grips set its width and height. By Naladdar.

- **Clicking a quest's icon on the windowed map shows it in the quest log**: the quest log beside
  the map opens if it was closed, with the quest's details, as well as tracking the quest and
  zooming in on it. (On the full-screen map a click still tracks and zooms only.)

- **A dungeon map remembers its tab**: picking Quests beside the quest log keeps it picked the next
  time a dungeon's map opens.

### Fixed

- **No more dot in the bottom-left corner of the screen** after closing the map, or inside a
  dungeon: the map art OpenMap keeps loaded while the map is closed was drawn there, hundreds of
  faint copies on one pixel. Found by ryanull24.

## v0.8.2 (2026-11-08)

### Improved

- **Panning no longer hitches**: the map set up to 300 textures' files in a single frame where a
  pan brought new ground into view, and each set is a load and an upload, so that frame showed as
  a hitch of about 35 ms. It sets 60 a frame now; the art still fades in, a few frames later.

### Fixed

- **The map no longer stalls a moment after it opens**: since 0.8.0 OpenMap keeps the map's art
  loaded while it's closed, then let go of it all in one frame a second into the opening, which the
  game unloaded at once (about a second's freeze). It now lets go of it a little at a time.

- **Zooming in notch by notch is smooth again**: since 0.8.1 the blur came back all at once each
  time the map stopped, one long frame the next wheel notch landed on. It now waits out a pause
  between notches and comes back a few zones a frame. Questie's mob paths are worked out once the
  map stops, not on every frame of a zoom.

## v0.8.1 (2026-11-08)

### New

- **Questie's mob paths on the stitched map**, drawn over the art for the zones near the view as
  you zoom in (Questie's own were under the art, and only on the zone's own map).

- **Darkening colour** (Options, under Darkening): the colour unexplored areas are darkened with,
  picked with the game's colour picker; **Default colour** brings back the dark one.

### Improved

- **Zooming is about four times smoother**: OpenMap no longer lays out its hidden icons and its
  blur on every frame of a zoom (the blur comes back a moment after you stop). Found and measured
  by Peendars.

- **Flight masters are easier to see on the map**: bigger, with a dark outline, and the ones you
  haven't learned are no longer half see-through (they were lost on the parchment).

- **Ctrl-click drops a pin can be turned off** (Options, and the menu's More tab): with Map Pin
  Enhanced a Ctrl-click dropped two pins, its own and OpenMap's. Off, the menu's Drop a pin still
  works.

### Fixed

- **Questie's icons show the first time you open the map**: after a login they could be missing
  until the map was closed and opened again (Questie was still setting up when OpenMap looked).

- **Zygor's waypoint shows on the stitched map**, in the right place and over the art (Zygor uses
  its own renamed copy of HereBeDragons, which OpenMap didn't know). Traced by robnoord.

- **Your class's trainers are found on every language's client**: on a French client (and the
  other non-English ones) every class trainer showed as a profession trainer.

- **An NPC who walks about shows once on the map**: Girl with Puppies in Orgrimmar had a vendor
  icon at every point of her walk, dozens over the city. An NPC with many spawns in one zone (with
  Vendors and the other townsfolk on) now has one icon, in the middle of where it walks. Fixed by
  diegodiaz1256.

- **No friends dot or badge for yourself**: with Share where you are on, you could show on your
  own map as a guild member (the guild's roster can spell your realm differently).

- **The map opens at once inside a dungeon**: each opening loaded the dungeon's map art again, a
  second or two (longer in dungeons with many floors, whose Floors tab shows every floor). OpenMap
  now keeps the art of the dungeon you're in loaded, as it does the world map's.

## v0.8.0-beta (2026-11-07)

### New

- **Friends and guild on the map** (Options: Friends and guild): your guild members and friends on
  your realm who are online show on the stitched map, a badge on the zone each is in with who's there. Those who use
  OpenMap and turn on **Share where you are** show as a class-coloured dot where they stand, updated
  every few seconds while they move. The map asks once whether to share; it's off unless you say yes,
  goes only to your guild and your friends, and never from inside a dungeon, raid or battleground.

### Improved

- **A new OpenMap icon, drawn by zloyeb**: a map scroll in a gold ring, in the AddOns list, on the
  minimap button, in the map's menu and its portrait (it borrowed the game's Eastern Kingdoms icon).
- **OpenMap is back on GitHub**, at github.com/openmap-world/openmap: Report a problem opens a
  report there again, and What's new and the AddOns list link to it.

### Fixed

- **"Center on player, keep zoom" opens at your zoom straight away**: having moved since the map
  closed, it opened on the zone's whole map for a moment and then jumped to the zoom kept.
- **The map opens with its art already there**: the game let go of the map's art while it was
  closed, and each opening loaded it again (blank parchment for a moment). OpenMap now keeps it
  loaded while the map is closed; `/openmap warm` turns that off.
- **The map closes in combat again**: with the map open as a fight started, neither Escape nor M
  closed it (since 0.7.0). The windowed map no longer stays open beside an NPC's window, which is
  what blocked it.
- **Flight masters you haven't learned show as not learned**: some showed as learned, as OpenMap
  counted the stops a flight passes through. What it remembered is forgotten once and counted again
  at the next flight master you talk to.
- **Flight masters are named in your own language**: on a client that isn't English, the map's
  flight masters kept the game's tables' English names. They're now named as the game names them,
  and a flight's measured time is found again on a route.
- **The map window can't go above the top of the screen**, where its title bar couldn't be
  grabbed to bring it back. `/openmap reset` puts the window back to its size and place.
- **The OpenMap menu fits a short screen**: on a TV at a big UI scale the Look tab ran off the
  bottom.

## v0.7.1-beta (2026-10-21)

### Fixed

- **The map loads the zone you pan or zoom to again**: with an addon adding map icons, it could stay
  on the zone you started on, so the zone you'd panned to showed none of their icons until you
  clicked it. Its setting, once Follow the view, is now **Load the zone in view**.
- **Flight masters you've learned are in colour**, all of them: OpenMap knew only the ones it had
  seen you visit since it was installed (and, on a client not in English, none). It now asks the
  game which you've found.

- **Retail: your arrow and the map's icons where they are in the cities**: in Stormwind, your arrow,
  Blizzard's flight master and the other icons on the city's map were drawn tens of yards from where
  they are (a player's report).
- **With Enhance QoL**, OpenMap says once in chat to turn off its Mover > World Map: the two both
  size the map, and its scale goes wrong (a player's finding).

## v0.7.0-beta (2026-10-20)

### New

- **OpenMap for retail** (Midnight): the same seamless map, from retail's own maps. Every continent on
  Azeroth's map, its zones stitched in as you zoom with their explored areas painted (or hidden until
  you've been there, as Blizzard's own map does), Blizzard's art as it is; the world's parchment out to
  its torn edge and on past it; dungeon and raid entrances from the encounter journal with every floor
  of their maps, flight masters, boats and zeppelins, the close-up minimap. A download of its own on
  CurseForge.

### Improved

- **The map stays open while you talk to an NPC** (or open a vendor, the bags' windows ...): the
  windowed map is no longer put away to make room. Escape still closes it; maximized, it behaves as
  before.
- **Reopen map: Center on player, keep zoom** (the menu's Reopen map, and Options): the map opens
  on you at the zoom you closed it at.
- **Choose your map**: the choice the first time the map opens is in the map window's own frame,
  with plainer words.
- **A little lighter at the whole-world view**: a city's map isn't drawn at all until it starts to fade
  in (before, it was drawn unseen).

## v0.5.0-beta (2026-10-16)

### New

- **Khaz Modan's blank land painted**: the stretches between Dun Morogh, Wetlands, Loch Modan,
  Searing Gorge and the Badlands that no zone map covers, and the coast round them, painted by hand
  by Santiago Reyes in the zone maps' own style, from Blizzard's art and following the game's
  terrain (used with his permission). The first of the gaps between zones to be filled; Options'
  **Filled gaps** turns them off.
- **Maps of City of Dalaran and Excavation Site: Wetlands**, drawn by Santiago Reyes and used with
  his permission: click their entrances in Alterac Mountains and the Wetlands (they opened on a blank
  page before). "Map by Santiago Reyes" at their foot, as with his others.
- **Airships to Zephras Isle**: the flying boats at the Dalaran skydock (Alterac Mountains) and in
  Mulgore are on the map; click one and Zephras Isle's map opens in the window, as a dungeon's does,
  and Back takes you to the world where you were. (Under the Boats switch.)
- **Maps of Ruins of Lordaeron and The Hall of Thanes**, two of WoW Forever's own dungeons, which
  the game has no map of: drawn by Santiago Reyes and used with his permission. Click their
  entrances in Undercity and Ironforge; the map shows "Map by Santiago Reyes" at its foot.
- **Dungeon Journal**: with Exehn's Dungeon Journal installed, a dungeon's map has **Open in Dungeon
  Journal** on its Bosses tab, and clicking an entrance can open its page there instead of its map
  (the menu's **Entrances open Dungeon Journal**, or Options). Its map still opens where Dungeon
  Journal has no page for it.
- **Dungeon quests without Questie**: the Quests tab works with Dungeon Journal or NeedRoll too, as a
  button that opens the dungeon's quests in it. With more than one installed, Options' **Dungeon
  quests from** picks which (the first installed: Questie, then Dungeon Journal, then NeedRoll).
- **The OpenMap button off the map, if you like**: **OpenMap button on the map** (the menu's Look tab)
  hides it and the favourites. The menu is still a click away: OpenMap is in the minimap's AddOns
  list, and there's a **minimap button** if you want one (the Look tab, or Options). Click for the map
  and its menu, right-click for the options window, drag it round the minimap; /openmap works too.
- **A choice the first time the map opens** on a new install: **Classic** (unexplored areas
  hidden, no dungeon or flight master icons, no zone levels, the favourite buttons folded away) or
  **OpenMap** (as it comes). Settings you already have aren't asked about or changed;
  /openmap welcome asks again. Suggested in #24.
- **Your arrow on top, or off**: the player arrow is drawn over every other icon on the map (quest
  givers, Questie's and other addons' icons), so you can always see which way you're facing
  (suggested in #31); your party's markers come up with it. Or take it off the world map (the menu's
  Show tab, **Your arrow**) and find your way old-school by the land around you: your party still
  shows, and so does the minimap.
- **Icons from zoom**: a slider (the menu's Look tab, or Options) for the zoom the icons for places
  (dungeons, boats, zeppelins and flight masters) show from: 1x has them from the whole world, higher
  keeps the map clean further out. Auto, as before, brings each in at its own zoom. Townsfolk never
  come in further out than their own; your pins, drawings and party always show.
- OpenMap shows under a **Map** category in the game's AddOns list.

### Improved

- **Map frame rate cap** (the menu's Look tab, or Options; off unless you set it): the frame rate at
  most while the map is open. A big map draws many layers over the whole screen every frame; at 60
  the graphics card does about half the work it does at 120 (reported: a full-screen 4K map doubling
  the card's power). Your own frame rate setting comes back as the map closes.
- Up close, a layer of the paper grain that has faded out is no longer drawn.
- **Report a problem** sends you to OpenMap's comments on CurseForge for now, to post its code in
  (What's new's link goes to OpenMap's CurseForge page too).
  Its window, and the bench's and the map notes' to copy from, are in the map window's own frame.
- **Dungeons, boats and zeppelins each have their own switch** in the menu's Show tab and in
  Options, so you can keep dungeon and raid entrances and hide the boats or zeppelins. A kind that's
  off takes its routes with it when routes are shown. Your old setting carries over to all three.
- **Out of a city to its zone**: right-click out of Stormwind, Ironforge, Darnassus, Orgrimmar,
  Thunder Bluff or Undercity and the map goes out to the zone around it (Elwynn Forest, Dun Morogh
  ...), as it does from anywhere else in that zone, not the whole continent.
- **Azeroth Tripview**: its live ships and docks are kept above the map's art. For other addons,
  OpenMapAPI (version 2) can now place a point of the game's world anywhere on the stitched map,
  for frames they put on the world map themselves (docs/api.md).

### Fixed

- Zooming in quickly, the zones no longer flicker to blank parchment for a moment: the map's
  pre-drawn tiles now stay until every zone coming into view has its art in.
- Opening a dungeon's map no longer can raise a Lua error the first time (when the map window
  changed size as it opened, as in full screen).
- **With a gamepad**: the cursor stays where you put it. It jumped back to the middle of the map
  each time the map underneath changed (shortly after every zoom or pan), so the next zoom was about
  the middle. And in combat, a dungeon's or Zephras Isle's map waits until you're out of it (a line
  in chat says so): opened then, the game set the map's gamepad buttons again in a way it blocks in
  combat, which could leave them wrong until a /reload.
- **WoW Forever's boats** are on the map, with their docks and routes: Steamwheedle Port (Tanaris)
  to Powderfuse Port (Riverglades), for both factions; Stormwind to Auberdine; and Menethil Harbor
  to Southshore and Auberdine, which takes the place of the old Menethil to Auberdine boat.
- **WoW Forever's flight masters**: Farholde Keep and Powderfuse Port for the Alliance, Rog'mar and
  Powderfuse Port for the Horde, with their flights (Farholde Keep to Powderfuse Port, Lakeshire,
  Morgan's Vigil and Thelsamar; Rog'mar to Stonard, Kargath, Flame Crest and Hammerfall). The flight
  network now comes from WoW Forever's own tables, which have moved Stormwind's flight master and
  redrawn some of the classic flights.
- **The close-up minimap on towns by the sea and on islands**: Menethil Harbor, Southshore,
  Theramore, Booty Bay's shallows, Teldrassil and Darnassus, Feathermoon Stronghold. It was cut to
  the continent map's coarse outline of the land, which leaves out what that map draws as sea; it
  now takes in each zone map's own land too.
- **No retail Eversong Woods or Zul'Aman over Quel'Thalas**: the minimap is now only the tiles the
  game itself draws (those its own world map file lists), which also leaves out other versions' sea
  far west of Dun Morogh and east of Wetlands, and the Draenei isles off Kalimdor.
- Blizzard's classic maps drawn in the land between zones are placed where WoW Forever places those
  zones. They were placed by Mists of Pandaria Classic's tables, whose zones are Cataclysm's, so
  The Barrens' was drawn at Northern Barrens' size and Stonetalon Mountains', Silithus', Badlands',
  Dun Morogh's and Azshara's were off, showing copies of their mountains beside the real ones.
  Cataclysm's Hillsbrad Foothills (Alterac taken in) and a different drawing of Mulgore are no longer
  used.
- The cave maps of four places WoW Forever doesn't have are gone: Greymane Manor (Gilneas),
  Spitescale Cavern (the Echo Isles as Cataclysm remade them), and Legion's Keeper's Rest and
  Karazhan Catacombs.
- **Books on Map Forever**'s book icons show on the stitched map: they were drawn under its art.
  Which ones show is still the addon's own choice (those of the zone or continent the map is on).
- The zone you're looking at has its name over the map again when you hover it, where the game
  names no place in it (Silverpine Forest's had gone; reported in #25). With Zone levels off, zone
  names still show, without their levels.
- **Move Any** owns the map window: with it, OpenMap's title bar, resize grips and saved place
  stand down, so Move Any's own drag and resize work on the map again (reported in #23). The map
  size slider and Reset size and place are off then.
- A city's own map that went missing (Ironforge showing only Dun Morogh's painting of it, until a
  /reload: reported in #30) is shown again when you reopen the map, and the map's check of what's in
  view no longer stays stuck if it stopped part way. (A safeguard: what hid it isn't known yet.)

## v0.4.0-beta (2026-10-16)

### New

- **Dungeon maps.** Click a dungeon's entrance for its own map, drawn from the game's own art (WoW
  Forever's map never shows it), right in the map window. Zoom with the wheel, drag to pan, and step
  through its floors with the arrows, the floor list or the side panel's Floors tab, which shows each
  floor as a small picture. Where several share an entrance you pick one; Blackrock Spire, Dire Maul
  and Scarlet Monastery are listed by wing, each opening on its own floor. Right-click, Escape or
  Back takes you back to the world where you were. 25 dungeons and raids have maps; WoW Forever's
  own new dungeons open on a blank page until the game has art for them.
- **A side panel for each dungeon**, in the quest log's place and look, as a tab beside the log: its
  floors, its bosses, its quests (with Questie: their level, done or in your log, objectives on
  hover) and its loot, where we recommend NeedRoll by mikebvs (a boss's row opens it). Put the quest
  log away and the dungeon's map has the whole view; the tabs at the map's edge bring the log back.
- **Dungeon entrances** show their level range, coloured for your level (the menu's Level ranges
  hides them). WoW Forever's own dungeons are on the map: City of Dalaran, The Drowned City,
  Excavation Site: Wetlands, The Hall of Thanes and Ruins of Lordaeron so far.
- **Map pins**, as many as you like: Ctrl-click the map (or Drop a pin) for one with a note and a
  colour. Its card follows it (Blizzard's waypoint, and TomTom's), shares it with your group, guild
  or a friend (other OpenMap players are asked first), gives a code to paste anywhere, or deletes
  it. The Pins list (/openmap pins) has them all, for all your characters.
- **The quill:** draw on the map with a pen, lines, arrows, circles and raid marks, in six inks and
  three widths (the menu's Quill, or /openmap draw). Your drawings are kept, and a pin's card can
  draw on that pin.
- **Tabs at the map's edge** for the OpenMap button and your favourites, in WoW Forever's own tab art.
  Drag the OpenMap tab anywhere round the edge; the arrow by it folds your favourites away. "Buttons
  as edge tabs" (the menu's Look tab) puts them back in the corner.
- **Report a problem draws:** in two steps, draw where it's wrong (with the quill, or on a dungeon's
  page), then say what's wrong, for a code to paste into a GitHub issue.
- **When reopening the map:** center on the player (the default for new installs), always restore
  the previous view, or restore it only while you're still in view. Middle-click the map to center
  on yourself at the same zoom. Thanks, C-Clymer (#19)!
- **What's new** in the game, laid out like the quest log: each version's changes, Newer and Older,
  and where to find OpenMap on GitHub.
- **For addon authors:** `OpenMapAPI` (docs/api.md), to place things on the stitched world, hear
  when the view moves or a dungeon's map opens, and add a switch to the OpenMap menu or a section
  to a dungeon's panel.

### Improved

- One place for OpenMap's settings: /openmap (and the game's AddOns settings page) opens the map's
  own menu, now with every setting in three tabs (On the map, Look, More) in the game's own settings
  look. The Look tab's sliders sit in two columns, with Defaults and Reset size and place under them.
- Other addons' map icons placed through HereBeDragons (TomTom, gatherers, notes addons) show on
  the stitched map from every zone in view, and Leatrix Maps' icons show above its art.
- Teldrassil's coast is whole, the great tree's roots all round the island, and Thunder Bluff comes
  in sooner, cut to its plan, under Mulgore's banner for it. (Changed textures: restart the game.)
- Darkened unexplored areas reach all of a zone's land and fade softly at their edges, with no hard
  lines or boxes in zones you've been to; cities you haven't found are darkened (or hidden) too.
  (Changed textures: restart the game.)
- The minimap's detail comes in after the same turns of the wheel in any window, full screen too,
  and a tall or very wide window brings the zones in by how much of the world is in view.
- The map pin's card, the pins list, What's new and the menu's dropdowns have the game's own frames
  and dropdown look; the coordinates are steady black boxes in the bottom-right corner; Find me has
  a crosshair; tooltips say plainly what a click does.
- The quest log's Back (from a quest's details) leaves the map where you're looking. The OpenMap
  menu shows over the quest log and stays put while you drag the map window, and the window's
  bottom-right corner is easier to grab with the quest log open.
- "Reset sliders to defaults" in Options, and Defaults under the menu's sliders.
- OpenMap gives back the game settings it holds: turn off its coordinates and Blizzard's come back,
  and at logout the map fade and coordinates are the game's own again.

### Fixed

- No more "action blocked" errors opening the map (or the quest log updating it) in combat
  (reported by C-Clymer in #19).
- Clicking a quest on another continent opens it at the first click.
- Zooming in on a zone no longer flashes plain parchment between its art from afar and close in.
- The quest log's button stays over the map's parchment border when you zoom right out, and its
  arrows point the way the log goes.
- A click on the window's resize corner without dragging no longer resets the view.
- Closing the map in the middle of resizing or moving it no longer leaves the window following the
  mouse.
- The menu's tabs no longer show another tab's names behind their own, and its search results
  aren't see-through.
- Clearing or replacing a map pin removes its TomTom waypoint.
- A flight route to or from a flight master you haven't learned says so.

## v0.3.0-beta (2026-10-14)

- "Minimap detail from" (a slider in the menu, under Deepest zoom, and in Options' Up close) sets how
  far in the minimap's detail starts to mix in: lower comes in sooner, higher later (20x by default);
  at 1x it's there from the whole world. Further out than the game's own minimap tiles can be
  drawn, smaller copies of them show, crossfading to the tiles as you zoom in. (New textures:
  restart the game.)
- "Minimap opacity" (in the menu too, and Options' "Minimap detail, most opacity"): the most the
  minimap's detail ever shows, at any zoom.
- More coastal and border detail: each zone map now shows everything it paints
  round its own land (the sea off its coasts with its shallows, hatching and islets, the
  mountains and coasts beyond its border), shared out with its neighbours so each place shows
  one painting, handing over smoothly at the maps' frames. Land no map paints is plain
  parchment, which the art fades into, instead of the neighbours' edges blurred across it.
  The zone maps' sea names, their names for the neighbouring zones and their compass roses
  are left out. (Changed textures: restart the game.)
- Improved compatibility with other map addons: they work alongside OpenMap instead of fighting
  it. On the stitched map the art and the view are OpenMap's, and the rest of theirs keeps working;
  their map art shows on dungeon maps as before. At login OpenMap names only the options that
  still clash, not the whole addon.
- Gamepad: on the stitched map the right stick zooms at a steady pace all the way in and out
  (it crawled zoomed in), about the gamepad's cursor; A zooms into the zone under the cursor and
  X out a map, as clicks do, instead of changing the map underneath; the coordinates, the hover
  label, the zone highlight and the boat routes follow the gamepad's cursor. Its cursor shows
  the tooltips of OpenMap's buttons and map icons, and A presses them: the OpenMap button, the
  favourites, the menu (a slider goes to the value under the cursor), the dungeon, flight and
  other icons.
- "Fade unexplored areas" is now "Darken unexplored areas": the land you haven't explored is much
  darker and greyer, instead of faded toward the parchment, and a zone you haven't found at all is
  darkened whole from every zoom, the whole world's too, with the mountains and land round it, so a
  stretch you haven't been to is dark from one zone to the next. Only land is darkened, not the
  sea the zone maps paint round their coasts. (New textures: restart the game.)
- Panning and zooming make far less Lua garbage (OpenMap's view and zoom updates reuse their
  tables instead of making new ones every frame), so the game has less to clear up as you use the map.
- Clicking a quest in the quest log that's in another zone opens it again: the map goes to the
  quest's zone and stays there. It flickered and went back to the list, because the map was put
  back where you'd last closed it. Reopening where you left off now only applies when you open the
  map, not when Blizzard changes the map while it's open (the quest log, the zone dropdown), and
  not when the map opens on a quest's zone from the quest tracker.
- A quest's details in the quest log reach the foot of a window taller than Blizzard's, with more
  room for the quest's text, instead of stopping short with an empty strip under the buttons.
- The OpenMap button is its icon alone, right in the map's bottom-left corner.
- Zoomed in, only the tiles of each zone near the view are drawn and loaded, not every tile of
  every zone it touches, and panning works out what to show only now and then instead of every
  frame (the sea and the paper grain stay put as you pan, too). Less for the game to draw and lay
  out as you move about.
- The zones' art is baked into world tiles (made by a script from Blizzard's map art, as the map
  draws it), so from the continents' zoom in to a zone the map draws a few dozen tiles instead of
  hundreds of masked textures; closer in than the tiles' own pixels, the zones' art is drawn live
  as before. Changing the colour match, or hiding unexplored areas, uses the live art throughout.
  (New textures, 69 MB: restart the game.)
- The continents' and seas' names cost far less to pan and zoom: only those near the view are
  drawn, and their halo takes half as many font strings (each copy's shadow is the one opposite
  it), the same to look at. Panning over a continent with its names showing was a third of the
  map's frame time on a wide screen. While the map moves (zooming or panning) their halo rests
  (every letter is drawn again at its new size on each frame of a zoom, and laid out again on each
  of a pan, and the halo was eight of its nine), back as soon as the map stops.
- Questie's icons from the neighbouring zones are placed up to half the map's width round it,
  not a whole width: every icon on the map is laid out again on each frame of a pan or zoom (231
  of them cost 7 ms a frame on a wide screen). Those further off show once the map switches to
  their zone.
- Panning and zooming no longer lay out the thousands of zone textures that aren't showing (the
  live art the baked tiles stand in for, the tiles off the view): a hidden one lets go of its place
  on the map until it shows again. With vsync off on a wide screen, all of OpenMap's art cost 20 ms
  of a 41 ms panning frame, 8 of them in art nobody could see.
- Up close over Orgrimmar the minimap's detail is much fainter (15% at most, from 50%): the city's own
  plan, which comes in from further out than the other cities', leads there.
- OpenMap's icons (flight masters, dungeons, the player arrow ...) are on the map's view instead of
  its canvas: they keep their size on screen by themselves, instead of their layer being rescaled
  on every frame of a zoom (which laid every icon out again: 6.6 ms of a zooming frame).
- `/openmap bench` times the map where it's slow (still, panning and zooming, at several zooms, then
  with each part of it off in turn) and gives the results to copy into an issue.
- The OpenMap menu's close button is easier to hit, and Escape closes the menu.
- "Report a problem" isn't only about the map: circling a spot is optional (just click Next), it
  works on dungeon maps too, and the issue form says so.
- The debug overlay also shows what can pile up over a session: the UI's Lua memory and how fast it
  grows, the map's pins (every addon's, and the kind there's most of), how much zone art is loaded,
  how many regions are placed live, which parts make the most Lua garbage a second (rescaling
  every addon's pins, switching maps, OpenMap's own updates), and which addons hold the most
  memory and grow it fastest.

## v0.2.0-beta (2026-10-11)

- Map notes (Tools → Map notes, `/openmap notes`) replace the paint tool: paint an area (or
  click) and say what's there, as a "fix this", "look into this" or "idea"; a list of them all
  (click one to go there) and Export, which gives them all as text to paste where they're needed.
  `tools/map-preview/notes.py` renders them out of game. Older paint mark-up becomes notes.
- A debug overlay (Tools → Debug overlay, `/openmap debug`): the frame rate on the map, a graph of
  frame times, the worst frame, and what OpenMap's own updates cost.
- The quest log shows on the full-screen map too: the Quest log button (and the arrow button in
  the corner, as on the windowed map) puts it over the map's right side. Its background no longer
  ends in a line when the window is taller than Blizzard's.
- Blizzard's quest areas (the blue shapes) keep up with the map as it zooms, instead of a step behind.
- The OpenMap button and the favourites' row are in the map's bottom-left corner, along its
  foot (over the coordinates when they show); favourites are icon buttons in Blizzard's
  action-button frame, glowing while they're on.
- The OpenMap menu is laid out afresh in the map window's own frame: the actions as tiles with
  icons, an icon by each setting, bronze rules between the parts. Find me, Drop a pin,
  Report a problem, Options and a new Quest log button (hide or show the quest log beside the
  map, out of combat) can be starred onto the map too.
- "Minimap detail" (in the menu's Up close and in Options) turns the minimap's detail off at
  the closest zoom, so the painted map is all you see.
- The deepest zoom is a slider in the menu, and goes to 192x (it was 96x at most).
- The window resizes from its bottom-left corner as well as the bottom-right, and both grips
  are easier to catch.
- Favourite settings: the star by each setting in the OpenMap menu puts it on the map as a
  button of its own, beside the OpenMap button (lit while it's on; click to switch it,
  right-click to take it off).
- The parchment border's edges are laid as copies of their piece at its own length, every other
  one mirrored, instead of one piece stretched along the whole side; the corners are as they were.
- Orgrimmar and Undercity keep their own maps' name banners: up close that's the city's title,
  and their zone's big banner for them (Durotar's, Tirisfal's) gives way to it as you zoom in,
  instead of covering the city. (Changed textures: restart the game.)
- No more straight-edged patches over the zones zoomed out (east of the Barrens, Stranglethorn ...):
  the blank paper in the gaps between zones reaches only a little way under the zones, not to
  the edge of the square it's drawn in. (Changed textures: restart the game.)
- The ocean past the world map keeps the world sea's own colours, carried outward, instead of
  one flat grey-green. (New texture: restart the game.)
- The OpenMap button stays in the map's top-left corner (an addon's frame across the map
  could push it off the right edge).
- Going full screen and back (or resizing the window) keeps the view you were looking at,
  instead of jumping to where the map was last closed.
- Resizing the window keeps its top-left corner (and the OpenMap menu) in place with the map
  size option off 100%, so the corner stays under the cursor; the resize grip sits in the
  window's outer corner, clear of the quest log button, and is easier to catch.
- Reopening a moved or resized map shows it in its place at once (not Blizzard's first).
- The menu's pin button works wherever you click (on Blizzard's map icons too, where only
  Ctrl-click did), with the pin cursor while it's on.
- On the stitched map the waypoint is always OpenMap's pin: Shift-clicking Blizzard's there was
  blocked ("only available to the Blizzard UI"). Shift-click OpenMap's to share it in chat.
- No more square patches and straight bands in the sea off Stranglethorn and Wetlands: the
  gap fill's borrowed paintings of the land between zones stay on land, and a zone's painted
  sea fades out well inside its frame. (New textures: restart the game.)
- Zone art fades in as it loads (zooming or panning fast onto new zones), instead of popping in.
- Over the major cities' own maps the minimap shows at half strength at most, so the city plan leads.
- "Dim unexplored areas" is now "Fade unexplored areas": those areas fade 60% of the way to the
  zone's blank parchment (its unexplored look) instead of darkening.
- Faster panning and zooming: map icons off the view (townsfolk, flight masters ...) are
  hidden, and blank tiles of the filled-in land aren't drawn.
- Opening the map loads only the zone art in view (and none until zone detail shows), instead
  of the whole world's; `/openmap status` shows how long the last openings took.
- Questie's icons stay on the map when it switches to a zone: Questie's map library places
  them from world coordinates that are off on Forever's zone and continent maps, so there
  each icon is placed (or moved) from Forever's own map positions. They're also lifted above the stitched art:
  Questie fixes its icons' frame levels, which put them under the zone art up close. `/openmap status`
  shows how many Questie icons there are and who placed them.
- The parchment border frames the map only when zoomed right out, fading as you zoom in.
- Blizzard's glow on the zone under the cursor is off by default on the stitched map
  ("Zone highlight on hover" in the menu brings it back).
- The map window's portrait is OpenMap's icon while the map is stitched; the OpenMap button
  sits beside Blizzard's floor dropdown instead of under it.
- Opening the map sets its view once (straight to where you left off), or not at all if
  it's still there, instead of Blizzard's reset to the whole world and back; the
  close-up softening no longer recolours the whole map when it first builds a zone.
- Zone art coming into view loads over a few frames instead of stalling one; `/openmap status`
  names the slowest steps of the close-up update, and how much of opening the map is OpenMap's.
- Undercity: Tirisfal's "Undercity" banner sits over the city until close in, as Orgrimmar's
  does. You can zoom 1.5x further in cities, and the minimap mixes in over the cities in the
  open. Undercity's and Ironforge's own maps are drawn over the minimap, which shows the
  surface there, wherever they are in the view.
- Blackrock Mountain's inside (its main floor) surfaces from further out as you zoom in on it.
- Cave and dungeon-entrance maps stay while they're on screen (they no longer fade as you pan
  away from them); only the dimming of the surface follows the one you're centred on.
- Undercity's map is cut to the city's plan (its quarters, the Ruins, the Sewers), so Tirisfal's
  painting shows round it instead of the city map's own parchment.
- "Fade while moving" (0-90%, in Options; on / off in the map's menu) replaces "Don't fade while
  moving": the map fades smoothly while you move, never while the mouse is over it.

## v0.1.0-beta (2026-10-09)

First public beta. One seamless world map for WoW Forever: every zone stitched
together, Blizzard's own art, with dungeon entrances and caves, flight paths,
boat and zeppelin routes, townsfolk and rares (with Questie), search, map pins,
group members, a movable and resizable window, and a "Report a problem" button.
The continent and sea names are lettered live; land Forever has no zone map for is
drawn from Blizzard's classic and pre-Cataclysm maps of it, or left as blank parchment.
