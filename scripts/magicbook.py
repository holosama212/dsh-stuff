import sys, os, json
sys.stdout.reconfigure(encoding='utf-8')
BOOK = "C:\\\\Users\\\\USER\\Desktop\\\u9b54\u5bfc\u4e66.xlsx"
NEWBOOK = "C:\\\\Users\\\\USER\\dsh-plugins\\nai-magicbook-2025.txt"
CACHE = "C:\\\\Users\\\\USER\\dsh-plugins\\grimoire.json"


def parse_new():
    rows = []
    try:
        lines = open(NEWBOOK, encoding="utf-8").read().split("\n")
    except Exception:
        return rows
    start = 0
    for i, l in enumerate(lines):
        if l.strip() == "\u7f16\u7e82\u8005\u6742\u9879":
            start = i
            break
    title = ""
    for l in lines[start:]:
        s = l.strip()
        if not s:
            continue
        if ("," not in s) and ("::" not in s) and len(s) <= 60:
            title = s
        else:
            rows.append([title, s])
    return rows


def load_book():
    if os.path.exists(CACHE):
        try:
            with open(CACHE, encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    import openpyxl
    wb = openpyxl.load_workbook(BOOK, read_only=True, data_only=True)
    book = {}
    for name in wb.sheetnames:
        rows = []
        for row in wb[name].iter_rows(values_only=True):
            cells = [str(c).replace("\n", " ").strip() for c in row if c is not None]
            if cells:
                rows.append(cells)
        book[name] = rows
    nb = parse_new()
    if nb:
        book["\u65b0\u6cd5\u51782025"] = nb
    try:
        with open(CACHE, "w", encoding="utf-8") as f:
            json.dump(book, f, ensure_ascii=False)
    except Exception:
        pass
    return book


args = sys.argv[1:]
if not args:
    print("usage: magicbook.py <keyword> [limit]")
    sys.exit(0)
kw = args[0].lower()
limit = int(args[1]) if len(args) > 1 else 40
book = load_book()
hits = 0
for name, rows in book.items():
    for cells in rows:
        line = " | ".join(cells)
        if kw in line.lower():
            print("[" + name + "] " + line[:400])
            hits += 1
            if hits >= limit:
                print("... hit limit " + str(limit))
                sys.exit(0)
print("== " + str(hits) + " hits")
