#!/usr/bin/env node
// Voice Ledger monthly report renderer.
//   node render.mjs <snapshot.json> <output.pdf> [--keep-html] [--summary]
// --summary renders the 2-page Client Summary from the same snapshot.
// Stdout: one JSON progress line per stage ({"stage": ...}).
// Stderr: one JSON error line ({"error", "hint"}) and a non-zero exit.
// Never prints report figures; runs fully offline.
import { readFileSync, writeFileSync, mkdtempSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { spawnSync } from "node:child_process";
import { renderHTML } from "./template.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

function progress(stage, extra = {}) { process.stdout.write(JSON.stringify({ stage, ...extra }) + "\n"); }
function fail(error, hint, code = 1) {
  process.stderr.write(JSON.stringify({ error, hint }) + "\n");
  process.exit(code);
}

const [snapshotPath, outputPath, ...flags] = process.argv.slice(2);
if (!snapshotPath || !outputPath) fail("Missing arguments.", "Usage: node render.mjs <snapshot.json> <output.pdf>", 64);

let echarts, VL;
try {
  echarts = require("echarts");
  VL = require("./shared/vl-charts.js");
} catch (e) {
  fail("Chart library not installed.", `Run "npm install" in ${here}.`);
}

let report;
try {
  report = JSON.parse(readFileSync(snapshotPath, "utf8"));
} catch (e) {
  fail("Could not read the report snapshot.", "The snapshot file is missing or not valid JSON; regenerate the report.");
}
if (report.schemaVersion !== 1) fail(`Unsupported snapshot schema ${report.schemaVersion}.`, "Update the renderer to match the app version.");

progress("charts");
// "($4,264.76)" -> "-$4,264.76" inside chart text (owner request 2026-10-03).
function minusSigns(svgText) { return svgText.replace(/\((\$[\d,.]+[KkMm]?)\)/g, "-$1"); }
const theme = VL.themes.print;
function svg(builder, data, width, height) {
  if (!data) return null;
  const chart = echarts.init(null, null, { renderer: "svg", ssr: true, width, height });
  try {
    chart.setOption(VL.builders[builder](data, theme, {}));
    return chart.renderToSVGString();
  } finally {
    chart.dispose();
  }
}

let charts;
try {
  const breakdownHeight = (b) => b ? Math.max(80, 19 * (b.positiveItems.length + b.negativeItems.length) + 26) : 0;
  const expensesHeight = report.expenses ? Math.max(110, 24 * report.expenses.items.length + 12) : 0;
  charts = {
    trendMixed: report.trend ? svg("trendMixed", report.trend, 720, 210) : null,
    trendArea: report.trend ? svg("trendArea", report.trend, 720, 190) : null,
    trendBars: report.trend ? svg("trendRevenueExpenses", report.trend, 720, 200) : null,
    sparklines: report.sparklines ? svg("sparklines", report.sparklines, 720, 30 * report.sparklines.rows.length + 8) : null,
    moneyFlow: report.moneyFlow ? svg("moneyFlow", report.moneyFlow, 720, 290) : null,
    trendNetIncome: report.trend ? svg("trendNetIncome", report.trend, 720, 140) : null,
    waterfall: svg("waterfall", report.waterfall, 720, 210),
    expenses: svg("rankedBars", report.expenses, 720, expensesHeight),
    aging: svg("agingBars", report.receivables, 720, 125),
    payables: svg("agingBars", report.payables, 720, 125),
    assets: svg("breakdownDiverging", report.assets, 720, breakdownHeight(report.assets)),
    liabilities: svg("breakdownDiverging", report.liabilitiesAndEquity, 720, breakdownHeight(report.liabilitiesAndEquity))
  };
  for (const k of Object.keys(charts)) if (charts[k]) charts[k] = minusSigns(charts[k]);
} catch (e) {
  fail("Chart rendering failed.", `A chart could not be drawn (${e.message}). The snapshot is kept for diagnosis.`);
}

progress("html");
const fontDir = resolve(here, "node_modules/@fontsource/inter/files");
if (!existsSync(join(fontDir, "inter-latin-400-normal.woff"))) fail("Report font missing.", `Run "npm install" in ${here}.`);
const workDir = mkdtempSync(join(tmpdir(), "vl-report-"));
const htmlPath = join(workDir, "report.html");
writeFileSync(htmlPath, renderHTML(report, charts, fontDir, { summary: flags.includes("--summary") }), "utf8");

progress("pdf");
const python = join(here, ".venv/bin/python");
if (!existsSync(python)) fail("PDF engine not installed.", `Create it: cd "${here}" && python3 -m venv .venv && .venv/bin/pip install weasyprint (needs "brew install pango").`);
const result = spawnSync(python, [join(here, "render_pdf.py"), htmlPath, resolve(outputPath), here, workDir], { encoding: "utf8" });
if (result.status !== 0) {
  const detail = (result.stderr || "").split("\n").filter(Boolean).slice(-1)[0] ?? "unknown error";
  fail("PDF generation failed.", `WeasyPrint: ${detail.slice(0, 300)}`);
}
if (flags.includes("--keep-html")) progress("html-kept", { path: htmlPath });
else rmSync(workDir, { recursive: true, force: true });
progress("done", { path: resolve(outputPath) });
