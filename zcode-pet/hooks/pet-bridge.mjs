#!/usr/bin/env node
/**
 * zcode-pet bridge: translates ZCode hook events into the desktop pet's state file.
 *
 * Contract:
 *   - stdin: the hook event JSON (ZCode compatible payload, camelCase + snake_case aliases).
 *   - writes ~/.zcode/pet/state.json (atomic) + appends ~/.zcode/pet/events.jsonl (capped).
 *   - bystander only: exit 0, NO stdout (empty stdout = zero impact on the agent loop).
 *   - on SessionStart / UserPromptSubmit / PreToolUse: ensures the pet app is running
 *     (spawns detached; first run compiles it via swiftc, ~5-10s, does not block the hook).
 *
 * Manual smoke test:
 *   printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"s1"}' \
 *     | node hooks/pet-bridge.mjs
 */
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const PET_DIR = path.join(os.homedir(), ".zcode", "pet");
const STATE_PATH = path.join(PET_DIR, "state.json");
const EVENTS_PATH = path.join(PET_DIR, "events.jsonl");
const PID_PATH = path.join(PET_DIR, "pet.pid");

const pluginRoot =
  process.env.ZCODE_PLUGIN_ROOT ||
  process.env.CLAUDE_PLUGIN_ROOT ||
  path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const APP_DIR = path.join(pluginRoot, "app");
const BIN_PATH = path.join(APP_DIR, "zcode-pet-bin");
const BUILD_PATH = path.join(APP_DIR, "build.sh");

function log(msg) {
  process.stderr.write(`[zcode-pet] ${msg}\n`);
}

function readStdinJson() {
  return new Promise((resolve) => {
    let raw = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (c) => (raw += c));
    process.stdin.on("end", () => {
      try {
        resolve(raw.trim() ? JSON.parse(raw) : {});
      } catch {
        resolve({});
      }
    });
    // Safety: never hang the agent loop if stdin never closes.
    setTimeout(() => resolve({}), 2000);
  });
}

function pick(obj, ...keys) {
  for (const k of keys) {
    if (obj[k] !== undefined && obj[k] !== null) return obj[k];
  }
  return undefined;
}

/** Map a hook event to the pet status the Swift app renders. */
function toPetState(input) {
  const event = pick(input, "hook_event_name", "hookEventName") || "Unknown";
  const base = {
    sessionId: pick(input, "session_id", "sessionId") || "",
    turnId: pick(input, "turnId") || "",
    ts: Date.now(),
    event,
  };
  switch (event) {
    case "SessionStart":
      return { ...base, status: "greet", note: pick(input, "source") || "startup" };
    case "UserPromptSubmit": {
      const prompt = String(pick(input, "prompt") || "");
      return { ...base, status: "thinking", note: prompt.slice(0, 60) };
    }
    case "PreToolUse":
    case "PostToolUse":
      return { ...base, status: "working", tool: pick(input, "tool_name", "toolName") || "Tool" };
    case "PostToolUseFailure":
      return {
        ...base,
        status: "error",
        tool: pick(input, "tool_name", "toolName") || "Tool",
        note: String(pick(input, "error") || pick(input, "error_details") || "").slice(0, 80),
      };
    case "PermissionRequest":
      return {
        ...base,
        status: "attention",
        tool: pick(input, "tool_name", "toolName") || "Tool",
      };
    case "Stop": {
      const count = Number(pick(input, "toolCallCount") || 0);
      return { ...base, status: count > 0 ? "celebrate" : "waiting", toolCallCount: count };
    }
    default:
      return { ...base, status: "idle" };
  }
}

function atomicWriteJson(file, obj) {
  const tmp = `${file}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(obj));
  fs.renameSync(tmp, file);
}

function appendEvent(state) {
  const line = JSON.stringify({
    ts: state.ts,
    event: state.event,
    status: state.status,
    tool: state.tool || "",
    sessionId: state.sessionId,
  });
  try {
    // Cap: if the log grows past ~64KB keep only the newest 200 lines.
    let body = line + "\n";
    if (fs.existsSync(EVENTS_PATH)) {
      const prev = fs.readFileSync(EVENTS_PATH, "utf8");
      if (prev.length > 65536) {
        body = prev.trimEnd().split("\n").slice(-199).concat(line).join("\n") + "\n";
      } else {
        body = prev + line + "\n";
      }
    }
    fs.writeFileSync(EVENTS_PATH, body);
  } catch (err) {
    log(`events append failed: ${err.message}`);
  }
}

function isPetAlive() {
  try {
    const pid = Number(fs.readFileSync(PID_PATH, "utf8").trim());
    if (!Number.isFinite(pid) || pid <= 0) return false;
    process.kill(pid, 0); // throws if not running
    return true;
  } catch {
    return false;
  }
}

function ensurePetRunning() {
  if (isPetAlive()) return;
  const cmd = `"${BUILD_PATH}" >/dev/null 2>&1 && exec "${BIN_PATH}" >/dev/null 2>&1`;
  try {
    const child = spawn("/bin/sh", ["-c", cmd], {
      detached: true,
      stdio: "ignore",
      cwd: APP_DIR,
    });
    child.unref();
    log(`pet spawned (pid ${child.pid})`);
  } catch (err) {
    log(`pet spawn failed: ${err.message}`);
  }
}

async function main() {
  const input = await readStdinJson();
  fs.mkdirSync(PET_DIR, { recursive: true });
  const state = toPetState(input);
  atomicWriteJson(STATE_PATH, state);
  appendEvent(state);
  if (["SessionStart", "UserPromptSubmit", "PreToolUse"].includes(state.event)) {
    ensurePetRunning();
  }
  // Bystander: exit 0, no stdout.
}

main().catch((err) => {
  log(`bridge error: ${err && err.stack ? err.stack : err}`);
  process.exit(0); // never disturb the agent loop
});
