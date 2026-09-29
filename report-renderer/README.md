# Voice Ledger report renderer

Turns a Voice Ledger monthly report snapshot (JSON) into a client-ready PDF, and
supplies the shared ECharts option builders the app's interactive charts use.

```
Swift Core (MonthlyReportBuilder, ChartData)  ->  snapshot.json  (every figure computed + checked)
report-renderer/render.mjs                    ->  ECharts SSR -> static SVG (animation off)
report-renderer/template.mjs                  ->  HTML/CSS (US Letter, repeating table headers, page numbers)
report-renderer/render_pdf.py (WeasyPrint)    ->  report.pdf (layout only; network blocked)
```

Everything runs locally. No CDN, no remote fonts, no network: `render_pdf.py`
refuses any URL that isn't a local file inside the renderer or temp folder, or
an inline `data:` URI. The renderer never talks to QuickBooks and never logs
figures.

## Install (once per Mac)

```bash
brew install pango node
cd report-renderer
npm install                      # echarts 6.1 + @fontsource/inter (bundled font)
python3 -m venv .venv
.venv/bin/pip install weasyprint
```

## Run

```bash
node render.mjs <snapshot.json> <output.pdf> [--keep-html]
npm run sample                   # samples/sample-snapshot.json -> samples/sample-report.pdf
npm test                         # render, escaping, theme, and color-stability tests
```

Progress goes to stdout as JSON lines (`{"stage":"charts"}`, `html`, `pdf`,
`done`); failures go to stderr as `{"error","hint"}` with a non-zero exit.

## How the app uses it

Close Package → **Monthly Client Report → Generate Report**
(`AppState.generateMonthlyReport`):

1. Reads 13 monthly P&Ls, the period Balance Sheet and Cash Flow, A/R aging and
   account types — read-only.
2. `MonthlyReportBuilder.build` computes every figure and check; the snapshot is
   sealed with a SHA-256 `snapshotID`.
3. `MonthlyReportService.render` writes
   `~/Library/Application Support/VoiceLedger/<realm>/monthly-reports/<YYYY-MM>/<timestamp>-<id>/snapshot.json`
   and runs `node render.mjs` to produce `report.pdf` beside it.
4. The preview sheet shows that exact `report.pdf`; Save/Open use the same file.

`Scripts/build-app-bundle.sh` copies this folder (including `.venv`) to
`~/Library/Application Support/VoiceLedger/Renderer`, and the app runs it from
there — running it from inside ~/Documents would trigger macOS's
Documents-folder permission prompt (and re-prompt after every rebuild). The app
falls back to `VOICE_LEDGER_REPORT_RENDERER`, then to walking up from the app
bundle. Node is looked up in `/opt/homebrew/bin` then
`/usr/local/bin`.

## Shared charts (PDF + in-app)

`shared/vl-charts.js` is one file loaded two ways: `require()` here (print theme,
static SVG, no animation, no tooltips) and a classic `<script>` in the app's
`EChartView` (dark theme, interactive). The build script copies
`app-host/chart-host.html`, `shared/vl-charts.js`, and
`node_modules/echarts/dist/echarts.min.js` into the app's `Resources/Charts`.
The web view only reports a clicked item's stable ID back to Swift, which checks
it against the IDs it sent; everything else (legend, detail panel, postings,
Open in QBO) is native SwiftUI. Colors come from an FNV-1a hash of the account
ID, mirrored in Swift (`ChartPalette`) so legends always match. Builders only map already-computed values to chart options.

## Sample data

`samples/sample-snapshot.json` is FICTIONAL (built by
`voiceledger-devtool sample-report`); it prints "SAMPLE DATA" on every page and
is never used for a client.
