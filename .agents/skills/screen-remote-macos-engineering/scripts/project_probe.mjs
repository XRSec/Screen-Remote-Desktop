#!/usr/bin/env node

import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const repo = path.resolve(process.cwd());
const outer = path.dirname(repo);

function run(cwd, command) {
  const result = spawnSync(command[0], command.slice(1), { cwd, encoding: "utf8" });
  return { code: result.status ?? 1, output: `${result.stdout ?? ""}${result.stderr ?? ""}`.trim() };
}

function swiftFiles(directory) {
  const result = [];
  for (const entry of readdirSync(directory)) {
    const file = path.join(directory, entry);
    const stat = statSync(file);
    if (stat.isDirectory()) result.push(...swiftFiles(file));
    else if (entry.endsWith(".swift")) result.push(file);
  }
  return result;
}

function status(label, directory) {
  const result = run(directory, ["git", "status", "--short"]);
  console.log(`${label}:`);
  console.log(result.code === 0 ? result.output || "  clean" : "  unavailable");
}

if (!statSync(path.join(repo, "Screen-Remote.xcodeproj")).isDirectory()) {
  throw new Error("Run this probe from the Screen-Remote-macOS repository root");
}

const files = swiftFiles(path.join(repo, "Screen-Remote"))
  .map((file) => ({
    path: path.relative(repo, file),
    lines: readFileSync(file, "utf8").split(/\r?\n/).length,
  }))
  .sort((a, b) => b.lines - a.lines || a.path.localeCompare(b.path));

console.log("Screen Remote macOS project probe");
console.log(`repo: ${repo}`);
console.log(`Swift files: ${files.length}`);
for (const file of files.filter((item) => item.lines > 500)) {
  console.log(`  ${file.lines.toString().padStart(4)}  ${file.path}`);
}
if (!files.some((item) => item.lines > 500)) console.log("  no Swift file exceeds 500 lines");

status("macOS status", repo);
status("outer status", outer);
status("dadb status", path.join(outer, "external", "dadb"));
status("macOS Wiki status", path.join(outer, "external", "wiki-macos"));
