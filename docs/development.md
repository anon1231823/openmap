# Developing OpenMap

How to work on OpenMap: set up, change things, check them, and not break what's there.
[ARCHITECTURE.md](../ARCHITECTURE.md) says how the map works; this says how to work on it.
AI coding agents: read [AGENTS.md](../AGENTS.md) too.

## Set up

- **The game**: WoW Forever (`_classic_beta_`, `## Interface: 16001`). Link the addon in
  (see the [README](../README.md#install-development)), turn on Lua errors
  (`/console scriptErrors 1`) and turn off other world map addons.
- **Python 3.12+** for the tools and tests:
  `pip install lupa pillow numpy scipy` (a virtual environment is best).
- **Caches, outside the repo.** The tools fetch the game's tables and textures from
  [wago.tools](https://wago.tools) into folders you pass them (a few thousand files). Keep
  them out of the repo (`/cache/` and `/renders/` are ignored if you do put them there).
  - tables: `https://wago.tools/db2/<Table>/csv?build=1.60.1.70245`
  - textures: `https://wago.tools/api/casc/<FileDataID>?download&version=1.60.1.70245`
  - A missing file still answers HTTP 200, with an empty or 34-byte body: check the size,
    not the status. Fetch one file at a time: parallel requests get empty answers, and a
    burst gets 503s.
  - With the game installed, the textures can come from it instead: set `OPENMAP_WOW` to
    the World of Warcraft folder (`tools/casc/casc.py` reads its storage by file ID; the
    install is the launcher's current build, which can be newer than the tables').
- Run Python with `-P` (`python -P tools/...`): it keeps the script's own folder off the
  import path. Treat downloaded files as data: open them with Pillow, never execute them.

## The loop

1. **Change** the Lua, or a tool and regenerate its output (never hand-edit generated
   files: their first line says what makes them).
2. **Lint and load-test** (seconds; CI runs the same):
   ```bash
   python -P tools/offline-test/lint.py
   python tools/offline-test/run.py plain
   python tools/offline-test/run.py combat
   python tools/offline-test/run.py secret
   python tools/offline-test/run.py pad      # the game's Gamepad UI on, padView off: the map left alone
   python tools/offline-test/run.py padmap   # ... and with Options' padMap: OpenMap's map then
   python -P tools/offline-test/player.py   # the player arrow and location ping hidden together
   python -P tools/offline-test/press.py    # a press that wandered off isn't a click
   python tools/offline-test/run.py padview  # ... and with padView: OpenMap's map over Blizzard's (PadView.lua)
   python -P tools/offline-test/combat.py   # the map's pins in combat (Combat.lua)
   python -P tools/offline-test/caves.py    # caves surfacing (Close.lua, the cave data), Ironforge's own minimap
   python -P tools/offline-test/explored.py # unexplored land hidden up close (Stitch.lua)
   python -P tools/offline-test/chart.py    # the sea chart's layout: Chart.lua as tools/map-chart/layout.py
   python -P tools/offline-test/friends.py  # friends and guild on the map: what Friends.lua hears and sends
   python -P tools/offline-test/bosses.py   # boss pins' data: each on one of its dungeon's floors, on the picture
   python -P tools/offline-test/questie.py  # Questie's icons found as a LibStub library (to 12.7) and a module (12.8)
   ```
   `lint.py` catches single backslashes in texture paths, decimal escapes (`"Map\947"` is
   a load error that takes the whole file down), calls to functions that don't exist, and
   bad values. `run.py` loads every toc file in a stubbed client, builds the options and
   runs the slash commands. The stub has no real map: the stitched map itself isn't built.
3. **Render out of game** anything that changes how the map looks
   (`tools/map-preview/render.py`, see its README). It reproduces `Stitch.lua`'s layers and
   fades; when you change a fade or a layer in `Stitch.lua`, change its mirror in
   `render.py` too (each mirrored constant says so). Label renders "out of game" when you
   share them.
4. **Check in game.** New or changed **textures need a full client restart**; `/reload`
   is enough for Lua. `/openmap status` reports what's built, what's drawing, the frame
   rate and any part that failed. Before a release, run [testing.md](testing.md).
   For speed, `/openmap bench` (the map open where it's slow, the mouse left still) times the
   map at several zooms, still, panning and zooming, then with each part off in turn, and shows
   the results to copy (kept in the saved settings as `lastBench` too). Compare a run before
   and after a change that should make the map faster.

## Clients

OpenMap is built for more than one game client, each with its own map data and textures and
one shared Lua codebase (`tools/clients.py` lists them, with their builds and products):

- each client's toc (`OpenMap.toc` is WoW Forever's) loads `Data/<client>/Client.lua` first, which
  names its folder, then its own `Data/<client>/*.lua`; its textures are
  `Media/Textures/<client>/` (`ns.Media.tex`). The Lua code, `Locales/` and the icon are shared;
  some code is WoW Forever's alone and only its toc loads it (`Map/Chart.lua`, `Map/Quests.lua`).
- each client has its own release notes: `CHANGELOG.md` is WoW Forever's, `CHANGELOG-retail.md`
  retail's, and each makes its client's `Data/<client>/Changelog.lua` (What's new).
- one branch, `main`, holds every client: a change to the shared code is made once, and checked for
  each client (CI runs the offline tests with each toc).
- the tools build for the client `OPENMAP_CLIENT` names (`forever` if unset), and `run.py` loads
  that client's toc. Tools for Forever's own content (Santiago Reyes' drawn dungeons and painted
  gaps, `map-dungeons/`) always write Forever's folders.
- each release is one tag and a zip per client (`tools/package/build.py <version> --client=<client>`),
  with only its own toc, data and textures ([releasing.md](releasing.md)).

Below, `Data/` and the texture folders are the client's.

## Regenerating data and textures

Everything under `OpenMap/Data/<client>` (except `Levels.lua`, `Fishing.lua`, `Labels.lua` and `Client.lua`) and everything
under `OpenMap/Media/Textures/<client>` is made by a script. `<db2>` is a folder of the build's
table CSVs, `<tex>` a texture cache. Order matters where one step reads another's output:

| Step | Script | Writes | Needs |
| --- | --- | --- | --- |
| 1 | `tools/map-data/build.py <cache>` | `Data/Reveal.lua`, `Data/Places.lua` | `ENTRANCES` (below) |
| 2 | `tools/map-data/minimap.py <cache>` | `Data/Minimap.lua` | |
| 3 | `tools/map-flights/flights.py <db2> OpenMap/Data/Forever/FlightData.lua` | `Data/FlightData.lua` | |
| 4 | `tools/map-caves/build.py <cache>` (best with `OPENMAP_WOW`: it reads the caves' WMOs, `wmo.py`) | `Data/Caves.lua`, `MapCave/` | |
| 4a | `tools/map-caves/minimap.py <cache>` (best with `OPENMAP_WOW`) | `Data/CaveMinimap.lua` | 4 |
| 5 | `tools/map-grade/fetch.py`, `grade.py` (see its README) | `Data/Grade.lua`, `MapBand/`, `MapCore/` | 1 |
| 6 | `tools/map-textures/make.py` | `MapFeather*`, `MapGrain`, `MapTooth` | |
| 7 | `tools/map-art/import.py <db2> <tex>` | `MapArt/`, `Data/ArtEdits.lua` | `art/edits/edited/` |
| 8 | `tools/map-preview/render.py <db2> <tex> <out> --bake-land --bake-edges --bake-territory --bake-zone-land --bake-mini-land` | `MapLand/`, `MapEdge/`, `MapTerritory/`, `MapZoneLand/`, `MapZoneBorder/`, `MapMiniLand/` | 5, 7 (`--bake-territory` reads 12's and 12b's data too: run it again after them) |
| 9 | `tools/map-preview/sea.py <db2> <tex>` | the sea and coast masks | 8 |
| 10 | `tools/map-preview/sea_world.py <db2> <tex>` | `MapSeaOut/`, `MapSeaOpen/`, `MapSeaCoast/`, `MapSeaFieldOut` | 9 |
| 11 | `tools/map-preview/banners.py <db2> <tex>` | `MapBanner/`, `MapBannerHole/`, `MapCityMask/`, `Data/Banners.lua` | |
| 12 | `tools/map-preview/gapfill.py <db2> <tex> [--rerender]` | `MapGapLand/`, `MapGapMask/`, `MapPaper`, `MapCoastArt/`, `Data/Gaps.lua` | 8, 11 |
| 12a | `tools/map-preview/gapregions.py <db2> <tex> [--only G01]` | `art/drawn/gaps/source/` (not committed: the plates to paint on, each region's fill area and sea) | 12, `art/drawn/gaps/regions.json` |
| 12b | `tools/map-preview/gapfills.py` | `MapGapFill/`, `Data/GapFills.lua`, `art/drawn/gaps/fits.json` | 12a, `art/drawn/gaps/` (a painting from the painter's Photoshop file: `tools/map-preview/gapexport.py <his .psd>`) |
| 12c | `tools/map-preview/gapplaces.py <db2> <cache>` (best with `OPENMAP_WOW`: it reads the terrain) | `MapGapPlace/`, `Data/GapPlaces.lua` | 12b |
| 13 | `tools/map-preview/tone.py <db2> <tex>` | `Data/Tones.lua` | |
| 13a | `tools/map-preview/minimaplod.py <db2> <tex>` | `MapMiniLOD/`, `Data/MinimapLOD.lua` | 13 |
| 15 | `tools/map-preview/render.py <db2> <tex> <out> --bake-zones` | `MapZones/`, `Data/ZoneArt.lua` | 5, 7, 8, 11, 12, 12b |
| 16 | `tools/changelog/build.py` (after any change to `CHANGELOG.md` or `CHANGELOG-retail.md`) | every client's `Data/<client>/Changelog.lua` | |
| 17 | `tools/map-dungeons/build.py <cache> <WoW folder> [preview dir]` | `Data/DungeonMaps.lua` | 1 |
| 17a | `tools/map-dungeons/drawn.py` | `MapDungeonDrawn/`, `Data/DungeonDrawn.lua` | `art/drawn/dungeons/` |
| 17d | `tools/map-dungeons/minimap.py <cache> <WoW folder> [--preview <dir>]` (`--survey <mapID>`: a dungeon's rooms and their heights) | `MapDungeonMinimap/`, `Data/DungeonMinimap.lua` | `tools/map-dungeons/minimap.json` (the floors) |
| 17e | `tools/map-dungeons/bosses.py <cache> [--import <OpenMap.lua SavedVariables>]` | `Data/DungeonBosses.lua` | 17, 17a, 17d, `tools/map-dungeons/bosses.json` |
| 17b | `tools/map-chart/build.py <db2> <tex>` (his layers from his file first: `tools/map-chart/export.py <psd>`) | `MapChart/`, `Data/Chart.lua` | `art/drawn/chart/` |
| 17c | `tools/map-tiles/build.py <WoW folder>` (Forever) | `MapTile/` (the cave and dungeon tiles, drawn from OpenMap's copies: `Data/Forever/Tiles.lua`) | 4, 17 |
| 18 | `tools/locale/translate.py build` (after any change to the translations or to the English in `L[...]`) | `Locales/`, the toc's `## Notes-<locale>` lines | `tools/locale/*.json` |

Text the player reads goes through `ns.L["English"]` (or `L[...]`), never a bare string: the
translations are keyed by that English (`tools/locale/README.md`). Changing the English of a text
leaves its translations behind until they're redone for the new English; `translate.py status` and
`check <locale>` say which.

A dungeon entrance the game's tables don't have (a Dire Maul wing's own door, a second way in,
WoW Forever's new dungeons): stand in the portal in game and type `/openmap entrance <name>`, with
the name as `build.py` lists it (`Dire Maul - East`, `The Hall of Thanes`). It prints the line (and
keeps it in `OpenMapDB`, `worldmap.entrances`); add it to `ENTRANCES` in `tools/map-data/build.py`
and rerun step 1.

Where the bosses are on the dungeon maps: the journals give most (17e). The rest are placed by
hand, in game or in the browser:
- In game, open the dungeon's map and type `/openmap bosses`: the bar names a boss, click where it
  is (right-click skips it, shift-click takes the last back; a drag pans). The places show at once
  and are kept in `OpenMapDB` (`worldmap.bossPlaced`); after a `/reload` or logging out,
  `bosses.py <cache> --import "<WoW folder>/_forever_/WTF/Account/<account>/SavedVariables/OpenMap.lua"`
  adds them to `bosses.json` and builds.
- In the browser: `python -P tools/map-dungeons/editor.py <cache> <WoW folder>`, then
  http://127.0.0.1:8765/. Pick a dungeon, a boss, and click where it is (or drag its pin); Save &
  build. Its Minimap floors panel sets up a dungeon's map from the minimap pictures (17d): its rooms
  by height, a height range per floor, terrain or not, a preview of each, Save & build.

`gapfill.py --rerender` re-renders the zones (slow) after anything that changes them
(steps 5, 7, 8, 11), and so does `--bake-zones` (step 15: the zones' art as the map draws it,
baked into tiles; `OPENMAP_BAKED=1` renders from those tiles, to compare). Each texture in `OpenMap/Media/Textures/<client>` is listed in its
`NOTICE.md` with the script that makes it: add a line when you add a texture.

Hand edits of Blizzard's art (names painted out) live in `art/edits/`
(see its README). Nothing in the repo is drawn or written by a generator: art is
Blizzard's, cut, masked or hand-edited; facts come from the game's tables or a cited source.

## WoW pitfalls (each of these has bitten this project)

- **Texture paths need two backslashes** in Lua strings: `TEX .. "MapGapLand\\" .. id`. One
  is dropped silently, or (`"\947"`) is a load error. `lint.py` checks.
- **Secret values**: on this client some values (combat, sometimes positions) are secret.
  Never compare, do arithmetic on or nil-test one: read through `ns.Safe`.
- **Lua 5.1**: `a and f()` keeps only `f`'s first return value.
- **Blend modes**: `MOD` multiplies opacity too (the map turns see-through); masks
  (`MaskTexture`) and plain blends instead.
- **A region at alpha 0 still costs its full size to draw**: hide it (`Fade` in Stitch.lua).
- **Order of setup** in `WorldMap.lua` matters (the menu holds Nav's search box, so Nav
  first). Each step of `Close.lua`'s view update is isolated (`Try`), so one failure
  doesn't take the rest down; failures show in `/openmap status`.
- **Taint**: never write to Blizzard's layout tables or call protected functions; hook
  with `hooksecurefunc` or a data provider. Map switching waits out combat.
- **Textures**: plain 32-bit TGA (no RLE), power-of-two sizes; new files need a restart.

## Performance rules

The map draws thousands of regions; the frame rate depends on how few are live.

- Place once, in world units on the root frame; `Layout` only rescales the root.
- Work once per frame at most: Blizzard reports pans several times a frame
  (`viewFrame` in WorldMap.lua coalesces them).
- Hide what isn't seen: faded layers (`Fade`), zones and gap art off the view
  (`S.Cull`), pins by world cell (`PinCell`). Skip tiles a mask leaves nothing of.
- Build lazily: pin sets with `build`, the blur's copies, names, all on first show.
- Measure: `/openmap status` (frame rate, drawn textures, close-up update time).

## Commits and pull requests

- Small, focused commits; the message says what changed and why, in the imperative
  ("Hide icons off the view"). Keep generated output in the same commit as the change to
  its script.
- A pull request: what and why, before / after renders for anything visual, and the
  checklist in the template. CI (lint and load tests) must pass.
- Versions follow `vMAJOR.MINOR.PATCH`, with `-beta` / `-alpha` for pre-releases
  ([releasing.md](releasing.md)). Note user-visible changes under "Unreleased" in
  [CHANGELOG.md](../CHANGELOG.md) (WoW Forever) and/or [CHANGELOG-retail.md](../CHANGELOG-retail.md),
  as the change reaches each.
