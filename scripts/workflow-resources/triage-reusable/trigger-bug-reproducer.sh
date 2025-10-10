#!/bin/bash
set -e

# Wait for label application
sleep 5

# Get issue details
ISSUE_JSON=$(gh api "repos/${REPOSITORY}/issues/${ISSUE_NUMBER}" --jq '{
  state: .state,
  labels: [.labels[].name]
}')

STATE=$(echo "$ISSUE_JSON" | jq -r '.state')

echo "Issue #${ISSUE_NUMBER} state: ${STATE}"
echo "Labels: $(echo "$ISSUE_JSON" | jq -r '.labels | join(", ")')"

# Check if issue is open
if [[ "$STATE" != "open" ]]; then
  echo "Issue not open - skipping"
  exit 0
fi

# Check for bug label
if ! echo "$ISSUE_JSON" | jq -e '.labels | contains(["bug"])' > /dev/null; then
  echo "No bug label - skipping"
  exit 0
fi

# Check for triaged label
if ! echo "$ISSUE_JSON" | jq -e '.labels | contains(["triaged"])' > /dev/null; then
  echo "Not triaged yet - skipping"
  exit 0
fi

# Trigger bug reproducer
echo "Triggering bug reproducer workflow"

gh workflow run claude-bug-reproducer.yml \
  --repo "${REPOSITORY}" \
  --field issue_number="${ISSUE_NUMBER}" \
  --field triggered_by_triage=true || echo "Trigger failed (non-fatal)"
