#!/usr/bin/env bash
# skill-check step: Workflow scripts parse and declare a bare meta.name
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
node <<'JS'
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const files = execFileSync("git", ["ls-files", "workflows/*.js"], { encoding: "utf8" })
  .split("\n").filter(Boolean);
if (files.length === 0) {
  console.log("ok    no workflow scripts tracked - nothing to check");
  process.exit(0);
}
// The Workflow host evaluates a script as an async function body, so
// top-level `await` and `return` are legal there but not in a plain ES
// module - a bare `node --check` fails on a correct script. Mirror the
// host instead: lift `export const meta` to a plain declaration, then
// parse (never run) the rest as one async function body.
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
let fail = 0;
for (const f of files) {
  const src = fs.readFileSync(f, "utf8")
    .replace(/^export\s+const\s+meta\b/m, "const meta");
  try {
    new AsyncFunction(src);
  } catch (e) {
    console.log(`FAIL  ${f}: ${e.name}: ${e.message}`);
    fail = 1;
    continue;
  }
  const m = /const\s+meta\b[\s\S]{0,400}?\bname:\s*['"]([^'"]+)['"]/.exec(src);
  const want = path.basename(f, ".js");
  if (!m) {
    console.log(`FAIL  ${f}: meta has no name:`);
    fail = 1;
  } else if (m[1].includes(":")) {
    console.log(`FAIL  ${f}: meta.name must be bare, not namespaced (got '${m[1]}') - callers add the <plugin>: prefix`);
    fail = 1;
  } else if (m[1] !== want) {
    console.log(`FAIL  ${f}: meta.name '${m[1]}' != filename '${want}'`);
    fail = 1;
  } else {
    console.log(`ok    ${f} (meta.name ${m[1]})`);
  }
}
process.exit(fail);
JS
