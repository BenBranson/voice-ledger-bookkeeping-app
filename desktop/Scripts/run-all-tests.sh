#!/usr/bin/env bash
# Every automated check in one command. Exit status is non-zero if ANY suite fails.
#   desktop/Scripts/run-all-tests.sh
# Suites: Swift (Core, Voice, integrations, app logic) · backend (vitest) ·
# voice-service (pytest) · build scripts (pytest). Regression baselines are
# separate: desktop/Scripts/preflight.sh (needs the backend running).
cd "$(dirname "$0")/../.."
fail=0
run() { local name="$1"; shift; printf '%-22s' "$name"; if out="$("$@" 2>&1)"; then echo "ok   $(echo "$out" | grep -E 'Test run with|Tests +[0-9]|passed' | tail -1 | tr -s ' ')"; else echo "FAILED"; echo "$out" | tail -15; fail=1; fi; }
run "Swift"            swift test --package-path desktop
run "Backend"          bash -c 'cd backend && npm test --silent'
PY=voice-service/.venv/bin/python
if [ -x "$PY" ] && "$PY" -c "import pytest" 2>/dev/null; then
  run "Voice service"  "$PY" -m pytest -q voice-service/test_main.py
  run "Build scripts"  "$PY" -m pytest -q desktop/Tests/Scripts/test_preflight.py
else
  echo "Python suites         SKIPPED — run: voice-service/.venv/bin/python -m pip install -r voice-service/requirements-dev.txt"; fail=1
fi
[ $fail = 0 ] && echo "ALL SUITES PASSED" || echo "SOMETHING FAILED"
exit $fail
