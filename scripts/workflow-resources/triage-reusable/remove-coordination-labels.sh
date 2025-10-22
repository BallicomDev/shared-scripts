#!/usr/bin/env bash
set -e

# Source retry wrapper
source .ai-tools-resources/scripts/github-utils/gh-retry.sh

REPOSITORY="${REPOSITORY:-}"
ISSUE_NUMBER="${ISSUE_NUMBER:-}"

echo "🧹 Removing workflow coordination labels..."

# Remove triage-in-progress label
gh_retry issue edit "${ISSUE_NUMBER}" \
  --repo "${REPOSITORY}" \
  --remove-label triage-in-progress \
  2>/dev/null || true

# Remove image-analysis-complete label if present
gh_retry issue edit "${ISSUE_NUMBER}" \
  --repo "${REPOSITORY}" \
  --remove-label image-analysis-complete \
  2>/dev/null || true

echo "✅ Workflow coordination labels removed"
