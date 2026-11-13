# A page in your browser for setting up OpenMap's dungeon maps: each dungeon's floors as the addon
# shows them (Blizzard's maps from the install, the drawn ones, the ones built from the game's
# minimap pictures), its bosses pinned where Data/DungeonBosses.lua has them, and places to set by
# hand: pick a boss, click where it is on its floor (or drag a pin there). Save writes them to
# bosses.json beside this script, with where each came from; Build runs bosses.py, which turns
# bosses.json and the journals into Data/Forever/DungeonBosses.lua (then /reload in game).
# The in-game placer (/openmap bosses) does the same from inside the game; bosses.py --import brings
# its places in, and they show here too.
# Minimap floors: for a dungeon whose files the install can read, its map built from the game's
# minimap pictures (minimap.py): its rooms by height, the floors to cut them into (a height range
# each, its terrain or not), a preview of each; Save & build writes minimap.json and runs minimap.py,
# then bosses.py.
#
# usage: python -P tools/map-dungeons/editor.py <cache dir> [World of Warcraft folder] [--port 8765]
#   (the cache dir is bosses.py's; the World of Warcraft folder, or OPENMAP_WOW, is where Blizzard's
#   maps are read from, else they're left grey). Only on this computer: http://127.0.0.1:<port>/
import io, json, os, subprocess, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(ROOT, "tools", "casc"))
import clients

sys.path.insert(0, HERE)
DATA = clients.data("forever")
TEX = clients.tex("forever")
PLACED = os.path.join(HERE, "bosses.json")
PIC_W, PIC_H = 1002, 668
FILES = ("Places.lua", "DungeonMaps.lua", "DungeonDrawn.lua", "DungeonMinimap.lua", "DungeonBosses.lua")


def read_data():
    """the addon's own tables, run as Lua (lupa, the offline tests'): {name: table}"""
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    ns = lua.eval("{ Media = { tex = 'TEX:' } }")
    run = lua.eval("function(src, ns) return assert(loadstring(src))('OpenMap', ns) end")
    for name in FILES:
        p = os.path.join(DATA, name)
        if os.path.exists(p):
            run(open(p, encoding="utf-8").read(), ns)

    def py(v):
        if lupa_type(v) == "table":
            keys = list(v.keys())
            if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
                return [py(v[k]) for k in sorted(keys)]
            return {(k if isinstance(k, int) else str(k)): py(v[k]) for k in keys}
        return v
    from lupa.lua51 import lua_type as lupa_type
    return {k: py(ns[k]) or {} for k in ("MapPlaces", "MapDungeonMaps", "MapDungeonDrawn", "MapDungeonMinimap", "MapDungeonBosses")}


def load_placed():
    return json.load(open(PLACED, encoding="utf-8")) if os.path.exists(PLACED) else {}


