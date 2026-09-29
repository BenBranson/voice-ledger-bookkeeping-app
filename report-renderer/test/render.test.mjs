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
