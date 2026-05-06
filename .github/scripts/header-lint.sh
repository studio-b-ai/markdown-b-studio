#!/usr/bin/env bash
# header-lint.sh — markdown-b-studio
#
# Guards the family binary-accent header extraction (PR #9).
# Runs against every tracked *.html file at repo root.
#
# Check 1 — Inline caution-stripe regression
#   Fail if a <style> block contains a CSS rule for .caution-stripe AND
#   a repeating-linear-gradient() in the same block. Header stripe CSS
#   belongs in /assets/header.css only.
#
# Check 2 — Missing /assets/header.css link
#   Fail if the file uses <div class="caution-stripe"> AND does not link
#   /assets/header.css. The header stripe requires the shared system.
#
# Check 3 — Forbidden 100%-opacity ink stripe
#   Fail if any file contains 'border-top: 2px solid var(--ink)'.
#   The new system uses 1px @ 60% alpha outlines only.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

ERRORS=0

# Directories to skip
SKIP_DIRS="drafts/ concepts/ .claude/ node_modules/ .github/"

is_skipped() {
  local file="$1"
  local rel="${file#"$REPO_ROOT/"}"
  for skip in $SKIP_DIRS; do
    if [[ "$rel" == "$skip"* ]]; then
      return 0
    fi
  done
  return 1
}

# Collect root-level HTML files
HTML_FILES=()
for f in "$REPO_ROOT"/*.html; do
  [[ -f "$f" ]] || continue
  is_skipped "$f" && continue
  HTML_FILES+=("$f")
done

if [[ ${#HTML_FILES[@]} -eq 0 ]]; then
  echo "[header-lint] No HTML files found at repo root — nothing to check."
  exit 0
fi

for file in "${HTML_FILES[@]}"; do
  rel="${file#"$REPO_ROOT/"}"

  # ------------------------------------------------------------------
  # Check 1: .caution-stripe in inline <style> with repeating-linear-gradient
  # ------------------------------------------------------------------
  check=$(python3 - "$file" <<'PYEOF'
import sys, re
content = open(sys.argv[1]).read()
blocks = re.findall(r'<style[^>]*>(.*?)</style>', content, re.DOTALL | re.IGNORECASE)
for block in blocks:
    # Strip CSS comments before selector check
    stripped = re.sub(r'/\*.*?\*/', '', block, flags=re.DOTALL)
    has_selector = bool(re.search(r'\.caution-stripe', stripped))
    has_gradient = 'repeating-linear-gradient(' in block
    if has_selector and has_gradient:
        print('FAIL')
        sys.exit(0)
print('PASS')
PYEOF
)
  if [[ "$check" == "FAIL" ]]; then
    echo "[header-lint] FAIL Check 1 ($rel): inline <style> block contains .caution-stripe selector with repeating-linear-gradient(). Header stripe CSS belongs in /assets/header.css only."
    ERRORS=$((ERRORS + 1))
  fi

  # ------------------------------------------------------------------
  # Check 2: file uses <div class="caution-stripe"> without /assets/header.css
  # ------------------------------------------------------------------
  if grep -qE 'class="[^"]*caution-stripe[^"]*"|class='"'"'[^'"'"']*caution-stripe[^'"'"']*'"'" "$file"; then
    if ! grep -q 'href="/assets/header.css"' "$file"; then
      echo "[header-lint] FAIL Check 2 ($rel): uses <div class=\"caution-stripe\"> but missing <link rel=\"stylesheet\" href=\"/assets/header.css\">."
      ERRORS=$((ERRORS + 1))
    fi
  fi

  # ------------------------------------------------------------------
  # Check 3: forbidden 100%-opacity ink stripe border
  # ------------------------------------------------------------------
  if grep -q 'border-top: 2px solid var(--ink)' "$file"; then
    echo "[header-lint] FAIL Check 3 ($rel): contains 'border-top: 2px solid var(--ink)' (retired pattern). Use 1px @ 60% alpha: 'border-top: 1px solid rgba(13, 13, 13, 0.60)'."
    ERRORS=$((ERRORS + 1))
  fi

done

if [[ $ERRORS -gt 0 ]]; then
  echo ""
  echo "[header-lint] $ERRORS check(s) failed. See messages above."
  exit 1
else
  echo "[header-lint] All checks passed (${#HTML_FILES[@]} file(s) scanned)."
  exit 0
fi
