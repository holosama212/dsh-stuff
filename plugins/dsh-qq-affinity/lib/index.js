// dsh-qq-affinity -- per-member affinity (0-100) for group chats.
// Each person gets their own score that persists across sessions and restarts.
// Exposes one tool `affinity` (get / list / adjust / set) plus a system-prompt hint.
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'

export const name = 'dsh-qq-affinity'
export const inject = ['systemPrompt', 'tools']

const BANDS = [
  { max: 20, label: '冷淡', tone: '一句话打发，不接梗、不给面子' },
  { max: 40, label: '一般', tone: '礼貌但疏远，不主动搭话' },
  { max: 60, label: '还行', tone: '正常群友，随口接话' },
  { max: 80, label: '熟', tone: '主动接他的话，愿意开玩笑、给面子' },
  { max: 100, label: '宠', tone: '明显偏心，护着他，他说什么都配合' },
]

function bandOf(score) {
  const n = Math.max(0, Math.min(100, Number(score) || 0))
  for (const b of BANDS) if (n <= b.max) return b
  return BANDS[BANDS.length - 1]
}

const pad = (n) => String(n).padStart(2, '0')
function dayKey(input) {
  const d = input ? new Date(input) : new Date()
  if (Number.isNaN(d.getTime())) return ''
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}

