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
    if (NEGATIVE_CATEGORIES[item.category] || item.category === "draw") return theme.negative;
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
      yAxis: valueAxis(theme),
      series: [{
        type: "bar",
        barMaxWidth: 34,
        data: b.map(function (x, i) {
          return { value: x.value, itemStyle: { color: x.category === "overdraft" ? theme.negative : theme.positive, borderRadius: [2, 2, 0, 0] },
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

  const builders = { breakdownDoughnut, breakdownDiverging, waterfall, rankedBars, trendRevenueExpenses, trendNetIncome, agingBars };

  return { themes, builders, colorFor, esc, money, NEGATIVE_CATEGORIES };
});
