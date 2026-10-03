// Monthly client report HTML/CSS for WeasyPrint. Pure layout: every value
// arrives pre-computed and pre-formatted in the report snapshot, and every
// chart arrives as a static SVG. All text is HTML-escaped here.

const esc = (v) => String(v ?? "")
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  .replace(/"/g, "&quot;").replace(/'/g, "&#39;");

const svgImg = (svg, alt) => svg
  ? `<img class="chart" alt="${esc(alt)}" src="data:image/svg+xml;base64,${Buffer.from(svg, "utf8").toString("base64")}">`
  : "";

const neg = (text) => /^\(|^-\$/.test(String(text)) ? " neg" : "";
// Client-facing pages show negatives as "-$4,264.76" (owner, 2026-10-03). Only the
// financial statements in Appendix D keep accountants' brackets.
const sv = (text) => String(text ?? "").replace(/^\((.*)\)$/, "-$1");


const triangle = (up, color) => `<svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg"><path d="${up ? "M5 1 L9.5 9 L0.5 9 Z" : "M0.5 1 L9.5 1 L5 9 Z"}" fill="${color}"/></svg>`;

// "($241.66) vs June 2026 (-1.5%)" → chip "▼ $241.66" + "vs June 2026 (-1.5%)". Direction comes from
// the sign the app already formatted; whether it is good uses the metric's own direction.
function changeChip(text, higherIsBetter) {
  const m = /^(\(?[+\-]?\$[\d,.]+\)?)\s+(vs\s.*)$/.exec(String(text ?? ""));
  if (!m) return `<span>${esc(text)}</span>`;
  const amount = m[1], down = /^\(|^-/.test(amount), zero = /^\$?0\.00$|^\+?\$0\.00$/.test(amount.replace(/[()+-]/g, ""));
  const cls = zero ? "flat" : (down !== higherIsBetter ? "good" : "bad");
  return `<span class="chip ${cls}">${zero ? "" : triangle(!down, cls === "good" ? "#135E5E" : "#B23A48")}${esc(amount.replace(/[()+]/g, ""))}</span><span>${esc(m[2])}</span>`;
}

// "From sales to profit" (owner, 2026-10-03): replaces the floating waterfall, which a
// non-accountant can't read. One row per step with an explicit + or -, bars all start
// at zero, and the last row is what's left. Amounts and order come from the snapshot.
const STEP_NAMES = { revenue: "Money in (sales)", cogs: "Cost of goods sold", expenses: "Costs of running the business", "other-expenses": "Other costs (interest, fees)", adjustment: "Bookkeeping adjustment (under review)" };
function moneySteps(w, note) {
  const steps = w.steps;
  const amount = (s) => Math.abs(s.to - s.from);
  const max = Math.max(...steps.map(amount), 1);
  const last = steps.at(-1);
  const lossLeft = last.to < 0;
  const row = (s, i) => {
    const total = s.kind === "total", isFirst = i === 0, isLast = i === steps.length - 1;
    const sign = isLast ? (lossLeft ? "-" : "") : isFirst ? "+" : s.kind === "increase" ? "+" : "-";
    const value = sign + String(s.valueText).replace(/^\(|\)$/g, "").replace(/^[+-]/, "");
    const name = isLast ? (lossLeft ? "Money lost this month" : "Money left over (profit)") : (STEP_NAMES[s.id] ?? s.label);
    const cls = isLast ? (lossLeft ? "loss" : "left") : isFirst ? "in" : s.kind === "increase" ? "in" : "out";
    const hint = !isFirst && !isLast && s.kind === "increase" ? `<div class="hint">Credits were bigger than costs here, so this line added money.</div>` : "";
    return `<div class="ms ${cls}${isLast ? " end" : ""}"><div class="nm">${isLast ? "= " : ""}${esc(name)}${hint}</div><div class="tr"><div class="fl" style="width:${(100 * amount(s) / max).toFixed(1)}%"></div></div><div class="vl">${esc(value)}</div></div>`;
  };
  return `<div class="keep"><h3>From sales to profit</h3><div class="steps">${steps.map(row).join("")}</div>
  <div class="caption">${w.reconciles ? "Each line is a QuickBooks total, and they add up exactly to the result." : esc(w.note)}${note ? ` ${esc(note)}` : ""}</div></div>`;
}

function table(columns, rows, opts = {}) {
  const head = columns.map((c, i) => `<th class="${i === 0 ? "" : "num"}">${esc(c)}</th>`).join("");
  const fmt = opts.brackets ? (c) => c : sv;
  const body = rows.map((r) => `<tr class="${r.total ? "total" : ""}">${r.cells.map((c, i) =>
    `<td class="${i === 0 ? `lbl d${Math.min(r.depth ?? 0, 4)}` : `num${r.normal ? "" : neg(c)}`}">${esc(i === 0 ? c : fmt(c))}</td>`).join("")}</tr>`).join("");
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
.story div{margin:1.5pt 0;display:grid;grid-template-columns:96pt 1fr}
.story b{color:var(--teal);font-size:7.6pt;letter-spacing:0.6pt;text-transform:uppercase;padding-top:1.5pt}
.takeaways{margin:6pt 0 2pt;padding:0;list-style:none}
.takeaways li{padding:2.5pt 0 2.5pt 14pt;border-bottom:0.5pt solid var(--line);position:relative;font-size:9.6pt}
.takeaways li:before{content:"";position:absolute;left:0;top:8pt;width:6pt;height:6pt;border-radius:3pt;background:var(--gold)}
.health{display:grid;grid-template-columns:1fr 1fr 1fr 1fr;gap:6pt;margin-top:4pt}
.hc{border:1pt solid var(--line);border-left:3pt solid var(--teal);border-radius:4pt;padding:4pt 6pt;break-inside:avoid}
.hc.attention{border-left-color:var(--gold)}
.hc.insufficient{border-left-color:#9AA5B4}
.hc .area{font-weight:700;font-size:9pt}
.hc .q{font-size:7pt;color:var(--muted);line-height:1.25}
.hc .st{display:inline-block;margin:2pt 0 1pt;font-size:6.8pt;font-weight:700;letter-spacing:0.5pt;text-transform:uppercase;padding:1.5pt 5pt;border-radius:2pt;background:#E3F2F2;color:#135E5E}
.hc.attention .st{background:#FBF1D9;color:#6E5812}
.hc.insufficient .st{background:#ECEFF3;color:#56637A}
.hc .d{font-size:7.6pt;line-height:1.3}
.work{border:1pt solid var(--line);border-radius:4pt;padding:7pt 9pt;margin:0 0 7pt;break-inside:avoid}
.work .top{display:flex;justify-content:space-between;gap:8pt}
.work .t{font-weight:600}
.work .st{font-size:7.4pt;font-weight:700;letter-spacing:0.5pt;text-transform:uppercase;white-space:nowrap}
.work .st.correctedVerified{color:var(--teal)}.work .st.awaitingVerification,.work .st.awaitingClient{color:#8C6D1F}.work .st.notAnError{color:var(--muted)}
.work .row{font-size:8.3pt;margin-top:2pt}
.work .row b{color:var(--muted);font-weight:600}
.counts{display:flex;gap:8pt;margin:6pt 0 10pt}
.counts>div{flex:1;border:1pt solid var(--line);border-radius:4pt;padding:6pt 8pt;text-align:center}
.counts .n{font-size:15pt;font-weight:700}
.counts .l{font-size:7.4pt;color:var(--muted);text-transform:uppercase;letter-spacing:0.5pt}
.counts.six{display:grid;grid-template-columns:1fr 1fr 1fr;gap:6pt}.counts.six>div{padding:4pt 6pt}.counts.six .n{font-size:13pt}
.counts.six.row{grid-template-columns:repeat(6,1fr);gap:4pt}.counts.six.row .n{font-size:11pt}.counts.six.row .l{font-size:6pt;letter-spacing:0.2pt}
.hc.low{border-left-color:var(--neg)}
.hc.low .st{background:#F7E1E4;color:#8A2433}
table.prio th:nth-child(1),table.prio td:nth-child(1){width:38%}
table.prio th:nth-child(5),table.prio td:nth-child(5){width:24%}
table.prio td{text-align:left;white-space:normal}
table.prio .pa{font-weight:600}
table.bridge tr.total td{font-weight:700}
table.impact td:nth-child(2){text-align:right;width:8%}
table.impact td:nth-child(3){white-space:normal;text-align:left}
table.checks td:nth-child(2){white-space:nowrap;width:12%}
.flow{break-before:auto;margin-top:6pt}
.appendix-banner{font-size:8pt;font-weight:700;letter-spacing:1.4pt;text-transform:uppercase;color:var(--teal);border-top:4pt solid var(--navy);padding-top:6pt;margin-bottom:-4pt}

/* ——— 2026-10-03 redesign (Figma "Voice Ledger — Monthly Report redesign", Option A cover + Option B summary) ——— */
@page :first{margin-top:0}
.band{margin:-8pt -0.7in 0;padding:34pt 0.7in 20pt;background:var(--navy);color:#fff;display:flex;justify-content:space-between;align-items:center}
.band .firm{color:#9FD3D3;font-size:7.6pt}
.band>div:first-child{flex:1;min-width:0}
.band .title{white-space:nowrap;font-size:21pt;font-weight:700;letter-spacing:-0.3pt;margin:2pt 0 2pt}
.band .sub{font-size:8.6pt;color:#C7D0DE}
.band .badge{background:var(--gold);color:var(--navy);font-size:7pt;font-weight:700;letter-spacing:0.8pt;padding:3pt 8pt;border-radius:999pt;white-space:nowrap}
.metaline{font-size:7.6pt;color:var(--muted);margin:7pt 0 0}
.metaline b{color:var(--ink);font-weight:600}
.hero{display:flex;gap:22pt;align-items:flex-end;margin:18pt 0 14pt;break-inside:avoid}
.hero-l .lbl,.stat .lbl,.panel .lbl{font-size:7.6pt;font-weight:600;letter-spacing:1pt;text-transform:uppercase;color:var(--muted)}
.hero-l .big{font-size:44pt;font-weight:700;letter-spacing:-1.2pt;line-height:1.05;margin:2pt 0 4pt}
.hero-l .big.neg{color:var(--neg)}
.hero-l .cmp{font-size:8.8pt;color:var(--muted)}
.hero-r{flex:1;background:#E3F2F2;color:#135E5E;border-radius:8pt;padding:9pt 12pt}
.hero-r .s{font-size:8pt}.hero-r .v{font-size:14pt;font-weight:600;margin:1pt 0}
.chip{display:inline-block;font-size:7.6pt;font-weight:600;padding:1.5pt 6pt;border-radius:999pt;margin-right:4pt;white-space:nowrap}
.chip.good{background:#E3F2F2;color:#135E5E}.chip.bad{background:#F7E1E4;color:var(--neg)}.chip.flat{background:#ECEFF3;color:var(--muted)}
.chip svg{width:6pt;height:6pt;vertical-align:0.2pt;margin-right:2pt}
.stats{display:flex;gap:9pt;margin:0 0 14pt;break-inside:avoid}
.stat{flex:1;background:var(--soft);border-radius:8pt;padding:9pt 11pt}
.stat .v{font-size:15pt;font-weight:700;margin:2pt 0 3pt}
.stat .v.neg{color:var(--neg)}
.stat .c{font-size:7.6pt;color:var(--muted)}
.legend{display:flex;gap:14pt;align-items:center;font-size:8pt;margin-bottom:2pt}
.legend b{font-size:10pt;color:var(--ink);margin-right:4pt}
.legend .sw{display:inline-block;width:12pt;height:2.5pt;border-radius:2pt;vertical-align:2pt;margin-right:4pt}
ol.tk{list-style:none;margin:4pt 0 12pt;padding:0;counter-reset:tk}
ol.tk li{counter-increment:tk;position:relative;padding:3pt 0 3pt 22pt;font-size:9.4pt}
ol.tk li:before{content:counter(tk);position:absolute;left:0;top:3pt;width:14pt;height:14pt;border-radius:7pt;background:var(--navy);color:#fff;font-size:7.5pt;font-weight:700;text-align:center;line-height:14pt}
.strip{display:flex;gap:7pt;break-inside:avoid}
.pill{flex:1;border:1pt solid var(--teal);background:#E3F2F2;border-radius:7pt;padding:6pt 9pt}
.pill .a{font-size:7.4pt;color:var(--muted)}.pill .s{font-size:9pt;font-weight:600;color:#135E5E}
.pill.attention{border-color:#C9A227;background:#FBF1D9}.pill.attention .s{color:#6E5812}
.pill.low{border-color:var(--neg);background:#F7E1E4}.pill.low .s{color:var(--neg)}
.pill.insufficient{border-color:#9AA5B4;background:#ECEFF3}.pill.insufficient .s{color:var(--muted)}
.panels{display:flex;gap:12pt;margin:4pt 0 12pt;break-inside:avoid}
.panel{flex:1;border:1pt solid var(--line);border-radius:8pt;padding:9pt 11pt;min-width:0}
.panel h3{margin:0 0 5pt}
.hrow{border-top:0.6pt solid var(--line);padding:5pt 0}
.hrow .top{display:flex;justify-content:space-between;align-items:center;gap:6pt}
.hrow .n{font-weight:600;font-size:9pt}.hrow .d{font-size:7.8pt;color:var(--muted);line-height:1.3;margin-top:1pt}
.tagp{font-size:6.6pt;font-weight:700;letter-spacing:0.5pt;text-transform:uppercase;padding:1.5pt 6pt;border-radius:999pt;background:#E3F2F2;color:#135E5E;white-space:nowrap}
.tagp.attention{background:#FBF1D9;color:#6E5812}.tagp.low{background:#F7E1E4;color:#8A2433}.tagp.insufficient{background:#ECEFF3;color:var(--muted)}
.bar{margin:0 0 6pt}.bar .top{display:flex;justify-content:space-between;font-size:8pt}.bar .top b{font-weight:600}
.bar .track{height:5.5pt;background:var(--soft);border-radius:3pt;margin-top:2pt}.bar .fill{height:5.5pt;border-radius:3pt;background:var(--teal)}
.bar .fill.other{background:#A9B8C9}
.prow{display:flex;gap:10pt;align-items:flex-start;padding:6pt 0;border-bottom:0.6pt solid var(--line);break-inside:avoid}
.prow .no{flex:0 0 14pt;height:14pt;border-radius:7pt;background:var(--navy);color:#fff;font-size:7.5pt;font-weight:700;text-align:center;line-height:14pt}
.prow .act{flex:1}.prow .act b{font-weight:600}.prow .act div{font-size:7.8pt;color:var(--muted)}
.prow .who{flex:0 0 70pt;font-size:8pt;color:var(--muted)}.prow .when{flex:0 0 96pt;font-size:8pt;color:var(--muted)}.prow .imp{flex:0 0 120pt;font-size:8pt}

.steps{margin:4pt 0 4pt;border:1pt solid var(--line);border-radius:8pt;padding:4pt 10pt}
.ms{display:flex;align-items:center;gap:10pt;padding:6pt 0;border-bottom:0.6pt solid var(--line)}
.ms:last-child{border-bottom:none}
.ms .nm{flex:0 0 190pt;font-size:9.4pt}
.ms .hint{font-size:7.4pt;color:var(--muted)}
.ms .tr{flex:1;height:9pt;background:var(--soft);border-radius:4pt}
.ms .fl{height:9pt;border-radius:4pt}
.ms .vl{flex:0 0 78pt;text-align:right;font-weight:600;font-variant-numeric:tabular-nums;font-size:10pt}
.ms.in .fl{background:var(--teal)}.ms.in .vl{color:#135E5E}
.ms.out .fl{background:var(--neg)}.ms.out .vl{color:var(--neg)}
.ms.end{border-top:1.2pt solid var(--navy);margin-top:2pt}
.ms.end .nm{font-weight:700}.ms.end .vl{font-size:11pt}
.ms.left .fl{background:var(--navy)}.ms.left .vl{color:var(--navy)}
.ms.loss .fl{background:var(--neg)}.ms.loss .vl{color:var(--neg)}
/* refreshed look carried through every section */
h2{border-bottom:0.8pt solid var(--line)}
h2 .num{display:inline-block;background:var(--navy);color:#fff;border-radius:999pt;padding:0 6pt;font-size:8.5pt;line-height:13pt;vertical-align:1.5pt;margin-right:7pt}
.story{border:none;background:var(--soft);border-left:3pt solid var(--teal);border-radius:6pt}
.kpi{border-radius:7pt}
.counts>div{border:none;background:var(--soft);border-radius:7pt}
.note{border-radius:6pt}
.tag{border-radius:999pt;padding:1pt 6pt}
.work{border-radius:7pt}
tr.total td{background:#EEF2F6}
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
    ? table(["Negative balance", "Type", "Amount"], b.negativeItems.map((n) => ({ cells: [n.label, n.note ?? "", n.valueText], normal: n.category === "draw" })))
    : "";
  return `<div class="keep"><h3>${esc(b.title)}</h3>
    ${svgImg(svg, `${b.title}: signed balances by account`)}
    <div class="totals"><span>Positive ${esc(b.positiveSubtotalText)}</span><span>Negative ${esc(b.negativeSubtotalText)}</span><span><b>Net ${esc(b.netText)}</b></span>${b.reportedTotalText ? `<span>QuickBooks total ${esc(b.reportedTotalText)} — ${b.reconciles ? "ties" : "does not tie"}</span>` : ""}</div>
    ${negatives}</div>`;
}

function story(n) {
  if (!n) return "";
  return `<div class="story"><div><b>What happened</b><span>${esc(n.happened)}</span></div><div><b>Why it matters</b><span>${esc(n.matters)}</span></div><div><b>Next step</b><span>${esc(n.next)}</span></div></div>`;
}

function agingBlock(a, svg, title, friendly, whoLabel) {
  if (!a) return "";
  return `<div class="keep">${title ? `<h3>${esc(title)}</h3>` : ""}${svg ? `<figure>${svgImg(svg, friendly)}</figure>` : ""}
    <div class="two"><div>${table(["Age", "Amount"], a.buckets.map((b) => ({ cells: [b.label, b.valueText] })).concat([{ total: true, cells: ["Total", a.totalText] }]))}</div>
    <div>${a.topCustomers.length ? table([whoLabel, "Amount"], a.topCustomers.map((c) => ({ cells: [c.label, c.valueText] }))) : ""}</div></div>
    <p class="small muted">${esc(a.note)}</p></div>`;
}

// opts.summary: the 2-page Client Summary (owner, 2026-10-03): cover + health/spending/priorities,
// rendered from the SAME snapshot as the full report so the two can never disagree.
export function renderHTML(report, charts, fontDir, opts = {}) {
  const S = !!opts.summary;
  const m = report.meta;
  const flag = m.isSample ? "SAMPLE DATA — fictional figures for review, not a client report"
    : m.environment === "sandbox" ? "SANDBOX DATA — generated from a QuickBooks test company" : "";
  const h2 = (title) => `<h2><span class="num">§N§</span>${esc(title)}</h2>`;
  const h2a = (letter, title) => `<h2><span class="num">${esc(letter)}</span>${esc(title)}</h2>`;
  const N = report.narratives ?? {};
  const sections = [];
  const status = report.statusSummary?.length ? report.statusSummary : (report.workSummary ?? []);
  const counts = status.map((r) => `<div><div class="n">${esc(r.valueText)}</div><div class="l">${esc(r.label)}</div></div>`).join("");

  // ——— Client summary ———

  // 1 — Month at a glance (cover: Option A of the Figma redesign)
  const kpi = Object.fromEntries((report.kpis ?? []).map((k) => [k.id, k]));
  const better = Object.fromEntries((report.sparklines?.rows ?? []).map((r) => [r.id, r.higherIsBetter]));
  const hib = (id) => better[id] ?? id !== "expenses";
  const net = kpi.net, bridge0 = report.performanceBridge;
  // Without a bookkeeping adjustment, the aside shows the month's profit margin (already
  // computed in the snapshot's trend), and says plainly when the month isn't finished.
  const heroAside = () => {
    const lastPt = report.trend?.points?.at(-1);
    const margin = lastPt && lastPt.period === m.periodKey && lastPt.marginPercent != null ? lastPt.marginPercent : null;
    if (margin == null && !m.isPartialMonth) return "";
    return `<div class="hero-r">${margin != null ? `<div class="v">${esc(margin)}% profit margin</div><div class="s">Net income as a share of revenue.</div>` : ""}${m.isPartialMonth ? `<div class="s">Month in progress: figures run through ${esc(m.balanceDateLabel.replace("Balances as of ", ""))}, so they will grow before the month closes.</div>` : ""}</div>`;
  };
  const stat = (k) => k ? `<div class="stat"><div class="lbl">${esc(k.label)}</div><div class="v${k.isNegative ? " neg" : ""}">${esc(sv(k.valueText))}</div><div class="c">${changeChip(k.comparisonText, hib(k.id))}</div></div>` : "";
  sections.push(`
<div class="band"><div><div class="firm">${esc(m.firmName)}</div>
<div class="title">${esc(m.periodLabel)} Financial Report</div>
<div class="sub">${esc(m.clientName)} · ${m.isPartialMonth ? "Month in progress · " : ""}${esc(m.balanceDateLabel)}</div></div>
${flag ? `<span class="badge">${m.isSample ? "SAMPLE DATA" : "SANDBOX DATA"}</span>` : ""}</div>
<div class="metaline">Prepared by <b>${esc(report.preparedBy || m.firmName)}</b> · Generated <b>${esc(m.generatedAtLabel)}</b> · Accounting basis <b>${esc(m.accountingBasis)}</b>${flag ? ` · ${esc(flag)}` : ""}${S ? `<br>This is your 2-page summary. The full monthly report (cash, customers, bills, every open item, statements) uses the same numbers.` : ""}</div>
${net ? `<div class="hero"><div class="hero-l"><div class="lbl">${esc(net.label)}</div><div class="big${net.isNegative ? " neg" : ""}">${esc(sv(net.valueText))}</div><div class="cmp">${changeChip(net.comparisonText, hib("net"))}</div></div>
${bridge0?.hasAdjustment ? `<div class="hero-r"><div class="s">Before the ${esc(bridge0.adjustmentsText)} bookkeeping adjustment</div><div class="v">${esc(bridge0.beforeAdjustmentsText)} operating result</div><div class="s">The adjustment is under review, not day-to-day spending.</div></div>`
  : heroAside()}</div>` : ""}
<div class="stats">${stat(kpi.revenue)}${stat(kpi.expenses)}${stat(kpi.cash)}</div>
${charts.trendArea ? `<figure class="keep"><div class="legend"><b>Trend</b><span><span class="sw" style="background:#1F8A8A"></span>Revenue</span><span><span class="sw" style="background:#C9A227"></span>Total costs</span></div>${svgImg(charts.trendArea, "Revenue and total costs by month")}<div class="caption">${esc(report.trend?.points?.slice(-13)[0]?.label ?? "")} – ${esc(report.trend?.points?.at(-1)?.label ?? "")}. The dot marks this month${m.isPartialMonth ? ", which is still in progress, so its drop is partly just fewer days" : ""}.</div></figure>` : ""}
${report.takeaways?.length ? `<h3>What matters this month</h3><ol class="tk">${report.takeaways.map((t) => `<li>${esc(t)}</li>`).join("")}</ol>` : ""}
${report.healthChecks?.length ? `<div class="strip">${report.healthChecks.map((h) => `<div class="pill ${esc(h.statusKind)}"><div class="a">${esc(h.area)}</div><div class="s">${esc(h.status)}</div></div>`).join("")}</div>` : ""}`);

  // 2 — Priorities, questions, where things stand
  const prio = report.priorities ?? [];
  const impact = report.workImpact ?? [];
  const spendItems = (report.expenses?.items ?? []).slice(0, 7);
  const spendMax = Math.max(...spendItems.map((i) => Math.abs(i.value)), 0) || 1;
  sections.push(`<div class="page">${h2("Health, spending and priorities")}
<div class="panels">
${report.healthChecks?.length ? `<div class="panel"><h3>Business health check</h3>${report.healthChecks.map((h) => `<div class="hrow"><div class="top"><span class="n">${esc(h.area)}</span><span class="tagp ${esc(h.statusKind)}">${esc(h.status)}</span></div><div class="d">${esc(h.detail)}</div></div>`).join("")}</div>` : ""}
${spendItems.length ? `<div class="panel"><h3>Where the money went</h3>${spendItems.map((i) => `<div class="bar"><div class="top"><span>${esc(i.label)}</span><b>${esc(sv(i.valueText))}</b></div><div class="track"><div class="fill${i.category === "other" ? " other" : ""}" style="width:${(100 * Math.abs(i.value) / spendMax).toFixed(1)}%"></div></div></div>`).join("")}<p class="small muted">Operating expenses ${esc(report.expenses.totalText)}; full detail in Where the money went.</p></div>` : ""}
</div>
<h3>Top priorities before next close</h3>
${prio.length ? prio.map((p, i) => `<div class="prow"><div class="no">${i + 1}</div><div class="act"><b>${esc(p.action)}</b><div>${esc(p.why)}</div></div><div class="who">${esc(p.owner)}</div><div class="when">${esc(p.timing)}</div><div class="imp">${esc(p.impact ?? "")}</div></div>`).join("") : `<p class="muted">No priority actions this month.</p>`}
${S && !report.questionsForClient?.length ? "" : `<h3>Questions for you</h3>
${report.questionsForClient?.length ? `<ul class="findings">${(S ? report.questionsForClient.slice(0, 3) : report.questionsForClient).map((q) => `<li><span class="tag r">Question</span>${esc(q)}</li>`).join("")}</ul>${S && report.questionsForClient.length > 3 ? `<p class="small muted">${report.questionsForClient.length - 3} more in the full report.</p>` : ""}` : `<p class="muted small">No open questions.</p>`}`}
${counts ? `<div class="keep"><h3>Where the bookkeeping stands</h3><div class="counts six row">${counts}</div>${S ? "" : `<p class="small muted">Every page of this report uses these same counts. Details: work log (Appendix A) and open items (Appendix B).</p>`}</div>` : ""}
${S ? "" : `<h3>Effect of this month's bookkeeping work</h3>
<p class="small">Correcting a record makes the numbers accurate; it doesn't by itself earn or recover money. Only a correction a person made and a later QuickBooks sync confirms counts as "corrected and verified".</p>
${impact.length ? `<div class="keep">${table(["Work completed and verified", "Items", "Effect on the reported figures"], impact.map((r) => ({ cells: [r.activity, String(r.count), r.effect] })), { className: "impact" })}<p class="small muted">None of this work moved or recovered actual money.</p></div>` : `<p class="muted small">No corrections were completed and verified for this period yet.</p>`}
${report.autoClearedCount ? `<p class="small muted">${esc(report.autoClearedCount)} earlier flag${report.autoClearedCount === 1 ? "" : "s"} stopped appearing on a later sync with no recorded correction. ${report.autoClearedCount === 1 ? "It is" : "They are"} not counted as work.</p>` : ""}`}</div>`);

  // 3 — Profitability: reported vs before adjustments
  const perf = [];
  const bridge = report.performanceBridge;
  // The bridge table repeated the "From sales to profit" list line for line; only its note stays.
  if (bridge?.note && !report.waterfall?.steps?.length) perf.push(`<p class="small muted">${esc(bridge.note)}</p>`);
  if (report.waterfall?.steps?.length) perf.push(moneySteps(report.waterfall, bridge?.note));
  if (charts.trendBars) perf.push(`<figure class="keep"><h3>Money in vs money out, month by month</h3>${svgImg(charts.trendBars, "Revenue and total costs by month")}<div class="caption">Teal is money in (sales); gold is money out (costs). When gold is taller than teal, that month lost money. ${esc(report.trend?.note ?? "")}</div></figure>`);
  if (report.monthOverMonth.length) perf.push(`<h3>Compared with last month</h3>${comparisonTable(report.monthOverMonth, "Last month")}`);
  if (report.ytd?.length) perf.push(`<div class="keep"><h3>Year to date</h3><p class="small muted">${esc(report.ytdLabel)}</p>${table(["", "This month", "Year to date"], report.ytd.map((r) => ({ total: r.isTotal, cells: [r.label, r.currentText, r.priorText] })))}</div>`);
  if (report.yearOverYear) perf.push(`<h3>Compared with the same month last year</h3>${comparisonTable(report.yearOverYear, "Last year")}`);
  if (perf.length) sections.push(`<div class="flow">${h2("Profitability")}${story(N.performance)}${perf.join("\n")}</div>`);

  // 4 — Where the money went (flows on from the previous page)
  const exp = report.expenses;
  if (exp) sections.push(`<div class="flow">${h2("Where the money went")}${story(N.expenses)}
    ${charts.moneyFlow ? `<figure class="keep"><h3>Every dollar in, every dollar out</h3>${svgImg(charts.moneyFlow, "Money flow from income to costs and profit")}<div class="caption">${esc(report.moneyFlow.note)}</div></figure>` : ""}
    <figure class="keep">${svgImg(charts.expenses, "Largest expense categories")}<div class="caption">Largest operating-expense categories this month${exp.items.some((i) => i.category === "other") ? "; smaller categories grouped as Other" : ""}.</div></figure>
    ${report.expenseChanges?.length ? `<div class="keep"><h3>Biggest changes from last month</h3>${table(["Category", "This month", "Last month", "Change", "% change"], report.expenseChanges.map((r) => ({ cells: [r.label, r.currentText, r.priorText, r.changeText, r.percentText] })))}</div>` : ""}
    <p class="small muted">Operating expenses total ${esc(exp.totalText)}${exp.reconciles ? ", which ties to QuickBooks" : ` (QuickBooks reports ${esc(exp.reportedTotalText ?? "n/a")})`}. Every category appears in the Profit &amp; Loss in Appendix D.</p></div>`);

  // 5 — Cash and collections
  const cash = report.cash;
  if (cash || report.receivables || report.payables) sections.push(`<div class="flow">${h2("Cash and collections")}${story(N.cash)}
    ${cash ? `<div class="two keep"><div><h3>Bank balances</h3>${table(["Account", "Balance"], cash.accounts.map((a) => ({ cells: [a.label + (a.note ? ` — ${a.note}` : ""), a.valueText] })).concat(cash.totalText ? [{ total: true, cells: ["Total bank accounts", cash.totalText] }] : []))}</div>
      <div>${report.cashTie?.length ? `<h3>Why two cash figures?</h3>${table(["", "Amount"], report.cashTie.map((r) => ({ total: r.isTotal, cells: [r.label, r.valueText] })))}` : ""}
      ${cash.cashFlow.length ? `<h3>Where cash came from and went</h3>${table(["", "Amount"], cash.cashFlow.map((r) => ({ total: r.isTotal, cells: [r.label, r.valueText] })))}` : ""}</div></div>
      <div class="note">${esc(cash.note)}</div>` : ""}
    ${report.receivables ? `<div class="keep"><h3>Customers who haven't paid (accounts receivable)</h3>${story(N.receivables)}${agingBlock(report.receivables, charts.aging, "", "Receivables by age", "Largest balances")}</div>` : ""}
    ${report.payables ? `<div class="keep"><h3>Bills the business owes (accounts payable)</h3>${story(N.payables)}${agingBlock(report.payables, charts.payables, "", "Payables by age", "Largest vendors")}</div>` : ""}</div>`);

  // 6 — Financial position
  if (report.position?.length || report.assets) sections.push(`<div class="flow">${h2("Financial position")}${story(N.position)}
    ${report.position?.length ? table(["", "Amount"], report.position.map((r) => ({ total: r.isTotal, cells: [r.label, r.valueText] }))) : ""}
    <p class="small muted">${esc(m.balanceDateLabel)}. In the charts below, bars left of the line are negative balances.</p>
    ${breakdownBlock(report.assets, charts.assets)}${breakdownBlock(report.liabilitiesAndEquity, charts.liabilities)}</div>`);

  // ——— Appendix ———
  const work = report.workCompleted ?? [];
  sections.push(`<div class="page appendix-start"><div class="appendix-banner">Appendix — supporting detail</div>${h2a("A", "Bookkeeping work log")}
    ${work.length ? work.map((w) => `<div class="work"><div class="top"><span class="t">${esc(w.title)}</span><span class="st ${esc(w.status)}">${esc(w.statusLabel)}</span></div>
      <div class="row"><b>Found:</b> ${esc(w.found)}</div>
      <div class="row"><b>What I did:</b> ${esc(w.action)}</div>
      <div class="row"><b>Effect on the numbers:</b> ${esc(w.impact)}</div>
      <div class="row small muted">${esc(w.doneBy)} · ${esc(w.doneAtLabel)} · affects ${esc(w.affectedPeriodLabel)} books · ${esc(w.amountText)}</div></div>`).join("") : `<p class="muted">No corrections were recorded for this period.</p>`}</div>`);

  const items = report.openItems ?? [];
  const groups = [["confirmed", "Confirmed issues", "Established directly from the QuickBooks data.", "v"], ["awaitingVerification", "Awaiting verification", "Work done; waiting for QuickBooks to confirm the correction.", "a"], ["awaitingClient", "Awaiting client", "Can't be finished without the client's answer.", "a"], ["possible", "Possible issues", "A pattern that often signals an error, not yet established.", "r"]];
  sections.push(`<div class="flow">${h2a("B", "Open items")}
    ${items.length ? groups.map(([kind, title, blurb, tagClass]) => {
      const list = items.filter((i) => i.kind === kind);
      if (!list.length) return "";
      return `<h3>${esc(title)} (${list.length})</h3><p class="small muted">${esc(blurb)}</p><ul class="findings">${list.map((f) => `<li><span class="amt">${esc(sv(f.amountText))}</span>
        <span class="tag ${tagClass}">${esc(f.tag)}</span><span class="t">${esc(f.title)}</span>
        ${f.detail ? `<div class="small muted">${esc(f.detail)}</div>` : ""}
        ${f.related?.length ? `<div class="small"><b>Same amount, likely the same problem:</b> ${esc(f.related.join("; "))}</div>` : ""}
        ${f.action ? `<div class="small"><b>Next step:</b> ${esc(f.action)}</div>` : ""}</li>`).join("")}</ul>`;
    }).join("") : `<p class="muted small">No open items.</p>`}</div>`);

  sections.push(`<div class="flow">${h2a("C", "Tie-out checks and notes")}
    ${table(["Check", "Result"], report.checks.map((c) => ({ cells: [`${c.label} — ${c.detail}`, c.passed ? "Passed" : "Not passed"] })), { className: "checks" })}
    <h3>Notes on data and limitations</h3>
    <ul class="small">${report.notes.map((x) => `<li>${esc(x)}</li>`).join("")}</ul></div>`);

  const cmp = report.comparativeProfitAndLoss ?? [];
  sections.push(`<div class="page">${h2a("D", "Financial statements")}
    ${cmp.length ? `<h3>Profit &amp; Loss — ${esc(m.periodLabel)} compared with last month</h3>${table(["Account", "This month", "Last month"], cmp.map((r) => ({ depth: r.depth, total: r.isTotal, cells: [r.label, r.currentText, r.priorText] })), { brackets: true })}` : ""}
    ${report.balanceSheetTable.length ? `<h3>Balance Sheet — ${esc(m.balanceDateLabel.replace("Balances as of ", ""))}</h3>${table(["Account", "Balance"], report.balanceSheetTable.map((r) => ({ depth: r.depth, total: r.isTotal, cells: [r.label, r.valueText] })), { brackets: true })}` : ""}
    ${report.cashFlowStatement?.length ? `<h3>Statement of Cash Flows — ${esc(m.periodLabel)}</h3>${table(["", "Amount"], report.cashFlowStatement.map((r) => ({ depth: r.depth, total: r.isTotal, cells: [r.label, r.valueText] })), { brackets: true })}` : ""}
    <p class="small muted">Report snapshot ${esc(m.snapshotID.slice(0, 16))} · prepared with Voice Ledger from read-only QuickBooks Online data.</p></div>`);

  let sectionNumber = 0;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>${esc(m.clientName)} — ${S ? "Client Summary" : "Monthly Financial Report"} — ${esc(m.periodLabel)}</title>
<meta name="author" content="${esc(m.firmName)}"><meta name="keywords" content="voice-ledger-snapshot:${esc(m.snapshotID)}">
<meta name="generator" content="Voice Ledger">
<style>${css(fontDir, m)}</style></head><body>
${(S ? sections.slice(0, 2) : sections).join("\n")}
</body></html>`.replace(/§N§/g, () => String(++sectionNumber));
}
