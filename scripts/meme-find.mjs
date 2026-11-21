// meme-find.mjs -- search every meme pack by caption/keyword/tag, print exact matches.
// Why: send_meme with only a tag draws a RANDOM meme from that emotion (~50 candidates),
// which is why auto-sent stickers felt unrelated. This index lets you pick the exact one.
//
// usage:  node.cmd meme-find.mjs "夸 厉害" [--tag happy] [--limit 8] [--all]
// output: one line per hit:  [tag] caption  ->  <abs path>
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import { DatabaseSync } from 'node:sqlite'

const HOME = process.env.USERPROFILE || os.homedir()
const PACKS = [
  path.join(HOME, '.dsh', 'meme-packs'),
  path.join(HOME, 'AppData', 'Roaming', 'dsh-desktop', 'harness', 'profiles', '.generations', 'live'),
]

function findIndexes() {
  const out = []
  // user packs
  const up = PACKS[0]
  if (fs.existsSync(up)) {
    for (const d of fs.readdirSync(up, { withFileTypes: true })) {
      if (!d.isDirectory()) continue
      const db = path.join(up, d.name, 'index.db')
      if (fs.existsSync(db)) out.push({ pack: d.name, db, root: path.join(up, d.name) })
    }
  }
  // builtin packs inside the live generation
  const live = PACKS[1]
  if (fs.existsSync(live)) {
    for (const g of fs.readdirSync(live, { withFileTypes: true })) {
      if (!g.isDirectory() || !g.name.startsWith('dsh-meme')) continue
      const memes = path.join(live, g.name, 'node_modules', 'dsh-meme', 'memes')
      if (!fs.existsSync(memes)) continue
      for (const d of fs.readdirSync(memes, { withFileTypes: true })) {
        if (!d.isDirectory()) continue
        const db = path.join(memes, d.name, 'index.db')
        if (fs.existsSync(db)) out.push({ pack: d.name, db, root: path.join(memes, d.name) })
      }
    }
  }
  return out
}

function loadAll() {
  const rows = []
  for (const p of findIndexes()) {
    let db
    try { db = new DatabaseSync(p.db, { readOnly: true }) } catch { continue }
    let list = []
    try { list = db.prepare('SELECT path, tag, caption, keywords FROM memes').all() } catch { list = [] }
    for (const r of list) {
      rows.push({
        pack: p.pack,
        tag: r.tag || '',
        caption: r.caption || '',
        keywords: r.keywords || '',
        abs: path.join(p.root, (r.path || '').replace(/\//g, path.sep)),
      })
    }
    try { db.close() } catch {}
  }
  return rows
}

const argv = process.argv.slice(2)
const opt = { terms: [], tag: '', limit: 8, all: false }
for (let i = 0; i < argv.length; i++) {
  const a = argv[i]
  if (a === '--tag') opt.tag = (argv[++i] || '').toLowerCase()
  else if (a === '--limit') opt.limit = Number(argv[++i]) || 8
  else if (a === '--all') opt.all = true
  else opt.terms.push(a)
}
const q = opt.terms.join(' ').trim()
const words = q.split(/[\s,，、]+/).filter(Boolean)

const rows = loadAll()
if (!rows.length) { console.log('没有找到任何图库索引'); process.exit(0) }

let pool = rows
if (opt.tag) pool = pool.filter((r) => r.tag === opt.tag)

const scored = []
for (const r of pool) {
  const hay = (r.caption + ' ' + r.keywords + ' ' + r.tag).toLowerCase()
  let score = 0
  for (const w of words) {
    const lw = w.toLowerCase()
    if (hay.includes(lw)) score += 2
    if (r.tag.toLowerCase() === lw) score += 3
    // 单个字也算弱命中，避免"夸"这种短词直接 0
    if (lw.length === 1 && hay.includes(lw)) score += 1
  }
  if (words.length === 0) score = 1
  if (score > 0) scored.push({ r, score })
}
scored.sort((a, b) => b.score - a.score)

const shown = opt.all ? scored : scored.slice(0, opt.limit)
if (!shown.length) {
  console.log(`没有命中「${q}」${opt.tag ? '（tag=' + opt.tag + '）' : ''}，试试换词或去掉 --tag`)
  const near = pool.slice(0, 5).map((r) => `  [${r.tag}] ${r.caption}`)
  console.log('该范围里随便几张长这样：\n' + near.join('\n'))
  process.exit(0)
}
console.log(`命中 ${scored.length} 张${opt.tag ? '（tag=' + opt.tag + '）' : ''}，显示 ${shown.length}：`)
for (const { r, score } of shown) {
  console.log(`[${r.tag}] ${r.caption}  ->  ${r.abs}`)
}
