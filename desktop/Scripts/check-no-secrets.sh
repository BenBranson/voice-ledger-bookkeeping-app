#!/usr/bin/env bash
# Scans the desktop app's own source (everything that ends up in the
# distributed client bundle) for secret-shaped literals.
#
# docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.3: "the QBO client secret and
# Claude API key live only in the thin backend... never transmitted to the
# desktop client." This is the "no secret in the client bundle" half of the
# Phase 1 step 1.2 exit gate, made mechanical rather than asserted.
#
# Two independent checks, because either alone misses cases:
#   1. Variable-name heuristic — a `let something...Secret/Key/Token = "..."`
#      assignment, regardless of what the literal looks like.
#   2. Known key-shape heuristic — literals matching a real provider's key
#      format, regardless of what they're assigned to.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCES_DIR="$DESKTOP_ROOT/Sources"

violations=0

while IFS= read -r -d '' file; do
  # Check 1: a secret/key/token-named constant assigned a non-empty string
  # literal. Catches "let clientSecret = "abc123"" regardless of shape.
  if grep -EnH '(let|var|static +let|static +var) +\w*(secret|apikey|api_key|clientsecret|privatekey)\w* *(:[^=]+)?= *"[^"]+"' -i "$file" >/dev/null 2>&1; then
    grep -EnH '(let|var|static +let|static +var) +\w*(secret|apikey|api_key|clientsecret|privatekey)\w* *(:[^=]+)?= *"[^"]+"' -i "$file" >&2
    violations=$((violations + 1))
  fi

  # Check 2: literals shaped like a real provider's API key format.
  if grep -EnH 'sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{35}' "$file" >/dev/null 2>&1; then
    grep -EnH 'sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{35}' "$file" >&2
    violations=$((violations + 1))
  fi
done < <(find "$SOURCES_DIR" -name '*.swift' -print0)

if [ "$violations" -gt 0 ]; then
  echo "" >&2
  echo "$violations possible secret(s) found in Sources/. Review before committing." >&2
  exit 1
fi

echo "check-no-secrets: OK — no secret-shaped literals found in Sources/."
exit 0
