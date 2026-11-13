# Reads files by file ID straight from the game's own install (its CASC storage, the Data
# folder beside the game's folders), so the tools needn't fetch them from wago.tools. Only
# what the tools need: local storage, the encoding and root tables, and BLTE's plain and
# zlib chunks (map textures aren't encrypted).
#
#   python -P tools/casc/casc.py <World of Warcraft folder> <file ID> <out file> [product]
#   product: the install's product in .build.info (WoW Forever's is wowf; it was wow_classic_beta,
#   and either name finds whichever the install has)
#
# From the tools: Casc(folder, product).read(fid) -> bytes (KeyError: not in this install).
# The install is whatever build the launcher last updated it to, which can be newer than
# the build the tools' tables name.
import bisect, os, struct, sys, zlib

# WoW Forever's product was renamed (wow_classic_beta, then wowf): either name finds the install
RENAMED = {"wowf": ("wow_classic_beta",), "wow_classic_beta": ("wowf",)}

import numpy as np

LOCALE_ENUS = 0x2
LOCALES = {"enUS": 0x2, "koKR": 0x4, "frFR": 0x10, "deDE": 0x20, "zhCN": 0x40, "esES": 0x80,
           "zhTW": 0x100, "enGB": 0x200, "esMX": 0x1000, "ruRU": 0x2000, "ptBR": 0x4000, "itIT": 0x8000}
NO_NAMES = 0x10000000           # root block content flag: no name hashes stored


class Encrypted(Exception):
    pass


def blte(data):
    """a BLTE-encoded blob, decoded"""
    if data[:4] != b"BLTE":
        raise ValueError("not BLTE")
    header = struct.unpack_from(">I", data, 4)[0]
    if header == 0:
        chunks, pos = [len(data) - 8], 8
    else:
        count = int.from_bytes(data[9:12], "big")
        chunks = [struct.unpack_from(">I", data, 12 + i * 24)[0] for i in range(count)]
        pos = header
    out = bytearray()
    for size in chunks:
        c = data[pos:pos + size]
        pos += size
        mode = c[:1]
        if mode == b"N":
            out += c[1:]
        elif mode == b"Z":
            out += zlib.decompress(c[1:])
        elif mode == b"E":
            raise Encrypted("encrypted chunk")
        else:
            raise ValueError("BLTE chunk mode %r" % mode)
    return bytes(out)


