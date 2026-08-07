/**
 * Extract auto-mode block events from pirouette session logs.
 *
 * Pairs each `Auto mode blocked …` result with the tool call that triggered it
 * and the user turns the classifier saw as intent, and flags sessions where the
 * user gave up and turned auto mode off.
 *
 *   node auto-mode/scan-blocks.mjs <session-root> [--since YYYY-MM-DD] [--full]
 */
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const args = process.argv.slice(2);
const roots = args.filter((a) => !a.startsWith("--"));
const sinceArg = args.find((a) => a.startsWith("--since="));
const since = sinceArg ? new Date(sinceArg.split("=")[1]) : undefined;
const full = args.includes("--full");

const files = [];
function walk(d) {
  for (const e of readdirSync(d, { withFileTypes: true })) {
    const p = join(d, e.name);
    if (e.isDirectory()) walk(p);
    else if (e.name.endsWith(".jsonl")) files.push(p);
  }
}
for (const r of roots) walk(r);

const clip = (s, n) => (s.length > n ? `${s.slice(0, n)}…` : s);
const oneLine = (s) => s.replace(/\s+/g, " ").trim();

let totalBlocks = 0;
const disabledIn = [];

for (const f of files) {
  if (since && statSync(f).mtime < since) continue;
  let entries;
  try {
    entries = readFileSync(f, "utf8")
      .split("\n")
      .filter(Boolean)
      .map((l) => {
        try {
          return JSON.parse(l);
        } catch {
          return null;
        }
      })
      .filter(Boolean);
  } catch {
    continue;
  }

  const session = f.replace(/.*\/sessions\//, "").replace(/\/.*/, "");
  const hits = [];
  let disabled = false;
  const userTurns = [];
  const callsById = new Map();

  for (const e of entries) {
    const ts = e.timestamp ? new Date(e.timestamp) : undefined;
    if (since && ts && ts < since) continue;
    const m = e.message ?? e;
    const content = Array.isArray(m?.content) ? m.content : [];

    if (m?.role === "user") {
      const t = content.filter((c) => c?.type === "text").map((c) => c.text).join("\n").trim();
      if (t && !t.startsWith("Auto mode")) userTurns.push(t);
    }
    for (const c of content) {
      if (c?.type === "toolCall") callsById.set(c.id, c);
    }
    if (/Auto mode disabled/.test(JSON.stringify(e))) disabled = true;

    // Block verdicts arrive as an errored toolResult message.
    if (m?.role === "toolResult") {
      const text = content.filter((x) => x?.type === "text").map((x) => x.text).join("\n");
      const match = text.match(/Auto mode blocked (\w+): ([^]*?)(?: If this is a false positive|$)/);
      if (match) {
        const call = callsById.get(m.toolCallId);
        hits.push({
          tool: match[1],
          reason: oneLine(match[2]),
          call: call ? oneLine(JSON.stringify(call.arguments)) : "(call not found)",
          intent: userTurns.slice(-2).map(oneLine).join("  ||  "),
          ts: e.timestamp,
        });
      }
    }
  }

  if (!hits.length) continue;
  totalBlocks += hits.length;
  if (disabled) disabledIn.push(session);
  console.log(`\n########## ${session}  (${hits.length} blocks${disabled ? ", USER TURNED AUTO MODE OFF" : ""})`);
  for (const h of hits) {
    console.log(`\n  [${h.ts ?? "?"}] ${h.tool}`);
    console.log(`  INTENT: ${clip(h.intent, full ? 100000 : 300)}`);
    console.log(`  CALL:   ${clip(h.call, full ? 100000 : 400)}`);
    console.log(`  BLOCK:  ${clip(h.reason, full ? 100000 : 400)}`);
  }
}

console.log(`\n\n===== ${totalBlocks} blocks; auto mode turned off in: ${disabledIn.join(", ") || "(none)"} =====`);
