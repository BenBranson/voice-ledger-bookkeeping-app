// Monthly client report HTML/CSS for WeasyPrint. Pure layout: every value
// arrives pre-computed and pre-formatted in the report snapshot, and every
// chart arrives as a static SVG. All text is HTML-escaped here.

const esc = (v) => String(v ?? "")
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  .replace(/"/g, "&quot;").replace(/'/g, "&#39;");

const svgImg = (svg, alt) => svg
  ? `<img class="chart" alt="${esc(alt)}" src="data:image/svg+xml;base64,${Buffer.from(svg, "utf8").toString("base64")}">`
  : "";

const neg = (text) => /^\(/.test(String(text)) ? " neg" : "";

function table(columns, rows, opts = {}) {
  const head = columns.map((c, i) => `<th class="${i === 0 ? "" : "num"}">${esc(c)}</th>`).join("");
  const body = rows.map((r) => `<tr class="${r.total ? "total" : ""}">${r.cells.map((c, i) =>
    `<td class="${i === 0 ? `lbl d${Math.min(r.depth ?? 0, 4)}` : `num${neg(c)}`}">${esc(c)}</td>`).join("")}</tr>`).join("");
  return `<table class="${opts.className ?? ""}"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`;
}

function fontFaces(fontDir) {
  return [[400, "400"], [500, "500"], [600, "600"], [700, "700"]].map(([w, f]) =>
    `@font-face{font-family:"Inter";font-weight:${w};src:url("file://${fontDir}/inter-latin-${f}-normal.woff") format("woff");}`).join("\n");
}

function css(fontDir, meta) {
  const flag = meta.isSample ? "SAMPLE DATA — not a real client" : meta.environment === "sandbox" ? "SANDBOX DATA — not a real client's books" : "";
  return `
${fontFaces(fontDir)}
:root{--navy:#1B2A4A;--teal:#1F8A8A;--gold:#C9A227;--ink:#1B2A4A;--muted:#56637A;--line:#DDE3EB;--soft:#F4F7FA;--neg:#B23A48;}
@page{size:Letter;margin:0.62in 0.6in 0.72in 0.6in;
  @bottom-left{content:"${esc(meta.firmName)} · ${esc(meta.clientName)} · ${esc(meta.periodLabel)}${flag ? " · " + flag : ""}";font:500 7.5pt Inter;color:#56637A;}
  @bottom-right{content:"Page " counter(page) " of " counter(pages);font:500 7.5pt Inter;color:#56637A;}}
*{box-sizing:border-box}
html{font-family:Inter,"Helvetica Neue",Arial,sans-serif;font-size:9.5pt;color:var(--ink);line-height:1.42}
h1{font-size:21pt;font-weight:700;margin:0 0 2pt;letter-spacing:-0.2pt}
h2{font-size:13pt;font-weight:700;margin:20pt 0 8pt;padding-bottom:4pt;border-bottom:1.5pt solid var(--navy);break-after:avoid}
h2 .num{color:var(--gold);margin-right:6pt}
h3{font-size:10pt;font-weight:600;margin:12pt 0 5pt;color:var(--navy);break-after:avoid}
p{margin:0 0 6pt}
.muted{color:var(--muted)}
.small{font-size:8pt}
.masthead{border-top:4pt solid var(--navy);padding-top:10pt;margin-bottom:6pt}
.firm{font-size:8pt;font-weight:600;letter-spacing:1.4pt;text-transform:uppercase;color:var(--teal)}
.meta{display:flex;flex-wrap:wrap;gap:4pt 14pt;font-size:8.2pt;color:var(--muted);margin-top:4pt}
.meta b{color:var(--ink);font-weight:600}
.flag{display:inline-block;margin-top:6pt;padding:3pt 7pt;border:1pt solid var(--gold);color:#6E5812;background:#FBF6E6;border-radius:3pt;font-size:8pt;font-weight:600}
.kpis{display:flex;gap:8pt;margin-top:10pt;break-inside:avoid}
.kpi{flex:1;border:1pt solid var(--line);border-top:3pt solid var(--teal);border-radius:4pt;padding:8pt 9pt;break-inside:avoid;background:#fff}
.kpi .label{font-size:7.5pt;font-weight:600;letter-spacing:0.8pt;text-transform:uppercase;color:var(--muted)}
.kpi .value{font-size:15pt;font-weight:700;margin:3pt 0 2pt}
.kpi .value.neg{color:var(--neg)}
.kpi .cmp{font-size:7.8pt;color:var(--ink)}
.kpi .detail{font-size:7pt;color:var(--muted);margin-top:2pt}
figure{margin:6pt 0 4pt;break-inside:avoid;page-break-inside:avoid}
figure .caption{font-size:8pt;color:var(--muted);margin-top:3pt}
img.chart{width:100%;display:block}
.two{display:flex;gap:14pt}
.two>div{flex:1;min-width:0}
table{width:100%;border-collapse:collapse;margin:4pt 0 8pt;font-size:8.4pt}
thead{display:table-header-group}
th{text-align:left;font-weight:600;font-size:7.5pt;letter-spacing:0.5pt;text-transform:uppercase;color:var(--muted);border-bottom:1pt solid var(--navy);padding:3pt 4pt}
td{padding:2.6pt 4pt;border-bottom:0.5pt solid var(--line);vertical-align:top}
tr{break-inside:avoid}
td.num,th.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
td.neg{color:var(--neg)}
tr.total td{font-weight:600;border-top:0.8pt solid var(--navy);background:var(--soft)}
td.d1{padding-left:10pt}td.d2{padding-left:18pt}td.d3{padding-left:26pt}td.d4{padding-left:34pt}
.note{background:var(--soft);border-left:3pt solid var(--teal);padding:6pt 8pt;font-size:8.2pt;margin:6pt 0;break-inside:avoid}
.warn{border-left-color:var(--gold)}
ul.findings{list-style:none;margin:0;padding:0}
ul.findings li{border-bottom:0.5pt solid var(--line);padding:4pt 0;break-inside:avoid}
ul.findings .t{font-weight:600}
ul.findings .amt{float:right;font-weight:600;font-variant-numeric:tabular-nums}
.tag{display:inline-block;font-size:6.8pt;font-weight:700;letter-spacing:0.6pt;text-transform:uppercase;padding:1pt 4pt;border-radius:2pt;margin-right:4pt}
.tag.v{background:#E3F2F2;color:#135E5E}.tag.r{background:#FBF1D9;color:#6E5812}.tag.a{background:#E6EBF3;color:var(--navy)}
.check{font-weight:600}.check.ok{color:var(--teal)}.check.no{color:var(--neg)}
.section{break-before:auto}
.keep{break-inside:avoid}
.totals{display:flex;gap:10pt;font-size:8pt;margin:2pt 0 6pt}
.totals span{background:var(--soft);padding:2pt 6pt;border-radius:3pt}
`;
}

function kpiCards(kpis) {
  return `<div class="kpis">${kpis.map((k) => `
    <div class="kpi"><div class="label">${esc(k.label)}</div>
    <div class="value${k.isNegative ? " neg" : ""}">${esc(k.valueText)}</div>
    <div class="cmp">${esc(k.comparisonText)}</div><div class="detail">${esc(k.detail)}</div></div>`).join("")}</div>`;
}

function comparisonTable(rows, priorLabel) {
  return table(["", "This month", priorLabel, "Change", "% change"],
    rows.map((r) => ({ cells: [r.label, r.currentText, r.priorText, r.changeText, r.percentText] })));
}

function findingList(items, tag, tagClass) {
  if (!items.length) return `<p class="muted small">None.</p>`;
  return `<ul class="findings">${items.map((f) => `<li><span class="amt">${esc(f.amountText)}</span>
    <span class="tag ${tagClass}">${tag}</span><span class="t">${esc(f.title)}</span>
    ${f.detail ? `<div class="small muted">${esc(f.detail)}</div>` : ""}
    ${f.action ? `<div class="small"><b>Next step:</b> ${esc(f.action)}</div>` : ""}</li>`).join("")}</ul>`;
}

function breakdownBlock(b, svg) {
  if (!b) return "";
  const negatives = b.negativeItems.length
    ? table(["Negative balance", "Type", "Amount"], b.negativeItems.map((n) => ({ cells: [n.label, n.note ?? "", n.valueText] })))
    : "";
  return `<div class="keep"><h3>${esc(b.title)}</h3>
    ${svgImg(svg, `${b.title}: signed balances by account`)}
    <div class="totals"><span>Positive ${esc(b.positiveSubtotalText)}</span><span>Negative ${esc(b.negativeSubtotalText)}</span><span><b>Net ${esc(b.netText)}</b></span>${b.reportedTotalText ? `<span>QuickBooks total ${esc(b.reportedTotalText)} — ${b.reconciles ? "ties" : "does not tie"}</span>` : ""}</div>
    ${negatives}</div>`;
}

export function renderHTML(report, charts, fontDir) {
  const m = report.meta;
  const flag = m.isSample ? "SAMPLE DATA — fictional figures for review, not a client report"
    : m.environment === "sandbox" ? "SANDBOX DATA — generated from a QuickBooks test company" : "";
  const h2 = (title) => `<h2><span class="num">§N§</span>${esc(title)}</h2>`;

  const perf = [];
  if (charts.trendRevenueExpenses) perf.push(`<figure><h3>Revenue and expenses by month</h3>${svgImg(charts.trendRevenueExpenses, "Revenue versus expenses by month")}<div class="caption">Revenue and total expenses by month. ${esc(report.trend?.note ?? "")}</div></figure>`);
  if (charts.trendNetIncome) perf.push(`<figure><h3>Net income by month</h3>${svgImg(charts.trendNetIncome, "Net income by month")}<div class="caption">Net income by month; bars below the line are losses.</div></figure>`);
  if (report.monthOverMonth.length) perf.push(`<h3>Compared with last month</h3>${comparisonTable(report.monthOverMonth, "Last month")}`);
  if (report.yearOverYear) perf.push(`<h3>Compared with the same month last year</h3>${comparisonTable(report.yearOverYear, "Last year")}`);
  if (charts.waterfall) perf.push(`<figure><h3>How revenue became ${esc(report.waterfall.steps.at(-1).label.toLowerCase())}</h3>${svgImg(charts.waterfall, "Revenue to net income bridge")}<div class="caption">${report.waterfall.reconciles ? "Each step uses QuickBooks' own section totals and ties exactly to reported net income." : esc(report.waterfall.note)}</div></figure>`);

  const exp = report.expenses;
  const expenseSection = exp ? `
    ${h2("Expense analysis")}
    <figure>${svgImg(charts.expenses, "Largest expense categories")}<div class="caption">Largest operating-expense categories this month${exp.items.some((i) => i.category === "other") ? "; smaller categories grouped as Other" : ""}.</div></figure>
    ${table(["Category", "Amount", "Share"], exp.allItems.map((i) => ({ cells: [i.label, i.valueText, i.share == null ? "—" : (i.share * 100).toFixed(1) + "%"] }))
      .concat(exp.creditItems.map((i) => ({ cells: [i.label + " (credit)", i.valueText, "—"] })))
      .concat([{ total: true, cells: ["Total operating expenses", exp.totalText, exp.reconciles ? "Ties to QuickBooks" : `QuickBooks: ${exp.reportedTotalText ?? "n/a"}`] }]))}` : "";

  const cash = report.cash;
  const ar = report.receivables;
  const cashSection = (cash || ar || report.assets) ? `
    ${h2("Cash and receivables")}
    ${cash ? `<div class="two"><div><h3>Bank balances</h3>${table(["Account", "Balance"], cash.accounts.map((a) => ({ cells: [a.label + (a.note ? ` — ${a.note}` : ""), a.valueText] })).concat(cash.totalText ? [{ total: true, cells: ["Total bank accounts", cash.totalText] }] : []))}</div>
      <div><h3>Cash movement</h3>${cash.cashFlow.length ? table(["", "Amount"], cash.cashFlow.map((r) => ({ total: r.isTotal, cells: [r.label, r.valueText] }))) : ""}<div class="note">${esc(cash.note)}</div></div></div>` : ""}
    ${ar ? `<div class="keep"><h3>Accounts receivable aging</h3><figure>${svgImg(charts.aging, "Receivables by age")}</figure>
      <div class="two"><div>${table(["Age", "Amount"], ar.buckets.map((b) => ({ cells: [b.label, b.valueText] })).concat([{ total: true, cells: ["Total receivables", ar.totalText] }]))}</div>
      <div>${ar.topCustomers.length ? table(["Largest balances", "Amount"], ar.topCustomers.map((c) => ({ cells: [c.label, c.valueText] }))) : ""}</div></div>
      <p class="small muted">${esc(ar.note)}</p></div>` : ""}
    ${report.assets || report.liabilitiesAndEquity ? `<h3>Balance sheet at a glance</h3><p class="small muted">${esc(m.balanceDateLabel)}. Bars to the left of the line are negative balances.</p>
      ${breakdownBlock(report.assets, charts.assets)}${breakdownBlock(report.liabilitiesAndEquity, charts.liabilities)}` : ""}` : "";

  let sectionNumber = 0;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>${esc(m.clientName)} — Monthly Financial Report — ${esc(m.periodLabel)}</title>
<meta name="author" content="${esc(m.firmName)}"><meta name="keywords" content="voice-ledger-snapshot:${esc(m.snapshotID)}">
<meta name="generator" content="Voice Ledger">
<style>${css(fontDir, m)}</style></head><body>
<div class="masthead"><div class="firm">${esc(m.firmName)}</div>
<h1>Monthly Financial Report</h1>
<div style="font-size:12pt;font-weight:600">${esc(m.clientName)} · ${esc(m.periodLabel)}${m.isPartialMonth ? " (month in progress)" : ""}</div>
<div class="meta"><span>Generated <b>${esc(m.generatedAtLabel)}</b></span><span>Accounting basis <b>${esc(m.accountingBasis)}</b></span><span><b>${esc(m.balanceDateLabel)}</b></span></div>
${flag ? `<div class="flag">${esc(flag)}</div>` : ""}</div>

${h2("Monthly overview")}
${kpiCards(report.kpis)}

${perf.length ? h2("Financial performance") + perf.join("\n") : ""}
${expenseSection}
${cashSection}

${h2("Findings and next steps")}
<p class="small muted">From Voice Ledger's automated review of the books. <b>Verified</b> items are confirmed from the data; <b>needs review</b> items are possible issues to confirm, not established errors.</p>
<h3>Verified observations</h3>${findingList(report.verifiedFindings, "Verified", "v")}
<h3>Needs review</h3>${findingList(report.reviewFindings, "Review", "r")}
<h3>Recommended actions</h3>${report.recommendedActions.length ? `<ul class="findings">${report.recommendedActions.map((a) => `<li><span class="tag a">Action</span>${esc(a)}</li>`).join("")}</ul>` : `<p class="muted small">None this month.</p>`}

${h2("Supporting detail")}
${report.profitAndLossTable.length ? `<h3>Profit &amp; Loss — ${esc(m.periodLabel)}</h3>${table(["Account", "Amount"], report.profitAndLossTable.map((r) => ({ depth: r.depth, total: r.isTotal, cells: [r.label, r.valueText] })))}` : ""}
${report.balanceSheetTable.length ? `<h3>Balance Sheet — ${esc(m.balanceDateLabel.replace("Balances as of ", ""))}</h3>${table(["Account", "Balance"], report.balanceSheetTable.map((r) => ({ depth: r.depth, total: r.isTotal, cells: [r.label, r.valueText] })))}` : ""}
<h3>Reconciliation checks</h3>
${table(["Check", "Result"], report.checks.map((c) => ({ cells: [`${c.label} — ${c.detail}`, c.passed ? "Passed" : "Not passed"] })))}
<h3>Notes on data and limitations</h3>
<ul class="small">${report.notes.map((x) => `<li>${esc(x)}</li>`).join("")}</ul>
<p class="small muted">Report snapshot ${esc(m.snapshotID.slice(0, 16))} · prepared with Voice Ledger from read-only QuickBooks Online data.</p>
</body></html>`.replace(/§N§/g, () => String(++sectionNumber));
}
