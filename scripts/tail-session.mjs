import fs from 'node:fs';
import zlib from 'node:zlib';
const f = process.argv[2];
const n = Number(process.argv[3] || 20);
const buf = fs.readFileSync(f);
const MAGIC = Buffer.from([0x28, 0xb5, 0x2f, 0xfd]);
const starts = []; let i = buf.indexOf(MAGIC, 0);
while (i !== -1) { starts.push(i); i = buf.indexOf(MAGIC, i + 4); }
starts.push(buf.length);
const chunks = [];
for (let k = 0; k < starts.length - 1; k++) {
  try { chunks.push(zlib.zstdDecompressSync(buf.subarray(starts[k], starts[k + 1])).toString('utf8')); } catch {}
}
const lines = chunks.join('').split('\n').filter(s => s.trim());
for (const line of lines.slice(-n)) {
  let o; try { o = JSON.parse(line); } catch { console.log('RAW ' + line.slice(0, 200)); continue; }
  const d = o.data || {};
  const msg = d.message || {};
  const c = Array.isArray(msg.content) ? msg.content : [];
  try {
    if (o.type === 'assistant/message') {
      const tag = '[turn ' + (d.turn ?? '?') + ' step ' + (d.step ?? '?') + ']';
      for (const part of c) {
        if (part.type === 'text') console.log(tag + ' TEXT ' + String(part.text).slice(0, 500));
        else if (part.type === 'tool-call') console.log(tag + ' CALL ' + part.name + ' ' + String(part.arguments).slice(0, 400));
      }
    } else if (o.type === 'tool/result') {
      const t = c.map(x => x.text || '').join(' ').slice(0, 400);
      console.log('[RESULT ' + (o.seq ?? '') + ' err=' + (msg.isError === true) + '] ' + t);
    } else if (o.type === 'user/message') {
      const t = c.map(x => x.text || '').join(' ').slice(0, 300);
      if (t) console.log('[USER ' + (o.seq ?? '') + '] ' + t);
    }
  } catch (e) {
    console.log('PARSE_ERR ' + o.type + ' ' + String(e.message));
  }
}