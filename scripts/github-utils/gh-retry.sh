#!/bin/bash
# Generic retry wrapper for gh CLI commands with exponential backoff
#
# Usage:
#   source gh-retry.sh
#   gh_retry api "orgs/MyOrg/repos" --paginate
#   gh_retry issue view 123 --json title,body
#
# Environment variables:
#   GH_RETRY_MAX_ATTEMPTS - Maximum retry attempts (default: 3)
#   GH_RETRY_BACKOFF_BASE - Base for exponential backoff (default: 2)

gh_retry() {
  local max_attempts="${GH_RETRY_MAX_ATTEMPTS:-3}"
  local backoff_base="${GH_RETRY_BACKOFF_BASE:-2}"
  local attempt=1

  while [[ $attempt -le $max_attempts ]]; do
    # Execute gh command with all arguments passed through
    if gh "$@"; then
      return 0
    fi

    local exit_code=$?

    # If this was the last attempt, fail
    if [[ $attempt -eq $max_attempts ]]; then
      echo "ERROR: gh command failed after $max_attempts attempts" >&2
      return $exit_code
    fi

    # Calculate exponential backoff wait time
    local wait_time=$((backoff_base ** attempt))
    echo "Attempt $attempt/$max_attempts failed (exit $exit_code), retrying in ${wait_time}s..." >&2
    sleep $wait_time

    attempt=$((attempt + 1))
  done
}
