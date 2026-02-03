#!/usr/bin/env bash
# check_claude_md_sync.sh - Check if CLAUDE.md needs updating based on source file changes
# Usage: bash inst/bin/check_claude_md_sync.sh

set -euo pipefail

CLAUDE_MD="CLAUDE.md"
SOURCE_FILES=(
    "README.md"
    "DESCRIPTION"
    ".github/workflows/R-CMD-check.yaml"
    "inst/py/environment.yml"
    "NEWS.md"
)

echo "Checking if CLAUDE.md is in sync with source documentation..."
echo ""

if [[ ! -f "$CLAUDE_MD" ]]; then
    echo "❌ CLAUDE.md not found!"
    exit 1
fi

# Get last modified time of CLAUDE.md
CLAUDE_MD_TIME=$(stat -c %Y "$CLAUDE_MD" 2>/dev/null || stat -f %m "$CLAUDE_MD" 2>/dev/null)

NEEDS_UPDATE=0
UPDATED_FILES=()

for file in "${SOURCE_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        FILE_TIME=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)

        if [[ "$FILE_TIME" -gt "$CLAUDE_MD_TIME" ]]; then
            NEEDS_UPDATE=1
            UPDATED_FILES+=("$file")
            echo "⚠️  $file was modified after CLAUDE.md"
        else
            echo "✅ $file is older than CLAUDE.md"
        fi
    else
        echo "⚠️  $file not found (may be expected)"
    fi
done

echo ""

if [[ "$NEEDS_UPDATE" -eq 1 ]]; then
    echo "🔄 CLAUDE.md may need updating. Changed files:"
    for file in "${UPDATED_FILES[@]}"; do
        echo "   - $file"
    done
    echo ""
    echo "To update CLAUDE.md:"
    echo "  1. Review changes: git diff $CLAUDE_MD ${UPDATED_FILES[*]}"
    echo "  2. Run: claude-code (or use your IDE)"
    echo "  3. Prompt: 'Review changes in ${UPDATED_FILES[*]} and update CLAUDE.md accordingly'"
    exit 1
else
    echo "✅ CLAUDE.md appears up to date with source documentation"
    exit 0
fi
