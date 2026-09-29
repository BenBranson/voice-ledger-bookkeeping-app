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
h1{font-size:20pt;font-weight:700;margin:0 0 1pt;letter-spacing:-0.2pt}
h2{font-size:13pt;font-weight:700;margin:14pt 0 6pt;padding-bottom:4pt;border-bottom:1.5pt solid var(--navy);break-after:avoid}
h2 .num{color:var(--gold);margin-right:6pt}
h3{font-size:10pt;font-weight:600;margin:12pt 0 5pt;color:var(--navy);break-after:avoid}
p{margin:0 0 6pt}
.muted{color:var(--muted)}
.small{font-size:8pt}
.masthead{border-top:4pt solid var(--navy);padding-top:8pt;margin-bottom:2pt}
.firm{font-size:8pt;font-weight:600;letter-spacing:1.4pt;text-transform:uppercase;color:var(--teal)}
.meta{display:flex;flex-wrap:wrap;gap:4pt 14pt;font-size:8.2pt;color:var(--muted);margin-top:4pt}
.meta b{color:var(--ink);font-weight:600}
.flag{display:inline-block;margin-top:6pt;padding:3pt 7pt;border:1pt solid var(--gold);color:#6E5812;background:#FBF6E6;border-radius:3pt;font-size:8pt;font-weight:600}
.kpis{display:flex;gap:8pt;margin-top:6pt;break-inside:avoid}
.kpi{flex:1;border:1pt solid var(--line);border-top:3pt solid var(--teal);border-radius:4pt;padding:6pt 8pt;break-inside:avoid;background:#fff}
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
h1,h3,.kpi .label{bookmark-level:none}
h2{bookmark-level:1}
.page{break-before:page}
.lede{font-size:10pt;margin:2pt 0 8pt}
.story{border:1pt solid var(--line);border-radius:4pt;padding:7pt 9pt;margin:4pt 0 10pt;break-inside:avoid;background:#fff}
.story div{margin:1.5pt 0}
.story b{display:inline-block;min-width:92pt;color:var(--teal);font-size:7.6pt;letter-spacing:0.6pt;text-transform:uppercase}
.takeaways{margin:6pt 0 2pt;padding:0;list-style:none}
.takeaways li{padding:3.5pt 0 3.5pt 14pt;border-bottom:0.5pt solid var(--line);position:relative;font-size:9.6pt}
.takeaways li:before{content:"";position:absolute;left:0;top:8pt;width:6pt;height:6pt;border-radius:3pt;background:var(--gold)}
.health{display:grid;grid-template-columns:1fr 1fr;gap:7pt;margin-top:6pt}
.hc{border:1pt solid var(--line);border-left:4pt solid var(--teal);border-radius:4pt;padding:4pt 7pt;break-inside:avoid}
.hc.attention{border-left-color:var(--gold)}
.hc.insufficient{border-left-color:#9AA5B4}
.hc .area{font-weight:700;font-size:10pt}
.hc .q{font-size:7.8pt;color:var(--muted)}
.hc .st{display:inline-block;margin:2pt 0 1pt;font-size:7.6pt;font-weight:700;letter-spacing:0.5pt;text-transform:uppercase;padding:1.5pt 5pt;border-radius:2pt;background:#E3F2F2;color:#135E5E}
.hc.attention .st{background:#FBF1D9;color:#6E5812}
.hc.insufficient .st{background:#ECEFF3;color:#56637A}
.hc .d{font-size:8.4pt}
.work{border:1pt solid var(--line);border-radius:4pt;padding:7pt 9pt;margin:0 0 7pt;break-inside:avoid}
.work .top{display:flex;justify-content:space-between;gap:8pt}
.work .t{font-weight:600}
.work .st{font-size:7.4pt;font-weight:700;letter-spacing:0.5pt;text-transform:uppercase;white-space:nowrap}
.work .st.correctedVerified{color:var(--teal)}.work .st.awaitingVerification,.work .st.awaitingClient{color:#8C6D1F}.work .st.notAnError{color:var(--muted)}
.work .row{font-size:8.3pt;margin-top:2pt}
.work .row b{color:var(--muted);font-weight:600}
.counts{display:flex;gap:8pt;margin:6pt 0 10pt}
.counts div{flex:1;border:1pt solid var(--line);border-radius:4pt;padding:6pt 8pt;text-align:center}
.counts .n{font-size:15pt;font-weight:700}
.counts .l{font-size:7.4pt;color:var(--muted);text-transform:uppercase;letter-spacing:0.5pt}
`;
}

function kpiCards(kpis) {
  return `<div class="kpis">${kpis.map((k) => `
    <div class="kpi"><div class="label">${esc(k.label)}</div>
    <div class="value${k.isNegative ? " neg" : ""}">${esc(k.valueText)}</div>
    <div class="cmp">${esc(k.comparisonText)}</div><div class="detail">${esc(k.detail)}</div></div>`).join("")}</div>`;
}

function comparisonTable(rows, priorLabel) {
  return `<div class="keep">` + table(["", "This month", priorLabel, "Change", "% change"],
    rows.map((r) => ({ cells: [r.label, r.currentText, r.priorText, r.changeText, r.percentText] }))) + `</div>`;
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

function story(n) {
  if (!n) return "";
  return `<div class="story"><div><b>What happened</b>${esc(n.happened)}</div><div><b>Why it matters</b>${esc(n.matters)}</div><div><b>Next step</b>${esc(n.next)}</div></div>`;
}

function agingBlock(a, svg, title, friendly, whoLabel) {
  if (!a) return "";
  return `<div class="keep">${title ? `<h3>${esc(title)}</h3>` : ""}${svg ? `<figure>${svgImg(svg, friendly)}</figure>` : ""}
    <div class="two"><div>${table(["Age", "Amount"], a.buckets.map((b) => ({ cells: [b.label, b.valueText] })).concat([{ total: true, cells: ["Total", a.totalText] }]))}</div>
    <div>${a.topCustomers.length ? table([whoLabel, "Amount"], a.topCustomers.map((c) => ({ cells: [c.label, c.valueText] }))) : ""}</div></div>
    <p class="small muted">${esc(a.note)}</p></div>`;
}

export function renderHTML(report, charts, fontDir) {
  const m = report.meta;
  const flag = m.isSample ? "SAMPLE DATA — fictional figures for review, not a client report"
    : m.environment === "sandbox" ? "SANDBOX DATA — generated from a QuickBooks test company" : "";
  const h2 = (title) => `<h2><span class="num">§N§</span>${esc(title)}</h2>`;
  const N = report.narratives ?? {};
  const sections = [];

  // 1 — Month at a glance
  sections.push(`
<div class="masthead"><div class="firm">${esc(m.firmName)}</div>
<h1>Monthly Financial Report</h1>
<div style="font-size:12pt;font-weight:600">${esc(m.clientName)} · ${esc(m.periodLabel)}${m.isPartialMonth ? " (month in progress)" : ""}</div>
<div class="meta"><span>Prepared by <b>${esc(report.preparedBy || m.firmName)}</b></span><span>Generated <b>${esc(m.generatedAtLabel)}</b></span><span>Accounting basis <b>${esc(m.accountingBasis)}</b></span><span><b>${esc(m.balanceDateLabel)}</b></span></div>
${flag ? `<div class="flag">${esc(flag)}</div>` : ""}</div>
${h2("Your month at a glance")}
${kpiCards(report.kpis)}
${charts.sparklines ? `<figure class="keep" style="margin-top:8pt">${svgImg(charts.sparklines, "Twelve-month trends for revenue, expenses, net income and cash")}<div class="caption">12-month trend, ${esc(report.sparklines.rangeLabel)}. The dot marks this month; its color shows whether the change from last month helped (teal) or hurt (red).</div></figure>` : ""}
${report.takeaways?.length ? `<ul class="takeaways">${report.takeaways.map((t) => `<li>${esc(t)}</li>`).join("")}</ul>` : ""}
${report.healthChecks?.length ? `<h3>Business health check</h3><div class="health">${report.healthChecks.map((h) => `<div class="hc ${esc(h.statusKind)}"><div class="area">${esc(h.area)}</div><div class="q">${esc(h.question)}</div><div class="st">${esc(h.status)}</div><div class="d">${esc(h.detail)}</div></div>`).join("")}</div>` : ""}`);

  // 2 — Priorities and decisions
  const counts = (report.workSummary ?? []).map((r) => `<div><div class="n">${esc(r.valueText)}</div><div class="l">${esc(r.label)}</div></div>`).join("");
  sections.push(`<div class="page">${h2("Priorities and decisions")}
<p class="lede">The three things that matter most before next month's close.</p>
${report.priorities?.length ? table(["Action", "Who", "When", "Why"], report.priorities.map((p) => ({ cells: [p.action, p.owner, p.timing, p.why] })), { className: "prio" }) : `<p class="muted">No priority actions this month.</p>`}
<h3>Questions for you</h3>
${report.questionsForClient?.length ? `<ul class="findings">${report.questionsForClient.map((q) => `<li><span class="tag r">Question</span>${esc(q)}</li>`).join("")}</ul>` : `<p class="muted small">No open questions.</p>`}
${counts ? `<h3>Bookkeeping work this month</h3><div class="counts">${counts}</div><p class="small muted">Details on the “Bookkeeping work completed” page.</p>` : ""}</div>`);

  // 3 — Sales and profitability
  const perf = [];
  if (charts.trendMixed) perf.push(`<figure><h3>Revenue, expenses and profit margin by month</h3>${svgImg(charts.trendMixed, "Revenue and expenses by month with profit margin")}<div class="caption">Bars use the left axis; the margin line (net income as a share of revenue) uses the right. Months without revenue have no margin. ${esc(report.trend?.note ?? "")}</div></figure>`);
  if (charts.trendNetIncome) perf.push(`<figure><h3>Net income by month</h3>${svgImg(charts.trendNetIncome, "Net income by month")}<div class="caption">Bars below the line are losses.</div></figure>`);
  if (report.monthOverMonth.length) perf.push(`<h3>Compared with last month</h3>${comparisonTable(report.monthOverMonth, "Last month")}`);
  if (report.yearOverYear) perf.push(`<h3>Compared with the same month last year</h3>${comparisonTable(report.yearOverYear, "Last year")}`);
  if (charts.waterfall) perf.push(`<figure class="keep"><h3>How revenue became ${esc(report.waterfall.steps.at(-1).label.toLowerCase())}</h3>${svgImg(charts.waterfall, "Revenue to net income bridge")}<div class="caption">${report.waterfall.reconciles ? "Each step uses QuickBooks' own section totals and ties exactly to reported net income." : esc(report.waterfall.note)}</div></figure>`);
  if (perf.length) sections.push(`<div class="page">${h2("Sales and profitability")}${story(N.performance)}${perf.join("\n")}</div>`);

  // 4 — Where the money went
  const exp = report.expenses;
  if (exp) sections.push(`<div class="page">${h2("Where the money went")}${story(N.expenses)}
    ${charts.moneyFlow ? `<figure class="keep"><h3>Every dollar in, every dollar out</h3>${svgImg(charts.moneyFlow, "Money flow from income to costs and profit")}<div class="caption">${esc(report.moneyFlow.note)}</div></figure>` : ""}
    <figure>${svgImg(charts.expenses, "Largest expense categories")}<div class="caption">Largest operating-expense categories this month${exp.items.some((i) => i.category === "other") ? "; smaller categories grouped as Other" : ""}.</div></figure>
    ${report.expenseChanges?.length ? `<h3>Biggest changes from last month</h3>${table(["Category", "This month", "Last month", "Change", "% change"], report.expenseChanges.map((r) => ({ cells: [r.label, r.currentText, r.priorText, r.changeText, r.percentText] })))}` : ""}
    <p class="small muted">Operating expenses total ${esc(exp.totalText)}${exp.reconciles ? ", which ties to QuickBooks" : ` (QuickBooks reports ${esc(exp.reportedTotalText ?? "n/a")})`}. Every category appears in the Profit &amp; Loss at the back of this report.</p></div>`);

  // 5 — Cash, customers who haven't paid, bills coming due
  const cash = report.cash;
  if (cash || report.receivables || report.payables) sections.push(`<div class="page">${h2("Cash position")}${story(N.cash)}
    ${cash ? `<div class="two"><div><h3>Bank balances</h3>${table(["Account", "Balance"], cash.accounts.map((a) => ({ cells: [a.label + (a.note ? ` — ${a.note}` : ""), a.valueText] })).concat(cash.totalText ? [{ total: true, cells: ["Total bank accounts", cash.totalText] }] : []))}</div>
      <div><h3>Where cash came from and went</h3>${cash.cashFlow.length ? table(["", "Amount"], cash.cashFlow.map((r) => ({ total: r.isTotal, cells: [r.label, r.valueText] }))) : ""}<div class="note">${esc(cash.note)}</div></div></div>` : ""}
    ${report.receivables ? `<div class="keep"><h3>Customers who haven't paid (accounts receivable)</h3>${story(N.receivables)}${agingBlock(report.receivables, charts.aging, "", "Receivables by age", "Largest balances")}</div>` : ""}
    ${report.payables ? `<div class="keep"><h3>Bills the business owes (accounts payable)</h3>${story(N.payables)}${agingBlock(report.payables, charts.payables, "", "Payables by age", "Largest vendors")}</div>` : ""}</div>`);

  // 6 — Financial position
  if (report.position?.length || report.assets) sections.push(`<div class="page">${h2("Financial position")}${story(N.position)}
    ${report.position?.length ? table(["", "Amount"], report.position.map((r) => ({ total: r.isTotal, cells: [r.label, r.valueText] }))) : ""}
    <p class="small muted">${esc(m.balanceDateLabel)}. In the charts below, bars left of the line are negative balances.</p>
    ${breakdownBlock(report.assets, charts.assets)}${breakdownBlock(report.liabilitiesAndEquity, charts.liabilities)}</div>`);

  // 7 — Bookkeeping work completed
  const work = report.workCompleted ?? [];
  sections.push(`<div class="page">${h2("Bookkeeping work completed")}
    <p class="lede">What I found in the books and what I did about it. Correcting a record makes the numbers accurate; it doesn't by itself earn or recover money, so each item states its effect on the reported figures.</p>
    ${counts ? `<div class="counts">${counts}</div>` : ""}
    ${work.length ? work.map((w) => `<div class="work"><div class="top"><span class="t">${esc(w.title)}</span><span class="st ${esc(w.status)}">${esc(w.statusLabel)}</span></div>
      <div class="row"><b>Found:</b> ${esc(w.found)}</div>
      <div class="row"><b>What I did:</b> ${esc(w.action)}</div>
      <div class="row"><b>Effect on the numbers:</b> ${esc(w.impact)}</div>
      <div class="row small muted">${esc(w.doneBy)} · ${esc(w.doneAtLabel)} · affects ${esc(w.affectedPeriodLabel)} books · ${esc(w.amountText)}</div></div>`).join("") : `<p class="muted">No corrections were recorded for this period.</p>`}</div>`);

  // 8 — Open items and reliability
  sections.push(`<div class="page">${h2("Open items and reliability")}
    <p class="small muted"><b>Verified</b> items are confirmed from the data; <b>needs review</b> items are possible issues, not established errors.</p>
    <h3>Confirmed issues still open</h3>${findingList(report.verifiedFindings, "Verified", "v")}
    <h3>Possible issues to review</h3>${findingList(report.reviewFindings, "Review", "r")}
    <h3>Reconciliation checks</h3>
    ${table(["Check", "Result"], report.checks.map((c) => ({ cells: [`${c.label} — ${c.detail}`, c.passed ? "Passed" : "Not passed"] })))}
    <h3>Notes on data and limitations</h3>
    <ul class="small">${report.notes.map((x) => `<li>${esc(x)}</li>`).join("")}</ul></div>`);

  // 9 — Supporting statements
  const cmp = report.comparativeProfitAndLoss ?? [];
  sections.push(`<div class="page">${h2("Financial statements")}
    ${cmp.length ? `<h3>Profit &amp; Loss — ${esc(m.periodLabel)} compared with last month</h3>${table(["Account", "This month", "Last month"], cmp.map((r) => ({ depth: r.depth, total: r.isTotal, cells: [r.label, r.currentText, r.priorText] })))}` : ""}
    ${report.balanceSheetTable.length ? `<h3>Balance Sheet — ${esc(m.balanceDateLabel.replace("Balances as of ", ""))}</h3>${table(["Account", "Balance"], report.balanceSheetTable.map((r) => ({ depth: r.depth, total: r.isTotal, cells: [r.label, r.valueText] })))}` : ""}
    ${report.cashFlowStatement?.length ? `<h3>Statement of Cash Flows — ${esc(m.periodLabel)}</h3>${table(["", "Amount"], report.cashFlowStatement.map((r) => ({ depth: r.depth, total: r.isTotal, cells: [r.label, r.valueText] })))}` : ""}
    <p class="small muted">Report snapshot ${esc(m.snapshotID.slice(0, 16))} · prepared with Voice Ledger from read-only QuickBooks Online data.</p></div>`);

  let sectionNumber = 0;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>${esc(m.clientName)} — Monthly Financial Report — ${esc(m.periodLabel)}</title>
<meta name="author" content="${esc(m.firmName)}"><meta name="keywords" content="voice-ledger-snapshot:${esc(m.snapshotID)}">
<meta name="generator" content="Voice Ledger">
<style>${css(fontDir, m)}</style></head><body>
${sections.join("\n")}
</body></html>`.replace(/§N§/g, () => String(++sectionNumber));
}
