import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

export const root = fileURLToPath(new URL("../", import.meta.url));

export async function run(command, args, { env = {}, timeout = 600_000, capture = false } = {}) {
  const child = spawn(command, args, { cwd: root, env: { ...process.env, ...env },
    stdio: ["ignore", capture ? "pipe" : "inherit", "inherit"] });
  let output = "", timedOut = false, forceStop;
  child.stdout?.on("data", bytes => { output += bytes; });
  const timer = setTimeout(() => {
    timedOut = true;
    child.kill("SIGTERM");
    forceStop = setTimeout(() => child.kill("SIGKILL"), 10_000);
  }, timeout);
  try {
    const code = await new Promise((resolve, reject) => {
      child.once("exit", resolve); child.once("error", reject);
    });
    assert.equal(timedOut, false, `${command} exceeded its test deadline`);
    assert.equal(code, 0, `${command} failed`);
    return output.trim();
  } finally { clearTimeout(timer); clearTimeout(forceStop); }
}

export async function withFixture(action) {
  const server = spawn(process.execPath, ["Tests/Fixtures/server.mjs"], {
    cwd: root, stdio: ["ignore", "pipe", "inherit"] });
  const reader = createInterface({ input: server.stdout });
  let timer;
  try {
    const ready = await new Promise((resolve, reject) => {
      timer = setTimeout(() => reject(new Error("Fixture startup timed out")), 10_000);
      reader.once("line", line => {
        try { resolve(JSON.parse(line)); } catch (error) { reject(error); }
      });
      server.once("exit", () => reject(new Error("Fixture stopped before readiness")));
      server.once("error", reject);
    });
    clearTimeout(timer);
    const url = new URL(ready.origin);
    assert.equal(url.hostname, "127.0.0.1"); assert.equal(url.protocol, "http:");
    assert.ok(url.port);
    await action(ready.origin);
  } finally {
    clearTimeout(timer); reader.close();
    if (server.exitCode === null && server.signalCode === null) {
      const stopped = new Promise(resolve => server.once("exit", resolve));
      server.kill("SIGTERM");
      const force = setTimeout(() => server.kill("SIGKILL"), 5_000);
      await stopped; clearTimeout(force);
    }
  }
}
