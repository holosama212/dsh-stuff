// capability-ledger.mjs - scan what I can do, write the ledger markdown.
// usage: .desktop-bin\node.cmd capability-ledger.mjs
import fs from 'node:fs'
import path from 'node:path'

const HOME = 'C:\\\\Users\\\\USER\\AppData\\Roaming\\dsh-desktop\\harness'
const SKILLS = path.join(HOME, 'skills')
const TOOLS = 'C:\\\\Users\\\\USER\\dsh-plugins'
const PROFILE = path.join(HOME, 'profiles', 'web', 'package.json')
const OUT = path.join(TOOLS, 'capability-ledger.md')

const BT = String.fromCharCode(96)

function skillDesc(dir) {
  for (const f of ['SKILL.md', 'skill.md']) {
    const p = path.join(dir, f)
    if (!fs.existsSync(p)) continue
    const txt = fs.readFileSync(p, 'utf8')
    const fm = txt.match(/^---[\s\S]*?description:\s*(.+)$/m)
    if (fm) return fm[1].trim().replace(/^["']|["']$/g, '')
    const line = txt.split(/\r?\n/).find((l) => l.trim() && !l.startsWith('#'))
    if (line) return line.trim().slice(0, 120)
  }
  return ''
}

const out = []
out.push('# 能力台账')
out.push('')
out.push('> 自动生成于 ' + new Date().toLocaleString('zh-CN') + '，生成器 dsh-plugins\\capability-ledger.mjs')
out.push('> 新增任何能力（技能 / 脚本 / 插件）后重跑一次，这份清单就是「我现在会什么」。')
out.push('')

out.push('## 一、技能（procedure，操作手册）')
out.push('')
let skills = []
try {
  skills = fs.readdirSync(SKILLS, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name).sort()
} catch (e) {}
for (const s of skills) {
  const d = skillDesc(path.join(SKILLS, s))
  out.push('- ' + s + (d ? '  ::  ' + d : ''))
}
out.push('')

out.push('## 二、工具脚本（local_exec 直接能跑的新功能）')
out.push('')
const exts = new Set(['.ps1', '.py', '.mjs', '.cmd', '.bat', '.js'])
let files = []
try {
  files = fs.readdirSync(TOOLS, { withFileTypes: true })
    .filter((e) => e.isFile() && exts.has(path.extname(e.name).toLowerCase()) && !e.name.startsWith('_'))
    .map((e) => e.name).sort()
} catch (e) {}
for (const f of files) {
  let hint = ''
  try {
    const txt = fs.readFileSync(path.join(TOOLS, f), 'utf8')
    const m = txt.match(/(?:^|\n)\s*(?:#|\/\/)\s*(.+)/)
    if (m) hint = m[1].trim().slice(0, 90)
  } catch (e) {}
  out.push('- ' + f + (hint ? '  ::  ' + hint : ''))
}
out.push('')

out.push('## 三、已装插件（带新工具的）')
out.push('')
try {
  const pkg = JSON.parse(fs.readFileSync(PROFILE, 'utf8'))
  for (const b of (pkg.dsh && pkg.dsh.profile && pkg.dsh.profile.bundles) || []) out.push('- ' + b)
} catch (e) {
  out.push('- (read package.json failed: ' + e.message + ')')
}
out.push('')

out.push('## 四、怎么加新能力')
out.push('')
out.push('1. 能写成步骤的 -> skill_manage 建技能，自动进 catalog，下个会话就能用。')
out.push('2. 能写成脚本的 -> 丢进 dsh-plugins\\（ps1 只写 ASCII），重跑本生成器登记。')
out.push('3. 需要新工具的 -> 装插件到 profiles\\web，写进 dsh.profile.bundles，重启 DSH。')
out.push('4. 三样都不是 -> memory_add，至少下次不会忘。')
out.push('')

fs.writeFileSync(OUT, out.join('\n'), 'utf8')
console.log('ledger -> ' + OUT + '  (skills=' + skills.length + ', scripts=' + files.length + ')')
