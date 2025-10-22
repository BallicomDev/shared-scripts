#!/usr/bin/env bash
#
# Fetch Issue Data for Bug Reproduction
#
# This script fetches issue data from GitHub API or uses event inputs.
# For workflow_dispatch events, it fetches fresh data from the API.
# For other events, it uses the data passed via workflow inputs.
#
# Required environment variables:
#   EVENT_NAME - GitHub event name (workflow_dispatch, issues, etc)
#   ISSUE_NUMBER - Issue number to fetch
#   REPOSITORY - Repository in owner/repo format
#   ISSUE_TITLE - Issue title (used if not workflow_dispatch)
#   ISSUE_BODY - Issue body (used if not workflow_dispatch)
#   ISSUE_LABELS - JSON array of issue labels (used if not workflow_dispatch)
#   GH_TOKEN - GitHub token for API access
#   GITHUB_OUTPUT - Path to GitHub Actions output file
#
# Outputs (via GITHUB_OUTPUT):
#   title - Issue title
#   body - Issue body (multiline)
#   has_bug_label - true/false if bug label exists
#   has_bug_in_title - true/false if bug in title
#

set -e

# Source retry wrapper
source .ai-tools-resources/scripts/github-utils/gh-retry.sh

# Get issue data (fetch fresh if workflow_dispatch, use inputs otherwise)
if [ "$EVENT_NAME" = "workflow_dispatch" ]; then
  echo "📥 Fetching issue #${ISSUE_NUMBER} data from API..."
  issue_json=$(gh_retry api repos/${REPOSITORY}/issues/${ISSUE_NUMBER})
  title=$(echo "$issue_json" | jq -r '.title')
  body=$(echo "$issue_json" | jq -r '.body // ""')
  labels=$(echo "$issue_json" | jq -c '[.labels[].name]')
else
  echo "📋 Using issue data from event..."
  title="$ISSUE_TITLE"
  body="$ISSUE_BODY"
  labels="$ISSUE_LABELS"
fi

# Check if bug label exists
has_bug_label=$(echo "$labels" | jq 'contains(["bug"])')
if echo "$title" | grep -qi "bug"; then
  has_bug_in_title="true"
else
  has_bug_in_title="false"
fi

echo "title=$title" >> "$GITHUB_OUTPUT"
echo "has_bug_label=$has_bug_label" >> "$GITHUB_OUTPUT"
echo "has_bug_in_title=$has_bug_in_title" >> "$GITHUB_OUTPUT"

# Set body as multiline output
echo "body<<EOF" >> "$GITHUB_OUTPUT"
echo "$body" >> "$GITHUB_OUTPUT"
echo "EOF" >> "$GITHUB_OUTPUT"

# Debug output
echo "🐛 Bug label: $has_bug_label"
echo "🐛 Bug in title: $has_bug_in_title"
echo "📋 Title: $title"
echo "🏷️  Labels: $labels"
