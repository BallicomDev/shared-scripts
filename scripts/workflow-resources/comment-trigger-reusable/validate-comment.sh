#!/usr/bin/env bash
#
# Comment Validation and Permission Pattern Detection
#
# This script analyzes GitHub issue comments to:
# 1. Check for @claude mentions
# 2. Detect permission escalation patterns
# 3. Set appropriate GITHUB_OUTPUT flags
#
# Required environment variables:
#   COMMENT_BODY - The comment text to analyze
#   GITHUB_OUTPUT - Path to GitHub Actions output file
#
# Outputs (via GITHUB_OUTPUT):
#   proceed - true/false whether to proceed with Claude response
#   needs_pr_tools - true/false if PR creation tools needed
#   needs_review_tools - true/false if PR review/merge tools needed
#   needs_workflow_tools - true/false if workflow management tools needed
#   needs_release_tools - true/false if release management tools needed
#   needs_write_tools - true/false if file write/commit tools needed
#   needs_image_analysis - true/false if image analysis needed
#

set -e

# Check for @claude mention
if echo "$COMMENT_BODY" | grep -q "@claude"; then
  echo "Claude was mentioned, proceeding..."
  echo "proceed=true" >> "$GITHUB_OUTPUT"
else
  echo "No @claude mention found, skipping..."
  echo "proceed=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

# ===================================================================
# PATTERN MATCHING FOR PERMISSION ESCALATION
# ===================================================================
# These patterns are case-insensitive and handle common variations
# Each pattern enables specific MCP tools for Claude to use

# -------------------------------------------------------------------
# PR CREATION PATTERNS - Enable pull request creation tools
# -------------------------------------------------------------------
if echo "$COMMENT_BODY" | grep -iE "(create|make|open|submit|raise|generate).*(PR|pull request|pull-request)" > /dev/null || \
   echo "$COMMENT_BODY" | grep -iE "(PR|pull request|pull-request).*(create|make|open|submit|raise|generate)" > /dev/null || \
   echo "$COMMENT_BODY" | grep -iE "^[[:space:]]*PR[[:space:]]*:.*" > /dev/null; then
  echo "PR creation pattern detected"
  echo "needs_pr_tools=true" >> "$GITHUB_OUTPUT"
else
  echo "needs_pr_tools=false" >> "$GITHUB_OUTPUT"
fi

# -------------------------------------------------------------------
# PR REVIEW/MERGE PATTERNS - Enable PR review and merge tools
# -------------------------------------------------------------------
if echo "$COMMENT_BODY" | grep -iE "(review|approve|merge|close).*(PR|pull request|#[0-9]+)" > /dev/null || \
   echo "$COMMENT_BODY" | grep -iE "(check|analyze|examine).*(PR|pull request|#[0-9]+)" > /dev/null; then
  echo "PR review/merge pattern detected"
  echo "needs_review_tools=true" >> "$GITHUB_OUTPUT"
else
  echo "needs_review_tools=false" >> "$GITHUB_OUTPUT"
fi

# -------------------------------------------------------------------
# WORKFLOW MANAGEMENT PATTERNS - Enable workflow/action tools
# -------------------------------------------------------------------
if echo "$COMMENT_BODY" | grep -iE "(run|trigger|execute|start|restart).*(workflow|action|CI|build|test)" > /dev/null || \
   echo "$COMMENT_BODY" | grep -iE "(workflow|action|CI|build).*(run|trigger|execute|start)" > /dev/null; then
  echo "Workflow management pattern detected"
  echo "needs_workflow_tools=true" >> "$GITHUB_OUTPUT"
else
  echo "needs_workflow_tools=false" >> "$GITHUB_OUTPUT"
fi

# -------------------------------------------------------------------
# RELEASE MANAGEMENT PATTERNS - Enable release/tag creation tools
# -------------------------------------------------------------------
if echo "$COMMENT_BODY" | grep -iE "(create|make|tag|publish).*(release|version|tag)" > /dev/null || \
   echo "$COMMENT_BODY" | grep -iE "(release|version).*(create|make|publish)" > /dev/null; then
  echo "Release management pattern detected"
  echo "needs_release_tools=true" >> "$GITHUB_OUTPUT"
else
  echo "needs_release_tools=false" >> "$GITHUB_OUTPUT"
fi

# -------------------------------------------------------------------
# FILE WRITE/COMMIT PATTERNS - Enable file modification tools
# -------------------------------------------------------------------
if echo "$COMMENT_BODY" | grep -iE "(write|create|add|modify|update|edit|fix|implement).*(file|code|script|config)" > /dev/null || \
   echo "$COMMENT_BODY" | grep -iE "(commit|push|save).*(change|update|fix)" > /dev/null; then
  echo "File modification pattern detected"
  echo "needs_write_tools=true" >> "$GITHUB_OUTPUT"
else
  echo "needs_write_tools=false" >> "$GITHUB_OUTPUT"
fi

# -------------------------------------------------------------------
# IMAGE ANALYSIS PATTERNS - Delegate to image analyzer workflow
# -------------------------------------------------------------------
if echo "$COMMENT_BODY" | grep -iE "(analyze|check|look at|examine|review).*(screenshot|image|picture)" > /dev/null || \
   echo "$COMMENT_BODY" | grep -iE "(screenshot|image|picture).*(analyze|check|examine|review)" > /dev/null || \
   echo "$COMMENT_BODY" | grep -iE "what.*in.*(screenshot|image|picture)" > /dev/null; then
  echo "Image analysis pattern detected"
  echo "needs_image_analysis=true" >> "$GITHUB_OUTPUT"
else
  echo "needs_image_analysis=false" >> "$GITHUB_OUTPUT"
fi

echo "Pattern detection complete"
