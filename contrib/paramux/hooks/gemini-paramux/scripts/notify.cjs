"use strict";

const { spawnSync } = require("node:child_process");
const path = require("node:path");

const MAX_INPUT_BYTES = 1024 * 1024;
const PARAMUX_TIMEOUT_MS = 5000;
const MAX_STDERR_BYTES = 64 * 1024;
const EVENTS = Object.freeze({
  BeforeAgent: Object.freeze({
    state: "working",
    message: "Gemini CLI is working",
  }),
  Notification: Object.freeze({
    state: "waiting",
    message: "Gemini CLI needs your approval",
  }),
  AfterAgent: Object.freeze({
    state: "done",
    message: "Gemini CLI finished responding",
  }),
});

let inputBytes = 0;
let inputTooLarge = false;
let inputFailed = false;
const inputChunks = [];

function fail(message, exitCode = 1) {
  process.stderr.write(`paramux Gemini hook: ${message}\n`);
  process.exitCode = Number.isInteger(exitCode) && exitCode > 0 && exitCode <= 255
    ? exitCode
    : 1;
}

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

function run(payloadText) {
  // RFC 8259 §8.1: ignore a leading BOM for interoperability. Windows
  // PowerShell 5.1 prepends one when pumping stdin on CP-65001 consoles.
  if (payloadText.charCodeAt(0) === 0xfeff) {
    payloadText = payloadText.slice(1);
  }
  let payload;
  try {
    payload = JSON.parse(payloadText);
  } catch (error) {
    fail(`invalid JSON input: ${error.message}`);
    return;
  }

  if (payload === null || Array.isArray(payload) || typeof payload !== "object") {
    fail("input must be a JSON object");
    return;
  }

  if (
    typeof payload.hook_event_name !== "string"
    || !Object.hasOwn(EVENTS, payload.hook_event_name)
  ) {
    fail("unsupported hook_event_name");
    return;
  }
  const event = EVENTS[payload.hook_event_name];
  if (
    payload.hook_event_name === "Notification"
    && payload.notification_type !== "ToolPermission"
  ) {
    fail("Notification requires notification_type ToolPermission");
    return;
  }

  let executable;
  try {
    executable = resolveParamuxExecutable();
  } catch (error) {
    fail(error.message);
    return;
  }
  const child = spawnSync(
    executable,
    ["notify", `--state=${event.state}`, event.message],
    {
      encoding: "utf8",
      maxBuffer: MAX_STDERR_BYTES,
      shell: false,
      stdio: ["ignore", "ignore", "pipe"],
      timeout: PARAMUX_TIMEOUT_MS,
      windowsHide: true,
    },
  );

  if (child.error) {
    fail(`failed to run ${executable}: ${child.error.message}`);
    return;
  }
  if (child.status !== 0) {
    const detail = typeof child.stderr === "string" ? child.stderr.trim() : "";
    fail(
      `${executable} exited with ${child.status}${detail ? `: ${detail}` : ""}`,
      child.status,
    );
    return;
  }

  process.stdout.write("{}");
}

process.stdin.on("data", (chunk) => {
  inputBytes += chunk.length;
  if (inputBytes > MAX_INPUT_BYTES) {
    inputTooLarge = true;
    inputChunks.length = 0;
    return;
  }
  if (!inputTooLarge) inputChunks.push(chunk);
});

process.stdin.on("error", (error) => {
  inputFailed = true;
  fail(`failed to read stdin: ${error.message}`);
});

process.stdin.on("end", () => {
  if (inputFailed) return;
  if (inputTooLarge) {
    fail(`input exceeds ${MAX_INPUT_BYTES} bytes`);
    return;
  }
  run(Buffer.concat(inputChunks, inputBytes).toString("utf8"));
});
