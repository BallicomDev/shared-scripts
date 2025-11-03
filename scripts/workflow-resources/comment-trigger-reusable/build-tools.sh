#!/usr/bin/env bash
#
# Dynamic Tool List Builder for Comment Trigger
#
# This script builds a comma-separated list of MCP tools to grant Claude
# based on detected permission patterns from the comment validation step.
#
# Required environment variables (from validation step outputs):
#   NEEDS_PR_TOOLS - true/false
#   NEEDS_REVIEW_TOOLS - true/false
#   NEEDS_WORKFLOW_TOOLS - true/false
#   NEEDS_RELEASE_TOOLS - true/false
#   NEEDS_WRITE_TOOLS - true/false
#   NEEDS_COMMENT_EDIT - true/false
#   GITHUB_OUTPUT - Path to GitHub Actions output file
#
# Outputs (via GITHUB_OUTPUT):
#   tools - Comma-separated list of allowed MCP tool names
#

set -e

echo "========================================="
echo "PERMISSION DETECTION AND TOOL GRANTING"
echo "========================================="
echo ""

# Start with base tools that are always available
echo "📋 Base Tools (Always Enabled):"
echo "  - Issue/Comment management"
echo "  - File reading (get_file_contents)"
echo "  - Commit/ref reading"
echo "  - Read, WebFetch"

TOOLS="mcp__github__create_issue_comment,mcp__github__add_issue_comment"
TOOLS="${TOOLS},mcp__github__get_issue,mcp__github__list_issue_comments,mcp__github__update_issue"
TOOLS="${TOOLS},mcp__github__create_ref,mcp__github__delete_ref,mcp__github__get_ref,mcp__github__list_refs"
TOOLS="${TOOLS},mcp__github__get_file_contents,mcp__github__get_commit,mcp__github__list_commits"
TOOLS="${TOOLS},mcp__github__create_issue"
TOOLS="${TOOLS},Read,WebFetch"
echo ""

# Add PR creation tools if pattern detected
if [[ "${NEEDS_PR_TOOLS}" == "true" ]]; then
  echo "✅ PR Creation Pattern Detected"
  echo "  Granting PR Tools:"
  echo "    - create_pull_request"
  echo "    - update_pull_request"
  echo "    - list_pull_requests"
  echo "    - get_pull_request"
  TOOLS="${TOOLS},mcp__github__create_pull_request,mcp__github__update_pull_request"
  TOOLS="${TOOLS},mcp__github__list_pull_requests,mcp__github__get_pull_request"

  echo "  Auto-escalating to File Write/Commit/Branch Tools (required for PR creation):"
  echo "    - create_or_update_file"
  echo "    - delete_file"
  echo "    - create_tree"
  echo "    - create_commit"
  echo "    - update_ref"
  echo "    - list_branches"
  echo "    - create_branch"
  TOOLS="${TOOLS},mcp__github__create_or_update_file,mcp__github__delete_file"
  TOOLS="${TOOLS},mcp__github__create_tree,mcp__github__create_commit,mcp__github__update_ref"
  TOOLS="${TOOLS},mcp__github__list_branches,mcp__github__create_branch"
  echo ""
fi

# Add PR review/merge tools if pattern detected
if [[ "${NEEDS_REVIEW_TOOLS}" == "true" ]]; then
  echo "✅ PR Review/Merge Pattern Detected"
  echo "  Granting Review Tools:"
  echo "    - create_pull_request_review"
  echo "    - merge_pull_request"
  echo "    - close_pull_request"
  echo "    - list_pull_request_reviews"
  TOOLS="${TOOLS},mcp__github__create_pull_request_review,mcp__github__merge_pull_request"
  TOOLS="${TOOLS},mcp__github__close_pull_request,mcp__github__list_pull_request_reviews"
  echo ""
fi

# Add workflow management tools if pattern detected
if [[ "${NEEDS_WORKFLOW_TOOLS}" == "true" ]]; then
  echo "✅ Workflow Management Pattern Detected"
  echo "  Granting Workflow Tools:"
  echo "    - trigger_workflow"
  echo "    - list_workflows"
  echo "    - get_workflow_run"
  echo "    - cancel_workflow_run"
  TOOLS="${TOOLS},mcp__github__trigger_workflow,mcp__github__list_workflows"
  TOOLS="${TOOLS},mcp__github__get_workflow_run,mcp__github__cancel_workflow_run"
  echo ""
fi

# Add release management tools if pattern detected
if [[ "${NEEDS_RELEASE_TOOLS}" == "true" ]]; then
  echo "✅ Release Management Pattern Detected"
  echo "  Granting Release Tools:"
  echo "    - create_release"
  echo "    - update_release"
  echo "    - delete_release"
  echo "    - list_releases"
  TOOLS="${TOOLS},mcp__github__create_release,mcp__github__update_release"
  TOOLS="${TOOLS},mcp__github__delete_release,mcp__github__list_releases"
  echo ""
fi

# Add file write/commit tools if pattern detected
if [[ "${NEEDS_WRITE_TOOLS}" == "true" ]]; then
  echo "✅ File Write/Commit Pattern Detected"
  echo "  Granting File Modification Tools:"
  echo "    - create_or_update_file"
  echo "    - delete_file"
  echo "    - create_commit"
  echo "    - push_commits"
  TOOLS="${TOOLS},mcp__github__create_or_update_file,mcp__github__delete_file"
  TOOLS="${TOOLS},mcp__github__create_commit,mcp__github__push_commits"
  echo ""
fi

# Add comment editing tools if pattern detected
if [[ "${NEEDS_COMMENT_EDIT}" == "true" ]]; then
  echo "✅ Comment Edit Pattern Detected"
  echo "  Granting Comment Editing Tools:"
  echo "    - update_issue_comment"
  TOOLS="${TOOLS},mcp__github__update_issue_comment"
  echo ""
fi

echo "========================================="
echo "FINAL GRANTED TOOLS:"
echo "$TOOLS" | tr ',' '\n' | sed 's/^/  - /'
echo "========================================="
echo "tools=${TOOLS}" >> "$GITHUB_OUTPUT"