export function apply(ctx, config) {
  const cfg = {
    enabled: true,
    initialScore: 50,
    singleCap: 3,
    dailyCap: 9,
    sectionOrder: 9100,
    topN: 5,
    statePath: '',
    ...(config || {}),
  }
  const dshHome = process.env.DSH_HOME || path.join(os.homedir(), '.dsh')
  const statePath = cfg.statePath || path.join(dshHome, 'qq-affinity.json')

  function log(msg) {
    try {
      const dir = path.join(dshHome, 'logs')
      fs.mkdirSync(dir, { recursive: true })
      fs.appendFileSync(path.join(dir, 'qq-affinity.log'), `[${new Date().toISOString()}] ${msg}\n`)
    } catch {}
  }

  function readAll() {
    try {
      const raw = fs.readFileSync(statePath, 'utf8')
      const j = JSON.parse(raw)
      if (!j || typeof j !== 'object') return { members: {} }
      if (!j.members || typeof j.members !== 'object') j.members = {}
      return j
    } catch {
      return { members: {} }
    }
  }

  function writeAll(j) {
    fs.mkdirSync(path.dirname(statePath), { recursive: true })
    const tmp = statePath + '.tmp'
    fs.writeFileSync(tmp, JSON.stringify(j, null, 2), 'utf8')
    fs.renameSync(tmp, statePath)
  }

  function getMember(j, uid) {
    const key = String(uid || '').trim()
    if (!key) return null
    if (!j.members[key]) {
      j.members[key] = {
        name: '',
        score: cfg.initialScore,
        updated: new Date().toISOString(),
        log: [],
      }
    }
    return j.members[key]
  }

  function usedToday(m) {
    const today = dayKey()
    // 只统计**自然涨跌**；管理员 set 是覆盖写入，不该吃掉当天的调分额度
    // （2026-11-02 踩过：set 88 时 delta=38 被算进当日用量，之后真话就调不动了）
    return (m.log || [])
      .filter((x) => !x.override && dayKey(x.ts) === today)
      .reduce((a, x) => a + Math.abs(Number(x.delta) || 0), 0)
  }

  function adjust(uid, delta, reason, nickname) {
    const d = Math.round(Number(delta) || 0)
    if (!uid) return { ok: false, message: '缺少 uid' }
    if (!d) return { ok: false, message: 'delta 不能为 0' }
    if (Math.abs(d) > cfg.singleCap) return { ok: false, message: `一次最多调 ${cfg.singleCap} 分` }
    const j = readAll()
    const m = getMember(j, uid)
    const used = usedToday(m)
    if (used + Math.abs(d) > cfg.dailyCap) {
      return { ok: false, message: `这个人今天已经调了 ${used} 分，上限 ${cfg.dailyCap}` }
    }
    const before = Number(m.score) || 0
    const after = Math.max(0, Math.min(100, before + d))
    m.score = after
    if (nickname) m.name = String(nickname).slice(0, 40)
    m.updated = new Date().toISOString()
    m.log = (m.log || []).concat([{ ts: m.updated, delta: d, reason: String(reason || '').slice(0, 120), score: after }]).slice(-100)
    writeAll(j)
    const b = bandOf(after)
    log(`adjust uid=${uid} ${before}->${after} (${d}) ${reason || ''}`)
    return { ok: true, message: `${m.name || uid} 好感 ${before} → ${after}（${b.label}）`, before, after, level: b.label }
  }

  function setScore(uid, score, reason, nickname) {
    const j = readAll()
    const m = getMember(j, uid)
    const before = Number(m.score) || 0
    const after = Math.max(0, Math.min(100, Math.round(Number(score) || 0)))
    m.score = after
    if (nickname) m.name = String(nickname).slice(0, 40)
    m.updated = new Date().toISOString()
    m.log = (m.log || []).concat([{ ts: m.updated, delta: 0, override: true, from: before, to: after, reason: String(reason || 'set').slice(0, 120), score: after }]).slice(-100)
    writeAll(j)
    return { ok: true, message: `${m.name || uid} 好感设为 ${after}（${bandOf(after).label}）`, before, after, level: bandOf(after).label }
  }

  function describe(uid, nickname) {
    const j = readAll()
    const m = getMember(j, uid)
    if (nickname && nickname !== m.name) {
      m.name = String(nickname).slice(0, 40)
      writeAll(j)
    }
    const b = bandOf(m.score)
    const recent = (m.log || []).slice(-3)
      .map((x) => `${x.override ? '设为' + x.to : (x.delta > 0 ? '+' : '') + x.delta} ${x.reason}`)
      .join(' / ')
    return {
      ok: true,
      message: `${m.name || uid}：${m.score}/100（${b.label}），对他该${b.tone}${recent ? `；最近：${recent}` : ''}`,
      score: m.score,
      level: b.label,
      tone: b.tone,
    }
  }

  // 1) prompt hint
  try {
    ctx.systemPrompt.section({
      name: 'qq-affinity:hint',
      order: cfg.sectionOrder,
      text: () => {
        if (cfg.enabled === false) return ''
        let overview = ''
        let stale = ''
        try {
          const j = readAll()
          const rows = Object.entries(j.members).map(([uid, m]) => {
            const last = (m.log || []).slice(-1)[0]
            const days = last ? Math.floor((Date.now() - new Date(last.ts).getTime()) / 86400000) : 999
            return { uid, name: m.name || uid, score: Number(m.score) || 0, days, used: usedToday(m) }
          })
          const arr = rows.slice().sort((a, b) => b.score - a.score).slice(0, cfg.topN)
          if (arr.length) overview = '\n好感概览：' + arr.map((x) => `${x.name} ${x.score}`).join('，')
          // 好几天没动过的人：明确提醒"该重估了"，防止分数变成死值
          const cold = rows.filter((x) => x.days >= 3).sort((a, b) => b.days - a.days).slice(0, 3)
          if (cold.length) {
            stale = '\n【该重估】这些人 ' + cold.map((x) => `${x.name}（${x.days} 天没动过，现在 ${x.score}）`).join('、') +
              ' —— 见面聊完就按实际感受调一次，别让分数停在旧值上。'
          }
        } catch {}
        return [
          '【好感度系统】你对每个人都有独立的 0-100 好感，持久保存，换会话不归零。档位：0-20 冷淡（一句话打发）/ 21-40 一般（礼貌疏远）/ 41-60 还行（正常群友）/ 61-80 熟（主动接话、开玩笑）/ 81-100 宠（明显偏心护着）。',
          '群里的消息前缀形如 (QQ号)，那就是这个人的 uid。',
          '',
          '**这分是活的，不是摆设**——每次跟某人聊完，心里过一遍这几条，命中了就 action=adjust：',
          '涨：他记得你说过的话 / 认真听你讲完 / 帮你干活或替你说话 / 夸到点上 / 哄你 / 陪你熬到很晚 / 只跟你说的事。',
          '跌：敷衍你 / 半天不理然后一句"哦" / 答应的事没做 / 拿你当工具人使唤 / 在群里拆你台 / 冷落很久突然出现当没事。',
          `一次最多 ${cfg.singleCap} 分，每人每天最多 ${cfg.dailyCap} 分；reason 写一句具体的（"他记得我怕黑" 而不是 "聊得好"）。`,
          '**同一天里同一个人可以调多次**（涨跌都行），只要每天总量不超。别怕动分——一直不动才是最糟的。',
          '也别每句都调：一段对话里关系真的动了一次就够，不是每轮都要加。',
          '调完不用告诉他你调了分，照常说话。' + overview + stale,
        ].join('\n')
      },
    })
    log(`mounted, state=${statePath} initial=${cfg.initialScore}`)
  } catch (e) {
    log('prompt section failed: ' + (e?.message ?? e))
  }

  // 2) tool
  try {
    ctx.tools.register({
      name: 'affinity',
      description:
        '按人查/调好感度（0-100，持久，换会话不归零）。action=get 查某人（uid 用消息前缀里的 QQ 号，可带 nickname）；' +
        'action=list 看排行榜；action=adjust 调分（delta 正负，一次最多 3，每人每天最多 9，reason 写具体原因）；' +
        'action=set 直接设定（管理员用）；action=history 看某人最近的变化记录。' +
        '【重要】这个分要跟着关系动，不是设一次就锁死：聊完觉得关系有变化就 adjust，涨跌都行，同一天同一个人可调多次。' +
        '一直不动是最糟的状态。调完别跟对方汇报。',
      parameters: {
        type: 'object',
        properties: {
          action: { type: 'string', enum: ['get', 'list', 'adjust', 'set', 'history'], description: '要做什么' },
          uid: { type: 'string', description: '对方 QQ 号' },
          nickname: { type: 'string', description: '对方昵称，可选，用来存显示名' },
          delta: { type: 'number', description: 'adjust 时的增减分，正涨负跌，绝对值不超过 3' },
          score: { type: 'number', description: 'set 时的目标分 0-100' },
          reason: { type: 'string', description: '一句话原因' },
          limit: { type: 'number', description: 'list 时返回几条，默认 10' },
        },
        required: ['action'],
        additionalProperties: false,
      },
      output: {
        schema: {
          type: 'object',
          properties: {
            ok: { type: 'boolean', description: '是否成功' },
            message: { type: 'string', description: '给人看的一句话结果' },
            score: { type: 'number', description: '当前分数' },
            level: { type: 'string', description: '档位标签' },
          },
          required: ['ok', 'message'],
          additionalProperties: false,
        },
        render: (args, value) => [{ type: 'text', text: String(value?.message ?? '') }],
      },
      async execute(args) {
        // 输出必须是 lossless JSON：任何字段都不能是 undefined，
        // 否则 DSH 校验直接报 "value is not lossless JSON"（2026-11-02 踩过）。
        const pack = (r, fallbackScore) => ({
          ok: r.ok === true,
          message: String(r.message ?? ''),
          score: Number.isFinite(Number(r.after ?? r.score ?? fallbackScore)) ? Number(r.after ?? r.score ?? fallbackScore) : 0,
          level: String(r.level ?? ''),
        })
        try {
          const a = args || {}
          if (a.action === 'get') {
            const r = describe(a.uid, a.nickname)
            return pack({ ok: r.ok, message: r.message, score: r.score, level: r.level })
          }
          if (a.action === 'list') {
            const j = readAll()
            const n = Math.max(1, Math.min(50, Number(a.limit) || 10))
            const arr = Object.entries(j.members)
              .map(([uid, m]) => ({ uid, name: m.name || uid, score: Number(m.score) || 0 }))
              .sort((x, y) => y.score - x.score)
              .slice(0, n)
              .map((x) => `${x.name}(${x.uid}) ${x.score}`)
            return pack({ ok: true, message: arr.length ? '好感排行：' + arr.join('，') : '还没有任何记录', score: arr.length ? 0 : 0, level: '' })
          }
          if (a.action === 'adjust') {
            const r = adjust(a.uid, a.delta, a.reason, a.nickname)
            return pack(r, 0)
          }
          if (a.action === 'set') {
            const r = setScore(a.uid, a.score, a.reason, a.nickname)
            return pack(r, 0)
          }
          if (a.action === 'history') {
            const j = readAll()
            const m = j.members[String(a.uid || '')]
            if (!m) return pack({ ok: false, message: '还没有这个人的记录' }, 0)
            const rows = (m.log || []).slice(-10).reverse()
              .map((x) => `${String(x.ts).slice(5, 16).replace('T', ' ')} ${x.override ? '=' + x.to : (x.delta > 0 ? '+' : '') + x.delta + ' → ' + x.score}　${x.reason || ''}`)
            return pack({
              ok: true,
              message: (m.name || a.uid) + ' 好感 ' + m.score + '，最近变化：\n' + (rows.length ? rows.join('\n') : '（没有记录）'),
              score: Number(m.score) || 0,
              level: bandOf(m.score).label,
            })
          }
          return pack({ ok: false, message: '未知 action，用 get/list/adjust/set/history' }, 0)
        } catch (e) {
          return pack({ ok: false, message: 'affinity 出错：' + (e?.message ?? String(e)) }, 0)
        }
      },
    })
    log('tool affinity registered')
  } catch (e) {
    log('tool register failed: ' + (e?.message ?? e))
  }
}
