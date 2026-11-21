# -*- coding: utf-8 -*-
"""Export the private-chat session log (owner QQ OWNER_QQ) to one readable Markdown file.

Sources : harness\\sessions\\<ws>\\onebot-private-OWNER_QQ*\\session.v4.jsonl.zstd  (zstd-jsonl)
Output  : Desktop\\交接-私聊存档.md  (+ <usb>\\LittleCodeSauce-Backup\\chat-archive\\<date>-private-chat.md)
Dep     : zstandard in C:\\\\Users\\\\USER\\dsh-plugins\\_pylibs
Keeps   : owner messages, assistant story text, qq_send_image captions, image file names.
Drops   : runtime-context / cron-prompt / system-reminder injections.
"""
import sys, os, io, json, re, datetime, shutil

sys.path.insert(0, r"C:\Users\USER\dsh-plugins\_pylibs")
import zstandard

BASE = r"C:\Users\USER\AppData\Roaming\dsh-desktop\harness\sessions\--C-Users-Administrator-Documents-deepseek-harness-default-workspace--"
_priv = []
try:
    for _n in os.listdir(BASE):
        if _n.startswith("onebot-private-OWNER_QQ") and os.path.exists(os.path.join(BASE, _n, "session.v4.jsonl.zstd")):
            _priv.append((_n, _n))
except Exception:
    pass
_priv.sort()
SESS = _priv
OUT = r"C:\Users\USER\Desktop\交接-私聊存档.md"

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


def collect():
    ev, dropped, imgs, caps = [], 0, 0, 0
    for sid, label in SESS:
        p = os.path.join(BASE, sid, "session.v4.jsonl.zstd")
        if not os.path.exists(p):
            print("skip missing session: " + sid)
            continue
        raw = open(p, "rb").read()
        body = zstandard.ZstdDecompressor().stream_reader(io.BytesIO(raw)).read().decode("utf-8", "replace")
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
                    ev.append((when, sid, label, "user", txt, []))
                else:
                    dropped += 1
            elif t == "assistant/message":
                txt = texts((data.get("message") or {}).get("content"))
                if txt.strip():
                    ev.append((when, sid, label, "me", txt.strip(), []))
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
                names = [os.path.basename(str(s)) for s in (args.get("sources") or [])
                         if str(s).lower().endswith(".png")]
                if cap:
                    ev.append((when, sid, label, "me", cap, names))
                    caps += 1
                elif names:
                    ev.append((when, sid, label, "img", "", names))
                    imgs += len(names)
    ev.sort(key=lambda x: (x[1], x[0]))
    return ev, dropped, imgs, caps


def render(ev, dropped, imgs):
    L = ["# 私聊完整存档 · 主人 OWNER_QQ（赫萝）", "",
         "导出时间：" + datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
         "事件 " + str(len(ev)) + " 条；滤掉系统注入 " + str(dropped) + " 条；图片 " + str(imgs) + " 张", "",
         "剧情 caption 全在这份里；图名对应 media\\onebot\\ 下同名 png。", "", "---", ""]
    cur = None
    curdate = None
    for when, sid, label, kind, txt, names in ev:
        if sid != cur:
            cur = sid
            curdate = None
            L += ["", "# ==== " + label + " ====", ""]
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


def copy_to_usb():
    roots = []
    for letter in "DEFGHIJKLMNOPQRSTUVWXYZ":
        root = letter + ":\\"
        if not os.path.exists(root):
            continue
        try:
            import ctypes
            if ctypes.windll.kernel32.GetDriveTypeW(letter + ":\\") == 2:
                roots.append(root)
        except Exception:
            pass
    for root in roots:
        try:
            d = os.path.join(root, "LittleCodeSauce-Backup", "chat-archive")
            os.makedirs(d, exist_ok=True)
            dst = os.path.join(d, datetime.datetime.now().strftime("%Y-%m-%d") + "-private-chat.md")
            shutil.copyfile(OUT, dst)
            print("usb copy: " + dst)
        except Exception as e:
            print("usb copy failed: " + str(e))


def main():
    ev, dropped, imgs, caps = collect()
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(render(ev, dropped, imgs))
    print("events=%d dropped=%d imgs=%d caps=%d bytes=%d" % (len(ev), dropped, imgs, caps, os.path.getsize(OUT)))
    print("out=" + OUT)
    copy_to_usb()


if __name__ == "__main__":
    main()
