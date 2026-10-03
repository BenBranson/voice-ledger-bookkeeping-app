#!/usr/bin/env bash
# Rebuilds docs/"Moneypenny Voice Commands.pdf" from docs/VOICE_COMMANDS.md (the owner prints it).
# Run after every voice-command change. Uses the report renderer's Python (markdown + WeasyPrint).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PY="$ROOT/report-renderer/.venv/bin/python"
"$PY" - "$ROOT/docs/VOICE_COMMANDS.md" "$ROOT/docs/Moneypenny Voice Commands.pdf" "$ROOT/report-renderer/node_modules/@fontsource/inter/files" <<'PY'
import sys, markdown
from weasyprint import HTML
src, out, fonts = sys.argv[1:4]
body = markdown.markdown(open(src, encoding="utf-8").read(), extensions=["tables"])
faces = "".join(f'@font-face{{font-family:Inter;font-weight:{w};src:url("file://{fonts}/inter-latin-{w}-normal.woff")}}' for w in (400, 600, 700))
css = faces + """
@page{size:Letter;margin:0.55in 0.55in 0.6in;@bottom-right{content:"Page " counter(page) " of " counter(pages);font:7.5pt Inter;color:#56637A}}
body{font-family:Inter,Arial,sans-serif;font-size:9pt;color:#1B2A4A;line-height:1.38}
h1{font-size:19pt;margin:0 0 2pt;border-top:4pt solid #1B2A4A;padding-top:8pt}
h2{font-size:12.5pt;margin:14pt 0 5pt;padding-bottom:3pt;border-bottom:0.8pt solid #DDE3EB;break-after:avoid}
h3{font-size:10pt;margin:10pt 0 3pt;break-after:avoid}
table{width:100%;border-collapse:collapse;margin:4pt 0 8pt;font-size:8.5pt}
th{text-align:left;font-size:7.5pt;text-transform:uppercase;letter-spacing:.5pt;color:#56637A;border-bottom:1pt solid #1B2A4A;padding:3pt 4pt}
td{padding:3pt 4pt;border-bottom:.5pt solid #DDE3EB;vertical-align:top}
tr{break-inside:avoid}
td:first-child{width:46%}
strong{color:#135E5E}
hr{border:none;border-top:.6pt solid #DDE3EB;margin:10pt 0}
p{margin:3pt 0 6pt}
"""
HTML(string=f"<html><head><meta charset='utf-8'><style>{css}</style></head><body>{body}</body></html>").write_pdf(out)
print("wrote", out)
PY
