#!/usr/bin/env bash
# Regression gate (docs/MONEYPENNY_CONSISTENCY_DESIGN.md, consumer 3).
#   1. swift test
#   2. voiceledger-devtool facts against the sandbox for each baseline period
#   3. facts-diff against desktop/Regression/<realm>-<period>.json
# A difference fails the build unless --accept-baseline is passed, which
# rewrites the baseline AFTER a human has read the diff.
#   Scripts/preflight.sh [--accept-baseline] [--skip-tests]
set -euo pipefail
DESKTOP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$DESKTOP_DIR/../backend"
REALM="${VL_REGRESSION_REALM:-9341456442848752}"
AS_OF="${VL_REGRESSION_AS_OF:-2026-09-30}"
PERIODS="${VL_REGRESSION_PERIODS:-2026-07 2026-08}"
ACCEPT=0; SKIP_TESTS=0
for arg in "$@"; do case "$arg" in --accept-baseline) ACCEPT=1;; --skip-tests) SKIP_TESTS=1;; esac; done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
cd "$DESKTOP_DIR"
if [ "$SKIP_TESTS" = 0 ]; then
  echo "preflight: swift test"
  if ! swift test >"$WORK_DIR/tests.log" 2>&1; then
    cat "$WORK_DIR/tests.log" >&2
    echo "preflight: unit tests FAILED" >&2
    exit 1
  fi
  grep -E "Test run with|Executed .* tests" "$WORK_DIR/tests.log" || true
fi

if ! curl -fsS -m 5 http://localhost:3000/healthz >/dev/null 2>&1; then
  echo "preflight: backend not running on :3000 — open Voice Ledger Launcher first"; exit 1
fi
if ! swift build --product voiceledger-devtool >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  echo "preflight: devtool build FAILED" >&2
  exit 1
fi
TOK="$WORK_DIR/session-token"
(cd "$BACKEND_DIR" && arch -arm64 node_modules/.bin/tsx spike/mintDevSession.ts "$REALM" "$TOK" >/dev/null) || { echo "preflight: could not mint a dev session"; exit 1; }
export VOICE_LEDGER_BACKEND_URL=http://localhost:3000 VOICE_LEDGER_SESSION_TOKEN="$(cat "$TOK")" VOICE_LEDGER_REALM_ID="$REALM"
rm -f "$TOK"

status=0
mkdir -p Regression
for period in $PERIODS; do
  y="${period%-*}"; m="${period#*-}"; m="${m#0}"
  base="Regression/$REALM-$period.json"; cur="$WORK_DIR/$period.json"
  echo "preflight: facts $period (as of $AS_OF)"
  .build/debug/voiceledger-devtool facts "$y" "$m" --as-of "$AS_OF" --out "$cur" >/dev/null || { echo "preflight: facts failed for $period"; status=1; continue; }
  if [ ! -f "$base" ]; then
    if [ "$ACCEPT" = 1 ]; then
      cp "$cur" "$base"
      echo "preflight: initial baseline for $period ACCEPTED"
    else
      echo "preflight: missing baseline for $period — review the facts and use --accept-baseline explicitly" >&2
      status=1
    fi
    continue
  fi
  if .build/debug/voiceledger-devtool facts-diff "$base" "$cur"; then :
  else
    if [ "$ACCEPT" = 1 ]; then cp "$cur" "$base"; echo "preflight: baseline for $period ACCEPTED"; else status=1; fi
  fi
done
if [ "$status" != 0 ]; then echo "preflight: numbers changed vs. the baseline. Read the diff; if it's intended, rerun with --accept-baseline."; fi
exit $status
