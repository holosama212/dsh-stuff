import sys, json
sys.stdout.reconfigure(encoding='utf-8')
DB = "C:\\\\Users\\\\USER\\dsh-plugins\\nai-tagdb.json"
rows = json.load(open(DB, encoding="utf-8"))
args = sys.argv[1:]
if not args:
    print("usage: naitag.py <keyword> [limit=30]")
    sys.exit(0)
kw = args[0].strip()
limit = int(args[1]) if len(args) > 1 and args[1].isdigit() else 30


def norm(s):
    return (s or "").lower().replace("_", " ").replace("-", " ")


k = norm(kw)
res = []
for r in rows:
    tag = r[0] if len(r) > 0 else ""
    cn = r[1] if len(r) > 1 else ""
    if k in norm(tag) or k in (cn or ""):
        res.append(r)
res.sort(key=lambda r: (r[3] if len(r) > 3 and isinstance(r[3], (int, float)) else 0), reverse=True)
print("query '%s' : %d hits (by popularity)" % (kw, len(res)))
for r in res[:limit]:
    tag = str(r[0]).replace("_", " ")
    cn = r[1] if len(r) > 1 else ""
    cat = r[2] if len(r) > 2 else ""
    uses = r[3] if len(r) > 3 else 0
    pol = r[4] if len(r) > 4 else ""
    print("%s | %s | %s | hits=%s | %s" % (tag, cn, cat, uses, pol))
if len(res) > limit:
    print("... %d more" % (len(res) - limit))
