#!/usr/bin/env bash
# Enforces docs/VOICE_LEDGER_SPEC.md's Architecture rule:
#   "/core never imports from /integrations directly."
#
# This is Phase 1 step 1.0's "lint rule enforcing /core ⊅ /integrations"
# (docs/phase-0/00_OVERVIEW.md Build Order). Run standalone or via
# `swift test` through Tests/ArchitectureTests/ModuleBoundaryTests.swift.
#
# Deliberately a source-text scan, not a build-graph inspection: it should
# catch the violation the moment someone types the import, before it ever
# compiles, and it should be readable by anyone without Swift tooling.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE_DIR="$DESKTOP_ROOT/Sources/Core"

FORBIDDEN_IMPORTS=(
  "IntegrationsQuickBooks"
  "IntegrationsImports"
  "Staging"
  "Voice"
  "DB"
  "Exporting"
)

violations=0

if [ ! -d "$CORE_DIR" ]; then
  echo "check-module-boundaries: Sources/Core not found at $CORE_DIR" >&2
  exit 1
fi

while IFS= read -r -d '' file; do
  for module in "${FORBIDDEN_IMPORTS[@]}"; do
    if grep -qE "^\s*import\s+${module}\b" "$file"; then
      echo "VIOLATION: $file imports $module — Core must have zero dependencies." >&2
      violations=$((violations + 1))
    fi
  done
done < <(find "$CORE_DIR" -name '*.swift' -print0)

if [ "$violations" -gt 0 ]; then
  echo "" >&2
  echo "$violations module boundary violation(s) found. See docs/VOICE_LEDGER_SPEC.md > Architecture." >&2
  exit 1
fi

echo "check-module-boundaries: OK — no forbidden imports in Sources/Core."
exit 0
