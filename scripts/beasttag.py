import sys,re,os
P=r"C:\Users\USER\dsh-plugins\beast-tags.txt"
def load():
    items=[]
    if not os.path.exists(P): return items
    txt=open(P,encoding="utf-8",errors="replace").read()
    for blk in txt.split("\u3010")[1:]:
        if "\u3011" not in blk: continue
        title,rest=blk.split("\u3011",1)
        items.append((title.strip(), rest.strip()))
    return items
def main():
    a=sys.argv[1:]
    if not a:
        print("usage: beasttag.py <keyword> [--limit N]")
        return
    kw=a[0].lower(); lim=6
    if "--limit" in a: lim=int(a[a.index("--limit")+1])
    items=load()
    hits=[(t,c) for t,c in items if kw in t.lower() or kw in c.lower()]
    print(f"total {len(items)} | matched {len(hits)}")
    for t,c in hits[:lim]:
        print("\n\u3010"+t+"\u3011")
        print("  "+c[:400])
main()