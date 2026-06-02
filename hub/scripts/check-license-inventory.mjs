#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const hubRoot = process.cwd();
const repoRoot = path.resolve(hubRoot, "..");
const lockPath = path.join(hubRoot, "package-lock.json");
const noticePath = path.join(repoRoot, "THIRD_PARTY_LICENSES.md");
const forbiddenLicensePattern = /\b(?:AGPL|GPL|LGPL|SSPL|BUSL)\b|Commons Clause/i;

const lock = JSON.parse(fs.readFileSync(lockPath, "utf8"));
const inventory = fs.readFileSync(noticePath, "utf8");
const packagePaths = Object.keys(lock.packages ?? {})
  .filter((packagePath) => packagePath.startsWith("node_modules/"))
  .sort();

const failures = [];

for (const packagePath of packagePaths) {
  const packageJsonPath = path.join(hubRoot, packagePath, "package.json");
  if (!fs.existsSync(packageJsonPath)) {
    failures.push(`${packagePath}: package.json is missing; run npm ci before license scan.`);
    continue;
  }

  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
  const name = packageJson.name ?? packagePath.replace(/^node_modules\//, "");
  const license = normalizeLicense(packageJson.license ?? packageJson.licenses);

  if (!license) {
    failures.push(`${name}: license field is missing.`);
    continue;
  }
  if (forbiddenLicensePattern.test(license)) {
    failures.push(`${name}: review copyleft or restricted license "${license}".`);
  }
  if (!inventory.includes(name)) {
    failures.push(`${name}: missing from THIRD_PARTY_LICENSES.md.`);
  }
}

if (failures.length > 0) {
  console.error("License inventory check failed:");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log(`Checked ${packagePaths.length} package licenses against THIRD_PARTY_LICENSES.md.`);

function normalizeLicense(value) {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) {
    return value.map(normalizeLicense).filter(Boolean).join(" OR ");
  }
  if (value && typeof value === "object" && typeof value.type === "string") {
    return value.type;
  }
  return "";
}
