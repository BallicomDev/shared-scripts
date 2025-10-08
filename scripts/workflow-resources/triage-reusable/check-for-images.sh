#!/usr/bin/env bash
set -e

REPOSITORY="${REPOSITORY:-}"
ISSUE_NUMBER="${ISSUE_NUMBER:-}"
EVENT_NAME="${EVENT_NAME:-}"
FETCH_ISSUE_BODY="${FETCH_ISSUE_BODY:-}"
INPUT_ISSUE_BODY="${INPUT_ISSUE_BODY:-}"

echo "🔍 Checking for images and image analysis status..."

# Get current issue labels
LABELS=$(gh api repos/${REPOSITORY}/issues/${ISSUE_NUMBER}/labels --jq '.[].name' | tr '\n' ' ')

# Check label status
if echo "$LABELS" | grep -q "image-analysis-complete"; then
  echo "has_complete=true" >> $GITHUB_OUTPUT
  echo "✅ Image analysis already complete"
else
  echo "has_complete=false" >> $GITHUB_OUTPUT
fi

if echo "$LABELS" | grep -q "image-analysis-in-progress"; then
  echo "in_progress=true" >> $GITHUB_OUTPUT
  echo "⏳ Image analysis in progress"
else
  echo "in_progress=false" >> $GITHUB_OUTPUT
fi

# Get issue body to check for images
if [[ "${EVENT_NAME}" == "workflow_dispatch" ]] && [[ -n "${FETCH_ISSUE_BODY}" ]]; then
  ISSUE_BODY="${FETCH_ISSUE_BODY}"
else
  ISSUE_BODY="${INPUT_ISSUE_BODY}"
fi

# Detect images using regex
# NOTE: Use [^ )] not [^\s)] - \s in bracket expressions is literal 's' not whitespace class
if echo "$ISSUE_BODY" | grep -qE '!\[.*?\]\(https?://[^ )]+\.(png|jpe?g|gif|webp|svg)\)'; then
  echo "has_images=true" >> $GITHUB_OUTPUT
  # Extract image URLs
  URLS=$(echo "$ISSUE_BODY" | grep -oE 'https?://[^ )]+\.(png|jpe?g|gif|webp|svg)' | paste -sd ',' -)
  echo "image_urls=$URLS" >> $GITHUB_OUTPUT
  echo "📸 Found images: $URLS"
else
  echo "has_images=false" >> $GITHUB_OUTPUT
  echo "image_urls=" >> $GITHUB_OUTPUT
  echo "ℹ️ No images detected in issue body"
fi
