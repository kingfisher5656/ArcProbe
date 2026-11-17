#!/usr/bin/env python3
"""Rebuilds the bundled pack list from the Arcaea wiki (run before a release; the app also updates itself).

Usage: python3 scripts/update-bundled-packs.py [folder holding Packlist.json and Songlist.json]
Without a folder the two files are downloaded from arcaea.miraheze.org.
"""
import json, pathlib, sys, urllib.request

def load(name):
    if len(sys.argv) > 1:
        return json.loads((pathlib.Path(sys.argv[1]) / f"{name}.json").read_text(encoding="utf-8"))
    request = urllib.request.Request(f"https://arcaea.miraheze.org/wiki/Data:{name}.json?action=raw", headers={"User-Agent": "ArcProbe"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)

packs = [{"id": p["id"], "name": p["name_localized"]["en"], **({"section": p["section"]} if p.get("section") else {}),
          **({"parentID": p["pack_parent"]} if p.get("pack_parent") else {})} for p in load("Packlist")["packs"]]
songs = {s["id"]: s["set"] for s in load("Songlist")["songs"] if not s.get("deleted") and s.get("set")}
output = pathlib.Path(__file__).resolve().parent.parent / "Packages/ArcaeaCore/Sources/ArcaeaCore/Resources/pack-catalog.json"
output.write_text(json.dumps({"packs": packs, "songPacks": dict(sorted(songs.items()))}, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
print(f"Wrote {len(packs)} packs and {len(songs)} songs to {output}")
