#!/usr/bin/env node
/**
 * read-session.mjs - inspect DSH session logs from the command line.
 *
 * Why: when a long task is delegated to its own session (cron attach=new /
 * sub-agent), the main chat must be able to check progress without leaving it.
 * This script lists sessions and dumps the tail of one session's transcript.
 *
 * Usage:
 *   node read-session.mjs --list [--n 12]
 *   node read-session.mjs --tail 20 [--session <id|prefix>]
 *   node read-session.mjs --tail 20 --file <path-to-session.v4.jsonl.zstd>
 *
 * Notes:
 * - Session logs are concatenated zstd frames; we split on the zstd magic and
 *   decompress frame by frame (Node 22+ zlib.zstdDecompressSync).
 * - Text is taken from user/message and assistant/message events only.
 * - Turn state (turn/end reason) is summarised so a stuck/failed run is visible.
 */
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const HOME = process.env.DSH_HOME || path.join(process.env.APPDATA || '', 'dsh-desktop', 'harness');
const SESSIONS = path.join(HOME, 'sessions');
const MAGIC = Buffer.from([0x28, 0xb5, 0x2f, 0xfd]);

function args() {
  const a = process.argv.slice(2);
  const o = { list: false, tail: 0, session: '', file: '', n: 12 };
  for (let i = 0; i < a.length; i++) {
    if (a[i] === '--list') o.list = true;
    else if (a[i] === '--tail') o.tail = Number(a[++i] || 20);
    else if (a[i] === '--session') o.session = a[++i] || '';
    else if (a[i] === '--file') o.file = a[++i] || '';
    else if (a[i] === '--n') o.n = Number(a[++i] || 12);
  }
  return o;
}

function walkDirs(root) {
  const out = [];
  if (!fs.existsSync(root)) return out;
  for (const d of fs.readdirSync(root, { withFileTypes: true })) {
    if (!d.isDirectory()) continue;
    const p = path.join(root, d.name);
    const f = path.join(p, 'session.v4.jsonl.zstd');
    if (fs.existsSync(f)) {
      const st = fs.statSync(f);
      out.push({ dir: d.name, file: f, mtime: st.mtimeMs, size: st.size });
    } else {
      out.push(...walkDirs(p));
    }
  }
  return out;
}

function decompressFrames(buf) {
  const idxs = [];
  let from = 0;
  while (true) {
    const i = buf.indexOf(MAGIC, from);
    if (i < 0) break;
    idxs.push(i);
    from = i + 4;
  }
  const parts = [];
  for (let k = 0; k < idxs.length; k++) {
    const s = idxs[k], e = k + 1 < idxs.length ? idxs[k + 1] : buf.length;
    try { parts.push(zlib.zstdDecompressSync(buf.subarray(s, e))); } catch { /* skip bad frame */ }
  }
  return Buffer.concat(parts).toString('utf8');
}

function list() {
  const rows = walkDirs(SESSIONS).sort((a, b) => b.mtime - a.mtime);
  for (const r of rows.slice(0, 40)) {
    const t = new Date(r.mtime).toLocaleString('zh-CN', { hour12: false });
    console.log(t + '  ' + (r.size / 1024).toFixed(0).padStart(6) + 'KB  ' + r.dir);
  }
}

function tail(o) {
  let file = o.file;
  if (!file) {
    const rows = walkDirs(SESSIONS).sort((a, b) => b.mtime - a.mtime);
    const hit = o.session ? rows.find(r => r.dir.includes(o.session)) : rows[0];
    if (!hit) { console.error('no session matched: ' + (o.session || '(latest)')); process.exit(2); }
    file = hit.file;
  }
  const text = decompressFrames(fs.readFileSync(file));
  const lines = text.split('\n').filter(Boolean);
  const conv = [];
  let lastTurn = null, lastStep = null, lastRetry = 0;
  for (const l of lines) {
    let e;
    try { e = JSON.parse(l); } catch { continue; }
    const t = e.type || '';
    if (t === 'turn/end') lastTurn = { time: e.time, reason: e.data && e.data.reason ? (e.data.reason.kind || e.data.reason) : undefined };
    if (t === 'step/end') lastStep = e.time;
    if (t === 'llm/retry-started' && e.data && e.data.retry) lastRetry = e.data.retry;
    if (t !== 'user/message' && t !== 'assistant/message') continue;
    const d = e.data || {};
    const m = d.message || d;
    const c = m.content || [];
    let s = '';
    if (typeof c === 'string') s = c;
    else if (Array.isArray(c)) s = c.filter(x => x && x.type === 'text').map(x => x.text).join(' ');
    if (!s.trim()) continue;
    const who = t === 'user/message' ? 'USER' : 'AI';
    const time = new Date(e.time).toLocaleString('zh-CN', { hour12: false });
    conv.push('[' + time + '] ' + who + ': ' + s.replace(/\s+/g, ' ').slice(0, 300));
  }
  console.log(conv.slice(-o.tail).join('\n'));
  console.error('---');
  console.error('file=' + file);
  console.error('last turn/end=' + JSON.stringify(lastTurn) + ' maxRetrySeen=' + lastRetry);
  if (lastStep && lastTurn && lastStep > (lastTurn.time || 0)) console.error('WARN: step/end newer than turn/end -> still running or aborted mid-turn');
}

const o = args();
if (o.list) list();
else tail(o);
