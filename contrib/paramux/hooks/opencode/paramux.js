import { spawn } from "node:child_process";
import path from "node:path";

const PARAMUX_TIMEOUT_MS = 5000;
const MAX_STDERR_BYTES = 64 * 1024;
const MAX_TRACKED_ERROR_SESSIONS = 256;
const NOTIFICATIONS = Object.freeze({
  working: Object.freeze({ state: "working", message: "OpenCode is working" }),
  waiting: Object.freeze({ state: "waiting", message: "OpenCode needs your approval" }),
  done: Object.freeze({ state: "done", message: "OpenCode finished responding" }),
  error: Object.freeze({ state: "error", message: "OpenCode stopped with an error" }),
});

function resolveParamuxExecutable() {
  if (process.platform !== "win32") {
    throw new Error("Paramux agent hooks are supported on Windows only");
  }

  const root = process.env.PARAMUX_HOME;
  if (typeof root !== "string" || root.length === 0 || !path.isAbsolute(root)) {
    throw new Error(
      "PARAMUX_HOME must be an absolute path; rerun install-paramux.ps1",
    );
  }

  return path.join(root, "paramux.com");
}

function runParamux(notification) {
  const executable = resolveParamuxExecutable();

  return new Promise((resolve, reject) => {
    const child = spawn(
      executable,
      ["+notify", `--state=${notification.state}`, notification.message],
      {
        shell: false,
        stdio: ["ignore", "ignore", "pipe"],
        windowsHide: true,
      },
    );
    const stderrChunks = [];
    let stderrBytes = 0;
    let settled = false;

    const finish = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) reject(error);
      else resolve();
    };

    const timer = setTimeout(() => {
      child.kill();
      finish(new Error(`${executable} timed out`));
    }, PARAMUX_TIMEOUT_MS);

    child.stderr.on("data", (chunk) => {
      if (stderrBytes >= MAX_STDERR_BYTES) return;
      const remaining = MAX_STDERR_BYTES - stderrBytes;
      const kept = chunk.subarray(0, remaining);
      stderrChunks.push(kept);
      stderrBytes += kept.length;
    });
    child.on("error", (error) => finish(error));
    child.on("close", (exitCode) => {
      if (exitCode === 0) {
        finish();
        return;
      }
      const detail = Buffer.concat(stderrChunks).toString("utf8").trim();
      finish(
        new Error(
          `${executable} exited with ${exitCode}${detail ? `: ${detail}` : ""}`,
        ),
      );
    });
  });
}

export const ParamuxPlugin = async ({ client }) => {
  const erroredSessions = new Set();
  let suppressNextIdle = false;
  let queue = Promise.resolve();

  const reportError = async (error) => {
    const message = error instanceof Error ? error.message : String(error);
    try {
      await client?.app?.log?.({
        body: {
          service: "paramux-agent-hook",
          level: "error",
          message,
        },
      });
    } catch {
      console.error(`paramux OpenCode hook: ${message}`);
    }
  };

  const notify = (notification) => {
    queue = queue.then(() => runParamux(notification)).catch(reportError);
    return queue;
  };

  return {
    event: async ({ event }) => {
      const properties = event?.properties;
      const sessionID = typeof properties?.sessionID === "string"
        ? properties.sessionID
        : undefined;

      if (event?.type === "session.error") {
        if (sessionID) {
          if (erroredSessions.size >= MAX_TRACKED_ERROR_SESSIONS) {
            erroredSessions.delete(erroredSessions.values().next().value);
          }
          erroredSessions.add(sessionID);
        } else {
          suppressNextIdle = true;
        }
        return notify(NOTIFICATIONS.error);
      }

      if (event?.type === "permission.asked") {
        return notify(NOTIFICATIONS.waiting);
      }

      if (event?.type !== "session.status") return;
      if (properties?.status?.type === "busy") {
        if (sessionID) erroredSessions.delete(sessionID);
        return notify(NOTIFICATIONS.working);
      }
      if (properties?.status?.type !== "idle") return;

      if (sessionID && erroredSessions.delete(sessionID)) return;
      if (!sessionID && suppressNextIdle) {
        suppressNextIdle = false;
        return;
      }
      return notify(NOTIFICATIONS.done);
    },
  };
};
