#!/bin/bash
set -euo pipefail

# Auto-assign unassigned issues to default assignee
# Uses GitHub REST API for simplicity and reliability

# Environment variables (required)
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY environment variable required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN environment variable required}"

# Configuration
DEFAULT_ASSIGNEE="${DEFAULT_ASSIGNEE:-}"
DRY_RUN="${DRY_RUN:-false}"

# Validate inputs
if [[ -z "$DEFAULT_ASSIGNEE" ]]; then
  echo "⚠️  DEFAULT_ASSIGNEE not set, nothing to do"
  exit 0
fi

echo "=== Issue Assignment ==="
echo "Repository: $GITHUB_REPOSITORY"
echo "Assignee: $DEFAULT_ASSIGNEE"
echo "Dry run: $DRY_RUN"
echo ""

# Fetch all open unassigned issues
echo "Fetching open unassigned issues..."
ISSUES=$(gh api "repos/$GITHUB_REPOSITORY/issues" \
  --method GET \
  --field state=open \
  --field per_page=100 \
  --jq '[.[] | select(.assignees | length == 0) | {number: .number, title: .title}]')

ISSUE_COUNT=$(echo "$ISSUES" | jq 'length')

if [[ "$ISSUE_COUNT" == "0" ]]; then
  echo "✓ No unassigned issues found"
  exit 0
fi

echo "Found $ISSUE_COUNT unassigned issue(s)"
echo ""

# Assign each issue
ASSIGNED=0
FAILED=0

while read -r issue; do
  ISSUE_NUM=$(echo "$issue" | jq -r '.number')
  ISSUE_TITLE=$(echo "$issue" | jq -r '.title')

  echo "Issue #$ISSUE_NUM: $ISSUE_TITLE"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would assign to $DEFAULT_ASSIGNEE"
    ASSIGNED=$((ASSIGNED + 1))
  else
    # Assign using REST API
    if gh api "repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUM" \
      --method PATCH \
      --field assignees[]="$DEFAULT_ASSIGNEE" \
      --silent 2>/dev/null; then
      echo "  ✓ Assigned to $DEFAULT_ASSIGNEE"
      ASSIGNED=$((ASSIGNED + 1))
    else
      echo "  ✗ Failed to assign"
      FAILED=$((FAILED + 1))
    fi
  fi
done < <(echo "$ISSUES" | jq -c '.[]')

echo ""
echo "=== Summary ==="
echo "Total unassigned: $ISSUE_COUNT"
echo "Successfully assigned: $ASSIGNED"
if [[ $FAILED -gt 0 ]]; then
  echo "Failed: $FAILED"
fi

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi

exit 0
