#!/usr/bin/env bash
set -e

# Source retry wrapper
source .ai-tools-resources/scripts/github-utils/gh-retry.sh

ISSUE_NUMBER="${ISSUE_NUMBER:-}"
REPOSITORY="${REPOSITORY:-}"

echo "📥 Fetching issue details for #${ISSUE_NUMBER}"

# Fetch issue details using GitHub CLI
gh_retry issue view "${ISSUE_NUMBER}" \
  --repo "${REPOSITORY}" \
  --json title,body,state,labels \
  --jq '{
    title: .title,
    body: .body,
    state: .state,
    labels: [.labels[].name]
  }' > /tmp/issue-details.json

# Extract fields
ISSUE_TITLE=$(jq -r '.title' /tmp/issue-details.json)
ISSUE_BODY=$(jq -r '.body' /tmp/issue-details.json)
ISSUE_STATE=$(jq -r '.state' /tmp/issue-details.json)
ISSUE_LABELS=$(jq -c '.labels' /tmp/issue-details.json)

# Set outputs
echo "title<<EOF" >> $GITHUB_OUTPUT
echo "$ISSUE_TITLE" >> $GITHUB_OUTPUT
echo "EOF" >> $GITHUB_OUTPUT

echo "body<<EOF" >> $GITHUB_OUTPUT
echo "$ISSUE_BODY" >> $GITHUB_OUTPUT
echo "EOF" >> $GITHUB_OUTPUT

echo "state=$ISSUE_STATE" >> $GITHUB_OUTPUT
echo "labels=$ISSUE_LABELS" >> $GITHUB_OUTPUT

echo "✅ Issue details fetched successfully"
