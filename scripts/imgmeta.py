#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
imgmeta.py — 读图片里内嵌的生成参数（NAI / A1111 / ComfyUI 等）

用法:
    python imgmeta.py <图片或目录> [更多路径...]
    python imgmeta.py <目录> --all      递归整个目录，只列有参数的

支持:
    PNG  : tEXt / zTXt / iTXt  (keyword: parameters / Comment / Software / Description)
    WebP : RIFF 容器里的 EXIF chunk -> UserComment
    JPEG : APP1 EXIF -> UserComment

输出: 有参数就打印（模型/seed/steps/正负串），没有就说明为什么。
"""
import sys
import os
import zlib
import struct
import json

# ---------- PNG ----------

def read_png_chunks(path):
    out = []
    with open(path, 'rb') as f:
        if f.read(8) != b'\x89PNG\r\n\x1a\n':
            return None
        while True:
            head = f.read(8)
            if len(head) < 8:
                break
            length = struct.unpack('>I', head[:4])[0]
            ctype = head[4:8]
            data = f.read(length)
            f.read(4)  # crc
            out.append((ctype, data))
            if ctype == b'IEND':
                break
    return out


def png_text_entries(chunks):
    """返回 {keyword: value} 文本字典"""
    d = {}
    for ctype, data in chunks:
        try:
            if ctype == b'tEXt':
                k, _, v = data.partition(b'\x00')
                d[k.decode('latin-1')] = v.decode('latin-1')
            elif ctype == b'zTXt':
                k, _, rest = data.partition(b'\x00')
                comp = rest[1:]  # skip compression method byte
                d[k.decode('latin-1')] = zlib.decompress(comp).decode('latin-1')
            elif ctype == b'iTXt':
                k, _, rest = data.partition(b'\x00')
                # rest: compflag(1) compmethod(1) langtag\0 translated\0 text
                rest = rest[2:]
                lang, _, rest = rest.partition(b'\x00')
                trans, _, text = rest.partition(b'\x00')
                d[k.decode('latin-1')] = text.decode('utf-8', 'replace')
        except Exception as e:
            d['__error__'] = f'{ctype}: {e}'
    return d


# ---------- EXIF (WebP / JPEG) ----------

def parse_exif(data):
    """极简 EXIF 解析：只取 UserComment(0x9286) / ImageDescription(0x010e) / Software(0x0131)"""
    res = {}
    if len(data) < 8:
        return res
    if data[:6] not in (b'Exif\x00\x00', b'Exif\x00', b'MM\x00*', b'II*\x00'):
        # 有些 WebP 直接给 TIFF 头
        if data[:2] not in (b'MM', b'II'):
            return res
    # 定位 TIFF 头
    off = 0
    if data[:6] == b'Exif\x00\x00':
        off = 6
    tiff = data[off:]
    if len(tiff) < 8:
        return res
    bo = '>' if tiff[:2] == b'MM' else '<'
    try:
        ifd_off = struct.unpack(bo + 'I', tiff[4:8])[0]
        n = struct.unpack(bo + 'H', tiff[ifd_off:ifd_off + 2])[0]
        for i in range(n):
            e = ifd_off + 2 + i * 12
            tag, typ, cnt = struct.unpack(bo + 'HHI', tiff[e:e + 8])
            valoff = tiff[e + 8:e + 12]
            if tag not in (0x9286, 0x010e, 0x0131):
                continue
            size = cnt * (1 if typ in (2, 7) else 2 if typ == 3 else 4)
            if size <= 4:
                raw = valoff[:size]
            else:
                o = struct.unpack(bo + 'I', valoff)[0]
                raw = tiff[o:o + size]
            if typ == 7:  # UNDEFINED, UserComment 有 8 字节字符集前缀
                body = raw[8:] if raw[:8].startswith((b'UNICODE', b'ASCII\x00', b'JIS')) else raw
                try:
                    txt = body.decode('utf-8')
                except Exception:
                    txt = body.decode('latin-1', 'replace')
            else:
                txt = raw.rstrip(b'\x00').decode('utf-8', 'replace')
            name = {0x9286: 'UserComment', 0x010e: 'ImageDescription', 0x0131: 'Software'}[tag]
            res[name] = txt
    except Exception as e:
        res['__error__'] = str(e)
    return res


def read_webp_meta(path):
    with open(path, 'rb') as f:
        head = f.read(12)
        if head[:4] != b'RIFF' or head[8:12] != b'WEBP':
            return None
        meta = {}
        while True:
            h = f.read(8)
            if len(h) < 8:
                break
            fourcc = h[:4]
            size = struct.unpack('<I', h[4:8])[0]
            payload = f.read(size)
            if size % 2:
                f.read(1)
            if fourcc == b'EXIF':
                meta.update(parse_exif(payload))
            elif fourcc == b'XMP ':
                meta['XMP'] = payload.decode('utf-8', 'replace')
        return meta


def read_jpeg_meta(path):
    with open(path, 'rb') as f:
        data = f.read()
    i = 2
    while i < len(data) - 4:
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xD8, 0xD9):
            i += 2
            continue
        seglen = struct.unpack('>H', data[i + 2:i + 4])[0]
        if marker == 0xE1 and data[i + 4:i + 10] == b'Exif\x00\x00':
            return parse_exif(data[i + 4:i + 2 + seglen])
        i += 2 + seglen
    return {}


# ---------- 输出 ----------

def pretty_params(raw):
    """把 NAI 的 JSON 或 A1111 的纯文本拆开"""
    raw = raw.strip()
    if raw.startswith('{'):
        try:
            j = json.loads(raw)
            lines = []
            for k, v in j.items():
                if isinstance(v, str) and len(v) > 400:
                    lines.append(f'{k}: ({len(v)} 字符)')
                    lines.append('  ' + v[:400] + ' …')
                else:
                    lines.append(f'{k}: {v}')
            return '\n'.join(lines)
        except Exception:
            pass
    # A1111: 正串\nNegative prompt: …\nSteps: …
    out = []
    for chunk in raw.split('\n'):
        out.append(chunk)
    return '\n'.join(out)


def dump(path):
    ext = os.path.splitext(path)[1].lower()
    print('=' * 70)
    print('FILE :', path)
    try:
        print('SIZE :', os.path.getsize(path), 'bytes')
    except Exception:
        pass

    texts = {}
    if ext == '.png':
        chunks = read_png_chunks(path)
        if chunks is None:
            print('不是合法 PNG')
            return False
        texts = png_text_entries(chunks)
    elif ext == '.webp':
        m = read_webp_meta(path)
        texts = m or {}
    elif ext in ('.jpg', '.jpeg'):
        texts = read_jpeg_meta(path)
    else:
        print('不支持的扩展名')
        return False

    if not texts:
        print('没有元数据（中继站/压缩后可能被抹掉了）')
        return False

    found = False
    for k, v in texts.items():
        if not v:
            continue
        if k in ('parameters', 'Comment', 'UserComment'):
            print(f'--- {k} ---')
            print(pretty_params(v))
            found = True
        elif k in ('Software', 'Description', 'ImageDescription'):
            print(f'{k}: {v}')
            found = True
    if not found:
        print('有元数据块但没找到生成参数:', list(texts.keys()))
    return found


def brief_mode(path):
    """只打印关键几行，方便一眼看"""
    ext = os.path.splitext(path)[1].lower()
    texts = {}
    if ext == '.png':
        chunks = read_png_chunks(path)
        if chunks is None:
            print(f'{os.path.basename(path)}: 不是合法 PNG')
            return False
        texts = png_text_entries(chunks)
    elif ext == '.webp':
        texts = read_webp_meta(path) or {}
    elif ext in ('.jpg', '.jpeg'):
        texts = read_jpeg_meta(path)
    else:
        return False

    raw = texts.get('parameters') or texts.get('Comment') or texts.get('UserComment') or ''
    if not raw:
        print(f'{os.path.basename(path)}: 无参数')
        return False
    j = None
    if raw.strip().startswith('{'):
        try:
            j = json.loads(raw)
        except Exception:
            j = None
    if j:
        fields = []
        for k in ('model_name', 'seed', 'steps', 'sampler', 'scale', 'width', 'height', 'noise_schedule'):
            if k in j:
                fields.append(f'{k}={j[k]}')
        p = j.get('prompt') or ''
        uc = j.get('uc') or ''
        print(f'{os.path.basename(path)}  ' + '  '.join(fields))
        print('  P:', p[:260] + (' …' if len(p) > 260 else ''))
        print('  N:', uc[:160] + (' …' if len(uc) > 160 else ''))
    else:
        print(f'{os.path.basename(path)}')
        print('  ' + raw[:400].replace('\n', ' '))
    return True


def main():
    brief = '--brief' in sys.argv or '-b' in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    if not args:
        print(__doc__)
        return
    targets = []
    for a in args:
        if os.path.isdir(a):
            for root, _, files in os.walk(a):
                for fn in files:
                    if os.path.splitext(fn)[1].lower() in ('.png', '.webp', '.jpg', '.jpeg'):
                        targets.append(os.path.join(root, fn))
        else:
            targets.append(a)
    ok = 0
    for t in targets:
        hit = brief_mode(t) if brief else dump(t)
        if hit:
            ok += 1
    print('=' * 70)
    print(f'共 {len(targets)} 张，{ok} 张带参数')


if __name__ == '__main__':
    main()
