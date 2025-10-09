#!/usr/bin/env bash
#
# Check Branch Does Not Exist
#
# This script verifies that the bug reproduction branch does not already exist.
# This is a fail-fast check to prevent duplicate branch creation issues.
#
# Required environment variables:
#   ISSUE_NUMBER - Issue number for branch naming
#   REPOSITORY - Repository in owner/repo format
#   GH_TOKEN - GitHub token for API access
#

set -e

branch_name="claude/bug-${ISSUE_NUMBER}-reproduce"

# Fail fast if branch already exists
if gh api repos/${REPOSITORY}/git/refs/heads/${branch_name} 2>/dev/null; then
  echo "❌ ERROR: Branch ${branch_name} already exists!"
  echo "This is unexpected - the branch should not exist before bug reproduction starts."
  echo "Possible causes:"
  echo "  - Previous workflow run did not clean up properly"
  echo "  - Multiple workflows running simultaneously"
  echo "  - Manual branch creation"
  echo ""
  echo "Please investigate and delete the branch manually if needed:"
  echo "  gh api -X DELETE repos/${REPOSITORY}/git/refs/heads/${branch_name}"
  exit 1
fi

echo "✅ Branch ${branch_name} does not exist, proceeding"
