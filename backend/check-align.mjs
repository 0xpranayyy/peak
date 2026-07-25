/**
 * Thin backend ↔ iOS alignment check (no network required).
 * Ensures expected Express routes exist in server.mjs and iOS still calls them.
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const serverSrc = fs.readFileSync(path.join(__dirname, "server.mjs"), "utf8");
const legalSrc = fs.readFileSync(path.join(__dirname, "legalPages.mjs"), "utf8");

const expectedInServer = [
  'app.get("/health"',
  'app.get("/health/live"',
  'app.post("/auth/session"',
  'app.post("/auth/import-wallet"',
  'app.post("/trading/resolve"',
  'app.post("/trading/setup"',
  'app.get("/portfolio"',
  'app.get("/activity"',
  'app.get("/orders"',
  'app.post("/orders"',
  'app.delete("/orders/:id"',
  'app.post("/deposit-address"',
];

const expectedInLegal = [
  'app.get("/legal/privacy"',
  'app.get("/legal/terms"',
  'app.get("/legal/support"',
];

const healthKeys = [
  "ok",
  "legacy",
  "privy",
  "privyAuthKey",
  "builder",
  "relayer",
  "sessions",
  "sessionStore",
  "cors",
  "uptimeSec",
];

let failed = 0;

for (const needle of expectedInServer) {
  if (!serverSrc.includes(needle)) {
    console.error(`Missing in server.mjs: ${needle}`);
    failed++;
  }
}

for (const needle of expectedInLegal) {
  if (!legalSrc.includes(needle)) {
    console.error(`Missing in legalPages.mjs: ${needle}`);
    failed++;
  }
}

for (const key of healthKeys) {
  if (!serverSrc.includes(key)) {
    console.error(`Health flag missing from server.mjs: ${key}`);
    failed++;
  }
}

for (const key of ["cashUSD", "syncReady", "builderConfigured", "needsDeploy"]) {
  if (!serverSrc.includes(key)) {
    console.error(`Portfolio/session field missing from server.mjs: ${key}`);
    failed++;
  }
}

const iosFiles = [
  path.join(__dirname, "../Peak/Networking/TradingProxyClient.swift"),
  path.join(__dirname, "../Peak/Services/TradingService.swift"),
];
const ios = iosFiles
  .filter((p) => fs.existsSync(p))
  .map((p) => fs.readFileSync(p, "utf8"))
  .join("\n");

if (ios) {
  const iosNeedles = [
    "auth/session",
    "auth/import-wallet",
    "trading/resolve",
    "trading/setup",
    '"portfolio"',
    '"activity"',
    '"orders"',
    "deposit-address",
    "cashUSD",
  ];
  for (const needle of iosNeedles) {
    if (!ios.includes(needle)) {
      console.error(`iOS trading client missing: ${needle}`);
      failed++;
    }
  }
}

if (failed > 0) {
  console.error(`check-align: ${failed} issue(s)`);
  process.exit(1);
}
console.log(
  `check-align: ok (${expectedInServer.length} server routes, ${expectedInLegal.length} legal, health+portfolio+iOS)`
);