def save_placed(placed):
    order = lambda kv: (not kv[0].isdigit(), int(kv[0]) if kv[0].isdigit() else 0, kv[0])
    out = {k: dict(sorted(v.items())) for k, v in sorted(placed.items(), key=order) if v}
    with open(PLACED, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
        fh.write("\n")


class State:
    def __init__(self, cache, wow):
        self.cache, self.wow, self.casc, self.pics, self.dungeons_mm = cache, wow, None, {}, {}
        self.lock = threading.Lock()
        self.reload()

    def reload(self):
        self.data = read_data()
        self.pics.clear()

    def floors(self, key):
        """(kind, floors) as Dungeons.lua's FloorsOf picks them: Blizzard's, the drawn, the minimap's;
        "minimap:<mapID>": the one built from the minimap pictures"""
        if isinstance(key, str) and key.startswith("minimap:"):
            m = self.data["MapDungeonMinimap"].get(int(key[8:]))
            return ("minimap", m) if m else (None, [])
        for kind, t in (("blizzard", self.data["MapDungeonMaps"]), ("drawn", self.data["MapDungeonDrawn"]),
                        ("minimap", self.data["MapDungeonMinimap"])):
            if key in t: return kind, t[key]
        return None, []

    def dungeons(self):
        places = self.data["MapPlaces"]
        names, order = {}, []
        groups = places.get("instances", [])
        groups = groups if isinstance(groups, list) else list(groups.values())
        for g in groups + [{4: [u]} for u in places.get("unplaced", [])]:
            insts = g[3] if isinstance(g, list) else g.get(4, [])   # (a spot on a zone's map has no continent: a dict)
            for inst in insts:
                key = inst[0] or inst[1]
                if key not in names:
                    names[key] = inst[1]
                    order.append(key)
        placed = load_placed()
        out = []
        for key in list(order):             # (a map built from the minimap pictures: beside its other one)
            if isinstance(key, int) and key in self.data["MapDungeonMinimap"] and key in self.data["MapDungeonMaps"] | self.data["MapDungeonDrawn"]:
                order.insert(order.index(key) + 1, "minimap:%d" % key)
                names["minimap:%d" % key] = names[key] + " (minimap)"
        for key in order:
            kind, fl = self.floors(key)
            base = int(key[8:]) if isinstance(key, str) and key.startswith("minimap:") else key
            bosses = list((places.get("bosses", {}).get(base) or [])) if isinstance(base, int) else []
            hand = placed.get(str(key), {})
            shipped = self.data["MapDungeonBosses"].get(key, {})
            for n in list(hand) + list(shipped):
                if n not in bosses: bosses.append(n)
            pins = {}
            for n in bosses:
                if n in hand: pins[n] = dict(hand[n], where="bosses.json")
                elif n in shipped:
                    p = shipped[n]
                    pins[n] = {"floor": p[0], "x": p[1], "y": p[2], "where": "the journals"}
            out.append({"key": key, "name": names[key], "kind": kind,
                        "floors": [f.get("name") or f.get("credit") and ("Map by " + f["credit"]) or "" for f in fl],
                        "bosses": bosses, "pins": pins})
        return out

    def picture(self, key, n):
        """a floor's picture as PNG bytes (1002 x 668)"""
        from PIL import Image
        ck = (key, n)
        if ck in self.pics: return self.pics[ck]
        kind, fl = self.floors(key)
        im = Image.new("RGB", (1024, 768), (60, 60, 60))
        if 1 <= n <= len(fl):
            for i, t in enumerate(fl[n - 1]["tiles"]):
                tile = self.tile(t)
                if tile: im.paste(tile.convert("RGB"), ((i % 4) * 256, (i // 4) * 256))
        buf = io.BytesIO()
        im.crop((0, 0, PIC_W, PIC_H)).save(buf, "PNG")
        self.pics[ck] = buf.getvalue()
        return self.pics[ck]

    def minimap(self, mid):
        """minimap.py's Dungeon for an instance map (its rooms), kept; or an error's words"""
        import minimap
        if mid not in self.dungeons_mm:
            if not self.wow: return "no World of Warcraft folder given"
            try:
                self.dungeons_mm[mid] = minimap.load(self.cache, self.wow, mid)
            except SystemExit as e:
                self.dungeons_mm[mid] = str(e)
        return self.dungeons_mm[mid]

    def minimap_info(self, mid):
        import minimap
        d = self.minimap(mid)
        config = json.load(open(minimap.CONFIG, encoding="utf-8")) if os.path.exists(minimap.CONFIG) else {}
        if isinstance(d, str): return {"error": d, "config": config.get(str(mid))}
        return {"terrain_tiles": len(d.tiles), "groups": d.survey(), "config": config.get(str(mid))}

    def minimap_preview(self, mid, floor):
        import minimap
        d = self.minimap(mid)
        if isinstance(d, str): raise ValueError(d)
        img, rect = d.draw(floor, px=1)
        page, _ = minimap.page_of(img, rect)
        buf = io.BytesIO()
        page.crop((0, 0, PIC_W, PIC_H)).save(buf, "PNG")
        return buf.getvalue()

    def tile(self, t):
        from PIL import Image
        if isinstance(t, str) and t.startswith("TEX:"):     # (one of OpenMap's own textures)
            rel = t[4:].replace("\\", os.sep)
            for ext in (".tga", ".png", ".blp"):
                p = os.path.join(TEX, rel + ext)
                if os.path.exists(p): return Image.open(p)
            return None
        if not self.wow: return None
        try:
            if not self.casc:
                from casc import Casc
                self.casc = Casc(self.wow, clients.CLIENTS["forever"]["product"])
            return Image.open(io.BytesIO(self.casc.read(int(t))))
        except Exception:
            return None


PAGE = r"""<!doctype html>
<html><head><meta charset="utf-8"><title>OpenMap dungeon editor</title>
<style>
:root { color-scheme: dark; --bg:#1b1712; --panel:#26201a; --line:#4a3d2e; --gold:#ffd100; --text:#e8dcc4; --dim:#9b8b70; }
* { box-sizing: border-box; }
[hidden] { display:none !important; }
body { margin:0; background:var(--bg); color:var(--text); font:14px/1.4 system-ui, sans-serif; display:flex; height:100vh; }
#list { width:260px; overflow:auto; border-right:1px solid var(--line); background:var(--panel); }
#list div { padding:6px 10px; cursor:pointer; display:flex; justify-content:space-between; gap:6px; }
#list div:hover { background:#332a20; } #list div.on { background:#463826; color:var(--gold); }
#list .n { color:var(--dim); font-size:12px; white-space:nowrap; }
#main { flex:1; display:flex; flex-direction:column; min-width:0; }
#bar { padding:8px 12px; border-bottom:1px solid var(--line); display:flex; gap:8px; align-items:center; flex-wrap:wrap; }
#bar h1 { font-size:16px; margin:0 12px 0 0; color:var(--gold); }
button { background:#3a2f22; color:var(--text); border:1px solid var(--line); border-radius:4px; padding:4px 10px; cursor:pointer; }
button:hover { border-color:var(--gold); } button.on { background:#5a4526; color:var(--gold); }
#work { flex:1; display:flex; min-height:0; }
#stage { flex:1; overflow:auto; position:relative; padding:12px; }
#pic { position:relative; max-width:1002px; cursor:crosshair; user-select:none; }
#pic img { display:block; width:100%; }
.pin { position:absolute; width:24px; height:24px; margin:-12px 0 0 -12px; border-radius:50%; background:#b3261e;
  border:2px solid #ffcf6a; color:#fff; font:bold 12px/20px system-ui; text-align:center; cursor:grab; }
.pin.hand { background:#2a6db3; } .pin.sel { box-shadow:0 0 0 4px var(--gold); }
.pin span { position:absolute; left:26px; top:2px; white-space:nowrap; font-weight:normal; text-shadow:0 0 3px #000, 0 0 3px #000; }
#side { width:300px; overflow:auto; border-left:1px solid var(--line); background:var(--panel); padding:8px; }
#side .b { padding:5px 6px; border-radius:4px; cursor:pointer; display:flex; gap:6px; }
#side .b:hover { background:#332a20; } #side .b.sel { background:#463826; }
#side .b .w { color:var(--dim); font-size:12px; margin-left:auto; text-align:right; }
#side .b button { padding:0 6px; font-size:12px; }
#msg { color:var(--dim); font-size:12px; margin-left:auto; }
pre { white-space:pre-wrap; font-size:12px; color:var(--dim); }
#mm { flex:1; overflow:auto; padding:12px; }
#mm .f { border:1px solid var(--line); border-radius:6px; padding:8px; margin:0 0 10px; }
#mm .f input[type=text] { width:200px; } #mm .f input[type=number] { width:80px; }
#mm input { background:#15110d; color:var(--text); border:1px solid var(--line); border-radius:3px; padding:2px 4px; }
#mm img { display:block; max-width:700px; width:100%; margin-top:6px; background:#000; }
#mmrooms { color:var(--dim); font-size:12px; margin-top:12px; }
.help { color:var(--dim); font-size:12px; margin:4px 0 10px; }
</style></head><body>
<div id="list"></div>
<div id="main">
 <div id="bar"><h1 id="title">Pick a dungeon</h1><span id="floors"></span>
  <button id="labels">Names</button><button id="save">Save</button><button id="build">Save &amp; build data</button>
  <button id="mmtab">Minimap floors</button><span id="msg"></span></div>
 <div id="mm" hidden><div class="help" id="mmhelp"></div><div id="mmfloors"></div>
  <button id="mmadd">Add floor</button> <button id="mmsave">Save &amp; build minimap maps</button> <span id="mmmsg"></span>
  <div id="mmrooms"></div></div>
 <div id="work"><div id="stage"><div id="pic"></div></div>
  <div id="side"><div class="help">Pick a boss, then click where it is on its floor. Drag a pin to move it.
  Blue pins are set by hand (bosses.json), red ones come from the journals. Save keeps them; build turns them into
  Data/Forever/DungeonBosses.lua.</div><div id="bosses"></div><pre id="out"></pre></div></div>
</div>
<script>
let all = [], cur = null, floor = 1, sel = null, dirty = {}, names = true;
const $ = id => document.getElementById(id);
async function load() {
  all = await (await fetch('/api/dungeons')).json();
  renderList();
  if (cur) pick(all.find(d => String(d.key) === String(cur.key)) || all[0], true);
}
function counts(d) { const n = d.bosses.length, p = Object.keys(d.pins).length; return n ? p + '/' + n : '' }
function renderList() {
  $('list').innerHTML = '';
  for (const d of all) {
    const el = document.createElement('div');
    el.className = cur && String(cur.key) === String(d.key) ? 'on' : '';
    el.innerHTML = `<span>${esc(d.name)}</span><span class="n">${d.kind ? counts(d) : 'no map'}</span>`;
    el.onclick = () => pick(d);
    $('list').appendChild(el);
  }
}
function esc(s) { return String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])) }
function pick(d, keepFloor) {
  cur = d; if (!keepFloor) { floor = 1; sel = d.bosses.find(n => !d.pins[n]) || null; }
  $('title').textContent = d.name + (!d.kind ? '  (no map yet)' : String(d.key).startsWith('minimap:') ? '' : '  (' + d.kind + ')');
  $('floors').innerHTML = '';
  d.floors.forEach((f, i) => {
    const b = document.createElement('button');
    b.textContent = (i + 1) + (f ? ': ' + f : ''); b.className = i + 1 === floor ? 'on' : '';
    b.onclick = () => { floor = i + 1; pick(cur, true); };
    $('floors').appendChild(b);
  });
  renderList(); renderPic(); renderBosses();
}
function renderPic() {
  const pic = $('pic'); pic.innerHTML = '';
  if (!cur || !cur.kind) { pic.textContent = 'No map of this dungeon to place bosses on yet.'; return; }
  const img = new Image(); img.src = `/api/floor/${encodeURIComponent(cur.key)}/${floor}.png`; img.draggable = false;
  pic.appendChild(img);
  pic.onclick = e => {
    if (e.target !== img || !sel) return;
    const r = img.getBoundingClientRect();
    setPin(sel, (e.clientX - r.left) / r.width, (e.clientY - r.top) / r.height);
    const next = cur.bosses.slice(cur.bosses.indexOf(sel) + 1).find(n => !cur.pins[n]);
    sel = next || sel; renderPic(); renderBosses();
  };
  cur.bosses.forEach((n, i) => {
    const p = cur.pins[n]; if (!p || p.floor !== floor) return;
    const el = document.createElement('div');
    el.className = 'pin' + (p.where === 'bosses.json' ? ' hand' : '') + (n === sel ? ' sel' : '');
    el.style.left = (p.x * 100) + '%'; el.style.top = (p.y * 100) + '%';
    el.innerHTML = (i + 1) + (names ? `<span>${esc(n)}</span>` : '');
    el.title = n + ' — ' + p.where + (p.source ? ' (' + p.source + ')' : '');
    el.onmousedown = e => drag(e, n, img);
    pic.appendChild(el);
  });
}
function setPin(n, x, y) {
  x = Math.min(1, Math.max(0, x)); y = Math.min(1, Math.max(0, y));
  cur.pins[n] = { floor, x: +x.toFixed(4), y: +y.toFixed(4), where: 'bosses.json', source: 'placed in the editor' };
  (dirty[cur.key] = dirty[cur.key] || {})[n] = cur.pins[n];
  $('msg').textContent = 'not saved';
}
function drag(e, n, img) {
  e.preventDefault(); e.stopPropagation(); sel = n;
  const r = img.getBoundingClientRect(); let moved = false;
  const move = ev => { moved = true; setPin(n, (ev.clientX - r.left) / r.width, (ev.clientY - r.top) / r.height); renderPic(); };
  const up = () => { removeEventListener('mousemove', move); removeEventListener('mouseup', up); renderBosses(); if (!moved) renderPic(); };
  addEventListener('mousemove', move); addEventListener('mouseup', up);
}
function renderBosses() {
  const box = $('bosses'); box.innerHTML = '';
  if (!cur) return;
  if (!cur.bosses.length) box.textContent = 'The game lists no bosses for it.';
  cur.bosses.forEach((n, i) => {
    const p = cur.pins[n], el = document.createElement('div');
    el.className = 'b' + (n === sel ? ' sel' : '');
    el.innerHTML = `<b>${i + 1}.</b> ${esc(n)} <span class="w">${p ? 'floor ' + p.floor + '<br>' + esc(p.where) : 'not placed'}</span>`;
    if (p && p.where === 'bosses.json') {
      const x = document.createElement('button'); x.textContent = '×'; x.title = 'Take this place out of bosses.json';
      x.onclick = ev => { ev.stopPropagation(); delete cur.pins[n]; (dirty[cur.key] = dirty[cur.key] || {})[n] = null; $('msg').textContent = 'not saved'; renderPic(); renderBosses(); };
      el.appendChild(x);
    }
    el.onclick = () => { sel = n; if (p && p.floor !== floor) { floor = p.floor; pick(cur, true); } else { renderPic(); renderBosses(); } };
    box.appendChild(el);
  });
}
async function save() {
  const r = await fetch('/api/bosses', { method: 'POST', body: JSON.stringify(dirty) });
  if (!r.ok) { $('msg').textContent = 'save failed: ' + await r.text(); return false; }
  dirty = {}; $('msg').textContent = 'saved to bosses.json'; return true;
}
$('save').onclick = save;
$('build').onclick = async () => {
  if (!await save()) return;
  $('msg').textContent = 'building…';
  const r = await (await fetch('/api/build', { method: 'POST' })).json();
  $('out').textContent = r.output; $('msg').textContent = r.ok ? 'built: /reload in game' : 'build failed';
  await load();
};
$('labels').onclick = () => { names = !names; $('labels').className = names ? 'on' : ''; renderPic(); };
// minimap floors: the dungeon's rooms by height, the floors to cut them into, a preview of each
let mm = null;
function baseKey() { const k = String(cur.key); return k.startsWith('minimap:') ? +k.slice(8) : cur.key; }
$('mmtab').onclick = async () => {
  if (!cur) return;
  const show = $('mm').hidden; $('mm').hidden = !show; $('work').hidden = show; $('mmtab').className = show ? 'on' : '';
  if (!show) return;
  if (typeof baseKey() !== 'number') { $('mmhelp').textContent = 'This dungeon has no map ID in the tables yet: its files can\'t be found.'; return; }
  $('mmhelp').textContent = 'Reading the dungeon\'s rooms from the install…'; $('mmfloors').innerHTML = ''; $('mmrooms').innerHTML = '';
  mm = await (await fetch('/api/minimap/' + baseKey())).json();
  if (mm.error) { $('mmhelp').textContent = mm.error; return; }
  mm.floors = (mm.config && mm.config.floors) || [];
  $('mmhelp').textContent = `${mm.groups.length} rooms with minimap pictures, ${mm.terrain_tiles} terrain tiles. ` +
    'Cut them into floors by height (a room is on a floor when its floor height is in the range); tick terrain for a dungeon that\'s outdoors. ' +
    'Floors that share a crop line up when you page between them.';
  const zs = mm.groups.map(g => Math.round(g.z0)); const bins = {};
  zs.forEach(z => { const b = Math.floor(z / 10) * 10; bins[b] = (bins[b] || 0) + 1; });
  $('mmrooms').textContent = 'Rooms by floor height (yards: count): ' + Object.keys(bins).map(Number).sort((a, b) => a - b).map(b => b + ': ' + bins[b]).join(',  ');
  renderFloors();
};
function renderFloors() {
  const box = $('mmfloors'); box.innerHTML = '';
  mm.floors.forEach((f, i) => {
    const el = document.createElement('div'); el.className = 'f';
    const z = f.z || ['', ''];
    el.innerHTML = `<b>Floor ${i + 1}</b> name <input type="text" value="${esc(f.name || '')}" data-k="name">
      height from <input type="number" value="${z[0]}" data-k="z0"> to <input type="number" value="${z[1]}" data-k="z1">
      <label><input type="checkbox" ${f.terrain ? 'checked' : ''} data-k="terrain"> terrain</label>
      crop <input type="text" value="${f.rect ? f.rect.join(', ') : ''}" placeholder="auto: its rooms" data-k="rect">
      <button data-a="up">↑</button> <button data-a="del">Remove</button> <button data-a="prev">Preview</button><img hidden>`;
    el.querySelectorAll('input').forEach(inp => inp.onchange = () => {
      const k = inp.dataset.k;
      if (k === 'name') f.name = inp.value;
      if (k === 'terrain') f.terrain = inp.checked;
      if (k === 'z0' || k === 'z1') {
        const a = el.querySelector('[data-k=z0]').value, b = el.querySelector('[data-k=z1]').value;
        if (a === '' && b === '') delete f.z; else f.z = [a === '' ? -9999 : +a, b === '' ? 9999 : +b];
      }
      if (k === 'rect') { const v = inp.value.split(',').map(x => parseFloat(x)).filter(x => !isNaN(x)); if (v.length === 4) f.rect = v; else delete f.rect; }
    });
    el.querySelector('[data-a=del]').onclick = () => { mm.floors.splice(i, 1); renderFloors(); };
    el.querySelector('[data-a=up]').onclick = () => { if (i) { mm.floors.splice(i - 1, 0, mm.floors.splice(i, 1)[0]); renderFloors(); } };
    el.querySelector('[data-a=prev]').onclick = async () => {
      const img = el.querySelector('img'); img.hidden = false; img.alt = 'drawing…';
      const r = await fetch('/api/minimap/' + baseKey() + '/preview', { method: 'POST', body: JSON.stringify(f) });
      if (r.ok) img.src = URL.createObjectURL(await r.blob()); else img.alt = await r.text();
    };
    box.appendChild(el);
  });
}
$('mmadd').onclick = () => { mm.floors.push({ name: '' }); renderFloors(); };
$('mmsave').onclick = async () => {
  $('mmmsg').textContent = 'building… (a minute or two)';
  const r = await fetch('/api/minimap/' + baseKey(), { method: 'POST', body: JSON.stringify({ name: cur.name.replace(/ \(minimap\)$/, ''), floors: mm.floors }) });
  const out = await r.json(); $('out').textContent = out.output || ''; $('mmmsg').textContent = out.ok ? 'built: /reload in game' : 'build failed (see the output in the Bosses view)';
  await load();
};
$('labels').className = 'on';
addEventListener('beforeunload', e => { if (Object.keys(dirty).length) { e.preventDefault(); e.returnValue = ''; } });
load();
</script></body></html>
"""


def make_handler(state):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *a): pass

        def send(self, code, body, ctype="application/json"):
            if isinstance(body, str): body = body.encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            from urllib.parse import unquote
            path = self.path.split("?")[0]
            if path == "/":
                return self.send(200, PAGE, "text/html; charset=utf-8")
            if path == "/api/dungeons":
                with state.lock:
                    return self.send(200, json.dumps(state.dungeons()))
            if path.startswith("/api/minimap/"):
                with state.lock:
                    return self.send(200, json.dumps(state.minimap_info(int(path.rsplit("/", 1)[1]))))
            if path.startswith("/api/floor/"):
                key, n = unquote(path[len("/api/floor/"):]).rsplit("/", 1)
                key = int(key) if key.isdigit() else key
                with state.lock:
                    return self.send(200, state.picture(key, int(n.split(".")[0])), "image/png")
            self.send(404, "not found", "text/plain")

        def do_POST(self):
            if self.headers.get("Origin") not in (None, "http://127.0.0.1:%d" % self.server.server_port,
                                                  "http://localhost:%d" % self.server.server_port):
                return self.send(403, "only from this page", "text/plain")
            body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
            if self.path == "/api/bosses":
                try:
                    changes = json.loads(body or b"{}")
                    placed = load_placed()
                    for key, bosses in changes.items():
                        for name, p in bosses.items():
                            if p is None:
                                placed.get(str(key), {}).pop(name, None)
                            else:
                                placed.setdefault(str(key), {})[name] = {
                                    "floor": int(p["floor"]), "x": round(float(p["x"]), 4), "y": round(float(p["y"]), 4),
                                    "source": str(p.get("source") or "placed in the editor")}
                    save_placed(placed)
                except Exception as e:
                    return self.send(400, "bad request: %s" % e, "text/plain")
                return self.send(200, "{}")
            if self.path.startswith("/api/minimap/") and self.path.endswith("/preview"):
                try:
                    with state.lock:
                        png = state.minimap_preview(int(self.path.split("/")[3]), json.loads(body or b"{}"))
                except Exception as e:
                    return self.send(400, "couldn't draw it: %s" % e, "text/plain")
                return self.send(200, png, "image/png")
            if self.path.startswith("/api/minimap/"):
                import minimap
                mid = self.path.rsplit("/", 1)[1]
                try:
                    entry = json.loads(body or b"{}")
                    floors = [{k: f[k] for k in ("name", "z", "terrain", "rect", "groups") if f.get(k) not in (None, "", False)}
                              for f in entry.get("floors", [])]
                except Exception as e:
                    return self.send(400, "bad request: %s" % e, "text/plain")
                config = json.load(open(minimap.CONFIG, encoding="utf-8")) if os.path.exists(minimap.CONFIG) else {}
                if floors: config[mid] = {"name": entry.get("name", ""), "floors": floors}
                else: config.pop(mid, None)
                with open(minimap.CONFIG, "w", encoding="utf-8", newline="\n") as fh:
                    fh.write("{\n" + ",\n".join(" %s: %s" % (json.dumps(k), json.dumps(config[k], ensure_ascii=False))
                                                 for k in sorted(config, key=int)) + "\n}\n")
                out, ok = "", True
                for script, extra in (("minimap.py", [state.wow]), ("bosses.py", [])):
                    r = subprocess.run([sys.executable, "-P", os.path.join(HERE, script), state.cache] + extra,
                                       capture_output=True, text=True, encoding="utf-8", errors="replace")
                    out += r.stdout + r.stderr
                    ok = ok and r.returncode == 0
                with state.lock:
                    state.reload()
                return self.send(200, json.dumps({"ok": ok, "output": out[-6000:]}))
            if self.path == "/api/build":
                r = subprocess.run([sys.executable, "-P", os.path.join(HERE, "bosses.py"), state.cache],
                                   capture_output=True, text=True, encoding="utf-8", errors="replace")
                with state.lock:
                    state.reload()
                return self.send(200, json.dumps({"ok": r.returncode == 0, "output": (r.stdout + r.stderr)[-6000:]}))
            self.send(404, "not found", "text/plain")
    return Handler


def main():
    args = [a for a in sys.argv[1:]]
    port = 8765
    if "--port" in args:
        i = args.index("--port")
        port = int(args[i + 1])
        del args[i:i + 2]
    if not args:
        sys.exit("usage: python -P tools/map-dungeons/editor.py <cache dir> [World of Warcraft folder] [--port 8765]")
    cache = args[0]
    wow = args[1] if len(args) > 1 else os.environ.get("OPENMAP_WOW")
    state = State(cache, wow)
    server = ThreadingHTTPServer(("127.0.0.1", port), make_handler(state))
    print("OpenMap dungeon editor: http://127.0.0.1:%d/  (Ctrl+C to stop)" % port)
    if not wow: print("(no World of Warcraft folder given: Blizzard's maps show grey)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
