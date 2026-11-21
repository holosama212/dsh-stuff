# -*- coding: utf-8 -*-
"""Export ONLY the recent tail of the owner's private chat (merged across the
most-recent sessions) to one small Markdown file, so a brand-new session can
read it fast and pick up where the last one left off.

Output  : Desktop\\交接-私聊-最新.md
Dep     : zstandard in C:\\\\Users\\\\USER\\dsh-plugins\\_pylibs
Keeps   : owner messages, assistant story text, qq_send_image captions + image names.
Drops   : runtime-context / cron-prompt / system-reminder injections.
"""
import sys, os, io, json, re, datetime

sys.path.insert(0, r"C:\Users\USER\dsh-plugins\_pylibs")
import zstandard

BASE = r"C:\Users\USER\AppData\Roaming\dsh-desktop\harness\sessions\--C-Users-Administrator-Documents-deepseek-harness-default-workspace--"
OUT = r"C:\Users\USER\Desktop\交接-私聊-最新.md"
KEEP = 70      # how many recent message blocks to keep
MAX_SESS = 6   # how many most-recent sessions to merge

NOISE = ["Current runtime context", "Current working directory:", "Instructions from:",
         "<system-reminder>", "【会话令牌】", "[CRON FIRE]", "唤醒提示", "session_id:",
         "This is an automatically generated checkpoint", "<developer"]


def texts(blocks):
    out = []
    for b in blocks or []:
        if isinstance(b, dict) and b.get("type") == "text":
            t = (b.get("text") or "").strip()
            if t:
                out.append(t)
    return "\n".join(out)


def clean_user(txt):
    m = re.search(r"<user_message[^>]*>(.*?)</user_message>", txt, re.S)
    if m:
        return m.group(1).strip() or None
    for n in NOISE:
        if n in txt:
            return None
    if len(txt) > 1200:
        return None
    return txt.strip() or None


def ts(ms):
    try:
        return datetime.datetime.fromtimestamp(int(ms) / 1000)
    except Exception:
        return None


def session_dirs():
    rows = []
    try:
        for n in os.listdir(BASE):
            if not n.startswith("onebot-private-OWNER_QQ"):
                continue
            if "-bg" in n:
                continue
            p = os.path.join(BASE, n, "session.v4.jsonl.zstd")
            if os.path.exists(p):
                rows.append((os.path.getmtime(p), n, p))
    except Exception:
        pass
    rows.sort(reverse=True)
    return rows[:MAX_SESS]


def collect(paths):
    ev = []
    for p in paths:
        try:
            raw = open(p, "rb").read()
            body = zstandard.ZstdDecompressor().stream_reader(io.BytesIO(raw)).read().decode("utf-8", "replace")
        except Exception:
            continue
        for line in body.split("\n"):
            if not line.strip():
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            t = r.get("type")
            data = r.get("data") or {}
            when = ts(r.get("time"))
            if not when:
                continue
            if t == "user/message":
                txt = clean_user(texts(data.get("content")))
                if txt:
                    ev.append((when, "user", txt, []))
            elif t == "assistant/message":
                txt = texts((data.get("message") or {}).get("content"))
                if txt.strip():
                    ev.append((when, "me", txt.strip(), []))
            elif t == "tool/call":
                if str(data.get("name") or "") != "qq_send_image":
                    continue
                args = data.get("arguments")
                if isinstance(args, str):
                    try:
                        args = json.loads(args)
                    except Exception:
                        args = {}
                if not isinstance(args, dict):
                    args = {}
                cap = (args.get("caption") or "").strip()
                names = [os.path.basename(str(s)) for s in (args.get("sources") or []) if str(s).lower().endswith(".png")]
                if cap:
                    ev.append((when, "me", cap, names))
                elif names:
                    ev.append((when, "img", "", names))
    ev.sort(key=lambda x: x[0])
    return ev


def render(ev, paths):
    L = ["# 私聊最近上下文 · 主人 OWNER_QQ（赫萝）", "",
         "导出时间：" + datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
         "说明：这是最近几段私聊的尾部（跨会话合并），新会话开场先读这份接上下文。", "",
         "合并会话：" + "、".join(os.path.basename(os.path.dirname(p)) for p in paths), "", "---", ""]
    curdate = None
    for when, kind, txt, names in ev:
        d = when.strftime("%Y-%m-%d")
        if d != curdate:
            curdate = d
            L += ["", "## " + d, ""]
        hm = when.strftime("%H:%M")
        if kind == "user":
            L += ["**赫萝**（" + hm + "）：" + txt.replace("\n", "\n> "), ""]
        else:
            if txt:
                L += ["**小鲸鱼**（" + hm + "）：" + txt.replace("\n", "\n> "), ""]
            if names:
                L += ["（图：*" + "*、*".join(names) + "*）", ""]
    return "\n".join(L)


def main():
    paths = [p for _, _, p in session_dirs()]
    ev = collect(paths)
    if len(ev) > KEEP:
        ev = ev[-KEEP:]
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(render(ev, paths))
    print("tail_events=%d sessions=%d bytes=%d" % (len(ev), len(paths), os.path.getsize(OUT)))
    print("out=" + OUT)


if __name__ == "__main__":
    main()
