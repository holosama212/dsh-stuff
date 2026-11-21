// cf-fetch.mjs - Cloudflare-resistant page fetcher.
// Drives a real (headful) Chrome over the DevTools Protocol so JS challenges
// (CF "managed"/IUAM) actually execute and clear; then returns rendered text/HTML.
// Uses a persistent dedicated profile so cf_clearance survives between runs.
//
// usage: node cf-fetch.mjs <url> [--out file] [--timeout ms] [--proxy host:port] [--html] [--keep] [--port n]
// exit: 0 ok+cf-cleared | 3 fetched but CF not confirmed cleared | 1 fail | 2 usage

import { spawn } from 'node:child_process';
import fs from 'node:fs';

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const DEFAULT_PROFILE = 'C:\\\\Users\\\\USER\\dsh-plugins\\.cf-profile';

function parseArgs(argv) {
  const o = { url: '', out: '', timeout: 45000, proxy: '', html: false, keep: false, port: 9333, shot: '', profile: '', click: '', clickAfter: 6000, clickOnce: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--out') o.out = argv[++i];
    else if (a === '--timeout') o.timeout = parseInt(argv[++i], 10) || 45000;
    else if (a === '--proxy') o.proxy = argv[++i];
    else if (a === '--html') o.html = true;
    else if (a === '--keep') o.keep = true;
    else if (a === '--port') o.port = parseInt(argv[++i], 10) || 9333;
    else if (a === '--url') o.url = argv[++i];
    else if (a === '--shot') o.shot = argv[++i];
    else if (a === '--profile') o.profile = argv[++i];
    else if (a === '--click') o.click = argv[++i];           // "x,y" page pixels
    else if (a === '--click-after') o.clickAfter = parseInt(argv[++i], 10) || 6000;
    else if (a === '--click-once') o.clickOnce = true;
    else if (!a.startsWith('--')) o.url = a;
  }
  return o;
}
const opt = parseArgs(process.argv.slice(2));
// Robust URL detection: prefer an explicit http(s) token anywhere on the command line.
if (!/^https?:\/\//i.test(opt.url || '')) {
  const cand = process.argv.slice(2).find((a) => /^https?:\/\//i.test(a));
  if (cand) opt.url = cand;
}
if (!/^https?:\/\//i.test(opt.url || '')) { console.error('usage: cf-fetch.mjs <url> [--out file] [--timeout ms] [--proxy host:port] [--html] [--keep]'); process.exit(2); }

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function chromeArgs() {
  const a = [
    '--remote-debugging-port=' + opt.port,
    '--user-data-dir=' + (opt.profile || DEFAULT_PROFILE),
    '--no-first-run', '--no-default-browser-check',
    '--disable-blink-features=AutomationControlled',
    '--disable-extensions',
    '--disable-background-timer-throttling',
    '--disable-backgrounding-occluded-windows',
    '--disable-renderer-backgrounding',
    '--window-size=1280,900',
    '--window-position=140,100',
    '--lang=en-US',
    'about:blank',
  ];
  if (opt.proxy) a.unshift('--proxy-server=' + opt.proxy);
  return a;
}

function connect(url, timeout = 8000) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    const to = setTimeout(() => { try { ws.close(); } catch {} reject(new Error('ws connect timeout')); }, timeout);
    ws.onopen = () => { clearTimeout(to); resolve(ws); };
    ws.onerror = () => { clearTimeout(to); reject(new Error('ws error')); };
  });
}
function cdp(ws) {
  let id = 0; const pend = new Map();
  ws.onmessage = (ev) => {
    let m; try { m = JSON.parse(ev.data); } catch { return; }
    if (m.id && pend.has(m.id)) {
      const { resolve, reject } = pend.get(m.id); pend.delete(m.id);
      if (m.error) reject(new Error(JSON.stringify(m.error))); else resolve(m.result);
    }
  };
  return (method, params = {}) => new Promise((resolve, reject) => {
    const mid = ++id; pend.set(mid, { resolve, reject });
    try { ws.send(JSON.stringify({ id: mid, method, params })); } catch (e) { pend.delete(mid); reject(e); }
    setTimeout(() => { if (pend.has(mid)) { pend.delete(mid); reject(new Error('cdp timeout ' + method)); } }, 35000);
  });
}

