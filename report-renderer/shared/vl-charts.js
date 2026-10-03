/*
 * Voice Ledger shared ECharts option builders.
 *
 * Loaded two ways from this ONE file:
 *   - the in-app chart host (WKWebView, classic <script>) -> window.VLCharts
 *   - the PDF renderer (Node, createRequire)              -> module.exports
 *
 * Input is the validated chart data Voice Ledger's Swift Core computes
 * (Core/ChartData.swift). Nothing here calculates a financial figure; it
 * only maps already-computed values and pre-formatted text to a chart.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.VLCharts = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  const themes = {
    dark: {
      name: "dark",
      interactive: true,
      font: "Inter, -apple-system, 'Helvetica Neue', sans-serif",
      text: "#F4F8FC",
      muted: "#9FB2C8",
      grid: "rgba(66,153,225,0.14)",
      axis: "rgba(159,178,200,0.45)",
      zero: "#9FB2C8",
      background: "transparent",
      palette: ["#29D3F2", "#2788D9", "#32C7A3", "#A67CF5", "#67E8F9", "#F2B84B", "#5B8DEF", "#7FD1AE", "#C79BF2", "#8FA8C8"],
      positive: "#32C7A3",
      negative: "#F06C8B",
      total: "#29D3F2",
      other: "#5F7390",
      connector: "rgba(159,178,200,0.55)",
      tooltipBg: "#0E1D30",
      tooltipBorder: "rgba(41,211,242,0.45)",
      fontSize: 12
    },
    print: {
      name: "print",
      interactive: false,
      font: "Inter, 'Helvetica Neue', Arial, sans-serif",
      text: "#1B2A4A",
      muted: "#56637A",
      grid: "#E3E8EF",
      axis: "#9AA5B4",
      zero: "#1B2A4A",
      background: "#FFFFFF",
      palette: ["#1B2A4A", "#1F8A8A", "#C9A227", "#3E5C85", "#7CC4C4", "#8C6D1F", "#5C6B80", "#2F6F9F", "#A9B8C9", "#4E8C6E"],
      positive: "#1F8A8A",
      negative: "#B23A48",
      total: "#1B2A4A",
      other: "#A9B2BF",
      connector: "#9AA5B4",
      tooltipBg: "#FFFFFF",
      tooltipBorder: "#9AA5B4",
      fontSize: 11
    }
  };

  const NEGATIVE_CATEGORIES = { overdraft: 1, contra: 1, creditBalance: 1, debitBalance: 1, negativeEquity: 1, deficit: 1, netLoss: 1 };

  function esc(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }

  function hash(text) {
    let h = 2166136261;
    for (let i = 0; i < text.length; i++) { h ^= text.charCodeAt(i); h = Math.imul(h, 16777619); }
    return h >>> 0;
  }

  /** Stable per-account color: the same account ID gets the same color on every screen. */
  function colorFor(item, theme) {
    if (item.category === "other") return theme.other;
    // Owner draws are normally negative: neutral slate, not error red.
    if (item.category === "draw") return theme.muted;
    if (NEGATIVE_CATEGORIES[item.category]) return theme.negative;
    if (!theme.interactive) return theme.positive;
    return theme.palette[hash(item.id || item.label) % theme.palette.length];
  }

  // Leaves room past the longest bar on each side for its value label.
  function paddedExtent(values) {
    let min = 0, max = 0;
    values.forEach(function (v) { if (v < min) min = v; if (v > max) max = v; });
    const range = (max - min) || 1;
    return {
      min: min < 0 ? min - range * 0.32 : 0,
      max: max > 0 ? max + range * 0.2 : 0,
      axisLabel: { showMinLabel: min >= 0, showMaxLabel: false }
    };
  }

  function compactMoney(value) {
    const abs = Math.abs(value);
    const sign = value < 0 ? "-" : "";
    if (abs >= 1e6) return sign + "$" + (abs / 1e6).toFixed(abs >= 1e7 ? 0 : 1) + "M";
    if (abs >= 1e3) return sign + "$" + (abs / 1e3).toFixed(abs >= 1e4 ? 0 : 1) + "K";
    return sign + "$" + abs.toFixed(0);
  }

  function base(theme, reducedMotion) {
    return {
      backgroundColor: theme.background,
      animation: theme.interactive && !reducedMotion,
      animationDuration: 350,
      animationDurationUpdate: 250,
      textStyle: { fontFamily: theme.font, color: theme.text, fontSize: theme.fontSize },
      aria: { enabled: true }
    };
  }

  function tooltip(theme, formatter, trigger) {
    if (!theme.interactive) return { show: false };
    return {
      show: true,
      trigger: trigger || "item",
      confine: true,
      renderMode: "html",
      backgroundColor: theme.tooltipBg,
      borderColor: theme.tooltipBorder,
      textStyle: { color: theme.text, fontFamily: theme.font, fontSize: 12 },
      extraCssText: "border-radius:8px;box-shadow:0 6px 18px rgba(0,0,0,0.35);",
      formatter: formatter
    };
  }

  function valueAxis(theme, extra) {
    extra = extra || {};
    return Object.assign({
      type: "value",
      splitLine: { lineStyle: { color: theme.grid } },
      axisLine: { show: false },
      axisTick: { show: false }
    }, extra, {
      axisLabel: Object.assign({ color: theme.muted, fontFamily: theme.font, formatter: compactMoney }, extra.axisLabel || {})
    });
  }

  function categoryAxis(theme, data, extra) {
    return Object.assign({
      type: "category",
      data: data,
      axisLabel: { color: theme.muted, fontFamily: theme.font, interval: 0 },
      axisLine: { lineStyle: { color: theme.axis } },
      axisTick: { show: false }
    }, extra || {});
  }

  function truncate(text, max) {
    return text.length > max ? text.slice(0, max - 1) + "…" : text;
  }

  // Doughnut of POSITIVE balances only; the center states that subtotal, and
  // the percentage denominator is the positive subtotal. Negatives and the
  // net total are shown alongside by the host (app/PDF), never folded in.
  function breakdownDoughnut(data, theme, opts) {
    opts = opts || {};
    const selectedId = opts.selectedId;
    const items = data.positiveItems;
    return Object.assign(base(theme, opts.reducedMotion), {
      tooltip: tooltip(theme, function (p) {
        const it = items[p.dataIndex];
        return "<b>" + esc(it.label) + "</b><br/>" + esc(it.valueText) +
          (it.share != null ? " · " + (it.share * 100).toFixed(1) + "% of positive balances" : "");
      }),
      title: {
        text: data.positiveSubtotalText,
        subtext: "Positive balances",
        left: "center",
        top: "center",
        itemGap: 4,
        textStyle: { color: theme.text, fontSize: theme.interactive ? 16 : 14, fontWeight: 600, fontFamily: theme.font },
        subtextStyle: { color: theme.muted, fontSize: 10, fontFamily: theme.font }
      },
      series: [{
        type: "pie",
        radius: ["58%", "82%"],
        center: ["50%", "50%"],
        avoidLabelOverlap: true,
        padAngle: 1.2,
        itemStyle: { borderRadius: 4, borderColor: theme.name === "print" ? "#FFFFFF" : "rgba(7,17,31,0.9)", borderWidth: 1 },
        label: { show: false },
        emphasis: { scale: true, scaleSize: 6 },
        selectedMode: theme.interactive ? "single" : false,
        selectedOffset: 8,
        data: items.map(function (it) {
          return {
            id: it.id,
            name: it.label,
            value: it.value,
            selected: it.id === selectedId,
            itemStyle: {
              color: colorFor(it, theme),
              opacity: selectedId && it.id !== selectedId ? 0.35 : 1
            }
          };
        })
      }]
    });
  }

  // Signed horizontal bars: positives right, negatives left of a visible
  // zero line. Used when negatives would make a doughnut misleading, and
  // always in print.
  function breakdownDiverging(data, theme, opts) {
    opts = opts || {};
    const items = data.positiveItems.concat(data.negativeItems);
    const sorted = items.slice().sort(function (a, b) { return a.value - b.value; });
    return Object.assign(base(theme, opts.reducedMotion), {
      grid: { left: 8, right: 64, top: 8, bottom: 8, containLabel: true },
      tooltip: tooltip(theme, function (p) {
        const it = sorted[p.dataIndex];
        return "<b>" + esc(it.label) + "</b><br/>" + esc(it.valueText) + (it.note ? "<br/><i>" + esc(it.note) + "</i>" : "");
      }),
      xAxis: valueAxis(theme, paddedExtent(sorted.map(function (it) { return it.value; }))),
      yAxis: categoryAxis(theme, sorted.map(function (it) { return truncate(it.label, 30); }), { axisLine: { show: false } }),
      series: [{
        type: "bar",
        barMaxWidth: 16,
        data: sorted.map(function (it) {
          return {
            id: it.id,
            value: it.value,
            itemStyle: { color: colorFor(it, theme), borderRadius: it.value < 0 ? [3, 0, 0, 3] : [0, 3, 3, 0], opacity: opts.selectedId && it.id !== opts.selectedId ? 0.35 : 1 },
            label: { show: true, position: it.value < 0 ? "left" : "right", formatter: it.valueText, color: theme.text, fontSize: 10 }
          };
        }),
        markLine: { silent: true, symbol: "none", lineStyle: { color: theme.zero, width: 1 }, label: { show: false }, data: [{ xAxis: 0 }] }
      }]
    });
  }

  // True waterfall: totals anchored at zero, changes float from the prior
  // running total, dashed connectors, visible zero line.
  function waterfall(data, theme, opts) {
    opts = opts || {};
    const steps = data.steps;
    const colors = { total: theme.total, decrease: theme.negative, increase: theme.positive };
    return Object.assign(base(theme, opts.reducedMotion), {
      grid: { left: 8, right: 16, top: 28, bottom: 8, containLabel: true },
      tooltip: tooltip(theme, function (p) {
        const s = steps[p.dataIndex];
        const kind = s.kind === "total" ? "Total" : (s.kind === "decrease" ? "Deduction" : "Addition");
        return "<b>" + esc(s.label) + "</b><br/>" + kind + ": " + esc(s.valueText);
      }),
      xAxis: categoryAxis(theme, steps.map(function (s) { return s.label; }), { axisLabel: { color: theme.muted, fontFamily: theme.font, interval: 0, width: 90, overflow: "break" } }),
      yAxis: valueAxis(theme, { scale: false }),
      series: [{
        type: "custom",
        encode: { x: 0, y: [1, 2] },
        data: steps.map(function (s, i) { return [i, s.from, s.to]; }),
        renderItem: function (params, api) {
          const i = api.value(0);
          const from = api.value(1);
          const to = api.value(2);
          const step = steps[i];
          const width = api.size([1, 0])[0] * 0.56;
          const top = api.coord([i, Math.max(from, to)]);
          const bottom = api.coord([i, Math.min(from, to)]);
          const height = Math.max(bottom[1] - top[1], 1);
          const children = [{
            type: "rect",
            shape: { x: top[0] - width / 2, y: top[1], width: width, height: height, r: 2 },
            style: { fill: colors[step.kind] }
          }, {
            type: "text",
            style: {
              text: step.valueText,
              x: top[0],
              y: to >= from ? top[1] - 4 : bottom[1] + 4,
              align: "center",
              verticalAlign: to >= from ? "bottom" : "top",
              fill: theme.text,
              fontSize: theme.interactive ? 11 : 10,
              fontWeight: 600,
              fontFamily: theme.font
            }
          }];
          if (i < steps.length - 1) {
            const next = steps[i + 1];
            const level = api.coord([i, to]);
            const nextX = api.coord([i + 1, next.kind === "total" ? next.to : next.from]);
            children.push({
              type: "line",
              shape: { x1: top[0] + width / 2, y1: level[1], x2: nextX[0] - width / 2, y2: level[1] },
              style: { stroke: theme.connector, lineDash: [3, 3], lineWidth: 1 }
            });
          }
          return { type: "group", children: children };
        }
      }, {
        type: "line",
        data: [],
        markLine: { silent: true, symbol: "none", lineStyle: { color: theme.zero, width: 1 }, label: { show: false }, data: [{ yAxis: 0 }] }
      }]
    });
  }

  function rankedBars(data, theme, opts) {
    opts = opts || {};
    const items = data.items.slice().reverse();
    return Object.assign(base(theme, opts.reducedMotion), {
      grid: { left: 8, right: 84, top: 4, bottom: 4, containLabel: true },
      tooltip: tooltip(theme, function (p) {
        const it = items[p.dataIndex];
        return "<b>" + esc(it.label) + "</b><br/>" + esc(it.valueText) +
          (it.share != null ? " · " + (it.share * 100).toFixed(1) + "% of expenses" : "");
      }),
      xAxis: valueAxis(theme, Object.assign({ show: false }, paddedExtent(items.map(function (it) { return it.value; })))),
      yAxis: categoryAxis(theme, items.map(function (it) { return truncate(it.label, 34); }), { axisLine: { show: false }, axisLabel: { color: theme.text, fontFamily: theme.font, width: 190, overflow: "truncate" } }),
      series: [{
        type: "bar",
        barMaxWidth: 18,
        data: items.map(function (it) {
          return {
            id: it.id,
            value: it.value,
            itemStyle: { color: colorFor(it, theme), borderRadius: [0, 4, 4, 0], opacity: opts.selectedId && it.id !== opts.selectedId ? 0.35 : 1 },
            label: { show: true, position: "right", formatter: it.valueText, color: theme.text, fontSize: 10, fontWeight: 600 }
          };
        })
      }]
    });
  }

  function trendRevenueExpenses(data, theme, opts) {
    opts = opts || {};
    const pts = data.points;
    return Object.assign(base(theme, opts.reducedMotion), {
      grid: { left: 8, right: 12, top: 30, bottom: 8, containLabel: true },
      legend: { top: 0, left: 0, textStyle: { color: theme.muted, fontFamily: theme.font }, itemWidth: 12, itemHeight: 8, data: ["Revenue", "Expenses"] },
      tooltip: tooltip(theme, function (params) {
        const p = pts[params[0].dataIndex];
        return "<b>" + esc(p.label) + "</b><br/>Revenue: " + money(p.revenue) + "<br/>Expenses: " + money(p.expenses);
      }, "axis"),
      xAxis: categoryAxis(theme, pts.map(function (p) { return shortMonth(p.label); }), { axisLabel: { color: theme.muted, fontFamily: theme.font, interval: pts.length > 12 ? 1 : 0 } }),
      yAxis: valueAxis(theme),
      series: [
        { name: "Revenue", type: "bar", barMaxWidth: 14, itemStyle: { color: theme.palette[1], borderRadius: [2, 2, 0, 0] }, data: pts.map(function (p) { return p.revenue; }) },
        { name: "Expenses", type: "bar", barMaxWidth: 14, itemStyle: { color: theme.name === "print" ? theme.palette[2] : theme.palette[3], borderRadius: [2, 2, 0, 0] }, data: pts.map(function (p) { return p.expenses; }) }
      ]
    });
  }

  // Report cover (2026-10-03 redesign, Option A): revenue as a soft area,
  // expenses as a dashed line, last point marked. Values come straight from
  // the snapshot; nothing is computed here.
  function trendArea(data, theme, opts) {
    opts = opts || {};
    const pts = data.points.slice(-13);
    const last = pts.length - 1;
    const dot = function (color) { return function (p, i) { return i === last ? { value: p, symbol: "circle", symbolSize: 8, itemStyle: { color: color } } : p; }; };
    return Object.assign(base(theme, opts.reducedMotion), {
      grid: { left: 4, right: 26, top: 8, bottom: 4, containLabel: true }, // room for the last month label ("Sep '26")
      xAxis: categoryAxis(theme, pts.map(function (p) { return shortMonth(p.label); }), { boundaryGap: false, axisLabel: { color: theme.muted, fontFamily: theme.font, fontSize: 9 } }),
      yAxis: valueAxis(theme),
      series: [
        { name: "Revenue", type: "line", smooth: false, showSymbol: false, lineStyle: { color: theme.palette[1], width: 2.5 },
          areaStyle: { color: theme.palette[1], opacity: 0.12 }, data: pts.map(function (p) { return p.revenue; }).map(dot(theme.palette[1])) },
        { name: "Expenses", type: "line", smooth: false, showSymbol: false, lineStyle: { color: theme.palette[2], width: 2.5, type: [6, 4] },
          data: pts.map(function (p) { return p.expenses; }).map(dot(theme.palette[2])) }
      ]
    });
  }

  function trendNetIncome(data, theme, opts) {
    opts = opts || {};
    const pts = data.points;
    return Object.assign(base(theme, opts.reducedMotion), {
      grid: { left: 8, right: 12, top: 12, bottom: 8, containLabel: true },
      tooltip: tooltip(theme, function (params) {
        const p = pts[params[0].dataIndex];
        return "<b>" + esc(p.label) + "</b><br/>Net income: " + money(p.netIncome);
      }, "axis"),
      xAxis: categoryAxis(theme, pts.map(function (p) { return shortMonth(p.label); }), { axisLabel: { color: theme.muted, fontFamily: theme.font, interval: pts.length > 12 ? 1 : 0 } }),
      yAxis: valueAxis(theme),
      series: [{
        type: "bar",
        barMaxWidth: 16,
        data: pts.map(function (p) {
          return { value: p.netIncome, itemStyle: { color: p.netIncome == null ? theme.other : (p.netIncome < 0 ? theme.negative : theme.positive), borderRadius: 2 } };
        }),
        markLine: { silent: true, symbol: "none", lineStyle: { color: theme.zero, width: 1 }, label: { show: false }, data: [{ yAxis: 0 }] }
      }]
    });
  }

  function agingBars(receivables, theme, opts) {
    opts = opts || {};
    const b = receivables.buckets;
    return Object.assign(base(theme, opts.reducedMotion), {
      grid: { left: 8, right: 12, top: 22, bottom: 8, containLabel: true },
      tooltip: tooltip(theme, function (p) { return "<b>" + esc(b[p.dataIndex].label) + "</b><br/>" + esc(b[p.dataIndex].valueText); }),
      xAxis: categoryAxis(theme, b.map(function (x) { return x.label; })),
      yAxis: valueAxis(theme, { splitNumber: 3 }),
      series: [{
        type: "bar",
        barMaxWidth: 34,
        data: b.map(function (x, i) {
          return { value: x.value, itemStyle: { color: x.category === "overdraft" ? theme.negative : x.category === "credit" ? theme.other : theme.positive, borderRadius: [2, 2, 0, 0] },
                   label: { show: true, position: "top", formatter: x.valueText, color: theme.text, fontSize: 10 } };
        })
      }]
    });
  }

  function money(v) {
    if (v == null) return "No data";
    const abs = Math.abs(v).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    return v < 0 ? "($" + abs + ")" : "$" + abs;
  }

  function shortMonth(label) {
    const parts = String(label).split(" ");
    return parts.length === 2 ? parts[0] + " '" + parts[1].slice(2) : label;
  }

  // Where the money came from and went. Node colors: inflows teal/blue,
  // costs by stable category color, profit green, a loss's shortfall red.
  function moneyFlow(data, theme, opts) {
    opts = opts || {};
    const byId = {};
    data.nodes.forEach(function (n) { byId[n.id] = n; });
    function nodeColor(n) {
      if (n.kind === "hub") return theme.total;
      if (n.kind === "profit") return theme.positive;
      if (n.kind === "loss") return theme.negative;
      if (n.kind === "source") return theme.palette[1];
      return colorFor({ id: n.id, category: n.id === "other" ? "other" : "expense" }, theme);
    }
    return Object.assign(base(theme, opts.reducedMotion), {
      tooltip: tooltip(theme, function (p) {
        if (p.dataType === "edge") {
          return esc(byId[p.data.source].label) + " → " + esc(byId[p.data.target].label) + "<br/><b>" + esc(p.data.valueText) + "</b>";
        }
        const n = byId[p.data.id];
        return "<b>" + esc(n.label) + "</b><br/>" + esc(n.valueText);
      }),
      series: [{
        type: "sankey",
        left: 200, right: 200, top: 8, bottom: 8,
        nodeWidth: 14,
        nodeGap: 12,
        layoutIterations: 0,
        draggable: false,
        emphasis: { focus: theme.interactive ? "adjacency" : "none" },
        label: {
          color: theme.text, fontFamily: theme.font, fontSize: theme.interactive ? 11 : 10,
          formatter: function (p) { const n = byId[p.data.id]; return n ? n.label + "  " + n.valueText : ""; }
        },
        lineStyle: { opacity: theme.interactive ? 0.35 : 0.4, curveness: 0.5 },
        data: data.nodes.map(function (n) {
          return { id: n.id, name: n.id, itemStyle: { color: nodeColor(n), opacity: opts.selectedId && opts.selectedId !== n.id && n.kind !== "hub" ? 0.4 : 1 },
                   label: n.kind === "hub" ? { show: false } : (n.kind === "source" || n.kind === "loss" ? { position: "left" } : undefined) };
        }),
        links: data.links.map(function (l) {
          // Each band takes the color of its non-hub end.
          return { source: l.source, target: l.target, value: l.value, valueText: l.valueText,
                   lineStyle: { color: l.target === "hub" ? "source" : "target" } };
        })
      }]
    });
  }

  // One chart, one grid per KPI row: label | sparkline | latest value.
  function sparklines(data, theme, opts) {
    opts = opts || {};
    const rows = data.rows;
    const rowH = theme.interactive ? 46 : 30;
    const option = Object.assign(base(theme, opts.reducedMotion), {
      grid: [], xAxis: [], yAxis: [], series: [], graphic: [],
      tooltip: tooltip(theme, function (p) {
        const r = rows[p.seriesIndex];
        return "<b>" + esc(r.label) + "</b> · " + esc(r.periods[p.dataIndex]) + "<br/>" + money(r.values[p.dataIndex]);
      })
    });
    rows.forEach(function (r, i) {
      const top = i * rowH + 6;
      option.grid.push({ left: 130, right: 190, top: top, height: rowH - 16 });
      option.xAxis.push({ gridIndex: i, type: "category", show: false, boundaryGap: false, data: r.periods });
      option.yAxis.push({ gridIndex: i, type: "value", show: false, scale: true });
      const last = r.values[r.values.length - 1];
      const prev = r.values.length > 1 ? r.values[r.values.length - 2] : null;
      const good = last == null || prev == null ? null : (r.higherIsBetter ? last >= prev : last <= prev);
      const color = good == null ? theme.muted : (good ? theme.positive : theme.negative);
      option.series.push({
        type: "line", xAxisIndex: i, yAxisIndex: i, data: r.values, connectNulls: false, smooth: 0.25,
        symbol: "circle", symbolSize: function (v, p) { return p.dataIndex === r.values.length - 1 ? 6 : 0; }, showSymbol: true,
        lineStyle: { width: 2, color: theme.palette[1] }, itemStyle: { color: color },
        areaStyle: { color: theme.palette[1], opacity: 0.12 }
      });
      option.graphic.push({ type: "text", left: 4, top: top + (rowH - 16) / 2 - 8, style: { text: r.label, fill: theme.text, fontFamily: theme.font, fontSize: 12, fontWeight: 600 } });
      option.graphic.push({ type: "text", right: 8, top: top + 2, style: { text: r.latestText, fill: theme.text, fontFamily: theme.font, fontSize: 13, fontWeight: 700, textAlign: "right" } });
      option.graphic.push({ type: "text", right: 8, top: top + (theme.interactive ? 20 : 15), style: { text: r.changeText, fill: color, fontFamily: theme.font, fontSize: 10, textAlign: "right" } });
    });
    return option;
  }

  // Revenue and expense bars with a profit-margin line (right axis). The
  // zoom slider is interactive-only; print shows the full range.
  function trendMixed(data, theme, opts) {
    opts = opts || {};
    const pts = data.points;
    const option = Object.assign(base(theme, opts.reducedMotion), {
      grid: { left: 8, right: 8, top: 34, bottom: theme.interactive ? 44 : 8, containLabel: true },
      legend: { top: 0, left: 0, textStyle: { color: theme.muted, fontFamily: theme.font }, itemWidth: 12, itemHeight: 8, data: ["Revenue", "Expenses", "Profit margin"] },
      tooltip: tooltip(theme, function (params) {
        const p = pts[params[0].dataIndex];
        return "<b>" + esc(p.label) + "</b><br/>Revenue: " + money(p.revenue) + "<br/>Expenses: " + money(p.expenses) +
          "<br/>Net income: " + money(p.netIncome) + "<br/>Margin: " + (p.marginPercent == null ? "n/m (no revenue)" : p.marginPercent.toFixed(1) + "%");
      }, "axis"),
      xAxis: categoryAxis(theme, pts.map(function (p) { return shortMonth(p.label); }), { axisLabel: { color: theme.muted, fontFamily: theme.font, interval: "auto" } }),
      yAxis: [valueAxis(theme), valueAxis(theme, { position: "right", splitLine: { show: false }, axisLabel: { formatter: function (v) { return v + "%"; } } })],
      series: [
        { name: "Revenue", type: "bar", barMaxWidth: 14, itemStyle: { color: theme.palette[1], borderRadius: [2, 2, 0, 0] }, data: pts.map(function (p) { return p.revenue; }) },
        { name: "Expenses", type: "bar", barMaxWidth: 14, itemStyle: { color: theme.name === "print" ? theme.palette[2] : theme.palette[3], borderRadius: [2, 2, 0, 0] }, data: pts.map(function (p) { return p.expenses; }) },
        { name: "Profit margin", type: "line", yAxisIndex: 1, connectNulls: false, symbolSize: 5, lineStyle: { width: 2, color: theme.name === "print" ? theme.palette[0] : theme.palette[5] }, itemStyle: { color: theme.name === "print" ? theme.palette[0] : theme.palette[5] }, data: pts.map(function (p) { return p.marginPercent; }) }
      ]
    });
    if (theme.interactive && pts.length > 6) {
      option.dataZoom = [
        { type: "inside", xAxisIndex: 0, startValue: Math.max(0, pts.length - 12), endValue: pts.length - 1, zoomOnMouseWheel: "shift", moveOnMouseWheel: false },
        { type: "slider", xAxisIndex: 0, height: 18, bottom: 8, startValue: Math.max(0, pts.length - 12), endValue: pts.length - 1,
          borderColor: theme.grid, fillerColor: "rgba(41,211,242,0.15)", textStyle: { color: theme.muted }, dataBackground: { lineStyle: { color: theme.axis }, areaStyle: { color: theme.grid } } }
      ];
    }
    return option;
  }

  // Posting activity by day for one account. Empty cells inside the range
  // are real zero-activity days.
  function postingCalendar(data, theme, opts) {
    opts = opts || {};
    const byDate = {};
    data.days.forEach(function (d) { byDate[d.date] = d; });
    const start = data.end.slice(0, 4) - 1 + data.end.slice(4, 8) + "01";
    const from = data.start > start ? data.start : start;
    return Object.assign(base(theme, opts.reducedMotion), {
      tooltip: tooltip(theme, function (p) {
        const d = byDate[p.value[0]];
        return "<b>" + esc(p.value[0]) + "</b><br/>" + (d ? d.count + " posting" + (d.count === 1 ? "" : "s") + " · " + esc(d.amountText) : "No postings");
      }),
      visualMap: { show: false, min: 0, max: data.maxCount, inRange: { color: theme.interactive ? ["#123047", "#29D3F2"] : ["#D8EEEE", "#1F8A8A"] } },
      calendar: {
        range: [from, data.end], top: 22, left: 34, right: 8, cellSize: ["auto", 13],
        itemStyle: { color: theme.interactive ? "#0B192A" : "#F4F7FA", borderColor: theme.interactive ? "#07111F" : "#FFFFFF", borderWidth: 2 },
        splitLine: { show: false },
        yearLabel: { show: false },
        monthLabel: { color: theme.muted, fontFamily: theme.font, fontSize: 10 },
        dayLabel: { color: theme.muted, fontFamily: theme.font, fontSize: 9, firstDay: 0, nameMap: ["S", "M", "T", "W", "T", "F", "S"] }
      },
      series: [{
        type: "heatmap", coordinateSystem: "calendar",
        data: data.days.filter(function (d) { return d.date >= from; }).map(function (d) { return { id: d.date, value: [d.date, d.count] }; })
      }]
    });
  }

  function expenseTreemap(data, theme, opts) {
    opts = opts || {};
    function map(n) {
      return { id: n.id, name: n.label, value: n.value, valueText: n.valueText,
               itemStyle: { color: colorFor({ id: n.id, category: "expense" }, theme) },
               children: n.children && n.children.length ? n.children.map(map) : undefined };
    }
    return Object.assign(base(theme, opts.reducedMotion), {
      tooltip: tooltip(theme, function (p) {
        const path = (p.treePathInfo || []).slice(1).map(function (x) { return esc(x.name); }).join(" › ");
        return "<b>" + path + "</b><br/>" + esc(p.data.valueText || "");
      }),
      series: [{
        type: "treemap", roam: false, nodeClick: false, breadcrumb: { show: false },
        left: 4, right: 4, top: 4, bottom: 4, leafDepth: 2,
        label: { show: true, color: theme.name === "print" ? "#FFFFFF" : "#07111F", fontFamily: theme.font, fontSize: 11, fontWeight: 600,
                 formatter: function (p) { return p.name + "\n" + (p.data.valueText || ""); } },
        upperLabel: { show: true, height: 18, color: theme.text, fontFamily: theme.font, fontSize: 10, fontWeight: 600 },
        itemStyle: { borderColor: theme.interactive ? "#07111F" : "#FFFFFF", borderWidth: 1, gapWidth: 1 },
        levels: [{ itemStyle: { borderWidth: 0, gapWidth: 3 } }, { itemStyle: { gapWidth: 1 }, upperLabel: { show: true } }, { colorSaturation: [0.35, 0.6] }],
        data: data.nodes.map(map)
      }]
    });
  }

  /**
   * General chart for Voice Ledger's pop-up insight cards (2026-10-02).
   * data: { type: "bar" | "stackedBar" | "hbar" | "hstackedBar" | "line", categories: [string],
   *         series: [{ name, values: [number|null], valueTexts: [string] }], ids: [string],
   *         markZero: bool }
   * Every number arrives computed by Swift; this only draws it.
   */
  function insightChart(data, theme, opts) {
    opts = opts || {};
    const horizontal = data.type === "hbar" || data.type === "hstackedBar";
    const stacked = data.type === "stackedBar" || data.type === "hstackedBar";
    const isLine = data.type === "line";
    const cats = horizontal ? data.categories.slice().reverse() : data.categories;
    const series = data.series.map(function (s, si) {
      const vals = horizontal ? s.values.slice().reverse() : s.values;
      const texts = horizontal ? (s.valueTexts || []).slice().reverse() : (s.valueTexts || []);
      const color = data.series.length === 1 ? theme.palette[0] : theme.palette[si % theme.palette.length];
      return {
        name: s.name,
        type: isLine ? "line" : "bar",
        stack: stacked ? "total" : undefined,
        smooth: isLine ? 0.25 : undefined,
        symbolSize: isLine ? 6 : undefined,
        barMaxWidth: horizontal ? 18 : 22,
        itemStyle: { color: color, borderRadius: stacked ? 0 : (horizontal ? [0, 4, 4, 0] : [3, 3, 0, 0]) },
        lineStyle: isLine ? { width: 2.5, color: color } : undefined,
        areaStyle: isLine && data.series.length === 1 ? { color: color, opacity: 0.08 } : undefined,
        label: (!stacked && data.series.length === 1 && !isLine && (horizontal || cats.length <= 8)) ? { show: true, position: horizontal ? "right" : "top", color: theme.text, fontSize: 10, fontWeight: 600,
                 formatter: function (p) { return texts[p.dataIndex] || ""; } } : undefined,
        markLine: data.markZero ? { silent: true, symbol: "none", lineStyle: { color: theme.negative, type: "dashed" }, data: [{ yAxis: 0 }], label: { show: false } } : undefined,
        data: vals.map(function (v, i) {
          return { value: v, itemStyle: (v != null && v < 0 && !isLine) ? { color: theme.negative } : undefined };
        })
      };
    });
    const valueAx = valueAxis(theme);
    const catAx = categoryAxis(theme, cats.map(function (c) { return truncate(c, horizontal ? 30 : 14); }),
      horizontal ? { axisLine: { show: false }, axisLabel: { color: theme.text, fontFamily: theme.font, width: 180, overflow: "truncate" } }
                 : { axisLabel: { color: theme.muted, fontFamily: theme.font, interval: cats.length > 13 ? 1 : 0, hideOverlap: true } });
    return Object.assign(base(theme, opts.reducedMotion), {
      grid: { left: 8, right: horizontal ? 84 : 16, top: data.series.length > 1 ? 30 : 16, bottom: 8, containLabel: true },
      legend: data.series.length > 1 ? { top: 0, left: 0, textStyle: { color: theme.muted, fontFamily: theme.font }, itemWidth: 12, itemHeight: 8 } : undefined,
      tooltip: tooltip(theme, function (params) {
        const list = Array.isArray(params) ? params : [params];
        const idx = list[0].dataIndex;
        const i = horizontal ? cats.length - 1 - idx : idx;
        return "<b>" + esc(data.categories[i]) + "</b><br/>" + data.series.map(function (s) {
          return esc(s.name) + ": " + esc((s.valueTexts && s.valueTexts[i]) || money(s.values[i]));
        }).join("<br/>");
      }, "axis"),
      xAxis: horizontal ? Object.assign({}, valueAx, { show: false }) : catAx,
      yAxis: horizontal ? catAx : valueAx,
      series: series
    });
  }

  const builders = { trendArea, insightChart, breakdownDoughnut, breakdownDiverging, waterfall, rankedBars, trendRevenueExpenses, trendNetIncome, agingBars, moneyFlow, sparklines, trendMixed, postingCalendar, expenseTreemap };

  return { themes, builders, colorFor, esc, money, NEGATIVE_CATEGORIES };
});
