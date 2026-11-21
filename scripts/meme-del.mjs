import { DatabaseSync } from "node:sqlite"
import { existsSync, unlinkSync } from "node:fs"
import { join } from "node:path"
const root = process.argv[2]
const rel = process.argv[3]
const db = new DatabaseSync(join(root, "index.db"))
const rows = db.prepare("SELECT path, tag, caption FROM memes WHERE path = ?").all(rel)
console.log("rows:", JSON.stringify(rows))
db.prepare("DELETE FROM memes WHERE path = ?").run(rel)
db.close()
const file = join(root, rel)
if (existsSync(file)) { unlinkSync(file); console.log("deleted file", file) } else { console.log("file already gone", file) }
