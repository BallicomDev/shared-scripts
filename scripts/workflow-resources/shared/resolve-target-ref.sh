#!/bin/bash
# Resolve a target git ref from an issue-body marker.
#
# Generic and config-free: every input arrives via environment variables.
# If the issue body carries an "Affected branch: <ref>" line (bold, italic or
# plain; space or dash separator), and that ref passes static safety checks and
# exists in the repository, the ref is selected for checkout BY NAME (its
# current tip). Anything unexpected fails open to the default branch so the
# caller never errors out.
#
# Inputs (env):
#   REPOSITORY    - "owner/name" of the repo to inspect (required)
#   ISSUE_NUMBER  - issue number whose body is parsed (optional; default branch
#                   is used when absent)
#   GH_TOKEN / GITHUB_TOKEN - auth for the gh CLI (provided by the runner)
#   GITHUB_OUTPUT - step-output file (provided by the runner)
#
# Outputs (written to GITHUB_OUTPUT):
#   branch=<ref>        selected ref name
#   source=default|marker  where the ref came from
#   is_default=true|false  whether the ref is the repo default branch
#
# Sourcing this file (rather than executing it) defines the functions without
# running main(), which the unit tests rely on.

set -euo pipefail

# Extract the requested ref from issue-body text on stdin.
# Matches the first "Affected branch:" line and strips markers/backticks/space.
# awk-only (mawk-safe): no gawk extensions.
parse_marker() {
  awk '
    /^[* ]*[Aa]ffected[ -][Bb]ranch:/ {
      line=$0
      sub(/\r$/,"",line)
      sub(/^[* ]*[Aa]ffected[ -][Bb]ranch:[* ]*/,"",line)
      gsub(/`/,"",line)
      sub(/^[ \t]+/,"",line)
      sub(/[ \t]+$/,"",line)
      if (line != "") { print line; exit }
    }'
}

# Static safety check on a requested ref name. Returns 0 if safe to pass to gh
# and git, 1 otherwise. Rejects option injection, rev-range syntax, anything
# outside a conservative charset, and names git itself considers malformed.
is_safe_ref() {
  local req="$1"
  [[ "$req" != -* && "$req" != *".."* ]] || return 1
  [[ "$req" =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
  git check-ref-format "refs/heads/$req" 2>/dev/null || return 1
  return 0
}

main() {
  local default_branch branch source body req req_sha is_default

  default_branch="$(gh api "repos/$REPOSITORY" --jq '.default_branch')"
  branch="$default_branch"
  source="default"

  if [[ -n "${ISSUE_NUMBER:-}" ]]; then
    body="$(gh api "repos/$REPOSITORY/issues/$ISSUE_NUMBER" --jq '.body // ""' 2>/dev/null || echo "")"
    req="$(printf '%s\n' "$body" | parse_marker)"
    if [[ -n "$req" ]]; then
      if ! is_safe_ref "$req"; then
        echo "::warning::Requested branch '$req' failed validation; using default branch."
      else
        req_sha="$(gh api "repos/$REPOSITORY/git/ref/heads/$req" --jq '.object.sha' 2>/dev/null || echo "")"
        if [[ -n "$req_sha" ]]; then
          branch="$req"
          source="marker"
          echo "Resolved requested branch '$req'"
        else
          echo "::warning::Requested branch '$req' not found in $REPOSITORY; using default branch."
        fi
      fi
    fi
  fi

  is_default="true"
  if [[ "$branch" != "$default_branch" ]]; then
    is_default="false"
  fi

  {
    echo "branch=$branch"
    echo "source=$source"
    echo "is_default=$is_default"
  } >> "$GITHUB_OUTPUT"
  echo "Target ref: $branch (will check out current tip) [source=$source, is_default=$is_default]"
}

# Run main only when executed directly, not when sourced by the test harness.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
