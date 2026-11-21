import json,sys,io,os
P=r"C:\Users\USER\dsh-plugins\tags-gallery.jsonl"
def load():
    rows=[]
    if not os.path.exists(P): return rows
    with open(P,encoding="utf-8",errors="replace") as f:
        for line in f:
            line=line.strip()
            if not line: continue
            try: rows.append(json.loads(line))
            except: pass
    return rows
def main():
    args=sys.argv[1:]
    if not args:
        print("usage: tagsgallery.py <keyword> [--cat CAT] [--limit N] [--all]")
        return
    kw=args[0].lower()
    cat=None; lim=30
    if "--cat" in args: cat=args[args.index("--cat")+1]
    if "--limit" in args: lim=int(args[args.index("--limit")+1])
    rows=load()
    hits=[r for r in rows if kw in r.get("t","").lower() and (cat is None or r.get("c")==cat)]
    hits.sort(key=lambda r:(r.get("c",""),r.get("t","")))
    print(f"total tags in db: {len(rows)}  |  matched: {len(hits)}")
    seen=set()
    n=0
    for r in hits:
        k=(r["m"],r["t"])
        tag=f'{r["t"]}  [{r["c"]}]'
        if tag in seen: continue
        seen.add(tag); n+=1
        print("  "+tag)
        if n>=lim: 
            print(f"  ... ({len(hits)-n} more)")
            break
main()