async function main() {
  // Reuse an already-running debug Chrome on this port (warm daemon) if present.
  let child = null, reused = false;
  try {
    const r = await fetch('http://127.0.0.1:' + opt.port + '/json/version', { signal: AbortSignal.timeout(800) });
    if (r.ok) reused = true;
  } catch {}
  if (!reused) child = spawn(CHROME, chromeArgs(), { stdio: 'ignore' });
  let ws = null, browserWs = null;
  try {
    let ver = null; const t0 = Date.now();
    while (Date.now() - t0 < 20000) {
      try {
        const r = await fetch('http://127.0.0.1:' + opt.port + '/json/version', { signal: AbortSignal.timeout(1500) });
        if (r.ok) { ver = await r.json(); break; }
      } catch {}
      await sleep(250);
    }
    if (!ver) throw new Error('devtools not ready on port ' + opt.port);
    browserWs = ver.webSocketDebuggerUrl;

    let target = null;
    try {
      const r = await fetch('http://127.0.0.1:' + opt.port + '/json/new?' + opt.url, { method: 'PUT' });
      if (r.ok) target = await r.json();
    } catch {}
    if (!target) {
      try {
        const r = await fetch('http://127.0.0.1:' + opt.port + '/json/list');
        const list = await r.json();
        target = list.find((x) => x.type === 'page');
      } catch {}
    }
    if (!target || !target.webSocketDebuggerUrl) throw new Error('no page target');

    ws = await connect(target.webSocketDebuggerUrl);
    const send = cdp(ws);
    await send('Page.enable');
    await send('Runtime.enable');
    try { await send('Page.navigate', { url: opt.url }); } catch {}

    if (opt.shot) {
      await sleep(7000);
      try { const s = await send('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(opt.shot, Buffer.from(s.data, 'base64')); console.error('SHOT -> ' + opt.shot); } catch (e) { console.error('SHOT_FAIL ' + e.message); }
    }

    const deadline = Date.now() + opt.timeout;
    let ok = false, lastInfo = null;
    // Optional Turnstile/checkbox click (page pixels "x,y"): re-click a few times
    // because the widget sometimes re-renders after the first attempt.
    let clickXY = null;
    if (opt.click) {
      const m = String(opt.click).split(',').map((s) => parseInt(s.trim(), 10));
      if (m.length === 2 && m.every((n) => Number.isFinite(n))) clickXY = { x: m[0], y: m[1] };
    }
    let clicks = 0, lastClick = 0;
    const navAt = Date.now();
    while (Date.now() < deadline) {
      if (clickXY && clicks < (opt.clickOnce ? 1 : 4) && Date.now() - navAt >= opt.clickAfter && Date.now() - lastClick > 9000) {
        lastClick = Date.now(); clicks += 1;
        try {
          for (const type of ['mousePressed', 'mouseReleased']) {
            await send('Input.dispatchMouseEvent', { type, x: clickXY.x, y: clickXY.y, button: 'left', clickCount: 1 });
          }
          console.error('CLICK ' + clicks + ' @ ' + clickXY.x + ',' + clickXY.y);
        } catch (e) { console.error('CLICK_FAIL ' + e.message); }
      }
      const res = await send('Runtime.evaluate', {
        expression: "(function(){try{var b=document.body?document.body.innerText:'';var s=(document.title||'')+' '+b.slice(0,2000);var cf=/Just a moment|\\u8bf7\\u7a0d\\u5019|Attention Required|Enable JavaScript and cookies|_cf_chl|cf-browser-verification|__cf_chl/i.test(s);return JSON.stringify({t:document.title||'',n:b.length,cf:cf});}catch(e){return JSON.stringify({err:String(e)});}})()",
        returnByValue: true,
      });
      let v = {}; try { v = JSON.parse(res.result.value); } catch {}
      lastInfo = v;
      if (v && !v.err && !v.cf && v.n >= 200) { ok = true; break; }
      await sleep(1000);
    }

    const expr = opt.html ? 'document.documentElement.outerHTML' : 'document.body.innerText';
    const res = await send('Runtime.evaluate', { expression: expr, returnByValue: true });
    let content = res && res.result ? res.result.value : '';
    if (typeof content !== 'string') content = String(content || '');
    let title = ''; try { const tr = await send('Runtime.evaluate', { expression: 'document.title', returnByValue: true }); title = tr.result.value || ''; } catch {}
    const meta = { url: opt.url, title: title, cf_cleared: ok, length: content.length };
    if (opt.out) { fs.writeFileSync(opt.out, content, 'utf8'); console.log('OK ' + JSON.stringify(meta) + ' -> ' + opt.out); }
    else { console.log('OK ' + JSON.stringify(meta)); process.stdout.write(content); }
    if (!ok) process.exitCode = 3;
  } finally {
    try { if (ws) ws.close(); } catch {}
    try {
      if (browserWs && !opt.keep && !reused) {
        const bws = await connect(browserWs, 2000);
        try { await cdp(bws)('Browser.close'); } catch {}
        try { bws.close(); } catch {}
      }
    } catch {}
    await sleep(400);
    try { if (child && !child.killed && !opt.keep) child.kill(); } catch {}
  }
}

main().catch((e) => { console.error('FAIL ' + e.message); process.exit(1); });
