#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""tagsearch.py -- offline Danbooru tag search over danbooru-tags.jsonl

Usage:
  python tagsearch.py <keyword> [more keywords...] [--limit N] [--cat general]
                      [--exact] [--json] [--data PATH]

Searches tag name / Chinese translation / related tags (case-insensitive
substring).  Underscores and spaces are treated as equivalent, so
"fox ears" finds the tag fox_ears.  Multiple keywords are AND-ed; when that
yields nothing the search falls back to OR and says so.

Results are printed exact-name matches first, then by post count (n)
descending, each with a category marker:
  [G] general  [A] artist  [P] copyright  [C] character  [M] meta
  [S] species  [L] lore

Data file: <this dir>\nai-tags\danbooru-tags.jsonl  (override with --data PATH)

Record shape (one JSON object per line):
  {"t": "tag_name", "cn": "中文", "c": "general", "n": 12345,
   "rel": ["related", ...], "wiki": "..."}
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DATA = os.path.join(HERE, "nai-tags", "danbooru-tags.jsonl")

CAT_MARK = {
    "general": "[G]",
    "artist": "[A]",
    "copyright": "[P]",
    "character": "[C]",
    "meta": "[M]",
    "species": "[S]",
    "lore": "[L]",
}


def norm(s):
    return (s or "").lower().replace("_", " ")


def parse_args(argv):
    kw = []
    limit = 10
    cat = None
    exact = False
    as_json = False
    data = DEFAULT_DATA
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--limit", "-n"):
            i += 1
            limit = int(argv[i])
        elif a in ("--cat", "-c"):
            i += 1
            cat = argv[i].strip().lower()
        elif a in ("--data", "-d"):
            i += 1
            data = argv[i]
        elif a == "--exact":
            exact = True
        elif a == "--json":
            as_json = True
        elif a in ("--help", "-h"):
            print(__doc__)
            sys.exit(0)
        else:
            kw.append(a)
        i += 1
    return kw, limit, cat, exact, as_json, data


def load(path):
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except ValueError:
                continue
    return rows


def score(row, kws, exact):
    """Return weight (int) when every keyword hits, else None."""
    t = norm(row.get("t"))
    cn = (row.get("cn") or "").lower()
    rel = [norm(x) for x in (row.get("rel") or [])]
    weight = 0
    for kw in kws:
        k = norm(kw)
        hit = False
        if exact:
            hit = (t == k) or (k in rel)
        else:
            if t == k:
                weight += 4
                hit = True
            elif k in t:
                weight += 2
                hit = True
            if k in cn:
                weight += 1
                hit = True
            for r in rel:
                if k in r:
                    weight += 1
                    hit = True
                    break
        if not hit:
            return None
    return weight


def collect(rows, kws, cat, exact):
    phrase = " ".join(norm(k) for k in kws)
    hits = []
    for r in rows:
        if cat and (r.get("c") or "").lower() != cat:
            continue
        w = score(r, kws, exact)
        if w is None:
            continue
        tier = 0 if norm(r.get("t")) == phrase else 1
        hits.append((tier, -(r.get("n") or 0), -w, r))
    hits.sort(key=lambda x: (x[0], x[1], x[2], norm(x[3].get("t"))))
    return hits


def render(hits, limit, label):
    print(label)
    if not hits:
        print("  (no match)")
        return
    for idx, (tier, nn, w, r) in enumerate(hits[:limit], 1):
        mark = CAT_MARK.get((r.get("c") or "").lower(), "[?]")
        line = "%2d. %s %-40s n=%-9d" % (idx, mark, r.get("t") or "", r.get("n") or 0)
        if r.get("cn"):
            line += " cn=%s" % r["cn"]
        print(line)
        rel = r.get("rel") or []
        if rel:
            print("        rel: %s" % ", ".join(str(x) for x in rel[:8]))
        wiki = r.get("wiki") or ""
        if wiki:
            one = " ".join(wiki.split())
            print("        wiki: %s" % (one[:120] + ("..." if len(one) > 120 else "")))


def main():
    kws, limit, cat, exact, as_json, data = parse_args(sys.argv[1:])
    if not kws:
        print(__doc__)
        sys.exit(1)
    if not os.path.isfile(data):
        print("data file not found: %s" % data)
        sys.exit(2)

    rows = load(data)
    hits = collect(rows, kws, cat, exact)
    note = ""
    if not hits and len(kws) > 1:
        # AND produced nothing: fall back to the longest single keyword
        kws2 = [max(kws, key=len)]
        hits = collect(rows, kws2, cat, exact)
        note = "  (AND 无结果，已回退为单关键词 %r)" % kws2[0]

    if as_json:
        out = [h[3] for h in hits[:limit]]
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return

    label = "query=%s  matched=%d  showing=%d  (cat=%s)" % (
        " ".join(kws), len(hits), min(limit, len(hits)), cat or "any")
    render(hits, limit, label + note)


if __name__ == "__main__":
    main()
