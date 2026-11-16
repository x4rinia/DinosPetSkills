#!/usr/bin/env python3
"""
DinosPetSkills · Daten-Sync aus ForeverBestiaryPetHunter
=========================================================

ForeverBestiaryPetHunter (FBPH) haelt seine komplette Datenbank (Tierfamilien, Faehigkeiten + Raenge, alle
zaehmbaren Wildtiere mit Level/Zone/"Lehrt") in seinem *privaten* Addon-Namespace (`local _, ns = ...` ->
`ns.Data`). Ein anderes Addon kann zur Laufzeit nicht darauf zugreifen (kein globales Objekt).

Dieses Skript liest daher `ForeverBestiaryPetHunter/Data/Data.lua` (nur lesend, es wird nichts veraendert) und
erzeugt daraus eine schlanke Kopie `DinosPetSkills/Data/FBPH_Snapshot.lua` (ohne Koordinaten, Notizen usw.).

Aufruf (wenn FBPH ein Update bekommen hat):
    python tools/sync_from_fbph.py
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON_DIR = os.path.dirname(HERE)
FBPH_DATA = os.path.join(os.path.dirname(ADDON_DIR), "ForeverBestiaryPetHunter", "Data", "Data.lua")
FBPH_COMM = os.path.join(os.path.dirname(ADDON_DIR), "ForeverBestiaryPetHunter", "Data", "Community.lua")
OUT_FILE = os.path.join(ADDON_DIR, "Data", "FBPH_Snapshot.lua")


# --------------------------------------------------------------------------- minimal Lua table parser
class LuaParser:
    def __init__(self, src, pos=0):
        self.s = src
        self.i = pos

    def ws(self):
        s = self.s
        while self.i < len(s):
            c = s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif s.startswith("--", self.i):
                m = re.compile(r"--\[(=*)\[").match(s, self.i)
                if m:
                    end = s.find("]" + m.group(1) + "]", m.end())
                    self.i = len(s) if end < 0 else end + len(m.group(1)) + 2
                else:
                    end = s.find("\n", self.i)
                    self.i = len(s) if end < 0 else end + 1
            else:
                break

    def peek(self):
        self.ws()
        return self.s[self.i] if self.i < len(self.s) else ""

    def expect(self, ch):
        self.ws()
        if not self.s.startswith(ch, self.i):
            raise SyntaxError("expected %r at %d: %r" % (ch, self.i, self.s[self.i:self.i + 40]))
        self.i += len(ch)

    def string(self):
        q = self.s[self.i]
        self.i += 1
        out = bytearray()
        s = self.s
        while True:
            c = s[self.i]
            if c == q:
                self.i += 1
                break
            if c == "\\":
                n = s[self.i + 1]
                if n.isdigit():
                    m = re.compile(r"\d{1,3}").match(s, self.i + 1)
                    out.append(int(m.group(0)))
                    self.i = m.end()
                    continue
                out += {"n": b"\n", "t": b"\t", "r": b"\r", "\\": b"\\", '"': b'"', "'": b"'"}.get(n, n.encode("utf-8"))
                self.i += 2
                continue
            out += c.encode("utf-8")
            self.i += 1
        return out.decode("utf-8", errors="replace")

    def value(self):
        c = self.peek()
        if c == "{":
            return self.table()
        if c in "\"'":
            return self.string()
        m = re.compile(r"-?\d+(\.\d+)?([eE][-+]?\d+)?").match(self.s, self.i)
        if m:
            self.i = m.end()
            t = m.group(0)
            return float(t) if ("." in t or "e" in t.lower()) else int(t)
        m = re.compile(r"[A-Za-z_][A-Za-z0-9_]*").match(self.s, self.i)
        if m:
            self.i = m.end()
            w = m.group(0)
            return {"true": True, "false": False, "nil": None}.get(w, w)
        raise SyntaxError("unexpected %r at %d" % (self.s[self.i:self.i + 30], self.i))

    def table(self):
        self.expect("{")
        arr, hsh = [], {}
        while True:
            c = self.peek()
            if c == "}":
                self.i += 1
                break
            if c == "[":
                self.i += 1
                k = self.value()
                self.expect("]")
                self.expect("=")
                hsh[k] = self.value()
            else:
                m = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)").match(self.s, self.i)
                if m:
                    self.i = m.end()
                    hsh[m.group(1)] = self.value()
                else:
                    arr.append(self.value())
            c = self.peek()
            if c in ",;":
                self.i += 1
        if hsh:
            for n, v in enumerate(arr, 1):
                hsh[n] = v
            return hsh
        return arr


def parse_after(src, marker):
    pos = src.find(marker)
    if pos < 0:
        raise SystemExit("Marker %r nicht in Data.lua gefunden" % marker)
    return LuaParser(src, pos + len(marker)).table()


# --------------------------------------------------------------------------- Lua serialiser
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil",
            "not", "or", "repeat", "return", "then", "true", "until", "while"}


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "") + '"'


def lua_key(k):
    if isinstance(k, str) and IDENT.match(k) and k not in KEYWORDS:
        return k
    if isinstance(k, str):
        return "[" + lua_str(k) + "]"
    return "[" + str(k) + "]"


def lua_val(v, ind=0, inline=False):
    if v is None:
        return "nil"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, (int, float)):
        return repr(v) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return lua_str(v)
    pad = "  " * (ind + 1)
    if isinstance(v, list):
        items = [lua_val(x, ind + 1, ind >= 1) for x in v]
        if inline or all(not isinstance(x, (dict, list)) for x in v):
            return "{" + ", ".join(items) + "}"
        return "{\n" + "".join(pad + it + ",\n" for it in items) + "  " * ind + "}"
    if isinstance(v, dict):
        keys = sorted(v.keys(), key=lambda k: (0, k, "") if isinstance(k, int) else (1, 0, str(k)))
        parts = [lua_key(k) + "=" + lua_val(v[k], ind + 1, ind >= 1) for k in keys]
        if inline:
            return "{" + ", ".join(parts) + "}"
        return "{\n" + "".join(pad + p + ",\n" for p in parts) + "  " * ind + "}"
    raise TypeError(type(v))


# --------------------------------------------------------------------------- slim down
LANGS = ("en", "de", "es", "fr", "ru", "zh")


def slim(data, beasts, comm=None):
    obs = (comm or {}).get("obs", {})
    out = {"date": data.get("date"), "clientBuild": data.get("clientBuild"), "familyOrder": data.get("familyOrder", [])}
    fams = {}
    for slug, f in data.get("families", {}).items():
        e = {k: f[k] for k in ("en", "de", "icon") if k in f}
        e["abil"] = [a.get("n") for a in f.get("abil", []) if isinstance(a, dict) and a.get("n")]
        fams[slug] = e
    out["families"] = fams
    abil = {}
    for en, a in data.get("abilities", {}).items():
        e = {"en": en}
        for k in ("de", "es", "fr", "ru", "zh", "icon", "kind", "fams", "taught"):
            if k in a:
                e[k] = a[k]
        ranks = []
        for rk in a.get("ranks", []):
            r = {"r": rk.get("r")}
            for k in ("l", "id", "en", "de"):
                if rk.get(k) is not None:
                    r[k] = rk[k]
            ranks.append(r)
        e["ranks"] = ranks
        abil[en] = e
    out["abilities"] = abil
    out["zonesDE"] = data.get("zonesDE", {})
    slim_beasts = []
    seen_ids = set()
    for b in beasts:
        if not isinstance(b, dict) or not b.get("f"):
            continue
        bid = b.get("id")
        if bid:
            seen_ids.add(bid)
        o = obs.get(bid) if bid else None
        e = {k: b[k] for k in ("id", "en", "de", "f", "l1", "l2", "r", "cf") if b.get(k) is not None}
        if isinstance(o, dict) and isinstance(o.get("n"), dict):
            e.setdefault("en", o["n"].get("enUS") or o["n"].get("enGB"))
            e.setdefault("de", o["n"].get("deDE"))
        zones = []
        for z in b.get("z", []) or []:
            if isinstance(z, dict) and z.get("z"):
                zones.append({k: z[k] for k in ("z", "i", "sub") if z.get(k) is not None})
        if zones:
            e["z"] = zones
        teaches = [list(t[:3]) for t in (b.get("t") or []) if isinstance(t, list) and len(t) >= 2]
        have = {(t[0], t[1]) for t in teaches}
        if isinstance(o, dict) and isinstance(o.get("ab"), dict):
            for sk, rk in o["ab"].items():
                if sk not in ("Faster Attack", "Slower Attack") and (sk, rk) not in have:
                    teaches.append([sk, rk, "t"])
                    have.add((sk, rk))
        if teaches:
            e["t"] = teaches
        slim_beasts.append(e)
    # Wildtiere, die nur in Community.lua stehen und Fähigkeiten lehren
    for bid, o in sorted(obs.items(), key=lambda kv: kv[0] if isinstance(kv[0], int) else 0):
        if bid in seen_ids or not isinstance(o, dict) or not o.get("f") or not isinstance(o.get("ab"), dict):
            continue
        teaches = [[sk, rk, "t"] for sk, rk in o["ab"].items() if sk not in ("Faster Attack", "Slower Attack")]
        if not teaches:
            continue
        n = o.get("n") if isinstance(o.get("n"), dict) else {}
        e = {"id": bid, "f": o["f"], "cf": "community", "t": teaches}
        if n.get("enUS") or n.get("enGB"):
            e["en"] = n.get("enUS") or n.get("enGB")
        if n.get("deDE"):
            e["de"] = n["deDE"]
        for k in ("l1", "l2"):
            if o.get(k) is not None:
                e[k] = o[k]
        slim_beasts.append(e)
    out["beasts"] = slim_beasts
    return out


def main():
    if not os.path.isfile(FBPH_DATA):
        raise SystemExit("ForeverBestiaryPetHunter/Data/Data.lua nicht gefunden: " + FBPH_DATA)
    with open(FBPH_DATA, "r", encoding="utf-8") as fh:
        src = fh.read()
    data = parse_after(src, "ns.Data =")
    beasts = parse_after(src, "ns.Data.beasts =")
    comm = None
    if os.path.isfile(FBPH_COMM):
        with open(FBPH_COMM, "r", encoding="utf-8") as fh:
            comm = parse_after(fh.read(), "ns.Data.community =")
    snap = slim(data, beasts, comm)
    os.makedirs(os.path.dirname(OUT_FILE), exist_ok=True)
    with open(OUT_FILE, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("-- DinosPetSkills: automatisch erzeugt aus ForeverBestiaryPetHunter/Data/Data.lua\n")
        fh.write("-- (tools/sync_from_fbph.py). Nicht von Hand bearbeiten - bei FBPH-Updates das Skript erneut starten.\n")
        fh.write("local _, ns = ...\n")
        fh.write("ns.FBPH = " + lua_val(snap) + "\n")
    print("OK: %d Faehigkeiten, %d Familien, %d Wildtiere -> %s" % (
        len(snap["abilities"]), len(snap["families"]), len(snap["beasts"]), OUT_FILE))


if __name__ == "__main__":
    sys.exit(main())
