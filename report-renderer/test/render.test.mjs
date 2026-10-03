import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { renderHTML } from "../template.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const echarts = require("echarts");
const VL = require("../shared/vl-charts.js");
const sample = JSON.parse(readFileSync(join(here, "../samples/sample-snapshot.json"), "utf8"));

test("sample snapshot renders to a multi-page PDF offline", () => {
  const out = join(mkdtempSync(join(tmpdir(), "vl-test-")), "r.pdf");
  const run = spawnSync(process.execPath, [join(here, "../render.mjs"), join(here, "../samples/sample-snapshot.json"), out], { encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  const pdf = readFileSync(out);
  assert.equal(pdf.subarray(0, 4).toString(), "%PDF");
  assert.ok(pdf.length > 40_000, `PDF unexpectedly small (${pdf.length} bytes)`);
});

test("labels are escaped in HTML and chart SVG", () => {
  const evil = structuredClone(sample);
  evil.meta.clientName = "<script>alert(1)</script>";
  evil.expenses.items[0].label = "<img src=x onerror=alert(1)>";
  const html = renderHTML(evil, {}, "/fonts");
  assert.ok(!html.includes("<script>alert(1)"));
  assert.ok(html.includes("&lt;script&gt;"));
  const chart = echarts.init(null, null, { renderer: "svg", ssr: true, width: 600, height: 300 });
  chart.setOption(VL.builders.rankedBars(evil.expenses, VL.themes.print, {}));
  const svg = chart.renderToSVGString();
  chart.dispose();
  assert.ok(!svg.includes("<img src=x"));
});

test("print theme disables animation and tooltips; dark theme keeps tooltips", () => {
  const print = VL.builders.waterfall(sample.waterfall, VL.themes.print, {});
  assert.equal(print.animation, false);
  assert.equal(print.tooltip.show, false);
  const dark = VL.builders.waterfall(sample.waterfall, VL.themes.dark, {});
  assert.equal(dark.tooltip.show, true);
  assert.equal(VL.builders.waterfall(sample.waterfall, VL.themes.dark, { reducedMotion: true }).animation, false);
});

test("stable colors: same account id gives the same color", () => {
  const a = { id: "acct:35", label: "Checking", category: "asset" };
  assert.equal(VL.colorFor(a, VL.themes.dark), VL.colorFor({ ...a, label: "Renamed" }, VL.themes.dark));
  assert.equal(VL.colorFor({ id: "x", category: "overdraft" }, VL.themes.dark), VL.themes.dark.negative);
});

test("new chart types render as SVG in print and build interactive options in dark", () => {
  const cases = [["moneyFlow", sample.moneyFlow], ["sparklines", sample.sparklines], ["trendMixed", sample.trend]];
  for (const [kind, data] of cases) {
    assert.ok(data, `${kind} data missing from sample`);
    const chart = echarts.init(null, null, { renderer: "svg", ssr: true, width: 700, height: 300 });
    chart.setOption(VL.builders[kind](data, VL.themes.print, {}));
    assert.ok(chart.renderToSVGString().length > 1000, kind);
    chart.dispose();
    assert.ok(VL.builders[kind](data, VL.themes.dark, {}).tooltip.show, kind);
  }
  assert.equal(VL.builders.trendMixed(sample.trend, VL.themes.print, {}).dataZoom, undefined);
  assert.ok(VL.builders.trendMixed(sample.trend, VL.themes.dark, {}).dataZoom.length === 2);
  const tree = { nodes: [{ id: "a", accountID: "1", label: "Vehicle", value: 400, valueText: "$400.00", children: [{ id: "b", accountID: "2", label: "Fuel", value: 400, valueText: "$400.00", children: [] }] }], totalText: "$400.00", credits: [] };
  const cal = { accountID: "1", accountLabel: "Checking", start: "2025-10-01", end: "2026-09-29", days: [{ date: "2026-07-03", count: 2, amountText: "$20.00" }], maxCount: 2, lastPostingText: "x" };
  for (const [kind, data] of [["expenseTreemap", tree], ["postingCalendar", cal]]) {
    const chart = echarts.init(null, null, { renderer: "svg", ssr: true, width: 700, height: 200 });
    chart.setOption(VL.builders[kind](data, VL.themes.dark, {}));
    assert.ok(chart.renderToSVGString().includes("<svg"), kind);
    chart.dispose();
  }
});

// 2026-10-03 cover redesign (Figma Option A): hero net figure, change chips colored by
// whether the move helped, the trend-area chart, and a partial-month note.
test("cover: hero, change chips and trend area", () => {
  const r = structuredClone(sample);
  const html = renderHTML(r, { trendArea: "<svg></svg>" }, "/fonts");
  assert.match(html, /class="band"/);
  assert.match(html, /class="hero"/);
  assert.match(html, /What matters this month/);
  const expenses = r.kpis.find((k) => k.id === "expenses");
  expenses.comparisonText = "+$100.00 vs June 2026 (+5.0%)";
  const revenue = r.kpis.find((k) => k.id === "revenue");
  revenue.comparisonText = "+$100.00 vs June 2026 (+5.0%)";
  const h2 = renderHTML(r, {}, "/fonts");
  // Expenses rising is bad; revenue rising is good.
  const chips = [...h2.matchAll(/<div class="stat"><div class="lbl">([^<]+)<\/div>.*?class="chip (good|bad|flat)"/g)].map((m) => [m[1], m[2]]);
  assert.deepEqual(Object.fromEntries(chips).Expenses, "bad");
  assert.deepEqual(Object.fromEntries(chips).Revenue, "good");
  r.meta.isPartialMonth = true; r.performanceBridge = null;
  assert.match(renderHTML(r, {}, "/fonts"), /Month in progress/);
  const svg = (() => { const c = echarts.init(null, null, { renderer: "svg", ssr: true, width: 720, height: 190 }); c.setOption(VL.builders.trendArea(r.trend ?? { points: [{ label: "Jul 2026", revenue: 1, expenses: 1 }] }, VL.themes.print, {})); const out = c.renderToSVGString(); c.dispose(); return out; })();
  assert.match(svg, /^<svg/);
});