class Casc:
    def __init__(self, folder, product="wowf"):
        self.data = os.path.join(folder, "Data")
        cfg = self._config(self._build_key(folder, product))
        self._indices()
        self._encoding(blte(self._read_ekey(bytes.fromhex(cfg["encoding"].split()[1]))))
        self._root(self.read_ckey(bytes.fromhex(cfg["root"].split()[0])))

    # --- the install's build: .build.info, then its build config
    @staticmethod
    def _build_key(folder, product):
        lines = open(os.path.join(folder, ".build.info"), encoding="utf-8").read().splitlines()
        names = [h.split("!")[0] for h in lines[0].split("|")]
        rows = [dict(zip(names, line.split("|"))) for line in lines[1:]]
        for name in (product,) + RENAMED.get(product, ()):
            for row in rows:
                if row.get("Product") == name and row.get("Active", "1") == "1":
                    return row["Build Key"]
        raise KeyError("no product %s in .build.info" % product)

    def _config(self, key):
        p = os.path.join(self.data, "config", key[0:2], key[2:4], key)
        out = {}
        for line in open(p, encoding="utf-8"):
            if " = " in line:
                k, v = line.split(" = ", 1)
                out[k.strip()] = v.strip()
        return out

    # --- where each encoded file is: the newest .idx of each bucket (key: the encoded key's first 9 bytes)
    def _indices(self):
        newest = {}
        d = os.path.join(self.data, "data")
        for f in os.listdir(d):
            if f.endswith(".idx") and len(f) == 14:
                bucket, version = f[:2], int(f[2:10], 16)
                if version >= newest.get(bucket, (-1, ""))[0]:
                    newest[bucket] = (version, f)
        self.index = {}
        for _, f in newest.values():
            b = open(os.path.join(d, f), "rb").read()
            hsize = struct.unpack_from("<I", b, 0)[0]
            _, _, _, size_len, off_len, key_len, off_bits = struct.unpack_from("<HBBBBBB", b, 8)
            pos = (8 + hsize + 15) & ~15
            length = struct.unpack_from("<I", b, pos)[0]
            pos += 8
            n = key_len + off_len + size_len
            mask = (1 << off_bits) - 1
            for i in range(pos, pos + length - n + 1, n):
                key = b[i:i + key_len]
                if key in self.index:
                    continue
                off = int.from_bytes(b[i + key_len:i + key_len + off_len], "big")
                size = int.from_bytes(b[i + key_len + off_len:i + n], "little")
                self.index[key] = (off >> off_bits, off & mask, size)

    def _read_ekey(self, ekey):
        archive, offset, size = self.index[ekey[:9]]
        with open(os.path.join(self.data, "data", "data.%03d" % archive), "rb") as f:
            f.seek(offset)
            return f.read(size)[30:]            # (each file's 30-byte local header)

    # --- content key -> encoded key: the encoding table's pages, searched by their first keys
    def _encoding(self, d):
        if d[:2] != b"EN":
            raise ValueError("not an encoding table")
        self.ck, self.ek = d[3], d[4]
        page_kb = struct.unpack_from(">H", d, 5)[0]
        pages = struct.unpack_from(">I", d, 9)[0]
        espec = struct.unpack_from(">I", d, 18)[0]
        pos = 22 + espec
        self.firsts = [d[pos + i * (self.ck + 16):pos + i * (self.ck + 16) + self.ck] for i in range(pages)]
        self.pages0 = pos + pages * (self.ck + 16)
        self.page = page_kb * 1024
        self.enc = d

    def ekey_of(self, ckey):
        i = bisect.bisect_right(self.firsts, ckey) - 1
        if i < 0:
            raise KeyError(ckey.hex())
        d, p = self.enc, self.pages0 + i * self.page
        end = p + self.page
        while p < end:
            n = d[p]
            if n == 0:
                break
            k = d[p + 6:p + 6 + self.ck]
            if k == ckey:
                return d[p + 6 + self.ck:p + 6 + self.ck + self.ek]
            p += 6 + self.ck + self.ek * n
        raise KeyError(ckey.hex())

    def read_ckey(self, ckey):
        return blte(self._read_ekey(self.ekey_of(ckey)))

    # --- file ID -> content key: the root table (enUS or every locale)
    def _root(self, d):
        fids, keys = [], []
        self._blocks = []                       # every block's IDs and locale mask (locales())
        if d[:4] == b"TSFM":
            hsize, version = struct.unpack_from("<II", d, 4)
            if hsize > 1000:                    # (the first form: no header size or version)
                hsize, version = 12, 0
            pos, named = hsize, True
        else:
            pos, version, named = 0, -1, True
        while pos + 12 <= len(d):
            num = struct.unpack_from("<I", d, pos)[0]
            if version == 2:
                locale, f1, f2 = struct.unpack_from("<III", d, pos + 4)
                flags = f1 | f2 | (d[pos + 16] << 17)
                pos += 17
            else:
                flags, locale = struct.unpack_from("<II", d, pos + 4)
                pos += 12
            deltas = np.frombuffer(d, "<i4", num, pos)
            pos += 4 * num
            ids = np.cumsum(deltas.astype(np.int64) + 1) - 1
            if version >= 0:
                ck = np.frombuffer(d, np.uint8, num * 16, pos).reshape(num, 16)
                pos += 16 * num
                if not flags & NO_NAMES:
                    pos += 8 * num
            else:                               # (before 8.2: key and name hash side by side)
                rec = np.frombuffer(d, np.uint8, num * 24, pos).reshape(num, 24)
                ck = rec[:, :16]
                pos += 24 * num
            self._blocks.append((ids, locale))
            if locale & LOCALE_ENUS:
                fids.append(ids)
                keys.append(ck)
        fid = np.concatenate(fids)
        key = np.concatenate(keys)
        order = np.argsort(fid, kind="stable")      # (the first block's key for an ID wins)
        self.fids, self.keys = fid[order], key[order]

    def ckey_of(self, fid):
        i = int(np.searchsorted(self.fids, fid))
        if i >= len(self.fids) or self.fids[i] != fid:
            raise KeyError(fid)
        return bytes(self.keys[i])

    def read(self, fid):
        """the file with this file ID, decoded"""
        return self.read_ckey(self.ckey_of(fid))

    def locales(self, fid):
        """the locales the root lists this file ID for (LOCALES' names): the game client reads a
        file only through its own locale's entries, so one listed for enUS alone is missing on
        every other client"""
        if not hasattr(self, "_loc_ids"):
            ids = np.concatenate([b[0] for b in self._blocks])
            loc = np.concatenate([np.full(len(b[0]), b[1], np.uint32) for b in self._blocks])
            order = np.argsort(ids, kind="stable")
            self._loc_ids, self._loc = ids[order], loc[order]
        lo, hi = np.searchsorted(self._loc_ids, fid), np.searchsorted(self._loc_ids, fid, "right")
        mask = int(np.bitwise_or.reduce(self._loc[lo:hi])) if hi > lo else 0
        return [name for name, bit in LOCALES.items() if mask & bit]


if __name__ == "__main__":
    folder, fid, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    c = Casc(folder, sys.argv[4] if len(sys.argv) > 4 else "wowf")
    data = c.read(fid)
    open(out, "wb").write(data)
    print("wrote", out, len(data), "bytes")
