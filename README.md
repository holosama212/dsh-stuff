# DSH 自用插件与脚本

在 [DeepSeek Harness](https://github.com/deepseek-ai)（DSH Desktop，Windows）上攒下来的一批插件和运维脚本。原本只是自己用的，整理出来给需要的人参考。

> **所有敏感信息已脱敏**：用户名、QQ 号、群号、群 ID 都替换成了占位符。用之前先把下面这几个占位符改成你自己的。

| 占位符 | 含义 |
|---|---|
| `C:\Users\USER` | 你的 Windows 用户目录 |
| `OWNER_QQ` | 你的 QQ 号（机器人主人） |
| `BOT_QQ` | 机器人自己的 QQ 号 |
| `GROUP_ID` | 你要用的群号 |

批量替换（PowerShell）：

```powershell
Get-ChildItem . -Recurse -File -Include *.ps1,*.mjs,*.py,*.json |
  ForEach-Object {
    $t = [IO.File]::ReadAllText($_.FullName)
    $t = $t -replace 'C:\\Users\\USER', "C:\Users\$env:USERNAME"
    $t = $t -replace 'OWNER_QQ', '你的QQ号'
    $t = $t -replace 'BOT_QQ', '机器人QQ号'
    $t = $t -replace 'GROUP_ID', '你的群号'
    [IO.File]::WriteAllText($_.FullName, $t, (New-Object Text.UTF8Encoding($false)))
  }
```

## 目录

```
plugins/    5 个 DSH 插件
scripts/    44 个运维/出图/QQ 相关脚本
```

## plugins

| 插件 | 干什么 |
|---|---|
| `dsh-qq-affinity` | QQ 好感度系统。每人 0–100 独立存档，提供 `affinity` 工具给模型查/调 |
| `qq-mode-console` | QQ 会话的模式控制台（查看/切换当前会话的工作模式） |
| `qq-agent-presets` | 预设管理，支持管理员通过 QQ 直接执行受限命令 |
| `dsh-bili-subagent` | 派子代理去刷 B 站：搜视频、读字幕、挑值得看的、汇报 |
| `dsh-infinite-gen-x` | 一套生成类提示词框架（角色/场景/叙事扩展） |

装法：整个目录丢进 `%APPDATA%\dsh-desktop\harness\plugins\`，然后在 DSH 的 bundle 配置里挂上，重启 DSH。

## scripts

### 出图（NovelAI）
| 脚本 | 说明 |
|---|---|
| `nai-parallel.ps1` | 批量并发出图，多 key 轮换，失败自动落付费兜底。核心脚本 |
| `nai-free.ps1` / `nai-free-one.ps1` | 单张出图（免费 relay） |
| `nai-gen.ps1` / `nai-one.ps1` / `nai-race.ps1` | 其他几种出图封装 |
| `latent-img.ps1` | latent.moe 免费出图 |
| `naitag.py` | 本地 tag 查询（配魔导书 xlsx） |
| `magicbook.py` | 查桌面「魔导书.xlsx」里的成套 tag |
| `tagsearch.py` | 查本地 22 万条 danbooru 标签库（含中文名、热度、关联） |
| `tagsgallery.py` | 查 tags.gallery 抓下来的词库 |
| `contact-sheet.py` | 批量出图后做带文件名的联系表，方便挑图 |
| `imgmeta.py` | 读图片内嵌的生成参数（NAI/A1111），能还原 seed、正负串 |

> 出图脚本需要 key 池文件，自己建一个 `nai-keys.txt` 放 key，一行一把。

### QQ / 桥接
| 脚本 | 说明 |
|---|---|
| `qq-chat-export.ps1` | 定时导出私聊记录 |
| `export-private-chat.py` / `export-private-tail.py` | 导出完整记录 / 只导尾部 |
| `meme-find.mjs` / `meme-del.mjs` | 表情包按语境搜索 / 删除 |
| `whale-sticker.ps1` | 生成表情包贴纸图 |
| `whale-voice.ps1` | 生成语音条 |
| `new-private-session.ps1` / `new-group-session.ps1` | 手动开新会话 |
| `read-session.mjs` / `tail-session.mjs` | 读会话记录 |

### 运维
| 脚本 | 说明 |
|---|---|
| `disk-steward.ps1` | 磁盘盘查与安全清理 |
| `backup-dsh.ps1` / `dsh-self-backup.ps1` / `dsh-full-backup.ps1` | 备份（增量 / 全量） |
| `backup-self.ps1` / `backup-self-full.ps1` | 同上，另一套 |
| `dsh-guard.ps1` / `dsh-guard-restart.ps1` | DSH 看守与安全重启（重启会断线，从进程外触发） |
| `restart-dsh.ps1` | 直接重启 |
| `clash-keepalive.ps1` | Clash 代理保活 |
| `mute-mode.ps1` + `mute-on/off/toggle.cmd` | 静音模式开关 |
| `autostart-suite.ps1` | 开机自启套件 |
| `open-dsh-web.ps1` | 从日志里找最新 token 打开 Web GUI |
| `pc-tools.ps1` | 剪贴板、通知、截图、前台窗口 |
| `cf-fetch.mjs` | 过 Cloudflare 抓网页 |
| `capability-ledger.mjs` | 能力清单登记 |

## 环境

- Windows 10/11 + PowerShell 5.1
- DSH Desktop
- 跑 `.ps1` 一律 `powershell -NoProfile -ExecutionPolicy Bypass -File <路径>`，不要 `&` 直接调用
- `.ps1` 尽量只写 ASCII；写文件用 `[IO.File]::WriteAllText` + `New-Object Text.UTF8Encoding($false)`

## 许可

MIT。自己用的东西，仅供参考，出问题自己担。
