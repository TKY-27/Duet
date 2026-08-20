#!/usr/bin/env node
/**
 * Regenerates THIRD_PARTY_LICENSES.md from hub/package-lock.json.
 *
 * `check-license-inventory.mjs` verifies the result in CI; this script is how
 * you produce it after a dependency change, so the inventory cannot drift from
 * the lockfile by hand-editing.
 *
 * Usage: npm run license:generate   (run `npm ci` first)
 */
import fs from "node:fs";
import path from "node:path";

const hubRoot = process.cwd();
const repoRoot = path.resolve(hubRoot, "..");
const lockPath = path.join(hubRoot, "package-lock.json");
const packageJsonPath = path.join(hubRoot, "package.json");
const noticePath = path.join(repoRoot, "THIRD_PARTY_LICENSES.md");

const lock = JSON.parse(fs.readFileSync(lockPath, "utf8"));
const hubPackage = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));

const locked = [];
for (const packagePath of Object.keys(lock.packages ?? {})) {
  if (!packagePath.startsWith("node_modules/")) continue;
  const lockEntry = lock.packages[packagePath] ?? {};
  const manifestPath = path.join(hubRoot, packagePath, "package.json");
  if (!fs.existsSync(manifestPath) && !lockEntry.optional) {
    throw new Error(`${packagePath}/package.json is missing; run npm ci before generating.`);
  }
  // npm installs only the platform-appropriate member of an optional
  // dependency set. TypeScript 7 records every platform package in the lock,
  // but most of their manifests are intentionally absent on this machine.
  // The lockfile still carries the package metadata needed for the inventory.
  const manifest = fs.existsSync(manifestPath)
    ? JSON.parse(fs.readFileSync(manifestPath, "utf8"))
    : {
        name: packagePath.replace(/^node_modules\//, ""),
        version: lockEntry.version,
        license: lockEntry.license,
      };
  locked.push({
    name: manifest.name ?? packagePath.replace(/^node_modules\//, ""),
    version: manifest.version ?? lockEntry.version ?? "unknown",
    license: normalizeLicense(manifest.license ?? manifest.licenses) ?? "UNKNOWN",
  });
}
locked.sort((a, b) => a.name.localeCompare(b.name));

const direct = [
  ...Object.keys(hubPackage.dependencies ?? {}).map((name) => ({ name, scope: "runtime" })),
  ...Object.keys(hubPackage.devDependencies ?? {}).map((name) => ({ name, scope: "development" })),
].map(({ name, scope }) => {
  const entry = locked.find((candidate) => candidate.name === name);
  if (!entry) throw new Error(`${name} is declared in package.json but absent from the lockfile.`);
  return { ...entry, scope };
});

const licenseCounts = new Map();
for (const entry of locked) {
  licenseCounts.set(entry.license, (licenseCounts.get(entry.license) ?? 0) + 1);
}
const countRows = [...licenseCounts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
const nonMit = locked.filter((entry) => entry.license !== "MIT");

const today = new Date().toISOString().slice(0, 10);
const markdown = `# Third-Party License Inventory

This inventory is generated from \`hub/package-lock.json\` by \`npm run license:generate\`
and verified in CI by \`npm run license:check\`. Do not edit it by hand.
The SwiftPM app declares no third-party package dependencies.

Last generated: ${today}.

## Direct Hub Dependencies

| Package | Version | Scope | License |
| --- | --- | --- | --- |
${direct.map((e) => `| \`${e.name}\` | ${e.version} | ${e.scope} | ${e.license} |`).join("\n")}

## Locked License Summary

| License | Package count |
| --- | ---: |
${countRows.map(([license, count]) => `| ${license} | ${count} |`).join("\n")}

Non-MIT locked packages:

| Package | Version | License |
| --- | --- | --- |
${nonMit.map((e) => `| \`${e.name}\` | ${e.version} | ${e.license} |`).join("\n")}

## Complete Locked Package Inventory

| Package | Version | License |
| --- | --- | --- |
${locked.map((e) => `| \`${e.name}\` | ${e.version} | ${e.license} |`).join("\n")}
`;

fs.writeFileSync(noticePath, markdown);
console.log(`Wrote ${path.relative(repoRoot, noticePath)}: ${locked.length} locked packages, ${direct.length} direct.`);

function normalizeLicense(license) {
  if (typeof license === "string") return license.trim();
  if (Array.isArray(license)) {
    return license
      .map((entry) => (typeof entry === "string" ? entry : entry?.type))
      .filter(Boolean)
      .join(" OR ");
  }
  if (license && typeof license === "object" && typeof license.type === "string") return license.type;
  return undefined;
}
