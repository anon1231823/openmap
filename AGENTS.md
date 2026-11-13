# Instructions for AI coding agents

These rules apply to any automated assistant working in this repository (and are a good
summary for people too). Read [docs/development.md](docs/development.md) for the full
workflow and [ARCHITECTURE.md](ARCHITECTURE.md) for how the map works.

## What this is

OpenMap: a seamless world map addon for WoW Forever (Lua 5.1 in the game's retail-engine
client, `## Interface: 16001`), plus Python tools that build its data and textures from
the game's own files. The addon is `OpenMap/`; everything else is tooling and docs.

## Hard rules

1. **True to the game.** The map stays true to the original game's art style and intent:
   the classic vanilla look and immersion come first. Art starts from Blizzard's, in the
   game files; edits to it (in `art/edits/`) only mend what's blurry or broken, and add no
   places, landmarks or detail the game's own maps don't have. Facts (place names,
   positions, levels) come from the game's tables or a source cited in the file. Interface
   text (option labels, tooltips) is fine. The one exception to Blizzard's art: maps of WoW
   Forever's own dungeons, which the game has none of, drawn by players who let OpenMap use
   them (`art/drawn/`), credited in game and in `NOTICE.md`.
2. **Generated files are generated.** Don't hand-edit anything a script writes (its first
   lines say which script). Change the script and rerun it, and commit both together.
3. **Blizzard's art stays credited.** A new texture gets a line in
   its client's `OpenMap/Media/Textures/<client>/NOTICE.md` (what it's cut from, which script makes it).
4. **Only MIT-compatible contributions.** Don't copy code, data or art from other addons
   unless their licence allows it under MIT (many map addons are "all rights reserved").
5. **No secrets, no personal data** in the repo: no API keys, tokens, real names, emails
   or local paths. Release credentials live in GitHub Actions secrets only.
   Never push a tag or start a CurseForge upload without the maintainer's go-ahead for that release
   (docs/releasing.md).
6. **Don't weaken CI or the checks** (`tools/offline-test`) to make a change pass.

## Verify every change

```bash
python -P tools/offline-test/lint.py
python tools/offline-test/run.py plain
python tools/offline-test/run.py combat
python tools/offline-test/run.py secret
python tools/offline-test/run.py pad
python tools/offline-test/run.py padmap
python tools/offline-test/run.py padview
python tools/offline-test/navigation.py
python -P tools/offline-test/combat.py
python -P tools/offline-test/caves.py
python -P tools/offline-test/explored.py
python -P tools/offline-test/chart.py
python -P tools/offline-test/friends.py
python -P tools/offline-test/questie.py
python -P tools/offline-test/bosses.py
```

All must pass, and the first eight again with `OPENMAP_CLIENT=retail` (retail's toc: one branch holds
every client, docs/development.md#clients). For anything visual, render before and after with
`tools/map-preview/render.py` and look at the images; keep render.py's mirrors of
Stitch.lua's constants in step. You can't run the game: say plainly what still needs an
in-game check (textures need a full client restart), and don't claim it works in game.

## Things that break silently here

- Single backslashes in texture paths (`"Map\947"`): use `"Map\\947"`. Lint catches it.
- Secret values: never compare, do arithmetic on or nil-test them; use `ns.Safe`.
- `a and f()` drops `f`'s extra return values (Lua 5.1).
- Writing to Blizzard's frames' layout tables, or calling protected functions: taint.
- The `MOD` blend mode makes the map see-through.
- A region at alpha 0 still costs its full size to draw: hide it.
- When scripting edits, write the script to a file rather than a shell heredoc: shell
  quoting mangles Lua and regex backslashes.

## Style

Match the surrounding code: tabs in Lua, short comments that say why (not what), plain
names, no new dependencies without a reason. Text the player reads goes through `ns.L["..."]`
(it's translated: `tools/locale/README.md`); a new or changed text needs its translations too. Keep changes focused; no drive-by
reformatting. Docs are plain and specific: say what a thing does, not how great it is.
