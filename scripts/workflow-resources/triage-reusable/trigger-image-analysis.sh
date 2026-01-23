#!/usr/bin/env bash
set -e

# Source retry wrapper
source .ai-tools-resources/scripts/github-utils/gh-retry.sh

REPOSITORY="${REPOSITORY:-}"
ISSUE_NUMBER="${ISSUE_NUMBER:-}"
IMAGE_URLS="${IMAGE_URLS:-}"

echo "🚀 Triggering image analysis workflow..."

# Add needed label (with retry)
gh_retry label create image-analysis-needed \
  --repo "${REPOSITORY}" \
  --color fbca04 \
  --description "Images detected, analysis needed" \
  2>/dev/null || true

gh_retry issue edit "${ISSUE_NUMBER}" \
  --repo "${REPOSITORY}" \
  --add-label image-analysis-needed

# Trigger image analyzer (with retry)
gh_retry workflow run claude-image-analyzer.yml \
  --repo "${REPOSITORY}" \
  --field issue_number="${ISSUE_NUMBER}" \
  --field image_urls="${IMAGE_URLS}" \
  --field caller_workflow="claude-triage"

echo "✅ Image analysis triggered - workflow will be re-triggered by comment event"
exit 0
